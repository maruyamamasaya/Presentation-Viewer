import SwiftUI
import LibraryOrganization
import LibraryOrganizationUI
import PDFKit

@MainActor
final class CloudLibraryStore: ObservableObject {
    @Published private(set) var organization = OrganizationState<CloudDiagram>()
    @Published private(set) var classifications: [String: LibraryClassification] = [:]
    @Published private(set) var collections: [CloudCollection] = []
    @Published private(set) var hiddenDiagrams: [CloudDiagram] = []
    @Published private(set) var items: [CloudDiagram] = []
    @Published private(set) var localDiagrams: [CloudDiagram] = []
    @Published private(set) var saved: [SavedCloudFile] = []
    @Published private(set) var offline = false
    @Published private(set) var busy = false
    @Published private(set) var refreshing = false
    @Published private(set) var paginationFailed = false
    @Published private(set) var nextCursor: String?
    @Published var errorMessage: String?
    @Published var notice: String?
    private var listedQuery = ""
    private var listedScope = "all"
    private let api: any CloudLibraryAPI
    private var pendingDetails: [String: Task<CloudDetail, Error>] = [:]
    private let files: CloudFileStore
    private let enableTestSync: Bool
    private let syncConnection: AuthenticatedSyncConnection?
    private var testSync: SyncLabSession?
    init(api: any CloudLibraryAPI = MockCloudAPI(), files: CloudFileStore, enableTestSync: Bool = false, syncConnection: AuthenticatedSyncConnection? = nil) { self.syncConnection = syncConnection; self.api = api; self.files = files; self.enableTestSync = enableTestSync }
    func loadNextPage(cursor: String) async {
        while refreshing {
            do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
        }
        guard !Task.isCancelled, nextCursor == cursor else { return }
        await refresh(query: listedQuery, scope: listedScope, more: true)
    }
    func refresh(query: String = "", scope: String = "all", more: Bool = false) async {
        if more && (refreshing || nextCursor == nil) { return }
        while refreshing {
            do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
        }
        guard !Task.isCancelled else { return }
        paginationFailed = false
        refreshing = true; defer { refreshing = false }
        do {
            let append = more && query == listedQuery && scope == listedScope
            organization = try await files.organization(); classifications = try await files.classifications(); collections = try await files.collections(); hiddenDiagrams = try await files.hiddenDiagrams()
            saved = try await files.records()
            localDiagrams = try await files.cachedDiagrams()
            let result = try await api.list(query: query, cursor: append ? nextCursor : nil, scope: scope)
            guard !Task.isCancelled else { return }
            items = append ? items + result.items.filter { new in !items.contains(where: { $0.id == new.id }) } : result.items
            try? await files.cacheCatalog(items)
            offline = false
            listedQuery = query; listedScope = scope
            nextCursor = append && result.nextCursor == nextCursor ? nil : result.nextCursor; saved = try await files.records(); errorMessage = nil
        } catch {
            guard !Task.isCancelled else { return }
            if more {
                paginationFailed = true
                notice = "追加の資料を取得できませんでした。下に引いて再読み込みできます。"
                return
            }
            if !items.isEmpty {
                errorMessage = nil
                notice = "端末の一覧を表示しています。接続時に更新してください。"
                nextCursor = nil
                return
            }
            do {
                items = try await files.cachedDiagrams()
                saved = try await files.records()
                localDiagrams = items
                offline = true; nextCursor = nil
                if !items.isEmpty || !saved.isEmpty {
                    errorMessage = nil; notice = "端末にある資料を表示しています。接続時に一覧を更新してください。"
                } else { errorMessage = message(error) }
            } catch { errorMessage = message(error) }
        }
    }
    func makeSyncLab() async -> SyncLabSession {
        if enableTestSync {
            if let testSync { return testSync }
            let binding = TestLibrarySyncBinding(read: { [weak self] in
                guard let self else { throw CancellationError() }
                let value = try await self.files.testLibrarySyncSource()
                return try JSONDecoder().decode(OrganizationState<OrganizationDocument>.self, from: JSONEncoder().encode(value))
            }, apply: { [weak self] state in
                guard let self else { throw CancellationError() }
                let value = try JSONDecoder().decode(OrganizationState<CloudDiagram>.self, from: JSONEncoder().encode(state))
                try await self.files.applyTestLibrarySync(value)
                self.organization = try await self.files.organization(); self.classifications = try await self.files.classifications(); self.collections = try await self.files.collections()
            }, backup: { [weak self] in
                guard let self else { throw CancellationError() }
                return try await self.files.managementBackup()
            }, restore: { [weak self] data in
                guard let self else { throw CancellationError() }
                try await self.files.restoreManagementBackup(data)
                self.organization = try await self.files.organization(); self.classifications = try await self.files.classifications(); self.collections = try await self.files.collections()
            })
            let seed = (try? await binding.read()) ?? OrganizationState<OrganizationDocument>()
            let documents = items.map { OrganizationDocument(id: $0.id, title: $0.title, type: $0.type, version: $0.version, formats: $0.formats.map(\.rawValue), pageCount: $0.pageCount, tags: $0.tags) }
            let session = SyncLabSession(directory: await files.testLibrarySyncDirectory(), seed: seed, documents: documents, binding: binding, rateLimited: true, connection: syncConnection)
            testSync = session; return session
        }
        await reloadSaved()
        func document(_ member: CloudDiagram) -> OrganizationDocument {
            OrganizationDocument(id: member.id, title: member.title, type: member.type, version: member.version, formats: member.formats.map(\.rawValue), pageCount: member.pageCount, tags: member.tags)
        }
        var seed = OrganizationState<OrganizationDocument>()
        seed.folders = organization.folders; seed.folderOrder = organization.folderOrder; seed.assignments = organization.assignments
        seed.classifications = classifications
        seed.collections = collections.map { ReadingCollection(id: $0.id, title: $0.title, members: $0.members.map(document)) }
        var seen = Set<String>()
        let documents = (items + localDiagrams + saved.map(\.diagram) + collections.flatMap(\.members)).map(document).filter { seen.insert($0.id).inserted }
        return SyncLabSession(directory: await files.syncLabDirectory(), seed: seed, documents: documents)
    }
    func createFolder(_ name: String, parentID: UUID? = nil) async -> Bool {
        guard testSync?.blocksLibraryEdits != true else { errorMessage = "同期の確認・復元処理中です。同期画面で完了または解除してから編集してください。"; return false }
        do { organization = try await files.createFolder(name: name, parentID: parentID); await testSync?.captureLibraryChanges(); return true }
        catch { errorMessage = message(error); return false }
    }
    func moveDocuments(_ ids: Set<String>, to folderID: UUID?) async -> Bool {
        guard testSync?.blocksLibraryEdits != true else { errorMessage = "同期の確認・復元処理中です。同期画面で完了または解除してから編集してください。"; return false }
        let known = Set((items + localDiagrams + saved.map(\.diagram) + collections.flatMap(\.members)).map { $0.id.lowercased() })
        guard !ids.isEmpty, Set(ids.map { $0.lowercased() }).isSubset(of: known) else { errorMessage = CloudError.invalidResponse.errorDescription; return false }
        do { organization = try await files.moveDocuments(ids, to: folderID); await testSync?.captureLibraryChanges(); return true }
        catch { errorMessage = message(error); return false }
    }
    func removeFolder(_ id: UUID) async -> Bool {
        guard testSync?.blocksLibraryEdits != true else { errorMessage = "同期の確認・復元処理中です。同期画面で完了または解除してから編集してください。"; return false }
        do { organization = try await files.removeOrganizationFolder(id); await testSync?.captureLibraryChanges(); return true }
        catch { errorMessage = message(error); return false }
    }
    func folderPath(_ id: UUID) -> String {
        var names: [String] = []; var next: UUID? = id; var seen = Set<UUID>()
        while let current = next, seen.insert(current).inserted, let folder = organization.folders.first(where: { $0.id == current }) {
            names.insert(folder.name, at: 0); next = folder.parentID
        }
        return names.joined(separator: " / ")
    }
    func classification(_ diagram: CloudDiagram) -> LibraryClassification {
        classifications[diagram.id.lowercased()] ?? LibraryClassification(tags: LibraryClassification.normalizedTags(diagram.tags))
    }
    func setClassification(_ diagram: CloudDiagram, value: LibraryClassification) async -> Bool {
        guard testSync?.blocksLibraryEdits != true else { errorMessage = "同期の確認・復元処理中です。同期画面で完了または解除してから編集してください。"; return false }
        do {
            classifications = try await files.setClassification(diagram, value: value)
            await testSync?.captureLibraryChanges()
            errorMessage = nil
            return true
        } catch { errorMessage = message(error); return false }
    }
    func saveCollection(_ collection: CloudCollection) async -> Bool {
        guard testSync?.blocksLibraryEdits != true else { errorMessage = "同期の確認・復元処理中です。同期画面で完了または解除してから編集してください。"; return false }
        do { collections = try await files.saveCollection(collection); errorMessage = nil; await testSync?.captureLibraryChanges(); return true }
        catch { errorMessage = message(error); return false }
    }
    func removeCollection(_ id: UUID) async -> Bool {
        guard testSync?.blocksLibraryEdits != true else { errorMessage = "同期の確認・復元処理中です。同期画面で完了または解除してから編集してください。"; return false }
        do { collections = try await files.removeCollection(id); errorMessage = nil; await testSync?.captureLibraryChanges(); return true }
        catch { errorMessage = message(error); return false }
    }
    func members(of collection: CloudCollection) -> [CloudDiagram] {
        collection.resolved(using: items + saved.map(\.diagram), hidden: hiddenDiagrams)
    }
    func collectionPages(_ collection: CloudCollection) async throws -> [CloudCollectionPage] {
        var pages: [CloudCollectionPage] = []
        for diagram in members(of: collection) {
            try Task.checkCancellation()
            let available: [CloudFile]
            // When no live catalog entry exists, keep the exact saved version usable without network.
            if !items.contains(where: { $0.id.lowercased() == diagram.id.lowercased() && $0.version == diagram.version }),
               saved.contains(where: { $0.diagram.id.lowercased() == diagram.id.lowercased() && $0.diagram.version == diagram.version }) {
                available = saved.filter { $0.diagram.id.lowercased() == diagram.id.lowercased() && $0.diagram.version == diagram.version }.map(\.file)
            } else { available = try await detail(diagram).files }
            let selected = collectionReadingFiles(available)
            guard !selected.isEmpty else { throw CloudError.unavailable }
            pages += selected.map { CloudCollectionPage(diagram: diagram, file: $0) }
        }
        guard !pages.isEmpty else { throw CloudError.unavailable }
        return pages
    }
    func isHidden(_ diagram: CloudDiagram) -> Bool {
        hiddenDiagrams.contains { $0.id.lowercased() == diagram.id.lowercased() }
    }
    func setHidden(_ diagram: CloudDiagram, hidden: Bool) async -> Bool {
        guard !busy else { return false }
        busy = true; defer { busy = false }
        do {
            let updated = try await files.setHidden(diagram, hidden: hidden)
            hiddenDiagrams = updated
            errorMessage = nil
            notice = hidden ? "このiPhoneで非表示にしました" : "表示に戻しました"
            return true
        } catch { errorMessage = message(error); return false }
    }
    private func download(_ diagram: CloudDiagram, file: CloudFile) async throws -> Data {
        for attempt in 0...1 {
            do {
                let grant = try await api.access(diagram: diagram, file: file)
                if cloudDate(grant.expiresAt).map({ $0 <= Date() }) == true { throw CloudError.expiredURL }
                try grant.validate(file: file)
                return try await api.download(grant)
            } catch CloudError.expiredURL { if attempt == 1 { throw CloudError.expiredURL } }
        }
        throw CloudError.expiredURL
    }
    func preferredLocalVersion(_ diagram: CloudDiagram) -> CloudDiagram {
        (localDiagrams + saved.map(\.diagram)).filter {
            $0.id.lowercased() == diagram.id.lowercased() && $0.version <= diagram.version
        }.max { $0.version < $1.version } ?? diagram
    }
    func availableUpdate(_ diagram: CloudDiagram) -> CloudDiagram? {
        guard !offline else { return nil }
        return items.filter { $0.id.lowercased() == diagram.id.lowercased() && $0.version > diagram.version }
            .max { $0.version < $1.version }
    }
    func localReadingFiles(_ diagram: CloudDiagram) async throws -> [CloudFile] {
        if let detail = try await files.cachedDetail(diagram) { return try await files.localFiles(detail) }
        return saved.filter { $0.diagram.id.lowercased() == diagram.id.lowercased() && $0.diagram.version == diagram.version }.map(\.file)
    }
    func reloadSaved() async {
        do {
            if items.isEmpty { items = (try? await files.cachedCatalog()) ?? [] }
            organization = try await files.organization(); classifications = try await files.classifications(); collections = try await files.collections(); hiddenDiagrams = try await files.hiddenDiagrams(); saved = try await files.records(); localDiagrams = try await files.cachedDiagrams(); if items.isEmpty { items = try await files.cachedDiagrams(); offline = true } } catch { errorMessage = message(error) }
    }
    func detail(_ diagram: CloudDiagram) async throws -> CloudDetail {
        try diagram.validate()
        if let detail = try await files.cachedDetail(diagram) {
            if offline {
                let local = try await files.localFiles(detail)
                return CloudDetail(id: detail.id, title: detail.title, type: detail.type, version: detail.version,
                                   formats: detail.formats, pageCount: detail.pageCount, tags: detail.tags, files: local)
            }
            return detail
        }
        let key = "\(diagram.id)-\(diagram.version)"
        if let task = pendingDetails[key] { return try await task.value }
        let task = Task { [api, files] in
            let detail = try await api.detail(id: diagram.id, version: diagram.version)
            try detail.validate()
            guard detail.id == diagram.id, detail.version == diagram.version,
                  detail.type == diagram.type, detail.pageCount == diagram.pageCount,
                  detail.formats == diagram.formats else { throw CloudError.invalidResponse }
            try await files.cacheDetail(detail)
            return detail
        }
        pendingDetails[key] = task
        defer { pendingDetails[key] = nil }
        return try await task.value
    }
    private func localOrDownload(_ diagram: CloudDiagram, file: CloudFile) async throws -> URL {
        let record = SavedCloudFile(diagram: diagram, file: file)
        if let url = try await files.localURL(record) { return url }
        return try await files.cacheData(download(diagram, file: file), record: record)
    }
    func open(_ diagram: CloudDiagram, file: CloudFile, persist: Bool) async -> OpenedDocument? {
        guard !busy else { return nil }
        busy = true; notice = nil; defer { busy = false }
        do {
            try file.validate(for: diagram)
            let record = SavedCloudFile(diagram: diagram, file: file)
            let local = try await localOrDownload(diagram, file: file)
            let url: URL
            if persist {
                try await files.save(Data(contentsOf: local), record: record); url = try await files.open(record)
                saved = try await files.records(); notice = "アプリ内に保存しました。オフラインで開けます。"
            } else { url = local }
            return opened(url, record: record)
        } catch { errorMessage = message(error); return nil }
    }
    func openSaved(_ record: SavedCloudFile) async -> OpenedDocument? {
        do { return opened(try await files.open(record), record: record) }
        catch { errorMessage = message(error); return nil }
    }
    func clearCache() async {
        guard !busy else { return }
        do { try await files.clearCache(); localDiagrams = []; if offline { items = [] }; notice = "一時キャッシュを削除しました。保存済み資料は残っています。" }
        catch { errorMessage = message(error) }
    }
    func clearLocalDocuments() async {
        guard !busy else { return }
        busy = true; defer { busy = false }
        do {
            try await files.clearLocalDocuments()
            saved = []; localDiagrams = []; if offline { items = [] }
            errorMessage = nil; notice = "端末の資料を削除しました。S3の資料は残っています。"
        } catch { await reloadSaved(); errorMessage = message(error) }
    }
    func saveOpened(_ document: OpenedDocument, record: SavedCloudFile) async -> Bool {
        guard !busy else { return false }
        busy = true; defer { busy = false }
        do {
            try await files.save(Data(contentsOf: document.url), record: record)
            saved = try await files.records(); notice = "保存しました"
            return true
        } catch { errorMessage = message(error); return false }
    }
    func isSaved(_ record: SavedCloudFile) -> Bool {
        saved.contains { $0.id == record.id && $0.file == record.file }
    }
    func cachedSlideThumbnail(_ diagram: CloudDiagram, file: CloudFile) async -> UIImage? {
        guard let url = try? await files.localURL(SavedCloudFile(diagram: diagram, file: file)) else { return nil }
        return UIImage(contentsOfFile: url.path)
    }

    func thumbnail(_ diagram: CloudDiagram, offline: Bool) async -> UIImage? {
        do {
            let url: URL
            if offline {
                let available = try await localReadingFiles(diagram)
                guard let file = preferredCloudFile(available),
                      let local = try await files.localURL(SavedCloudFile(diagram: diagram, file: file)) else { return nil }
                url = local
            } else {
                let detail = try await detail(diagram)
                guard let file = detail.files.first(where: { $0.format == .png && $0.page == 1 }) ?? detail.files.first(where: { $0.format == .pdf }) else { return nil }
                url = try await localOrDownload(diagram, file: file)
            }
            if url.pathExtension == "pdf" {
                return PDFDocument(url: url)?.page(at: 0)?.thumbnail(of: CGSize(width: 420, height: 236), for: .mediaBox)
            }
            return UIImage(contentsOfFile: url.path)
        } catch { return nil }
    }
    private func opened(_ url: URL, record: SavedCloudFile) -> OpenedDocument {
        OpenedDocument(url: url, name: record.diagram.title.replacingOccurrences(of: "（モック）", with: ""), format: record.file.format.documentFormat, accessURL: url, scoped: false)
    }
    private func message(_ error: Error) -> String { (error as? CloudError)?.errorDescription ?? "処理を完了できませんでした。保存領域と接続を確認してください。" }
}

func preferredCloudFile(_ files: [CloudFile]) -> CloudFile? {
    for format in [CloudFormat.pdf, .png, .pptx] {
        if let file = files.filter({ $0.format == format }).sorted(by: { $0.page < $1.page }).first { return file }
    }
    return nil
}

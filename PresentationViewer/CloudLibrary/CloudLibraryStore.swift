import SwiftUI
import PDFKit

@MainActor
final class CloudLibraryStore: ObservableObject {
    @Published private(set) var items: [CloudDiagram] = []
    @Published private(set) var saved: [SavedCloudFile] = []
    @Published private(set) var busy = false
    @Published private(set) var nextCursor: String?
    @Published var errorMessage: String?
    @Published var notice: String?
    private var listedQuery = ""
    private var listedScope = "all"
    private let api: any CloudLibraryAPI
    private let files: CloudFileStore
    init(api: any CloudLibraryAPI = MockCloudAPI(), files: CloudFileStore) { self.api = api; self.files = files }
    func refresh(query: String = "", scope: String = "all", more: Bool = false) async {
        while busy {
            do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
        }
        guard !Task.isCancelled else { return }
        busy = true; defer { busy = false }
        do {
            let append = more && query == listedQuery && scope == listedScope
            let result = try await api.list(query: query, cursor: append ? nextCursor : nil, scope: scope)
            guard !Task.isCancelled else { return }
            items = append ? items + result.items.filter { new in !items.contains(where: { $0.id == new.id }) } : result.items
            listedQuery = query; listedScope = scope
            nextCursor = result.nextCursor; saved = try await files.records(); errorMessage = nil
        } catch { if !Task.isCancelled { errorMessage = message(error) } }
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
    func reloadSaved() async {
        do { saved = try await files.records() } catch { errorMessage = message(error) }
    }
    func detail(_ diagram: CloudDiagram) async throws -> CloudDetail { try await api.detail(id: diagram.id, version: diagram.version) }
    func open(_ diagram: CloudDiagram, file: CloudFile, persist: Bool) async -> OpenedDocument? {
        guard !busy else { return nil }
        busy = true; notice = nil; defer { busy = false }
        do {
            try file.validate(for: diagram)
            let record = SavedCloudFile(diagram: diagram, file: file)
            let bytes = try await download(diagram, file: file)
            let url: URL
            if persist {
                try await files.save(bytes, record: record); url = try await files.open(record)
                saved = try await files.records(); notice = "アプリ内に保存しました。オフラインで開けます。"
            } else { url = try await files.cacheData(bytes, record: record) }
            return opened(url, record: record)
        } catch { errorMessage = message(error); return nil }
    }
    func openSaved(_ record: SavedCloudFile) async -> OpenedDocument? {
        do { return opened(try await files.open(record), record: record) }
        catch { errorMessage = message(error); return nil }
    }
    func clearCache() async {
        do { try await files.clearCache(); notice = "一時キャッシュを削除しました。保存済み資料は残っています。" }
        catch { errorMessage = message(error) }
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
    func thumbnail(_ diagram: CloudDiagram, offline: Bool) async -> UIImage? {
        do {
            let url: URL
            if offline {
                let candidates = saved.filter { $0.diagram.id == diagram.id && $0.diagram.version == diagram.version }
                guard let file = preferredCloudFile(candidates.map(\.file)), let record = candidates.first(where: { $0.file == file }) else { return nil }
                url = try await files.open(record)
            } else {
                let detail = try await api.detail(id: diagram.id, version: diagram.version)
                guard let file = detail.files.first(where: { $0.format == .png && $0.page == 1 }) ?? detail.files.first(where: { $0.format == .pdf }) else { return nil }
                url = try await files.cacheData(try await download(diagram, file: file), record: SavedCloudFile(diagram: diagram, file: file))
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

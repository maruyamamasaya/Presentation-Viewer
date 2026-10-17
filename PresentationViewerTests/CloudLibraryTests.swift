import XCTest
import PDFKit
import UIKit
import LibraryOrganization
@testable import PresentationViewer

final class CloudLibraryTests: XCTestCase {
    @MainActor func testIOSOIDCProvidesBearerForHTTPSBootstrapAndByteBoundedBatches() async throws {
        let config = CloudConnection(issuer: URL(string:"https://cognito-idp.ap-northeast-1.amazonaws.com/ap-northeast-1_Test")!,domain:URL(string:"https://test.auth.ap-northeast-1.amazoncognito.com")!,clientID:"isolated-sync-test",api:URL(string:"https://api.example")!,artifactHosts:["assets.example"],redirect:"presentationviewer://oauth/callback")
        let auth = try CloudOIDC(config:config,readTokens:{ CloudTokens(access:"test-bearer",refresh:"unused",expires:Date().addingTimeInterval(3600),subject:"test-owner") },readCachedNamespace:{ nil })
        let library = UUID()
        OIDCTestProtocol.respond = { request in
            XCTAssertEqual(request.url?.absoluteString,"https://api.example/v1/organization/bootstrap")
            XCTAssertEqual(request.value(forHTTPHeaderField:"Authorization"),"Bearer test-bearer")
            return try JSONSerialization.data(withJSONObject:["libraryID":library.uuidString,"protocolVersion":1,"limit":5,"windowSeconds":3600,"maxOperations":50,"maxBodyBytes":4096])
        }
        defer { OIDCTestProtocol.respond = nil }
        let settings = URLSessionConfiguration.ephemeral; settings.protocolClasses = [OIDCTestProtocol.self]
        let connection = try auth.organizationSyncConnection(transport:URLSession(configuration:settings))
        let bootstrap = try await connection.bootstrap()
        let transport = try AuthenticatedOrganizationTransport<String>(connection:connection,bootstrap:bootstrap,attemptID:UUID())
        let operations = (0..<51).map { SyncOperation<String>(key:"tag/\($0)",expectedRevision:0,value:.tag(String(repeating:"日本語",count:60))) }
        let batch = try transport.batch(libraryID:library,operations:operations)
        XCTAssertGreaterThan(batch.count,0); XCTAssertLessThan(batch.count,50)
        let bytes = try JSONEncoder().encode(LimitedSyncRequest(action:"sync",libraryID:library,attemptID:transport.attemptID,operations:batch))
        XCTAssertLessThanOrEqual(bytes.count,4096)
    }
    @MainActor func testHTTPSConnectionOnlyAttachesToIsolatedTestLibrary() async throws {
        let (files, root) = try temporaryStore(); defer { try? FileManager.default.removeItem(at: root) }
        let connection = try AuthenticatedSyncConnection(baseURL: URL(string: "https://api.example")!, issuer: "https://issuer.example", subject: "test-owner") { _ in throw OrganizationConnectionError.authentication }
        let ordinary = CloudLibraryStore(files: files, syncConnection: connection)
        let ordinarySession = await ordinary.makeSyncLab(); XCTAssertNil(ordinarySession.httpsConnection)
        let isolated = CloudLibraryStore(files: files, enableTestSync: true, syncConnection: connection)
        let isolatedSession = await isolated.makeSyncLab(); XCTAssertEqual(isolatedSession.httpsConnection?.identityKey, connection.identityKey)
        XCTAssertFalse(isolatedSession.connected)
    }
    @MainActor func testSyncFactoryPreservesLiveOrganizationAndSavedFiles() async throws {
        let (files, root) = try temporaryStore(); defer { try? FileManager.default.removeItem(at: root) }
        let store = CloudLibraryStore(api: MockCloudAPI(), files: files); await store.refresh()
        let diagram = try XCTUnwrap(store.items.first { CloudLibraryKind.illustrations.contains($0) && ($0.formats.contains(.png) || $0.formats.contains(.pdf)) })
        let classified = await store.setClassification(diagram, value: LibraryClassification(group: .work, tags: ["保持するタグ"])); XCTAssertTrue(classified)
        let created = await store.createFolder("保持するフォルダ"); XCTAssertTrue(created)
        let folder = try XCTUnwrap(store.organization.folders.first)
        let moved = await store.moveDocuments([diagram.id], to: folder.id); XCTAssertTrue(moved)
        let collection = CloudCollection(id: UUID(), title: "保持するまとめ", members: [diagram])
        let collected = await store.saveCollection(collection); XCTAssertTrue(collected)
        let urls = ["organization.json", "classifications.json", "collections.json"].map { root.appendingPathComponent("saved/" + $0) }
        let before = try urls.map { try Data(contentsOf: $0) }
        let session = await store.makeSyncLab()
        XCTAssertFalse(session.connected)
        XCTAssertEqual(session.state.folders.first?.id, folder.id)
        XCTAssertEqual(session.state.collections.first?.id, collection.id)
        XCTAssertEqual(session.state.collections.first?.members.first?.id, diagram.id.lowercased())
        XCTAssertEqual(session.state.classifications[diagram.id.lowercased()]?.tags, ["保持するタグ"])
        session.clear()
        XCTAssertEqual(try urls.map { try Data(contentsOf: $0) }, before)
        XCTAssertEqual(store.collections, [collection])
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("saved/sync-lab/checkpoint.json").path))
    }
    @MainActor func testFoldersBatchMoveRestoreAndKeepLegacyMetadata() async throws {
        let (files, root) = try temporaryStore(); defer { try? FileManager.default.removeItem(at: root) }
        let store = CloudLibraryStore(api: MockCloudAPI(), files: files)
        await store.refresh()
        let first = try XCTUnwrap(store.items.first)
        let second = CloudDiagram(id: UUID().uuidString.lowercased(), title: "保存済み図", type: "illustration", version: 1, formats: [.pdf], pageCount: 1, tags: [])
        let sample = try XCTUnwrap(store.items.first { CloudLibraryKind.illustrations.contains($0) && $0.formats.contains(.pdf) })
        let collection = CloudCollection(id: UUID(), title: "従来のまとめ", members: [sample])
        let classification = LibraryClassification(group: .work, tags: ["既存タグ"])
        _ = try await files.setClassification(first, value: classification)
        _ = try await files.saveCollection(collection)
        let detail = try await MockCloudAPI().detail(id: sample.id, version: sample.version)
        let pdf = try XCTUnwrap(detail.files.first { $0.format == .pdf })
        let grant = try await MockCloudAPI().access(diagram: sample, file: pdf)
        let bytes = try await MockCloudAPI().download(grant)
        try await files.save(bytes, record: SavedCloudFile(diagram: second, file: pdf))
        await store.reloadSaved()
        let created = await store.createFolder("親"); XCTAssertTrue(created)
        let parent = try XCTUnwrap(store.organization.folders.first)
        let childCreated = await store.createFolder("子", parentID: parent.id); XCTAssertTrue(childCreated)
        let child = try XCTUnwrap(store.organization.folders.last)
        let moved = await store.moveDocuments([first.id, second.id], to: child.id); XCTAssertTrue(moved)
        let restored = CloudLibraryStore(api: OfflineAPI(), files: files)
        await restored.reloadSaved()
        XCTAssertEqual(restored.organization.assignments.count, 2)
        XCTAssertEqual(restored.folderPath(child.id), "親 / 子")
        XCTAssertEqual(restored.classifications[first.id.lowercased()], classification)
        XCTAssertEqual(restored.collections, [collection])
        XCTAssertEqual(restored.saved.count, 1)
        let unfiled = await restored.moveDocuments([first.id, second.id], to: nil); XCTAssertTrue(unfiled)
        XCTAssertTrue(restored.organization.assignments.isEmpty)
        let movedAgain = await restored.moveDocuments([first.id], to: child.id); XCTAssertTrue(movedAgain)
        let removed = await restored.removeFolder(parent.id); XCTAssertTrue(removed)
        XCTAssertTrue(restored.organization.folders.isEmpty)
        XCTAssertTrue(restored.organization.assignments.isEmpty)
        XCTAssertEqual(restored.collections, [collection]); XCTAssertEqual(restored.saved.count, 1)
        let other = try CloudFileStore(saved: root.appendingPathComponent("other"), cache: root.appendingPathComponent("other-cache"))
        let isolated = try await other.organization(); XCTAssertTrue(isolated.folders.isEmpty)
    }
    @MainActor func testFolderFailureLeavesAssignmentsAndLegacyFilesUntouched() async throws {
        let (files, root) = try temporaryStore(); defer { try? FileManager.default.removeItem(at: root) }
        let store = CloudLibraryStore(api: MockCloudAPI(), files: files); await store.refresh()
        let created = await store.createFolder("保持"); XCTAssertTrue(created)
        let first = try XCTUnwrap(store.items.first)
        let id = try XCTUnwrap(store.organization.folders.first?.id)
        let moved = await store.moveDocuments([first.id], to: id); XCTAssertTrue(moved)
        let before = store.organization.assignments
        let rejected = await store.moveDocuments([UUID().uuidString], to: id); XCTAssertFalse(rejected)
        let invalid = await store.moveDocuments([first.id], to: UUID()); XCTAssertFalse(invalid)
        let url = root.appendingPathComponent("saved/organization.json")
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        let failed = await store.moveDocuments([first.id], to: nil); XCTAssertFalse(failed)
        XCTAssertEqual(store.organization.assignments, before)
    }
    @MainActor
    func testCatalogRestoresWithoutDocumentDownloadAndSurvivesRefreshFailure() async throws {
        let (files, root) = try temporaryStore(); defer { try? FileManager.default.removeItem(at: root) }
        let api = CacheCountingAPI()
        let online = CloudLibraryStore(api: api, files: files)
        await online.refresh()
        let expected = online.items
        XCTAssertFalse(expected.isEmpty)
        let restored = CloudLibraryStore(api: OfflineAPI(), files: files)
        await restored.reloadSaved()
        XCTAssertEqual(restored.items, expected)
        await restored.refresh()
        XCTAssertEqual(restored.items, expected)
        XCTAssertNil(restored.errorMessage)
        let counts = await api.counts()
        XCTAssertEqual(counts, [0, 0, 0])
    }

    func testCacheBudgetEvictsOldestAcrossNamespacesAndKeepsSavedFiles() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let shared = root.appendingPathComponent("cache")
        let files = try CloudFileStore(saved: root.appendingPathComponent("saved"), cache: shared.appendingPathComponent("owner"), cacheLimit: 4096, cacheRoot: shared)
        let other = shared.appendingPathComponent("other")
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        let old = other.appendingPathComponent("old.bin")
        try Data(repeating: 0, count: 4000).write(to: old)
        let saved = root.appendingPathComponent("saved/keep.bin")
        try Data(repeating: 1, count: 50).write(to: saved)
        let items = try await MockCloudAPI().list(query: "", cursor: nil).items
        try await files.cacheCatalog(items)
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: saved.path))
        let catalog = try await files.cachedCatalog()
        XCTAssertEqual(catalog, items)
        XCTAssertEqual(CloudFileStore.maximumCacheBytes, 5_000_000_000)
    }

    @MainActor
    func testPaginationDeduplicatesAndFailedAppendKeepsListAndCursor() async throws {
        let (files, root) = try temporaryStore(); defer { try? FileManager.default.removeItem(at: root) }
        let api = PagingAPI()
        let store = CloudLibraryStore(api: api, files: files)
        await store.refresh()
        let first = store.items
        XCTAssertEqual(store.nextCursor, "second")
        await api.setFailure(true)
        await store.refresh(more: true)
        XCTAssertEqual(store.items, first)
        XCTAssertEqual(store.nextCursor, "second")
        await api.setFailure(false)
        await store.refresh(more: true)
        XCTAssertEqual(Set(store.items.map(\.id)).count, store.items.count)
        XCTAssertGreaterThan(store.items.count, first.count)
        XCTAssertNil(store.nextCursor)
        await store.refresh()
        XCTAssertEqual(store.items, first)
    }

    func testStorageCostEstimate() {
        XCTAssertEqual(StorageCostEstimate.monthlyYen(gib: 100, usdPerGiB: 0.025, yenPerUSD: 150, taxPercent: 10)!, 412.5, accuracy: 0.00001)
        XCTAssertEqual(StorageCostEstimate.monthlyYen(gib: 0, usdPerGiB: 0.025, yenPerUSD: 150, taxPercent: 10), 0)
        for invalid in [-1.0, Double.infinity, Double.nan, 51201] {
            XCTAssertNil(StorageCostEstimate.monthlyYen(gib: invalid, usdPerGiB: 0.025, yenPerUSD: 150, taxPercent: 10))
        }
    }
    func testCostHistoryPersistsAndIsIsolated() async throws {
        let (files, root) = try temporaryStore(); defer { try? FileManager.default.removeItem(at: root) }
        let sample = StorageCostSnapshot(date: Date(), bytes: 1073741824, monthlyYen: 4.125)
        _ = try await files.recordCost(sample)
        try await files.clearLocalDocuments()
        let reloaded = try await files.costHistory()
        XCTAssertEqual(reloaded.count, 1)
        XCTAssertEqual(reloaded.first?.bytes, sample.bytes)
        let other = try CloudFileStore(saved: root.appendingPathComponent("isolated"), cache: root.appendingPathComponent("isolated-cache"))
        let empty = try await other.costHistory()
        XCTAssertTrue(empty.isEmpty)
    }

    @MainActor
    func testClassificationPersistsAcrossRestartCleanupAndVersions() async throws {
        let (files, root) = try temporaryStore(); defer { try? FileManager.default.removeItem(at: root) }
        let diagram = try await MockCloudAPI().list(query: "", cursor: nil).items[0]
        let store = CloudLibraryStore(api: OfflineAPI(), files: files)
        XCTAssertEqual(store.classification(diagram).group, .other)
        let success = await store.setClassification(diagram, value: LibraryClassification(group: .work, tags: [" AWS ", "aws", "設計", ""]))
        XCTAssertTrue(success)
        XCTAssertEqual(store.classification(diagram).tags, ["AWS", "設計"])
        try await files.clearLocalDocuments()
        let restartedFiles = try CloudFileStore(saved: root.appendingPathComponent("saved"), cache: root.appendingPathComponent("cache"))
        let restarted = CloudLibraryStore(api: OfflineAPI(), files: restartedFiles)
        await restarted.reloadSaved()
        XCTAssertEqual(restarted.classification(diagram).group, .work)
        var encoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(diagram)) as? [String: Any])
        encoded["version"] = diagram.version + 1
        let newer = try JSONDecoder().decode(CloudDiagram.self, from: JSONSerialization.data(withJSONObject: encoded))
        XCTAssertEqual(restarted.classification(newer), restarted.classification(diagram))
        let isolated = try CloudFileStore(saved: root.appendingPathComponent("other-saved"), cache: root.appendingPathComponent("other-cache"))
        let isolatedValues = try await isolated.classifications()
        XCTAssertTrue(isolatedValues.isEmpty)
        let removed = await restarted.setClassification(diagram, value: LibraryClassification(group: .personal, tags: []))
        XCTAssertTrue(removed)
        XCTAssertEqual(restarted.classification(diagram).tags, [])
    }

    @MainActor
    func testClassificationWriteFailureKeepsPublishedValue() async throws {
        let (files, root) = try temporaryStore(); defer { try? FileManager.default.removeItem(at: root) }
        let diagram = try await MockCloudAPI().list(query: "", cursor: nil).items[0]
        let store = CloudLibraryStore(api: OfflineAPI(), files: files)
        let original = store.classification(diagram)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("saved/classifications.json"), withIntermediateDirectories: true)
        let success = await store.setClassification(diagram, value: LibraryClassification(group: .work, tags: ["new"]))
        XCTAssertFalse(success)
        XCTAssertEqual(store.classification(diagram), original)
        XCTAssertNotNil(store.errorMessage)
    }

    @MainActor
    func testUpdateNoticeKeepsLocalCopyUntilExplicitUpdate() async throws {
        let (files, root) = try temporaryStore(); defer { try? FileManager.default.removeItem(at: root) }
        let api = CacheCountingAPI()
        let store = CloudLibraryStore(api: api, files: files)
        await store.refresh()
        let old = try XCTUnwrap(store.items.first)
        let detail = try await store.detail(old)
        let file = try XCTUnwrap(preferredCloudFile(detail.files))
        let first = await store.open(old, file: file, persist: false); XCTAssertNotNil(first)
        await store.reloadSaved()
        XCTAssertNil(store.availableUpdate(old))
        let before = await api.counts()
        await api.setCatalogVersion(old.version + 1)
        await store.refresh()
        let latest = try XCTUnwrap(store.items.first { $0.id == old.id })
        XCTAssertEqual(store.preferredLocalVersion(latest).version, old.version)
        XCTAssertEqual(store.availableUpdate(old)?.version, latest.version)
        let reopened = await store.open(old, file: file, persist: false); XCTAssertNotNil(reopened)
        let after = await api.counts(); XCTAssertEqual(before, after)
        let newDetail = try await store.detail(latest)
        let newFile = try XCTUnwrap(preferredCloudFile(newDetail.files))
        let updated = await store.open(latest, file: newFile, persist: false); XCTAssertNotNil(updated)
        await store.reloadSaved()
        XCTAssertEqual(store.preferredLocalVersion(latest).version, latest.version)
        XCTAssertNil(store.availableUpdate(latest))
        let offlineStore = CloudLibraryStore(api: OfflineAPI(), files: files)
        await offlineStore.refresh()
        XCTAssertNil(offlineStore.availableUpdate(old))
    }

    @MainActor
    func testTemporaryCopiesReturnAfterOfflineRestartAndCleanup() async throws {
        let (files, root) = try temporaryStore(); defer { try? FileManager.default.removeItem(at: root) }
        let api = MockCloudAPI()
        let item = try await api.list(query: "RAG", cursor: nil).items[0]
        let online = CloudLibraryStore(api: api, files: files)
        let detail = try await online.detail(item)
        let pdf = try XCTUnwrap(preferredCloudFile(detail.files))
        let first = await online.open(item, file: pdf, persist: false)
        XCTAssertNotNil(first)
        let restarted = CloudLibraryStore(api: OfflineAPI(), files: try CloudFileStore(saved: root.appendingPathComponent("saved"), cache: root.appendingPathComponent("cache")))
        await restarted.reloadSaved()
        XCTAssertEqual(restarted.items, [item])
        await restarted.refresh()
        XCTAssertTrue(restarted.offline); XCTAssertNil(restarted.errorMessage)
        let offlineDetail = try await restarted.detail(item)
        XCTAssertEqual(offlineDetail.files, [pdf])
        let reopened = await restarted.open(item, file: pdf, persist: false)
        XCTAssertNotNil(reopened)
        await restarted.clearCache()
        XCTAssertTrue(restarted.items.isEmpty)
        await restarted.refresh()
        XCTAssertTrue(restarted.items.isEmpty)
    }
    @MainActor
    func testLocalCleanupKeepsPreferencesAndOnlineSource() async throws {
        let (files, root) = try temporaryStore(); defer { try? FileManager.default.removeItem(at: root) }
        let api = MockCloudAPI()
        let item = try await api.list(query: "RAG", cursor: nil).items[0]
        let store = CloudLibraryStore(api: api, files: files)
        let detail = try await store.detail(item)
        let pdf = try XCTUnwrap(preferredCloudFile(detail.files))
        let opened = await store.open(item, file: pdf, persist: true)
        XCTAssertNotNil(opened)
        _ = try await files.setHidden(item, hidden: true)
        await store.clearLocalDocuments()
        XCTAssertTrue(store.saved.isEmpty)
        let copies = try await files.cachedDiagrams(); XCTAssertTrue(copies.isEmpty)
        let hidden = try await files.hiddenDiagrams(); XCTAssertEqual(hidden, [item])
        await store.refresh()
        XCTAssertFalse(store.items.isEmpty); XCTAssertFalse(store.offline)
        let fetched = await store.open(item, file: pdf, persist: false)
        XCTAssertNotNil(fetched)
    }
    @MainActor
    func testCollectionOrderPersistsAndRemovalKeepsSavedFiles() async throws {
        let (files, root) = try temporaryStore(); defer { try? FileManager.default.removeItem(at: root) }
        let api = MockCloudAPI()
        let listed = try await api.list(query: "", cursor: nil)
        let sample = try XCTUnwrap(listed.items.first { CloudLibraryKind.illustrations.contains($0) && $0.formats.contains(.pdf) })
        let detail = try await api.detail(id: sample.id, version: sample.version)
        let pdf = try XCTUnwrap(detail.files.first { $0.format == .pdf })
        let grant = try await api.access(diagram: sample, file: pdf)
        let bytes = try await api.download(grant)
        let second = CloudDiagram(id: UUID().uuidString.lowercased(), title: "続き", type: "illustration", version: 1, formats: [.pdf], pageCount: 1, tags: [])
        try await files.save(bytes, record: SavedCloudFile(diagram: sample, file: pdf))
        try await files.save(bytes, record: SavedCloudFile(diagram: second, file: pdf))
        let store = CloudLibraryStore(api: OfflineAPI(), files: files)
        let collection = CloudCollection(id: UUID(), title: "2枚の図鑑", members: [second, sample])
        let saved = await store.saveCollection(collection); XCTAssertTrue(saved)
        await store.clearCache()
        let recreated = CloudLibraryStore(api: OfflineAPI(), files: try CloudFileStore(saved: root.appendingPathComponent("saved"), cache: root.appendingPathComponent("cache")))
        await recreated.reloadSaved()
        XCTAssertEqual(recreated.collections, [collection])
        let pages = try await recreated.collectionPages(collection)
        XCTAssertEqual(pages.map { $0.diagram.id }, [second.id, sample.id])
        for page in pages { let opened = await recreated.open(page.diagram, file: page.file, persist: false); XCTAssertNotNil(opened) }
        let isolated = try CloudFileStore(saved: root.appendingPathComponent("other-saved"), cache: root.appendingPathComponent("other-cache"))
        let other = try await isolated.collections(); XCTAssertTrue(other.isEmpty)
        let removed = await recreated.removeCollection(collection.id); XCTAssertTrue(removed)
        XCTAssertTrue(recreated.collections.isEmpty)
        let records = try await files.records(); XCTAssertEqual(records.count, 2)
    }
    func testCollectionValidationAndLatestHiddenResolution() throws {
        let id = UUID().uuidString.lowercased()
        let one = CloudDiagram(id: id, title: "前編", type: "illustration", version: 1, formats: [.png], pageCount: 1, tags: [])
        let newer = CloudDiagram(id: id, title: "前編新版", type: "illustration", version: 2, formats: [.png], pageCount: 1, tags: [])
        let two = CloudDiagram(id: UUID().uuidString.lowercased(), title: "後編", type: "illustration", version: 1, formats: [.png], pageCount: 1, tags: [])
        let group = CloudCollection(id: UUID(), title: "図鑑", members: [one, two])
        try group.validate()
        XCTAssertEqual(group.resolved(using: [two, newer, one], hidden: []), [newer, two])
        XCTAssertEqual(group.resolved(using: [newer], hidden: [one]), [two])
        XCTAssertThrowsError(try CloudCollection(id: UUID(), title: "", members: [one]).validate())
        XCTAssertThrowsError(try CloudCollection(id: UUID(), title: "重複", members: [one, newer]).validate())
        XCTAssertThrowsError(try CloudCollection(id: UUID(), title: "空", members: []).validate())
    }
    @MainActor
    func testCollectionWriteFailurePreservesState() async throws {
        let (files, root) = try temporaryStore(); defer { try? FileManager.default.removeItem(at: root) }
        let member = CloudDiagram(id: UUID().uuidString.lowercased(), title: "図解", type: "illustration", version: 1, formats: [.png], pageCount: 1, tags: [])
        try FileManager.default.createDirectory(at: root.appendingPathComponent("saved/collections.json"), withIntermediateDirectories: true)
        let store = CloudLibraryStore(files: files)
        let result = await store.saveCollection(CloudCollection(id: UUID(), title: "まとめ", members: [member]))
        XCTAssertFalse(result); XCTAssertTrue(store.collections.isEmpty); XCTAssertNotNil(store.errorMessage)
    }
    func testCollectionUsesAllPNGPagesInOrderOrPDFOnlyFallback() {
        func file(_ name: String, _ format: CloudFormat) -> CloudFile { CloudFile(name: name, format: format, sizeBytes: 1, sha256: String(repeating: "a", count: 64), contentType: format.mime) }
        let png2 = file("slides/002/slide.png", .png), png1 = file("slides/001/slide.png", .png), pdf = file("document.pdf", .pdf)
        XCTAssertEqual(collectionReadingFiles([png2, pdf, png1]), [png1, png2])
        XCTAssertEqual(collectionReadingFiles([file("presentation.pptx", .pptx), pdf]), [pdf])
    }

    @MainActor
    func testLocalHidePersistsWithoutAPIAndKeepsSavedCopy() async throws {
        let api = CacheCountingAPI()
        let (files, root) = try temporaryStore(); defer { try? FileManager.default.removeItem(at: root) }
        let store = CloudLibraryStore(api: api, files: files)
        await store.refresh(query: "RAG")
        let item = try XCTUnwrap(store.items.first)
        let detail = try await store.detail(item)
        let file = try XCTUnwrap(preferredCloudFile(detail.files))
        let document = await store.open(item, file: file, persist: true)
        XCTAssertNotNil(document)
        let before = await api.counts()
        let hidden = await store.setHidden(item, hidden: true)
        XCTAssertTrue(hidden); XCTAssertTrue(store.isHidden(item))
        XCTAssertTrue(store.saved.contains { $0.diagram.id == item.id })
        let after = await api.counts(); XCTAssertEqual(before, after)
        await store.clearCache()
        let recreated = CloudLibraryStore(api: api, files: try CloudFileStore(saved: root.appendingPathComponent("saved"), cache: root.appendingPathComponent("cache")))
        await recreated.reloadSaved(); XCTAssertTrue(recreated.isHidden(item))
        let updated = CloudDiagram(id: item.id, title: item.title, type: item.type, version: item.version + 1, formats: item.formats, pageCount: item.pageCount, tags: item.tags)
        XCTAssertTrue(recreated.isHidden(updated))
        let otherFiles = try CloudFileStore(saved: root.appendingPathComponent("other-saved"), cache: root.appendingPathComponent("other-cache"))
        let other = CloudLibraryStore(api: api, files: otherFiles)
        await other.reloadSaved(); XCTAssertFalse(other.isHidden(item))
        let restored = await recreated.setHidden(item, hidden: false)
        XCTAssertTrue(restored); XCTAssertFalse(recreated.isHidden(item))
        await store.reloadSaved(); XCTAssertFalse(store.isHidden(item))
    }
    @MainActor
    func testLocalHideFailureDoesNotChangeVisibleState() async throws {
        let (files, root) = try temporaryStore(); defer { try? FileManager.default.removeItem(at: root) }
        let item = try await MockCloudAPI().list(query: "", cursor: nil).items[0]
        let store = CloudLibraryStore(files: files)
        let url = root.appendingPathComponent("saved/hidden-diagrams.json")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        let hidden = await store.setHidden(item, hidden: true)
        XCTAssertFalse(hidden); XCTAssertFalse(store.isHidden(item)); XCTAssertNotNil(store.errorMessage)
    }
    @MainActor
    func testCacheReusedAfterRecreationAndNewVersionDownloaded() async throws {
        let api = CacheCountingAPI()
        let item = try await api.list(query: "RAG", cursor: nil).items[0]
        let (files, root) = try temporaryStore(); defer { try? FileManager.default.removeItem(at: root) }
        let store = CloudLibraryStore(api: api, files: files)
        let detail = try await store.detail(item)
        let file = try XCTUnwrap(preferredCloudFile(detail.files))
        let result613 = await store.open(item, file: file, persist: false)
        XCTAssertNotNil(result613)
        let result689 = await store.thumbnail(item, offline: false)
        XCTAssertNotNil(result689)
        let initial = await api.counts()
        XCTAssertEqual(initial, [1, 2, 2])
        let recreated = CloudLibraryStore(api: api, files: try CloudFileStore(saved: root.appendingPathComponent("saved"), cache: root.appendingPathComponent("cache")))
        _ = try await recreated.detail(item)
        let result1056 = await recreated.open(item, file: file, persist: true)
        XCTAssertNotNil(result1056)
        let result1135 = await recreated.thumbnail(item, offline: false)
        XCTAssertNotNil(result1135)
        let reused = await api.counts(); XCTAssertEqual(reused, initial)
        let newer = CloudDiagram(id: item.id, title: item.title, type: item.type, version: 2, formats: item.formats, pageCount: item.pageCount, tags: item.tags)
        let updated = try await recreated.detail(newer)
        let result1498 = await recreated.open(newer, file: try XCTUnwrap(preferredCloudFile(updated.files)), persist: false)
        XCTAssertNotNil(result1498)
        let changed = await api.counts(); XCTAssertEqual(changed, [2, 3, 3])
        await recreated.clearCache()
        let result1737 = await recreated.open(item, file: file, persist: false)
        XCTAssertNotNil(result1737)
        let savedReuse = await api.counts(); XCTAssertEqual(savedReuse, changed)
    }
    @MainActor
    func testCorruptCacheRefetchedAndCacheClearDownloadsAgain() async throws {
        let api = CacheCountingAPI()
        let item = try await api.list(query: "RAG", cursor: nil).items[0]
        let (files, root) = try temporaryStore(); defer { try? FileManager.default.removeItem(at: root) }
        let store = CloudLibraryStore(api: api, files: files)
        let detail = try await store.detail(item)
        let file = try XCTUnwrap(preferredCloudFile(detail.files))
        let opened = await store.open(item, file: file, persist: false)
        let url = try XCTUnwrap(opened?.url)
        try Data("corrupt".utf8).write(to: url)
        let recovered = await store.open(item, file: file, persist: false)
        XCTAssertNotNil(recovered)
        XCTAssertEqual(cloudHash(try Data(contentsOf: url)), file.sha256)
        let counts = await api.counts(); XCTAssertEqual(counts, [1, 2, 2])
        await store.clearCache()
        _ = try await store.detail(item)
        let reopened = await store.open(item, file: file, persist: false)
        XCTAssertNotNil(reopened)
        let cleared = await api.counts(); XCTAssertEqual(cleared, [2, 3, 3])
    }
    @MainActor
    func testCachedDetailAndFilesWorkWithoutNetworkAndStayIsolated() async throws {
        let api = MockCloudAPI()
        let item = try await api.list(query: "RAG", cursor: nil).items[0]
        let (files, root) = try temporaryStore(); defer { try? FileManager.default.removeItem(at: root) }
        let online = CloudLibraryStore(api: api, files: files)
        let detail = try await online.detail(item)
        let file = try XCTUnwrap(preferredCloudFile(detail.files))
        let initial = await online.open(item, file: file, persist: false)
        XCTAssertNotNil(initial)
        let offline = CloudLibraryStore(api: OfflineAPI(), files: files)
        let cached = try await offline.detail(item)
        XCTAssertEqual(cached.files, detail.files)
        let reopened = await offline.open(item, file: file, persist: false)
        XCTAssertNotNil(reopened)
        let other = try CloudFileStore(saved: root.appendingPathComponent("other-saved"), cache: root.appendingPathComponent("other-cache"))
        let isolated = try await other.localURL(SavedCloudFile(diagram: item, file: file))
        let isolatedDetail = try await other.cachedDetail(item)
        XCTAssertNil(isolated); XCTAssertNil(isolatedDetail)
        let detailURL = root.appendingPathComponent("cache/detail-\(item.id.lowercased())-\(item.version).json")
        try Data("invalid".utf8).write(to: detailURL)
        let corrupt = try await files.cachedDetail(item)
        XCTAssertNil(corrupt)
        XCTAssertFalse(FileManager.default.fileExists(atPath: detailURL.path))
    }
    @MainActor
    func testConnectionIsReadyBeforeFirstTabRender() async throws {
        let config = try CloudConnection.bundled()
        let state = CloudConnectionState(makeAuth: { try CloudOIDC(config: config, readTokens: { nil }) })
        XCTAssertNotNil(state.auth)
        XCTAssertFalse(state.failed)
    }
    @MainActor
    func testSharedConnectionRetriesFailureAndKeepsOneAuthForTabs() async throws {
        let config = try CloudConnection.bundled()
        var attempts = 0
        let state = CloudConnectionState(makeAuth: {
            attempts += 1
            if attempts == 1 { throw CloudError.unavailable }
            return try CloudOIDC(config: config, readTokens: { nil })
        }, startImmediately: false)
        state.initialize(); XCTAssertTrue(state.failed); XCTAssertNil(state.auth)
        state.initialize(); XCTAssertFalse(state.failed); XCTAssertNotNil(state.auth)
        let auth = state.auth
        state.initialize(); XCTAssertEqual(attempts, 2); XCTAssertTrue(auth === state.auth)
    }
    @MainActor
    func testLocalNamespaceAvailableWithoutLoginAndRejectsInvalidNamespace() throws {
        let config = try CloudConnection.bundled()
        let previous = cloudHash(Data("previous-owner".utf8))
        let auth = try CloudOIDC(config: config, readTokens: { throw CloudError.authentication }, readCachedNamespace: { previous })
        XCTAssertNil(auth.namespace)
        XCTAssertEqual(auth.libraryNamespace, previous)
        let invalid = try CloudOIDC(config: config, readTokens: { nil }, readCachedNamespace: { "../another-owner" })
        XCTAssertNil(invalid.libraryNamespace)
    }
    @MainActor
    func testConfiguredConnectionSurvivesUnavailableSavedLogin() async throws {
        let config = try CloudConnection.bundled()
        let auth = try CloudOIDC(config: config, readTokens: { throw CloudError.authentication })
        XCTAssertEqual(auth.config.api, config.api)
        XCTAssertNil(auth.namespace)
        XCTAssertNotNil(auth.message)
        let empty = try CloudOIDC(config: config, readTokens: { nil })
        XCTAssertNil(empty.message)
    }
    func testCapacityCountsAllPagesAndOnlyLatestVersions() async throws {
        let api = CapacityTestAPI()
        let value = try await api.capacity()
        XCTAssertEqual(value.documentCount, 2)
        XCTAssertEqual(value.sizeBytes, 600)
        XCTAssertLessThan(abs(value.updatedAt.timeIntervalSinceNow), 5)
        let empty = try await CapacityTestAPI(empty: true).capacity()
        XCTAssertEqual(empty.documentCount, 0)
        XCTAssertEqual(empty.sizeBytes, 0)
    }
    func testCapacityRejectsPartialFailureAndCursorLoop() async {
        for api in [CapacityTestAPI(failing: true), CapacityTestAPI(loop: true)] {
            do { _ = try await api.capacity(); XCTFail("Partial or looping total accepted") }
            catch { XCTAssertTrue(error is CloudError) }
        }
    }
    func testPKCEAndCallbackRejectWrongStateAndDuplicateCode() throws {
        XCTAssertEqual(oidcChallenge("dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"), "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
        let redirect = "presentationviewer://oauth/callback"
        XCTAssertEqual(try oidcCode(URL(string: redirect + "?code=abc&state=expected")!, redirect: redirect, state: "expected"), "abc")
        for suffix in ["?code=abc&state=wrong", "?code=abc&code=other&state=expected", "?error=denied&state=expected"] {
            XCTAssertThrowsError(try oidcCode(URL(string: redirect + suffix)!, redirect: redirect, state: "expected"))
        }
        XCTAssertThrowsError(try oidcCode(URL(string: "presentationviewer://evil/callback?code=abc&state=expected")!, redirect: redirect, state: "expected"))
    }
    func testKeychainAndProductionConfiguration() throws {
        let keychain = CloudKeychain(account: "test-" + UUID().uuidString)
        defer { try? keychain.delete() }
        XCTAssertNil(try keychain.read())
        let value = CloudTokens(access: "test-access", refresh: "test-refresh", expires: Date(), subject: "test-subject")
        try keychain.write(value); XCTAssertEqual(try keychain.read()?.subject, "test-subject")
        try keychain.delete(); XCTAssertNil(try keychain.read())
        let valid = CloudConnection(issuer: URL(string: "https://cognito-idp.ap-northeast-1.amazonaws.com/ap-northeast-1_Test")!, domain: URL(string: "https://test.auth.ap-northeast-1.amazoncognito.com")!, clientID: "client", api: URL(string: "https://api.example")!, artifactHosts: ["bucket.s3.ap-northeast-1.amazonaws.com"], redirect: "presentationviewer://oauth/callback")
        XCTAssertNoThrow(try valid.validate())
        let invalid = CloudConnection(issuer: valid.issuer, domain: valid.domain, clientID: "client", api: URL(string: "http://api.example")!, artifactHosts: valid.artifactHosts, redirect: valid.redirect)
        XCTAssertThrowsError(try invalid.validate())
    }
    @MainActor
    func testExpiredURLIsRenewedOnceBeforeSaving() async throws {
        let mock = MockCloudAPI(), item = try await mock.list(query: "RAG", cursor: nil).items[0]
        let detail = try await mock.detail(id: item.id, version: item.version)
        let file = try XCTUnwrap(preferredCloudFile(detail.files))
        let (files, root) = try temporaryStore(); defer { try? FileManager.default.removeItem(at: root) }
        let api = ExpiringAPI(mock: mock)
        let store = CloudLibraryStore(api: api, files: files)
        let opened = await store.open(item, file: file, persist: true)
        XCTAssertNotNil(opened)
        let attempts = await api.attempts; XCTAssertEqual(attempts, 2)
        XCTAssertEqual(store.saved.count, 1)
        await store.clearCache(); let reopened = await store.openSaved(store.saved[0]); XCTAssertNotNil(reopened)
    }
    @MainActor
    func testOIDCRefreshValidatesIdentityAndLogoutClearsKeychain() async throws {
        let config = CloudConnection(issuer: URL(string: "https://cognito-idp.ap-northeast-1.amazonaws.com/ap-northeast-1_Test")!, domain: URL(string: "https://test.auth.ap-northeast-1.amazoncognito.com")!, clientID: UUID().uuidString, api: URL(string: "https://api.example")!, artifactHosts: ["bucket.s3.ap-northeast-1.amazonaws.com"], redirect: "presentationviewer://oauth/callback")
        let keychain = CloudKeychain(account: config.key)
        defer { try? keychain.delete(); OIDCTestProtocol.respond = nil }
        try keychain.write(CloudTokens(access: "old", refresh: "refresh", expires: Date(timeIntervalSince1970: 0), subject: "owner"))
        var refreshed = false, revoked = false
        OIDCTestProtocol.respond = { request in
            if request.url?.path == "/oauth2/token" {
                refreshed = true
                return Data("{\"access_token\":\"new\",\"expires_in\":300,\"token_type\":\"Bearer\"}".utf8)
            }
            if request.url?.path == "/v1/me" {
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer new")
                return try JSONSerialization.data(withJSONObject: ["issuer": config.issuer.absoluteString, "subject": "owner"])
            }
            if request.url?.path == "/oauth2/revoke" { revoked = true; return Data() }
            throw CloudError.invalidResponse
        }
        let settings = URLSessionConfiguration.ephemeral; settings.protocolClasses = [OIDCTestProtocol.self]
        let auth = try CloudOIDC(config: config, transport: URLSession(configuration: settings))
        let token = try await auth.accessToken()
        XCTAssertEqual(token, "new"); XCTAssertTrue(refreshed)
        XCTAssertEqual(try keychain.read()?.access, "new")
        await auth.logout()
        XCTAssertTrue(revoked); XCTAssertNil(auth.subject); XCTAssertNil(try keychain.read())
        do { _ = try await auth.accessToken(); XCTFail("Logged-out token returned") } catch { XCTAssertTrue(error is CloudError) }
    }
    private func temporaryStore() throws -> (CloudFileStore, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        return (try CloudFileStore(saved: root.appendingPathComponent("saved"), cache: root.appendingPathComponent("cache")), root)
    }
    func testDefaultReadingPrefersPDFThenFirstPNG() async throws {
        let api = MockCloudAPI(), item = try await api.list(query: "RAG", cursor: nil).items[0]
        let detail = try await api.detail(id: item.id, version: item.version)
        XCTAssertEqual(preferredCloudFile(detail.files)?.format, .pdf)
        let images = detail.files.filter { $0.format == .png }.reversed()
        XCTAssertEqual(preferredCloudFile(Array(images))?.page, 1)
        XCTAssertNil(preferredCloudFile([]))
    }
    @MainActor
    func testSaveFromReaderNeedsNoAPIAndKeepsDocument() async throws {
        let api = MockCloudAPI(), item = try await api.list(query: "RAG", cursor: nil).items[0]
        let detail = try await api.detail(id: item.id, version: item.version)
        let file = try XCTUnwrap(preferredCloudFile(detail.files))
        let grant = try await api.access(diagram: item, file: file)
        let data = try await api.download(grant)
        let (files, root) = try temporaryStore(); defer { try? FileManager.default.removeItem(at: root) }
        let record = SavedCloudFile(diagram: item, file: file), url = try await files.cacheData(data, record: record)
        let document = OpenedDocument(url: url, name: item.title, format: .pdf, accessURL: url, scoped: false)
        let originalID = document.id
        let store = CloudLibraryStore(api: OfflineAPI(), files: files)
        let success = await store.saveOpened(document, record: record)
        XCTAssertTrue(success); XCTAssertTrue(store.isSaved(record)); XCTAssertEqual(document.id, originalID)
        await store.clearCache()
        let reopened = await store.openSaved(record)
        XCTAssertNotNil(reopened); XCTAssertEqual(PDFDocument(url: try XCTUnwrap(reopened?.url))?.pageCount, 8)
    }
    func testMockContractSearchAndAllFormats() async throws {
        let api = MockCloudAPI()
        let list = try await api.list(query: "RAG", cursor: nil)
        XCTAssertEqual(list.items.count, 1); XCTAssertEqual(list.items[0].pageCount, 8)
        let all = try await api.list(query: "", cursor: nil)
        var formats = Set<CloudFormat>()
        for item in all.items {
            let detail = try await api.detail(id: item.id, version: item.version)
            for file in detail.files {
                let grant = try await api.access(diagram: item, file: file)
                let data = try await api.download(grant)
                XCTAssertEqual(data.count, file.sizeBytes); XCTAssertEqual(cloudHash(data), file.sha256)
                formats.insert(file.format)
                if file.format == .png { XCTAssertNotNil(UIImage(data: data)) }
                if file.format == .pdf { XCTAssertEqual(PDFDocument(data: data)?.pageCount, item.pageCount) }
                if file.format == .pptx { XCTAssertEqual(Array(data.prefix(2)), [0x50, 0x4b]) }
            }
        }
        XCTAssertEqual(formats, Set(CloudFormat.allCases))
    }
    func testSaveSurvivesRecreationAndCacheClearWithoutAPI() async throws {
        let api = MockCloudAPI(); let list = try await api.list(query: "RAG", cursor: nil)
        let detail = try await api.detail(id: list.items[0].id, version: 1)
        let file = try XCTUnwrap(detail.files.first(where: { $0.format == .pdf }))
        let grant = try await api.access(diagram: detail.diagram, file: file); let data = try await api.download(grant)
        let (store, root) = try temporaryStore(); defer { try? FileManager.default.removeItem(at: root) }
        let record = SavedCloudFile(diagram: detail.diagram, file: file)
        let cached = try await store.cacheData(data, record: record); try await store.save(data, record: record)
        try await store.clearCache(); XCTAssertFalse(FileManager.default.fileExists(atPath: cached.path))
        // Fresh store instance models restart. No API method called below.
        let reopened = try CloudFileStore(saved: root.appendingPathComponent("saved"), cache: root.appendingPathComponent("cache"))
        let records = try await reopened.records(); XCTAssertEqual(records.count, 1)
        let url = try await reopened.open(records[0]); XCTAssertEqual(cloudHash(try Data(contentsOf: url)), file.sha256)
        XCTAssertEqual(PDFDocument(url: url)?.pageCount, 8)
    }
    func testCorruptionCannotBeSavedOrOpened() async throws {
        let api = MockCloudAPI(); let list = try await api.list(query: "RAG", cursor: nil)
        let detail = try await api.detail(id: list.items[0].id, version: 1)
        let file = detail.files[0], record = SavedCloudFile(diagram: detail.diagram, file: file)
        let grant = try await api.access(diagram: detail.diagram, file: file); let data = try await api.download(grant)
        let (store, root) = try temporaryStore(); defer { try? FileManager.default.removeItem(at: root) }
        do { try await store.save(Data("corrupt".utf8), record: record); XCTFail("corruption accepted") } catch { XCTAssertTrue(error is CloudError) }
        let empty = try await store.records(); XCTAssertTrue(empty.isEmpty)
        try await store.save(data, record: record); let url = try await store.open(record)
        try Data("tampered".utf8).write(to: url)
        do { _ = try await store.open(record); XCTFail("tampered offline data opened") } catch { XCTAssertTrue(error is CloudError) }
    }
    func testCommonAPIMillisecondExpiryAndLegacyJSONArtifacts() async throws {
        let api = MockCloudAPI(); let item = try await api.list(query: "RAG", cursor: nil).items[0]
        let detail = try await api.detail(id: item.id, version: item.version), file = detail.files[0]
        let grant = CloudGrant(url: URL(string: "https://artifacts.example.com/slide.png")!, method: "GET", expiresAt: "2099-01-01T00:00:00.000Z", expiresIn: 300, contentType: file.contentType, sizeBytes: file.sizeBytes, sha256: file.sha256, fileName: "slide.png")
        XCTAssertNoThrow(try grant.validate(file: file))
        let expired = CloudGrant(url: grant.url, method: "GET", expiresAt: "2000-01-01T00:00:00.000Z", expiresIn: 300, contentType: file.contentType, sizeBytes: file.sizeBytes, sha256: file.sha256, fileName: "slide.png")
        XCTAssertThrowsError(try expired.validate(file: file))
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(detail)) as? [String: Any])
        var files = try XCTUnwrap(json["files"] as? [[String: Any]])
        for i in files.indices { files[i].removeValue(forKey: "contentType") }
        files.append(["name": "input.json", "format": "json", "sizeBytes": 2, "sha256": String(repeating: "0", count: 64)])
        json["files"] = files
        let decoded = try JSONDecoder().decode(CloudDetail.self, from: JSONSerialization.data(withJSONObject: json))
        try decoded.validate(); XCTAssertEqual(decoded.files.count, detail.files.count)
    }
    func testApprovedLargePresentationIsScopedToExactVersionAndBytes() throws {
        let diagram = CloudDiagram(id: CloudArtifactSizePolicy.diagramID, title: "2040", type: "presentation", version: 1, formats: [.png, .pdf, .pptx], pageCount: 40, tags: [])
        let pdf = CloudFile(name: "document.pdf", format: .pdf, sizeBytes: 29_640_691, sha256: "eb08beebf657a1582423e48f3602207169828b5ec906c5ce9c9a3a18acbf620a", contentType: CloudFormat.pdf.mime)
        let pptx = CloudFile(name: "presentation.pptx", format: .pptx, sizeBytes: 20_067_274, sha256: "80e86b33ad702a9642f615e475885a48847288a365469b36778d689211ed870b", contentType: CloudFormat.pptx.mime)
        for file in [pdf, pptx] {
            XCTAssertNoThrow(try file.validate(for: diagram))
            let grant = CloudGrant(url: URL(string: "https://artifacts.example.com/" + file.name)!, method: "GET", expiresAt: "2099-01-01T00:00:00Z", expiresIn: 300, contentType: file.contentType, sizeBytes: file.sizeBytes, sha256: file.sha256, fileName: file.name)
            XCTAssertNoThrow(try grant.validate(file: file)); XCTAssertTrue(CloudArtifactSizePolicy.allows(grant: grant))
            for (id, version, pages) in [(UUID().uuidString, 1, 40), (diagram.id, 2, 40), (diagram.id, 1, 39)] {
                let other = CloudDiagram(id: id, title: diagram.title, type: "presentation", version: version, formats: diagram.formats, pageCount: pages, tags: [])
                XCTAssertThrowsError(try file.validate(for: other))
            }
            for changed in [CloudFile(name: file.name, format: file.format, sizeBytes: file.sizeBytes + 1, sha256: file.sha256, contentType: file.contentType), CloudFile(name: file.name, format: file.format, sizeBytes: file.sizeBytes, sha256: String(repeating: "0", count: 64), contentType: file.contentType)] {
                XCTAssertThrowsError(try changed.validate(for: diagram))
                let bad = CloudGrant(url: grant.url, method: "GET", expiresAt: grant.expiresAt, expiresIn: 300, contentType: changed.contentType, sizeBytes: changed.sizeBytes, sha256: changed.sha256, fileName: changed.name)
                XCTAssertFalse(CloudArtifactSizePolicy.allows(grant: bad))
            }
        }
    }
    func testApprovedLargePDFCacheSaveAndOfflineReopen() async throws {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("outputs/large-presentation-fixture/document.pdf")
        guard FileManager.default.fileExists(atPath: fixture.path) else { throw XCTSkip("Optional real 40-page PDF fixture not installed") }
        let data = try Data(contentsOf: fixture)
        let diagram = CloudDiagram(id: CloudArtifactSizePolicy.diagramID, title: "2040", type: "presentation", version: 1, formats: [.png, .pdf, .pptx], pageCount: 40, tags: [])
        let file = CloudFile(name: "document.pdf", format: .pdf, sizeBytes: 29_640_691, sha256: "eb08beebf657a1582423e48f3602207169828b5ec906c5ce9c9a3a18acbf620a", contentType: CloudFormat.pdf.mime)
        let record = SavedCloudFile(diagram: diagram, file: file)
        let (store, root) = try temporaryStore(); defer { try? FileManager.default.removeItem(at: root) }
        let cached = try await store.cacheData(data, record: record)
        XCTAssertEqual(PDFDocument(url: cached)?.pageCount, 40)
        try await store.save(data, record: record); try await store.clearCache()
        let reopened = try CloudFileStore(saved: root.appendingPathComponent("saved"), cache: root.appendingPathComponent("cache"))
        let url = try await reopened.open(record)
        XCTAssertEqual(cloudHash(try Data(contentsOf: url)), file.sha256)
        XCTAssertEqual(PDFDocument(url: url)?.pageCount, 40)
    }
    func testUnsafeNamesAndHTTPAreRejected() async throws {
        let api = MockCloudAPI(); let item = try await api.list(query: "RAG", cursor: nil).items[0]
        let file = CloudFile(name: "../../other.pdf", format: .pdf, sizeBytes: 12, sha256: String(repeating: "0", count: 64), contentType: "application/pdf")
        XCTAssertThrowsError(try file.validate(for: item))
        let oversized = CloudFile(name: "document.pdf", format: .pdf, sizeBytes: 20_000_000, sha256: String(repeating: "0", count: 64), contentType: "application/pdf")
        XCTAssertThrowsError(try oversized.validate(for: item))
        XCTAssertThrowsError(try HTTPSCloudAPI(baseURL: URL(string: "http://example.com")!, allowedArtifactHosts: ["example.com"], tokens: NeverToken()))
        let client = try HTTPSCloudAPI(baseURL: URL(string: "https://example.com")!, allowedArtifactHosts: ["artifacts.example.com"], tokens: NeverToken())
        let grant = CloudGrant(url: URL(string: "https://evil.example/test")!, method: "GET", expiresAt: "2099-01-01T00:00:00Z", expiresIn: 300, contentType: "application/pdf", sizeBytes: 12, sha256: String(repeating: "0", count: 64), fileName: "document.pdf")
        do { _ = try await client.download(grant); XCTFail("unapproved host requested") } catch { XCTAssertTrue(error is CloudError) }
    }
    func testSameVersionDifferentHashCannotOverwrite() async throws {
        let api = MockCloudAPI(); let list = try await api.list(query: "RAG", cursor: nil)
        let detail = try await api.detail(id: list.items[0].id, version: 1)
        let f = detail.files[0]; let grant = try await api.access(diagram: detail.diagram, file: f); let data = try await api.download(grant)
        let (store, root) = try temporaryStore(); defer { try? FileManager.default.removeItem(at: root) }
        let record = SavedCloudFile(diagram: detail.diagram, file: f); try await store.save(data, record: record)
        let other = Data("other".utf8), file = CloudFile(name: f.name, format: f.format, sizeBytes: other.count, sha256: cloudHash(other), contentType: f.contentType)
        do { try await store.save(other, record: SavedCloudFile(diagram: detail.diagram, file: file)); XCTFail("immutable version overwritten") } catch { XCTAssertTrue(error is CloudError) }
        let url = try await store.open(record); XCTAssertEqual(cloudHash(try Data(contentsOf: url)), f.sha256)
    }
}
private struct NeverToken: CloudAccessTokenProvider { func accessToken() async throws -> String { throw CloudError.authentication } }

private struct OfflineAPI: CloudLibraryAPI {
    func list(query: String, cursor: String?) async throws -> CloudList { throw CloudError.unavailable }
    func detail(id: String, version: Int) async throws -> CloudDetail { throw CloudError.unavailable }
    func access(diagram: CloudDiagram, file: CloudFile) async throws -> CloudGrant { throw CloudError.unavailable }
    func download(_ grant: CloudGrant) async throws -> Data { throw CloudError.unavailable }
}

private actor ExpiringAPI: CloudLibraryAPI {
    let mock: MockCloudAPI
    private(set) var attempts = 0
    init(mock: MockCloudAPI) { self.mock = mock }
    func list(query: String, cursor: String?) async throws -> CloudList { try await mock.list(query: query, cursor: cursor) }
    func detail(id: String, version: Int) async throws -> CloudDetail { try await mock.detail(id: id, version: version) }
    func access(diagram: CloudDiagram, file: CloudFile) async throws -> CloudGrant {
        attempts += 1; return try await mock.access(diagram: diagram, file: file)
    }
    func download(_ grant: CloudGrant) async throws -> Data {
        if attempts == 1 { throw CloudError.expiredURL }
        return try await mock.download(grant)
    }
}

private final class OIDCTestProtocol: URLProtocol {
    static var respond: ((URLRequest) throws -> Data)?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let data = try Self.respond?(request) ?? Data()
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: ["Content-Type": "application/json"])!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

private struct CapacityTestAPI: CloudLibraryAPI {
    var empty = false
    var failing = false
    var loop = false
    private let first = "00000000-0000-4000-8000-000000000001"
    private let second = "00000000-0000-4000-8000-000000000002"
    private func item(_ id: String, _ version: Int) -> CloudDiagram {
        CloudDiagram(id: id, title: "容量試験", type: "presentation", version: version,
                     formats: [.pdf, .pptx, .png], pageCount: 2, tags: [])
    }
    func list(query: String, cursor: String?) async throws -> CloudList {
        XCTAssertEqual(query, "")
        if empty { return CloudList(items: [], nextCursor: nil) }
        if cursor == nil { return CloudList(items: [item(first, 1)], nextCursor: "next") }
        return CloudList(items: [item(first, 2), item(second, 1)], nextCursor: loop ? "next" : nil)
    }
    func detail(id: String, version: Int) async throws -> CloudDetail {
        if failing && id == second { throw CloudError.unavailable }
        if id == first { XCTAssertEqual(version, 2) }
        let diagram = item(id, version)
        let files = [("document.pdf", CloudFormat.pdf, 100), ("presentation.pptx", .pptx, 100),
                     ("slides/001/slide.png", .png, 50), ("slides/002/slide.png", .png, 50)]
            .map { CloudFile(name: $0.0, format: $0.1, sizeBytes: $0.2,
                            sha256: String(repeating: "a", count: 64), contentType: $0.1.mime) }
        return CloudDetail(id: id, title: diagram.title, type: diagram.type, version: version,
                           formats: diagram.formats, pageCount: 2, tags: [], files: files)
    }
    func access(diagram: CloudDiagram, file: CloudFile) async throws -> CloudGrant {
        XCTFail("Capacity must not request artifact access"); throw CloudError.invalidResponse
    }
    func download(_ grant: CloudGrant) async throws -> Data {
        XCTFail("Capacity must not download artifacts"); throw CloudError.invalidResponse
    }
}

final class CloudLibraryKindTests: XCTestCase {
    func testTypeClassificationKeepsSingleSlidePresentationSeparate() {
        func item(_ type: String, pages: Int = 1) -> CloudDiagram {
            CloudDiagram(id: "40dfe0b6-faec-4a34-8d90-f7c12155f6cf", title: "Test", type: type, version: 1, formats: [.png, .pdf], pageCount: pages, tags: [])
        }
        XCTAssertTrue(CloudLibraryKind.presentations.contains(item("presentation")))
        XCTAssertFalse(CloudLibraryKind.illustrations.contains(item("presentation")))
        for type in ["illustration", "roadmap", "architecture", "flowchart", "comparison"] {
            XCTAssertTrue(CloudLibraryKind.illustrations.contains(item(type)))
            XCTAssertFalse(CloudLibraryKind.presentations.contains(item(type)))
        }
        XCTAssertTrue(CloudLibraryKind.presentations.contains(item("legacy")))
    }
    func testIllustrationFileNamesRejectPresentationAndExtraPage() throws {
        let diagram = CloudDiagram(id: "40dfe0b6-faec-4a34-8d90-f7c12155f6cf", title: "Test", type: "illustration", version: 1, formats: [.png, .pdf], pageCount: 1, tags: [])
        let valid = CloudFile(name: "diagram.pdf", format: .pdf, sizeBytes: 10, sha256: String(repeating: "a", count: 64), contentType: "application/pdf")
        XCTAssertNoThrow(try valid.validate(for: diagram))
        let invalid = CloudFile(name: "document.pdf", format: .pdf, sizeBytes: 10, sha256: valid.sha256, contentType: valid.contentType)
        XCTAssertThrowsError(try invalid.validate(for: diagram))
    }
}

private actor CacheCountingAPI: CloudLibraryAPI {
    let mock = MockCloudAPI()
    var details = 0, grants = 0, downloads = 0
    var catalogVersion = 1
    func setCatalogVersion(_ version: Int) { catalogVersion = version }
    func counts() -> [Int] { [details, grants, downloads] }
    func list(query: String, cursor: String?) async throws -> CloudList {
        let result = try await mock.list(query: query, cursor: cursor)
        return CloudList(items: result.items.map {
            CloudDiagram(id: $0.id, title: $0.title, type: $0.type, version: catalogVersion,
                         formats: $0.formats, pageCount: $0.pageCount, tags: $0.tags)
        }, nextCursor: result.nextCursor)
    }
    func detail(id: String, version: Int) async throws -> CloudDetail {
        details += 1
        let original = try await mock.detail(id: id, version: 1)
        return CloudDetail(id: original.id, title: original.title, type: original.type, version: version,
                           formats: original.formats, pageCount: original.pageCount, tags: original.tags, files: original.files)
    }
    func access(diagram: CloudDiagram, file: CloudFile) async throws -> CloudGrant {
        grants += 1
        let original = try await mock.detail(id: diagram.id, version: 1)
        return try await mock.access(diagram: original.diagram, file: file)
    }
    func download(_ grant: CloudGrant) async throws -> Data { downloads += 1; return try await mock.download(grant) }
}

private actor PagingAPI: CloudLibraryAPI {
    private var failure = false
    func setFailure(_ value: Bool) { failure = value }
    func list(query: String, cursor: String?) async throws -> CloudList {
        if failure { throw CloudError.unavailable }
        let items = try await MockCloudAPI().list(query: "", cursor: nil).items
        return CloudList(items: cursor == nil ? [items[0]] : items, nextCursor: cursor == nil ? "second" : nil)
    }
    func detail(id: String, version: Int) async throws -> CloudDetail { throw CloudError.unavailable }
    func access(diagram: CloudDiagram, file: CloudFile) async throws -> CloudGrant { throw CloudError.unavailable }
    func download(_ grant: CloudGrant) async throws -> Data { throw CloudError.unavailable }
}


extension CloudLibraryTests {
    @MainActor func testOrdinaryLibraryEditsSyncAndReceivedMetadataAppears() async throws {
        let (files, root) = try temporaryStore(); defer { try? FileManager.default.removeItem(at: root) }
        let store = CloudLibraryStore(api: MockCloudAPI(), files: files, enableTestSync: true)
        await store.refresh()
        let diagram = try XCTUnwrap(store.items.first { CloudLibraryKind.illustrations.contains($0) && $0.formats.contains(.pdf) })
        let library = UUID()
        let directory = await files.testLibrarySyncDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let payload: [String: Any] = ["schemaVersion": 1, "endpoint": "http://127.0.0.1:1", "client": try JSONSerialization.jsonObject(with: JSONEncoder().encode(OrganizationSyncClient<OrganizationDocument>(libraryID: library))), "imported": true, "observed": [:], "bound": true]
        try JSONSerialization.data(withJSONObject: payload).write(to: directory.appendingPathComponent("checkpoint.json"))
        let session = await store.makeSyncLab()
        let created = await store.createFolder("通常画面のフォルダ"); XCTAssertTrue(created)
        let folder = try XCTUnwrap(store.organization.folders.first)
        let moved = await store.moveDocuments([diagram.id], to: folder.id); XCTAssertTrue(moved)
        let classified = await store.setClassification(diagram, value: LibraryClassification(group: .work, tags: ["通常タグ"])); XCTAssertTrue(classified)
        let collected = await store.saveCollection(CloudCollection(id: UUID(), title: "通常まとめ", members: [diagram])); XCTAssertTrue(collected)
        XCTAssertGreaterThan(session.pendingCount, 0)
        let server = LocalOrganizationSyncServer<OrganizationDocument>(libraryID: library, memberID: { $0.id })
        await session.synchronize(with: server)
        XCTAssertEqual(session.pendingCount, 0)
        var peer = OrganizationSyncClient<OrganizationDocument>(libraryID: library)
        try await peer.synchronize(with: server)
        var renamed = folder; renamed.name = "受信したフォルダ"
        peer.edit(key: OrganizationSyncKey.folder(folder.id), value: .folder(renamed))
        peer.edit(key: OrganizationSyncKey.group(diagram.id), value: .group(.personal))
        peer.edit(key: OrganizationSyncKey.tag(diagram.id, "受信タグ"), value: .tag("受信タグ"))
        try await peer.synchronize(with: server)
        await session.synchronize(with: server)
        XCTAssertEqual(store.organization.folders.first?.name, "受信したフォルダ")
        XCTAssertEqual(store.organization.assignments[diagram.id.lowercased()], folder.id)
        XCTAssertEqual(store.classification(diagram).group, .personal)
        XCTAssertEqual(Set(store.classification(diagram).tags), Set(["通常タグ", "受信タグ"]))
        XCTAssertEqual(store.collections.first?.title, "通常まとめ")
        let restored = CloudLibraryStore(api: MockCloudAPI(), files: files)
        await restored.refresh()
        XCTAssertEqual(restored.organization.folders.first?.name, "受信したフォルダ")
        XCTAssertEqual(restored.classifications, store.classifications)
        XCTAssertEqual(restored.collections, store.collections)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("saved/test-library-sync/recovery.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("saved/test-sync-apply.json").path))
    }
    func testInterruptedLibraryApplyRecoversBeforeReading() async throws {
        let (files, root) = try temporaryStore(); defer { try? FileManager.default.removeItem(at: root) }
        var state = OrganizationState<CloudDiagram>()
        state.folders = [OrganizationFolder(name: "中断した受信反映")]
        state.classifications[UUID().uuidString.lowercased()] = LibraryClassification(group: .work, tags: ["保持"])
        try JSONEncoder().encode(state).write(to: root.appendingPathComponent("saved/test-sync-apply.json"))
        let recovered = try await files.organization()
        let classifications = try await files.classifications()
        XCTAssertEqual(recovered.folders, state.folders)
        XCTAssertEqual(classifications, state.classifications)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("saved/test-sync-apply.json").path))
    }
}


extension CloudLibraryTests {
    @MainActor func testManagementOnlyBackupRestoresExactFilesAndStopsSync() async throws {
        let (files, root) = try temporaryStore(); defer { try? FileManager.default.removeItem(at: root) }
        let store = CloudLibraryStore(api: MockCloudAPI(), files: files, enableTestSync: true)
        await store.refresh()
        let created = await store.createFolder("元フォルダ"); XCTAssertTrue(created)
        let diagram = try XCTUnwrap(store.items.first)
        let tagged = await store.setClassification(diagram, value: LibraryClassification(group: .work, tags: ["元タグ"])); XCTAssertTrue(tagged)
        let saved = root.appendingPathComponent("saved")
        let before = try ["organization.json", "classifications.json"].map { try Data(contentsOf: saved.appendingPathComponent($0)) }
        let body = saved.appendingPathComponent("untouched.pdf")
        let bodyBytes = Data("BODY-MUST-NOT-BE-BACKED-UP".utf8); try bodyBytes.write(to: body)
        let session = await store.makeSyncLab()
        await session.prepare(endpoint: "http://127.0.0.1:1", libraryID: UUID().uuidString)
        XCTAssertNotNil(session.backupDate)
        let changed = await store.createFolder("後の変更"); XCTAssertTrue(changed)
        await session.restoreBackup()
        XCTAssertFalse(session.connected)
        XCTAssertEqual(store.organization.folders.map(\.name), ["元フォルダ"])
        XCTAssertEqual(try ["organization.json", "classifications.json"].map { try Data(contentsOf: saved.appendingPathComponent($0)) }, before)
        XCTAssertFalse(FileManager.default.fileExists(atPath: saved.appendingPathComponent("collections.json").path))
        XCTAssertEqual(try Data(contentsOf: body), bodyBytes)
        let recovery = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: saved.appendingPathComponent("test-library-sync/recovery.json"))) as? [String: Any])
        let payload = try XCTUnwrap(Data(base64Encoded: recovery["payload"] as? String ?? ""))
        let contents = try JSONDecoder().decode([String: Data].self, from: payload)
        XCTAssertEqual(Set(contents.keys), Set(["organization.json", "classifications.json"]))
    }
    func testInterruptedManagementRestoreWinsOverPendingSyncApply() async throws {
        let (files, root) = try temporaryStore(); defer { try? FileManager.default.removeItem(at: root) }
        _ = try await files.createFolder(name: "復元対象")
        let original = try await files.managementBackup()
        _ = try await files.createFolder(name: "戻す変更")
        var incoming = OrganizationState<CloudDiagram>(); incoming.folders = [OrganizationFolder(name: "再適用してはいけない受信")]
        try JSONEncoder().encode(incoming).write(to: root.appendingPathComponent("saved/test-sync-apply.json"))
        try original.write(to: root.appendingPathComponent("saved/management-restore.json"))
        let restored = try await files.organization()
        XCTAssertEqual(restored.folders.map(\.name), ["復元対象"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("saved/test-sync-apply.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("saved/management-restore.json").path))
    }
}

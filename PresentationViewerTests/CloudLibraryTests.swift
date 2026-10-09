import XCTest
import PDFKit
import UIKit
@testable import PresentationViewer

final class CloudLibraryTests: XCTestCase {
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
                if file.format == .pdf { XCTAssertEqual(PDFDocument(data: data)?.pageCount, 8) }
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

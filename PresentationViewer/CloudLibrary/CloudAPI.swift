import Foundation

protocol CloudLibraryAPI: Sendable {
    func list(query: String, cursor: String?) async throws -> CloudList
    func list(query: String, cursor: String?, scope: String) async throws -> CloudList
    func detail(id: String, version: Int) async throws -> CloudDetail
    func access(diagram: CloudDiagram, file: CloudFile) async throws -> CloudGrant
    func download(_ grant: CloudGrant) async throws -> Data
}

extension CloudLibraryAPI {
    func list(query: String, cursor: String?, scope: String) async throws -> CloudList {
        let result = try await list(query: query, cursor: cursor)
        let items = result.items.filter { item in
            if query.isEmpty || scope == "all" { return true }
            return (scope == "title" ? item.title : item.tags.joined(separator: " ")).localizedCaseInsensitiveContains(query)
        }
        return CloudList(items: items, nextCursor: result.nextCursor)
    }
}
/// The shipped application uses bundled fixtures only. No AWS or login secrets.
struct MockCloudAPI: CloudLibraryAPI {
    let folder: URL
    init(folder: URL = Bundle.main.url(forResource: "MockLibrary", withExtension: nil)!) { self.folder = folder }
    private func catalog() throws -> [CloudDetail] {
        try JSONDecoder().decode([CloudDetail].self, from: Data(contentsOf: folder.appendingPathComponent("catalog.json")))
    }
    func list(query: String, cursor: String?) async throws -> CloudList {
        guard cursor == nil else { throw CloudError.invalidResponse }
        let items = try catalog().map { try $0.validate(); return $0.diagram }
        return CloudList(items: items.filter { query.isEmpty || ($0.title + " " + $0.tags.joined(separator: " ")).localizedCaseInsensitiveContains(query) }, nextCursor: nil)
    }
    func detail(id: String, version: Int) async throws -> CloudDetail {
        guard let item = try catalog().first(where: { $0.id == id && $0.version == version }) else { throw CloudError.unavailable }
        try item.validate(); return item
    }
    func access(diagram: CloudDiagram, file: CloudFile) async throws -> CloudGrant {
        let detail = try await detail(id: diagram.id, version: diagram.version)
        guard detail.files.contains(file) else { throw CloudError.invalidResponse }
        return CloudGrant(url: URL(string: "mock://library/\(diagram.id)/\(file.name)")!, method: "GET",
                          expiresAt: ISO8601DateFormatter().string(from: Date().addingTimeInterval(300)), expiresIn: 300,
                          contentType: file.contentType, sizeBytes: file.sizeBytes, sha256: file.sha256,
                          fileName: URL(fileURLWithPath: file.name).lastPathComponent)
    }
    func download(_ grant: CloudGrant) async throws -> Data {
        guard grant.url.scheme == "mock", grant.url.host == "library" else { throw CloudError.invalidResponse }
        let parts = grant.url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 2, let item = try catalog().first(where: { $0.id == parts[0] }),
              let file = item.files.first(where: { $0.name == parts.dropFirst().joined(separator: "/") }) else { throw CloudError.unavailable }
        try grant.validate(file: file)
        return try Data(contentsOf: folder.appendingPathComponent(item.id).appendingPathComponent(file.name))
    }
}

/// Short-lived access tokens supplied by PKCE/Keychain or an injected provider.
protocol CloudAccessTokenProvider: Sendable { func accessToken() async throws -> String }
final class NoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
}

struct HTTPSCloudAPI: CloudLibraryAPI {
    let baseURL: URL
    let allowedArtifactHosts: Set<String>
    let tokens: any CloudAccessTokenProvider
    private let session: URLSession
    init(baseURL: URL, allowedArtifactHosts: Set<String>, tokens: any CloudAccessTokenProvider) throws {
        guard baseURL.scheme == "https", baseURL.host != nil, baseURL.user == nil, baseURL.password == nil,
              baseURL.query == nil, baseURL.fragment == nil, !allowedArtifactHosts.isEmpty else { throw CloudError.invalidResponse }
        self.baseURL = baseURL; self.allowedArtifactHosts = allowedArtifactHosts; self.tokens = tokens
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false; config.urlCache = nil; config.timeoutIntervalForRequest = 30
        session = URLSession(configuration: config, delegate: NoRedirects(), delegateQueue: nil)
    }
    private func request<T: Decodable>(_ path: String, query: [URLQueryItem] = [], body: Data? = nil) async throws -> T {
        var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = query.isEmpty ? nil : query
        var request = URLRequest(url: components.url!); request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpMethod = body == nil ? "GET" : "POST"; request.httpBody = body
        request.setValue("Bearer \(try await tokens.accessToken())", forHTTPHeaderField: "Authorization")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        let (bytes, response) = try await session.bytes(for: request)
        guard let response = response as? HTTPURLResponse else { throw CloudError.invalidResponse }
        if response.statusCode == 401 { throw CloudError.authentication }
        guard response.statusCode == 200, response.mimeType == "application/json" else { throw CloudError.unavailable }
        var data = Data()
        for try await byte in bytes { if data.count >= 1_000_000 { throw CloudError.invalidResponse }; data.append(byte) }
        return try JSONDecoder().decode(T.self, from: data)
    }
    func list(query: String, cursor: String?) async throws -> CloudList {
        try await list(query: query, cursor: cursor, scope: "all")
    }
    func list(query: String, cursor: String?, scope: String) async throws -> CloudList {
        var q = [URLQueryItem(name: "q", value: query), URLQueryItem(name: "limit", value: "20"), URLQueryItem(name: "scope", value: scope)]
        if let cursor { q.append(URLQueryItem(name: "cursor", value: cursor)) }
        let result: CloudList = try await request("v1/diagrams", query: q)
        for item in result.items { try item.validate() }; return result
    }
    func detail(id: String, version: Int) async throws -> CloudDetail {
        guard UUID(uuidString: id) != nil, version > 0 else { throw CloudError.invalidResponse }
        let result: CloudDetail = try await request("v1/diagrams/\(id)", query: [URLQueryItem(name: "version", value: String(version))])
        try result.validate(); guard result.id == id && result.version == version else { throw CloudError.invalidResponse }; return result
    }
    func access(diagram: CloudDiagram, file: CloudFile) async throws -> CloudGrant {
        try file.validate(for: diagram)
        let body = try JSONSerialization.data(withJSONObject: ["version": diagram.version, "artifact": file.format.rawValue, "page": file.page, "purpose": "download"])
        let result: CloudGrant = try await request("v1/diagrams/\(diagram.id)/access-url", body: body)
        if cloudDate(result.expiresAt).map({ $0 <= Date() }) == true { throw CloudError.expiredURL }
        try result.validate(file: file); return result
    }
    func download(_ grant: CloudGrant) async throws -> Data {
        guard grant.url.scheme == "https", let host = grant.url.host, allowedArtifactHosts.contains(host),
              grant.url.user == nil, grant.url.password == nil, grant.url.port == nil || grant.url.port == 443,
              grant.sizeBytes > 0, grant.sizeBytes < 20_000_000 else { throw CloudError.invalidResponse }
        if cloudDate(grant.expiresAt).map({ $0 <= Date() }) != false { throw CloudError.expiredURL }
        // Never send API Authorization headers to a signed artifact URL.
        let (bytes, response) = try await session.bytes(from: grant.url)
        guard let response = response as? HTTPURLResponse else { throw CloudError.invalidResponse }
        if response.statusCode == 403 { throw CloudError.expiredURL }
        guard response.statusCode == 200, response.mimeType == grant.contentType else { throw CloudError.unavailable }
        var data = Data()
        for try await byte in bytes { if data.count >= grant.sizeBytes { throw CloudError.integrity }; data.append(byte) }
        guard data.count == grant.sizeBytes else { throw CloudError.integrity }; return data
    }
}

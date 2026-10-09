import Foundation
import SwiftUI
import AuthenticationServices
import Security
import CryptoKit

struct CloudConnection: Codable, Sendable {
    let issuer: URL
    let domain: URL
    let clientID: String
    let api: URL
    let artifactHosts: [String]
    let redirect: String
    func validate() throws {
        guard issuer.absoluteString.range(of: "^https://cognito-idp\\.ap-northeast-1\\.amazonaws\\.com/ap-northeast-1_[A-Za-z0-9]+$", options: .regularExpression) != nil,
              domain.scheme == "https", domain.host?.hasSuffix(".auth.ap-northeast-1.amazoncognito.com") == true,
              domain.path.isEmpty || domain.path == "/", domain.query == nil, domain.fragment == nil,
              domain.user == nil, domain.password == nil, domain.port == nil,
              api.scheme == "https", api.host != nil, api.user == nil, api.password == nil,
              api.query == nil, api.fragment == nil, api.port == nil,
              !clientID.isEmpty, !artifactHosts.isEmpty,
              artifactHosts.allSatisfy({ $0.range(of: "^[a-z0-9.-]+$", options: .regularExpression) != nil }),
              redirect == "presentationviewer://oauth/callback" else { throw CloudError.invalidResponse }
    }
    static func bundled() throws -> CloudConnection {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "CloudConnectionJSON") as? String, !value.isEmpty else { throw CloudError.unavailable }
        let config = try JSONDecoder().decode(Self.self, from: Data(value.utf8)); try config.validate(); return config
    }
    var key: String { cloudHash(Data((issuer.absoluteString + "\n" + clientID + "\n" + api.absoluteString).utf8)) }
}
struct CloudTokens: Codable, Sendable {
    var access: String
    var refresh: String
    var expires: Date
    var subject: String
}
struct CloudKeychain {
    let account: String
    private var query: [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: "com.example.PresentationViewer.oidc", kSecAttrAccount as String: account] }
    func read() throws -> CloudTokens? {
        var q = query; q[kSecReturnData as String] = true; q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?; let status = SecItemCopyMatching(q as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else { throw CloudError.authentication }
        return try JSONDecoder().decode(CloudTokens.self, from: data)
    }
    func write(_ value: CloudTokens) throws {
        let attributes: [String: Any] = [kSecValueData as String: try JSONEncoder().encode(value), kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            guard SecItemAdd(query.merging(attributes) { _, new in new } as CFDictionary, nil) == errSecSuccess else { throw CloudError.authentication }
        } else if status != errSecSuccess { throw CloudError.authentication }
    }
    func delete() throws { let s = SecItemDelete(query as CFDictionary); guard s == errSecSuccess || s == errSecItemNotFound else { throw CloudError.authentication } }
}
func oidcRandom() throws -> String {
    var bytes = [UInt8](repeating: 0, count: 32)
    guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw CloudError.authentication }
    return Data(bytes).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
}
func oidcChallenge(_ verifier: String) -> String {
    Data(SHA256.hash(data: Data(verifier.utf8))).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
}
func oidcCode(_ callback: URL, redirect: String, state: String) throws -> String {
    guard let parts = URLComponents(url: callback, resolvingAgainstBaseURL: false),
          callback.scheme == URL(string: redirect)?.scheme, callback.host == "oauth", callback.path == "/callback", callback.fragment == nil,
          parts.queryItems?.filter({ $0.name == "state" }).count == 1,
          parts.queryItems?.first(where: { $0.name == "state" })?.value == state,
          parts.queryItems?.contains(where: { $0.name == "error" }) != true,
          parts.queryItems?.filter({ $0.name == "code" }).count == 1,
          let code = parts.queryItems?.first(where: { $0.name == "code" })?.value, !code.isEmpty else { throw CloudError.authentication }
    return code
}

@MainActor
final class CloudOIDC: NSObject, ObservableObject, CloudAccessTokenProvider, ASWebAuthenticationPresentationContextProviding {
    let config: CloudConnection
    @Published private(set) var subject: String?
    @Published var message: String?
    @Published private(set) var working = false
    private var tokens: CloudTokens?
    private var browser: ASWebAuthenticationSession?
    private var generation = UUID()
    private var refreshTask: Task<String, Error>?
    private let session: URLSession
    private var keychain: CloudKeychain { CloudKeychain(account: config.key) }
    init(config: CloudConnection, transport: URLSession? = nil) throws {
        try config.validate(); self.config = config
        let settings = URLSessionConfiguration.ephemeral; settings.httpShouldSetCookies = false; settings.urlCache = nil; settings.timeoutIntervalForRequest = 30
        session = transport ?? URLSession(configuration: settings, delegate: NoRedirects(), delegateQueue: nil)
        super.init()
        tokens = try keychain.read(); subject = tokens?.subject
    }
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows).first(where: \.isKeyWindow) ?? ASPresentationAnchor()
    }
    func login() async {
        guard !working else { return }; working = true; defer { working = false }
        do {
            let verifier = try oidcRandom(), state = try oidcRandom()
            var url = URLComponents(url: config.domain.appendingPathComponent("oauth2/authorize"), resolvingAgainstBaseURL: false)!
            url.queryItems = [URLQueryItem(name: "response_type", value: "code"), URLQueryItem(name: "client_id", value: config.clientID), URLQueryItem(name: "redirect_uri", value: config.redirect), URLQueryItem(name: "scope", value: "openid diagram-library/read"), URLQueryItem(name: "state", value: state), URLQueryItem(name: "code_challenge_method", value: "S256"), URLQueryItem(name: "code_challenge", value: oidcChallenge(verifier))]
            let callback: URL = try await withCheckedThrowingContinuation { continuation in
                browser = ASWebAuthenticationSession(url: url.url!, callbackURLScheme: "presentationviewer") { result, error in
                    if let result { continuation.resume(returning: result) } else { continuation.resume(throwing: error ?? CloudError.authentication) }
                }
                browser?.presentationContextProvider = self; browser?.prefersEphemeralWebBrowserSession = true
                if browser?.start() != true { continuation.resume(throwing: CloudError.authentication) }
            }
            browser = nil
            let code = try oidcCode(callback, redirect: config.redirect, state: state)
            let value = try await exchange(["grant_type": "authorization_code", "client_id": config.clientID, "redirect_uri": config.redirect, "code": code, "code_verifier": verifier], old: nil)
            try keychain.write(value); tokens = value; subject = value.subject; message = nil
        } catch { message = "ログインできませんでした。認証と接続設定を確認してください。" }
    }
    private func post(_ path: String, values: [String: String]) async throws -> Data {
        var request = URLRequest(url: config.domain.appendingPathComponent(path)); request.httpMethod = "POST"
        var form = URLComponents(); form.queryItems = values.sorted(by: { $0.key < $1.key }).map { URLQueryItem(name: $0.key, value: $0.value) }
        request.httpBody = Data((form.percentEncodedQuery ?? "").replacingOccurrences(of: "+", with: "%2B").utf8)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200, data.count < 100_000 else { throw CloudError.authentication }
        return data
    }
    private func exchange(_ values: [String: String], old: CloudTokens?) async throws -> CloudTokens {
        struct Reply: Decodable { let access_token: String; let refresh_token: String?; let expires_in: Int; let token_type: String }
        let reply = try JSONDecoder().decode(Reply.self, from: await post("oauth2/token", values: values))
        guard reply.token_type.lowercased() == "bearer", reply.expires_in > 0, reply.expires_in <= 86400, !reply.access_token.isEmpty,
              let refresh = reply.refresh_token ?? old?.refresh, !refresh.isEmpty else { throw CloudError.authentication }
        // Identity comes only from the API after JWT signature and owner authorization, never from unverified JWT decoding.
        var request = URLRequest(url: config.api.appendingPathComponent("v1/me")); request.setValue("Bearer " + reply.access_token, forHTTPHeaderField: "Authorization")
        let (data, response) = try await session.data(for: request)
        struct Identity: Decodable { let issuer: String; let subject: String }
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count < 100_000 else { throw CloudError.authentication }
        let identity = try JSONDecoder().decode(Identity.self, from: data)
        guard identity.issuer == config.issuer.absoluteString, !identity.subject.isEmpty, old == nil || old?.subject == identity.subject else { throw CloudError.authentication }
        return CloudTokens(access: reply.access_token, refresh: refresh, expires: Date().addingTimeInterval(TimeInterval(reply.expires_in)), subject: identity.subject)
    }
    func accessToken() async throws -> String {
        guard let tokens else { throw CloudError.authentication }
        if tokens.expires > Date().addingTimeInterval(60) { return tokens.access }
        if let refreshTask { return try await refreshTask.value }
        let expectedGeneration = generation
        let task = Task { @MainActor in
            let updated = try await self.exchange(["grant_type": "refresh_token", "client_id": self.config.clientID, "refresh_token": tokens.refresh], old: tokens)
            guard self.generation == expectedGeneration, !Task.isCancelled else { throw CloudError.authentication }
            try self.keychain.write(updated); self.tokens = updated; return updated.access
        }
        refreshTask = task; defer { refreshTask = nil }
        return try await task.value
    }
    func logout() async {
        guard !working else { return }; working = true; defer { working = false }
        generation = UUID(); refreshTask?.cancel(); refreshTask = nil
        let old = tokens
        do { try keychain.delete(); tokens = nil; subject = nil } catch { message = "認証情報を削除できませんでした。"; return }
        if let old {
            do { _ = try await post("oauth2/revoke", values: ["client_id": config.clientID, "token": old.refresh]) }
            catch { message = "端末からログアウトしました。通信できずサーバーの失効は未確認です。" }
        }
    }
    var namespace: String? { subject.map { cloudHash(Data((config.key + "\n" + $0).utf8)) } }
}

import SwiftUI

@main
struct PresentationViewerApp: App {
    @UIApplicationDelegateAdaptor(AppOrientationPolicy.self) private var appDelegate
    var body: some Scene {
        WindowGroup { AppLibraryTabs() }
    }
}

@MainActor
private struct AppLibraryTabs: View {
    @AppStorage("cloudProduction") private var production = false
    @State private var settings = false
    private let files = Result { try CloudFileStore.applicationStore() }
    var body: some View {
        TabView {
            Group {
                switch files {
                case .success(let files):
                    if production {
                        switch Result(catching: { try CloudProductionView(onSettings: { settings = true }) }) {
                        case .success(let view): view
                        case .failure: NavigationStack {
                            ContentUnavailableView("本番接続は未設定です", systemImage: "cloud", description: Text("承認後にCloudConnectionJSONを設定してください。"))
                                .toolbar { Button("接続設定") { settings = true } }
                        }
                        }
                    } else { CloudLibraryView(files: files, onSettings: { settings = true }) }
                case .failure: ContentUnavailableView("保存領域を準備できません", systemImage: "externaldrive.badge.exclamationmark")
                }
            }.tabItem { Label("図解ライブラリ", systemImage: "square.stack") }
            LibraryView().tabItem { Label("ローカル資料", systemImage: "folder") }
        }
        .sheet(isPresented: $settings) {
            NavigationStack { Form {
                Toggle("本番APIを使用", isOn: $production)
                Text("オフ：同梱サンプル。オン：設定済みHTTPS APIとCognito。資料と保存領域を分離します。ログアウト後は本番の保存資料を表示せず、同じ利用者で再ログインすると再利用できます。")
            }.navigationTitle("接続設定").toolbar { Button("閉じる") { settings = false } } }
        }
    }
}

@MainActor
final class AppOrientationPolicy: NSObject, UIApplicationDelegate {
    static var mask: UIInterfaceOrientationMask = .portrait
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        Self.mask
    }
}

@MainActor
private struct CloudProductionView: View {
    @StateObject private var auth: CloudOIDC
    let onSettings: () -> Void
    init(onSettings: @escaping () -> Void) throws {
        self.onSettings = onSettings
        let auth = try CloudOIDC(config: CloudConnection.bundled())
        _auth = StateObject(wrappedValue: auth)
    }
    var body: some View {
        Group {
            if let namespace = auth.namespace {
                switch Result(catching: { (try CloudFileStore.applicationStore(namespace: namespace), try HTTPSCloudAPI(baseURL: auth.config.api, allowedArtifactHosts: Set(auth.config.artifactHosts), tokens: auth)) }) {
                case .success(let connection):
                    CloudLibraryView(files: connection.0, api: connection.1, production: true, onSettings: onSettings, onLogout: { Task { await auth.logout() } }).id(namespace)
                case .failure: ContentUnavailableView("接続を準備できません", systemImage: "cloud")
                }
            } else {
                NavigationStack {
                    VStack(spacing: 20) {
                        ContentUnavailableView("クラウド資料にログイン", systemImage: "person.crop.circle", description: Text("Cognitoで認証後、許可された資料を取得します。"))
                        Button("ログイン") { Task { await auth.login() } }.buttonStyle(.borderedProminent).disabled(auth.working)
                    }.navigationTitle("図解ライブラリ").toolbar { Button("接続設定", action: onSettings) }
                }
            }
        }
        .alert("認証", isPresented: Binding(get: { auth.message != nil }, set: { if !$0 { auth.message = nil } })) { Button("OK") { auth.message = nil } } message: { Text(auth.message ?? "") }
    }
}

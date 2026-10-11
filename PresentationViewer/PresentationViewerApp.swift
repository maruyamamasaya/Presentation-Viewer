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
    @StateObject private var connection = CloudConnectionState()
    @Environment(\.scenePhase) private var scenePhase
    private let files = Result { try CloudFileStore.applicationStore() }
    var body: some View {
        TabView {
            ForEach(CloudLibraryKind.allCases, id: \.rawValue) { kind in
            Group {
                switch files {
                case .success(let files):
                    if production {
                        CloudConnectionGate(connection: connection, kind: kind, onSettings: { settings = true })
                    } else { CloudLibraryView(files: files, kind: kind, onSettings: { settings = true }) }
                case .failure: ContentUnavailableView("保存領域を準備できません", systemImage: "externaldrive.badge.exclamationmark")
                }
            }.tabItem { Label(kind.title, systemImage: kind == .presentations ? "square.stack" : "rectangle.on.rectangle") }
            }
            LibraryView().tabItem { Label("ローカル資料", systemImage: "folder") }
        }
        .task { connection.initialize() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { connection.initialize(); connection.auth?.restoreSession() } }
        .sheet(isPresented: $settings) {
            NavigationStack { Form {
                Toggle("本番APIを使用", isOn: $production)
                Text("オフ：同梱サンプル。オン：設定済みHTTPS APIとCognito。資料と保存領域を分離します。ログアウト後は本番の保存資料を表示せず、同じ利用者で再ログインすると再利用できます。")
            }.navigationTitle("接続設定").toolbar { Button("閉じる") { settings = false } } }
        }
    }
}

@MainActor
final class CloudConnectionState: ObservableObject {
    @Published private(set) var auth: CloudOIDC?
    @Published private(set) var failed = false
    private let makeAuth: @MainActor () throws -> CloudOIDC
    init(makeAuth: (@MainActor () throws -> CloudOIDC)? = nil, startImmediately: Bool = true) {
        self.makeAuth = makeAuth ?? { try CloudOIDC(config: CloudConnection.bundled()) }
        if startImmediately { initialize() }
    }
    func initialize() {
        guard auth == nil else { return }
        do {
            auth = try makeAuth(); failed = false
            #if DEBUG
            print("Cloud startup: configured=true, savedLogin=\(auth?.namespace != nil)")
            #endif
        }
        catch {
            failed = true
            #if DEBUG
            print("Cloud startup: configured=false, error=\(type(of: error))")
            #endif
        }
    }
}

@MainActor
private struct CloudConnectionGate: View {
    @ObservedObject var connection: CloudConnectionState
    let kind: CloudLibraryKind
    let onSettings: () -> Void
    var body: some View {
        Group {
            if let auth = connection.auth {
                CloudProductionView(auth: auth, kind: kind, onSettings: onSettings)
            } else {
                NavigationStack {
                    VStack(spacing: 20) {
                        ContentUnavailableView("接続設定を読み込めません", systemImage: "cloud")
                        Button("再試行") { connection.initialize() }
                    }.toolbar { Button("接続設定", action: onSettings) }
                }
            }
        }.task { connection.initialize() }
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
    @ObservedObject var auth: CloudOIDC
    let kind: CloudLibraryKind
    let onSettings: () -> Void
    var body: some View {
        Group {
            if let namespace = auth.namespace {
                switch Result(catching: { (try CloudFileStore.applicationStore(namespace: namespace), try HTTPSCloudAPI(baseURL: auth.config.api, allowedArtifactHosts: Set(auth.config.artifactHosts), tokens: auth)) }) {
                case .success(let connection):
                    CloudLibraryView(files: connection.0, kind: kind, api: connection.1, production: true, onSettings: onSettings, onLogout: { Task { await auth.logout() } }).id(namespace)
                case .failure: ContentUnavailableView("接続を準備できません", systemImage: "cloud")
                }
            } else {
                NavigationStack {
                    VStack(spacing: 20) {
                        ContentUnavailableView("クラウド資料にログイン", systemImage: "person.crop.circle", description: Text("Cognitoで認証後、許可された資料を取得します。"))
                        Button("ログイン") { Task { await auth.login() } }.buttonStyle(.borderedProminent).disabled(auth.working)
                    }.navigationTitle(kind.title).toolbar { Button("接続設定", action: onSettings) }
                }
            }
        }
        .alert("認証", isPresented: Binding(get: { auth.message != nil }, set: { if !$0 { auth.message = nil } })) { Button("OK") { auth.message = nil } } message: { Text(auth.message ?? "") }
    }
}

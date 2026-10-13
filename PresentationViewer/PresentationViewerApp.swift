import SwiftUI

/// Prefer landscape at launch while keeping normal screens freely rotatable.
private struct LibraryOrientationAnchor: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> LibraryOrientationController {
        LibraryOrientationController()
    }

    func updateUIViewController(_ controller: LibraryOrientationController, context: Context) {}
}

private final class LibraryOrientationController: UIViewController {
    private var requestedInitialOrientation = false

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !requestedInitialOrientation, let scene = view.window?.windowScene else { return }
        requestedInitialOrientation = true
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: .landscape)) { _ in
            // Windowed iPad layouts may keep their current orientation.
        }
    }
}

@main
struct PresentationViewerApp: App {
    @UIApplicationDelegateAdaptor(AppOrientationPolicy.self) private var appDelegate
    var body: some Scene {
        WindowGroup {
            AppLibraryTabs()
                .background(LibraryOrientationAnchor().frame(width: 0, height: 0))
        }
    }
}

@MainActor
private struct AppLibraryTabs: View {
    @AppStorage("cloudProduction") private var production = false
    @State private var settings = false
    @State private var connectionDrawer = false
    @State private var selectedTab = CloudLibraryKind.presentations.rawValue
    @StateObject private var connection = CloudConnectionState()
    @Environment(\.scenePhase) private var scenePhase
    private let files = Result { try CloudFileStore.applicationStore() }
    var body: some View {
        TabView(selection: $selectedTab) {
            ForEach(CloudLibraryKind.allCases, id: \.rawValue) { kind in
            Group {
                switch files {
                case .success(let files):
                    if production {
                        CloudConnectionGate(connection: connection, kind: kind, onSettings: { settings = true })
                    } else { CloudLibraryView(files: files, kind: kind, onSettings: { settings = true }) }
                case .failure: ContentUnavailableView("保存領域を準備できません", systemImage: "externaldrive.badge.exclamationmark")
                }
            }.toolbar(UIDevice.current.userInterfaceIdiom == .phone ? .hidden : .visible, for: .tabBar).tag(kind.rawValue).tabItem { Label(kind.title, systemImage: kind == .presentations ? "square.stack" : "rectangle.on.rectangle") }
            }
            LibraryView().toolbar(UIDevice.current.userInterfaceIdiom == .phone ? .hidden : .visible, for: .tabBar).tag("local").tabItem { Label("ローカル資料", systemImage: "folder") }
        }
        .toolbar(UIDevice.current.userInterfaceIdiom == .phone ? .hidden : .visible, for: .tabBar)
        .environment(\.libraryDestination, $selectedTab)
        .overlay {
            if UIDevice.current.userInterfaceIdiom == .phone && selectedTab != "local" && (production && connection.auth?.namespace == nil || (try? files.get()) == nil) {
                LibraryDrawer(isPresented: $connectionDrawer) {
                    Button("接続設定") { connectionDrawer = false; settings = true }.frame(minHeight: 44)
                }.environment(\.libraryDestination, $selectedTab)
            }
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
    static var mask: UIInterfaceOrientationMask = .allButUpsideDown
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
                    CloudLibraryView(files: connection.0, kind: kind, api: connection.1, production: true, onSettings: onSettings, onLogout: { Task { await auth.logout() } }, onReauthenticate: { Task { await auth.login() } }).id("\(namespace)-\(auth.loginRevision)")
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

private struct LibraryDestinationKey: EnvironmentKey {
    static let defaultValue: Binding<String> = .constant(CloudLibraryKind.presentations.rawValue)
}
extension EnvironmentValues {
    var libraryDestination: Binding<String> {
        get { self[LibraryDestinationKey.self] }
        set { self[LibraryDestinationKey.self] = newValue }
    }
}

/// A temporary library drawer; readers use a separate, reserved slide rail.
struct LibraryDrawer<Content: View>: View {
    @Binding var isPresented: Bool
    var filterSummary = ""
    @Environment(\.libraryDestination) private var destination
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ViewBuilder let content: () -> Content
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .trailing) {
                if isPresented {
                    Button { close() } label: { Color.black.opacity(0.32).ignoresSafeArea() }
                        .buttonStyle(.plain).accessibilityLabel("メニューを閉じる")
                    VStack(spacing: 0) {
                        HStack {
                            Text("ライブラリ").font(.headline)
                            Spacer()
                            Button(action: close) { Image(systemName: "xmark").frame(width: 44, height: 44) }
                                .accessibilityLabel("メニューを閉じる")
                        }.padding(.horizontal, 16)
                        ScrollView {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(CloudLibraryKind.allCases, id: \.rawValue) { kind in
                                    destinationButton(kind.title, icon: kind == .presentations ? "square.stack" : "rectangle.on.rectangle", value: kind.rawValue)
                                }
                                destinationButton("ローカル資料", icon: "folder", value: "local")
                                Divider()
                                content()
                            }.padding(16)
                        }
                    }
                    .frame(width: min(dynamicTypeSize.isAccessibilitySize ? 380 : 320, geometry.size.width * 0.88))
                    .background(.regularMaterial)
                    .transition(.move(edge: .trailing))
                    .simultaneousGesture(DragGesture().onEnded { if $0.translation.width > 60 && abs($0.translation.height) < 40 { close() } })
                } else {
                    Color.clear.frame(width: 16).contentShape(Rectangle())
                        .gesture(DragGesture().onEnded { if $0.translation.width < -50 { withAnimation { isPresented = true } } })
                        .accessibilityHidden(true)
                    VStack { Spacer();
                        Button { withAnimation { isPresented = true } } label: {
                            Image(systemName: "line.3.horizontal")
                                .font(.system(size: 19, weight: .medium))
                                .frame(width: 48, height: 48)
                                .background(.regularMaterial, in: Circle())
                                .overlay(alignment: .topTrailing) {
                                    if !filterSummary.isEmpty {
                                        Circle().fill(Color.accentColor).frame(width: 8, height: 8).padding(3)
                                    }
                                }
                                .shadow(color: .black.opacity(0.15), radius: 5, y: 2)
                        }.buttonStyle(.plain).accessibilityLabel("ライブラリメニューを開く、\(destinationTitle)\(filterSummary.isEmpty ? "" : "、" + filterSummary)")
                        .padding(.trailing, 12).padding(.bottom, 8)
                    }
                }
            }.frame(width: geometry.size.width, height: geometry.size.height, alignment: .trailing)
        }
    }
    private var destinationTitle: String {
        CloudLibraryKind.allCases.first { $0.rawValue == destination.wrappedValue }?.title ?? "ローカル資料"
    }
    private func close() { withAnimation { isPresented = false } }
    private func destinationButton(_ title: String, icon: String, value: String) -> some View {
        Button { destination.wrappedValue = value; close() } label: {
            HStack {
                Label(title, systemImage: icon)
                Spacer()
                if destination.wrappedValue == value { Image(systemName: "checkmark") }
            }.frame(minHeight: 44).contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(destination.wrappedValue == value ? .isSelected : [])
    }
}

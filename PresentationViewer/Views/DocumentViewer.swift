import SwiftUI
import QuickLook

@MainActor
struct DocumentViewer: View {
    let document: OpenedDocument
    @StateObject private var pdfSession: PDFReadingSession
    @ObservedObject private var external = ExternalDisplayCoordinator.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var toolbarVisible = true
    @State private var thumbnailPreference: Bool?
    @State private var imagePresenting = false
    @StateObject private var orientation = ViewerOrientationController()

    init(document: OpenedDocument) {
        self.document = document
        _pdfSession = StateObject(wrappedValue: PDFReadingSession(url: document.format == .pdf ? document.url : nil))
    }

    private var isImage: Bool { [.png, .jpg, .jpeg].contains(document.format) }
    private var canPresent: Bool { isImage || (document.format == .pdf && pdfSession.pageCount > 0) }
    private var presenting: Bool { pdfSession.isPresenting || imagePresenting }
    private var thumbnailsVisible: Bool { thumbnailPreference ?? (horizontalSizeClass == .regular) }

    var body: some View {
        NavigationStack {
            Group {
                switch document.format {
                case .pptx:
                    if QLPreviewController.canPreview(document.url as NSURL) {
                        QuickLookView(url: document.url)
                    } else {
                        ViewerErrorView(message: "このPPTXはQuick Lookで表示できません。PDFに書き出してお試しください。")
                    }
                case .pdf:
                    PDFDocumentView(session: pdfSession, thumbnailsVisible: thumbnailsVisible)
                case .svg: SVGDocumentView(url: document.url)
                case .png, .jpg, .jpeg:
                    ImageDocumentView(url: document.url, presenting: imagePresenting, onTap: toggleControls)
                }
            }
            .background(presenting ? Color.black : Color(uiColor: .systemBackground))
            .navigationTitle(document.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("閉じる") { dismiss() }.keyboardShortcut(.cancelAction)
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    orientationMenu
                    if document.format == .pdf, pdfSession.pageCount > 0 {
                        Button {
                            thumbnailPreference = !thumbnailsVisible
                        } label: {
                            Label(thumbnailsVisible ? "ページ一覧を隠す" : "ページ一覧を表示", systemImage: "square.grid.2x2")
                        }
                    }
                    Menu {
                        Button("プレゼンを開始（PDF・画像）", systemImage: "play.rectangle") { beginPresentation() }
                            .disabled(!canPresent)
                        if document.format == .pdf {
                            Label(external.connected ? "外部画面に接続済み" : "外部画面未接続", systemImage: "display")
                        }
                    } label: { Label("プレゼン", systemImage: "play.rectangle") }
                    if isImage {
                        Button(action: toggleControls) {
                            Label("ツールバーを隠す", systemImage: "arrow.up.left.and.arrow.down.right")
                        }
                        .keyboardShortcut("t", modifiers: .command)
                    }
                }
            }
            .toolbar(toolbarVisible && !presenting ? .visible : .hidden, for: .navigationBar)
            .safeAreaInset(edge: .top, spacing: 0) {
                if presenting {
                    // Remains reachable with touch, pointer, VoiceOver and Escape.
                    HStack {
                        Button("プレゼンを終了", systemImage: "xmark") { endPresentation() }
                            .keyboardShortcut(.cancelAction)
                        orientationMenu
                    }
                        .buttonStyle(.bordered).controlSize(.large)
                        .foregroundStyle(.white).tint(.white)
                        .padding(8).background(.black.opacity(0.65), in: Capsule()).padding(8)
                } else if !toolbarVisible {
                    HStack {
                        Button("閉じる") { dismiss() }.keyboardShortcut(.cancelAction)
                        orientationMenu
                        Button(action: toggleControls) {
                            Label("ツールバーを表示", systemImage: "arrow.down.right.and.arrow.up.left").labelStyle(.iconOnly)
                        }
                        .keyboardShortcut("t", modifiers: .command)
                    }
                    .buttonStyle(.bordered).controlSize(.large)
                    .padding(8).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)).padding(8)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if document.format == .pdf, presenting {
                    HStack(spacing: 24) {
                        Button { pdfSession.movePage(-1) } label: { Label("前のページ", systemImage: "chevron.left") }
                            .keyboardShortcut(.leftArrow, modifiers: [])
                            .disabled(pdfSession.pageIndex == 0)
                        Text("\(pdfSession.pageIndex + 1) / \(pdfSession.pageCount)")
                            .monospacedDigit().accessibilityLabel("\(pdfSession.pageCount)ページ中\(pdfSession.pageIndex + 1)ページ")
                        Button { pdfSession.movePage(1) } label: { Label("次のページ", systemImage: "chevron.right") }
                            .keyboardShortcut(.rightArrow, modifiers: [])
                            .disabled(pdfSession.pageIndex + 1 >= pdfSession.pageCount)
                    }
                    .labelStyle(.iconOnly).buttonStyle(.bordered).controlSize(.large)
                    .foregroundStyle(.white).tint(.white)
                    .padding(8).background(.black.opacity(0.65), in: Capsule()).padding(8)
                }
            }
        }
        .statusBarHidden(presenting)
        .background(ViewerOrientationAnchor(controller: orientation).frame(width: 0, height: 0))
        .alert("画面の向きを変更できません", isPresented: Binding(
            get: { orientation.errorMessage != nil },
            set: { if !$0 { orientation.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { orientation.errorMessage = nil }
        } message: {
            Text(orientation.errorMessage ?? "")
        }
        .onDisappear { external.end(pdfSession) }
    }

    private var orientationMenu: some View {
        Menu {
            Button("横画面にする", systemImage: "rectangle") { orientation.request(.landscape) }
            Button("縦画面にする", systemImage: "rectangle.portrait") { orientation.request(.portrait) }
        } label: {
            Label("画面の向き", systemImage: "rotate.right")
        }
    }

    private func toggleControls() {
        withAnimation(.easeInOut(duration: 0.2)) {
            if !presenting { toolbarVisible.toggle() }
        }
    }

    private func beginPresentation() {
        guard canPresent else { return }
        if document.format == .pdf {
            pdfSession.isPresenting = true
            external.begin(pdfSession)
        } else { imagePresenting = true }
    }

    private func endPresentation() {
        external.end(pdfSession)
        pdfSession.isPresenting = false
        imagePresenting = false
        toolbarVisible = true
    }
}

/// Resolve the scene from the viewer itself so external displays are never rotated.
@MainActor
private final class ViewerOrientationController: ObservableObject {
    weak var viewController: UIViewController?
    @Published var errorMessage: String?

    func request(_ orientations: UIInterfaceOrientationMask) {
        guard let viewController, let scene = viewController.view.window?.windowScene else {
            errorMessage = "画面の準備ができていません。もう一度お試しください。"
            return
        }
        errorMessage = nil
        viewController.setNeedsUpdateOfSupportedInterfaceOrientations()
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: orientations)) { [weak self] _ in
            Task { @MainActor in
                self?.errorMessage = "この表示状態では画面の向きを変更できません。iPadでは全画面で開いてからお試しください。"
            }
        }
    }
}

private struct ViewerOrientationAnchor: UIViewControllerRepresentable {
    let controller: ViewerOrientationController

    func makeUIViewController(context: Context) -> UIViewController {
        let viewController = UIViewController()
        controller.viewController = viewController
        return viewController
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}

struct ViewerErrorView: View {
    let message: String
    var body: some View {
        ContentUnavailableView("表示できません", systemImage: "doc.badge.exclamationmark", description: Text(message))
    }
}

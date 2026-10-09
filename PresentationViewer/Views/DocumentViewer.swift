import SwiftUI
import QuickLook

@MainActor
struct DocumentViewer: View {
    let document: OpenedDocument
    let libraryActions: AnyView?
    let imagePages: ImagePageControls?
    @StateObject private var pdfSession: PDFReadingSession
    @ObservedObject private var external = ExternalDisplayCoordinator.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var toolbarVisible = true
    @State private var thumbnailPreference: Bool?
    @State private var imagePresenting = false
    @StateObject private var orientation = ViewerOrientationController()

    init(document: OpenedDocument, libraryActions: AnyView? = nil, imagePages: ImagePageControls? = nil) {
        self.document = document
        self.libraryActions = libraryActions
        self.imagePages = imagePages
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
                case .svg: ViewerErrorView(message: "SVGの表示は終了しました。PDFまたはPNGを使用してください。")
                case .png, .jpg, .jpeg:
                    ImageDocumentView(url: document.url, presenting: imagePresenting, onTap: toggleControls).id(document.url)
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
                    if let libraryActions {
                        libraryActions
                        Menu {
                            if document.format == .pdf, pdfSession.pageCount > 0 {
                                Button(thumbnailsVisible ? "ページ一覧を隠す" : "ページ一覧を表示") { thumbnailPreference = !thumbnailsVisible }
                            }
                            Button("プレゼンを開始") { beginPresentation() }.disabled(!canPresent)
                        } label: { Label("表示設定", systemImage: "slider.horizontal.3") }
                    } else {
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
            }
            .toolbar(toolbarVisible && !presenting ? .visible : .hidden, for: .navigationBar)
            .ignoresSafeArea(presenting ? .all : [], edges: .all)
            .overlay(alignment: .leading) {
                if hasPages { pageButton(previous: true).padding(.leading, 8) }
            }
            .overlay(alignment: .trailing) {
                if hasPages { pageButton(previous: false).padding(.trailing, 8) }
            }
            .overlay(alignment: .topTrailing) {
                if presenting {
                    Button(action: endPresentation) { Image(systemName: "xmark") }
                        .accessibilityLabel("プレゼンを終了").keyboardShortcut(.cancelAction)
                        .buttonStyle(PresentationSideButtonStyle())
                        .foregroundStyle(.white).background(.black.opacity(0.45), in: Capsule())
                        .padding(.trailing, 8).padding(.top, 8)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) {
                if !presenting && !toolbarVisible {
                    HStack {
                        Button("閉じる") { dismiss() }.keyboardShortcut(.cancelAction)
                        Button { toolbarVisible = true } label: { Label("操作を表示", systemImage: "ellipsis") }
                    }.buttonStyle(.bordered).padding(8).background(.regularMaterial)
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
        .onDisappear { external.end(pdfSession); orientation.request(.portrait) }
    }

    private var hasPages: Bool {
        presenting && (document.format == .pdf || imagePages != nil)
    }

    private func pageButton(previous: Bool) -> some View {
        Button {
            if document.format == .pdf { pdfSession.movePage(previous ? -1 : 1) }
            else if previous { imagePages?.previous() }
            else { imagePages?.next() }
        } label: { Image(systemName: previous ? "chevron.left" : "chevron.right") }
        .accessibilityLabel(previous ? "前のページ" : "次のページ")
        .keyboardShortcut(previous ? .leftArrow : .rightArrow, modifiers: [])
        .disabled(document.format == .pdf
            ? (previous ? pdfSession.pageIndex == 0 : pdfSession.pageIndex + 1 >= pdfSession.pageCount)
            : (previous ? imagePages?.canPrevious != true : imagePages?.canNext != true))
        .font(.system(size: 17, weight: .semibold))
        .buttonStyle(PresentationSideButtonStyle())
        .foregroundStyle(.white).background(.black.opacity(0.45), in: Capsule())
    }

    private func toggleControls() {
        withAnimation(.easeInOut(duration: 0.2)) {
            if !presenting { toolbarVisible.toggle() }
        }
    }

    private func beginPresentation() {
        guard canPresent else { return }
        orientation.request(.landscape)
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
        orientation.request(.portrait)
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
        AppOrientationPolicy.mask = orientations
        scene.windows.filter { $0.isKeyWindow }.first?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
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

private struct PresentationSideButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        // Generous side controls; the full rectangle participates in hit testing.
        configuration.label.frame(width: 60, height: 56)
            .contentShape(Rectangle())
            .background(configuration.isPressed ? Color.white.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct ImagePageControls {
    let canPrevious: Bool
    let canNext: Bool
    let previous: () -> Void
    let next: () -> Void
}

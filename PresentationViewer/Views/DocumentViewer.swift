import SwiftUI
import QuickLook
import PDFKit

@MainActor
struct DocumentViewer: View {
    let document: OpenedDocument
    let libraryActions: AnyView?
    let imagePages: ImagePageControls?
    let externalPageNavigation: Bool
    let displayIntent: ViewerDisplayIntent
    @StateObject private var pdfSession: PDFReadingSession
    @ObservedObject private var external = ExternalDisplayCoordinator.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var toolbarVisible = true
    @State private var thumbnailPreference: Bool?
    @State private var imagePresenting = false
    @StateObject private var orientation = ViewerOrientationController()

    init(document: OpenedDocument, libraryActions: AnyView? = nil, imagePages: ImagePageControls? = nil, displayIntent: ViewerDisplayIntent = .presentation, externalPageNavigation: Bool = false) {
        self.document = document
        self.libraryActions = libraryActions
        self.imagePages = imagePages
        self.externalPageNavigation = externalPageNavigation
        self.displayIntent = displayIntent
        _pdfSession = StateObject(wrappedValue: PDFReadingSession(url: document.format == .pdf ? document.url : nil))
    }

    private var isImage: Bool { [.png, .jpg, .jpeg].contains(document.format) }
    private var canPresent: Bool { isImage || (document.format == .pdf && pdfSession.pageCount > 0) }
    private var presenting: Bool { pdfSession.isPresenting || imagePresenting }
    private var startTitle: String { displayIntent == .illustration ? "全画面表示" : "プレゼンを開始" }
    private var endTitle: String { displayIntent == .illustration ? "全画面表示を終了" : "プレゼンを終了" }
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
                            Button(startTitle) { beginPresentation() }.disabled(!canPresent)
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
                        Button(startTitle, systemImage: displayIntent == .illustration ? "arrow.up.left.and.arrow.down.right" : "play.rectangle") { beginPresentation() }
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
            .overlay {
                if !presenting && toolbarVisible && canPresent {
                    Button(action: beginPresentation) {
                        Image(systemName: displayIntent == .illustration ? "arrow.up.left.and.arrow.down.right" : "play.fill")
                            .font(.system(size: 28, weight: .semibold))
                            .frame(width: 76, height: 76)
                            .background(.regularMaterial, in: Circle())
                            .overlay(Circle().strokeBorder(.primary.opacity(0.12)))
                            .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(startTitle)
                }
            }
            .overlay {
                if presenting && displayIntent == .presentation {
                    GeometryReader { geometry in
                        let safe = geometry.safeAreaInsets
                        slideSidebar
                            .frame(width: 64, height: max(44, geometry.size.height - safe.top - safe.bottom - 104))
                            .position(x: safe.leading + 38, y: safe.top + (geometry.size.height - safe.top - safe.bottom - 104) / 2 + 8)
                        if hasPages {
                            pageButton(previous: true)
                                .position(x: safe.leading + 30, y: geometry.size.height - safe.bottom - 30)
                            pageButton(previous: false)
                                .position(x: geometry.size.width - safe.trailing - 30, y: geometry.size.height - safe.bottom - 30)
                        }
                        Text("\(currentPage + 1) / \(totalPages)")
                            .font(.system(size: 12, weight: .medium).monospacedDigit())
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .foregroundStyle(.white.opacity(0.6))
                            .background(.black.opacity(0.12), in: Capsule())
                            .position(x: geometry.size.width / 2, y: geometry.size.height - safe.bottom - 26)
                            .allowsHitTesting(false)
                    }
                } else if hasPages {
                    HStack { pageButton(previous: true); Spacer(); pageButton(previous: false) }.padding(.horizontal, 8)
                }
            }
            .overlay(alignment: .topTrailing) {
                if presenting {
                    Button(action: endPresentation) { Image(systemName: "xmark") }
                        .accessibilityLabel(endTitle).keyboardShortcut(.cancelAction)
                        .buttonStyle(PresentationSideButtonStyle())
                        .foregroundStyle(.white.opacity(0.6)).background(.black.opacity(0.12), in: Capsule())
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
        .onDisappear { external.end(pdfSession); orientation.request(.landscape, allowingRotation: true) }
    }

    private var hasPages: Bool {
        if externalPageNavigation { return imagePages != nil }
        return presenting && displayIntent == .presentation && (document.format == .pdf || imagePages != nil)
    }

    private var currentPage: Int { document.format == .pdf ? pdfSession.pageIndex : imagePages?.pageIndex ?? 0 }
    private var totalPages: Int { document.format == .pdf ? pdfSession.pageCount : imagePages?.pageCount ?? 1 }

    private var slideSidebar: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical) {
                LazyVStack(spacing: 6) {
                    ForEach(0..<totalPages, id: \.self) { index in
                        Button {
                            if document.format == .pdf { pdfSession.selectPage(index) }
                            else { imagePages?.selectPage?(index) }
                        } label: {
                            ZStack {
                                if document.format != .pdf {
                                    PresentationImageThumbnail(index: index, currentURL: index == currentPage ? document.url : nil, load: imagePages?.thumbnail)
                                }
                                if let page = pdfSession.document?.page(at: index) {
                                    Image(uiImage: page.thumbnail(of: CGSize(width: 112, height: 64), for: .mediaBox))
                                        .resizable().scaledToFit().opacity(0.28)
                                }
                                Text("\(index + 1)").font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.65))
                                    .shadow(color: .black.opacity(0.6), radius: 1)
                            }
                            .frame(width: 56, height: 44)
                            .background(.black.opacity(0.08), in: RoundedRectangle(cornerRadius: 5))
                            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.white.opacity(index == currentPage ? 0.6 : 0.12), lineWidth: index == currentPage ? 1.5 : 0.5))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).id(index)
                        .disabled(document.format != .pdf && imagePages?.selectPage == nil)
                        .accessibilityLabel("スライド \(index + 1)")
                        .accessibilityAddTraits(index == currentPage ? .isSelected : [])
                    }
                }.padding(4)
            }
            .scrollIndicators(.hidden)
            .background(.black.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
            .onAppear { proxy.scrollTo(currentPage, anchor: .center) }
            .onChange(of: currentPage) { _, index in
                withAnimation(.easeInOut(duration: 0.2)) { proxy.scrollTo(index, anchor: .center) }
            }
        }
    }

    private func pageButton(previous: Bool) -> some View {
        Button {
            if document.format == .pdf && !externalPageNavigation { pdfSession.movePage(previous ? -1 : 1) }
            else if previous { imagePages?.previous() }
            else { imagePages?.next() }
        } label: { Image(systemName: previous ? "chevron.left" : "chevron.right") }
        .accessibilityLabel(previous ? "前のページ" : "次のページ")
        .keyboardShortcut(previous ? .leftArrow : .rightArrow, modifiers: [])
        .disabled(document.format == .pdf && !externalPageNavigation
            ? (previous ? pdfSession.pageIndex == 0 : pdfSession.pageIndex + 1 >= pdfSession.pageCount)
            : (previous ? imagePages?.canPrevious != true : imagePages?.canNext != true))
        .font(.system(size: 17, weight: .semibold))
        .buttonStyle(PresentationSideButtonStyle())
        .foregroundStyle(.white.opacity(0.6)).background(.black.opacity(0.12), in: Capsule())
    }

    private func toggleControls() {
        withAnimation(.easeInOut(duration: 0.2)) {
            if !presenting { toolbarVisible.toggle() }
        }
    }

    private func beginPresentation() {
        guard canPresent else { return }
        let contentSize: CGSize?
        if document.format == .pdf {
            contentSize = pdfSession.document?.page(at: pdfSession.pageIndex)?.bounds(for: .mediaBox).size
        } else {
            contentSize = UIImage(contentsOfFile: document.url.path)?.size
        }
        orientation.request(displayIntent.orientation(for: contentSize))
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
        orientation.request(.landscape, allowingRotation: true)
    }
}

/// Resolve the scene from the viewer itself so external displays are never rotated.
@MainActor
private final class ViewerOrientationController: ObservableObject {
    weak var viewController: UIViewController?
    @Published var errorMessage: String?

    func request(_ orientations: UIInterfaceOrientationMask, allowingRotation: Bool = false) {
        AppOrientationPolicy.mask = allowingRotation ? .allButUpsideDown : orientations
        guard let viewController, let scene = viewController.view.window?.windowScene else {
            errorMessage = "画面の準備ができていません。もう一度お試しください。"
            return
        }
        errorMessage = nil
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
        configuration.label.frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .background(configuration.isPressed ? Color.white.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 16))
    }
}

struct ImagePageControls {
    let canPrevious: Bool
    let canNext: Bool
    let previous: () -> Void
    let next: () -> Void
    var pageIndex: Int = 0
    var pageCount: Int = 1
    var selectPage: ((Int) -> Void)? = nil
    var thumbnail: ((Int) async -> UIImage?)? = nil
}

private struct PresentationImageThumbnail: View {
    let index: Int
    let currentURL: URL?
    let load: ((Int) async -> UIImage?)?
    @State private var image: UIImage?
    var body: some View {
        Group {
            if let image {
                Image(uiImage: image).resizable().scaledToFit().opacity(0.28)
            }
        }.task(id: currentURL) {
            if let currentURL { image = UIImage(contentsOfFile: currentURL.path) }
            else { image = await load?(index) }
        }
    }
}

/// Library classification determines the action; page count alone does not identify illustrations.
enum ViewerDisplayIntent {
    case presentation, illustration

    func orientation(for size: CGSize?) -> UIInterfaceOrientationMask {
        guard self == .illustration else { return .landscape }
        guard let size, size.width > 0, size.height > 0 else { return .portrait }
        return size.width > size.height ? .landscape : .portrait
    }
}

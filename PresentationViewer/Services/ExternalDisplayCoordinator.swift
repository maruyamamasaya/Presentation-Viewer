import SwiftUI
import UIKit
import PDFKit
import Combine

// The only process-wide state is the currently presented PDF and external scenes.
// Main app windows remain single-window to avoid competing presenters.
@MainActor
final class ExternalDisplayCoordinator: ObservableObject {
    static let shared = ExternalDisplayCoordinator()
    @Published private(set) var session: PDFReadingSession?
    @Published private(set) var connected = false
    private var scenes = Set<String>()

    func begin(_ session: PDFReadingSession) { self.session = session }
    func end(_ session: PDFReadingSession) {
        if self.session === session { self.session = nil }
    }
    func didConnect(_ id: String) { scenes.insert(id); connected = !scenes.isEmpty }
    func didDisconnect(_ id: String) { scenes.remove(id); connected = !scenes.isEmpty }
}

@MainActor
final class ExternalDisplaySceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    private weak var displayScene: UIWindowScene?
    private var subscription: AnyCancellable?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard session.role == .windowExternalDisplayNonInteractive,
              let windowScene = scene as? UIWindowScene else { return }
        displayScene = windowScene
        ExternalDisplayCoordinator.shared.didConnect(session.persistentIdentifier)
        subscription = ExternalDisplayCoordinator.shared.$session.sink { [weak self] reading in
            self?.show(reading)
        }
    }

    private func show(_ session: PDFReadingSession?) {
        // No custom window while browsing: leave mirroring/extended desktop to iPadOS.
        window?.isHidden = true
        window?.windowScene = nil
        window = nil
        guard let session, session.isPresenting, session.pageCount > 0,
              let displayScene else { return }
        let output = UIWindow(windowScene: displayScene)
        output.rootViewController = UIHostingController(rootView: ExternalPDFSlide(session: session))
        output.backgroundColor = .black
        output.isUserInteractionEnabled = false
        output.isHidden = false
        window = output
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        subscription = nil
        window?.isHidden = true
        window?.windowScene = nil
        window = nil
        displayScene = nil
        ExternalDisplayCoordinator.shared.didDisconnect(scene.session.persistentIdentifier)
    }
}

private struct ExternalPDFSlide: View {
    @ObservedObject var session: PDFReadingSession
    var body: some View {
        ExternalPDFCanvas(session: session)
            .background(.black).ignoresSafeArea()
    }
}

private struct ExternalPDFCanvas: UIViewRepresentable {
    @ObservedObject var session: PDFReadingSession
    func makeUIView(context: Context) -> ResizingPDFView {
        let view = ResizingPDFView()
        view.backgroundColor = .black
        view.displayMode = .singlePage
        view.displaysPageBreaks = false
        view.pageShadowsEnabled = false
        view.autoScales = true
        view.document = session.document
        view.isUserInteractionEnabled = false
        return view
    }
    func updateUIView(_ view: ResizingPDFView, context: Context) {
        if let page = session.document?.page(at: session.pageIndex), view.currentPage !== page {
            view.go(to: page)
            view.resetFitOnNextLayout = true
            view.setNeedsLayout()
        }
    }
}

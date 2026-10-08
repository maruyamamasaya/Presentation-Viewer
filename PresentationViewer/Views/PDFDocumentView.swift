import SwiftUI
import PDFKit
import Combine

@MainActor
struct PDFDocumentView: View {
    @ObservedObject var session: PDFReadingSession
    let thumbnailsVisible: Bool
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        if session.pageCount > 0 {
            PDFCanvas(session: session, thumbnailsVisible: thumbnailsVisible && !session.isPresenting,
                      verticalThumbnails: horizontalSizeClass == .regular)
        } else {
            ViewerErrorView(message: "PDFが破損しているか、パスワードで保護されています。")
        }
    }
}

@MainActor
private struct PDFCanvas: UIViewControllerRepresentable {
    @ObservedObject var session: PDFReadingSession
    let thumbnailsVisible: Bool
    let verticalThumbnails: Bool

    func makeUIViewController(context: Context) -> PDFCanvasController {
        PDFCanvasController(session: session)
    }

    func updateUIViewController(_ controller: PDFCanvasController, context: Context) {
        controller.configure(thumbnailsVisible: thumbnailsVisible, verticalThumbnails: verticalThumbnails)
    }
}

@MainActor
final class PDFCanvasController: UIViewController {
    let pdfView = ResizingPDFView()
    private let thumbnailView = PDFThumbnailView()
    private let session: PDFReadingSession
    private var pageObserver: NSObjectProtocol?
    private var subscription: AnyCancellable?
    private var layoutConstraints: [NSLayoutConstraint] = []
    private var layoutKey: String?
    private var presentation = false
    private var synchronizing = false
    private var readingScale: CGFloat = 1

    init(session: PDFReadingSession) {
        self.session = session
        super.init(nibName: nil, bundle: nil)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        for child in [pdfView, thumbnailView] {
            child.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(child)
        }
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pdfView.document = session.document
        thumbnailView.pdfView = pdfView
        thumbnailView.thumbnailSize = CGSize(width: 60, height: 80)
        // PDFKit owns thumbnail selection and generates pages on demand.
        pageObserver = NotificationCenter.default.addObserver(forName: .PDFViewPageChanged,
            object: pdfView, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, !self.synchronizing, let page = self.pdfView.currentPage,
                          let document = self.pdfView.document else { return }
                    self.session.selectPage(document.index(for: page))
                }
            }
        subscription = session.$pageIndex.sink { [weak self] index in self?.showPage(index) }
    }

    func configure(thumbnailsVisible: Bool, verticalThumbnails: Bool) {
        loadViewIfNeeded()
        synchronizing = true
        defer { synchronizing = false }
        if presentation != session.isPresenting {
            if session.isPresenting {
                readingScale = pdfView.scaleFactor / max(pdfView.scaleFactorForSizeToFit, 0.001)
            }
            presentation = session.isPresenting
            pdfView.displayMode = presentation ? .singlePage : .singlePageContinuous
            pdfView.backgroundColor = presentation ? .black : .systemBackground
            pdfView.displaysPageBreaks = !presentation
            pdfView.pageShadowsEnabled = !presentation
            pdfView.resetFitOnNextLayout = true
            pdfView.setNeedsLayout()
            view.layoutIfNeeded()
        }
        let key = "\(thumbnailsVisible):\(verticalThumbnails)"
        if layoutKey != key {
            layoutKey = key
            NSLayoutConstraint.deactivate(layoutConstraints)
            thumbnailView.isHidden = !thumbnailsVisible
            thumbnailView.layoutMode = verticalThumbnails ? .vertical : .horizontal
            thumbnailView.backgroundColor = .secondarySystemBackground
            let safe = view.safeAreaLayoutGuide
            layoutConstraints = [pdfView.topAnchor.constraint(equalTo: safe.topAnchor),
                                 pdfView.trailingAnchor.constraint(equalTo: safe.trailingAnchor)]
            if !thumbnailsVisible {
                layoutConstraints += [pdfView.leadingAnchor.constraint(equalTo: safe.leadingAnchor),
                                      pdfView.bottomAnchor.constraint(equalTo: safe.bottomAnchor)]
            } else if verticalThumbnails {
                layoutConstraints += [thumbnailView.topAnchor.constraint(equalTo: safe.topAnchor),
                    thumbnailView.bottomAnchor.constraint(equalTo: safe.bottomAnchor),
                    thumbnailView.leadingAnchor.constraint(equalTo: safe.leadingAnchor),
                    thumbnailView.widthAnchor.constraint(equalToConstant: 100),
                    pdfView.leadingAnchor.constraint(equalTo: thumbnailView.trailingAnchor),
                    pdfView.bottomAnchor.constraint(equalTo: safe.bottomAnchor)]
            } else {
                layoutConstraints += [pdfView.leadingAnchor.constraint(equalTo: safe.leadingAnchor),
                    pdfView.bottomAnchor.constraint(equalTo: thumbnailView.topAnchor),
                    thumbnailView.leadingAnchor.constraint(equalTo: safe.leadingAnchor),
                    thumbnailView.trailingAnchor.constraint(equalTo: safe.trailingAnchor),
                    thumbnailView.bottomAnchor.constraint(equalTo: safe.bottomAnchor),
                    thumbnailView.heightAnchor.constraint(equalToConstant: 100)]
            }
            NSLayoutConstraint.activate(layoutConstraints)
            view.layoutIfNeeded()
        }
        showPage(session.pageIndex)
        // Restore reader zoom once after returning from single-page presentation.
        if !presentation, readingScale != 1 {
            pdfView.scaleFactor = min(max(pdfView.scaleFactorForSizeToFit * readingScale,
                                         pdfView.minScaleFactor), pdfView.maxScaleFactor)
            readingScale = 1
        }
    }

    private func showPage(_ index: Int) {
        guard let page = session.document?.page(at: index), pdfView.currentPage !== page else { return }
        let wasSynchronizing = synchronizing
        synchronizing = true
        pdfView.go(to: page)
        // A caller may already be suppressing notifications during a layout update.
        synchronizing = wasSynchronizing
    }

    deinit {
        if let pageObserver { NotificationCenter.default.removeObserver(pageObserver) }
    }
}

final class ResizingPDFView: PDFView {
    private var viewport = CGSize.zero
    private var previousFit: CGFloat = 0
    private var resizing = false
    var resetFitOnNextLayout = false

    override func layoutSubviews() {
        guard !resizing, bounds.width > 0, bounds.height > 0,
              bounds.size != viewport || resetFitOnNextLayout else {
            super.layoutSubviews()
            return
        }
        resizing = true
        defer { resizing = false }
        let destination = currentDestination
        let relativeZoom = viewport == .zero || previousFit <= 0 || resetFitOnNextLayout
            ? 1 : max(1, scaleFactor / previousFit)
        resetFitOnNextLayout = false
        viewport = bounds.size
        super.layoutSubviews()
        let fit = scaleFactorForSizeToFit
        if fit > 0 {
            previousFit = fit
            minScaleFactor = fit
            maxScaleFactor = fit * 5
            scaleFactor = min(fit * relativeZoom, maxScaleFactor)
        }
        if let destination { go(to: destination) }
    }
}

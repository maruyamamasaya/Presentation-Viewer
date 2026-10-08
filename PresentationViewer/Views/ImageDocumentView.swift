import SwiftUI
import UIKit

struct ImageDocumentView: View {
    @State private var image: UIImage?
    let onTap: () -> Void
    let presenting: Bool

    init(url: URL, presenting: Bool = false, onTap: @escaping () -> Void = {}) {
        _image = State(initialValue: UIImage(contentsOfFile: url.path))
        self.onTap = onTap
        self.presenting = presenting
    }

    var body: some View {
        if let image {
            ImageCanvas(image: image, presenting: presenting, onTap: onTap)
        } else {
            ViewerErrorView(message: "画像を読み込めません。ファイルが破損している可能性があります。")
        }
    }
}

private struct ImageCanvas: UIViewRepresentable {
    let image: UIImage
    let presenting: Bool
    let onTap: () -> Void

    func makeUIView(context: Context) -> ZoomingImageView {
        ZoomingImageView(image: image, onTap: onTap)
    }

    func updateUIView(_ view: ZoomingImageView, context: Context) {
        view.onTap = onTap
        view.setPresentation(presenting)
    }
}

// UIScrollView owns pinch, panning and trackpad interaction.
final class ZoomingImageView: UIScrollView, UIScrollViewDelegate {
    private let imageView: UIImageView
    private var viewport = CGSize.zero
    private var fitScale: CGFloat = 1
    private var resizing = false
    private var presenting = false
    private var readingZoom: CGFloat = 1
    var onTap: () -> Void

    init(image: UIImage, onTap: @escaping () -> Void) {
        imageView = UIImageView(image: image)
        self.onTap = onTap
        super.init(frame: .zero)
        delegate = self
        backgroundColor = .systemBackground
        contentInsetAdjustmentBehavior = .never
        imageView.frame = CGRect(origin: .zero, size: image.size)
        imageView.contentMode = .scaleAspectFit
        imageView.isAccessibilityElement = true
        imageView.accessibilityLabel = "画像"
        imageView.accessibilityTraits = .image
        addSubview(imageView)
        contentSize = image.size
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(doubleTapped(_:)))
        doubleTap.numberOfTapsRequired = 2
        let singleTap = UITapGestureRecognizer(target: self, action: #selector(singleTapped))
        singleTap.require(toFail: doubleTap)
        singleTap.cancelsTouchesInView = false
        addGestureRecognizer(doubleTap)
        addGestureRecognizer(singleTap)
        imageView.accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: "拡大", target: self, selector: #selector(zoomIn)),
            UIAccessibilityCustomAction(name: "全体を表示", target: self, selector: #selector(zoomOut)),
            UIAccessibilityCustomAction(name: "ツールバーを切り替え", target: self, selector: #selector(toggleControls))
        ]
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func setPresentation(_ enabled: Bool) {
        backgroundColor = enabled ? .black : .systemBackground
        guard presenting != enabled else { return }
        if enabled { readingZoom = zoomScale / max(minimumZoomScale, 0.001) }
        presenting = enabled
        setZoomScale(min(max(minimumZoomScale * (enabled ? 1 : readingZoom), minimumZoomScale), maximumZoomScale),
                     animated: false)
    }

    override func layoutSubviews() {
        guard !resizing, bounds.width > 0, bounds.height > 0,
              imageView.bounds.width > 0, imageView.bounds.height > 0, bounds.size != viewport else {
            super.layoutSubviews()
            return
        }
        resizing = true
        defer { resizing = false }
        let initial = viewport == .zero
        let relativeZoom = initial ? 1 : zoomScale / fitScale
        let focus = imageView.convert(CGPoint(x: contentOffset.x + viewport.width / 2,
                                             y: contentOffset.y + viewport.height / 2), from: self)
        viewport = bounds.size
        fitScale = min(bounds.width / imageView.bounds.width, bounds.height / imageView.bounds.height)
        minimumZoomScale = fitScale
        maximumZoomScale = fitScale * 5
        setZoomScale(min(max(fitScale * relativeZoom, minimumZoomScale), maximumZoomScale), animated: false)
        centerImage()
        if initial {
            contentOffset = CGPoint(x: -contentInset.left, y: -contentInset.top)
        } else {
            let x = focus.x * zoomScale - bounds.width / 2
            let y = focus.y * zoomScale - bounds.height / 2
            contentOffset = CGPoint(
                x: min(max(x, -contentInset.left), max(-contentInset.left, contentSize.width - bounds.width + contentInset.right)),
                y: min(max(y, -contentInset.top), max(-contentInset.top, contentSize.height - bounds.height + contentInset.bottom)))
        }
        super.layoutSubviews()
    }

    func viewForZooming(in scrollView: UIScrollView) -> UIView? { imageView }
    func scrollViewDidZoom(_ scrollView: UIScrollView) { centerImage() }

    private func centerImage() {
        let horizontal = max(0, (bounds.width - imageView.frame.width) / 2)
        let vertical = max(0, (bounds.height - imageView.frame.height) / 2)
        contentInset = UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
    }

    @objc private func singleTapped() { onTap() }
    @objc private func toggleControls() -> Bool { onTap(); return true }
    @objc private func zoomIn() -> Bool {
        setZoomScale(min(zoomScale * 2, maximumZoomScale), animated: true)
        return true
    }
    @objc private func zoomOut() -> Bool { setZoomScale(minimumZoomScale, animated: true); return true }

    @objc private func doubleTapped(_ gesture: UITapGestureRecognizer) {
        if zoomScale > minimumZoomScale * 1.01 {
            setZoomScale(minimumZoomScale, animated: true)
        } else {
            let scale = min(minimumZoomScale * 2, maximumZoomScale)
            let point = gesture.location(in: imageView)
            zoom(to: CGRect(x: point.x - bounds.width / scale / 2, y: point.y - bounds.height / scale / 2,
                            width: bounds.width / scale, height: bounds.height / scale), animated: true)
        }
    }
}

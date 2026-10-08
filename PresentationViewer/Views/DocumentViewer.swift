import SwiftUI
import PDFKit
import QuickLook

struct DocumentViewer: View {
    let document: OpenedDocument
    @Environment(\.dismiss) private var dismiss

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
                case .pdf: PDFDocumentView(url: document.url)
                case .svg: SVGDocumentView(url: document.url)
                case .png, .jpg, .jpeg: ImageDocumentView(url: document.url)
                }
            }
            .navigationTitle(document.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }
}

struct ViewerErrorView: View {
    let message: String
    var body: some View {
        ContentUnavailableView("表示できません", systemImage: "doc.badge.exclamationmark", description: Text(message))
    }
}

struct PDFDocumentView: View {
    private let document: PDFDocument?

    init(url: URL) { document = PDFDocument(url: url) }

    var body: some View {
        if let document, document.pageCount > 0, !document.isLocked {
            PDFCanvas(document: document)
        } else {
            ViewerErrorView(message: "PDFが破損しているか、パスワードで保護されています。")
        }
    }
}

private struct PDFCanvas: UIViewRepresentable {
    let document: PDFDocument
    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.document = document
        return view
    }
    func updateUIView(_ view: PDFView, context: Context) {}
}

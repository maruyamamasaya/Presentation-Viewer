import PDFKit
import Combine

@MainActor
final class PDFReadingSession: ObservableObject {
    let document: PDFDocument?
    @Published private(set) var pageIndex = 0
    @Published var isPresenting = false
    var pageCount: Int { document?.isLocked == false ? document?.pageCount ?? 0 : 0 }

    init(url: URL?) { document = url.flatMap { PDFDocument(url: $0) } }
    init(document: PDFDocument) { self.document = document }

    func selectPage(_ index: Int) {
        guard pageCount > 0 else { return }
        let selected = min(max(index, 0), pageCount - 1)
        if pageIndex != selected { pageIndex = selected }
    }

    func movePage(_ delta: Int) { selectPage(pageIndex + delta) }
}

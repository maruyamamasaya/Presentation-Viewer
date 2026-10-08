import XCTest
import PDFKit
import UIKit
@testable import PresentationViewer

final class ViewerStateTests: XCTestCase {
    @MainActor
    private func makePDF() throws -> PDFDocument {
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 960, height: 540))
        let data = renderer.pdfData { context in
            for page in 1...3 {
                context.beginPage()
                ("Page \(page)" as NSString).draw(at: CGPoint(x: 40, y: 40), withAttributes: nil)
            }
        }
        return try XCTUnwrap(PDFDocument(data: data))
    }

    @MainActor
    func testPageNavigationClampsAtDocumentBoundaries() throws {
        let session = PDFReadingSession(document: try makePDF())
        XCTAssertEqual(session.pageCount, 3)
        session.movePage(-1)
        XCTAssertEqual(session.pageIndex, 0)
        session.selectPage(100)
        XCTAssertEqual(session.pageIndex, 2)
        session.movePage(1)
        XCTAssertEqual(session.pageIndex, 2)
        session.movePage(-1)
        XCTAssertEqual(session.pageIndex, 1)
    }

    @MainActor
    func testPresentationKeepsSelectedPage() throws {
        let session = PDFReadingSession(document: try makePDF())
        session.selectPage(1)
        session.isPresenting = true
        session.movePage(1)
        session.isPresenting = false
        XCTAssertEqual(session.pageIndex, 2)
        XCTAssertFalse(session.isPresenting)
    }

    @MainActor
    func testEmptySessionDoesNotNavigate() {
        let session = PDFReadingSession(url: nil)
        session.selectPage(99)
        session.movePage(-1)
        XCTAssertEqual(session.pageCount, 0)
        XCTAssertEqual(session.pageIndex, 0)
    }

    @MainActor
    func testExternalDisconnectKeepsReaderAndUsesSameSession() throws {
        let output = ExternalDisplayCoordinator()
        let reader = PDFReadingSession(document: try makePDF())
        let other = PDFReadingSession(document: try makePDF())
        reader.isPresenting = true
        output.didConnect("display-1")
        output.didConnect("display-2")
        output.begin(reader)
        reader.selectPage(2)
        XCTAssertTrue(output.session === reader)
        XCTAssertEqual(output.session?.pageIndex, 2)
        output.didDisconnect("display-1")
        XCTAssertTrue(output.connected)
        output.didDisconnect("display-2")
        XCTAssertFalse(output.connected)
        XCTAssertEqual(reader.pageIndex, 2)
        output.end(other)
        XCTAssertTrue(output.session === reader)
        output.end(reader)
        XCTAssertNil(output.session)
    }

    @MainActor
    func testImageResizeKeepsAspectFitAndRelativeZoom() {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 1600, height: 900)).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 1600, height: 900))
        }
        let view = ZoomingImageView(image: image, onTap: {})
        view.frame = CGRect(x: 0, y: 0, width: 400, height: 800)
        view.layoutIfNeeded()
        XCTAssertEqual(view.minimumZoomScale, 0.25, accuracy: 0.001)
        view.setZoomScale(view.minimumZoomScale * 2, animated: false)
        view.frame = CGRect(x: 0, y: 0, width: 800, height: 400)
        view.layoutIfNeeded()
        XCTAssertEqual(view.minimumZoomScale, 400 / 900, accuracy: 0.001)
        XCTAssertEqual(view.zoomScale / view.minimumZoomScale, 2, accuracy: 0.01)
        view.frame = CGRect(x: 0, y: 0, width: 300, height: 600)
        view.layoutIfNeeded()
        XCTAssertEqual(view.zoomScale / view.minimumZoomScale, 2, accuracy: 0.01)
        XCTAssertTrue(view.contentOffset.x.isFinite && view.contentOffset.y.isFinite)
    }

    @MainActor
    func testPDFControllerRetainsPageAcrossPresentationAndResize() throws {
        let session = PDFReadingSession(document: try makePDF())
        let controller = PDFCanvasController(session: session)
        controller.loadViewIfNeeded()
        controller.view.frame = CGRect(x: 0, y: 0, width: 768, height: 1024)
        controller.configure(thumbnailsVisible: true, verticalThumbnails: true)
        session.selectPage(1)
        session.isPresenting = true
        controller.configure(thumbnailsVisible: false, verticalThumbnails: false)
        controller.view.frame = CGRect(x: 0, y: 0, width: 1024, height: 768)
        controller.view.layoutIfNeeded()
        XCTAssertEqual(controller.pdfView.displayMode, .singlePage)
        XCTAssertTrue(controller.pdfView.currentPage === session.document?.page(at: 1))
        session.isPresenting = false
        controller.configure(thumbnailsVisible: true, verticalThumbnails: true)
        XCTAssertEqual(session.pageIndex, 1)
        XCTAssertEqual(controller.pdfView.displayMode, .singlePageContinuous)
    }
}

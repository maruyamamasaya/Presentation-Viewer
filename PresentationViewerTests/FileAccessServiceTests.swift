import XCTest
@testable import PresentationViewer

final class FileAccessServiceTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    private func write(_ name: String, text: String = "sample") throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data(text.utf8).write(to: url)
        return url
    }

    func testBookmarkRestoresFolderAndScanFiltersFiles() throws {
        for name in ["slides.PPTX", "notes.pdf", "drawing.svg", "photo.png", "photo.jpg", "photo.jpeg", "skip.txt", ".hidden.pdf"] {
            _ = try write(name)
        }
        let child = directory.appendingPathComponent("Child", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        try Data("nested".utf8).write(to: child.appendingPathComponent("nested.pdf"))
        let folder = try FileAccessService.register(directory)
        let restored = try JSONDecoder().decode(RegisteredFolder.self, from: JSONEncoder().encode(folder))
        XCTAssertEqual(try FileAccessService.resolve(restored).url.resolvingSymlinksInPath(), directory.resolvingSymlinksInPath())
        let scan = FileAccessService.scan([restored])
        XCTAssertTrue(scan.failures.isEmpty)
        XCTAssertEqual(Set(scan.documents.map(\.name)), Set(["slides.PPTX", "notes.pdf", "drawing.svg", "photo.png", "photo.jpg", "photo.jpeg"]))
    }

    func testRescanReflectsAdditionDeletionAndModification() throws {
        let original = try write("original.pdf")
        let folder = try FileAccessService.register(directory)
        XCTAssertEqual(FileAccessService.scan([folder]).documents.count, 1)
        try FileManager.default.removeItem(at: original)
        let updated = try write("updated.svg", text: "first")
        XCTAssertEqual(FileAccessService.scan([folder]).documents.map(\.name), ["updated.svg"])
        let firstKey = try XCTUnwrap(FileAccessService.scan([folder]).documents.first).thumbnailKey
        try Data("a larger revision".utf8).write(to: updated)
        XCTAssertNotEqual(try XCTUnwrap(FileAccessService.scan([folder]).documents.first).thumbnailKey, firstKey)
    }

    func testOpenPreservesSourceAndUsesOriginalURL() throws {
        let source = try write("original.pdf")
        let before = try Data(contentsOf: source)
        let folder = try FileAccessService.register(directory)
        let item = try XCTUnwrap(FileAccessService.scan([folder]).documents.first)
        let opened = try FileAccessService.open(item, in: folder)
        defer { opened.endAccess() }
        XCTAssertEqual(opened.url.resolvingSymlinksInPath(), source.resolvingSymlinksInPath())
        XCTAssertEqual(try Data(contentsOf: source), before)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["original.pdf"])
    }

    func testEmptyFileAndDeletedFolderProduceErrors() throws {
        _ = try write("empty.pdf", text: "")
        let folder = try FileAccessService.register(directory)
        let item = try XCTUnwrap(FileAccessService.scan([folder]).documents.first)
        XCTAssertThrowsError(try FileAccessService.open(item, in: folder))
        try FileManager.default.removeItem(at: directory)
        XCTAssertNotNil(FileAccessService.scan([folder]).failures[folder.id])
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    func testOverlappingRegistrationsDoNotDuplicateDocuments() throws {
        _ = try write("same.pdf")
        let first = try FileAccessService.register(directory)
        let second = try FileAccessService.register(directory)
        XCTAssertEqual(FileAccessService.scan([first, second]).documents.count, 1)
    }

    @MainActor
    func testStoreRestoresAndUnregistersWithoutDeletingSource() async throws {
        let suite = "PresentationViewerTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let source = try write("keep.pdf")
        let store = LibraryStore(defaults: defaults)
        await store.add(directory)
        XCTAssertEqual(store.folders.count, 1)
        await store.add(directory)
        XCTAssertEqual(store.folders.count, 1)
        let restored = LibraryStore(defaults: defaults)
        await restored.refresh()
        XCTAssertEqual(restored.documents.map(\.name), ["keep.pdf"])
        restored.remove(Set(restored.folders.map(\.id)))
        await restored.refresh()
        XCTAssertTrue(restored.folders.isEmpty)
        XCTAssertTrue(restored.documents.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        XCTAssertTrue(LibraryStore(defaults: defaults).folders.isEmpty)
    }
}

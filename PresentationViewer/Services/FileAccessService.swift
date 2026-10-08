import Foundation

enum DocumentFormat: String, Sendable {
    case pptx, pdf, svg, png, jpg, jpeg
    var symbol: String {
        switch self {
        case .pptx: "rectangle.on.rectangle"
        case .pdf: "doc.richtext"
        case .svg, .png, .jpg, .jpeg: "photo"
        }
    }
}

struct RegisteredFolder: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    var name: String
    var bookmark: Data
}

struct LibraryDocument: Identifiable, Sendable {
    var id: String { "\(folderID.uuidString):\(url.path)" }
    let folderID: UUID
    let url: URL
    let format: DocumentFormat
    let modified: Date?
    let size: Int
    var name: String { url.lastPathComponent }
    var thumbnailKey: String { "\(id):\(modified?.timeIntervalSince1970 ?? 0):\(size)" }
}

struct OpenedDocument: Identifiable, Sendable {
    let id = UUID()
    let url: URL
    let name: String
    let format: DocumentFormat
    let accessURL: URL
    let scoped: Bool
    func endAccess() {
        if scoped { accessURL.stopAccessingSecurityScopedResource() }
    }
}

struct FolderScan: Sendable {
    var folders: [RegisteredFolder]
    var documents: [LibraryDocument]
    var failures: [UUID: String]
}

enum FileAccessError: LocalizedError {
    case unavailable, empty
    var errorDescription: String? {
        switch self {
        case .unavailable: "アクセスできません。フォルダを再選択するか、ファイルアプリでダウンロード状態を確認してください。"
        case .empty: "ファイルが空のため表示できません。"
        }
    }
}

enum FileAccessService {
    static func register(_ url: URL, id: UUID = UUID()) throws -> RegisteredFolder {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard try url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory == true else {
            throw FileAccessError.unavailable
        }
        return RegisteredFolder(id: id, name: url.lastPathComponent,
            bookmark: try url.bookmarkData(options: .minimalBookmark, includingResourceValuesForKeys: nil, relativeTo: nil))
    }

    static func resolve(_ folder: RegisteredFolder) throws -> (url: URL, stale: Bool) {
        var stale = false
        let url = try URL(resolvingBookmarkData: folder.bookmark, options: .withoutUI,
            relativeTo: nil, bookmarkDataIsStale: &stale)
        return (url, stale)
    }

    static func coordinatedRead<T>(_ url: URL, options: NSFileCoordinator.ReadingOptions = [],
                                   _ read: (URL) throws -> T) throws -> T {
        var coordinationError: NSError?
        var result: Result<T, Error>?
        NSFileCoordinator().coordinate(readingItemAt: url, options: options, error: &coordinationError) { readable in
            result = Result { try read(readable) }
        }
        if let coordinationError { throw coordinationError }
        guard let result else { throw FileAccessError.unavailable }
        return try result.get()
    }

    static func scan(_ folders: [RegisteredFolder]) -> FolderScan {
        var output = FolderScan(folders: folders, documents: [], failures: [:])
        var seen = Set<URL>()
        for (index, folder) in folders.enumerated() {
            do {
                let resolved = try resolve(folder)
                let scoped = resolved.url.startAccessingSecurityScopedResource()
                defer { if scoped { resolved.url.stopAccessingSecurityScopedResource() } }
                if resolved.stale {
                    output.folders[index].bookmark = try resolved.url.bookmarkData(options: .minimalBookmark,
                        includingResourceValuesForKeys: nil, relativeTo: nil)
                }
                output.folders[index].name = resolved.url.lastPathComponent
                let items = try coordinatedRead(resolved.url, options: .immediatelyAvailableMetadataOnly) { directory in
                    let urls = try FileManager.default.contentsOfDirectory(at: directory,
                        includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey],
                        options: [.skipsHiddenFiles, .skipsPackageDescendants])
                    return urls.compactMap { url -> LibraryDocument? in
                        guard let format = DocumentFormat(rawValue: url.pathExtension.lowercased()),
                            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey]),
                            values.isRegularFile == true else { return nil }
                        return LibraryDocument(folderID: folder.id, url: url, format: format,
                            modified: values.contentModificationDate, size: values.fileSize ?? 0)
                    }
                }
                output.documents.append(contentsOf: items.filter { seen.insert($0.url.standardizedFileURL).inserted })
            } catch { output.failures[folder.id] = error.localizedDescription }
        }
        output.documents.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return output
    }

    // Keep the folder's security scope alive until all viewer components are dismissed.
    // Coordinated reading asks File Provider/iCloud to materialize the file as needed.
    static func open(_ item: LibraryDocument, in folder: RegisteredFolder, downloading: Bool = true) throws -> OpenedDocument {
        let resolved = try resolve(folder)
        let scoped = resolved.url.startAccessingSecurityScopedResource()
        do {
            let source = resolved.url.appendingPathComponent(item.name)
            if !downloading {
                let values = try source.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
                if values.isUbiquitousItem == true,
                    values.ubiquitousItemDownloadingStatus != .current,
                    values.ubiquitousItemDownloadingStatus != .downloaded {
                    throw FileAccessError.unavailable
                }
            }
            let readable = try coordinatedRead(source) { url in
                let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                guard values.isRegularFile == true else { throw FileAccessError.unavailable }
                guard (values.fileSize ?? 0) > 0 else { throw FileAccessError.empty }
                return url
            }
            return OpenedDocument(url: readable, name: item.name, format: item.format,
                accessURL: resolved.url, scoped: scoped)
        } catch {
            if scoped { resolved.url.stopAccessingSecurityScopedResource() }
            throw error
        }
    }
}

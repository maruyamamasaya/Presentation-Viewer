import Foundation

struct SavedCloudFile: Codable, Identifiable, Sendable {
    let diagram: CloudDiagram
    let file: CloudFile
    var id: String { "\(diagram.id.lowercased())-\(diagram.version)-\(file.format.rawValue)-\(file.page)" }
    var relativeName: String { "\(id).\(file.format.rawValue)" }
    var displayName: String { "\(diagram.title) · v\(diagram.version) · \(file.format.rawValue.uppercased())\(file.format == .png && diagram.pageCount > 1 ? " · \(file.page)/\(diagram.pageCount)" : "")" }
    func validate() throws { try file.validate(for: diagram) }
}

actor CloudFileStore {
    private let saved: URL
    private let cache: URL
    init(saved: URL, cache: URL) throws {
        guard saved.standardizedFileURL != cache.standardizedFileURL else { throw CloudError.invalidResponse }
        self.saved = saved; self.cache = cache
        for folder in [saved, cache] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
    }
    static func applicationStore(namespace: String? = nil) throws -> CloudFileStore {
        let fm = FileManager.default
        let saved = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("DiagramLibrary")
        let cache = try fm.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("DiagramLibrary")
        if let namespace {
            guard namespace.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else { throw CloudError.invalidResponse }
            return try CloudFileStore(saved: saved.appendingPathComponent(namespace), cache: cache.appendingPathComponent(namespace))
        }
        return try CloudFileStore(saved: saved, cache: cache)
    }
    func records() throws -> [SavedCloudFile] {
        let url = saved.appendingPathComponent("index.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let records = try JSONDecoder().decode([SavedCloudFile].self, from: Data(contentsOf: url))
        for record in records { try record.validate() }
        guard Set(records.map(\.id)).count == records.count else { throw CloudError.invalidResponse }
        return records.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }
    private func verify(_ data: Data, record: SavedCloudFile) throws {
        try record.validate()
        guard data.count == record.file.sizeBytes, cloudHash(data) == record.file.sha256 else { throw CloudError.integrity }
    }
    func cacheData(_ data: Data, record: SavedCloudFile) throws -> URL {
        try verify(data, record: record)
        // Hash in cache name avoids overwriting a file that is currently being viewed.
        let url = cache.appendingPathComponent(record.id + "-" + record.file.sha256 + "." + record.file.format.rawValue)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]); return url
    }
    func save(_ data: Data, record: SavedCloudFile) throws {
        try verify(data, record: record)
        var index = try records()
        if let old = index.first(where: { $0.id == record.id }) {
            guard old.file == record.file else { throw CloudError.conflict }
        } else { index.append(record) }
        let destination = saved.appendingPathComponent(record.relativeName)
        let existed = FileManager.default.fileExists(atPath: destination.path)
        try data.write(to: destination, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        do { try JSONEncoder().encode(index).write(to: saved.appendingPathComponent("index.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication]) }
        catch { if !existed { try? FileManager.default.removeItem(at: destination) }; throw error }
    }
    func open(_ record: SavedCloudFile) throws -> URL {
        try record.validate()
        guard try records().contains(where: { $0.id == record.id && $0.file == record.file }) else { throw CloudError.unavailable }
        let url = saved.appendingPathComponent(record.relativeName)
        try verify(Data(contentsOf: url), record: record); return url
    }
    func clearCache() throws {
        for url in try FileManager.default.contentsOfDirectory(at: cache, includingPropertiesForKeys: nil) { try FileManager.default.removeItem(at: url) }
    }
}

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
    // Shares the user's saved namespace; cache clearing never removes visibility settings.
    func hiddenDiagrams() throws -> [CloudDiagram] {
        let url = saved.appendingPathComponent("hidden-diagrams.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let items = try JSONDecoder().decode([CloudDiagram].self, from: Data(contentsOf: url))
        for item in items { try item.validate() }
        guard Set(items.map { $0.id.lowercased() }).count == items.count else { throw CloudError.invalidResponse }
        return items
    }
    func setHidden(_ diagram: CloudDiagram, hidden: Bool) throws -> [CloudDiagram] {
        try diagram.validate()
        var items = try hiddenDiagrams().filter { $0.id.lowercased() != diagram.id.lowercased() }
        if hidden { items.append(diagram) }
        try JSONEncoder().encode(items).write(to: saved.appendingPathComponent("hidden-diagrams.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return items
    }
    func collections() throws -> [CloudCollection] {
        let url = saved.appendingPathComponent("collections.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let values = try JSONDecoder().decode([CloudCollection].self, from: Data(contentsOf: url))
        for value in values { try value.validate() }
        guard Set(values.map(\.id)).count == values.count else { throw CloudError.invalidResponse }
        return values
    }
    func saveCollection(_ collection: CloudCollection) throws -> [CloudCollection] {
        try collection.validate()
        var values = try collections()
        if let index = values.firstIndex(where: { $0.id == collection.id }) { values[index] = collection }
        else { values.append(collection) }
        try writeCollections(values)
        return values
    }
    func removeCollection(_ id: UUID) throws -> [CloudCollection] {
        let values = try collections().filter { $0.id != id }
        try writeCollections(values)
        return values
    }
    private func writeCollections(_ values: [CloudCollection]) throws {
        try JSONEncoder().encode(values).write(to: saved.appendingPathComponent("collections.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
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
    /// Only verified bytes for this exact immutable version may be reused.
    func localURL(_ record: SavedCloudFile) throws -> URL? {
        try record.validate()
        if let url = try? open(record) { return url }
        let url = cache.appendingPathComponent(record.id + "-" + record.file.sha256 + "." + record.file.format.rawValue)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            try verify(Data(contentsOf: url), record: record)
            return url
        } catch {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
    }
    private func detailURL(_ diagram: CloudDiagram) throws -> URL {
        try diagram.validate()
        return cache.appendingPathComponent("detail-\(diagram.id.lowercased())-\(diagram.version).json")
    }
    func cachedDetail(_ diagram: CloudDiagram) throws -> CloudDetail? {
        let url = try detailURL(diagram)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            let detail = try JSONDecoder().decode(CloudDetail.self, from: Data(contentsOf: url))
            try detail.validate()
            guard detail.id == diagram.id, detail.version == diagram.version,
                  detail.type == diagram.type, detail.pageCount == diagram.pageCount,
                  detail.formats == diagram.formats else { throw CloudError.invalidResponse }
            return detail
        } catch {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
    }
    func cacheDetail(_ detail: CloudDetail) throws {
        try detail.validate()
        try JSONEncoder().encode(detail).write(to: detailURL(detail.diagram), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
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

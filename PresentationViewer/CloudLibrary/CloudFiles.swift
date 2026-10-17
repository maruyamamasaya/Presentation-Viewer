import Foundation
import LibraryOrganization

struct SavedCloudFile: Codable, Identifiable, Sendable {
    let diagram: CloudDiagram
    let file: CloudFile
    var id: String { "\(diagram.id.lowercased())-\(diagram.version)-\(file.format.rawValue)-\(file.page)" }
    var relativeName: String { "\(id).\(file.format.rawValue)" }
    var displayName: String { "\(diagram.title) · v\(diagram.version) · \(file.format.rawValue.uppercased())\(file.format == .png && diagram.pageCount > 1 ? " · \(file.page)/\(diagram.pageCount)" : "")" }
    func validate() throws { try file.validate(for: diagram) }
}

typealias LibraryGroup = LibraryOrganization.LibraryGroup
typealias LibraryClassification = LibraryOrganization.LibraryClassification

actor CloudFileStore {
    private let saved: URL
    private let cache: URL
    private static let cacheLock = NSLock()
    static let maximumCacheBytes: Int64 = 5_000_000_000
    private let cacheLimit: Int64
    private let cacheRoot: URL
    init(saved: URL, cache: URL, cacheLimit: Int64 = CloudFileStore.maximumCacheBytes, cacheRoot: URL? = nil) throws {
        guard saved.standardizedFileURL != cache.standardizedFileURL else { throw CloudError.invalidResponse }
        self.saved = saved; self.cache = cache; self.cacheLimit = max(0, cacheLimit); self.cacheRoot = cacheRoot ?? cache
        for folder in [saved, cache] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
    }
    static func applicationStore(namespace: String? = nil) throws -> CloudFileStore {
        let fm = FileManager.default
        let saved = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("DiagramLibrary")
        let cache = try fm.url(for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true).appendingPathComponent("DiagramLibrary")
        if let namespace {
            guard namespace.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else { throw CloudError.invalidResponse }
            return try CloudFileStore(saved: saved.appendingPathComponent(namespace), cache: cache.appendingPathComponent(namespace), cacheRoot: cache)
        }
        return try CloudFileStore(saved: saved, cache: cache)
    }
    func syncLabDirectory() -> URL { saved.appendingPathComponent("sync-lab") }
    func organization() throws -> OrganizationState<CloudDiagram> {
        let url = saved.appendingPathComponent("organization.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return OrganizationState() }
        return try OrganizationState.load(Data(contentsOf: url))
    }
    private func writeOrganization(_ value: OrganizationState<CloudDiagram>) throws {
        try JSONEncoder().encode(value).write(to: saved.appendingPathComponent("organization.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }
    func createFolder(name: String, parentID: UUID? = nil) throws -> OrganizationState<CloudDiagram> {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var value = try organization()
        guard !name.isEmpty, name.count <= 120, parentID == nil || value.folders.contains(where: { $0.id == parentID }) else { throw CloudError.invalidResponse }
        value.folders.append(OrganizationFolder(name: name, parentID: parentID))
        try writeOrganization(value); return value
    }
    func moveDocuments(_ ids: Set<String>, to folderID: UUID?) throws -> OrganizationState<CloudDiagram> {
        var value = try organization()
        guard folderID == nil || value.folders.contains(where: { $0.id == folderID }), ids.allSatisfy({ UUID(uuidString: $0) != nil }) else { throw CloudError.invalidResponse }
        value.moveBooks(Set(ids.map { $0.lowercased() }), to: folderID)
        try writeOrganization(value); return value
    }
    func removeOrganizationFolder(_ id: UUID) throws -> OrganizationState<CloudDiagram> {
        var value = try organization(); value.removeFolder(id)
        try writeOrganization(value); return value
    }
    func costHistory() throws -> [StorageCostSnapshot] {
        let url = saved.appendingPathComponent("storage-cost-history.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        return try JSONDecoder().decode([StorageCostSnapshot].self, from: Data(contentsOf: url))
    }
    func recordCost(_ snapshot: StorageCostSnapshot) throws -> [StorageCostSnapshot] {
        var history = try costHistory()
        history.append(snapshot)
        history = Array(history.suffix(365))
        try JSONEncoder().encode(history).write(to: saved.appendingPathComponent("storage-cost-history.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return history
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
    func classifications() throws -> [String: LibraryClassification] {
        let url = saved.appendingPathComponent("classifications.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        return try JSONDecoder().decode([String: LibraryClassification].self, from: Data(contentsOf: url))
    }
    func setClassification(_ diagram: CloudDiagram, value: LibraryClassification) throws -> [String: LibraryClassification] {
        try diagram.validate()
        var values = try classifications()
        values[diagram.id.lowercased()] = LibraryClassification(group: value.group, tags: LibraryClassification.normalizedTags(value.tags))
        try JSONEncoder().encode(values).write(to: saved.appendingPathComponent("classifications.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return values
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
        try writeCache(data, to: url)
        return url
    }
    /// Only verified bytes for this exact immutable version may be reused.
    func localURL(_ record: SavedCloudFile) throws -> URL? {
        try record.validate()
        if let url = try? open(record) { return url }
        let url = cache.appendingPathComponent(record.id + "-" + record.file.sha256 + "." + record.file.format.rawValue)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            try verify(Data(contentsOf: url), record: record)
            try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
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
        try writeCache(JSONEncoder().encode(detail), to: detailURL(detail.diagram))
    }
    // Catalog metadata is restored before scanning or verifying document bytes.
    func cachedCatalog() throws -> [CloudDiagram] {
        try Self.cacheLock.withLock { try reserveCache(bytes: 0, replacing: cache.appendingPathComponent(".reservation")) }
        let url = cache.appendingPathComponent("catalog.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let diagrams = try JSONDecoder().decode([CloudDiagram].self, from: Data(contentsOf: url))
        for diagram in diagrams { try diagram.validate() }
        return diagrams
    }
    func cacheCatalog(_ diagrams: [CloudDiagram]) throws {
        for diagram in diagrams { try diagram.validate() }
        try writeCache(JSONEncoder().encode(diagrams), to: cache.appendingPathComponent("catalog.json"))
    }
    private func writeCache(_ data: Data, to url: URL) throws {
        try Self.cacheLock.withLock {
            try reserveCache(bytes: data.count, replacing: url)
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }
    private func reserveCache(bytes: Int, replacing destination: URL) throws {
        guard Int64(bytes) <= cacheLimit else { throw CloudError.unavailable }
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        guard let enumerator = fm.enumerator(at: cacheRoot, includingPropertiesForKeys: keys) else { throw CloudError.unavailable }
        let entries = enumerator.allObjects.compactMap { $0 as? URL }
            .filter { $0 != destination }
            .compactMap { url -> (URL, Int64, Date)? in
                guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]), values.isRegularFile == true else { return nil }
                return (url, Int64(values.fileSize ?? 0), values.contentModificationDate ?? .distantPast)
            }.sorted { $0.2 < $1.2 }
        var total = entries.reduce(Int64(bytes)) { $0 + $1.1 }
        for (url, size, _) in entries where total > cacheLimit {
            try fm.removeItem(at: url); total -= size
        }
    }
    /// Recover browsable copies after restart, without trusting an unverified cache file.
    func cachedDiagrams() throws -> [CloudDiagram] {
        var diagrams: [CloudDiagram] = []
        for url in try FileManager.default.contentsOfDirectory(at: cache, includingPropertiesForKeys: nil)
            where url.lastPathComponent.hasPrefix("detail-") && url.pathExtension == "json" {
            guard let detail = try? JSONDecoder().decode(CloudDetail.self, from: Data(contentsOf: url)),
                  (try? detail.validate()) != nil else { continue }
            for file in detail.files where file.format != .svg {
                if try localURL(SavedCloudFile(diagram: detail.diagram, file: file)) != nil {
                    diagrams.append(detail.diagram); break
                }
            }
        }
        return diagrams.sorted { $0.version > $1.version }
    }
    func localFiles(_ detail: CloudDetail) throws -> [CloudFile] {
        try detail.files.filter { try localURL(SavedCloudFile(diagram: detail.diagram, file: $0)) != nil }
    }
    /// Remove document copies only; collections and hidden preferences belong to the user.
    func clearLocalDocuments() throws {
        for record in try records() {
            let url = saved.appendingPathComponent(record.relativeName)
            if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
        }
        try JSONEncoder().encode([SavedCloudFile]()).write(to: saved.appendingPathComponent("index.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        try clearCache()
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

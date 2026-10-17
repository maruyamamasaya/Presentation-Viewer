import Foundation
import LibraryOrganization
import CryptoKit

enum CloudError: LocalizedError {
    case invalidResponse, integrity, unavailable, authentication, conflict, expiredURL
    var errorDescription: String? {
        switch self {
        case .invalidResponse: "資料の情報が不正です。"
        case .integrity: "ファイルの整合性を確認できませんでした。保存・表示を中止しました。"
        case .unavailable: "資料を取得できません。接続状態を確認してください。"
        case .authentication: "認証が必要です。再ログインしてください。"
        case .expiredURL: "取得URLが期限切れです。もう一度取得してください。"
        case .conflict: "同じ資料・版の内容が変わっています。別の版で取得してください。"
        }
    }
}

enum CloudFormat: String, Codable, CaseIterable, Sendable {
    case png, svg, pdf, pptx
    var documentFormat: DocumentFormat { DocumentFormat(rawValue: rawValue)! }
    var mime: String {
        switch self {
        case .png: "image/png"
        case .svg: "image/svg+xml"
        case .pdf: "application/pdf"
        case .pptx: "application/vnd.openxmlformats-officedocument.presentationml.presentation"
        }
    }
}

enum CloudLibraryKind: String, CaseIterable {
    case presentations, illustrations
    var title: String { self == .presentations ? "プレゼン資料" : "図解ライブラリ" }
    func contains(_ diagram: CloudDiagram) -> Bool {
        // Untyped historic entries remain in presentations; legacy single diagrams stay illustrations.
        let single = ["illustration", "roadmap", "architecture", "flowchart", "comparison"].contains(diagram.type)
        return self == .illustrations ? single : !single
    }
}

struct CloudDiagram: Codable, Identifiable, Sendable, Equatable {
    let id: String
    let title: String
    let type: String
    let version: Int
    let formats: [CloudFormat]
    let pageCount: Int
    let tags: [String]
    func validate() throws {
        guard UUID(uuidString: id) != nil, version > 0, version <= 999999,
              !title.isEmpty, title.count <= 2000, pageCount > 0, pageCount <= 999,
              !formats.isEmpty, Set(formats).count == formats.count else { throw CloudError.invalidResponse }
    }
}
struct CloudList: Codable, Sendable { let items: [CloudDiagram]; let nextCursor: String? }
// Human-approved exception for this immutable presentation only. Other files retain 20 MB.
enum CloudArtifactSizePolicy {
    static let diagramID = "4f2af5d0-86c9-4709-9dad-9f6a67e5ac10"
    static func approvedLargeFile(name: String, sizeBytes: Int, sha256: String, contentType: String) -> Bool {
        switch name {
        case "document.pdf":
            return sizeBytes == 29_640_691 && contentType == CloudFormat.pdf.mime &&
                sha256 == "eb08beebf657a1582423e48f3602207169828b5ec906c5ce9c9a3a18acbf620a"
        case "presentation.pptx":
            return sizeBytes == 20_067_274 && contentType == CloudFormat.pptx.mime &&
                sha256 == "80e86b33ad702a9642f615e475885a48847288a365469b36778d689211ed870b"
        default: return false
        }
    }
    static func allows(file: CloudFile, diagram: CloudDiagram) -> Bool {
        guard file.sizeBytes > 0 else { return false }
        if file.sizeBytes < 20_000_000 { return true }
        return diagram.id.lowercased() == diagramID && diagram.version == 1 &&
            diagram.type == "presentation" && diagram.pageCount == 40 &&
            approvedLargeFile(name: file.name, sizeBytes: file.sizeBytes, sha256: file.sha256, contentType: file.contentType)
    }
    static func allows(grant: CloudGrant) -> Bool {
        guard grant.sizeBytes > 0 else { return false }
        return grant.sizeBytes < 20_000_000 || approvedLargeFile(name: grant.fileName, sizeBytes: grant.sizeBytes,
            sha256: grant.sha256, contentType: grant.contentType)
    }
}

struct CloudFile: Codable, Sendable, Equatable {
    let name: String
    let format: CloudFormat
    let sizeBytes: Int
    let sha256: String
    let contentType: String
    var page: Int {
        let parts = name.split(separator: "/")
        return parts.count == 3 && parts[0] == "slides" ? Int(parts[1]) ?? 0 : 1
    }
    func validate(for diagram: CloudDiagram) throws {
        try diagram.validate()
        let expected = diagram.type == "presentation"
            ? (format == .png ? String(format: "slides/%03d/slide.png", page) : format == .pdf ? "document.pdf" : format == .pptx ? "presentation.pptx" : "")
            : "diagram.\(format.rawValue)"
        guard name == expected, !expected.isEmpty, diagram.formats.contains(format),
              page >= 1, page <= diagram.pageCount, contentType == format.mime,
              CloudArtifactSizePolicy.allows(file: self, diagram: diagram),
              sha256.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else { throw CloudError.invalidResponse }
    }
}
struct CloudDetail: Codable, Sendable {
    let id: String
    let title: String
    let type: String
    let version: Int
    let formats: [CloudFormat]
    let pageCount: Int
    let tags: [String]
    let files: [CloudFile]
    var diagram: CloudDiagram { CloudDiagram(id: id, title: title, type: type, version: version, formats: formats, pageCount: pageCount, tags: tags) }
    func validate() throws {
        try diagram.validate()
        guard !files.isEmpty, files.count <= 1000, Set(files.map(\.name)).count == files.count else { throw CloudError.invalidResponse }
        for file in files { try file.validate(for: diagram) }
    }
}
struct CloudGrant: Codable, Sendable {
    let url: URL
    let method: String
    let expiresAt: String
    let expiresIn: Int
    let contentType: String
    let sizeBytes: Int
    let sha256: String
    let fileName: String
    func validate(file: CloudFile) throws {
        guard method == "GET", expiresIn > 0, expiresIn <= 900,
              cloudDate(expiresAt).map({ $0 > Date() }) == true,
              contentType == file.contentType, sizeBytes == file.sizeBytes, sha256 == file.sha256,
              fileName == URL(fileURLWithPath: file.name).lastPathComponent else { throw CloudError.invalidResponse }
    }
}
func cloudHash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

extension CloudDetail {
    private struct RawFile: Decodable {
        let name: String; let format: String; let sizeBytes: Int; let sha256: String; let contentType: String?
    }
    private enum CodingKeys: String, CodingKey { case id, title, type, version, formats, pageCount, tags, files }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id); title = try c.decode(String.self, forKey: .title)
        type = try c.decode(String.self, forKey: .type); version = try c.decode(Int.self, forKey: .version)
        formats = try c.decode([CloudFormat].self, forKey: .formats); pageCount = try c.decode(Int.self, forKey: .pageCount)
        tags = try c.decode([String].self, forKey: .tags)
        files = try c.decode([RawFile].self, forKey: .files).compactMap { raw in
            guard let format = CloudFormat(rawValue: raw.format) else { return nil }
            return CloudFile(name: raw.name, format: format, sizeBytes: raw.sizeBytes, sha256: raw.sha256, contentType: raw.contentType ?? format.mime)
        }
    }
}

func cloudDate(_ value: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.date(from: value) ?? ISO8601DateFormatter().date(from: value)
}

/// A device-local reading collection. Membership is by document ID; the snapshot is an offline fallback.
typealias CloudCollection = ReadingCollection<CloudDiagram>
extension ReadingCollection where Member == CloudDiagram {
    func validate() throws {
        do { try validateStructure(memberID: { $0.id.lowercased() }) }
        catch { throw CloudError.invalidResponse }
        guard members.allSatisfy({ CloudLibraryKind.illustrations.contains($0) && ($0.formats.contains(.png) || $0.formats.contains(.pdf)) }) else { throw CloudError.invalidResponse }
        for member in members { try member.validate() }
    }
    func resolved(using available: [CloudDiagram], hidden: [CloudDiagram]) -> [CloudDiagram] {
        let hiddenIDs = Set(hidden.map { $0.id.lowercased() })
        return members.filter { !hiddenIDs.contains($0.id.lowercased()) }.map { member in
            available.filter { $0.id.lowercased() == member.id.lowercased() && CloudLibraryKind.illustrations.contains($0) }
                .max(by: { $0.version < $1.version }) ?? member
        }
    }
}
struct CloudCollectionPage: Identifiable, Sendable {
    let diagram: CloudDiagram
    let file: CloudFile
    var id: String { SavedCloudFile(diagram: diagram, file: file).id }
}
func collectionReadingFiles(_ files: [CloudFile]) -> [CloudFile] {
    let pngs = files.filter { $0.format == .png }.sorted { $0.page < $1.page }
    return pngs.isEmpty ? files.filter { $0.format == .pdf }.prefix(1).map { $0 } : pngs
}

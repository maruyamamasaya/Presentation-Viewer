import SwiftUI
import QuickLookThumbnailing

struct DocumentTile: View {
    let item: LibraryDocument
    let folder: RegisteredFolder
    @State private var thumbnail: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 8).fill(Color(uiColor: .secondarySystemBackground))
                if let thumbnail {
                    Image(uiImage: thumbnail).resizable().scaledToFit().padding(8)
                } else {
                    Image(systemName: item.format.symbol)
                        .font(.largeTitle).foregroundStyle(.secondary)
                }
            }
            .aspectRatio(4 / 3, contentMode: .fit)
            .clipped()
            .accessibilityHidden(true)
            Text(item.name).font(.subheadline).lineLimit(2).truncationMode(.middle)
                .foregroundStyle(.primary)
            Text(item.format.rawValue.uppercased()).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .task(id: item.thumbnailKey + folder.bookmark.base64EncodedString()) {
            thumbnail = nil
            let image = await ThumbnailService.shared.image(for: item, folder: folder)
            if !Task.isCancelled { thumbnail = image }
        }
    }
}

@MainActor
private final class ThumbnailService {
    static let shared = ThumbnailService()
    private let cache = NSCache<NSString, UIImage>()

    init() {
        cache.countLimit = 60
        cache.totalCostLimit = 8 * 1024 * 1024
    }

    func image(for item: LibraryDocument, folder: RegisteredFolder) async -> UIImage? {
        let key = item.thumbnailKey as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let access: OpenedDocument
        do {
            access = try await Task.detached(priority: .utility) {
                try FileAccessService.open(item, in: folder, downloading: false)
            }.value
        } catch { return nil }
        defer { access.endAccess() }
        guard !Task.isCancelled else { return nil }
        let request = QLThumbnailGenerator.Request(fileAt: access.url,
            size: CGSize(width: 160, height: 160), scale: 2, representationTypes: .thumbnail)
        let image: UIImage? = await withCheckedContinuation { continuation in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
                continuation.resume(returning: representation?.uiImage)
            }
        }
        if let image {
            cache.setObject(image, forKey: key, cost: Int(image.size.width * image.scale * image.size.height * image.scale * 4))
        }
        return image
    }
}

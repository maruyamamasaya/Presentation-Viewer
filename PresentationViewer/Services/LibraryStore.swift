import Foundation
import Combine

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var folders: [RegisteredFolder] = []
    @Published private(set) var documents: [LibraryDocument] = []
    @Published private(set) var failures: [UUID: String] = [:]
    @Published private(set) var refreshing = false
    @Published var errorMessage: String?
    private let defaults: UserDefaults
    private let key = "registeredFolders.v1"
    private var refreshAgain = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: key) {
            do { folders = try JSONDecoder().decode([RegisteredFolder].self, from: data) }
            catch { errorMessage = "フォルダ登録情報を復元できませんでした。フォルダを追加し直してください。" }
        }
    }

    func add(_ url: URL, replacing id: UUID? = nil) async {
        do {
            let record = try await Task.detached(priority: .userInitiated) {
                try FileAccessService.register(url, id: id ?? UUID())
            }.value
            let duplicate = folders.first { folder in
                (try? FileAccessService.resolve(folder).url.standardizedFileURL) == url.standardizedFileURL && folder.id != id
            }
            guard duplicate == nil else { errorMessage = "このフォルダは登録済みです。"; return }
            if let id, let index = folders.firstIndex(where: { $0.id == id }) { folders[index] = record }
            else { folders.append(record) }
            save()
            await refresh()
        } catch { errorMessage = error.localizedDescription }
    }

    func remove(_ ids: Set<UUID>) {
        folders.removeAll { ids.contains($0.id) }
        documents.removeAll { ids.contains($0.folderID) }
        failures = failures.filter { !ids.contains($0.key) }
        save()
        Task { await refresh() }
    }

    func refresh() async {
        if refreshing { refreshAgain = true; return }
        refreshing = true
        repeat {
            refreshAgain = false
            let snapshot = folders
            let result = await Task.detached(priority: .userInitiated) { FileAccessService.scan(snapshot) }.value
            if folders == snapshot {
                folders = result.folders
                documents = result.documents
                failures = result.failures
                save()
            } else { refreshAgain = true }
        } while refreshAgain
        refreshing = false
    }

    private func save() {
        do { defaults.set(try JSONEncoder().encode(folders), forKey: key) }
        catch { errorMessage = "フォルダ登録情報を保存できませんでした。" }
    }
}

import SwiftUI

struct FolderManagementView: View {
    @ObservedObject var store: LibraryStore
    @State private var showPicker = false
    @State private var replacing: UUID?

    var body: some View {
        List {
            ForEach(store.folders) { folder in
                VStack(alignment: .leading, spacing: 8) {
                    Label(folder.name, systemImage: "folder")
                    if let failure = store.failures[folder.id] {
                        Text(failure).font(.caption).foregroundStyle(.secondary)
                        Button("フォルダを再選択") {
                            replacing = folder.id
                            showPicker = true
                        }
                    }
                }
            }
            .onDelete { offsets in store.remove(Set(offsets.map { store.folders[$0].id })) }
            Button {
                replacing = nil
                showPicker = true
            } label: { Label("フォルダを追加", systemImage: "folder.badge.plus") }
        }
        .navigationTitle("フォルダ管理")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { Task { await store.refresh() } } label: { Label("更新", systemImage: "arrow.clockwise") }
                    .disabled(store.refreshing)
            }
            ToolbarItem(placement: .topBarLeading) { EditButton() }
        }
        .refreshable { await store.refresh() }
        .sheet(isPresented: $showPicker) {
            FolderPicker { url in
                let id = replacing
                Task { await store.add(url, replacing: id) }
            }
        }
    }
}

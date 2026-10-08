import SwiftUI

@MainActor
struct LibraryView: View {
    @StateObject private var store = LibraryStore()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ScaledMetric(relativeTo: .body) private var compactTileWidth = 140
    @ScaledMetric(relativeTo: .body) private var regularTileWidth = 180
    @State private var showPicker = false
    @State private var document: OpenedDocument?
    @State private var activeAccess: OpenedDocument?
    @State private var opening = false
    @State private var visibleItemID: String?
    private var gridSpacing: CGFloat { horizontalSizeClass == .regular ? 20 : 12 }
    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: horizontalSizeClass == .regular ? regularTileWidth : compactTileWidth),
                  spacing: gridSpacing, alignment: .top)]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                if store.folders.isEmpty {
                    ContentUnavailableView {
                        Label("フォルダが未登録です", systemImage: "folder")
                    } actions: {
                        Button("フォルダを追加") { showPicker = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    if !store.failures.isEmpty {
                        NavigationLink {
                            FolderManagementView(store: store)
                        } label: {
                            Label("アクセスできないフォルダがあります", systemImage: "exclamationmark.triangle")
                                .font(.subheadline)
                        }
                        .padding(.horizontal)
                    }
                    if store.documents.isEmpty && !store.refreshing {
                        ContentUnavailableView("資料がありません", systemImage: "doc")
                    }
                    LazyVGrid(columns: columns, alignment: .leading, spacing: gridSpacing) {
                        ForEach(store.documents) { item in
                            if let folder = store.folders.first(where: { $0.id == item.folderID }) {
                                Button { open(item, in: folder) } label: {
                                    DocumentTile(item: item, folder: folder)
                                }
                                .buttonStyle(.plain)
                                .hoverEffect(.highlight)
                                .id(item.id)
                                .disabled(opening)
                                .accessibilityLabel("\(item.name)、\(item.format.rawValue.uppercased())")
                            }
                        }
                    }
                    .scrollTargetLayout()
                    .padding(horizontalSizeClass == .regular ? 24 : 16)
                }
            }
            .scrollPosition(id: $visibleItemID, anchor: .top)
            .refreshable { await store.refresh() }
            .navigationTitle("ライブラリ")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        FolderManagementView(store: store)
                    } label: { Label("フォルダ管理", systemImage: "folder.badge.gearshape") }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { Task { await store.refresh() } } label: { Label("更新", systemImage: "arrow.clockwise") }
                        .keyboardShortcut("r", modifiers: .command)
                        .disabled(store.refreshing)
                    Button { showPicker = true } label: { Label("フォルダを追加", systemImage: "folder.badge.plus") }
                        .keyboardShortcut("o", modifiers: .command)
                }
            }
            .overlay {
                if opening {
                    ProgressView("読み込み中…")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .overlay(alignment: .bottom) {
                if store.refreshing { ProgressView().padding().background(.regularMaterial, in: Capsule()) }
            }
        }
        .sheet(isPresented: $showPicker) {
            FolderPicker { url in Task { await store.add(url) } }
        }
        .fullScreenCover(item: $document, onDismiss: {
            activeAccess?.endAccess()
            activeAccess = nil
        }) { DocumentViewer(document: $0) }
        .alert("読み込めません", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
        .task { await store.refresh() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await store.refresh() } }
        }
    }

    private func open(_ item: LibraryDocument, in folder: RegisteredFolder) {
        guard !opening else { return }
        opening = true
        Task { @MainActor in
            do {
                let opened = try await Task.detached(priority: .userInitiated) {
                    try FileAccessService.open(item, in: folder)
                }.value
                activeAccess = opened
                document = opened
            } catch {
                store.errorMessage = error.localizedDescription
                await store.refresh()
            }
            opening = false
        }
    }
}

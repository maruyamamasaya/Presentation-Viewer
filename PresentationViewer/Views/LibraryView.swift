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
    private var visibleDocuments: [LibraryDocument] { store.documents.filter { $0.format != .svg } }
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
                    if visibleDocuments.isEmpty && !store.refreshing {
                        ContentUnavailableView("資料がありません", systemImage: "doc")
                    }
                    LazyVGrid(columns: columns, alignment: .leading, spacing: gridSpacing) {
                        ForEach(visibleDocuments) { item in
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
        }) { opened in
            LocalDocumentReader(initial: opened, items: store.documents, folders: store.folders)
        }
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

@MainActor
private struct LocalDocumentReader: View {
    let initial: OpenedDocument
    let items: [LibraryDocument]
    let folders: [RegisteredFolder]
    @State private var current: OpenedDocument?
    @State private var acquired: OpenedDocument?
    @State private var busy = false
    @State private var error: String?
    private var document: OpenedDocument { current ?? initial }
    private var pages: [LibraryDocument] {
        items.filter { $0.format == .png && $0.url.deletingLastPathComponent() == initial.url.deletingLastPathComponent() }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
    private var controls: ImagePageControls? {
        guard initial.format == .png, pages.count > 1,
              let index = pages.firstIndex(where: { $0.url.lastPathComponent == document.url.lastPathComponent }) else { return nil }
        return ImagePageControls(canPrevious: !busy && index > 0, canNext: !busy && index + 1 < pages.count,
            previous: { if index > 0 { move(to: pages[index - 1]) } },
            next: { if index + 1 < pages.count { move(to: pages[index + 1]) } })
    }
    var body: some View {
        DocumentViewer(document: document, imagePages: controls)
            .overlay { if busy { ProgressView("読み込み中…").padding().background(.regularMaterial) } }
            .alert("読み込めません", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
            .onDisappear { acquired?.endAccess(); acquired = nil }
    }
    private func move(to item: LibraryDocument) {
        guard !busy, let folder = folders.first(where: { $0.id == item.folderID }) else { return }
        busy = true
        Task {
            do {
                let opened = try await Task.detached { try FileAccessService.open(item, in: folder) }.value
                let old = acquired
                current = opened; acquired = opened
                old?.endAccess()
            } catch { self.error = error.localizedDescription }
            busy = false
        }
    }
}

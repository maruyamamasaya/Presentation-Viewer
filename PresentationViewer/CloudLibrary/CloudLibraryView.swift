import SwiftUI
import LibraryOrganizationUI
import Charts

private struct CloudReading: Identifiable {
    let id = UUID()
    let diagram: CloudDiagram
    let files: [CloudFile]
    let initial: CloudFile
    let document: OpenedDocument
    let offline: Bool
}

@MainActor
struct CloudLibraryView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store: CloudLibraryStore
    @State private var drawerPresented = false
    private var phoneUI: Bool { UIDevice.current.userInterfaceIdiom == .phone }
    @State private var selectedShelf = "all"
    @State private var selecting = false
    @State private var selectedDocuments = Set<String>()
    @State private var folderName = ""
    @State private var showFolderDialog = false
    @State private var moving = false
    @State private var syncLab: SyncLabSession?
    @State private var selectedGroup = "すべて"
    @State private var selectedTag = ""
    @State private var classificationDraft: CloudDiagram?
    @State private var query = ""
    @State private var searchScope = "すべて"
    @State private var showSearch = false
    @FocusState private var searchFocused: Bool
    @State private var reading: CloudReading?
    @State private var collectionDraft: CloudCollection?
    @State private var collectionReading: CloudCollectionReading?
    @State private var opening = false
    @State private var showCapacity = false
    @State private var showClearDocuments = false
    @State private var showHidden = false
    @State private var hideCandidate: CloudDiagram?
    private let costFiles: CloudFileStore
    private let api: any CloudLibraryAPI
    let onSettings: (() -> Void)?
    let onLogout: (() -> Void)?
    let onReauthenticate: (() -> Void)?
    let production: Bool
    let kind: CloudLibraryKind
    init(files: CloudFileStore, kind: CloudLibraryKind = .presentations, api: any CloudLibraryAPI = MockCloudAPI(), production: Bool = false, onSettings: (() -> Void)? = nil, onLogout: (() -> Void)? = nil, onReauthenticate: (() -> Void)? = nil) {
        self.costFiles = files
        self.kind = kind
        self.api = api
        self.production = production; self.onSettings = onSettings; self.onLogout = onLogout
        self.onReauthenticate = onReauthenticate
        _store = StateObject(wrappedValue: CloudLibraryStore(api: api, files: files))
    }
    private var savedDiagrams: [CloudDiagram] {
        var seen = Set<String>()
        return store.saved.filter { $0.file.format != .svg }.map(\.diagram).filter { seen.insert("\($0.id)-\($0.version)").inserted }
    }
    private var diagrams: [CloudDiagram] {
        var seen = Set<String>()
        let candidates = showHidden ? store.hiddenDiagrams :
            store.items.map { store.preferredLocalVersion($0) } + (store.localDiagrams + savedDiagrams).sorted { $0.version > $1.version } + store.collections.flatMap(\.members)
        return candidates.filter {
            (showHidden || !store.isHidden($0)) && kind.contains($0) && !$0.formats.allSatisfy { $0 == .svg } && matchesSearch($0) && matchesClassification($0) && matchesFolder($0)
        }.filter { seen.insert($0.id.lowercased()).inserted }
    }
    private var visibleCollections: [CloudCollection] {
        guard !selecting, selectedShelf == "all", kind == .illustrations, !showHidden, selectedGroup == "すべて", selectedTag.isEmpty else { return [] }
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.collections.filter { collection in
            !store.members(of: collection).isEmpty && (term.isEmpty || collection.title.localizedCaseInsensitiveContains(term) || store.members(of: collection).contains(where: matchesSearch))
        }
    }
    private var looseDiagrams: [CloudDiagram] {
        guard kind == .illustrations, !showHidden else { return diagrams }
        let grouped = Set(visibleCollections.flatMap { store.members(of: $0).map { $0.id.lowercased() } })
        return diagrams.filter { !grouped.contains($0.id.lowercased()) }
    }
    private var collectionChoices: [CloudDiagram] {
        var seen = Set<String>()
        return (store.items + savedDiagrams).filter { kind.contains($0) && !store.isHidden($0) && ($0.formats.contains(.png) || $0.formats.contains(.pdf)) }
            .sorted { $0.version > $1.version }.filter { seen.insert($0.id.lowercased()).inserted }
    }
    private var apiScope: String { searchScope == "タイトル" ? "title" : searchScope == "タグ" ? "tags" : "all" }
    private var searchRequest: String { "\(showHidden)-\(query)-\(apiScope)" }
    private func refresh(more: Bool = false) async {
        if showHidden { await store.reloadSaved(); return }
        await store.refresh(query: "", scope: "all", more: more) }
    var body: some View {
        GeometryReader { geometry in
        let landscapePhone = UIDevice.current.userInterfaceIdiom == .phone && geometry.size.width > geometry.size.height
        let landscapeColumns = dynamicTypeSize.isAccessibilitySize || geometry.size.width < 600 ? 2 : 3
        NavigationStack {
            VStack(spacing: 0) {
                if !phoneUI {
                    classificationControls
                    if showSearch { searchControls }
                }
                if selecting {
                    HStack {
                        Text("\(selectedDocuments.count)件を選択")
                        Button("すべて選択") { selectedDocuments = Set(diagrams.map { $0.id.lowercased() }) }
                        Menu("フォルダへ移動") {
                            Button("未整理") { moveSelection(to: nil) }
                            ForEach(store.organization.orderedFolders) { folder in
                                Button(store.folderPath(folder.id)) { moveSelection(to: folder.id) }
                            }
                        }.disabled(selectedDocuments.isEmpty || moving)
                        Button("完了") { selecting = false; selectedDocuments.removeAll() }
                    }.font(.subheadline).padding(8)
                }
                if !phoneUI { folderControls }
                ScrollView {
                LazyVStack(alignment: .leading, spacing: 20) {
                    if showHidden {
                        Text("このiPhoneで非表示にした資料です。表示に戻せます。").font(.caption).foregroundStyle(.secondary)
                    }
                    LazyVGrid(columns: landscapePhone
                              ? Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: landscapeColumns)
                              : [GridItem(.adaptive(minimum: 260), spacing: 20)], spacing: landscapePhone ? 12 : 20) {
                        ForEach(visibleCollections) { collection in
                            Button { openCollection(collection) } label: {
                                if let first = store.members(of: collection).first {
                                    CloudCover(diagram: first, store: store, offline: isSavedOnly(first), coverFocused: landscapePhone,
                                               titleOverride: collection.title,
                                               captionOverride: "\(store.members(of: collection).count)件のまとめ",
                                               savedOverride: store.members(of: collection).allSatisfy { member in store.saved.contains { $0.diagram.id == member.id && $0.diagram.version == member.version } })
                                }
                            }.buttonStyle(.plain).disabled(opening || store.busy)
                            .accessibilityLabel("\(collection.title)のまとめを読む")
                            .contextMenu {
                                Menu("資料のグループ・タグ", systemImage: "tag") {
                                    ForEach(store.members(of: collection)) { member in
                                        Button(member.title) { classificationDraft = member }
                                    }
                                }
                                Button("まとめを編集", systemImage: "pencil") { collectionDraft = collection }
                                Button("まとめを解除", systemImage: "rectangle.stack.badge.minus", role: .destructive) { Task { _ = await store.removeCollection(collection.id) } }
                            }
                            .overlay(alignment: .topTrailing) {
                                Menu {
                                    Menu("資料のグループ・タグ", systemImage: "tag") {
                                        ForEach(store.members(of: collection)) { member in
                                            Button(member.title) { classificationDraft = member }
                                        }
                                    }
                                    Button("まとめを編集", systemImage: "pencil") { collectionDraft = collection }
                                    Button("まとめを解除", systemImage: "rectangle.stack.badge.minus", role: .destructive) { Task { _ = await store.removeCollection(collection.id) } }
                                } label: { Image(systemName: "ellipsis.circle.fill").font(.title2).padding(8).background(.regularMaterial, in: Circle()) }.padding(8)
                            }
                        }
                        ForEach(looseDiagrams, id: \.selfKey) { diagram in
                            diagramCard(diagram, landscapePhone: landscapePhone)
                        }
                    }
                    if looseDiagrams.isEmpty && visibleCollections.isEmpty && !store.busy {
                        ContentUnavailableView(showHidden ? "非表示の資料はありません" : "資料が見つかりません",
                                               systemImage: showHidden ? "eye.slash" : "magnifyingglass",
                                               description: Text(showHidden ? "資料カードのメニューから非表示にできます。" : query.isEmpty ? "下に引いて一覧を更新してください。保存した資料は通信なしでも表示されます。" : "グループ・タグや検索条件を変えてみてください。"))
                    }
                    if !showHidden, let cursor = store.nextCursor {
                        if store.paginationFailed {
                            Button("読み込みを再試行") { Task { await store.loadNextPage(cursor: cursor) } }
                        } else {
                            ProgressView().frame(maxWidth: .infinity).padding()
                                .task(id: cursor) { await store.loadNextPage(cursor: cursor) }
                        }
                    }
                }.padding().padding(.bottom, phoneUI ? 60 : 0)
            }
            }
            .navigationTitle(showHidden ? "非表示の資料" : kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSearch.toggle()
                        searchFocused = showSearch
                        if !showSearch { query = ""; searchScope = "すべて" }
                    } label: { Image(systemName: showSearch ? "xmark" : "magnifyingglass") }
                    .accessibilityLabel(showSearch ? "検索を閉じる" : "資料を検索")
                }
                ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    libraryActions
                } label: { Label("その他", systemImage: "ellipsis") }.disabled(opening || store.busy)
                }
            }
            .toolbar(phoneUI ? .hidden : .visible, for: .navigationBar)
            .overlay {
                if phoneUI {
                    LibraryDrawer(isPresented: $drawerPresented, filterSummary: [selectedShelf == "unfiled" ? "未整理" : UUID(uuidString: selectedShelf).map(store.folderPath) ?? "", showHidden ? "非表示" : "", selectedGroup == "すべて" ? "" : selectedGroup, selectedTag, query].filter { !$0.isEmpty }.joined(separator: " · ")) {
                        folderControls
                        Text("検索").font(.headline)
                        searchControls
                        Button("検索結果を見る") { searchFocused = false; withAnimation { drawerPresented = false } }
                            .frame(minHeight: 44)
                        Text("グループ").font(.headline)
                        ForEach(["すべて"] + LibraryGroup.allCases.map(\.rawValue), id: \.self) { group in
                            Button {
                                selectedGroup = group
                                withAnimation { drawerPresented = false }
                            } label: {
                                HStack { Text(group); Spacer(); if selectedGroup == group { Image(systemName: "checkmark") } }.frame(minHeight: 44)
                            }.buttonStyle(.plain).accessibilityAddTraits(selectedGroup == group ? .isSelected : [])
                        }
                        Text("タグ").font(.headline)
                        ForEach([""] + Array(Set(availableTags + (selectedTag.isEmpty ? [] : [selectedTag]))).sorted(), id: \.self) { tag in
                            Button {
                                selectedTag = tag
                                withAnimation { drawerPresented = false }
                            } label: {
                                HStack { Text(tag.isEmpty ? "すべてのタグ" : tag); Spacer(); if selectedTag == tag { Image(systemName: "checkmark") } }.frame(minHeight: 44)
                            }.buttonStyle(.plain).accessibilityAddTraits(selectedTag == tag ? .isSelected : [])
                        }
                        Divider()
                        Menu { libraryActions } label: { Label("管理・設定", systemImage: "ellipsis").frame(minHeight: 44) }
                            .disabled(opening || store.busy)
                    }
                }
            }
            .overlay { if opening { ProgressView("資料を開いています").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)) } }
            .refreshable { await store.reloadSaved(); await refresh() }
            .task { await store.reloadSaved() }
            .onAppear { Task { await store.reloadSaved() } }
            .task(id: searchRequest) {
                if showHidden { await store.reloadSaved() }
                else {
                    do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
                    await refresh()
                }
            }
            .onChange(of: selectedShelf) { _, _ in selectedDocuments.removeAll() }
            .onChange(of: diagrams.map { $0.id.lowercased() }) { _, ids in selectedDocuments.formIntersection(Set(ids)) }
            .onChange(of: showHidden) { _, _ in selecting = false; selectedDocuments.removeAll() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await store.reloadSaved(); await refresh() } }
            }
        }
        .alert("フォルダを作成", isPresented: $showFolderDialog) {
            TextField("フォルダ名", text: $folderName)
            Button("作成") { Task { if await store.createFolder(folderName, parentID: UUID(uuidString: selectedShelf)) { folderName = "" } } }
            Button("キャンセル", role: .cancel) {}
        } message: { Text("フォルダ選択中なら、その中に作成します。") }
        .confirmationDialog("端末の資料をすべて削除しますか？", isPresented: $showClearDocuments, titleVisibility: .visible) {
            Button("端末の資料を削除", role: .destructive) { Task { await store.clearLocalDocuments() } }
        } message: {
            Text("保存済み資料と一時キャッシュを両ライブラリから削除します。S3の正本、ローカル資料タブのファイル、フォルダ・まとめ・非表示・グループ・タグの設定は残ります。再取得には通信が必要です。")
        }
        .sheet(item: $syncLab) { SyncLabView(session: $0) }
        .sheet(item: $classificationDraft) { diagram in
            LibraryClassificationEditor(diagram: diagram, store: store)
        }
        .sheet(isPresented: $showCapacity) { CloudCapacityView(api: api, production: production, files: costFiles) }
        .sheet(item: $collectionDraft) { draft in
            CloudCollectionEditor(collection: draft, choices: collectionChoices, store: store)
        }
        .fullScreenCover(item: $collectionReading) { CloudCollectionReader(reading: $0, store: store) }
        .fullScreenCover(item: $reading) { CloudReader(reading: $0, store: store, onReauthenticate: onReauthenticate) }
        .alert("このiPhoneで非表示にしますか？", isPresented: Binding(get: { hideCandidate != nil }, set: { if !$0 { hideCandidate = nil } })) {
            Button("キャンセル", role: .cancel) { hideCandidate = nil }
            Button("非表示にする", role: .destructive) {
                if let diagram = hideCandidate { Task { _ = await store.setHidden(diagram, hidden: true) } }
                hideCandidate = nil
            }
        } message: { Text("「\(hideCandidate?.title ?? "")」をこのiPhoneの一覧から隠します。「非表示の資料」から戻せます。クラウドの資料と保存したファイルは残ります。") }
        .alert("操作を完了できません", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            if store.errorMessage == CloudError.authentication.errorDescription, let onReauthenticate {
                Button("ログインし直す") { store.errorMessage = nil; onReauthenticate() }
            }
            Button("OK") { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
        }
    }
    private func diagramCard(_ diagram: CloudDiagram, landscapePhone: Bool) -> some View {
                            Button {
                                if selecting {
                                    let id = diagram.id.lowercased()
                                    if !selectedDocuments.insert(id).inserted { selectedDocuments.remove(id) }
                                } else if !showHidden { open(diagram) }
                            } label: {
                                CloudCover(diagram: diagram, store: store, offline: isSavedOnly(diagram), coverFocused: landscapePhone, showHidden: showHidden)
                            }
                            .buttonStyle(.plain).disabled(opening || store.busy)
                            .accessibilityLabel(selecting ? "\(diagram.title)を選択" : showHidden ? diagram.title : "\(diagram.title)を読む")
                            .accessibilityValue(selecting && selectedDocuments.contains(diagram.id.lowercased()) ? "選択中" : "未選択")
                            .overlay(alignment: .topLeading) {
                                if selecting { Image(systemName: selectedDocuments.contains(diagram.id.lowercased()) ? "checkmark.circle.fill" : "circle").font(.title).padding(8).background(.regularMaterial, in: Circle()).padding(4).allowsHitTesting(false) }
                            }
                            .contextMenu {
                                Button("グループ・タグを編集", systemImage: "tag") { classificationDraft = diagram }
                                if !showHidden || !store.hiddenDiagrams.isEmpty {
                                    if showHidden {
                                        Button("表示に戻す", systemImage: "arrow.uturn.backward") { Task { _ = await store.setHidden(diagram, hidden: false) } }
                                    } else {
                                        Button("非表示にする", systemImage: "eye.slash", role: .destructive) { hideCandidate = diagram }
                                    }
                                }
                            }
                            .overlay(alignment: .bottomTrailing) {
                                if !selecting, !showHidden, let update = store.availableUpdate(diagram) {
                                    Button { open(update, updating: true) } label: {
                                        Label("更新あり", systemImage: "arrow.down.circle")
                                            .font(.caption).padding(8).background(.regularMaterial, in: Capsule())
                                    }.buttonStyle(.plain).padding(8).disabled(opening || store.busy)
                                    .accessibilityLabel("\(diagram.title)を最新版に更新")
                                }
                            }
                            .overlay(alignment: .topTrailing) {
                                if !selecting, !showHidden || !store.hiddenDiagrams.isEmpty {
                                    Menu {
                                        Button("グループ・タグを編集", systemImage: "tag") { classificationDraft = diagram }
                                        if showHidden {
                                            Button("表示に戻す", systemImage: "arrow.uturn.backward") { Task { _ = await store.setHidden(diagram, hidden: false) } }
                                        } else {
                                            Button("非表示にする", systemImage: "eye.slash", role: .destructive) { hideCandidate = diagram }
                                        }
                                    } label: { Image(systemName: "ellipsis.circle.fill").font(.title2).padding(8).background(.regularMaterial, in: Circle()) }
                                    .padding(8).disabled(opening || store.busy).accessibilityLabel("\(diagram.title)の操作")
                                }
                            }
    }
    private func matchesFolder(_ diagram: CloudDiagram) -> Bool {
        let assignment = store.organization.assignments[diagram.id.lowercased()]
        if selectedShelf == "unfiled" { return assignment == nil }
        if let id = UUID(uuidString: selectedShelf) { return assignment.map { store.organization.descendants(of: id).contains($0) } ?? false }
        return true
    }
    private func moveSelection(to folderID: UUID?) {
        let ids = selectedDocuments; moving = true
        Task {
            if await store.moveDocuments(ids, to: folderID) { selectedDocuments.removeAll(); selecting = false }
            moving = false
        }
    }
    private var folderControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("本棚").font(.headline)
            Picker("フォルダ", selection: $selectedShelf) {
                Text("すべての資料").tag("all")
                Text("未整理").tag("unfiled")
                ForEach(store.organization.orderedFolders) { folder in Text(store.folderPath(folder.id)).tag(folder.id.uuidString) }
            }.pickerStyle(.menu)
            Button("フォルダを作成", systemImage: "folder.badge.plus") { folderName = ""; showFolderDialog = true }
            if let id = UUID(uuidString: selectedShelf) {
                Button("フォルダを解除", systemImage: "folder.badge.minus") {
                    Task { if await store.removeFolder(id) { selectedShelf = "all"; selectedDocuments.removeAll() } }
                }
            }
            Button(selecting ? "選択を終了" : "資料を選択", systemImage: "checkmark.circle") {
                selecting.toggle(); selectedDocuments.removeAll(); drawerPresented = false
            }.disabled(showHidden)
        }
    }
    private var availableTags: [String] {
        let candidates = showHidden ? store.hiddenDiagrams : store.items + store.localDiagrams + savedDiagrams
        return LibraryClassification.normalizedTags(candidates.filter {
            kind.contains($0) && (showHidden || !store.isHidden($0))
        }.flatMap { store.classification($0).tags }).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }
    private func matchesClassification(_ diagram: CloudDiagram) -> Bool {
        let value = store.classification(diagram)
        return (selectedGroup == "すべて" || value.group.rawValue == selectedGroup)
            && (selectedTag.isEmpty || value.tags.contains { $0.localizedCaseInsensitiveCompare(selectedTag) == .orderedSame })
    }
    @ViewBuilder private var libraryActions: some View {
                    Button("同期の検証", systemImage: "arrow.triangle.2.circlepath") { Task { syncLab = await store.makeSyncLab() } }
                    Button(showHidden ? "資料一覧に戻る" : "非表示の資料", systemImage: showHidden ? "doc.richtext" : "eye.slash") { showHidden.toggle() }
                    if kind == .illustrations && !showHidden {
                        Button("図解をまとめる", systemImage: "rectangle.stack.badge.plus") { collectionDraft = CloudCollection(id: UUID(), title: "", members: []) }
                    }
                    Button("保存料金シミュレーション", systemImage: "externaldrive") { showCapacity = true }
                    if let onSettings { Button("接続設定", systemImage: "gear") { onSettings() } }
                    if let onReauthenticate { Button("ログインし直す", systemImage: "person.crop.circle.badge.checkmark", action: onReauthenticate) }
                    if let onLogout { Button("ログアウト", systemImage: "rectangle.portrait.and.arrow.right") { onLogout() } }
                    Button("一覧を更新", systemImage: "arrow.clockwise") { Task { await refresh() } }
                    Button("一時キャッシュを削除", systemImage: "trash") { Task { await store.clearCache() } }
                    Button("端末の資料をすべて削除", systemImage: "trash", role: .destructive) { showClearDocuments = true }
    }
    private var classificationControls: some View {
        VStack(spacing: 8) {
            Picker("グループ", selection: $selectedGroup) {
                Text("すべて").tag("すべて")
                ForEach(LibraryGroup.allCases, id: \.self) { Text($0.rawValue).tag($0.rawValue) }
            }.pickerStyle(.segmented)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack {
                    tagButton("すべてのタグ", value: "")
                    ForEach(availableTags, id: \.self) { tagButton($0, value: $0) }
                    if !selectedTag.isEmpty && !availableTags.contains(selectedTag) { tagButton(selectedTag, value: selectedTag) }
                }
            }
        }.padding(.horizontal).padding(.vertical, 8)
    }
    private func tagButton(_ title: String, value: String) -> some View {
        Button { selectedTag = value } label: {
            Text(title).font(.subheadline).padding(.horizontal, 12).padding(.vertical, 8)
                .background(selectedTag == value ? Color.accentColor.opacity(0.18) : Color(uiColor: .secondarySystemBackground), in: Capsule())
        }.buttonStyle(.plain).accessibilityAddTraits(selectedTag == value ? .isSelected : [])
    }
    private var searchControls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("タイトル・タグを検索", text: $query)
                    .focused($searchFocused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .accessibilityLabel("\(kind.title)を検索")
                if !query.isEmpty {
                    Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                        .accessibilityLabel("検索をクリア")
                }
            }
            .padding(12)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
            Picker("検索対象", selection: $searchScope) {
                ForEach(["すべて", "タイトル", "タグ"], id: \.self) { Text($0).tag($0) }
            }.pickerStyle(.segmented)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
    }
    private func matchesSearch(_ diagram: CloudDiagram) -> Bool {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return true }
        let titleMatches = diagram.title.localizedCaseInsensitiveContains(term)
        let tagMatches = store.classification(diagram).tags.contains { $0.localizedCaseInsensitiveContains(term) }
        switch searchScope {
        case "タイトル": return titleMatches
        case "タグ": return tagMatches
        default: return titleMatches || tagMatches
        }
    }
    private func isSavedOnly(_ diagram: CloudDiagram) -> Bool {
        !store.items.contains { $0.id == diagram.id && $0.version == diagram.version }
    }
    private func openCollection(_ collection: CloudCollection) {
        guard !opening else { return }
        opening = true
        Task {
            defer { opening = false }
            do {
                let pages = try await store.collectionPages(collection)
                let first = pages[0]
                if let document = await store.open(first.diagram, file: first.file, persist: false) {
                    collectionReading = CloudCollectionReading(collection: collection, pages: pages, document: document)
                }
            } catch { store.errorMessage = "まとめを開けませんでした。非表示の資料や接続状態を確認してください。" }
        }
    }
    private func open(_ diagram: CloudDiagram, updating: Bool = false) {
        guard !opening else { return }
        opening = true
        let offline = !updating && (store.offline || isSavedOnly(diagram))
        Task {
            defer { opening = false }
            do {
                let localFiles = try await store.localReadingFiles(diagram).filter { $0.format != .svg }
                let files: [CloudFile]
                if !updating && !localFiles.isEmpty { files = localFiles }
                else if offline { files = localFiles }
                else { files = try await store.detail(diagram).files.filter { $0.format != .svg } }
                guard let file = preferredCloudFile(localFiles) ?? preferredCloudFile(files) else { throw CloudError.unavailable }
                let keepSaved = updating && store.saved.contains { $0.diagram.id.lowercased() == diagram.id.lowercased() }
                let doc = await store.open(diagram, file: file, persist: keepSaved)
                if doc != nil { await store.reloadSaved() }
                if let doc { reading = CloudReading(diagram: diagram, files: files, initial: file, document: doc, offline: offline) }
            } catch { store.errorMessage = "資料を開けませんでした。もう一度お試しください。" }
        }
    }
}
private extension CloudDiagram { var selfKey: String { "\(id)-\(version)" } }

@MainActor
private struct CloudCover: View {
    let diagram: CloudDiagram
    @ObservedObject var store: CloudLibraryStore
    let offline: Bool
    var coverFocused = false
    var showHidden = false
    var titleOverride: String? = nil
    var captionOverride: String? = nil
    var savedOverride: Bool? = nil
    @State private var image: UIImage?
    var body: some View {
        VStack(alignment: .leading, spacing: coverFocused ? 8 : 12) {
            ZStack {
                Color(uiColor: .secondarySystemBackground)
                if let image { Image(uiImage: image).resizable().scaledToFit() }
                else { Image(systemName: "doc.richtext").font(.largeTitle).foregroundStyle(.secondary) }
            }.aspectRatio(16/9, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 12))
            Text((titleOverride ?? diagram.title).replacingOccurrences(of: "（モック）", with: "")).font(.headline).foregroundStyle(.primary).lineLimit(2)
            HStack {
                Text(captionOverride ?? "\(diagram.pageCount)ページ").foregroundStyle(.secondary)
                Spacer()
            }.font(.caption)
        }
        .padding(coverFocused ? 6 : 12).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .task(id: "\(diagram.selfKey)-\(offline)-\(store.saved.filter { $0.diagram.id == diagram.id && $0.diagram.version == diagram.version }.count)") {
            if !showHidden { image = await store.thumbnail(diagram, offline: offline) }
        }
    }
}

@MainActor
private struct CloudReader: View {
    let reading: CloudReading
    @ObservedObject var store: CloudLibraryStore
    @State private var document: OpenedDocument
    @State private var file: CloudFile
    @State private var saving = false
    @State private var switching = false
    @State private var showInfo = false
    let onReauthenticate: (() -> Void)?
    init(reading: CloudReading, store: CloudLibraryStore, onReauthenticate: (() -> Void)? = nil) {
        self.onReauthenticate = onReauthenticate
        self.reading = reading; self.store = store
        _document = State(initialValue: reading.document); _file = State(initialValue: reading.initial)
    }
    private var record: SavedCloudFile { SavedCloudFile(diagram: reading.diagram, file: file) }
    var body: some View {
        DocumentViewer(document: document, libraryActions: AnyView(actions), imagePages: imagePageControls,
                       displayIntent: CloudLibraryKind.illustrations.contains(reading.diagram) ? .illustration : .presentation)
            .id(file.format == .png ? "png-pages" : document.id.uuidString)
            .overlay(alignment: .bottom) {
                if saving || switching { ProgressView(saving ? "保存中…" : "読み込み中…").padding().background(.regularMaterial, in: Capsule()).padding(.bottom, 30) }
            }
            .sheet(isPresented: $showInfo) {
                NavigationStack {
                    Form {
                        Section("資料") { Text(reading.diagram.title); Text("版 \(reading.diagram.version) · \(reading.diagram.pageCount)ページ") }
                        Section("ファイル") { Text(file.format.rawValue.uppercased()); Text("\(file.sizeBytes.formatted()) bytes"); Text(file.sha256).font(.caption.monospaced()).textSelection(.enabled) }
                        if reading.files.contains(where: { $0.format == .pptx }) {
                            Section { Text("PPTXはQuick Lookで書体や折り返しが変わる場合があります。見た目を保つ閲覧にはPDFを利用してください。") }
                        }
                    }.navigationTitle("資料情報").toolbar { Button("閉じる") { showInfo = false } }
                }
            }
            .alert("操作を完了できません", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
                if store.errorMessage == CloudError.authentication.errorDescription, let onReauthenticate {
                    Button("ログインし直す") { store.errorMessage = nil; onReauthenticate() }
                }
                Button("OK") { store.errorMessage = nil }
            } message: { Text(store.errorMessage ?? "") }
    }
    private var actions: some View {
        HStack {
            Button {
                saving = true
                Task { _ = await store.saveOpened(document, record: record); saving = false }
            } label: { Image(systemName: store.isSaved(record) ? "bookmark.fill" : "bookmark") }
                .accessibilityLabel(store.isSaved(record) ? "保存済み" : "資料を保存")
                .disabled(store.isSaved(record) || saving || switching || store.busy)
            Menu {
                ForEach([CloudFormat.pdf, .png, .pptx].filter { f in reading.files.contains(where: { $0.format == f }) }, id: \.self) { format in
                    if let selected = reading.files.first(where: { $0.format == format && (format != .png || $0.page == file.page) }) ?? reading.files.first(where: { $0.format == format }) {
                        Button { switchFile(selected) } label: {
                            if file.format == format { Label(format.rawValue.uppercased(), systemImage: "checkmark") }
                            else { Text(format.rawValue.uppercased()) }
                        }
                    }
                }
                if file.format == .png && reading.files.filter({ $0.format == .png }).count > 1 {
                    Menu("PNGのページ") {
                        ForEach(reading.files.filter { $0.format == .png }, id: \.name) { selected in
                            Button("ページ \(selected.page)") { switchFile(selected) }
                        }
                    }
                }
                Divider()
                Button("資料情報", systemImage: "info.circle") { showInfo = true }
            } label: { Text(file.format.rawValue.uppercased()).font(.subheadline.weight(.semibold)) }.accessibilityLabel("形式を選択、現在\(file.format.rawValue.uppercased())").disabled(saving || switching)
        }
    }
    private var imagePageControls: ImagePageControls? {
        let pages = reading.files.filter { $0.format == .png }.sorted { $0.page < $1.page }
        guard file.format == .png, pages.count > 1, let index = pages.firstIndex(of: file) else { return nil }
        return ImagePageControls(canPrevious: !switching && index > 0,
                                 canNext: !switching && index + 1 < pages.count,
                                 previous: { if index > 0 { switchFile(pages[index - 1]) } },
                                 next: { if index + 1 < pages.count { switchFile(pages[index + 1]) } },
                                 pageIndex: index, pageCount: pages.count,
                                 selectPage: { selected in if pages.indices.contains(selected) { switchFile(pages[selected]) } },
                                 thumbnail: { selected in
                                     guard pages.indices.contains(selected) else { return nil }
                                     return await store.cachedSlideThumbnail(reading.diagram, file: pages[selected])
                                 })
    }
    private func switchFile(_ selected: CloudFile) {
        guard !switching, selected != file else { return }
        switching = true
        Task {
            let doc = await store.open(reading.diagram, file: selected, persist: false)
            if let doc { file = selected; document = doc }
            switching = false
        }
    }
}

@MainActor
private struct CloudCapacityView: View {
    let api: any CloudLibraryAPI
    let production: Bool
    let files: CloudFileStore
    @Environment(\.dismiss) private var dismiss
    @State private var capacity: CloudCapacity?
    @State private var history: [StorageCostSnapshot] = []
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var historyError: String?
    @State private var manual = false
    @State private var gib = 10.0
    @State private var rate = 0.025
    @State private var exchange = 150.0
    @State private var tax = 10.0
    private var measuredGiB: Double { Double(capacity?.sizeBytes ?? 0) / 1_073_741_824 }
    private var estimate: Double? {
        guard manual || capacity != nil else { return nil }
        return StorageCostEstimate.monthlyYen(gib: manual ? gib : measuredGiB, usdPerGiB: rate, yenPerUSD: exchange, taxPercent: tax)
    }
    private func yen(_ amount: Double) -> String { amount.formatted(.currency(code: "JPY").precision(.fractionLength(2))) }
    var body: some View {
        NavigationStack {
            Form {
                Section(production ? "登録資料の保存費（月額試算）" : "サンプルの保存費（月額試算）") {
                    if let estimate { Text(yen(estimate) + "／月").font(.title.bold()).accessibilityLabel("月額試算 " + yen(estimate)) }
                    else { Text("容量を取得するか、有効な条件を入力してください。") }
                    if let capacity {
                        LabeledContent("最新版の資料", value: "\(capacity.documentCount)件")
                        LabeledContent("合計容量", value: ByteCountFormatter.string(fromByteCount: capacity.sizeBytes, countStyle: .binary))
                        LabeledContent("取得日時") { Text(capacity.updatedAt, format: .dateTime.year().month().day().hour().minute()) }
                    }
                    if loading { ProgressView("容量を集計しています…") }
                    if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
                    Button("容量を更新・履歴に記録") { Task { await refresh() } }.disabled(loading)
                    Text("全ライブラリの最新版のPDF・PPTX・PNG等を集計。旧版・S3の過去バージョン・管理ファイル・ゴミ箱は対象外。S3全体の請求額ではありません。ファイル本体はダウンロードしません。")
                    if !production { Text("サンプルです。実際のS3利用量ではありません。") }
                }
                Section("容量と料金の条件") {
                    Toggle("容量を手入力する", isOn: $manual)
                    if manual { numberField("保存容量（GiB）", value: $gib) }
                    numberField("単価（USD／GiB・月）", value: $rate)
                    numberField("為替（円／USD）", value: $exchange)
                    numberField("税率（%）", value: $tax)
                    Text("東京 S3 Standardの参考値：0.025 USD。為替150円・税10%は仮定です。1 GiB = 1,073,741,824 bytes。容量 × 単価 × 為替 × (1 + 税率 / 100)。50 TiBまでの単一料金帯の試算です。")
                    Text("過去版・原本・プレビューなどを含む総量が分かる場合は手入力してください。手入力値は取得履歴には記録しません。")
                    Link("AWS公式の最新料金を確認", destination: URL(string: "https://aws.amazon.com/jp/s3/pricing/")!)
                }
                Section("取得時点の履歴（この端末・最大365回）") {
                    if let historyError { Text(historyError).foregroundStyle(.red) }
                    if history.isEmpty { Text("容量更新後に記録します。自動・日次計測ではありません。") }
                    else {
                        Chart(history) { item in
                            LineMark(x: .value("取得日時", item.date), y: .value("容量 GiB", Double(item.bytes) / 1_073_741_824))
                            PointMark(x: .value("取得日時", item.date), y: .value("容量 GiB", Double(item.bytes) / 1_073_741_824))
                        }.frame(height: 160).chartYAxisLabel("GiB")
                        Chart(history) { item in
                            LineMark(x: .value("取得日時", item.date), y: .value("月額 円", item.monthlyYen))
                            PointMark(x: .value("取得日時", item.date), y: .value("月額 円", item.monthlyYen))
                        }.frame(height: 160).chartYAxisLabel("円／月")
                        Text("料金は各取得時の条件で記録。現在の条件変更で過去の試算は変わりません。")
                    }
                }
                Section("含まれない費用") {
                    Text("ダウンロード通信料・APIリクエスト・認証等の費用、無料枠・クレジット・日割りは反映しません。現在の容量を1か月保持する仮定で、実際の請求や今月の累計ではありません。")
                }
            }
            .navigationTitle("保存料金シミュレーション")
            .toolbar { Button("閉じる") { dismiss() } }
            .task {
                do { history = try await files.costHistory() }
                catch { historyError = "保存済み履歴を読み込めませんでした。" }
            }
        }
    }
    private func numberField(_ title: String, value: Binding<Double>) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(title, value: value, format: .number)
                .keyboardType(.decimalPad).multilineTextAlignment(.trailing)
                .frame(minWidth: 80, maxWidth: 180)
        }
    }
    @MainActor private func refresh() async {
        guard !loading else { return }
        loading = true; errorMessage = nil
        defer { loading = false }
        do {
            let result = try await api.capacity()
            try Task.checkCancellation()
            capacity = result
            guard let cost = StorageCostEstimate.monthlyYen(gib: Double(result.sizeBytes) / 1_073_741_824, usdPerGiB: rate, yenPerUSD: exchange, taxPercent: tax) else {
                errorMessage = "容量は取得しました。料金条件を修正して再度記録してください。"; return
            }
            do {
                history = try await files.recordCost(StorageCostSnapshot(date: result.updatedAt, bytes: result.sizeBytes, monthlyYen: cost))
                historyError = nil
            } catch { historyError = "容量は取得しましたが履歴を保存できませんでした。" }
        } catch {
            if !Task.isCancelled { errorMessage = "更新できませんでした。表示中の容量は前回の取得値です。" }
        }
    }
}

@MainActor
private struct CloudCollectionEditor: View {
    let collection: CloudCollection
    let choices: [CloudDiagram]
    @ObservedObject var store: CloudLibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var members: [CloudDiagram]
    @State private var saving = false
    init(collection: CloudCollection, choices: [CloudDiagram], store: CloudLibraryStore) {
        self.collection = collection; self.choices = choices; self.store = store
        _title = State(initialValue: collection.title); _members = State(initialValue: collection.members)
    }
    var body: some View {
        NavigationStack {
            List {
                Section("まとめの名前") { TextField("例：色即是空の図鑑", text: $title) }
                Section {
                    ForEach(members, id: \.id) { member in
                        HStack {
                            Text(member.title)
                            Spacer()
                            if let index = members.firstIndex(where: { $0.id == member.id }) {
                                Button { members.swapAt(index, index - 1) } label: { Image(systemName: "arrow.up") }
                                    .buttonStyle(.borderless).disabled(index == 0)
                                    .accessibilityLabel("\(member.title)を前へ移動")
                                Button { members.swapAt(index, index + 1) } label: { Image(systemName: "arrow.down") }
                                    .buttonStyle(.borderless).disabled(index + 1 >= members.count)
                                    .accessibilityLabel("\(member.title)を後へ移動")
                            }
                            Button { members.removeAll { $0.id == member.id } } label: { Image(systemName: "minus.circle.fill").foregroundStyle(.red) }
                                .buttonStyle(.borderless).accessibilityLabel("\(member.title)をまとめから外す")
                        }
                    }.onMove { members.move(fromOffsets: $0, toOffset: $1) }
                } header: { Text("読む順番 · \(members.count)件") } footer: { Text("上下のボタンで読む順番を変えられます。まとめはこのiPhoneに保存されます。") }
                Section("追加する図解") {
                    ForEach(choices.filter { candidate in !members.contains { $0.id.lowercased() == candidate.id.lowercased() } }, id: \.id) { member in
                        Button { members.append(member) } label: { Label(member.title, systemImage: "plus.circle") }
                            .disabled(members.count >= 100)
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle(collection.title.isEmpty ? "図解をまとめる" : "まとめを編集")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        saving = true
                        Task {
                            let result = await store.saveCollection(CloudCollection(id: collection.id, title: title.trimmingCharacters(in: .whitespacesAndNewlines), members: members))
                            saving = false
                            if result { dismiss() }
                        }
                    }.disabled(saving || members.isEmpty || title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || title.count > 120)
                }
            }
            .alert("まとめを保存できません", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
                Button("OK") { store.errorMessage = nil }
            } message: { Text(store.errorMessage ?? "") }
        }.interactiveDismissDisabled(saving)
    }
}
private struct CloudCollectionReading: Identifiable {
    let id = UUID()
    let collection: CloudCollection
    let pages: [CloudCollectionPage]
    let document: OpenedDocument
}
@MainActor
private struct CloudCollectionReader: View {
    let reading: CloudCollectionReading
    @ObservedObject var store: CloudLibraryStore
    @State private var document: OpenedDocument
    @State private var index = 0
    @State private var loading = false
    @State private var saving = false
    init(reading: CloudCollectionReading, store: CloudLibraryStore) {
        self.reading = reading; self.store = store; _document = State(initialValue: reading.document)
    }
    private var controls: ImagePageControls {
        ImagePageControls(canPrevious: !loading && !saving && index > 0, canNext: !loading && !saving && index + 1 < reading.pages.count,
                          previous: { move(to: index - 1) }, next: { move(to: index + 1) })
    }
    var body: some View {
        DocumentViewer(document: document, libraryActions: AnyView(actions), imagePages: controls,
                       displayIntent: .illustration, externalPageNavigation: true)
            // Image navigation preserves full-screen state; PDF fallback needs a new PDF session.
            .id(document.format == .png ? "collection-images" : document.id.uuidString)
            .overlay(alignment: .bottom) {
                VStack(spacing: 6) {
                    if loading || saving { ProgressView(saving ? "まとめを保存中…" : "読み込み中…") }
                    Text("\(index + 1) / \(reading.pages.count)").font(.caption.monospacedDigit())
                }.padding(8).background(.regularMaterial, in: Capsule()).padding(.bottom, 12)
            }
            .alert("操作を完了できません", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
                Button("OK") { store.errorMessage = nil }
            } message: { Text(store.errorMessage ?? "") }
    }
    private var actions: some View {
        HStack {
            Text("\(index + 1) / \(reading.pages.count)").font(.caption.monospacedDigit())
                .accessibilityLabel("まとめの\(index + 1)番目、全\(reading.pages.count)件")
            Button {
                saving = true
                Task {
                    for page in reading.pages {
                        if Task.isCancelled { break }
                        guard await store.open(page.diagram, file: page.file, persist: true) != nil else { break }
                    }
                    saving = false
                }
            } label: { Image(systemName: allSaved ? "bookmark.fill" : "bookmark") }
                .accessibilityLabel(allSaved ? "まとめは保存済み" : "まとめをすべて保存")
                .disabled(loading || saving || allSaved || store.busy)
        }
    }
    private var allSaved: Bool {
        reading.pages.allSatisfy { store.isSaved(SavedCloudFile(diagram: $0.diagram, file: $0.file)) }
    }
    private func move(to next: Int) {
        guard !loading, !saving, reading.pages.indices.contains(next) else { return }
        loading = true
        Task {
            let page = reading.pages[next]
            if let opened = await store.open(page.diagram, file: page.file, persist: false) { document = opened; index = next }
            loading = false
        }
    }
}

@MainActor
private struct LibraryClassificationEditor: View {
    @Environment(\.dismiss) private var dismiss
    let diagram: CloudDiagram
    @ObservedObject var store: CloudLibraryStore
    @State private var group: LibraryGroup
    @State private var tags: [String]
    @State private var newTag = ""
    @State private var saving = false
    @State private var failed = false
    init(diagram: CloudDiagram, store: CloudLibraryStore) {
        self.diagram = diagram; self.store = store
        let value = store.classification(diagram)
        _group = State(initialValue: value.group); _tags = State(initialValue: value.tags)
    }
    private func addTag() {
        tags = LibraryClassification.normalizedTags(tags + [newTag]); newTag = ""
    }
    var body: some View {
        NavigationStack {
            Form {
                Section { Text(diagram.title) }
                Section("グループ") {
                    Picker("グループ", selection: $group) {
                        ForEach(LibraryGroup.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }.pickerStyle(.segmented)
                }
                Section("タグ") {
                    ForEach(tags, id: \.self) { tag in
                        HStack {
                            Text(tag)
                            Spacer()
                            Button { tags.removeAll { $0 == tag } } label: { Image(systemName: "minus.circle") }
                                .accessibilityLabel("タグ「\(tag)」を削除")
                        }
                    }
                    HStack {
                        TextField("新しいタグ", text: $newTag).submitLabel(.done).onSubmit { addTag() }
                        Button("追加") { addTag() }.disabled(newTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                Section { Text("分類はこのiPhoneに保存され、同じ資料の新版にも適用されます。").font(.caption).foregroundStyle(.secondary) }
                if failed { Text("保存できませんでした。もう一度お試しください。").foregroundStyle(.red) }
            }
            .disabled(saving)
            .navigationTitle("グループ・タグ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("キャンセル") { dismiss() }.disabled(saving) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        addTag(); saving = true
                        Task {
                            if await store.setClassification(diagram, value: LibraryClassification(group: group, tags: tags)) { dismiss() }
                            else { failed = true }
                            saving = false
                        }
                    }.disabled(saving)
                }
            }
        }
    }
}

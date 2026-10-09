import SwiftUI

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
    @StateObject private var store: CloudLibraryStore
    @State private var query = ""
    @State private var searchScope = "すべて"
    @State private var offline = false
    @State private var reading: CloudReading?
    @State private var opening = false
    let onSettings: (() -> Void)?
    let onLogout: (() -> Void)?
    let production: Bool
    init(files: CloudFileStore, api: any CloudLibraryAPI = MockCloudAPI(), production: Bool = false, onSettings: (() -> Void)? = nil, onLogout: (() -> Void)? = nil) {
        self.production = production; self.onSettings = onSettings; self.onLogout = onLogout
        _store = StateObject(wrappedValue: CloudLibraryStore(api: api, files: files))
    }
    private var savedDiagrams: [CloudDiagram] {
        var seen = Set<String>()
        return store.saved.filter { $0.file.format != .svg }.map(\.diagram).filter { seen.insert("\($0.id)-\($0.version)").inserted }
    }
    private var diagrams: [CloudDiagram] {
        (offline ? savedDiagrams : store.items).filter {
            !$0.formats.allSatisfy { $0 == .svg } && matchesSearch($0)
        }
    }
    private var apiScope: String { searchScope == "タイトル" ? "title" : searchScope == "タグ" ? "tags" : "all" }
    private var searchRequest: String { "\(offline)-\(query)-\(apiScope)" }
    private func refresh(more: Bool = false) async { await store.refresh(query: production ? query.trimmingCharacters(in: .whitespacesAndNewlines) : "", scope: production ? apiScope : "all", more: more) }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                searchControls
                ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Picker("表示する資料", selection: $offline) {
                        Text("すべて").tag(false)
                        Text("保存済み").tag(true)
                    }.pickerStyle(.segmented)
                    if !offline { Label(production ? "クラウド資料" : "サンプル資料", systemImage: "cloud").font(.caption).foregroundStyle(.secondary) }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 20)], spacing: 20) {
                        ForEach(diagrams, id: \.selfKey) { diagram in
                            Button { open(diagram) } label: {
                                CloudCover(diagram: diagram, store: store, offline: offline)
                            }
                            .buttonStyle(.plain).disabled(opening || store.busy)
                            .accessibilityLabel("\(diagram.title)を読む")
                        }
                    }
                    if diagrams.isEmpty && !store.busy {
                        ContentUnavailableView(offline && query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "保存した資料はありません" : "資料が見つかりません",
                                               systemImage: offline ? "bookmark" : "magnifyingglass",
                                               description: Text(offline && query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "資料を開いて、右上の保存ボタンを押してください。" : "検索語や検索対象を変えてみてください。"))
                    }
                    if !offline && store.nextCursor != nil {
                        Button("さらに表示") { Task { await refresh(more: true) } }
                    }
                }.padding()
            }
            }
            .navigationTitle("図解ライブラリ")
            .toolbar {
                Menu {
                    if let onSettings { Button("接続設定", systemImage: "gear") { onSettings() } }
                    if let onLogout { Button("ログアウト", systemImage: "rectangle.portrait.and.arrow.right") { onLogout() } }
                    Button("一覧を更新", systemImage: "arrow.clockwise") { Task { await refresh() } }
                    Button("一時キャッシュを削除", systemImage: "trash") { Task { await store.clearCache() } }
                } label: { Label("その他", systemImage: "ellipsis") }.disabled(opening || store.busy)
            }
            .overlay { if opening { ProgressView("資料を開いています").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)) } }
            .refreshable { if offline { await store.reloadSaved() } else { await refresh() } }
            .task { await store.reloadSaved(); if !production { await refresh() } }
            .task(id: searchRequest) {
                if production && !offline {
                    do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
                    await refresh()
                }
            }
            .onChange(of: offline) { _, _ in Task { await store.reloadSaved() } }
        }
        .fullScreenCover(item: $reading) { CloudReader(reading: $0, store: store) }
        .alert("資料を開けません", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK") { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
    }
    private var searchControls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("タイトル・タグを検索", text: $query)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .accessibilityLabel("図解を検索")
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
        let tagMatches = diagram.tags.contains { $0.localizedCaseInsensitiveContains(term) }
        switch searchScope {
        case "タイトル": return titleMatches
        case "タグ": return tagMatches
        default: return titleMatches || tagMatches
        }
    }
    private func open(_ diagram: CloudDiagram) {
        guard !opening else { return }
        opening = true
        Task {
            defer { opening = false }
            do {
                let files = offline
                    ? store.saved.filter { $0.diagram.id == diagram.id && $0.diagram.version == diagram.version }.map(\.file).filter { $0.format != .svg }
                    : try await store.detail(diagram).files.filter { $0.format != .svg }
                guard let file = preferredCloudFile(files) else { throw CloudError.unavailable }
                let doc = offline
                    ? await store.openSaved(SavedCloudFile(diagram: diagram, file: file))
                    : await store.open(diagram, file: file, persist: false)
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
    @State private var image: UIImage?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                Color(uiColor: .secondarySystemBackground)
                if let image { Image(uiImage: image).resizable().scaledToFit() }
                else { Image(systemName: "doc.richtext").font(.largeTitle).foregroundStyle(.secondary) }
            }.aspectRatio(16/9, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 12))
            Text(diagram.title.replacingOccurrences(of: "（モック）", with: "")).font(.headline).foregroundStyle(.primary).lineLimit(2)
            HStack {
                Text("\(diagram.pageCount)ページ").foregroundStyle(.secondary)
                Spacer()
                if store.saved.contains(where: { $0.diagram.id == diagram.id && $0.diagram.version == diagram.version }) {
                    Label("保存済み", systemImage: "checkmark.circle.fill").foregroundStyle(.secondary)
                }
            }.font(.caption)
        }
        .padding(12).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .task(id: "\(diagram.selfKey)-\(offline)") { image = await store.thumbnail(diagram, offline: offline) }
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
    init(reading: CloudReading, store: CloudLibraryStore) {
        self.reading = reading; self.store = store
        _document = State(initialValue: reading.document); _file = State(initialValue: reading.initial)
    }
    private var record: SavedCloudFile { SavedCloudFile(diagram: reading.diagram, file: file) }
    var body: some View {
        DocumentViewer(document: document, libraryActions: AnyView(actions), imagePages: imagePageControls)
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
                Button("OK") { store.errorMessage = nil }
            } message: { Text(store.errorMessage ?? "") }
    }
    private var actions: some View {
        HStack {
            Button {
                saving = true
                Task { _ = await store.saveOpened(document, record: record); saving = false }
            } label: { Label(store.isSaved(record) ? "保存済み" : "保存", systemImage: store.isSaved(record) ? "bookmark.fill" : "bookmark") }
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
                                 next: { if index + 1 < pages.count { switchFile(pages[index + 1]) } })
    }
    private func switchFile(_ selected: CloudFile) {
        guard !switching, selected != file else { return }
        switching = true
        Task {
            let doc = reading.offline
                ? await store.openSaved(SavedCloudFile(diagram: reading.diagram, file: selected))
                : await store.open(reading.diagram, file: selected, persist: false)
            if let doc { file = selected; document = doc }
            switching = false
        }
    }
}

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
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var store: CloudLibraryStore
    @State private var query = ""
    @State private var searchScope = "すべて"
    @State private var showSearch = false
    @FocusState private var searchFocused: Bool
    @State private var reading: CloudReading?
    @State private var collectionDraft: CloudCollection?
    @State private var collectionReading: CloudCollectionReading?
    @State private var opening = false
    @State private var showCapacity = false
    @State private var showHidden = false
    @State private var hideCandidate: CloudDiagram?
    private let api: any CloudLibraryAPI
    let onSettings: (() -> Void)?
    let onLogout: (() -> Void)?
    let production: Bool
    let kind: CloudLibraryKind
    init(files: CloudFileStore, kind: CloudLibraryKind = .presentations, api: any CloudLibraryAPI = MockCloudAPI(), production: Bool = false, onSettings: (() -> Void)? = nil, onLogout: (() -> Void)? = nil) {
        self.kind = kind
        self.api = api
        self.production = production; self.onSettings = onSettings; self.onLogout = onLogout
        _store = StateObject(wrappedValue: CloudLibraryStore(api: api, files: files))
    }
    private var savedDiagrams: [CloudDiagram] {
        var seen = Set<String>()
        return store.saved.filter { $0.file.format != .svg }.map(\.diagram).filter { seen.insert("\($0.id)-\($0.version)").inserted }
    }
    private var diagrams: [CloudDiagram] {
        (showHidden ? store.hiddenDiagrams : store.items + savedDiagrams.filter { saved in !store.items.contains { $0.id == saved.id && $0.version == saved.version } }).filter {
            (showHidden || !store.isHidden($0)) && kind.contains($0) && !$0.formats.allSatisfy { $0 == .svg } && matchesSearch($0)
        }
    }
    private var visibleCollections: [CloudCollection] {
        guard kind == .illustrations, !showHidden else { return [] }
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
        await store.refresh(query: production ? query.trimmingCharacters(in: .whitespacesAndNewlines) : "", scope: production ? apiScope : "all", more: more) }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if showSearch { searchControls }
                ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if showHidden {
                        Text("このiPhoneで非表示にした資料です。表示に戻せます。").font(.caption).foregroundStyle(.secondary)
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 20)], spacing: 20) {
                        ForEach(visibleCollections) { collection in
                            Button { openCollection(collection) } label: {
                                if let first = store.members(of: collection).first {
                                    CloudCover(diagram: first, store: store, offline: isSavedOnly(first),
                                               titleOverride: collection.title,
                                               captionOverride: "\(store.members(of: collection).count)件のまとめ",
                                               savedOverride: store.members(of: collection).allSatisfy { member in store.saved.contains { $0.diagram.id == member.id && $0.diagram.version == member.version } })
                                }
                            }.buttonStyle(.plain).disabled(opening || store.busy)
                            .accessibilityLabel("\(collection.title)のまとめを読む")
                            .contextMenu {
                                Button("まとめを編集", systemImage: "pencil") { collectionDraft = collection }
                                Button("まとめを解除", systemImage: "rectangle.stack.badge.minus", role: .destructive) { Task { _ = await store.removeCollection(collection.id) } }
                            }
                            .overlay(alignment: .topTrailing) {
                                Menu {
                                    Button("まとめを編集", systemImage: "pencil") { collectionDraft = collection }
                                    Button("まとめを解除", systemImage: "rectangle.stack.badge.minus", role: .destructive) { Task { _ = await store.removeCollection(collection.id) } }
                                } label: { Image(systemName: "ellipsis.circle.fill").font(.title2).padding(8).background(.regularMaterial, in: Circle()) }.padding(8)
                            }
                        }
                        ForEach(looseDiagrams, id: \.selfKey) { diagram in
                            Button { if !showHidden { open(diagram) } } label: {
                                CloudCover(diagram: diagram, store: store, offline: isSavedOnly(diagram), showHidden: showHidden)
                            }
                            .buttonStyle(.plain).disabled(opening || store.busy)
                            .accessibilityLabel(showHidden ? diagram.title : "\(diagram.title)を読む")
                            .contextMenu {
                                if !showHidden || !store.hiddenDiagrams.isEmpty {
                                    if showHidden {
                                        Button("表示に戻す", systemImage: "arrow.uturn.backward") { Task { _ = await store.setHidden(diagram, hidden: false) } }
                                    } else {
                                        Button("非表示にする", systemImage: "eye.slash", role: .destructive) { hideCandidate = diagram }
                                    }
                                }
                            }
                            .overlay(alignment: .topTrailing) {
                                if !showHidden || !store.hiddenDiagrams.isEmpty {
                                    Menu {
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
                    }
                    if looseDiagrams.isEmpty && visibleCollections.isEmpty && !store.busy {
                        ContentUnavailableView(showHidden ? "非表示の資料はありません" : "資料が見つかりません",
                                               systemImage: showHidden ? "eye.slash" : "magnifyingglass",
                                               description: Text(showHidden ? "資料カードのメニューから非表示にできます。" : query.isEmpty ? "下に引いて一覧を更新してください。保存した資料は通信なしでも表示されます。" : "検索語や検索対象を変えてみてください。"))
                    }
                    if !showHidden && store.nextCursor != nil {
                        Button("さらに表示") { Task { await refresh(more: true) } }
                    }
                }.padding()
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
                    Button(showHidden ? "資料一覧に戻る" : "非表示の資料", systemImage: showHidden ? "doc.richtext" : "eye.slash") { showHidden.toggle() }
                    if kind == .illustrations && !showHidden {
                        Button("図解をまとめる", systemImage: "rectangle.stack.badge.plus") { collectionDraft = CloudCollection(id: UUID(), title: "", members: []) }
                    }
                    Button("登録資料の容量", systemImage: "externaldrive") { showCapacity = true }
                    if let onSettings { Button("接続設定", systemImage: "gear") { onSettings() } }
                    if let onLogout { Button("ログアウト", systemImage: "rectangle.portrait.and.arrow.right") { onLogout() } }
                    Button("一覧を更新", systemImage: "arrow.clockwise") { Task { await refresh() } }
                    Button("一時キャッシュを削除", systemImage: "trash") { Task { await store.clearCache() } }
                } label: { Label("その他", systemImage: "ellipsis") }.disabled(opening || store.busy)
                }
            }
            .overlay { if opening { ProgressView("資料を開いています").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16)) } }
            .refreshable { await store.reloadSaved(); await refresh() }
            .task { await store.reloadSaved() }
            .task(id: searchRequest) {
                if showHidden { await store.reloadSaved() }
                else {
                    do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
                    await refresh()
                }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await store.reloadSaved(); await refresh() } }
            }
        }
        .sheet(isPresented: $showCapacity) { CloudCapacityView(api: api, production: production) }
        .sheet(item: $collectionDraft) { draft in
            CloudCollectionEditor(collection: draft, choices: collectionChoices, store: store)
        }
        .fullScreenCover(item: $collectionReading) { CloudCollectionReader(reading: $0, store: store) }
        .fullScreenCover(item: $reading) { CloudReader(reading: $0, store: store) }
        .alert("このiPhoneで非表示にしますか？", isPresented: Binding(get: { hideCandidate != nil }, set: { if !$0 { hideCandidate = nil } })) {
            Button("キャンセル", role: .cancel) { hideCandidate = nil }
            Button("非表示にする", role: .destructive) {
                if let diagram = hideCandidate { Task { _ = await store.setHidden(diagram, hidden: true) } }
                hideCandidate = nil
            }
        } message: { Text("「\(hideCandidate?.title ?? "")」をこのiPhoneの一覧から隠します。「非表示の資料」から戻せます。クラウドの資料と保存したファイルは残ります。") }
        .alert("操作を完了できません", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
            Button("OK") { store.errorMessage = nil }
        } message: { Text(store.errorMessage ?? "") }
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
        let tagMatches = diagram.tags.contains { $0.localizedCaseInsensitiveContains(term) }
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
    private func open(_ diagram: CloudDiagram) {
        guard !opening else { return }
        opening = true
        let offline = isSavedOnly(diagram)
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
    var showHidden = false
    var titleOverride: String? = nil
    var captionOverride: String? = nil
    var savedOverride: Bool? = nil
    @State private var image: UIImage?
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack {
                Color(uiColor: .secondarySystemBackground)
                if let image { Image(uiImage: image).resizable().scaledToFit() }
                else { Image(systemName: "doc.richtext").font(.largeTitle).foregroundStyle(.secondary) }
            }.aspectRatio(16/9, contentMode: .fit).clipShape(RoundedRectangle(cornerRadius: 12))
            Text((titleOverride ?? diagram.title).replacingOccurrences(of: "（モック）", with: "")).font(.headline).foregroundStyle(.primary).lineLimit(2)
            HStack {
                Text(captionOverride ?? "\(diagram.pageCount)ページ").foregroundStyle(.secondary)
                Spacer()
                if savedOverride ?? store.saved.contains(where: { $0.diagram.id == diagram.id && $0.diagram.version == diagram.version }) {
                    Image(systemName: "bookmark.fill").foregroundStyle(.secondary).accessibilityLabel("保存済み")
                }
            }.font(.caption)
        }
        .padding(12).background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
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
    init(reading: CloudReading, store: CloudLibraryStore) {
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

@MainActor
private struct CloudCapacityView: View {
    let api: any CloudLibraryAPI
    let production: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var capacity: CloudCapacity?
    @State private var loading = false
    @State private var errorMessage: String?
    @State private var refreshID = 0
    var body: some View {
        NavigationStack {
            Form {
                Section(production ? "クラウドの登録資料" : "サンプルの登録資料") {
                    if let capacity {
                        LabeledContent("登録資料", value: "\(capacity.documentCount)件")
                        LabeledContent("合計容量", value: ByteCountFormatter.string(fromByteCount: capacity.sizeBytes, countStyle: .decimal))
                        LabeledContent("最終更新") {
                            Text(capacity.updatedAt, format: .dateTime.year().month().day().hour().minute())
                        }
                    } else if !loading && errorMessage == nil { Text("未取得").foregroundStyle(.secondary) }
                    if loading { ProgressView("容量を集計しています…") }
                    if let errorMessage { Text(errorMessage).foregroundStyle(.secondary) }
                    Button("更新") { refreshID += 1 }.disabled(loading)
                }
                Section {
                    Text("ライブラリ全体の最新版のPDF・PPTX・全ページPNG・SVGを合計します。旧版と管理ファイルは含みません。")
                    Text("iPhoneへの保存状況や検索条件に関係なく集計します。S3全体の使用容量とは異なります。")
                    if !production { Text("サンプル資料の集計です。S3の登録資料容量ではありません。") }
                }
            }
            .navigationTitle("登録資料の容量")
            .toolbar { Button("閉じる") { dismiss() } }
            .task(id: refreshID) {
                loading = true; errorMessage = nil
                defer { loading = false }
                do {
                    let result = try await api.capacity()
                    try Task.checkCancellation()
                    capacity = result
                } catch {
                    if !Task.isCancelled {
                        errorMessage = capacity == nil
                            ? "容量を取得できませんでした。接続を確認して更新してください。"
                            : "更新できませんでした。前回取得した容量を表示しています。"
                    }
                }
            }
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

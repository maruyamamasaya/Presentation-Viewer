import SwiftUI
import QuickLook

@MainActor
struct DocumentViewer: View {
    let document: OpenedDocument
    @StateObject private var pdfSession: PDFReadingSession
    @ObservedObject private var external = ExternalDisplayCoordinator.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var toolbarVisible = true
    @State private var thumbnailPreference: Bool?
    @State private var imagePresenting = false

    init(document: OpenedDocument) {
        self.document = document
        _pdfSession = StateObject(wrappedValue: PDFReadingSession(url: document.format == .pdf ? document.url : nil))
    }

    private var isImage: Bool { [.png, .jpg, .jpeg].contains(document.format) }
    private var canPresent: Bool { isImage || (document.format == .pdf && pdfSession.pageCount > 0) }
    private var presenting: Bool { pdfSession.isPresenting || imagePresenting }
    private var thumbnailsVisible: Bool { thumbnailPreference ?? (horizontalSizeClass == .regular) }

    var body: some View {
        NavigationStack {
            Group {
                switch document.format {
                case .pptx:
                    if QLPreviewController.canPreview(document.url as NSURL) {
                        QuickLookView(url: document.url)
                    } else {
                        ViewerErrorView(message: "このPPTXはQuick Lookで表示できません。PDFに書き出してお試しください。")
                    }
                case .pdf:
                    PDFDocumentView(session: pdfSession, thumbnailsVisible: thumbnailsVisible)
                case .svg: SVGDocumentView(url: document.url)
                case .png, .jpg, .jpeg:
                    ImageDocumentView(url: document.url, presenting: imagePresenting, onTap: toggleControls)
                }
            }
            .background(presenting ? Color.black : Color(uiColor: .systemBackground))
            .navigationTitle(document.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("閉じる") { dismiss() }.keyboardShortcut(.cancelAction)
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if document.format == .pdf, pdfSession.pageCount > 0 {
                        Button {
                            thumbnailPreference = !thumbnailsVisible
                        } label: {
                            Label(thumbnailsVisible ? "ページ一覧を隠す" : "ページ一覧を表示", systemImage: "square.grid.2x2")
                        }
                    }
                    Menu {
                        Button("プレゼンを開始（PDF・画像）", systemImage: "play.rectangle") { beginPresentation() }
                            .disabled(!canPresent)
                        if document.format == .pdf {
                            Label(external.connected ? "外部画面に接続済み" : "外部画面未接続", systemImage: "display")
                        }
                    } label: { Label("プレゼン", systemImage: "play.rectangle") }
                    if isImage {
                        Button(action: toggleControls) {
                            Label("ツールバーを隠す", systemImage: "arrow.up.left.and.arrow.down.right")
                        }
                        .keyboardShortcut("t", modifiers: .command)
                    }
                }
            }
            .toolbar(toolbarVisible && !presenting ? .visible : .hidden, for: .navigationBar)
            .overlay(alignment: .topLeading) {
                if presenting {
                    // Remains reachable with touch, pointer, VoiceOver and Escape.
                    Button("プレゼンを終了", systemImage: "xmark") { endPresentation() }
                        .keyboardShortcut(.cancelAction)
                        .buttonStyle(.bordered).controlSize(.large)
                        .foregroundStyle(.white).tint(.white)
                        .padding(8).background(.black.opacity(0.65), in: Capsule()).padding(8)
                } else if !toolbarVisible {
                    HStack {
                        Button("閉じる") { dismiss() }.keyboardShortcut(.cancelAction)
                        Button(action: toggleControls) {
                            Label("ツールバーを表示", systemImage: "arrow.down.right.and.arrow.up.left").labelStyle(.iconOnly)
                        }
                        .keyboardShortcut("t", modifiers: .command)
                    }
                    .buttonStyle(.bordered).controlSize(.large)
                    .padding(8).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)).padding(8)
                }
            }
            .overlay(alignment: .bottom) {
                if document.format == .pdf, presenting {
                    HStack(spacing: 24) {
                        Button { pdfSession.movePage(-1) } label: { Label("前のページ", systemImage: "chevron.left") }
                            .keyboardShortcut(.leftArrow, modifiers: [])
                            .disabled(pdfSession.pageIndex == 0)
                        Text("\(pdfSession.pageIndex + 1) / \(pdfSession.pageCount)")
                            .monospacedDigit().accessibilityLabel("\(pdfSession.pageCount)ページ中\(pdfSession.pageIndex + 1)ページ")
                        Button { pdfSession.movePage(1) } label: { Label("次のページ", systemImage: "chevron.right") }
                            .keyboardShortcut(.rightArrow, modifiers: [])
                            .disabled(pdfSession.pageIndex + 1 >= pdfSession.pageCount)
                    }
                    .labelStyle(.iconOnly).buttonStyle(.bordered).controlSize(.large)
                    .foregroundStyle(.white).tint(.white)
                    .padding(8).background(.black.opacity(0.65), in: Capsule()).padding(8)
                }
            }
        }
        .statusBarHidden(presenting)
        .onDisappear { external.end(pdfSession) }
    }

    private func toggleControls() {
        withAnimation(.easeInOut(duration: 0.2)) {
            if !presenting { toolbarVisible.toggle() }
        }
    }

    private func beginPresentation() {
        guard canPresent else { return }
        if document.format == .pdf {
            pdfSession.isPresenting = true
            external.begin(pdfSession)
        } else { imagePresenting = true }
    }

    private func endPresentation() {
        external.end(pdfSession)
        pdfSession.isPresenting = false
        imagePresenting = false
        toolbarVisible = true
    }
}

struct ViewerErrorView: View {
    let message: String
    var body: some View {
        ContentUnavailableView("表示できません", systemImage: "doc.badge.exclamationmark", description: Text(message))
    }
}

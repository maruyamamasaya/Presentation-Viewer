import SwiftUI
import WebKit

struct SVGDocumentView: View {
    let url: URL
    @State private var failed = false

    var body: some View {
        if failed {
            ViewerErrorView(message: "SVGを表示できません。単体で表示できるSVGファイルを選択してください。")
        } else {
            SVGCanvas(url: url, failed: $failed)
        }
    }
}

private struct SVGCanvas: UIViewRepresentable {
    let url: URL
    @Binding var failed: Bool

    func makeCoordinator() -> Coordinator { Coordinator(url: url, failed: $failed) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        // Block remote requests, including SVG subresources, before loading anything.
        let rules = """
        [{"trigger":{"url-filter":"^https?://"},"action":{"type":"block"}},
         {"trigger":{"url-filter":".*","resource-type":["image","style-sheet","script","font","media","raw"]},"action":{"type":"block"}}]
        """
        WKContentRuleListStore.default().compileContentRuleList(
            forIdentifier: "OfflineSVG", encodedContentRuleList: rules
        ) { [weak view, coordinator = context.coordinator] list, error in
            guard let view else { return }
            guard let list, error == nil else { coordinator.failed.wrappedValue = true; return }
            view.configuration.userContentController.add(list)
            guard let parser = XMLParser(contentsOf: self.url) else {
                coordinator.failed.wrappedValue = true
                return
            }
            let validator = SVGValidator()
            parser.delegate = validator
            parser.shouldProcessNamespaces = true
            parser.shouldResolveExternalEntities = false
            guard parser.parse(), validator.isSVG else { coordinator.failed.wrappedValue = true; return }
            view.loadFileURL(self.url, allowingReadAccessTo: self.url)
        }
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {}
    static func dismantleUIView(_ view: WKWebView, coordinator: Coordinator) {
        view.stopLoading()
        view.navigationDelegate = nil
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        let url: URL
        var failed: Binding<Bool>
        init(url: URL, failed: Binding<Bool>) { self.url = url; self.failed = failed }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(navigationAction.request.url == url ? .allow : .cancel)
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            failed.wrappedValue = true
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            failed.wrappedValue = true
        }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { failed.wrappedValue = true }
    }
}

private final class SVGValidator: NSObject, XMLParserDelegate {
    private var sawRoot = false
    var isSVG = false
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        if !sawRoot {
            sawRoot = true
            isSVG = elementName == "svg"
        }
    }
}

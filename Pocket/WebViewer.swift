import SwiftUI
import WebKit

@MainActor final class WebSession: NSObject, ObservableObject, WKNavigationDelegate, WKUIDelegate {
    let webView: WKWebView
    let app: MiniApp
    @Published var loading = true
    @Published var error: String?
    @Published var canGoBack = false
    @Published var currentURL: URL?
    @Published var externalURL: URL?
    var onVisit: ((URL) -> Void)?
    private var observation: NSKeyValueObservation?
    init(app: MiniApp, url: URL) {
        self.app = app
        let configuration = WKWebViewConfiguration()
        // Each app gets a separate ephemeral cookie/storage jar. Never use .default().
        configuration.websiteDataStore = .nonPersistent()
        configuration.allowsInlineMediaPlayback = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self; webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.isOpaque = false; webView.backgroundColor = .black
        observation = webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] view, _ in
            Task { @MainActor in self?.canGoBack = view.canGoBack }
        }
        load(url)
    }
    func load(_ url: URL) {
        guard WebPolicy.safe(url, for: app.url) else { error = "This link is outside the app's website."; return }
        currentURL = url; webView.load(URLRequest(url: url))
    }
    func discard() { webView.stopLoading(); webView.navigationDelegate = nil; webView.uiDelegate = nil; webView.loadHTMLString("", baseURL: nil); onVisit = nil; observation = nil }
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { loading = true; error = nil }
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loading = false; canGoBack = webView.canGoBack
        if let url = webView.url, WebPolicy.safe(url, for: app.url) { currentURL = url; onVisit?(url) }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { failed(error) }
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) { failed(error) }
    private func failed(_ error: Error) {
        guard (error as NSError).code != NSURLErrorCancelled else { return }
        loading = false; self.error = error.localizedDescription
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { loading = false; error = "This page stopped responding. Reload to continue." }
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { decisionHandler(.cancel); return }
        if url.scheme?.lowercased() == "solana" {
            decisionHandler(.cancel); loading = false
            if action.navigationType == .linkActivated,
               action.sourceFrame.isMainFrame, WebPolicy.solanaPayment(url) { externalURL = url }
            else { error = "Use a valid payment link to open your wallet." }
            return
        }
        // Subresources stay under normal WebKit security. Only top-level navigation changes app identity.
        if action.targetFrame?.isMainFrame == false { decisionHandler(.allow); return }
        guard WebPolicy.safe(url, for: app.url) else {
            decisionHandler(.cancel); loading = false
            if ["https", "http", "mailto", "tel"].contains(url.scheme?.lowercased() ?? "") { externalURL = url }
            else { error = "This app requested an unsupported link." }
            return
        }
        if action.targetFrame == nil { decisionHandler(.cancel); load(url); return }
        decisionHandler(.allow)
    }
    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if response.isForMainFrame, let url = response.response.url, !WebPolicy.safe(url, for: app.url) {
            externalURL = url; loading = false; decisionHandler(.cancel)
        } else if response.canShowMIMEType { decisionHandler(.allow) }
        else { error = "Open this download in your browser."; loading = false; decisionHandler(.cancel) }
    }
    func reload() { error = nil; if webView.url != nil { webView.reload() } else { load(currentURL ?? app.url) } }
}

/// At most three live pages. Account/server changes discard every cookie jar and page.
@MainActor final class WebSessionPool {
    static let shared = WebSessionPool()
    private var identity: String?
    private var sessions: [String: WebSession] = [:]
    private var order: [String] = []
    func use(identity: String) { if self.identity != identity { clear(); self.identity = identity } }
    func session(app: MiniApp, initial: URL, exactTarget: URL? = nil) -> WebSession {
        if let existing = sessions[app.id], existing.app.url != app.url { remove(app.id) }
        let session = sessions[app.id] ?? WebSession(app: app, url: initial)
        sessions[app.id] = session; order.removeAll { $0 == app.id }; order.append(app.id)
        while order.count > 3 { remove(order[0]) }
        if let exactTarget { session.load(exactTarget) }
        return session
    }
    func remove(_ id: String) { sessions.removeValue(forKey: id)?.discard(); order.removeAll { $0 == id } }
    func retain(_ ids: Set<String>) { for id in Array(sessions.keys) where !ids.contains(id) { remove(id) } }
    func clear() { for session in sessions.values { session.discard() }; sessions = [:]; order = []; identity = nil }
}

struct WebSurface: UIViewRepresentable {
    let session: WebSession
    func makeUIView(context: Context) -> WKWebView { session.webView }
    func updateUIView(_ view: WKWebView, context: Context) {}
}

struct WebViewer: View {
    @ObservedObject var session: WebSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    var body: some View {
        ZStack {
            WebSurface(session: session)
                .ignoresSafeArea(.container, edges: .all)
            if let error = session.error {
                ContentUnavailableView {
                    Label("Couldn’t open this page", systemImage: "wifi.exclamationmark")
                } description: { Text(error) } actions: {
                    Button("Try again") { session.reload() }.buttonStyle(.borderedProminent)
                    Button("Open app home") { session.load(session.app.url) }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(PocketStyle.canvas)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button { PocketHaptics.tap(); dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.72), in: Circle())
            }
            .buttonStyle(PocketPressStyle())
            .accessibilityLabel("Return to Pocket")
            .padding(.trailing, 16).padding(.top, 8)
        }
        .confirmationDialog("Open outside Pocket?", isPresented: Binding(get: { session.externalURL != nil }, set: { if !$0 { session.externalURL = nil } }), titleVisibility: .visible) {
            if let url = session.externalURL { Button(WebPolicy.solanaPayment(url) ? "Open wallet" : "Open \(url.host ?? url.scheme ?? "link")") {
                openURL(url) { accepted in if !accepted { session.error = "No app could open this link. Install a compatible wallet for Solana payments." } }
                session.externalURL = nil
            } }
            Button("Stay in Pocket", role: .cancel) { session.externalURL = nil }
        } message: { Text("This link opens another app. Your Pocket session and credentials are not shared.") }
    }
}

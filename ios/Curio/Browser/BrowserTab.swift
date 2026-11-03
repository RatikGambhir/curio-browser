import UIKit
import WebKit

/// A tab's live page: the web view (created on first view and released when
/// the tab sleeps), its state, and page commands.
final class BrowserTab: NSObject {
    /// A load that has not finished after this long is reported as stalled.
    private static let stalledLoad: Duration = .seconds(30)
    private static let webSchemes: Set<String> = ["http", "https", "about", "data", "blob", "file"]

    let id: UUID
    weak var delegate: BrowserTabDelegate?
    private let engine: WebEngine
    private(set) var state: PageState
    private(set) var webView: CurioWebView?
    private(set) var isActive = false
    private(set) var lastActive = Date.now
    private var restoreScroll: Double?
    private var observations: [NSKeyValueObservation] = []
    private var stallTask: Task<Void, Never>?
    private var downloads: [ObjectIdentifier: UUID] = [:]
    private var appearance: UIUserInterfaceStyle = .unspecified

    init(id: UUID, url: String, title: String, favicon: String?, scrollY: Double, engine: WebEngine) {
        self.id = id
        self.engine = engine
        state = PageState(url: url, title: title, favicon: favicon)
        restoreScroll = scrollY > 0 ? scrollY : nil
        super.init()
    }

    deinit {
        stallTask?.cancel()
    }

    /// Whether the page is loaded (not asleep).
    var isAwake: Bool { webView != nil }
    var isInternal: Bool { Curio.isInternalURL(state.url) }

    // MARK: - Lifecycle

    /// Shows or hides the tab. Showing a sleeping tab wakes it.
    func setActive(_ active: Bool) {
        isActive = active
        lastActive = .now
        if active && webView == nil && !isInternal { load(state.url) }
    }

    /// Puts the tab to sleep, releasing its web view and engine memory.
    func sleep() {
        guard let webView else { return }
        stallTask?.cancel()
        observations.removeAll()
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.removeFromSuperview()
        self.webView = nil
        state.loading = false
        state.stalled = false
        state.selection = nil
        delegate?.tabStateDidChange(self)
    }

    func setAppearance(_ style: UIUserInterfaceStyle) {
        appearance = style
        webView?.overrideUserInterfaceStyle = style
    }

    func setRestoreScroll(_ y: Double) {
        restoreScroll = y > 0 ? y : nil
    }

    private func makeWebView() -> CurioWebView {
        let webView = CurioWebView(frame: .zero, configuration: engine.configuration(handler: self))
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsLinkPreview = true
        webView.isInspectable = true
        webView.overrideUserInterfaceStyle = appearance
        webView.scrollView.contentInsetAdjustmentBehavior = .automatic
        webView.onAskAboutSelection = { [weak self] action in
            guard let self else { return }
            delegate?.tab(self, askAboutSelection: action)
        }
        if state.zoom != 1 { webView.pageZoom = state.zoom }
        // WebKit reports these changes on the main thread.
        observations = [
            webView.observe(\.title) { [weak self] _, _ in MainActor.assumeIsolated { self?.titleChanged(self?.webView?.title) } },
            webView.observe(\.url) { [weak self] _, _ in MainActor.assumeIsolated { self?.urlChanged(self?.webView?.url) } },
            webView.observe(\.canGoBack) { [weak self] _, _ in MainActor.assumeIsolated { self?.refreshHistory() } },
            webView.observe(\.canGoForward) { [weak self] _, _ in MainActor.assumeIsolated { self?.refreshHistory() } },
            webView.observe(\.hasOnlySecureContent) { [weak self] _, _ in MainActor.assumeIsolated { self?.refreshHistory() } },
        ]
        return webView
    }

    private func load(_ url: String) {
        guard let target = URL(string: url) else { return }
        let webView = webView ?? makeWebView()
        self.webView = webView
        state.loading = true
        state.stalled = false
        webView.load(URLRequest(url: target))
        watchForStall()
        delegate?.tabStateDidChange(self)
    }

    // MARK: - Commands

    /// Navigates to `url`. Curio's own pages release the web view.
    func navigate(to url: String) {
        state.url = url
        state.title = ""
        state.favicon = nil
        restoreScroll = nil
        if Curio.isInternalURL(url) {
            sleep()
            delegate?.tabStateDidChange(self)
        } else {
            load(url)
        }
    }

    func goBack() { webView?.goBack() }
    func goForward() { webView?.goForward() }

    func reload() {
        if let webView {
            state.stalled = false
            webView.reload()
            watchForStall()
        } else if !isInternal {
            load(state.url)
        }
    }

    func stop() {
        webView?.stopLoading()
        state.loading = false
        delegate?.tabStateDidChange(self)
    }

    func setZoom(_ zoom: Double) {
        state.zoom = min(max(zoom, 0.3), 3)
        webView?.pageZoom = state.zoom
        delegate?.tabStateDidChange(self)
    }

    /// Readable page content as `PageContext` JSON.
    func extractContent() async -> String? {
        guard let webView else { return nil }
        let result = try? await webView.evaluateJavaScript(PageScripts.extractContent, contentWorld: engine.world)
        return result as? String
    }

    func find(_ query: String, forward: Bool) async -> FindResult {
        guard let webView,
              let json = try? await webView.evaluateJavaScript(PageScripts.find(query, forward: forward), contentWorld: engine.world) as? String,
              let data = json.data(using: .utf8),
              let result = try? JSONDecoder().decode(FindResult.self, from: data) else {
            return FindResult()
        }
        return result
    }

    func clearFind() {
        webView?.evaluateJavaScript(PageScripts.clearFind, in: nil, in: engine.world)
    }

    var printFormatter: UIPrintFormatter? { webView?.viewPrintFormatter() }

    // MARK: - State

    private func titleChanged(_ title: String?) {
        let title = (title ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard title != state.title, !title.isEmpty || webView?.url != nil else { return }
        state.title = title
        delegate?.tabStateDidChange(self)
    }

    /// Fires for regular navigations and single-page-app URL changes.
    private func urlChanged(_ url: URL?) {
        guard let url = url?.absoluteString, !url.isEmpty, url != state.url else { return }
        let hostChanged = Curio.displayHost(url) != Curio.displayHost(state.url)
        state.url = url
        if hostChanged {
            state.favicon = nil
            state.themeColor = nil
        }
        refreshHistory()
        delegate?.tab(self, didNavigateTo: url)
        delegate?.tabStateDidChange(self)
    }

    private func refreshHistory() {
        guard let webView else { return }
        state.canGoBack = webView.canGoBack
        state.canGoForward = webView.canGoForward
        state.secure = webView.hasOnlySecureContent
        delegate?.tabStateDidChange(self)
    }

    private func watchForStall() {
        stallTask?.cancel()
        stallTask = Task { [weak self] in
            try? await Task.sleep(for: Self.stalledLoad)
            guard !Task.isCancelled, let self, state.loading else { return }
            state.loading = false
            state.stalled = true
            delegate?.tabStateDidChange(self)
        }
    }

    /// Falls back to the site's `/favicon.ico` when the page declares none.
    private func defaultFavicon() -> String? {
        guard let components = URLComponents(string: state.url), let scheme = components.scheme,
              scheme.hasPrefix("http"), let host = components.host else { return nil }
        let port = components.port.map { ":\($0)" } ?? ""
        return "\(scheme)://\(host)\(port)/favicon.ico"
    }
}

// MARK: - Page bridge

extension BrowserTab: WKScriptMessageHandler {
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame,
              let body = message.body as? [String: Any],
              body["token"] as? String == engine.token,
              let type = body["type"] as? String else { return }
        switch type {
        case "selection":
            let text = String((body["text"] as? String ?? "").prefix(20_000))
            state.selection = text.isEmpty ? nil : text
            delegate?.tabSelectionDidChange(self)
        case "meta":
            if let favicon = body["favicon"] as? String, favicon.hasPrefix("http"), favicon.count < 2048 {
                state.favicon = favicon
            } else if state.favicon == nil {
                state.favicon = defaultFavicon()
            }
            state.themeColor = (body["themeColor"] as? String).map { String($0.prefix(64)) }
            delegate?.tabStateDidChange(self)
        case "scroll":
            if let y = body["y"] as? Double, y.isFinite { delegate?.tab(self, didScrollTo: y) }
        default:
            break
        }
    }
}

// MARK: - Navigation

extension BrowserTab: WKNavigationDelegate {
    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                 decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
        guard let url = action.request.url else { return decisionHandler(.cancel) }
        if action.shouldPerformDownload { return decisionHandler(.download) }
        let scheme = url.scheme?.lowercased() ?? ""
        if !Self.webSchemes.contains(scheme) {
            // Links to other apps (mailto:, zoommtg:, ...) ask first.
            decisionHandler(.cancel)
            if action.navigationType == .linkActivated || action.targetFrame?.isMainFrame != false {
                delegate?.tab(self, wantsToOpenExternally: url)
            }
            return
        }
        // ⌘-click opens links in a background tab (⇧ brings it forward).
        if #available(iOS 18.4, *), action.navigationType == .linkActivated,
           action.modifierFlags.contains(.command), scheme.hasPrefix("http") {
            decisionHandler(.cancel)
            delegate?.tab(self, openInNewTab: url.absoluteString, background: !action.modifierFlags.contains(.shift))
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse,
                 decisionHandler: @escaping @MainActor (WKNavigationResponsePolicy) -> Void) {
        let disposition = (response.response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Disposition") ?? ""
        if response.isForMainFrame && (!response.canShowMIMEType || disposition.lowercased().hasPrefix("attachment")) {
            decisionHandler(.download)
        } else {
            decisionHandler(.allow)
        }
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        state.loading = true
        state.stalled = false
        state.selection = nil
        refreshHistory()
        watchForStall()
        delegate?.tabStateDidChange(self)
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        urlChanged(webView.url)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        stallTask?.cancel()
        state.loading = false
        state.stalled = false
        if let url = webView.url?.absoluteString { state.url = url }
        refreshHistory()
        if let y = restoreScroll {
            restoreScroll = nil
            webView.evaluateJavaScript(PageScripts.restoreScroll(y), in: nil, in: engine.world)
        }
        if state.favicon == nil { state.favicon = defaultFavicon() }
        delegate?.tab(self, didNavigateTo: state.url)
        delegate?.tab(self, didFinishLoading: state.url, title: state.title)
        delegate?.tabStateDidChange(self)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loadFailed(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        loadFailed(error)
    }

    private func loadFailed(_ error: Error) {
        stallTask?.cancel()
        state.loading = false
        let nsError = error as NSError
        // Cancelled loads and loads that turned into downloads aren't failures.
        let ignored = (nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled)
            || (nsError.domain == "WebKitErrorDomain" && nsError.code == 102)
        if !ignored { state.stalled = true }
        delegate?.tabStateDidChange(self)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        webView.reload()
    }
}

// MARK: - UI

extension BrowserTab: WKUIDelegate {
    /// Pop-ups and `target=_blank` links open as Curio tabs.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                 for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = action.request.url?.absoluteString, url.hasPrefix("http") {
            delegate?.tab(self, openInNewTab: url, background: false)
        }
        return nil
    }

    func webView(_ webView: WKWebView, contextMenuConfigurationFor element: WKContextMenuElementInfo) async -> UIContextMenuConfiguration? {
        guard let url = element.linkURL, url.scheme?.hasPrefix("http") == true else { return nil }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { [weak self] suggested in
            guard let self else { return UIMenu(children: suggested) }
            let open = UIAction(title: "Open in New Tab", image: UIImage(systemName: "plus.square.on.square")) { [weak self] _ in
                guard let self else { return }
                delegate?.tab(self, openInNewTab: url.absoluteString, background: false)
            }
            let background = UIAction(title: "Open in Background Tab", image: UIImage(systemName: "square.on.square")) { [weak self] _ in
                guard let self else { return }
                delegate?.tab(self, openInNewTab: url.absoluteString, background: true)
            }
            let copy = UIAction(title: "Copy Link", image: UIImage(systemName: "link")) { _ in
                UIPasteboard.general.url = url
            }
            return UIMenu(children: [UIMenu(options: .displayInline, children: [open, background, copy])] + suggested)
        }
    }

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async {
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            let alert = makeAlert(message, frame: frame)
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in done.resume() })
            presentOrDefault(alert) { done.resume() }
        }
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async -> Bool {
        await withCheckedContinuation { (done: CheckedContinuation<Bool, Never>) in
            let alert = makeAlert(message, frame: frame)
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in done.resume(returning: false) })
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in done.resume(returning: true) })
            presentOrDefault(alert) { done.resume(returning: false) }
        }
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?,
                 initiatedByFrame frame: WKFrameInfo) async -> String? {
        await withCheckedContinuation { (done: CheckedContinuation<String?, Never>) in
            let alert = makeAlert(prompt, frame: frame)
            alert.addTextField { $0.text = defaultText }
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in done.resume(returning: nil) })
            alert.addAction(UIAlertAction(title: "OK", style: .default) { [weak alert] _ in
                done.resume(returning: alert?.textFields?.first?.text)
            })
            presentOrDefault(alert) { done.resume(returning: nil) }
        }
    }

    private func makeAlert(_ message: String, frame: WKFrameInfo) -> UIAlertController {
        let host = Curio.displayHost(frame.request.url?.absoluteString ?? state.url)
        return UIAlertController(title: host, message: message, preferredStyle: .alert)
    }

    /// Background tabs can't show dialogs; their requests are declined.
    private func presentOrDefault(_ alert: UIAlertController, otherwise fallback: () -> Void) {
        if isActive, let delegate {
            delegate.tab(self, present: alert)
        } else {
            fallback()
        }
    }
}

// MARK: - Downloads

extension BrowserTab: WKDownloadDelegate {
    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String) async -> URL? {
        let directory = StoragePaths.downloadsDirectory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let name = Self.uniqueFileName(suggestedFilename.isEmpty ? "download" : suggestedFilename, in: directory)
        let source = download.originalRequest?.url?.absoluteString ?? state.url
        if let id = delegate?.tab(self, didStartDownload: source, fileName: name) {
            downloads[ObjectIdentifier(download)] = id
        }
        return directory.appending(path: name)
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let id = downloads.removeValue(forKey: ObjectIdentifier(download)) else { return }
        delegate?.tab(self, didFinishDownload: id, fileName: nil, success: true)
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        guard let id = downloads.removeValue(forKey: ObjectIdentifier(download)) else { return }
        delegate?.tab(self, didFinishDownload: id, fileName: nil, success: false)
    }

    /// "file.pdf", then "file 2.pdf", "file 3.pdf", …
    private static func uniqueFileName(_ name: String, in directory: URL) -> String {
        let safe = name.replacingOccurrences(of: "/", with: "-")
        let base = (safe as NSString).deletingPathExtension
        let ext = (safe as NSString).pathExtension
        var candidate = safe
        var counter = 2
        while FileManager.default.fileExists(atPath: directory.appending(path: candidate).path(percentEncoded: false)) {
            candidate = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
            counter += 1
        }
        return candidate
    }
}

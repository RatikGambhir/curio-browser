import WebKit

/// Downloads an icon using Curio's WebKit transport policy when URLSession rejects it.
final class WebFaviconDownload: NSObject, WKNavigationDelegate, WKDownloadDelegate {
    private let webView: WKWebView
    private let destination = URL.temporaryDirectory.appending(path: "favicon-\(UUID().uuidString)")
    private var result: CheckedContinuation<URL?, Never>?
    private var timeout: Task<Void, Never>?
    private var download: WKDownload?

    private override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
    }

    static func file(for url: URL) async -> URL? {
        let request = WebFaviconDownload()
        let file = await request.start(url)
        withExtendedLifetime(request) {}
        return file
    }

    private func start(_ url: URL) async -> URL? {
        await withCheckedContinuation { continuation in
            result = continuation
            timeout = Task { [weak self] in
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                self?.finish(success: false)
            }
            if webView.load(URLRequest(url: url)) == nil { finish(success: false) }
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let scheme = action.request.url?.scheme, scheme == "http" || scheme == "https" else { return .cancel }
        return .allow
    }

    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        guard result != nil, let response = response.response as? HTTPURLResponse,
              (200..<300).contains(response.statusCode) else {
            finish(success: false)
            return .cancel
        }
        return .download
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        guard result != nil else {
            download.cancel { _ in }
            return
        }
        self.download = download
        download.delegate = self
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(success: false)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(success: false)
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String) async -> URL? {
        result == nil ? nil : destination
    }

    func downloadDidFinish(_ download: WKDownload) {
        finish(success: true)
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        self.download = nil
        finish(success: false)
    }

    private func finish(success: Bool) {
        guard let continuation = result else { return }
        result = nil
        timeout?.cancel()
        timeout = nil
        webView.stopLoading()
        if !success {
            let destination = destination
            if let download {
                download.cancel { _ in try? FileManager.default.removeItem(at: destination) }
            } else {
                try? FileManager.default.removeItem(at: destination)
            }
        }
        download = nil
        continuation.resume(returning: success ? destination : nil)
    }
}

import WebKit

/// Downloads an icon using Curio's WebKit transport policy when URLSession rejects it.
final class WebFaviconDownload: NSObject, WKNavigationDelegate, WKDownloadDelegate {
    private let webView: WKWebView
    private let destination = URL.temporaryDirectory.appending(path: "favicon-\(UUID().uuidString)")
    private var result: CheckedContinuation<URL, any Error>?
    private var timeout: Task<Void, Never>?
    private var download: WKDownload?
    private var progressObservation: NSKeyValueObservation?

    private override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        webView.navigationDelegate = self
    }

    static func file(for url: URL) async throws -> URL {
        let request = WebFaviconDownload()
        defer { withExtendedLifetime(request) {} }
        return try await request.start(url)
    }

    private func start(_ url: URL) async throws -> URL {
        var request = URLRequest(url: url)
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        return try await withCheckedThrowingContinuation { continuation in
            result = continuation
            timeout = Task { [weak self] in
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled else { return }
                self?.finish(error: URLError(.timedOut))
            }
            if webView.load(request) == nil { finish(error: URLError(.cannotLoadFromNetwork)) }
        }
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        guard let scheme = action.request.url?.scheme, scheme == "http" || scheme == "https" else { return .cancel }
        return .allow
    }

    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        guard result != nil else { return .cancel }
        do {
            try Self.validate(response.response)
            return .download
        } catch {
            finish(error: error)
            return .cancel
        }
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        guard result != nil else {
            download.cancel { _ in }
            return
        }
        self.download = download
        download.delegate = self
        progressObservation = download.progress.observe(\.completedUnitCount, options: [.initial, .new]) { [weak self] progress, _ in
            if progress.completedUnitCount > FaviconLoader.maximumResponseBytes {
                Task { @MainActor in self?.finish(error: FaviconLoader.ResponseError.tooLarge) }
            }
        }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        finish(error: error)
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        finish(error: error)
    }

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String) async -> URL? {
        guard result != nil else { return nil }
        do {
            try Self.validate(response)
            return destination
        } catch {
            finish(error: error)
            return nil
        }
    }

    func downloadDidFinish(_ download: WKDownload) {
        self.download = nil
        let size = try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize
        guard let size else {
            finish(error: CocoaError(.fileReadUnknown))
            return
        }
        finish(error: size > FaviconLoader.maximumResponseBytes ? FaviconLoader.ResponseError.tooLarge : nil)
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        self.download = nil
        finish(error: error)
    }

    nonisolated static func validate(_ response: URLResponse) throws {
        try FaviconLoader.validate(response)
        // WebKit writes before reporting progress. Require a bounded, unencoded
        // response so it cannot start an unbounded transfer to disk.
        guard let response = response as? HTTPURLResponse,
              response.expectedContentLength >= 0,
              response.value(forHTTPHeaderField: "Transfer-Encoding") == nil,
              (response.value(forHTTPHeaderField: "Content-Encoding") ?? "identity").lowercased() == "identity"
        else { throw FaviconLoader.ResponseError.missing }
    }

    private func finish(error: (any Error)? = nil) {
        guard let continuation = result else { return }
        result = nil
        timeout?.cancel()
        timeout = nil
        progressObservation = nil
        webView.stopLoading()
        if let error {
            let destination = destination
            if let download {
                download.cancel { _ in try? FileManager.default.removeItem(at: destination) }
            } else {
                try? FileManager.default.removeItem(at: destination)
            }
            continuation.resume(throwing: error)
        } else {
            continuation.resume(returning: destination)
        }
        download = nil
    }
}

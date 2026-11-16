import os
import UIKit
import WebKit
import XCTest
@testable import Curio

final class FaviconTests: XCTestCase {
    @MainActor
    func testFallbackUsesOnlyTheHTTPOrigin() {
        let urls = FaviconLoader.candidates(
            declared: "https://cdn.example.com/declared.png",
            pageURL: "https://user:secret@[2001:db8::1]:8443/a?q=1#section"
        )
        XCTAssertEqual(urls.map(\.absoluteString), [
            "https://cdn.example.com/declared.png",
            "https://[2001:db8::1]:8443/favicon.ico",
        ])
        XCTAssertEqual(FaviconLoader.candidates(declared: nil, pageURL: "HTTP://Example.com/a").map(\.absoluteString), [
            "http://example.com/favicon.ico",
        ])
        XCTAssertTrue(FaviconLoader.candidates(declared: "httpx://example.com/icon", pageURL: "file:///index.html").isEmpty)
    }

    @MainActor
    func testConventionalDeclaredIconIsOnlyTriedOnce() async {
        let loader = makeLoader()
        let urls = FaviconLoader.candidates(declared: "https://favicon.test:443/favicon.ico#icon",
                                            pageURL: "https://favicon.test/page")
        XCTAssertEqual(urls.count, 1)
        let image = await loader.image(for: urls)
        XCTAssertNotNil(image)
        XCTAssertEqual(FaviconResponseStub.requests(), urls)
    }

    @MainActor
    func testWorkingDeclaredIconTakesPriority() async {
        let loader = makeLoader()
        let urls = candidates(declaredPath: "/working")
        let image = await loader.image(for: urls)
        XCTAssertNotNil(image)
        XCTAssertEqual(FaviconResponseStub.requests(), Array(urls.prefix(1)))
    }

    @MainActor
    func testBrokenDeclaredIconsRecoverAndShareCachedResults() async {
        let loader = makeLoader()
        let unreadable = candidates(declaredPath: "/unreadable")
        let missing = candidates(declaredPath: "/missing")
        let timeout = candidates(declaredPath: "/timeout")

        let recovered = await loader.image(for: unreadable)
        let cached = await loader.image(for: unreadable)
        let after404 = await loader.image(for: missing)
        let afterTimeout = await loader.image(for: timeout)
        XCTAssertNotNil(recovered)
        XCTAssertNotNil(cached)
        XCTAssertNotNil(after404)
        XCTAssertNotNil(afterTimeout)
        XCTAssertNotNil(loader.cachedImage(for: unreadable))
        XCTAssertEqual(FaviconResponseStub.requests().map(\.path), ["/unreadable", "/favicon.ico", "/missing", "/timeout"])
    }

    @MainActor
    func testMissingImagesStayMissingAndAreCached() async {
        let loader = makeLoader()
        let urls = FaviconLoader.candidates(declared: "https://favicon.test/missing",
                                            pageURL: "https://missing-favicon.test/page")
        let first = await loader.image(for: urls)
        let second = await loader.image(for: urls)
        XCTAssertNil(first)
        XCTAssertNil(second)
        XCTAssertEqual(FaviconResponseStub.requests(), urls)
    }

    @MainActor
    func testTemporaryFailuresRetryAndRecover() async {
        let loader = makeLoader()
        for path in ["/retry-timeout", "/retry-server-error"] {
            let urls = candidates(declaredPath: path)
            let recovered = await loader.image(for: urls)
            let retried = await loader.image(for: Array(urls.prefix(1)))
            XCTAssertNotNil(recovered)
            XCTAssertNotNil(retried)
            XCTAssertEqual(FaviconResponseStub.requests().filter { $0.path == path }.count, 2)
        }
    }

    @MainActor
    func testOversizedHeaderAndUnannouncedOversizedBodyUseFallback() async {
        let loader = makeLoader()
        for path in ["/oversized-header", "/oversized-body"] {
            let urls = candidates(declaredPath: path)
            let recovered = await loader.image(for: urls)
            let rejected = await loader.image(for: Array(urls.prefix(1)))
            XCTAssertNotNil(recovered)
            XCTAssertNil(rejected)
            XCTAssertEqual(FaviconResponseStub.requests().filter { $0.path == path }.count, 1)
        }
        let boundary = await loader.image(for: Array(candidates(declaredPath: "/exact-limit").prefix(1)))
        XCTAssertNotNil(boundary)
    }

    func testWebKitDownloadRequiresBoundedUnencodedBody() throws {
        let url = try XCTUnwrap(URL(string: "http://favicon.test/favicon.ico"))
        func response(_ fields: [String: String]) throws -> HTTPURLResponse {
            try XCTUnwrap(HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: fields))
        }
        XCTAssertNoThrow(try WebFaviconDownload.validate(response(["Content-Length": "128"])))
        XCTAssertThrowsError(try WebFaviconDownload.validate(response([:])))
        XCTAssertThrowsError(try WebFaviconDownload.validate(response(["Content-Length": "524289"])))
        XCTAssertThrowsError(try WebFaviconDownload.validate(response(["Content-Length": "128", "Content-Encoding": "gzip"])))
        XCTAssertThrowsError(try WebFaviconDownload.validate(response(["Content-Length": "128", "Transfer-Encoding": "chunked"])))
    }

    @MainActor
    func testRestoredDocumentReportsItsDeclaredFaviconAgain() async throws {
        let restoredIcon = "https://favicon.test/restored.ico"
        let restored = expectation(description: "Updated metadata from the restored document")
        let probe = FaviconBridgeProbe { body in
            if body["type"] as? String == "meta", body["favicon"] as? String == restoredIcon {
                restored.fulfill()
            }
        }
        let world = WKContentWorld.world(name: "Curio Favicon Tests")
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(probe, contentWorld: world, name: "curio")
        let webView = WKWebView(frame: .zero, configuration: configuration)
        _ = try await webView.callAsyncJavaScript("""
            \(PageScripts.bridge(token: "test"));
            const icon = document.createElement('link');
            icon.rel = 'icon';
            icon.href = '\(restoredIcon)';
            document.head.appendChild(icon);
            window.dispatchEvent(new PageTransitionEvent('pageshow', { persisted: true }));
            """, arguments: [:], in: nil, contentWorld: world)
        await fulfillment(of: [restored], timeout: 5)
    }

    @MainActor
    func testReusedViewKeepsItsLetterWhenAFormerPagesIconFinishes() async throws {
        let loader = makeLoader()
        let requested = expectation(description: "The first view has started its favicon request")
        FaviconResponseStub.onSlowRequest { requested.fulfill() }
        let view = FaviconView(loader: loader)
        let firstURL = "https://favicon.test/slow"
        let secondURL = "https://missing-favicon.test/page"
        let letter = try XCTUnwrap(view.subviews.compactMap { $0 as? UILabel }.first)
        let image = try XCTUnwrap(view.subviews.compactMap { $0 as? UIImageView }.first)

        view.configure(label: "First", url: firstURL, pageURL: firstURL)
        XCTAssertEqual(letter.text, "F")
        XCTAssertFalse(letter.isHidden)
        XCTAssertTrue(image.isHidden)

        await fulfillment(of: [requested], timeout: 5)
        XCTAssertEqual(FaviconResponseStub.requests().map(\.absoluteString), [firstURL])
        view.configure(label: "Second", url: nil, pageURL: secondURL)

        let newImage = await loader.image(for: FaviconLoader.candidates(declared: nil, pageURL: secondURL))
        FaviconResponseStub.completeSlowRequest()
        let oldImage = await loader.image(for: FaviconLoader.candidates(declared: firstURL, pageURL: firstURL))
        XCTAssertNil(newImage)
        XCTAssertNotNil(oldImage)
        await Task.yield()
        XCTAssertEqual(letter.text, "S")
        XCTAssertFalse(letter.isHidden)
        XCTAssertTrue(image.isHidden)
    }

    @MainActor
    private func candidates(declaredPath: String) -> [URL] {
        FaviconLoader.candidates(declared: "https://favicon.test\(declaredPath)", pageURL: "https://favicon.test/page")
    }

    @MainActor
    private func makeLoader() -> FaviconLoader {
        FaviconResponseStub.reset()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FaviconResponseStub.self]
        return FaviconLoader(session: URLSession(configuration: configuration))
    }
}

@MainActor
private final class FaviconBridgeProbe: NSObject, WKScriptMessageHandler {
    private let receive: ([String: Any]) -> Void

    init(receive: @escaping ([String: Any]) -> Void) { self.receive = receive }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        if let body = message.body as? [String: Any] { receive(body) }
    }
}

private final class FaviconResponseStub: URLProtocol, @unchecked Sendable {
    private struct State {
        var requests: [URL] = []
        var onSlowRequest: (@Sendable () -> Void)?
        var slowResponse: (@Sendable () -> Void)?
    }

    private static let state = OSAllocatedUnfairLock(initialState: State())
    // A 16×16 ICO with a PNG payload.
    private static let ico = Data(base64Encoded: "AAABAAEAEBAAAAEAIABSAAAAFgAAAIlQTkcNChoKAAAADUlIRFIAAAAQAAAAEAgGAAAAH/P/YQAAABlJREFUeJxj+M8Q+p8SzDBqwKgBowYMFwMAuFhTH4gPtB4AAAAASUVORK5CYII=")!

    static func requests() -> [URL] { state.withLock { $0.requests } }
    static func reset() { state.withLock { $0 = State() } }

    static func onSlowRequest(_ notify: @escaping @Sendable () -> Void) {
        state.withLock { $0.onSlowRequest = notify }
    }

    static func completeSlowRequest() {
        let complete = state.withLock { state in
            defer { state.slowResponse = nil }
            return state.slowResponse
        }
        complete?()
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        let firstRequest = Self.state.withLock { state in
            let first = !state.requests.contains(url)
            state.requests.append(url)
            return first
        }
        if url.path == "/slow" {
            let notify = Self.state.withLock { state in
                state.slowResponse = { [self] in sendResponse(for: url, firstRequest: firstRequest) }
                return state.onSlowRequest
            }
            notify?()
        } else {
            sendResponse(for: url, firstRequest: firstRequest)
        }
    }

    private func sendResponse(for url: URL, firstRequest: Bool) {
        if url.path == "/timeout" || (url.path == "/retry-timeout" && firstRequest) {
            client?.urlProtocol(self, didFailWithError: URLError(.timedOut))
            return
        }
        let hasImage = url.host == "favicon.test" && [
            "/favicon.ico", "/working", "/slow", "/retry-timeout", "/retry-server-error",
            "/oversized-header", "/oversized-body", "/exact-limit",
        ].contains(url.path)
        let status = if url.path == "/retry-server-error" && firstRequest { 503 }
            else { hasImage || url.path == "/unreadable" ? 200 : 404 }
        let limit = FaviconLoader.maximumResponseBytes
        let headers = url.path == "/oversized-header" ? ["Content-Length": String(limit + 1)] : nil
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: hasImage ? Self.ico : Data("not an image".utf8))
        if url.path == "/oversized-body" || url.path == "/exact-limit" {
            let padding = limit - Self.ico.count + (url.path == "/oversized-body" ? 1 : 0)
            client?.urlProtocol(self, didLoad: Data(repeating: 0, count: padding))
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

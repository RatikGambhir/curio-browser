import os
import UIKit
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
    func testReusedViewKeepsItsLetterWhenAFormerPagesIconFinishes() async throws {
        let loader = makeLoader()
        let view = FaviconView(loader: loader)
        let firstURL = "https://favicon.test/slow"
        let secondURL = "https://missing-favicon.test/page"
        let letter = try XCTUnwrap(view.subviews.compactMap { $0 as? UILabel }.first)
        let image = try XCTUnwrap(view.subviews.compactMap { $0 as? UIImageView }.first)

        view.configure(label: "First", url: firstURL, pageURL: firstURL)
        XCTAssertEqual(letter.text, "F")
        XCTAssertFalse(letter.isHidden)
        XCTAssertTrue(image.isHidden)

        let clock = ContinuousClock()
        let deadline = clock.now + .seconds(2)
        while FaviconResponseStub.requests().isEmpty && clock.now < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertEqual(FaviconResponseStub.requests().map(\.absoluteString), [firstURL])
        view.configure(label: "Second", url: nil, pageURL: secondURL)

        let newImage = await loader.image(for: FaviconLoader.candidates(declared: nil, pageURL: secondURL))
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

private final class FaviconResponseStub: URLProtocol, @unchecked Sendable {
    private static let recorded = OSAllocatedUnfairLock(initialState: [URL]())
    // A 16×16 ICO with a PNG payload.
    private static let ico = Data(base64Encoded: "AAABAAEAEBAAAAEAIABSAAAAFgAAAIlQTkcNChoKAAAADUlIRFIAAAAQAAAAEAgGAAAAH/P/YQAAABlJREFUeJxj+M8Q+p8SzDBqwKgBowYMFwMAuFhTH4gPtB4AAAAASUVORK5CYII=")!

    static func requests() -> [URL] { recorded.withLock { $0 } }
    static func reset() { recorded.withLock { $0.removeAll() } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else { return }
        Self.recorded.withLock { $0.append(url) }
        if url.path == "/slow" {
            Task { @Sendable [self] in
                try? await Task.sleep(for: .milliseconds(250))
                sendResponse(for: url)
            }
        } else {
            sendResponse(for: url)
        }
    }

    private func sendResponse(for url: URL) {
        if url.path == "/timeout" {
            client?.urlProtocol(self, didFailWithError: URLError(.timedOut))
            return
        }
        let hasImage = url.host == "favicon.test" && ["/favicon.ico", "/working", "/slow"].contains(url.path)
        let status = hasImage || url.path == "/unreadable" ? 200 : 404
        let response = HTTPURLResponse(url: url, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: hasImage ? Self.ico : Data("not an image".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

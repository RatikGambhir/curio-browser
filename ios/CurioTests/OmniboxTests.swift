import XCTest
@testable import Curio

final class OmniboxTests: XCTestCase {
    private func nav(_ input: String) -> Navigation? {
        Omnibox.classify(input, engine: .duckDuckGo)
    }

    func testBlankInputIsIgnored() {
        XCTAssertNil(Omnibox.classify("   ", engine: .google))
    }

    func testExplicitURLsAreKept() {
        XCTAssertEqual(nav("https://github.com/zed-industries/zed"), .url("https://github.com/zed-industries/zed"))
        XCTAssertEqual(nav("about:blank"), .url("about:blank"))
    }

    func testBareDomainsGetHTTPS() {
        XCTAssertEqual(nav("rust-lang.org/learn"), .url("https://rust-lang.org/learn"))
        XCTAssertEqual(nav("docs.rs"), .url("https://docs.rs/"))
    }

    func testLocalAddressesGetHTTP() {
        XCTAssertEqual(nav("localhost:3000/app"), .url("http://localhost:3000/app"))
        XCTAssertEqual(nav("192.168.1.10"), .url("http://192.168.1.10/"))
    }

    func testWordsAndSentencesSearch() {
        guard case .search = nav("gpui") else { return XCTFail("expected search") }
        guard case .search(let query, let url) = nav("how does gpui handle state?") else { return XCTFail("expected search") }
        XCTAssertEqual(query, "how does gpui handle state?")
        XCTAssertTrue(url.hasPrefix("https://duckduckgo.com/?q=how%20does%20gpui"))
    }

    func testDangerousSchemesAreSearchedNotExecuted() {
        guard case .search = nav("javascript:alert(1)") else { return XCTFail("javascript: must be searched") }
        guard case .search = nav("vbscript:foo") else { return XCTFail("vbscript: must be searched") }
    }

    func testVersionNumbersAreNotDomains() {
        guard case .search = nav("v1.2") else { return XCTFail("expected search") }
    }

    func testCustomEngineTemplate() {
        let engine = SearchEngine.custom("https://search.example/?q=%s&src=curio")
        XCTAssertEqual(engine.searchURL(for: "a b"), "https://search.example/?q=a%20b&src=curio")
    }

    func testDisplayHostStripsWWWAndPath() {
        XCTAssertEqual(Curio.displayHost("https://www.example.com/a/b?c=d"), "example.com")
        XCTAssertEqual(Curio.displayHost("http://localhost:8080/x"), "localhost")
        XCTAssertEqual(Curio.displayHost(Curio.newTabURL), "Curio")
    }
}

import UIKit
import XCTest
@testable import Curio

final class SettingsTests: XCTestCase {
    func testMissingFieldsFallBackToDefaults() throws {
        let settings = try JSONDecoder().decode(Settings.self, from: Data(#"{"appearance":{"theme":"dark"}}"#.utf8))
        XCTAssertEqual(settings.appearance.theme, .dark)
        XCTAssertEqual(settings.appearance.sidebarWidth, 260)
        XCTAssertEqual(settings.ai.provider, .anthropic)
    }

    func testSanitizeClampsValues() {
        var settings = Settings()
        settings.appearance.sidebarWidth = 9_999
        settings.browsing.maxLiveTabs = 0
        let clean = settings.sanitized()
        XCTAssertEqual(clean.appearance.sidebarWidth, 420)
        XCTAssertEqual(clean.browsing.maxLiveTabs, 2)
    }

    func testOnlyCompatibleProvidersTakeACustomBaseURL() {
        var ai = AISettings()
        ai.update(.openAI) { $0.baseURL = "https://evil.example" }
        ai.update(.openAICompatible) { $0.baseURL = "http://localhost:1234/v1/" }
        XCTAssertEqual(ai.baseURL(for: .openAI), "https://api.openai.com/v1")
        XCTAssertEqual(ai.baseURL(for: .openAICompatible), "http://localhost:1234/v1")
        XCTAssertEqual(ai.model(for: .anthropic), "claude-opus-5-5")
    }

    @MainActor
    func testKeystrokeParsing() {
        XCTAssertEqual(KeyStroke("shift-secondary-t"), KeyStroke("cmd-shift-t"))
        XCTAssertEqual(KeyStroke("secondary--")?.input, "-")
        XCTAssertEqual(KeyStroke("ctrl-secondary-right")?.input, UIKeyCommand.inputRightArrow)
        XCTAssertEqual(KeyStroke("shift-secondary-]")?.label, "⇧⌘]")
        XCTAssertNil(KeyStroke("hyper-x"))
    }

    func testEveryDefaultShortcutParses() {
        for command in CurioCommand.allCases {
            for stroke in command.defaultKeystrokes {
                XCTAssertNotNil(KeyStroke(stroke), "\(command.rawValue): \(stroke)")
            }
        }
    }

    func testThemeTokensKeepTextReadable() {
        for accent in AccentColor.allCases {
            let light = CurioTheme(accent: accent, appearance: .light)
            XCTAssertGreaterThan(light.chromeTop.l - light.text.l, 0.6)
            let dark = CurioTheme(accent: accent, appearance: .dark)
            XCTAssertGreaterThan(dark.text.l - dark.chromeTop.l, 0.6)
        }
    }

    func testHueMixTakesShortestPath() {
        let mixed = HSLA.mix(HSLA(0.95, 0.5, 0.5), HSLA(0.05, 0.5, 0.5), 0.5)
        XCTAssertTrue(mixed.h < 0.01 || mixed.h > 0.99)
    }
}

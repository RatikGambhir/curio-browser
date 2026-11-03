import Foundation

/// All user preferences. Every field has a default so settings written by
/// other versions of Curio always load. API keys live in the Keychain.
nonisolated struct Settings: Codable, Equatable, Sendable {
    var appearance = AppearanceSettings()
    var browsing = BrowsingSettings()
    var ai = AISettings()
    /// Keybinding overrides: action name (e.g. `curio::NewTab`) to keystroke
    /// (e.g. `secondary-shift-n`). An empty keystroke unbinds.
    var keybindings: [String: String] = [:]

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        appearance = (try? c.decodeIfPresent(AppearanceSettings.self, forKey: .appearance)) ?? AppearanceSettings()
        browsing = (try? c.decodeIfPresent(BrowsingSettings.self, forKey: .browsing)) ?? BrowsingSettings()
        ai = (try? c.decodeIfPresent(AISettings.self, forKey: .ai)) ?? AISettings()
        keybindings = (try? c.decodeIfPresent([String: String].self, forKey: .keybindings)) ?? [:]
    }

    /// Clamps values that could have been edited out of range.
    func sanitized() -> Settings {
        var s = self
        s.appearance.sidebarWidth = min(max(s.appearance.sidebarWidth, 200), 420)
        s.appearance.aiPanelWidth = min(max(s.appearance.aiPanelWidth, 300), 640)
        s.browsing.maxLiveTabs = min(max(s.browsing.maxLiveTabs, 2), 64)
        s.browsing.sleepAfterMinutes = min(max(s.browsing.sleepAfterMinutes, 5), 24 * 60)
        s.ai.maxContextChars = min(max(s.ai.maxContextChars, 2_000), 400_000)
        return s
    }
}

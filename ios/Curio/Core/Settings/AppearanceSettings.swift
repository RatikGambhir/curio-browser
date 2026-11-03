import Foundation

/// Appearance preferences.
nonisolated struct AppearanceSettings: Codable, Equatable, Sendable {
    var theme: ThemeMode = .system
    var tabLayout: TabLayout = .vertical
    var sidebarVisible = true
    var sidebarWidth: Double = 260
    var aiPanelWidth: Double = 380
    /// Tint the chrome with the active space's color.
    var tintChromeWithSpace = true
    var reduceMotion = false

    private enum CodingKeys: String, CodingKey {
        case theme, tabLayout = "tab_layout", sidebarVisible = "sidebar_visible", sidebarWidth = "sidebar_width"
        case aiPanelWidth = "ai_panel_width", tintChromeWithSpace = "tint_chrome_with_space", reduceMotion = "reduce_motion"
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppearanceSettings()
        theme = (try? c.decodeIfPresent(ThemeMode.self, forKey: .theme)) ?? d.theme
        tabLayout = (try? c.decodeIfPresent(TabLayout.self, forKey: .tabLayout)) ?? d.tabLayout
        sidebarVisible = try c.decodeIfPresent(Bool.self, forKey: .sidebarVisible) ?? d.sidebarVisible
        sidebarWidth = try c.decodeIfPresent(Double.self, forKey: .sidebarWidth) ?? d.sidebarWidth
        aiPanelWidth = try c.decodeIfPresent(Double.self, forKey: .aiPanelWidth) ?? d.aiPanelWidth
        tintChromeWithSpace = try c.decodeIfPresent(Bool.self, forKey: .tintChromeWithSpace) ?? d.tintChromeWithSpace
        reduceMotion = try c.decodeIfPresent(Bool.self, forKey: .reduceMotion) ?? d.reduceMotion
    }
}

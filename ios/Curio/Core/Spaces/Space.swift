import Foundation

/// An independent browsing context with its own tabs and appearance.
nonisolated struct Space: Codable, Equatable, Identifiable, Sendable {
    /// Icons offered when creating or customizing a space.
    static let icons = [
        "✦", "☀︎", "☾", "◆", "●", "▲", "♠︎", "♣︎", "♥︎", "⚑", "✿", "❖", "🧭", "🔭", "🧪", "📚", "💼", "🎨",
        "🎧", "🌿", "🏔", "⚡️", "🚀", "🏠",
    ]

    var id: UUID
    var name: String
    /// A short glyph or emoji shown in the space switcher.
    var icon: String
    var color: AccentColor
    var strip: TabStrip
    /// The tab shown when this space is active. May be a favorite's tab.
    var activeTab: UUID?

    init(name: String, icon: String, color: AccentColor) {
        id = UUID()
        self.name = name
        self.icon = icon
        self.color = color
        strip = TabStrip()
        activeTab = nil
    }

    private enum CodingKeys: String, CodingKey { case id, name, icon, color, strip, activeTab = "active_tab" }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Space"
        icon = try c.decodeIfPresent(String.self, forKey: .icon) ?? Space.icons[0]
        color = (try? c.decodeIfPresent(AccentColor.self, forKey: .color)) ?? .iris
        strip = try c.decodeIfPresent(TabStrip.self, forKey: .strip) ?? TabStrip()
        activeTab = try c.decodeIfPresent(UUID.self, forKey: .activeTab)
    }
}

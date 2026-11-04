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
    /// The theme behind the chrome. Its tone also decides whether the chrome
    /// is light or dark.
    var gradient: SpaceGradient
    var strip: TabStrip
    /// The tab shown when this space is active. May be a favorite's tab.
    var activeTab: UUID?

    init(name: String, icon: String, gradient: SpaceGradient) {
        id = UUID()
        self.name = name
        self.icon = icon
        self.gradient = gradient
        strip = TabStrip()
        activeTab = nil
    }

    private enum CodingKeys: String, CodingKey { case id, name, icon, gradient, color, strip, activeTab = "active_tab" }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Space"
        icon = try c.decodeIfPresent(String.self, forKey: .icon) ?? Space.icons[0]
        // Spaces saved before themes only have an accent; give them the
        // matching light theme.
        if let gradient = try? c.decodeIfPresent(SpaceGradient.self, forKey: .gradient) {
            self.gradient = gradient
        } else if let color = try? c.decodeIfPresent(AccentColor.self, forKey: .color) {
            gradient = SpaceGradient.from(accent: color)
        } else {
            gradient = .default
        }
        strip = try c.decodeIfPresent(TabStrip.self, forKey: .strip) ?? TabStrip()
        activeTab = try c.decodeIfPresent(UUID.self, forKey: .activeTab)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(icon, forKey: .icon)
        try c.encode(gradient, forKey: .gradient)
        // Older builds only read the accent.
        try c.encode(gradient.legacyAccent, forKey: .color)
        try c.encode(strip, forKey: .strip)
        try c.encodeIfPresent(activeTab, forKey: .activeTab)
    }
}

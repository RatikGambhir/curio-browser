import Foundation

/// One browser tab's persistent state. Live page state (loading, history)
/// lives in `BrowserTab`.
nonisolated struct Tab: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var url: String
    var title: String
    var faviconURL: String?
    /// The address a pinned tab or favorite returns to when unloaded.
    var homeURL: String?
    var scrollY: Double
    var createdAt: Timestamp
    var lastActiveAt: Timestamp

    init(url: String = Curio.newTabURL) {
        let now = Timestamp.now
        id = UUID()
        self.url = url
        title = ""
        faviconURL = nil
        homeURL = nil
        scrollY = 0
        createdAt = now
        lastActiveAt = now
    }

    /// The title, falling back to the host or "New Tab".
    var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        if url == Curio.newTabURL { return "New Tab" }
        return Curio.displayHost(url)
    }

    var isNewTabPage: Bool { url == Curio.newTabURL }

    /// A copy of this tab with a new identity.
    func duplicate() -> Tab {
        var copy = self
        let now = Timestamp.now
        copy.id = UUID()
        copy.createdAt = now
        copy.lastActiveAt = now
        return copy
    }

    private enum CodingKeys: String, CodingKey {
        case id, url, title, faviconURL = "favicon_url", homeURL = "home_url", scrollY = "scroll_y"
        case createdAt = "created_at", lastActiveAt = "last_active_at"
    }

    /// Missing fields fall back to defaults, so older sessions always load.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = Tab()
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? fallback.id
        url = try c.decodeIfPresent(String.self, forKey: .url) ?? fallback.url
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        faviconURL = try c.decodeIfPresent(String.self, forKey: .faviconURL)
        homeURL = try c.decodeIfPresent(String.self, forKey: .homeURL)
        scrollY = try c.decodeIfPresent(Double.self, forKey: .scrollY) ?? 0
        createdAt = try c.decodeIfPresent(Timestamp.self, forKey: .createdAt) ?? fallback.createdAt
        lastActiveAt = try c.decodeIfPresent(Timestamp.self, forKey: .lastActiveAt) ?? fallback.lastActiveAt
    }
}

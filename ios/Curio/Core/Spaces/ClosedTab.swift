import Foundation

/// A closed tab remembered for "Reopen Closed Tab" and the archive. Saved
/// with the session, so it survives restarts.
nonisolated struct ClosedTab: Codable, Equatable, Sendable {
    var space: UUID
    var tab: Tab
    var restoreAt: TabPlacement
    /// When it was closed. Tabs closed before this was recorded read as 0.
    var closedAt: Timestamp

    init(space: UUID, tab: Tab, restoreAt: TabPlacement, closedAt: Timestamp = .now) {
        self.space = space
        self.tab = tab
        self.restoreAt = restoreAt
        self.closedAt = closedAt
    }

    private enum CodingKeys: String, CodingKey { case space, tab, restoreAt, closedAt = "closed_at" }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        space = try c.decode(UUID.self, forKey: .space)
        tab = try c.decode(Tab.self, forKey: .tab)
        restoreAt = try c.decode(TabPlacement.self, forKey: .restoreAt)
        closedAt = try c.decodeIfPresent(Timestamp.self, forKey: .closedAt) ?? 0
    }
}

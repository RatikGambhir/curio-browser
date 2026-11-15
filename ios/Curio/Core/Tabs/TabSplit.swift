import Foundation

/// How the panes of a split view are arranged.
nonisolated enum SplitOrientation: String, Codable, Sendable {
    /// Side by side, left to right.
    case horizontal
    /// Stacked, top to bottom.
    case vertical

    var flipped: SplitOrientation { self == .horizontal ? .vertical : .horizontal }
}

/// Two to four tabs shown side by side in one window, like Arc's and Dia's
/// split view. The member tabs stay ordinary tabs of their space (and
/// folder); the split only records which of them are shown together and how
/// much room each pane gets.
nonisolated struct TabSplit: Equatable, Identifiable, Sendable {
    /// The fewest tabs a split holds; with fewer it dissolves.
    static let minPanes = 2
    /// The most tabs a split holds.
    static let maxPanes = 4
    /// The smallest share a pane can be resized to.
    static let minSize = 0.15

    var id: UUID
    /// Member tabs, in pane order (left to right, or top to bottom).
    var tabs: [UUID]
    /// Each pane's share of the split, parallel to `tabs`. Sums to 1.
    var sizes: [Double]
    var orientation: SplitOrientation

    /// Creates a split with equal panes. Duplicate ids are dropped and only
    /// the first `maxPanes` tabs are kept.
    init(tabs: [UUID], orientation: SplitOrientation = .horizontal, id: UUID = UUID()) {
        self.id = id
        self.orientation = orientation
        var unique: [UUID] = []
        for tab in tabs where unique.count < Self.maxPanes && !unique.contains(tab) {
            unique.append(tab)
        }
        self.tabs = unique
        sizes = []
        equalize()
    }

    func contains(_ tab: UUID) -> Bool { tabs.contains(tab) }

    /// Whether the split still has enough panes to be shown.
    var isValid: Bool { (Self.minPanes...Self.maxPanes).contains(tabs.count) }

    /// Whether another pane can be added.
    var isFull: Bool { tabs.count >= Self.maxPanes }

    /// Gives every pane the same share.
    mutating func equalize() {
        let share = 1 / Double(max(tabs.count, 1))
        sizes = Array(repeating: share, count: tabs.count)
    }

    /// Repairs `sizes` after loading or editing: one finite, positive share
    /// per pane, summing to 1. Anything unusable resets to equal panes.
    mutating func normalize() {
        let usable = sizes.count == tabs.count && sizes.allSatisfy { $0.isFinite && $0 > 0 }
        let total = sizes.reduce(0, +)
        guard usable, total > .ulpOfOne else { return equalize() }
        sizes = sizes.map { $0 / total }
    }

    /// Adds a pane at `index` (clamped to the end), splitting the room
    /// evenly. Returns `false` when the split is full or already has the tab.
    @discardableResult
    mutating func addTab(_ tab: UUID, at index: Int) -> Bool {
        guard !isFull, !contains(tab) else { return false }
        tabs.insert(tab, at: max(0, min(index, tabs.count)))
        equalize()
        return true
    }

    /// Removes a pane, giving its room to the pane before it (or the one
    /// after, for the first). Returns `false` when the tab isn't a pane.
    @discardableResult
    mutating func removeTab(_ tab: UUID) -> Bool {
        guard let index = tabs.firstIndex(of: tab) else { return false }
        tabs.remove(at: index)
        let freed = index < sizes.count ? sizes.remove(at: index) : 0
        let heir = min(max(index - 1, 0), sizes.count - 1)
        if sizes.indices.contains(heir) { sizes[heir] += freed }
        normalize()
        return true
    }

    /// Moves the divider after pane `divider` by `delta` (a share of the
    /// whole split), keeping both neighbors at least `minSize`. Returns
    /// `true` when anything moved.
    @discardableResult
    mutating func resize(divider: Int, by delta: Double) -> Bool {
        guard delta.isFinite, divider >= 0, divider + 1 < sizes.count else { return false }
        let before = sizes[divider]
        let pair = before + sizes[divider + 1]
        // Panes already smaller than the minimum may still be resized.
        let minimum = min(Self.minSize, pair / 2)
        let next = min(max(before + delta, minimum), pair - minimum)
        guard abs(next - before) > 1e-6 else { return false }
        sizes[divider] = next
        sizes[divider + 1] = pair - next
        return true
    }
}

nonisolated extension TabSplit: Codable {
    private enum CodingKeys: String, CodingKey { case id, tabs, sizes, orientation }

    /// Missing or unknown fields fall back to defaults; the strip repairs
    /// anything that doesn't fit its tabs.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        tabs = try c.decodeIfPresent([UUID].self, forKey: .tabs) ?? []
        sizes = (try? c.decodeIfPresent([Double].self, forKey: .sizes)) ?? []
        orientation = (try? c.decodeIfPresent(SplitOrientation.self, forKey: .orientation)) ?? .horizontal
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(tabs, forKey: .tabs)
        try c.encode(sizes, forKey: .sizes)
        try c.encode(orientation, forKey: .orientation)
    }
}

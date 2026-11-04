import Foundation

/// The full browser organization: spaces (each with tabs, pinned tabs,
/// groups, name, icon, theme and active tab), global favorites, and recently
/// closed tabs. It has no engine or UI state, so every operation is
/// synchronous and unit tested.
nonisolated struct Workspace: Equatable, Sendable {
    /// How many closed tabs are remembered.
    static let closedTabLimit = 50

    private(set) var spaces: [Space]
    private(set) var favorites: [Favorite]
    private(set) var activeSpaceID: UUID
    private(set) var closedTabs: [ClosedTab] = []

    /// Builds a workspace from persisted parts. An empty list gets a default
    /// space so there is always somewhere to put tabs.
    init(spaces: [Space], favorites: [Favorite], closed: [ClosedTab] = []) {
        var spaces = spaces
        if spaces.isEmpty { spaces.append(Space(name: "Personal", icon: "✦", gradient: .default)) }
        self.spaces = spaces
        self.favorites = favorites
        activeSpaceID = spaces[0].id
        closedTabs = Self.restoredClosedTabs(closed, spaces: spaces)
        // Drop active-tab references that no longer resolve.
        for index in self.spaces.indices {
            if let active = self.spaces[index].activeTab, findTab(active) == nil {
                self.spaces[index].activeTab = nil
            }
        }
    }

    /// Saved closed tabs, ready to use: tabs whose space is gone are
    /// dropped, the rest are newest first (ties keep their saved order),
    /// and at most `closedTabLimit` are kept.
    private static func restoredClosedTabs(_ closed: [ClosedTab], spaces: [Space]) -> [ClosedTab] {
        let kept = closed.enumerated().filter { item in spaces.contains { $0.id == item.element.space } }
        let sorted = kept.sorted { a, b in
            a.element.closedAt != b.element.closedAt ? a.element.closedAt > b.element.closedAt : a.offset < b.offset
        }
        return Array(sorted.prefix(closedTabLimit).map(\.element))
    }

    /// A first-run workspace with two starter spaces.
    static func firstRun() -> Workspace {
        Workspace(spaces: [
            Space(name: "Personal", icon: "✦", gradient: .lavenderBlush),
            Space(name: "Work", icon: "💼", gradient: .skyHaze),
        ], favorites: [])
    }

    // MARK: - Spaces

    func space(_ id: UUID) -> Space? { spaces.first { $0.id == id } }
    func spaceIndex(_ id: UUID) -> Int? { spaces.firstIndex { $0.id == id } }

    var activeSpace: Space { space(activeSpaceID) ?? spaces[0] }

    /// Mutates a space in place. Returns `false` for unknown spaces.
    @discardableResult
    mutating func updateSpace(_ id: UUID, _ change: (inout Space) -> Void) -> Bool {
        guard let index = spaceIndex(id) else { return false }
        change(&spaces[index])
        return true
    }

    mutating func updateActiveSpace(_ change: (inout Space) -> Void) {
        let index = spaceIndex(activeSpaceID) ?? 0
        change(&spaces[index])
    }

    /// Creates a space after the existing ones.
    @discardableResult
    mutating func createSpace(name: String, icon: String, gradient: SpaceGradient?) -> UUID {
        let gradient = gradient ?? spaces.last.map(\.gradient.next) ?? .default
        let space = Space(name: name, icon: icon, gradient: gradient)
        spaces.append(space)
        return space.id
    }

    @discardableResult
    mutating func renameSpace(_ id: UUID, to name: String) -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }
        return updateSpace(id) { $0.name = name }
    }

    @discardableResult
    mutating func setSpaceIcon(_ id: UUID, _ icon: String) -> Bool {
        let icon = icon.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !icon.isEmpty else { return false }
        return updateSpace(id) { $0.icon = icon }
    }

    @discardableResult
    mutating func setSpaceGradient(_ id: UUID, _ gradient: SpaceGradient) -> Bool {
        updateSpace(id) { $0.gradient = gradient }
    }

    /// Deletes a space and its tabs. The last space cannot be deleted.
    mutating func deleteSpace(_ id: UUID) -> Space? {
        guard spaces.count > 1, let index = spaceIndex(id) else { return nil }
        let removed = spaces.remove(at: index)
        if activeSpaceID == id {
            activeSpaceID = spaces[min(index, spaces.count - 1)].id
        }
        closedTabs.removeAll { $0.space == id }
        return removed
    }

    /// Moves a space to `newIndex` (clamped).
    @discardableResult
    mutating func moveSpace(_ id: UUID, to newIndex: Int) -> Bool {
        guard let index = spaceIndex(id) else { return false }
        let space = spaces.remove(at: index)
        spaces.insert(space, at: max(0, min(newIndex, spaces.count)))
        return true
    }

    /// Activates a space.
    @discardableResult
    mutating func switchSpace(_ id: UUID) -> Bool {
        guard space(id) != nil, activeSpaceID != id else { return false }
        activeSpaceID = id
        return true
    }

    /// The space next to the active one (`forward` means to the right).
    func adjacentSpace(forward: Bool) -> UUID? {
        guard let index = spaceIndex(activeSpaceID) else { return nil }
        let target = forward ? index + 1 : index - 1
        return spaces.indices.contains(target) ? spaces[target].id : nil
    }

    mutating func restoreActiveSpace(_ id: UUID) {
        if space(id) != nil { activeSpaceID = id }
    }

    // MARK: - Tabs

    /// Finds a tab in any space or favorite.
    func findTab(_ id: UUID) -> (owner: TabOwner, tab: Tab)? {
        if let favorite = favorites.first(where: { $0.tab.id == id }) {
            return (.favorite(favorite.id), favorite.tab)
        }
        for space in spaces {
            if let tab = space.strip.tab(id) { return (.space(space.id), tab) }
        }
        return nil
    }

    func tab(_ id: UUID) -> Tab? { findTab(id)?.tab }

    /// Mutates a tab wherever it lives.
    mutating func updateTab(_ id: UUID, _ change: (inout Tab) -> Void) {
        if let index = favorites.firstIndex(where: { $0.tab.id == id }) {
            change(&favorites[index].tab)
            return
        }
        for index in spaces.indices where spaces[index].strip.contains(id) {
            spaces[index].strip.updateTab(id, change)
            return
        }
    }

    /// The space that owns a tab, unless it is a favorite.
    func spaceOfTab(_ id: UUID) -> UUID? {
        spaces.first { $0.strip.contains(id) }?.id
    }

    var activeTabID: UUID? { activeSpace.activeTab }
    var activeTab: Tab? { activeTabID.flatMap(tab) }

    /// Opens a tab in `space`. With `activate`, it becomes the space's
    /// active tab.
    @discardableResult
    mutating func openTab(_ tab: Tab, in space: UUID, at placement: TabPlacement, activate: Bool) -> UUID? {
        guard let index = spaceIndex(space) else { return nil }
        let id = spaces[index].strip.insert(tab, at: placement)
        if activate { spaces[index].activeTab = id }
        return id
    }

    /// Opens a tab in the active space next to the active tab when it is a
    /// regular tab, or at the top of the regular section otherwise.
    @discardableResult
    mutating func openTabInActiveSpace(_ tab: Tab, activate: Bool) -> UUID {
        openTab(tab, in: activeSpaceID, at: placementNearActive, activate: activate)
        return tab.id
    }

    private var placementNearActive: TabPlacement {
        let space = activeSpace
        if let active = space.activeTab, space.strip.location(of: active)?.section == .unpinned {
            return .afterTab(active)
        }
        return .sectionStart(.unpinned)
    }

    /// Activates a tab, switching to its space when needed. Favorites open in
    /// the active space.
    @discardableResult
    mutating func activateTab(_ id: UUID) -> Bool {
        guard let (owner, _) = findTab(id) else { return false }
        if case .space(let space) = owner { activeSpaceID = space }
        updateActiveSpace { $0.activeTab = id }
        updateTab(id) { $0.lastActiveAt = .now }
        return true
    }

    /// Closes a regular tab, remembering it for reopening. Returns the tab
    /// that became active in its space.
    mutating func closeTab(_ id: UUID) -> (space: UUID, nextActive: UUID?)? {
        guard let spaceID = spaceOfTab(id), let index = spaceIndex(spaceID) else { return nil }
        let next = spaces[index].strip.neighborForClose(id)
        guard let removed = spaces[index].strip.remove(id) else { return nil }
        if spaces[index].activeTab == id { spaces[index].activeTab = next }
        closedTabs.insert(ClosedTab(space: spaceID, tab: removed.tab, restoreAt: removed.restoreAt, closedAt: .now), at: 0)
        if closedTabs.count > Self.closedTabLimit { closedTabs.removeLast(closedTabs.count - Self.closedTabLimit) }
        return (spaceID, spaces[index].activeTab)
    }

    /// Closed tabs for the Library's Archived Tabs, newest first, with the
    /// space each came from. Every word of `query` must appear in the tab's
    /// title, its URL or the space's name.
    func archivedTabs(matching query: String) -> [(closed: ClosedTab, space: Space)] {
        let words = query.split(whereSeparator: \.isWhitespace)
        return closedTabs.compactMap { closed in
            guard let owner = space(closed.space) else { return nil }
            let fields = [closed.tab.displayTitle, closed.tab.url, owner.name]
            let matches = words.allSatisfy { word in fields.contains { $0.localizedStandardContains(word) } }
            return matches ? (closed, owner) : nil
        }
    }

    /// Reopens the most recently closed tab in its original place.
    mutating func reopenClosedTab() -> UUID? {
        while !closedTabs.isEmpty {
            let closed = closedTabs.removeFirst()
            guard space(closed.space) != nil else { continue }
            openTab(closed.tab, in: closed.space, at: closed.restoreAt, activate: true)
            activeSpaceID = closed.space
            return closed.tab.id
        }
        return nil
    }

    /// Reopens one closed tab in its original place.
    mutating func reopenClosed(_ id: UUID) -> UUID? {
        guard let index = closedTabs.firstIndex(where: { $0.tab.id == id }) else { return nil }
        let closed = closedTabs.remove(at: index)
        guard space(closed.space) != nil else { return nil }
        openTab(closed.tab, in: closed.space, at: closed.restoreAt, activate: true)
        activeSpaceID = closed.space
        return id
    }

    /// Duplicates a tab next to the original and returns the copy's id.
    mutating func duplicateTab(_ id: UUID) -> UUID? {
        guard let copy = tab(id)?.duplicate() else { return nil }
        if let spaceID = spaceOfTab(id), let space = space(spaceID) {
            let placement: TabPlacement = space.strip.isPinned(id) ? .sectionStart(.unpinned) : .afterTab(id)
            openTab(copy, in: spaceID, at: placement, activate: true)
        } else {
            openTab(copy, in: activeSpaceID, at: .sectionStart(.unpinned), activate: true)
        }
        return copy.id
    }

    /// Moves a tab to the top of another space's regular section.
    @discardableResult
    mutating func moveTab(_ id: UUID, toSpace target: UUID) -> Bool {
        guard let source = spaceOfTab(id), source != target, space(target) != nil,
              let index = spaceIndex(source) else { return false }
        let next = spaces[index].strip.neighborForClose(id)
        guard let removed = spaces[index].strip.remove(id) else { return false }
        if spaces[index].activeTab == id { spaces[index].activeTab = next }
        return openTab(removed.tab, in: target, at: .sectionStart(.unpinned), activate: false) != nil
    }

    /// Moves a whole group and its tabs to another space.
    @discardableResult
    mutating func moveGroup(_ group: UUID, from source: UUID, to target: UUID) -> Bool {
        guard source != target, space(target) != nil, let sourceIndex = spaceIndex(source),
              let taken = spaces[sourceIndex].strip.takeGroup(group) else { return false }
        if let active = spaces[sourceIndex].activeTab, taken.tabs.contains(where: { $0.id == active }) {
            spaces[sourceIndex].activeTab = spaces[sourceIndex].strip.orderedTabIDs.first
        }
        return updateSpace(target) { $0.strip.insertGroup(taken.group, tabs: taken.tabs, section: taken.section) }
    }

    /// Every tab with its owner: favorites first, then spaces in order.
    var allTabs: [(owner: TabOwner, tab: Tab)] {
        favorites.map { (TabOwner.favorite($0.id), $0.tab) } + spaces.flatMap { space in
            space.strip.orderedTabIDs.compactMap { id in space.strip.tab(id).map { (TabOwner.space(space.id), $0) } }
        }
    }

    // MARK: - Favorites

    /// Adds a favorite for a URL; `nil` when it already exists.
    @discardableResult
    mutating func addFavorite(url: String, title: String, favicon: String?) -> UUID? {
        guard !favorites.contains(where: { $0.tab.homeURL == url }) else { return nil }
        var favorite = Favorite(url: url, title: title)
        favorite.tab.faviconURL = favicon
        favorites.append(favorite)
        return favorite.id
    }

    /// Turns a regular tab into a favorite, keeping its page state.
    @discardableResult
    mutating func favoriteFromTab(_ id: UUID) -> UUID? {
        guard let spaceID = spaceOfTab(id), let index = spaceIndex(spaceID) else { return nil }
        let next = spaces[index].strip.neighborForClose(id)
        guard var tab = spaces[index].strip.remove(id)?.tab else { return nil }
        tab.homeURL = tab.url
        let favorite = Favorite(tab: tab)
        // The tab keeps its identity, so it stays active if it was.
        if spaces[index].activeTab != id && spaces[index].activeTab == nil {
            spaces[index].activeTab = next
        }
        favorites.append(favorite)
        return favorite.id
    }

    /// Removes a favorite. Spaces showing it fall back to their first tab.
    mutating func removeFavorite(_ id: UUID) -> Favorite? {
        guard let index = favorites.firstIndex(where: { $0.id == id }) else { return nil }
        let favorite = favorites.remove(at: index)
        for spaceIndex in spaces.indices where spaces[spaceIndex].activeTab == favorite.tab.id {
            spaces[spaceIndex].activeTab = spaces[spaceIndex].strip.orderedTabIDs.first
        }
        return favorite
    }

    @discardableResult
    mutating func moveFavorite(_ id: UUID, to newIndex: Int) -> Bool {
        guard let index = favorites.firstIndex(where: { $0.id == id }) else { return false }
        let favorite = favorites.remove(at: index)
        favorites.insert(favorite, at: max(0, min(newIndex, favorites.count)))
        return true
    }
}

// MARK: - Persistence

nonisolated extension Workspace: Codable {
    private enum CodingKeys: String, CodingKey {
        case spaces, favorites, activeSpace = "active_space", closed
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            spaces: try c.decodeIfPresent([Space].self, forKey: .spaces) ?? [],
            favorites: try c.decodeIfPresent([Favorite].self, forKey: .favorites) ?? [],
            closed: (try? c.decodeIfPresent([ClosedTab].self, forKey: .closed)) ?? []
        )
        if let active = try c.decodeIfPresent(UUID.self, forKey: .activeSpace) {
            restoreActiveSpace(active)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(spaces, forKey: .spaces)
        try c.encode(favorites, forKey: .favorites)
        try c.encode(activeSpaceID, forKey: .activeSpace)
        try c.encode(closedTabs, forKey: .closed)
    }
}

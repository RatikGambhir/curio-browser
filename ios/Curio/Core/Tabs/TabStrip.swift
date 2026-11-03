import Foundation

/// The tabs and groups of one space, in two sections (pinned and regular).
/// Every operation uses identity-based placement, so drag and drop never acts
/// on stale indices. Groups never nest.
nonisolated struct TabStrip: Equatable, Sendable {
    private(set) var tabsByID: [UUID: Tab] = [:]
    private(set) var groupsByID: [UUID: TabGroup] = [:]
    private var pinned: [TabItem] = []
    private var unpinned: [TabItem] = []

    init() {}

    /// Rebuilds a strip from persisted parts, dropping dangling references so
    /// a corrupted file can never produce an inconsistent strip.
    init(tabs: [Tab], groups: [TabGroup], pinned: [TabItem], unpinned: [TabItem]) {
        let tabs = Dictionary(tabs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var groups = Dictionary(groups.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<UUID>()
        for key in groups.keys {
            groups[key]?.tabs.removeAll { !(tabs[$0] != nil && seen.insert($0).inserted) }
        }
        func keep(_ items: [TabItem]) -> [TabItem] {
            var seenGroups = Set<UUID>()
            return items.filter { item in
                switch item {
                case .tab(let id): tabs[id] != nil && seen.insert(id).inserted
                case .group(let id): groups[id] != nil && seenGroups.insert(id).inserted
                }
            }
        }
        let keptPinned = keep(pinned)
        let keptUnpinned = keep(unpinned)
        tabsByID = tabs
        groupsByID = groups
        self.pinned = keptPinned
        self.unpinned = keptUnpinned
        // Tabs that are referenced nowhere are appended so no data is lost.
        let orphans = tabs.values.filter { !seen.contains($0.id) }.sorted { $0.createdAt < $1.createdAt }.map(\.id)
        self.unpinned.append(contentsOf: orphans.map(TabItem.tab))
        let referenced = Set((self.pinned + self.unpinned).compactMap { item -> UUID? in
            if case .group(let id) = item { return id }
            return nil
        })
        self.unpinned.append(contentsOf: groups.keys.filter { !referenced.contains($0) }.map(TabItem.group))
    }

    // MARK: - Lookup

    /// Number of tabs, including grouped ones.
    var count: Int { tabsByID.count }
    var isEmpty: Bool { tabsByID.isEmpty }

    func tab(_ id: UUID) -> Tab? { tabsByID[id] }
    func contains(_ id: UUID) -> Bool { tabsByID[id] != nil }
    func group(_ id: UUID) -> TabGroup? { groupsByID[id] }
    var tabs: [Tab] { Array(tabsByID.values) }
    var groups: [TabGroup] { Array(groupsByID.values) }

    mutating func updateTab(_ id: UUID, _ change: (inout Tab) -> Void) {
        guard var tab = tabsByID[id] else { return }
        change(&tab)
        tabsByID[id] = tab
    }

    /// The items of a section, in order.
    func items(_ section: TabSection) -> [TabItem] {
        section == .pinned ? pinned : unpinned
    }

    private mutating func withItems<R>(_ section: TabSection, _ body: (inout [TabItem]) -> R) -> R {
        switch section {
        case .pinned: body(&pinned)
        case .unpinned: body(&unpinned)
        }
    }

    /// Where a tab currently lives.
    func location(of id: UUID) -> TabLocation? {
        for section in TabSection.allCases {
            for (index, item) in items(section).enumerated() {
                switch item {
                case .tab(let tab) where tab == id:
                    return TabLocation(section: section, group: nil, index: index)
                case .group(let groupID):
                    if let position = groupsByID[groupID]?.tabs.firstIndex(of: id) {
                        return TabLocation(section: section, group: groupID, index: position)
                    }
                default:
                    break
                }
            }
        }
        return nil
    }

    /// The section and index of a group.
    func groupLocation(_ id: UUID) -> (section: TabSection, index: Int)? {
        for section in TabSection.allCases {
            if let index = items(section).firstIndex(of: .group(id)) { return (section, index) }
        }
        return nil
    }

    func isPinned(_ id: UUID) -> Bool { location(of: id)?.section == .pinned }

    // MARK: - Inserting and moving tabs

    /// Inserts a tab. If the placement refers to something that no longer
    /// exists, the tab is appended to the unpinned section instead.
    @discardableResult
    mutating func insert(_ tab: Tab, at placement: TabPlacement) -> UUID {
        tabsByID[tab.id] = tab
        attach(tab.id, placement)
        return tab.id
    }

    private mutating func attach(_ id: UUID, _ placement: TabPlacement) {
        let fallback = TabPlacement.sectionEnd(.unpinned)
        switch placement {
        case .sectionStart(let section):
            withItems(section) { $0.insert(.tab(id), at: 0) }
        case .sectionEnd(let section):
            withItems(section) { $0.append(.tab(id)) }
        case .beforeTab(let anchor), .afterTab(let anchor):
            let after = if case .afterTab = placement { 1 } else { 0 }
            guard let location = location(of: anchor) else { return attach(id, fallback) }
            if let group = location.group {
                groupsByID[group]?.tabs.insert(id, at: location.index + after)
            } else {
                withItems(location.section) { $0.insert(.tab(id), at: location.index + after) }
            }
        case .beforeGroup(let anchor), .afterGroup(let anchor):
            let after = if case .afterGroup = placement { 1 } else { 0 }
            guard let (section, index) = groupLocation(anchor) else { return attach(id, fallback) }
            withItems(section) { $0.insert(.tab(id), at: index + after) }
        case .inGroup(let groupID, let index):
            guard var group = groupsByID[groupID] else { return attach(id, fallback) }
            let position = min(index ?? group.tabs.count, group.tabs.count)
            group.tabs.insert(id, at: position)
            groupsByID[groupID] = group
        }
    }

    /// Detaches a tab without dropping its data, returning where it was.
    private mutating func detach(_ id: UUID) -> TabPlacement? {
        guard let location = location(of: id) else { return nil }
        let restoreAt = restorePlacement(location)
        if let group = location.group {
            groupsByID[group]?.tabs.remove(at: location.index)
        } else {
            withItems(location.section) { _ = $0.remove(at: location.index) }
        }
        return restoreAt
    }

    private func restorePlacement(_ location: TabLocation) -> TabPlacement {
        if let groupID = location.group, let group = groupsByID[groupID] {
            if location.index > 0 { return .afterTab(group.tabs[location.index - 1]) }
            return .inGroup(groupID, 0)
        }
        let items = items(location.section)
        guard location.index > 0 else { return .sectionStart(location.section) }
        switch items[location.index - 1] {
        case .tab(let previous): return .afterTab(previous)
        case .group(let group): return .afterGroup(group)
        }
    }

    /// Removes a tab, returning it with a placement to restore it later.
    mutating func remove(_ id: UUID) -> RemovedTab? {
        guard let restoreAt = detach(id), let tab = tabsByID.removeValue(forKey: id) else { return nil }
        return RemovedTab(tab: tab, restoreAt: restoreAt)
    }

    /// Moves a tab. Moving a tab relative to itself is a no-op.
    @discardableResult
    mutating func move(_ id: UUID, to placement: TabPlacement) -> Bool {
        guard contains(id) else { return false }
        switch placement {
        case .beforeTab(let anchor), .afterTab(let anchor):
            if anchor == id { return false }
        default:
            break
        }
        guard detach(id) != nil else { return false }
        attach(id, placement)
        return true
    }

    /// Pins a tab: moves it out of any group to the end of the pinned section
    /// and remembers its current URL as its home.
    @discardableResult
    mutating func pin(_ id: UUID) -> Bool {
        guard !isPinned(id) else { return false }
        updateTab(id) { $0.homeURL = $0.url }
        return move(id, to: .sectionEnd(.pinned))
    }

    /// Unpins a tab, moving it to the top of the regular section.
    @discardableResult
    mutating func unpin(_ id: UUID) -> Bool {
        guard isPinned(id) else { return false }
        updateTab(id) { $0.homeURL = nil }
        return move(id, to: .sectionStart(.unpinned))
    }

    // MARK: - Groups

    /// Creates a group where the first member is (or at the end of the regular
    /// section) and moves the members into it.
    @discardableResult
    mutating func createGroup(name: String, color: AccentColor, members: [UUID]) -> UUID {
        let group = TabGroup(name: name, color: color)
        let anchor = members.compactMap { location(of: $0) }.first
        let section: TabSection
        let index: Int
        if let anchor {
            section = anchor.section
            if let parent = anchor.group {
                index = groupLocation(parent).map { $0.index + 1 } ?? 0
            } else {
                index = anchor.index
            }
        } else {
            section = .unpinned
            index = unpinned.count
        }
        groupsByID[group.id] = group
        withItems(section) { $0.insert(.group(group.id), at: min(index, $0.count)) }
        for member in members {
            move(member, to: .inGroup(group.id, nil))
        }
        return group.id
    }

    /// Renames a group. Blank names are ignored.
    @discardableResult
    mutating func renameGroup(_ id: UUID, to name: String) -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, groupsByID[id] != nil else { return false }
        groupsByID[id]?.name = name
        return true
    }

    mutating func setGroupColor(_ id: UUID, _ color: AccentColor) {
        groupsByID[id]?.color = color
    }

    mutating func setGroupCollapsed(_ id: UUID, _ collapsed: Bool) {
        groupsByID[id]?.collapsed = collapsed
    }

    /// Deletes a group. With `keepTabs`, its tabs take the group's place;
    /// otherwise they are removed and returned.
    @discardableResult
    mutating func deleteGroup(_ id: UUID, keepTabs: Bool) -> [Tab] {
        guard let (section, index) = groupLocation(id), let group = groupsByID.removeValue(forKey: id) else {
            return []
        }
        withItems(section) { items in
            items.remove(at: index)
            if keepTabs {
                items.insert(contentsOf: group.tabs.map(TabItem.tab), at: index)
            }
        }
        if keepTabs { return [] }
        return group.tabs.compactMap { tabsByID.removeValue(forKey: $0) }
    }

    /// Moves a group to a new top-level position.
    @discardableResult
    mutating func moveGroup(_ id: UUID, to placement: GroupPlacement) -> Bool {
        switch placement {
        case .beforeItem(.group(let other)), .afterItem(.group(let other)):
            if other == id { return false }
        default:
            break
        }
        guard let (section, index) = groupLocation(id) else { return false }
        withItems(section) { _ = $0.remove(at: index) }
        var target = section
        var position: Int? = index
        switch placement {
        case .sectionStart(let s):
            target = s
            position = 0
        case .sectionEnd(let s):
            target = s
            position = nil
        case .beforeItem(let anchor), .afterItem(let anchor):
            let after = if case .afterItem = placement { 1 } else { 0 }
            var found: (TabSection, Int)?
            for s in TabSection.allCases {
                if let i = items(s).firstIndex(of: anchor) {
                    found = (s, i)
                    break
                }
            }
            // Anchoring on a grouped tab means "next to its group".
            if found == nil, case .tab(let tab) = anchor, let group = location(of: tab)?.group,
               let groupPosition = groupLocation(group) {
                found = (groupPosition.section, groupPosition.index)
            }
            if let (s, i) = found {
                target = s
                position = i + after
            }
        }
        withItems(target) { items in
            if let position {
                items.insert(.group(id), at: min(position, items.count))
            } else {
                items.append(.group(id))
            }
        }
        return true
    }

    /// Removes a group and its tabs so they can move to another space.
    mutating func takeGroup(_ id: UUID) -> (group: TabGroup, tabs: [Tab], section: TabSection)? {
        guard let (section, index) = groupLocation(id) else { return nil }
        withItems(section) { _ = $0.remove(at: index) }
        guard let group = groupsByID.removeValue(forKey: id) else { return nil }
        let tabs = group.tabs.compactMap { tabsByID.removeValue(forKey: $0) }
        return (group, tabs, section)
    }

    /// Adds a group with its tabs at the end of `section`.
    @discardableResult
    mutating func insertGroup(_ group: TabGroup, tabs: [Tab], section: TabSection) -> UUID {
        var group = group
        for tab in tabs {
            if !group.tabs.contains(tab.id) { group.tabs.append(tab.id) }
            tabsByID[tab.id] = tab
        }
        group.tabs.removeAll { tabsByID[$0] == nil }
        groupsByID[group.id] = group
        withItems(section) { $0.append(.group(group.id)) }
        return group.id
    }

    // MARK: - Ordering

    /// Every tab id in display order (pinned first, groups expanded).
    var orderedTabIDs: [UUID] {
        TabSection.allCases.flatMap { section in
            items(section).flatMap { item -> [UUID] in
                switch item {
                case .tab(let id): [id]
                case .group(let id): groupsByID[id]?.tabs ?? []
                }
            }
        }
    }

    /// Flattened rows for rendering. Tabs inside collapsed groups are hidden
    /// unless they are `alwaysShow` (the active tab stays visible under its
    /// collapsed folder, as in Arc).
    func rows(alwaysShow: UUID?) -> [TabRow] {
        var rows: [TabRow] = []
        for section in TabSection.allCases {
            for item in items(section) {
                switch item {
                case .tab(let id):
                    rows.append(.tab(id: id, section: section, group: nil))
                case .group(let groupID):
                    guard let group = groupsByID[groupID] else { continue }
                    rows.append(.group(id: groupID, section: section))
                    for tab in group.tabs where !group.collapsed || tab == alwaysShow {
                        rows.append(.tab(id: tab, section: section, group: groupID))
                    }
                }
            }
        }
        return rows
    }

    /// The tab to activate after `closing` closes: the next one in display
    /// order, or the previous one when it was last.
    func neighborForClose(_ closing: UUID) -> UUID? {
        let order = orderedTabIDs
        guard let index = order.firstIndex(of: closing) else { return nil }
        if index + 1 < order.count { return order[index + 1] }
        return index > 0 ? order[index - 1] : nil
    }
}

// MARK: - Persistence

nonisolated extension TabStrip: Codable {
    private enum CodingKeys: String, CodingKey { case tabs, groups, pinned, unpinned }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            tabs: try c.decodeIfPresent([Tab].self, forKey: .tabs) ?? [],
            groups: try c.decodeIfPresent([TabGroup].self, forKey: .groups) ?? [],
            pinned: try c.decodeIfPresent([TabItem].self, forKey: .pinned) ?? [],
            unpinned: try c.decodeIfPresent([TabItem].self, forKey: .unpinned) ?? []
        )
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(orderedTabIDs.compactMap { tabsByID[$0] }, forKey: .tabs)
        try c.encode(Array(groupsByID.values), forKey: .groups)
        try c.encode(pinned, forKey: .pinned)
        try c.encode(unpinned, forKey: .unpinned)
    }
}

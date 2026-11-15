import Foundation

/// The tabs and groups of one space, in two sections (pinned and regular).
/// Every operation uses identity-based placement, so drag and drop never acts
/// on stale indices. Groups never nest.
///
/// Tabs can also be shown together in a `TabSplit` (split view). A split's
/// tabs always sit next to each other, in pane order, in one container (the
/// pinned section, the regular section or one folder), and moving any of
/// them moves the whole split, so a split lives in exactly one place.
nonisolated struct TabStrip: Equatable, Sendable {
    private(set) var tabsByID: [UUID: Tab] = [:]
    private(set) var groupsByID: [UUID: TabGroup] = [:]
    private var pinned: [TabItem] = []
    private var unpinned: [TabItem] = []
    private(set) var splitsByID: [UUID: TabSplit] = [:]

    init() {}

    /// Rebuilds a strip from persisted parts, dropping dangling references so
    /// a corrupted file can never produce an inconsistent strip.
    init(tabs: [Tab], groups: [TabGroup], pinned: [TabItem], unpinned: [TabItem], splits: [TabSplit] = []) {
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
        // Older sessions may have saved the new tab page as a tab's home.
        for tab in tabs.values where tab.homeURL == Curio.newTabURL {
            syncHome(tab.id)
        }
        splitsByID = Dictionary(splits.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        repairSplits()
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

    /// Whether a tab is kept when closed: pinned tabs and tabs in a folder.
    /// Closing a saved tab unloads it and resets it to its home URL.
    func isSaved(_ id: UUID) -> Bool {
        guard let location = location(of: id) else { return false }
        return location.section == .pinned || location.group != nil
    }

    /// Where a new tab opened from `anchor` goes: right after it when it's a
    /// regular tab, right after its folder when it's in a regular folder, and
    /// at the top of the regular section otherwise. New tabs never land inside
    /// a folder or in the pinned section.
    func placementForNewTab(anchor: UUID?) -> TabPlacement {
        // A tab opened from a split goes after the whole split.
        let anchor = anchor.map { split(of: $0)?.tabs.last ?? $0 }
        guard let anchor, let location = location(of: anchor), location.section == .unpinned else {
            return .sectionStart(.unpinned)
        }
        if let group = location.group { return .afterGroup(group) }
        return .afterTab(anchor)
    }

    /// Updates a tab's current URL. A saved tab without a home (one that was
    /// showing the new tab page) takes its first real page as its home.
    @discardableResult
    mutating func setTabURL(_ id: UUID, _ url: String) -> Bool {
        guard let tab = tabsByID[id], tab.url != url else { return false }
        tabsByID[id]?.url = url
        if tab.homeURL == nil { syncHome(id) }
        return true
    }

    /// Saved tabs remember their first page, skipping the new tab page. A tab
    /// that leaves the pinned section and every folder forgets its home.
    private mutating func syncHome(_ id: UUID) {
        let saved = isSaved(id)
        guard var tab = tabsByID[id] else { return }
        if !saved || tab.homeURL == Curio.newTabURL { tab.homeURL = nil }
        if saved && tab.homeURL == nil && !tab.isNewTabPage && !tab.url.isEmpty { tab.homeURL = tab.url }
        tabsByID[id] = tab
    }

    // MARK: - Inserting and moving tabs

    /// Inserts a tab. If the placement refers to something that no longer
    /// exists, the tab is appended to the unpinned section instead.
    @discardableResult
    mutating func insert(_ tab: Tab, at placement: TabPlacement) -> UUID {
        tabsByID[tab.id] = tab
        attach(tab.id, placement)
        syncHome(tab.id)
        repairSplits()
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
        repairSplits()
        return RemovedTab(tab: tab, restoreAt: restoreAt)
    }

    /// Moves a tab. Moving a tab relative to itself is a no-op.
    ///
    /// Moving a tab that is part of a split moves the whole split: its first
    /// pane goes to `placement` and the others follow it.
    @discardableResult
    mutating func move(_ id: UUID, to placement: TabPlacement) -> Bool {
        guard contains(id) else { return false }
        let members = split(of: id)?.tabs ?? [id]
        let id = members[0]
        switch placement {
        case .beforeTab(let anchor), .afterTab(let anchor):
            if members.contains(anchor) { return false }
        default:
            break
        }
        guard detach(id) != nil else { return false }
        attach(id, placement)
        syncHome(id)
        repairSplits()
        return true
    }

    /// Pins a tab: moves it out of any group to the end of the pinned section
    /// and remembers its current URL as its home (a blank tab gets its home on
    /// its first navigation).
    @discardableResult
    mutating func pin(_ id: UUID) -> Bool {
        guard !isPinned(id) else { return false }
        updateTab(id) { tab in
            if !tab.isNewTabPage && !tab.url.isEmpty { tab.homeURL = tab.url }
        }
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
    /// section) and moves the members into it. A group may be empty, and stays
    /// until it is deleted.
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
        if keepTabs {
            for tab in group.tabs { syncHome(tab) }
            return []
        }
        let removed = group.tabs.compactMap { tabsByID.removeValue(forKey: $0) }
        repairSplits()
        return removed
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
        // A folder dropped next to a split's inner tab would separate it.
        repairSplits()
        return true
    }

    /// Removes a group with its tabs and the splits among them, so they can
    /// move to another space.
    mutating func takeGroup(_ id: UUID) -> TakenGroup? {
        guard let (section, index) = groupLocation(id) else { return nil }
        withItems(section) { _ = $0.remove(at: index) }
        guard let group = groupsByID.removeValue(forKey: id) else { return nil }
        let tabs = group.tabs.compactMap { tabsByID.removeValue(forKey: $0) }
        let inside = splitsByID.values.filter { split in split.tabs.contains { group.tabs.contains($0) } }.map(\.id)
        let splits = inside.compactMap { splitsByID.removeValue(forKey: $0) }
        repairSplits()
        return TakenGroup(group: group, tabs: tabs, splits: splits, section: section)
    }

    /// Adds a group (with its tabs and splits) at the end of its section.
    @discardableResult
    mutating func insertGroup(_ taken: TakenGroup) -> UUID {
        var group = taken.group
        for tab in taken.tabs {
            if !group.tabs.contains(tab.id) { group.tabs.append(tab.id) }
            tabsByID[tab.id] = tab
        }
        group.tabs.removeAll { tabsByID[$0] == nil }
        groupsByID[group.id] = group
        withItems(taken.section) { $0.append(.group(group.id)) }
        for split in taken.splits { splitsByID[split.id] = split }
        repairSplits()
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
    ///
    /// With `showingSplits`, a split is one `.split` row where its first tab
    /// would be, and its other tabs get no row of their own. Without it (the
    /// single-page layout), every pane is listed as an ordinary tab.
    func rows(alwaysShow: UUID?, showingSplits: Bool = true) -> [TabRow] {
        var rows: [TabRow] = []
        // The split the always-shown tab belongs to stays visible with it.
        let alwaysSplit = alwaysShow.flatMap { split(of: $0)?.id }
        func row(_ id: UUID, _ section: TabSection, _ group: UUID?) -> TabRow? {
            guard showingSplits, let split = split(of: id) else { return .tab(id: id, section: section, group: group) }
            return split.tabs.first == id ? .split(id: split.id, section: section, group: group) : nil
        }
        for section in TabSection.allCases {
            for item in items(section) {
                switch item {
                case .tab(let id):
                    if let row = row(id, section, nil) { rows.append(row) }
                case .group(let groupID):
                    guard let group = groupsByID[groupID] else { continue }
                    rows.append(.group(id: groupID, section: section))
                    for tab in group.tabs {
                        let shown = !group.collapsed || tab == alwaysShow
                            || (alwaysSplit != nil && split(of: tab)?.id == alwaysSplit)
                        if shown, let row = row(tab, section, groupID) { rows.append(row) }
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

    // MARK: - Split view

    /// Every split, in no particular order.
    var splits: [TabSplit] { Array(splitsByID.values) }

    func split(_ id: UUID) -> TabSplit? { splitsByID[id] }

    /// The split a tab is shown in, if any.
    func split(of tab: UUID) -> TabSplit? {
        // Splits are few (a handful per space), so a scan beats keeping a
        // reverse index in sync.
        splitsByID.values.first { $0.contains(tab) }
    }

    /// Shows `tabs` side by side. They are taken out of any split they were
    /// in and gathered next to the first of them, in its section or folder.
    /// Tabs the strip doesn't own are ignored; returns `nil` unless at least
    /// two remain.
    @discardableResult
    mutating func createSplit(_ tabs: [UUID], orientation: SplitOrientation = .horizontal) -> UUID? {
        let split = TabSplit(tabs: tabs.filter { contains($0) }, orientation: orientation)
        guard split.isValid else { return nil }
        for tab in split.tabs { detachFromSplit(tab) }
        splitsByID[split.id] = split
        repairSplits()
        return split.id
    }

    /// Takes in a split made elsewhere (another space), keeping its id,
    /// orientation and pane sizes. Its tabs must already be in this strip.
    @discardableResult
    mutating func adoptSplit(_ split: TabSplit) -> UUID? {
        var split = split
        split.tabs.removeAll { !contains($0) }
        split.normalize()
        guard split.isValid else { return nil }
        for tab in split.tabs { detachFromSplit(tab) }
        splitsByID[split.id] = split
        repairSplits()
        return splitsByID[split.id]?.id
    }

    /// Adds `tab` to a split as the pane at `index` (clamped to the end).
    /// The tab leaves any other split and moves next to the split's other
    /// tabs.
    @discardableResult
    mutating func addToSplit(_ id: UUID, tab: UUID, at index: Int) -> Bool {
        guard contains(tab), let split = splitsByID[id], !split.isFull, !split.contains(tab) else { return false }
        detachFromSplit(tab)
        let added = splitsByID[id]?.addTab(tab, at: index) ?? false
        repairSplits()
        return added
    }

    /// Takes a tab out of its split and puts it right after the split. A
    /// split left with one tab is dissolved.
    @discardableResult
    mutating func removeFromSplit(_ tab: UUID) -> Bool {
        guard let last = detachFromSplit(tab) else { return false }
        if last != tab { move(tab, to: .afterTab(last)) }
        repairSplits()
        return true
    }

    /// Dissolves a split; its tabs stay where they are as ordinary tabs.
    @discardableResult
    mutating func dissolveSplit(_ id: UUID) -> Bool {
        splitsByID.removeValue(forKey: id) != nil
    }

    /// Moves the divider after pane `divider` (see `TabSplit.resize`).
    @discardableResult
    mutating func resizeSplit(_ id: UUID, divider: Int, by delta: Double) -> Bool {
        splitsByID[id]?.resize(divider: divider, by: delta) ?? false
    }

    /// Gives every pane of a split the same room.
    @discardableResult
    mutating func equalizeSplit(_ id: UUID) -> Bool {
        guard splitsByID[id] != nil else { return false }
        splitsByID[id]?.equalize()
        return true
    }

    /// Switches a split between side by side and stacked.
    @discardableResult
    mutating func flipSplit(_ id: UUID) -> Bool {
        guard let split = splitsByID[id] else { return false }
        splitsByID[id]?.orientation = split.orientation.flipped
        return true
    }

    /// Takes a tab out of its split without moving it. Returns the split's
    /// last remaining pane (or the tab itself when the split dissolved).
    @discardableResult
    private mutating func detachFromSplit(_ tab: UUID) -> UUID? {
        guard let id = split(of: tab)?.id, var split = splitsByID[id] else { return nil }
        split.removeTab(tab)
        if split.isValid {
            splitsByID[id] = split
            return split.tabs.last
        }
        splitsByID.removeValue(forKey: id)
        return split.tabs.last ?? tab
    }

    /// Keeps every split consistent with the strip: drops panes whose tabs
    /// are gone (and splits left too small), a tab in two splits stays in the
    /// first (by id order), and each split's tabs are gathered after its
    /// first pane, in pane order, in the same section or folder.
    private mutating func repairSplits() {
        guard !splitsByID.isEmpty else { return }
        let ids = splitsByID.keys.sorted { $0.uuidString < $1.uuidString }
        var seen = Set<UUID>()
        for id in ids {
            guard var split = splitsByID[id] else { continue }
            let before = split.tabs.count
            split.tabs.removeAll { !(tabsByID[$0] != nil && seen.insert($0).inserted) }
            if split.tabs.count != before { split.equalize() } else { split.normalize() }
            splitsByID[id] = split.isValid ? split : nil
        }
        for id in ids {
            guard let members = splitsByID[id]?.tabs, !isContiguous(members) else { continue }
            for (previous, tab) in zip(members, members.dropFirst()) {
                guard detach(tab) != nil else { continue }
                attach(tab, .afterTab(previous))
                syncHome(tab)
            }
        }
    }

    /// Whether `members` sit next to each other, in order, in one container.
    private func isContiguous(_ members: [UUID]) -> Bool {
        guard let first = members.first.flatMap(location(of:)) else { return false }
        return members.enumerated().dropFirst().allSatisfy { offset, tab in
            guard let location = location(of: tab) else { return false }
            return location.section == first.section && location.group == first.group && location.index == first.index + offset
        }
    }
}

/// A group taken out of a strip with everything needed to put it in another
/// one: its tabs and the splits among them.
nonisolated struct TakenGroup: Equatable, Sendable {
    var group: TabGroup
    var tabs: [Tab]
    var splits: [TabSplit]
    var section: TabSection
}

// MARK: - Persistence

nonisolated extension TabStrip: Codable {
    private enum CodingKeys: String, CodingKey { case tabs, groups, pinned, unpinned, splits }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            tabs: try c.decodeIfPresent([Tab].self, forKey: .tabs) ?? [],
            groups: try c.decodeIfPresent([TabGroup].self, forKey: .groups) ?? [],
            pinned: try c.decodeIfPresent([TabItem].self, forKey: .pinned) ?? [],
            unpinned: try c.decodeIfPresent([TabItem].self, forKey: .unpinned) ?? [],
            // Older sessions have no splits; a damaged list loads as none.
            splits: (try? c.decodeIfPresent([TabSplit].self, forKey: .splits)) ?? []
        )
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(orderedTabIDs.compactMap { tabsByID[$0] }, forKey: .tabs)
        try c.encode(Array(groupsByID.values), forKey: .groups)
        try c.encode(pinned, forKey: .pinned)
        try c.encode(unpinned, forKey: .unpinned)
        try c.encode(splitsByID.values.sorted { $0.id.uuidString < $1.id.uuidString }, forKey: .splits)
    }
}

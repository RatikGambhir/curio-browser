import UIKit

/// The browser's model and coordinator: owns the workspace (spaces, tabs,
/// favorites), the live `BrowserTab`s for tabs that have been shown, saving,
/// sleeping and history. View controllers call into it and redraw on
/// `SessionChange`s.
final class BrowserSession {
    let services: AppServices
    let engine = WebEngine()
    weak var delegate: BrowserSessionDelegate?

    private(set) var workspace: Workspace
    private(set) var liveTabs: [UUID: BrowserTab] = [:]
    private var saveTask: Task<Void, Never>?
    private var maintenanceTask: Task<Void, Never>?
    private var appearance: UIUserInterfaceStyle = .unspecified
    /// The room the page area has for split views; set by the browser
    /// screen as its layout changes.
    private(set) var splitRoom: SplitRoom = .none
    /// The last close-button unload, so a double tap doesn't also archive.
    private var lastUnload: (id: UUID, time: ContinuousClock.Instant)?

    init(services: AppServices) {
        self.services = services
        let restored = services.settings.settings.browsing.restoreSession ? services.workspaceStore.load() : nil
        workspace = restored ?? .firstRun()
        if restored == nil, let saved = services.workspaceStore.load() {
            // Not restoring tabs still keeps spaces, saved tabs (pinned and in
            // folders), folders and favorites.
            workspace = Self.withoutRegularTabs(saved)
        }
        maintenanceTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                self?.putIdleTabsToSleep()
            }
        }
    }

    deinit {
        maintenanceTask?.cancel()
        saveTask?.cancel()
    }

    var settings: Settings { services.settings.settings }

    private static func withoutRegularTabs(_ saved: Workspace) -> Workspace {
        var workspace = saved
        for space in saved.spaces {
            for case .tab(let id) in space.strip.items(.unpinned) {
                _ = workspace.closeTab(id)
            }
            workspace.updateSpace(space.id) { $0.activeTab = $0.strip.orderedTabIDs.first }
        }
        return Workspace(spaces: workspace.spaces, favorites: workspace.favorites)
    }

    // MARK: - Reading state

    var activeTabID: UUID? { workspace.activeTabID }
    var activeTab: Tab? { workspace.activeTab }
    var activeLiveTab: BrowserTab? { activeTabID.flatMap { liveTabs[$0] } }

    func tabViewModel(_ id: UUID) -> TabViewModel? {
        guard let tab = workspace.tab(id) else { return nil }
        let live = liveTabs[id]
        return TabViewModel(
            id: id,
            title: tab.displayTitle,
            favicon: tab.faviconURL,
            active: workspace.activeTabID == id,
            pinned: workspace.activeSpace.strip.isPinned(id),
            saved: isSaved(id),
            loading: live?.state.loading ?? false,
            asleep: !(live?.isAwake ?? false)
        )
    }

    var pageNav: PageNav {
        let state = activeLiveTab?.state
        let page = activeTab.flatMap { tab -> PageNav.PageInfo? in
            tab.isNewTabPage ? nil : .init(url: tab.url, host: Curio.displayHost(tab.url), title: tab.displayTitle)
        }
        return PageNav(
            canGoBack: state?.canGoBack ?? false,
            canGoForward: state?.canGoForward ?? false,
            loading: state?.loading ?? false,
            secure: (state?.secure ?? false) || page?.url.hasPrefix("https:") == true,
            zoom: state?.zoom ?? 1,
            page: page
        )
    }

    /// Open tabs for the command bar's "Switch to Tab".
    var tabSuggestions: [TabSuggestion] {
        workspace.allTabs.filter { !$0.tab.isNewTabPage }.map { owner, tab in
            let space: String = switch owner {
            case .favorite: "Favorites"
            case .space(let id): workspace.space(id)?.name ?? ""
            }
            return TabSuggestion(id: tab.id, title: tab.displayTitle, url: tab.url, favicon: tab.faviconURL, space: space)
        }
    }

    /// Favorites, then the active space's tabs, in display order.
    var visibleTabOrder: [UUID] {
        workspace.favorites.map(\.tab.id) + workspace.activeSpace.strip.orderedTabIDs
    }

    /// Pages offered on the new tab page, most visited first.
    func topSites(limit: Int) -> [HistoryEntry] {
        var seen = Set<String>()
        return services.history.search("", limit: 40).filter {
            $0.url.hasPrefix("http") && seen.insert(Curio.displayHost($0.url)).inserted
        }.prefix(limit).map(\.self)
    }

    // MARK: - Live tabs

    /// The live tab for `id`, created (without a web view) if needed.
    @discardableResult
    func ensureLiveTab(_ id: UUID) -> BrowserTab? {
        if let live = liveTabs[id] { return live }
        guard let tab = workspace.tab(id) else { return nil }
        let live = BrowserTab(id: id, url: tab.url, title: tab.title, favicon: tab.faviconURL, scrollY: tab.scrollY, engine: engine)
        live.delegate = self
        live.setAppearance(appearance)
        liveTabs[id] = live
        return live
    }

    private func releaseTab(_ id: UUID) {
        liveTabs.removeValue(forKey: id)?.sleep()
    }

    func setAppearance(_ style: UIUserInterfaceStyle) {
        appearance = style
        for tab in liveTabs.values { tab.setAppearance(style) }
    }

    /// Makes the visible tabs (the active tab, or every pane of its split
    /// view) visible, creating their web views on demand, and every other
    /// tab hidden. Visible tabs never sleep.
    func syncActiveTab() {
        let visible = visibleTabIDs
        for (id, live) in liveTabs where !visible.contains(id) && live.isActive {
            live.setActive(false)
        }
        for id in visible {
            if let live = ensureLiveTab(id), !live.isActive { live.setActive(true) }
        }
        // Only unfocused panes report presses in their page (to take the focus).
        let active = workspace.activeTabID
        for (id, live) in liveTabs {
            live.setReportsFocus(visible.count > 1 && id != active && visible.contains(id))
        }
        delegate?.session(self, didChange: .activeTab)
        delegate?.session(self, didChange: .tabs)
    }

    // MARK: - Tabs

    func activateTab(_ id: UUID) {
        let previous = workspace.activeSpaceID
        guard workspace.activateTab(id) else { return }
        if workspace.activeSpaceID != previous { spaceChanged(from: previous) }
        syncActiveTab()
        scheduleSave()
    }

    /// Opens `url` in a new tab near `after` (the active tab by default):
    /// right after a regular tab, right below a folder, or at the top of the
    /// regular tabs. New tabs never open inside a folder.
    @discardableResult
    func openInNewTab(_ url: String, after: UUID? = nil, activate: Bool = true) -> UUID {
        let tab = Tab(url: url)
        let anchor = after ?? workspace.activeTabID
        let space = anchor.flatMap(workspace.spaceOfTab) ?? workspace.activeSpaceID
        let placement = workspace.space(space)?.strip.placementForNewTab(anchor: anchor) ?? .sectionStart(.unpinned)
        workspace.openTab(tab, in: space, at: placement, activate: false)
        if activate {
            activateTab(tab.id)
        } else {
            // Background tabs start loading right away, hidden.
            ensureLiveTab(tab.id)?.navigate(to: url)
            delegate?.session(self, didChange: .tabs)
            scheduleSave()
        }
        return tab.id
    }

    /// Navigates the active tab, or opens a tab when there is none.
    func navigateActive(_ url: String) {
        guard let id = workspace.activeTabID else {
            openInNewTab(url)
            return
        }
        workspace.setTabURL(id, url)
        workspace.updateTab(id) {
            $0.title = ""
            $0.faviconURL = nil
            $0.scrollY = 0
        }
        if let live = ensureLiveTab(id) {
            live.navigate(to: url)
            if !live.isActive { live.setActive(true) }
        }
        delegate?.session(self, didChange: .activeTab)
        delegate?.session(self, didChange: .tabs)
        scheduleSave()
    }

    /// Opens a page from a command bar result: the new tab page is reused,
    /// otherwise `newTab` decides.
    func open(_ url: String, newTab: Bool) {
        let reuse = activeTab?.isNewTabPage ?? false
        if newTab && !reuse {
            openInNewTab(url, after: activeTabID)
        } else {
            navigateActive(url)
        }
    }

    /// Whether a tab is kept when closed: pinned or in a folder.
    func isSaved(_ id: UUID) -> Bool {
        workspace.spaceOfTab(id).flatMap(workspace.space)?.strip.isSaved(id) ?? false
    }

    /// Closes a tab for good (it goes to Archived Tabs). Favorites are put to
    /// sleep and hidden instead.
    func closeTab(_ id: UUID) {
        switch workspace.findTab(id)?.owner {
        case .favorite:
            if workspace.activeTabID == id {
                workspace.updateActiveSpace { $0.activeTab = $0.strip.orderedTabIDs.first }
            }
            releaseTab(id)
        case .space:
            if workspace.closeTab(id) != nil { releaseTab(id) }
        case nil:
            return
        }
        syncActiveTab()
        scheduleSave()
    }

    /// Saved tabs (pinned or in a folder) are kept; "closing" them releases
    /// the page and resets the tab to its home URL instead. A pane leaves its
    /// split first (showing the split would load it again), and the pane
    /// beside it takes the focus.
    func unloadTab(_ id: UUID) {
        var beside: UUID?
        if let spaceID = workspace.spaceOfTab(id), let split = workspace.space(spaceID)?.strip.split(of: id) {
            beside = Workspace.paneBeside(id, in: split)
            workspace.updateSpace(spaceID) { $0.strip.removeFromSplit(id) }
        }
        // Release first: sleeping reports the page's last URL one more time,
        // which would otherwise overwrite the reset to home.
        releaseTab(id)
        if let home = workspace.tab(id)?.homeURL {
            workspace.updateTab(id) {
                $0.url = home
                $0.scrollY = 0
            }
        }
        if workspace.activeTabID == id {
            workspace.updateActiveSpace { space in
                space.activeTab = beside ?? space.strip.orderedTabIDs.first { $0 != id }
            }
        }
        syncActiveTab()
        scheduleSave()
    }

    /// Close Tab and ⌘W: unloads saved tabs, closes the rest.
    func closeOrUnloadTab(_ id: UUID) {
        if isSaved(id) { unloadTab(id) } else { closeTab(id) }
    }

    /// A tab row's close button: unloads a saved tab whose page is live, and
    /// otherwise closes the tab into Archived Tabs.
    func unloadOrArchiveTab(_ id: UUID) {
        let now = ContinuousClock.now
        if isSaved(id) && liveTabs[id]?.isAwake == true {
            lastUnload = (id, now)
            unloadTab(id)
        } else if isSaved(id), let last = lastUnload, last.id == id, now - last.time < .milliseconds(500) {
            // The second tap of a double tap on − lands on the × that replaced
            // it; archiving the tab would be a surprise.
            return
        } else {
            closeTab(id)
        }
    }

    func closeActiveTab() {
        if let id = activeTabID { closeOrUnloadTab(id) }
    }

    func reopenClosedTab() {
        let previous = workspace.activeSpaceID
        guard workspace.reopenClosedTab() != nil else { return }
        if workspace.activeSpaceID != previous { spaceChanged(from: previous) }
        syncActiveTab()
        scheduleSave()
    }

    func reopenArchivedTab(_ id: UUID) {
        let previous = workspace.activeSpaceID
        guard workspace.reopenClosed(id) != nil else { return }
        if workspace.activeSpaceID != previous { spaceChanged(from: previous) }
        syncActiveTab()
        scheduleSave()
    }

    func duplicateTab(_ id: UUID) {
        guard workspace.duplicateTab(id) != nil else { return }
        syncActiveTab()
        scheduleSave()
    }

    func togglePin(_ id: UUID) {
        guard let space = workspace.spaceOfTab(id) else { return }
        workspace.updateSpace(space) { space in
            if space.strip.isPinned(id) { space.strip.unpin(id) } else { space.strip.pin(id) }
        }
        changedTabs()
    }

    func addFavorite(_ id: UUID) {
        guard case .space = workspace.findTab(id)?.owner, workspace.tab(id)?.isNewTabPage == false else { return }
        if workspace.favoriteFromTab(id) != nil {
            delegate?.session(self, showToast: "Added to Favorites", title: nil, kind: .success)
            changedTabs()
        }
    }

    func removeFavorite(_ id: UUID) {
        guard let favorite = workspace.removeFavorite(id) else { return }
        releaseTab(favorite.tab.id)
        syncActiveTab()
        scheduleSave()
    }

    /// Returns a favorite to its saved address.
    func resetFavorite(_ tabID: UUID) {
        guard let home = workspace.tab(tabID)?.homeURL else { return }
        activateTab(tabID)
        navigateActive(home)
    }

    /// Moves a tab (sidebar drag and drop), across spaces if needed.
    func dropTab(_ id: UUID, at placement: TabPlacement) {
        let target = workspace.activeSpaceID
        switch workspace.findTab(id)?.owner {
        case .space(let space) where space == target:
            workspace.updateSpace(space) { $0.strip.move(id, to: placement) }
        case .space:
            moveTabToSpace(id, target)
            workspace.updateSpace(target) { $0.strip.move(id, to: placement) }
        default:
            return
        }
        changedTabs()
    }

    func dropGroup(_ id: UUID, at placement: GroupPlacement) {
        let space = workspace.activeSpaceID
        guard workspace.space(space)?.strip.group(id) != nil else { return }
        workspace.updateSpace(space) { $0.strip.moveGroup(id, to: placement) }
        changedTabs()
    }

    func moveTabToSpace(_ id: UUID, _ space: UUID) {
        if workspace.moveTab(id, toSpace: space) {
            syncActiveTab()
            scheduleSave()
        }
    }

    func moveGroupToSpace(_ group: UUID, from: UUID, to: UUID) {
        if workspace.moveGroup(group, from: from, to: to) {
            syncActiveTab()
            scheduleSave()
        }
    }

    func setGroupCollapsed(_ group: UUID, _ collapsed: Bool) {
        workspace.updateActiveSpace { $0.strip.setGroupCollapsed(group, collapsed) }
        changedTabs()
    }

    /// Creates a "New Folder" around `members` and returns it.
    func newGroup(with members: [UUID]) -> UUID? {
        guard let first = members.first, let spaceID = workspace.spaceOfTab(first),
              let space = workspace.space(spaceID) else { return nil }
        let color = Self.nextFolderColor(space)
        var group: UUID?
        workspace.updateSpace(spaceID) { group = $0.strip.createGroup(name: Self.newFolderName, color: color, members: members) }
        changedTabs()
        return group
    }

    /// Creates an empty "New Folder" at the top of the active space's
    /// regular tabs and returns it.
    @discardableResult
    func newFolder() -> UUID {
        let color = Self.nextFolderColor(workspace.activeSpace)
        var group = UUID()
        workspace.updateActiveSpace { space in
            group = space.strip.createGroup(name: Self.newFolderName, color: color, members: [])
            space.strip.moveGroup(group, to: .sectionStart(.unpinned))
        }
        changedTabs()
        return group
    }

    private static let newFolderName = "New Folder"

    /// Cycles through the accent colors so neighboring folders differ.
    private static func nextFolderColor(_ space: Space) -> AccentColor {
        AccentColor.allCases[(space.strip.groups.count + 1) % AccentColor.allCases.count]
    }

    func renameGroup(_ group: UUID, to name: String) {
        workspace.updateActiveSpace { $0.strip.renameGroup(group, to: name) }
        changedTabs()
    }

    func setGroupColor(_ group: UUID, _ color: AccentColor) {
        workspace.updateActiveSpace { $0.strip.setGroupColor(group, color) }
        changedTabs()
    }

    /// Dissolves a group, keeping its tabs in place.
    func ungroup(_ group: UUID) {
        workspace.updateActiveSpace { $0.strip.deleteGroup(group, keepTabs: true) }
        changedTabs()
    }

    /// Deletes a group together with its tabs.
    func closeGroup(_ group: UUID) {
        var closed: [Tab] = []
        workspace.updateActiveSpace { space in
            closed = space.strip.deleteGroup(group, keepTabs: false)
            if let active = space.activeTab, !space.strip.contains(active), !workspace.favorites.contains(where: { $0.tab.id == active }) {
                space.activeTab = space.strip.orderedTabIDs.first
            }
        }
        closed.forEach { releaseTab($0.id) }
        syncActiveTab()
        scheduleSave()
    }

    /// Takes a tab out of its group, placing it right after the group.
    func removeFromGroup(_ id: UUID) {
        if let group = workspace.activeSpace.strip.location(of: id)?.group {
            dropTab(id, at: .afterGroup(group))
        }
    }

    /// Closes every top-level regular tab of the active space except `keep`.
    func closeOtherTabs(keeping keep: UUID) {
        let others = workspace.activeSpace.strip.items(.unpinned).compactMap { item -> UUID? in
            if case .tab(let id) = item, id != keep { return id }
            return nil
        }
        others.forEach(closeTab)
    }

    func selectTab(at index: Int?) {
        let order = visibleTabOrder
        let target = index.map { order.indices.contains($0) ? order[$0] : nil } ?? order.last
        if let target { activateTab(target) }
    }

    func cycleTab(forward: Bool) {
        let order = visibleTabOrder
        guard !order.isEmpty else { return }
        let current = activeTabID.flatMap { order.firstIndex(of: $0) }
        let next = switch current {
        case .some(let i): forward ? (i + 1) % order.count : (i + order.count - 1) % order.count
        case .none: 0
        }
        activateTab(order[next])
    }

    private func changedTabs() {
        delegate?.session(self, didChange: .tabs)
        scheduleSave()
    }

    // MARK: - Split view

    /// What Split View did.
    enum SplitResult {
        /// A new pane was added and focused; its page is chosen next.
        case added
        /// There is no tab to split with; open a new tab instead.
        case noActiveTab
        /// Refused (the reason was shown) or not available.
        case refused
    }

    static let splitFullMessage = "A split view shows up to \(TabSplit.maxPanes) tabs"
    static let splitFavoriteMessage = "Favorites can’t be shown in a split view"

    /// Reports the page area's room for split views. Showing or hiding a
    /// split when it starts or stops fitting.
    func setSplitRoom(_ room: SplitRoom) {
        guard room != splitRoom else { return }
        let before = (visibleTabIDs, splitRoom.available)
        splitRoom = room
        if visibleTabIDs != before.0 {
            syncActiveTab()
        } else if room.available != before.1 {
            delegate?.session(self, didChange: .tabs)
        }
    }

    /// Whether Split View is offered right now.
    var splitAvailable: Bool { splitRoom.available }

    /// The split of the active tab in the active space, if any.
    var activeSplit: TabSplit? {
        activeTabID.flatMap { workspace.activeSpace.strip.split(of: $0) }
    }

    /// The split on screen: the active tab's, while all its panes fit.
    var visibleSplit: TabSplit? {
        activeSplit.flatMap { splitRoom.fits($0) ? $0 : nil }
    }

    /// The tabs whose pages are on screen: the active tab, or every pane of
    /// its split view.
    var visibleTabIDs: [UUID] {
        if let split = visibleSplit { return split.tabs }
        return activeTabID.map { [$0] } ?? []
    }

    func split(of tab: UUID) -> TabSplit? {
        workspace.spaceOfTab(tab).flatMap(workspace.space)?.strip.split(of: tab)
    }

    /// Split View: adds a new tab beside the active tab (or as another pane
    /// of its split) and focuses it, so its page can be chosen.
    func splitView() -> SplitResult {
        guard splitAvailable else { return .refused }
        guard let active = activeTabID else { return .noActiveTab }
        guard let spaceID = workspace.spaceOfTab(active), let strip = workspace.space(spaceID)?.strip else {
            delegate?.session(self, showToast: Self.splitFavoriteMessage, title: nil, kind: .info)
            return .refused
        }
        let existing = strip.split(of: active)
        guard canGrowSplit(existing) else { return .refused }
        let pane = Tab()
        workspace.updateSpace(spaceID) { space in
            space.strip.insert(pane, at: .afterTab(active))
            if let existing, let index = existing.tabs.firstIndex(of: active) {
                space.strip.addToSplit(existing.id, tab: pane.id, at: index + 1)
            } else {
                space.strip.createSplit([active, pane.id])
            }
        }
        activateTab(pane.id)
        return .added
    }

    /// Whether `split` (or a new split, for `nil`) can take one more pane:
    /// under the pane limit and with room for every pane in its orientation.
    /// Shows why when it can't.
    private func canGrowSplit(_ split: TabSplit?) -> Bool {
        let panes = (split?.tabs.count ?? 1) + 1
        if panes > TabSplit.maxPanes {
            delegate?.session(self, showToast: Self.splitFullMessage, title: nil, kind: .info)
            return false
        }
        guard splitRoom.fits(panes: panes, orientation: split?.orientation ?? .horizontal) else {
            delegate?.session(self, showToast: Self.splitRoomMessage, title: nil, kind: .info)
            return false
        }
        return true
    }

    static let splitRoomMessage = "There isn’t room for another pane here"

    /// Drops a pane that Split View added if its page was never chosen (it
    /// still shows the new tab page). It doesn't go to Archived Tabs.
    func discardBlankPane(_ id: UUID) {
        guard workspace.tab(id)?.isNewTabPage == true, workspace.closeTab(id, remember: false) != nil else { return }
        releaseTab(id)
        syncActiveTab()
        scheduleSave()
    }

    /// Shows `tab` beside the active tab: before or after it, in a new split
    /// or as another pane of the active tab's split, and `tab` takes the
    /// focus. The split stays where the active tab is (its space and
    /// folder), except that a pinned or folder tab is never turned into a
    /// regular tab: when only `tab` is saved, the split moves to it instead.
    func splitWith(_ tab: UUID, before: Bool) {
        guard let active = activeTabID, active != tab else { return }
        guard let spaceID = workspace.spaceOfTab(active), splitAvailable,
              let strip = workspace.space(spaceID)?.strip else {
            // The active tab is a favorite: just show the tab.
            activateTab(tab)
            return
        }
        guard let tabSpace = workspace.spaceOfTab(tab) else {
            delegate?.session(self, showToast: Self.splitFavoriteMessage, title: nil, kind: .info)
            return
        }
        let existing = strip.split(of: active)
        if existing?.contains(tab) == true {
            activateTab(tab)
            return
        }
        // Check before changing anything, so a refusal leaves every tab put.
        guard canGrowSplit(existing) else { return }
        if tabSpace != spaceID { workspace.moveTab(tab, toSpace: spaceID) }
        workspace.updateSpace(spaceID) { space in
            space.strip.removeFromSplit(tab)
            let toTab = space.strip.isSaved(tab) && !space.strip.isSaved(active)
            if let existing {
                // Moving any pane moves the whole split.
                if toTab { space.strip.move(active, to: .afterTab(tab)) }
                let index = (existing.tabs.firstIndex(of: active) ?? 0) + (before ? 0 : 1)
                space.strip.addToSplit(existing.id, tab: tab, at: index)
            } else {
                if toTab {
                    space.strip.move(active, to: before ? .afterTab(tab) : .beforeTab(tab))
                } else {
                    space.strip.move(tab, to: before ? .beforeTab(active) : .afterTab(active))
                }
                space.strip.createSplit(before ? [tab, active] : [active, tab])
            }
        }
        activateTab(tab)
    }

    /// Separate Split View: the active tab's split becomes ordinary tabs.
    func separateSplitView() {
        if let split = activeSplit { dissolveSplit(split.id) }
    }

    func dissolveSplit(_ id: UUID) {
        workspace.updateActiveSpace { $0.strip.dissolveSplit(id) }
        syncActiveTab()
        scheduleSave()
    }

    /// Takes a tab out of its split, putting it right after the split.
    func removeFromSplit(_ tab: UUID) {
        guard let spaceID = workspace.spaceOfTab(tab) else { return }
        var removed = false
        workspace.updateSpace(spaceID) { removed = $0.strip.removeFromSplit(tab) }
        guard removed else { return }
        syncActiveTab()
        scheduleSave()
    }

    /// Switches a split between side by side and stacked.
    func flipSplit(_ id: UUID) {
        workspace.updateActiveSpace { $0.strip.flipSplit(id) }
        // A stacked split may fit where side by side didn't, or the reverse.
        syncActiveTab()
        delegate?.session(self, didChange: .split)
        scheduleSave()
    }

    /// Gives every pane of a split the same room.
    func equalizeSplit(_ id: UUID) {
        workspace.updateActiveSpace { $0.strip.equalizeSplit(id) }
        delegate?.session(self, didChange: .split)
        scheduleSave()
    }

    /// Moves a divider while it is dragged. Returns whether anything moved;
    /// the caller lays the panes out again.
    @discardableResult
    func resizeSplit(_ id: UUID, divider: Int, by delta: Double) -> Bool {
        var moved = false
        workspace.updateActiveSpace { moved = $0.strip.resizeSplit(id, divider: divider, by: delta) }
        if moved { scheduleSave() }
        return moved
    }

    /// Focuses a visible pane (a tap in it, or its sidebar segment).
    func focusPane(_ id: UUID) {
        guard id != activeTabID else { return }
        activateTab(id)
    }

    // MARK: - Spaces

    func switchSpace(_ id: UUID) {
        let previous = workspace.activeSpaceID
        guard workspace.switchSpace(id) else { return }
        spaceChanged(from: previous)
        syncActiveTab()
        scheduleSave()
    }

    func switchToAdjacentSpace(forward: Bool) {
        if let id = workspace.adjacentSpace(forward: forward) { switchSpace(id) }
    }

    func selectSpace(at index: Int) {
        if workspace.spaces.indices.contains(index) { switchSpace(workspace.spaces[index].id) }
    }

    private func spaceChanged(from previous: UUID) {
        let from = workspace.spaceIndex(previous) ?? 0
        let to = workspace.spaceIndex(workspace.activeSpaceID) ?? 0
        delegate?.session(self, didChange: .space(direction: to >= from ? 1 : -1))
    }

    /// Creates a space (and switches to it) or edits an existing one.
    func saveSpace(_ id: UUID?, name: String, icon: String, gradient: SpaceGradient) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "New Space" : name
        if let id {
            workspace.renameSpace(id, to: name)
            workspace.setSpaceIcon(id, icon)
            workspace.setSpaceGradient(id, gradient)
            delegate?.session(self, didChange: .space(direction: 0))
            changedTabs()
        } else {
            let id = workspace.createSpace(name: name, icon: icon, gradient: gradient)
            switchSpace(id)
        }
    }

    func shiftSpace(_ id: UUID, by delta: Int) {
        guard let index = workspace.spaceIndex(id) else { return }
        workspace.moveSpace(id, to: max(0, index + delta))
        changedTabs()
    }

    func deleteSpace(_ id: UUID) {
        guard let removed = workspace.deleteSpace(id) else { return }
        removed.strip.tabs.forEach { releaseTab($0.id) }
        delegate?.session(self, didChange: .space(direction: 0))
        syncActiveTab()
        scheduleSave()
    }

    /// Icon and theme suggested for a new space: the theme after the last
    /// space's, in the same tone.
    var newSpaceDefaults: (icon: String, gradient: SpaceGradient) {
        let gradient = workspace.spaces.last.map(\.gradient.next) ?? .default
        return (Space.icons[(workspace.spaces.count + 3) % Space.icons.count], gradient)
    }

    // MARK: - Page commands

    func goBack() { activeLiveTab?.goBack() }
    func goForward() { activeLiveTab?.goForward() }

    func reload() {
        if let id = activeTabID { ensureLiveTab(id)?.reload() }
    }

    func stopLoading() { activeLiveTab?.stop() }

    func zoom(by delta: Double) {
        guard let live = activeLiveTab else { return }
        live.setZoom(((live.state.zoom + delta) * 10).rounded() / 10)
    }

    func resetZoom() { activeLiveTab?.setZoom(1) }

    func copyActiveURL() {
        guard let tab = activeTab, !tab.isNewTabPage else { return }
        UIPasteboard.general.string = tab.url
        delegate?.session(self, showToast: "Link copied", title: nil, kind: .info)
    }

    func toggleBookmark() {
        guard let tab = activeTab, tab.url.hasPrefix("http") else { return }
        if services.bookmarks.isBookmarked(tab.url) {
            services.bookmarks.remove(url: tab.url)
            delegate?.session(self, showToast: "Bookmark removed", title: nil, kind: .info)
        } else {
            services.bookmarks.add(url: tab.url, title: tab.displayTitle)
            delegate?.session(self, showToast: "Bookmarked", title: nil, kind: .success)
        }
    }

    var isActivePageBookmarked: Bool {
        activeTab.map { services.bookmarks.isBookmarked($0.url) } ?? false
    }

    // MARK: - Assistant context

    func contextTab(_ id: UUID) -> ContextTab? {
        workspace.tab(id).map { ContextTab(id: id, title: $0.displayTitle, url: $0.url, favicon: $0.faviconURL) }
    }

    /// The tabs the assistant could read: the current one and the space's.
    var assistantContext: (current: ContextTab?, space: (id: UUID, name: String), spaceTabs: [ContextTab]) {
        let space = workspace.activeSpace
        return (activeTabID.flatMap(contextTab), (space.id, space.name), space.strip.orderedTabIDs.compactMap(contextTab))
    }

    /// Extracts the content of `tabs`, waking sleeping tabs first.
    func extractPages(_ tabs: [UUID]) async -> [PageContext] {
        var pages: [PageContext] = []
        for id in tabs {
            guard let model = workspace.tab(id), !Curio.isInternalURL(model.url), let live = ensureLiveTab(id) else { continue }
            if !live.isAwake {
                // Load hidden; read once it finishes (bounded wait).
                live.navigate(to: model.url)
                for _ in 0..<40 {
                    try? await Task.sleep(for: .milliseconds(250))
                    if !live.state.loading { break }
                }
            }
            let json = await live.extractContent()
            let page = json.flatMap { $0.data(using: .utf8) }.flatMap { try? JSONDecoder().decode(PageContext.self, from: $0) }
            pages.append(page ?? PageContext(
                title: model.displayTitle,
                url: model.url,
                text: "(The page content could not be read. Only its title and address are known.)"
            ))
        }
        return pages
    }

    // MARK: - Sleeping

    /// Puts background tabs to sleep: those idle too long, then the least
    /// recently used beyond the live-tab limit.
    func putIdleTabsToSleep() {
        let browsing = settings.browsing
        let idleLimit = TimeInterval(browsing.sleepAfterMinutes * 60)
        let awake = liveTabs.values.filter { $0.isAwake && !$0.isActive }.sorted { $0.lastActive < $1.lastActive }
        let excess = max(0, awake.count - max(browsing.maxLiveTabs - 1, 0))
        for (index, tab) in awake.enumerated() where index < excess || Date.now.timeIntervalSince(tab.lastActive) > idleLimit {
            tab.sleep()
        }
    }

    /// Frees memory under pressure: every background tab sleeps.
    func handleMemoryWarning() {
        for tab in liveTabs.values where !tab.isActive { tab.sleep() }
    }

    // MARK: - Saving

    /// Saves shortly after changes, coalescing bursts.
    func scheduleSave() {
        guard saveTask == nil else { return }
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(900))
            guard let self, !Task.isCancelled else { return }
            saveTask = nil
            services.workspaceStore.save(workspace)
        }
    }

    /// Saves immediately (the app is going to the background).
    func saveNow() {
        saveTask?.cancel()
        saveTask = nil
        services.workspaceStore.saveNow(workspace)
        services.history.saveNow()
    }

    // MARK: - History

    private func recordVisit(_ url: String) {
        guard settings.browsing.saveHistory, url.hasPrefix("http") else { return }
        services.history.recordVisit(url: url, title: "")
    }

    private func updateVisitTitle(_ url: String, _ title: String) {
        guard settings.browsing.saveHistory, url.hasPrefix("http"), !title.isEmpty else { return }
        services.history.updateTitle(url: url, title: title)
    }
}

// MARK: - Page events

extension BrowserSession: BrowserTabDelegate {
    func tabStateDidChange(_ tab: BrowserTab) {
        let state = tab.state
        var changed = false
        var titleChanged = false
        if let model = workspace.tab(tab.id) {
            if !state.url.isEmpty && workspace.setTabURL(tab.id, state.url) {
                changed = true
            }
            workspace.updateTab(tab.id) { model in
                if !state.title.isEmpty && model.title != state.title {
                    model.title = state.title
                    changed = true
                    titleChanged = true
                }
                if let favicon = state.favicon, model.faviconURL != favicon {
                    model.faviconURL = favicon
                    changed = true
                }
            }
            if titleChanged { updateVisitTitle(state.url.isEmpty ? model.url : state.url, state.title) }
        }
        if changed { scheduleSave() }
        delegate?.session(self, didChange: .page(tab.id))
    }

    func tab(_ tab: BrowserTab, didNavigateTo url: String) {
        recordVisit(url)
    }

    func tab(_ tab: BrowserTab, didFinishLoading url: String, title: String) {
        updateVisitTitle(url, title)
    }

    func tab(_ tab: BrowserTab, openInNewTab url: String, background: Bool) {
        openInNewTab(url, after: tab.id, activate: !background)
    }

    func tab(_ tab: BrowserTab, wantsToOpenExternally url: URL) {
        delegate?.session(self, confirmExternalOpen: url)
    }

    func tabSelectionDidChange(_ tab: BrowserTab) {
        if tab.id == activeTabID { delegate?.session(self, didChange: .selection) }
    }

    func tab(_ tab: BrowserTab, didScrollTo y: Double) {
        guard let model = workspace.tab(tab.id), abs(model.scrollY - y) > 1 else { return }
        workspace.updateTab(tab.id) { $0.scrollY = y }
        scheduleSave()
    }

    func tab(_ tab: BrowserTab, didStartDownload url: String, fileName: String) -> UUID {
        let id = services.downloads.start(url: url, fileName: fileName)
        delegate?.session(self, showToast: fileName, title: "Downloading", kind: .info)
        delegate?.session(self, didChange: .downloads)
        return id
    }

    func tab(_ tab: BrowserTab, didFinishDownload id: UUID, fileName: String?, success: Bool) {
        services.downloads.finish(id, fileName: fileName, success: success)
        let name = services.downloads.records.first { $0.id == id }?.displayName ?? ""
        delegate?.session(self, showToast: name, title: success ? "Download complete" : "Download failed", kind: success ? .success : .error)
        delegate?.session(self, didChange: .downloads)
    }

    func tab(_ tab: BrowserTab, askAboutSelection action: QuickAction?) {
        delegate?.session(self, askAboutSelection: action)
    }

    func tab(_ tab: BrowserTab, present alert: UIAlertController) {
        delegate?.session(self, present: alert)
    }

    func tabDidRequestFocus(_ tab: BrowserTab) {
        if tab.id != activeTabID, visibleTabIDs.contains(tab.id) { focusPane(tab.id) }
    }
}

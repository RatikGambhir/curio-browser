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

    init(services: AppServices) {
        self.services = services
        let restored = services.settings.settings.browsing.restoreSession ? services.workspaceStore.load() : nil
        workspace = restored ?? .firstRun()
        if restored == nil, let saved = services.workspaceStore.load() {
            // Not restoring tabs still keeps spaces, pinned tabs and favorites.
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
            for item in space.strip.items(.unpinned) {
                switch item {
                case .tab(let id): _ = workspace.closeTab(id)
                case .group(let id): workspace.updateSpace(space.id) { _ = $0.strip.deleteGroup(id, keepTabs: false) }
                }
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

    /// Makes the active tab visible (creating its web view on demand) and
    /// every other tab hidden.
    func syncActiveTab() {
        let active = workspace.activeTabID
        for (id, live) in liveTabs where id != active && live.isActive {
            live.setActive(false)
        }
        if let active, let live = ensureLiveTab(active), !live.isActive {
            live.setActive(true)
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

    /// Opens `url` in a new tab next to `after` (or at the top of the active
    /// space's regular tabs).
    @discardableResult
    func openInNewTab(_ url: String, after: UUID? = nil, activate: Bool = true) -> UUID {
        let tab = Tab(url: url)
        let space = after.flatMap(workspace.spaceOfTab) ?? workspace.activeSpaceID
        let placement: TabPlacement = if let after, workspace.space(space)?.strip.isPinned(after) == false {
            .afterTab(after)
        } else {
            .sectionStart(.unpinned)
        }
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
        workspace.updateTab(id) {
            $0.url = url
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

    /// Closes a tab. Favorites are put to sleep and hidden instead.
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

    /// Pinned tabs are kept; "closing" them unloads the page instead.
    func unloadTab(_ id: UUID) {
        if let home = workspace.tab(id)?.homeURL {
            workspace.updateTab(id) {
                $0.url = home
                $0.scrollY = 0
            }
        }
        releaseTab(id)
        if workspace.activeTabID == id {
            workspace.updateActiveSpace { space in
                space.activeTab = space.strip.orderedTabIDs.first { $0 != id }
            }
        }
        syncActiveTab()
        scheduleSave()
    }

    func closeOrUnloadTab(_ id: UUID) {
        if workspace.activeSpace.strip.isPinned(id) { unloadTab(id) } else { closeTab(id) }
    }

    func closeActiveTab() {
        if let id = activeTabID { closeTab(id) }
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

    /// Creates a "New Group" around `members` and returns it.
    func newGroup(with members: [UUID]) -> UUID? {
        guard let first = members.first, let spaceID = workspace.spaceOfTab(first),
              let space = workspace.space(spaceID) else { return nil }
        let color = AccentColor.allCases[(space.strip.groups.count + 1) % AccentColor.allCases.count]
        var group: UUID?
        workspace.updateSpace(spaceID) { group = $0.strip.createGroup(name: "New Group", color: color, members: members) }
        changedTabs()
        return group
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
    func saveSpace(_ id: UUID?, name: String, icon: String, color: AccentColor) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "New Space" : name
        if let id {
            workspace.renameSpace(id, to: name)
            workspace.setSpaceIcon(id, icon)
            workspace.setSpaceColor(id, color)
            delegate?.session(self, didChange: .space(direction: 0))
            changedTabs()
        } else {
            let id = workspace.createSpace(name: name, icon: icon, color: color)
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

    /// Icon and color suggested for a new space.
    var newSpaceDefaults: (icon: String, color: AccentColor) {
        let color = workspace.spaces.last.map(\.color.next) ?? .iris
        return (Space.icons[(workspace.spaces.count + 3) % Space.icons.count], color)
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
            workspace.updateTab(tab.id) { model in
                if !state.url.isEmpty && model.url != state.url {
                    model.url = state.url
                    changed = true
                }
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
}

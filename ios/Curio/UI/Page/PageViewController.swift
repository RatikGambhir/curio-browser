import UIKit

/// The page area: one page card showing the active tab, or the panes of its
/// split view side by side (or stacked). The focused pane (the active tab)
/// carries the page bar (with vertical tabs on wide screens), the new tab
/// page and the overlays on top of the page (loading bar, stalled banner,
/// find bar, selection actions); the other panes show a slim header.
final class PageViewController: UIViewController {
    private let session: BrowserSession
    let pageBar = PageBarView()
    let newTabPage = NewTabPageView()
    let findBar = FindBarView()
    private let container = SplitContainerView()
    private let dropOverlay = SplitDropOverlay()
    private let loadingBar = LoadingBarView(fraction: 0.35, period: 1.1)
    private let stalledBanner = StalledBannerView()
    private let selectionBar = SelectionActionsView()
    /// The panes on screen, in pane order.
    private var panes: [PaneView] = []
    private var overlayConstraints: [NSLayoutConstraint] = []
    private var findTask: Task<Void, Never>?
    private var findRegular: [NSLayoutConstraint] = []
    private var findCompact: [NSLayoutConstraint] = []
    private var selectionBottom: NSLayoutConstraint?
    private var focusedTab: UUID?
    private var reportedSize: CGSize = .zero

    private(set) var findOpen = false
    var compact = false {
        didSet { updateFindPlacement() }
    }
    var showsPageBar = true {
        didSet { if showsPageBar != oldValue { showActiveTab() } }
    }
    /// Hides the selection bar while another overlay owns the screen.
    var suppressSelection = false {
        didSet { refreshOverlays() }
    }
    var onCommand: ((CurioCommand) -> Void)? {
        didSet {
            pageBar.onCommand = onCommand
            newTabPage.onCommand = onCommand
        }
    }
    var onSelectionAction: ((QuickAction?) -> Void)?
    /// The page area changed size (split views show only when they fit).
    var onSizeChange: ((CGSize) -> Void)?

    init(session: BrowserSession) {
        self.session = session
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        for subview in [container, dropOverlay] as [UIView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(subview)
            NSLayoutConstraint.activate([
                subview.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                subview.trailingAnchor.constraint(equalTo: view.trailingAnchor),
                subview.topAnchor.constraint(equalTo: view.topAnchor),
                subview.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            ])
        }
        newTabPage.translatesAutoresizingMaskIntoConstraints = false
        for overlay in [loadingBar, stalledBanner, findBar, selectionBar] as [UIView] {
            overlay.translatesAutoresizingMaskIntoConstraints = false
        }
        findBar.isHidden = true
        stalledBanner.isHidden = true
        selectionBar.isHidden = true
        loadingBar.isHidden = true
        stalledBanner.retryButton.addAction(UIAction { [weak self] _ in self?.session.reload() }, for: .primaryActionTriggered)
        selectionBar.onAction = { [weak self] in self?.onSelectionAction?($0) }
        findBar.onSearch = { [weak self] query, forward in self?.runFind(query, forward: forward) }
        findBar.onClose = { [weak self] in self?.closeFind() }
        newTabPage.onOpen = { [weak self] url in self?.session.navigateActive(url) }
        pageBar.onRemoveFromSplit = { [weak self] in
            guard let self, let id = session.activeTabID else { return }
            session.removeFromSplit(id)
        }
        container.onResize = { [weak self] divider, delta in
            guard let self, let split = session.visibleSplit,
                  session.resizeSplit(split.id, divider: divider, by: delta) else { return nil }
            return session.visibleSplit?.sizes
        }
        container.onEqualize = { [weak self] in
            guard let self, let split = session.visibleSplit else { return }
            session.equalizeSplit(split.id)
        }
        dropOverlay.onDrop = { [weak self] tab, before in self?.session.splitWith(tab, before: before) }
        showActiveTab()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if view.bounds.size != reportedSize {
            reportedSize = view.bounds.size
            onSizeChange?(reportedSize)
        }
    }

    private func updateFindPlacement() {
        guard isViewLoaded else { return }
        NSLayoutConstraint.deactivate(compact ? findRegular : findCompact)
        NSLayoutConstraint.activate(compact ? findCompact : findRegular)
        selectionBottom?.constant = compact ? -10 : -16
    }

    // MARK: - Showing the active tab

    /// The focused pane: the active tab's, or the only one.
    private var focusedPane: PaneView? { panes.first { $0.isFocusedPane } }

    private func makePane() -> PaneView {
        let pane = PaneView()
        pane.onFocus = { [weak self] id in self?.session.focusPane(id) }
        pane.header.removeButton.addAction(UIAction { [weak self, weak pane] _ in
            guard let self, let id = pane?.tabID else { return }
            session.removeFromSplit(id)
        }, for: .primaryActionTriggered)
        pane.header.closeButton.addAction(UIAction { [weak self, weak pane] _ in
            guard let self, let id = pane?.tabID else { return }
            session.closeOrUnloadTab(id)
        }, for: .primaryActionTriggered)
        pane.header.menuProvider = { [weak self, weak pane] in
            guard let self, let id = pane?.tabID, let split = session.split(of: id) else { return nil }
            return UIMenu(children: [SidebarMenus.splitItems(id, split: split.id, session: session)])
        }
        return pane
    }

    /// Puts the visible tabs in the page area: the active tab's web view (or
    /// the new tab page), or every pane of its split view. Panes still on
    /// screen keep their web views, so focusing a pane never interrupts a
    /// touch on its page.
    func showActiveTab() {
        guard isViewLoaded else { return }
        let split = session.visibleSplit
        let active = session.activeTabID
        let slots: [UUID?] = split?.tabs ?? [active]
        var spare = panes.filter { pane in !slots.contains { $0 != nil && $0 == pane.tabID } }
        var ordered: [PaneView] = []
        for slot in slots {
            if let slot, let existing = panes.first(where: { $0.tabID == slot }) {
                ordered.append(existing)
            } else {
                let pane = spare.isEmpty ? makePane() : spare.removeFirst()
                if let slot { pane.setTab(slot) } else { pane.reset() }
                ordered.append(pane)
            }
        }
        spare.forEach { $0.reset() }
        panes = ordered
        for (pane, slot) in zip(ordered, slots) {
            let focused = split == nil || slot == active
            pane.isFocusedPane = focused
            pane.outlined = split != nil && focused
            let tab = slot.flatMap(session.workspace.tab)
            let webView = (tab?.isNewTabPage ?? true) ? nil : slot.flatMap { session.liveTabs[$0]?.webView }
            pane.host(webView)
            if focused {
                pane.setHeader(showsPageBar ? pageBar : nil)
                attachFocusedContent(to: pane)
                pane.showPlaceholder(nil, visible: false)
                newTabPage.isHidden = webView != nil
                if webView == nil { refreshNewTabPage() }
            } else {
                let model = slot.flatMap(session.tabViewModel)
                if let model { pane.header.configure(model) }
                pane.setHeader(showsPageBar ? pane.header : nil)
                pane.showPlaceholder(model, visible: webView == nil)
            }
        }
        container.show(ordered, sizes: split?.sizes ?? [1], orientation: split?.orientation ?? .horizontal)
        pageBar.showsRemoveFromSplit = split != nil
        if focusedTab != active {
            focusedTab = active
            if findOpen { closeFind() }
        }
        refreshOverlays()
        updateAccessibility(split)
    }

    /// Refreshes a visible pane after its page changed (title, icon, a web
    /// view created or released).
    func refreshPane(_ id: UUID) {
        guard isViewLoaded, let pane = panes.first(where: { $0.tabID == id }) else { return }
        let tab = session.workspace.tab(id)
        let webView = (tab?.isNewTabPage ?? true) ? nil : session.liveTabs[id]?.webView
        if pane.hostedWebView !== webView || (webView != nil && webView?.superview !== pane.content) {
            showActiveTab()
        } else if !pane.isFocusedPane, let model = session.tabViewModel(id) {
            pane.header.configure(model)
            pane.showPlaceholder(model, visible: webView == nil)
        }
    }

    /// Re-applies pane sizes and orientation (a flip or equal sizes).
    func refreshSplitLayout() {
        showActiveTab()
    }

    /// Moves the new tab page and the overlays into the focused pane.
    private func attachFocusedContent(to pane: PaneView) {
        let content = pane.content
        guard loadingBar.superview !== content else {
            // Keep the overlays above a web view hosted since.
            for overlay in [loadingBar, stalledBanner, findBar, selectionBar] as [UIView] { content.bringSubviewToFront(overlay) }
            return
        }
        NSLayoutConstraint.deactivate(overlayConstraints + findRegular + findCompact)
        for view in [newTabPage, loadingBar, stalledBanner, findBar, selectionBar] as [UIView] { view.removeFromSuperview() }
        pane.insertUnderPage(newTabPage)
        for overlay in [loadingBar, stalledBanner, findBar, selectionBar] as [UIView] { content.addSubview(overlay) }
        let selectionBottom = selectionBar.bottomAnchor.constraint(equalTo: content.safeAreaLayoutGuide.bottomAnchor, constant: compact ? -10 : -16)
        self.selectionBottom = selectionBottom
        overlayConstraints = [
            newTabPage.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            newTabPage.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            newTabPage.topAnchor.constraint(equalTo: content.topAnchor),
            newTabPage.bottomAnchor.constraint(equalTo: content.bottomAnchor),
            loadingBar.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            loadingBar.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            loadingBar.topAnchor.constraint(equalTo: content.topAnchor),
            stalledBanner.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            stalledBanner.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            stalledBanner.topAnchor.constraint(equalTo: content.topAnchor, constant: 12),
            selectionBar.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            selectionBar.leadingAnchor.constraint(greaterThanOrEqualTo: content.leadingAnchor, constant: 8),
            selectionBottom,
        ]
        // A narrow pane gets the full-width find bar.
        let regularFind = findBar.widthAnchor.constraint(equalToConstant: 360)
        regularFind.priority = .defaultHigh
        findRegular = [
            findBar.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
            findBar.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            findBar.leadingAnchor.constraint(greaterThanOrEqualTo: content.leadingAnchor, constant: 8),
            regularFind,
        ]
        findCompact = [
            findBar.topAnchor.constraint(equalTo: content.topAnchor, constant: 8),
            findBar.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 8),
            findBar.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -8),
        ]
        NSLayoutConstraint.activate(overlayConstraints)
        NSLayoutConstraint.activate(compact ? findCompact : findRegular)
    }

    /// VoiceOver reads the panes in order, each named for its page.
    private func updateAccessibility(_ split: TabSplit?) {
        for (index, pane) in panes.enumerated() {
            guard let split, let id = pane.tabID else {
                pane.accessibilityLabel = nil
                continue
            }
            let title = session.workspace.tab(id)?.displayTitle ?? ""
            pane.accessibilityLabel = "\(title), pane \(index + 1) of \(split.tabs.count)"
            pane.accessibilityContainerType = .semanticGroup
            pane.shouldGroupAccessibilityChildren = true
        }
    }

    // MARK: - Drop zones

    /// Shows the split drop zones while a tab is dragged, when split views
    /// are available.
    func setDropZonesActive(_ active: Bool) {
        guard isViewLoaded else { return }
        dropOverlay.setActive(active && session.splitAvailable)
    }

    func refreshNewTabPage() {
        let workspace = session.workspace
        let favorites = workspace.favorites.map { (title: $0.tab.displayTitle, url: $0.tab.url, favicon: $0.tab.faviconURL) }
        let top = session.topSites(limit: 8).map { entry in
            (title: entry.title.isEmpty ? Curio.displayHost(entry.url) : entry.title, url: entry.url, favicon: String?.none)
        }
        let hasKeyboard = traitCollection.userInterfaceIdiom == .pad
        newTabPage.update(spaceName: workspace.activeSpace.name, sites: Array((favorites + top).prefix(8)), showsKeyboardHint: hasKeyboard)
    }

    /// Updates the loading bar, stalled banner and selection actions.
    func refreshOverlays() {
        guard isViewLoaded else { return }
        let state = session.activeLiveTab?.state
        let showingPage = focusedPane?.hostedWebView != nil
        loadingBar.isHidden = !(showingPage && state?.loading == true)
        stalledBanner.isHidden = !(showingPage && state?.stalled == true)
        let selection = state?.selection.flatMap { $0.count >= 2 ? $0 : nil }
        if let selection, showingPage, !suppressSelection {
            selectionBar.update(selection: selection, compact: compact)
            if selectionBar.isHidden {
                selectionBar.isHidden = false
                selectionBar.alpha = 0
                UIView.animate(withDuration: ThemeCenter.shared.motionEnabled ? 0.14 : 0) { self.selectionBar.alpha = 1 }
            }
        } else {
            selectionBar.isHidden = true
        }
    }

    // MARK: - Find in page

    func openFind() {
        guard session.activeLiveTab?.isAwake == true, focusedPane?.hostedWebView != nil else { return }
        findOpen = true
        findBar.isHidden = false
        findBar.field.textField.becomeFirstResponder()
        findBar.field.textField.selectAll(nil)
    }

    func closeFind() {
        findOpen = false
        findTask?.cancel()
        findBar.isHidden = true
        findBar.field.textField.resignFirstResponder()
        findBar.show(FindResult())
        session.activeLiveTab?.clearFind()
    }

    func findAgain(forward: Bool) {
        guard findOpen else { return openFind() }
        findBar.search(forward: forward)
    }

    private func runFind(_ query: String, forward: Bool) {
        guard let live = session.activeLiveTab else { return }
        findTask?.cancel()
        findTask = Task { [weak self] in
            let result = await live.find(query, forward: forward)
            guard !Task.isCancelled else { return }
            self?.findBar.show(result)
        }
    }
}

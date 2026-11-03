import UIKit

/// The page card: the page bar (with vertical tabs on wide screens), the
/// active tab's web view or the new tab page, and the overlays on top of the
/// page (loading bar, stalled banner, find bar, selection actions).
final class PageViewController: UIViewController {
    private let session: BrowserSession
    let card = CardView()
    let pageBar = PageBarView()
    let newTabPage = NewTabPageView()
    let findBar = FindBarView()
    private let content = UIView()
    private let loadingBar = LoadingBarView(fraction: 0.35, period: 1.1)
    private let stalledBanner = StalledBannerView()
    private let selectionBar = SelectionActionsView()
    private var hostedWebView: CurioWebView?
    private var findTask: Task<Void, Never>?
    private var findRegular: [NSLayoutConstraint] = []
    private var findCompact: [NSLayoutConstraint] = []
    private var selectionBottom: NSLayoutConstraint?

    private(set) var findOpen = false
    var compact = false {
        didSet { updateFindPlacement() }
    }
    var showsPageBar = true {
        didSet { pageBar.isHidden = !showsPageBar }
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

    init(session: BrowserSession) {
        self.session = session
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        card.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(card)
        let column = UIStackView(arrangedSubviews: [pageBar, content])
        column.axis = .vertical
        column.translatesAutoresizingMaskIntoConstraints = false
        card.contentView.addSubview(column)
        newTabPage.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(newTabPage)
        content.clipsToBounds = true
        for overlay in [loadingBar, stalledBanner, findBar, selectionBar] as [UIView] {
            overlay.translatesAutoresizingMaskIntoConstraints = false
            content.addSubview(overlay)
        }
        let selectionBottom = selectionBar.bottomAnchor.constraint(equalTo: content.safeAreaLayoutGuide.bottomAnchor, constant: -16)
        self.selectionBottom = selectionBottom
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            card.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            card.topAnchor.constraint(equalTo: view.topAnchor),
            card.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            column.leadingAnchor.constraint(equalTo: card.contentView.leadingAnchor),
            column.trailingAnchor.constraint(equalTo: card.contentView.trailingAnchor),
            column.topAnchor.constraint(equalTo: card.contentView.topAnchor),
            column.bottomAnchor.constraint(equalTo: card.contentView.bottomAnchor),
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
        ])
        findRegular = [
            findBar.topAnchor.constraint(equalTo: content.topAnchor, constant: 10),
            findBar.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -14),
            findBar.widthAnchor.constraint(equalToConstant: 360),
        ]
        findCompact = [
            findBar.topAnchor.constraint(equalTo: content.topAnchor, constant: 8),
            findBar.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 8),
            findBar.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -8),
        ]
        updateFindPlacement()
        findBar.isHidden = true
        stalledBanner.isHidden = true
        selectionBar.isHidden = true
        loadingBar.isHidden = true
        stalledBanner.retryButton.addAction(UIAction { [weak self] _ in self?.session.reload() }, for: .primaryActionTriggered)
        selectionBar.onAction = { [weak self] in self?.onSelectionAction?($0) }
        findBar.onSearch = { [weak self] query, forward in self?.runFind(query, forward: forward) }
        findBar.onClose = { [weak self] in self?.closeFind() }
        newTabPage.onOpen = { [weak self] url in self?.session.navigateActive(url) }
    }

    private func updateFindPlacement() {
        guard isViewLoaded else { return }
        NSLayoutConstraint.deactivate(compact ? findRegular : findCompact)
        NSLayoutConstraint.activate(compact ? findCompact : findRegular)
        selectionBottom?.constant = compact ? -10 : -16
    }

    // MARK: - Showing the active tab

    /// Puts the active tab's web view (or the new tab page) in the card.
    func showActiveTab() {
        guard isViewLoaded else { return }
        let live = session.activeLiveTab
        let tab = session.activeTab
        let webView = (tab?.isNewTabPage ?? true) ? nil : live?.webView
        if hostedWebView !== webView {
            hostedWebView?.removeFromSuperview()
            hostedWebView = webView
            if let webView {
                webView.translatesAutoresizingMaskIntoConstraints = false
                content.insertSubview(webView, aboveSubview: newTabPage)
                NSLayoutConstraint.activate([
                    webView.leadingAnchor.constraint(equalTo: content.leadingAnchor),
                    webView.trailingAnchor.constraint(equalTo: content.trailingAnchor),
                    webView.topAnchor.constraint(equalTo: content.topAnchor),
                    webView.bottomAnchor.constraint(equalTo: content.bottomAnchor),
                ])
            }
        }
        newTabPage.isHidden = webView != nil
        if webView == nil { refreshNewTabPage() }
        if findOpen { closeFind() }
        refreshOverlays()
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
        let showingPage = hostedWebView != nil
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
        guard session.activeLiveTab?.isAwake == true, hostedWebView != nil else { return }
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

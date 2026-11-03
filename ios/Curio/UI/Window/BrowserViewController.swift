import UIKit

/// The browser screen. On wide screens (iPad, an unfolded foldable) it
/// matches the desktop: a sidebar column, the page floating as a card, and
/// the assistant beside it. On narrow screens (iPhone, a folded foldable,
/// Slide Over) tabs live in a drawer, the address bar sits at the bottom,
/// and the assistant opens as a sheet. The layout follows the available
/// width, so it switches live when a device folds or a window resizes.
final class BrowserViewController: UIViewController, ThemeObserving {
    let services: AppServices
    let session: BrowserSession

    // Child screens.
    let sidebar: SidebarViewController
    let library: LibraryViewController
    let page: PageViewController
    let assistant: AssistantViewController
    var commandBar: CommandBarViewController?

    // Chrome.
    let chrome = GradientView()
    let leftColumn = UIView()
    let sidebarHost = UIView()
    let libraryHost = UIView()
    let sidebarHandle = ResizeHandleView()
    let mainStack = UIStackView()
    let toolbar = ToolbarView()
    let tabStrip: TabStripView
    let pageHost = UIView()
    let aiHandle = ResizeHandleView()
    let aiColumn = UIView()
    let aiCard = CardView(shadow: .md)
    let bottomBar = BottomBarView()
    let drawerScrim = UIControl()
    let drawer = UIView()
    let drawerBackground = GradientView()
    let peekEdge = UIView()
    var toasts: ToastPresenter?

    // State.
    var isCompact = false
    var assistantOpen = false
    var libraryOpen = false
    var drawerOpen = false
    var sidebarWidth: CGFloat
    var aiWidth: CGFloat
    var hasLaidOut = false
    var hasAppliedMode = false
    weak var presentedAssistantSheet: UIViewController?
    /// Keeps the Quick Look data source alive while a file is previewed.
    var previewSource: PreviewSource?

    // Constraints changed by `applyLayout`.
    var leftWidth: NSLayoutConstraint!
    var sidebarHostWidth: NSLayoutConstraint!
    var libraryHostWidth: NSLayoutConstraint!
    var sidebarHandleWidth: NSLayoutConstraint!
    var aiColumnWidth: NSLayoutConstraint!
    var aiHandleWidth: NSLayoutConstraint!
    var pageLeading: NSLayoutConstraint!
    var pageTrailing: NSLayoutConstraint!
    var pageTop: NSLayoutConstraint!
    var pageBottom: NSLayoutConstraint!
    var mainBottomToBar: NSLayoutConstraint!
    var mainBottomToSafe: NSLayoutConstraint!
    /// The page column ends at the assistant column, or at the screen edge
    /// when the assistant floats over the page.
    var mainTrailingToAI: NSLayoutConstraint!
    var mainTrailingToSafe: NSLayoutConstraint!
    var drawerLeading: NSLayoutConstraint!
    var drawerWidth: NSLayoutConstraint!
    var drawerTop: NSLayoutConstraint!
    var drawerBottom: NSLayoutConstraint!

    init(services: AppServices) {
        self.services = services
        session = BrowserSession(services: services)
        sidebar = SidebarViewController(session: session)
        library = LibraryViewController(session: session)
        page = PageViewController(session: session)
        assistant = AssistantViewController(session: session)
        tabStrip = TabStripView(session: session)
        sidebarWidth = services.settings.settings.appearance.sidebarWidth
        aiWidth = services.settings.settings.appearance.aiPanelWidth
        super.init(nibName: nil, bundle: nil)
        session.delegate = self
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    var settings: Settings { services.settings.settings }

    override var preferredStatusBarStyle: UIStatusBarStyle {
        ThemeCenter.shared.theme.appearance == .dark ? .lightContent : .darkContent
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildHierarchy()
        wireActions()
        toasts = ToastPresenter(host: view)
        services.settings.observe(self) { [weak self] _ in self?.settingsChanged() }
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (self: Self, _: UITraitCollection) in
            self.applyTheme(animated: false)
        }
        registerForTraitChanges([UITraitHorizontalSizeClass.self]) { (self: Self, _: UITraitCollection) in
            self.updateMode(for: self.view.bounds.size)
        }
        applyTheme(animated: false)
        ThemeCenter.shared.observe(self)
        session.syncActiveTab()
    }

    /// First-time layout needs the view's final size, which is known here.
    override func viewIsAppearing(_ animated: Bool) {
        super.viewIsAppearing(animated)
        if !hasLaidOut {
            hasLaidOut = true
            updateMode(for: view.bounds.size, animated: false)
            // An empty space opens on the command bar, like a fresh Arc window.
            if session.activeTab?.isNewTabPage ?? true {
                openCommandBar(.newTab)
            }
            #if DEBUG
            runDebugLaunchActions()
            #endif
        }
    }

    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        coordinator.animate { _ in self.updateMode(for: size, animated: false) }
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        session.handleMemoryWarning()
    }

    func themeDidChange(_ theme: CurioTheme) {
        setNeedsStatusBarAppearanceUpdate()
        drawerScrim.backgroundColor = theme.scrim.uiColor
        drawer.layer.borderColor = theme.surfaceBorder.uiColor.cgColor
    }

    // MARK: - Building

    private func embed(_ child: UIViewController, in container: UIView) {
        addChild(child)
        child.view.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(child.view)
        NSLayoutConstraint.activate([
            child.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            child.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            child.view.topAnchor.constraint(equalTo: container.topAnchor),
            child.view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        child.didMove(toParent: self)
    }

    private func buildHierarchy() {
        let safe = view.safeAreaLayoutGuide
        for subview in [chrome, leftColumn, sidebarHandle, mainStack, aiHandle, aiColumn, bottomBar, peekEdge, drawerScrim, drawer] as [UIView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(subview)
        }
        leftColumn.clipsToBounds = true
        for host in [sidebarHost, libraryHost] {
            host.translatesAutoresizingMaskIntoConstraints = false
            leftColumn.addSubview(host)
        }
        embed(sidebar, in: sidebarHost)
        embed(library, in: libraryHost)
        sidebar.delegate = self
        library.delegate = self

        mainStack.axis = .vertical
        mainStack.addArrangedSubview(toolbar)
        mainStack.addArrangedSubview(tabStrip)
        mainStack.addArrangedSubview(pageHost)
        addChild(page)
        page.view.translatesAutoresizingMaskIntoConstraints = false
        pageHost.addSubview(page.view)
        page.didMove(toParent: self)

        aiCard.translatesAutoresizingMaskIntoConstraints = false
        aiColumn.addSubview(aiCard)
        assistant.delegate = self
        embed(assistant, in: aiCard.contentView)

        drawer.clipsToBounds = true
        drawer.layer.cornerCurve = .continuous
        drawerBackground.translatesAutoresizingMaskIntoConstraints = false
        drawer.addSubview(drawerBackground)
        drawerScrim.alpha = 0
        drawerScrim.isHidden = true
        drawer.isHidden = true

        leftWidth = leftColumn.widthAnchor.constraint(equalToConstant: sidebarWidth)
        sidebarHostWidth = sidebarHost.widthAnchor.constraint(equalToConstant: sidebarWidth)
        libraryHostWidth = libraryHost.widthAnchor.constraint(equalToConstant: LibraryViewController.railWidth + sidebarWidth)
        sidebarHandleWidth = sidebarHandle.widthAnchor.constraint(equalToConstant: 6)
        aiColumnWidth = aiColumn.widthAnchor.constraint(equalToConstant: 0)
        aiHandleWidth = aiHandle.widthAnchor.constraint(equalToConstant: 0)
        pageLeading = page.view.leadingAnchor.constraint(equalTo: pageHost.leadingAnchor)
        pageTrailing = pageHost.trailingAnchor.constraint(equalTo: page.view.trailingAnchor, constant: 8)
        pageTop = page.view.topAnchor.constraint(equalTo: pageHost.topAnchor, constant: 8)
        pageBottom = pageHost.bottomAnchor.constraint(equalTo: page.view.bottomAnchor, constant: 8)
        mainBottomToBar = mainStack.bottomAnchor.constraint(equalTo: bottomBar.topAnchor)
        mainBottomToSafe = mainStack.bottomAnchor.constraint(equalTo: safe.bottomAnchor)
        mainTrailingToAI = mainStack.trailingAnchor.constraint(equalTo: aiHandle.leadingAnchor)
        mainTrailingToSafe = mainStack.trailingAnchor.constraint(equalTo: safe.trailingAnchor)
        drawerLeading = drawer.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: -400)
        drawerWidth = drawer.widthAnchor.constraint(equalToConstant: 320)
        drawerTop = drawer.topAnchor.constraint(equalTo: view.topAnchor)
        drawerBottom = view.bottomAnchor.constraint(equalTo: drawer.bottomAnchor)

        NSLayoutConstraint.activate([
            chrome.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            chrome.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            chrome.topAnchor.constraint(equalTo: view.topAnchor),
            chrome.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            leftColumn.leadingAnchor.constraint(equalTo: safe.leadingAnchor),
            leftColumn.topAnchor.constraint(equalTo: safe.topAnchor),
            leftColumn.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            leftWidth,
            sidebarHost.leadingAnchor.constraint(equalTo: leftColumn.leadingAnchor),
            sidebarHost.topAnchor.constraint(equalTo: leftColumn.topAnchor),
            sidebarHost.bottomAnchor.constraint(equalTo: leftColumn.bottomAnchor),
            sidebarHostWidth,
            libraryHost.leadingAnchor.constraint(equalTo: leftColumn.leadingAnchor),
            libraryHost.topAnchor.constraint(equalTo: leftColumn.topAnchor),
            libraryHost.bottomAnchor.constraint(equalTo: leftColumn.bottomAnchor),
            libraryHostWidth,

            sidebarHandle.leadingAnchor.constraint(equalTo: leftColumn.trailingAnchor),
            sidebarHandle.topAnchor.constraint(equalTo: safe.topAnchor),
            sidebarHandle.bottomAnchor.constraint(equalTo: safe.bottomAnchor),
            sidebarHandleWidth,

            mainStack.leadingAnchor.constraint(equalTo: sidebarHandle.trailingAnchor),
            mainStack.topAnchor.constraint(equalTo: safe.topAnchor),
            mainTrailingToAI,
            mainBottomToSafe,
            pageLeading, pageTrailing, pageTop, pageBottom,

            aiHandle.trailingAnchor.constraint(equalTo: aiColumn.leadingAnchor),
            aiHandle.topAnchor.constraint(equalTo: safe.topAnchor),
            aiHandle.bottomAnchor.constraint(equalTo: safe.bottomAnchor),
            aiHandleWidth,
            aiColumn.trailingAnchor.constraint(equalTo: safe.trailingAnchor),
            aiColumn.topAnchor.constraint(equalTo: safe.topAnchor),
            aiColumn.bottomAnchor.constraint(equalTo: safe.bottomAnchor),
            aiColumnWidth,
            aiCard.leadingAnchor.constraint(equalTo: aiColumn.leadingAnchor),
            aiCard.trailingAnchor.constraint(equalTo: aiColumn.trailingAnchor, constant: -Metrics.panelGap),
            aiCard.topAnchor.constraint(equalTo: aiColumn.topAnchor, constant: Metrics.panelGap),
            aiCard.bottomAnchor.constraint(equalTo: aiColumn.bottomAnchor, constant: -Metrics.panelGap),

            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            peekEdge.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            peekEdge.topAnchor.constraint(equalTo: safe.topAnchor, constant: Metrics.toolbarHeight),
            peekEdge.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            peekEdge.widthAnchor.constraint(equalToConstant: 8),

            drawerScrim.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            drawerScrim.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            drawerScrim.topAnchor.constraint(equalTo: view.topAnchor),
            drawerScrim.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            drawerLeading, drawerWidth, drawerTop, drawerBottom,
            drawerBackground.leadingAnchor.constraint(equalTo: drawer.leadingAnchor),
            drawerBackground.trailingAnchor.constraint(equalTo: drawer.trailingAnchor),
            drawerBackground.topAnchor.constraint(equalTo: drawer.topAnchor),
            drawerBackground.bottomAnchor.constraint(equalTo: drawer.bottomAnchor),
        ])
    }

    private func wireActions() {
        let command: (CurioCommand) -> Void = { [weak self] in self?.perform($0) }
        page.onCommand = command
        page.onSelectionAction = { [weak self] in self?.askAboutSelection($0) }
        toolbar.onCommand = command
        bottomBar.onCommand = command
        tabStrip.onCommand = command
        tabStrip.onAskAboutTab = { [weak self] in self?.sidebarAskAboutTab($0) }
        bottomBar.moreButton.menu = moreMenu()
        drawerScrim.addAction(UIAction { [weak self] _ in self?.setDrawer(open: false) }, for: .touchUpInside)
        drawerScrim.accessibilityLabel = "Close Tabs"
        let swipeClose = UIPanGestureRecognizer(target: self, action: #selector(drawerScrimPan(_:)))
        drawerScrim.addGestureRecognizer(swipeClose)
        let barSwipe = UIPanGestureRecognizer(target: self, action: #selector(bottomBarPan(_:)))
        bottomBar.addGestureRecognizer(barSwipe)
        HoverTracker(peekEdge) { [weak self] inside in
            if inside { self?.setPeek(open: true) }
        }
        HoverTracker(drawer) { [weak self] inside in
            guard let self, !inside, !isCompact, drawerOpen else { return }
            setPeek(open: false)
        }
        sidebarHandle.currentValue = { [weak self] in self?.sidebarWidth ?? 260 }
        sidebarHandle.onChange = { [weak self] width in
            guard let self else { return }
            sidebarWidth = min(max(width, 200), 420)
            applyLayout(animated: false)
        }
        sidebarHandle.onEnd = { [weak self] in self?.persistWidths() }
        aiHandle.direction = -1
        aiHandle.currentValue = { [weak self] in self?.aiWidth ?? 380 }
        aiHandle.onChange = { [weak self] width in
            guard let self else { return }
            aiWidth = min(max(width, 300), min(640, view.bounds.width * 0.6))
            applyLayout(animated: false)
        }
        aiHandle.onEnd = { [weak self] in self?.persistWidths() }
    }

    private func persistWidths() {
        let (sidebar, ai) = (Double(sidebarWidth), Double(aiWidth))
        services.settings.update {
            $0.appearance.sidebarWidth = sidebar
            $0.appearance.aiPanelWidth = ai
        }
    }

    // MARK: - Theme

    /// Applies the active space's accent and the light/dark setting.
    func applyTheme(animated: Bool) {
        let appearance = Appearance.resolve(settings.appearance.theme, system: traitCollection.userInterfaceStyle)
        let accent: AccentColor = settings.appearance.tintChromeWithSpace ? session.workspace.activeSpace.color : .graphite
        ThemeCenter.shared.reduceMotion = settings.appearance.reduceMotion
        ThemeCenter.shared.apply(accent: accent, appearance: appearance)
        let theme = ThemeCenter.shared.theme
        let duration = animated && ThemeCenter.shared.motionEnabled ? 0.32 : 0
        chrome.setColors(theme.chromeTop.uiColor, theme.chromeBottom.uiColor, duration: duration)
        drawerBackground.setColors(theme.chromeTop.uiColor, theme.chromeBottom.uiColor, duration: duration)
        view.window?.overrideUserInterfaceStyle = settings.appearance.theme == .system ? .unspecified : appearance.interfaceStyle
        view.window?.tintColor = theme.accent.uiColor
        session.setAppearance(appearance.interfaceStyle)
    }

    private var lastLayoutSettings: AppearanceSettings?

    private func settingsChanged() {
        applyTheme(animated: false)
        let appearance = settings.appearance
        if lastLayoutSettings?.tabLayout != appearance.tabLayout || lastLayoutSettings?.sidebarVisible != appearance.sidebarVisible {
            if appearance.tabLayout == .horizontal { libraryOpen = false }
            placeSidebar()
            applyLayout(animated: lastLayoutSettings != nil)
        }
        lastLayoutSettings = appearance
        refreshBars()
        tabStrip.reload()
        UIMenuSystem.main.setNeedsRebuild()
    }
}

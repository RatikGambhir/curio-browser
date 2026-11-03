import UIKit

extension BrowserViewController {
    // MARK: - Bars

    /// Updates navigation buttons and addresses in every bar.
    func refreshBars() {
        guard isViewLoaded else { return }
        let nav = session.pageNav
        page.pageBar.update(nav, sidebarVisible: sidebarColumnVisible, assistantOpen: assistantOpen, showsSidebarButton: true)
        let space = session.workspace.activeSpace
        if !toolbar.isHidden {
            toolbar.update(nav, space: space, assistantOpen: assistantOpen, spaceMenu: spacePickerMenu())
        }
        if !bottomBar.isHidden {
            bottomBar.update(nav, assistantOpen: assistantOpen)
        }
    }

    private func spacePickerMenu() -> UIMenu {
        let active = session.workspace.activeSpaceID
        let spaces = session.workspace.spaces.map { space in
            UIAction(title: "\(space.icon)  \(space.name)", state: space.id == active ? .on : .off) { [weak self] _ in
                self?.session.switchSpace(space.id)
            }
        }
        let newSpace = UIAction(title: "New Space…", image: Icon.plus.image()) { [weak self] _ in self?.perform(.newSpace) }
        return UIMenu(children: [UIMenu(options: .displayInline, children: spaces), newSpace])
    }

    /// Everything that doesn't fit in the phone's bottom bar.
    func moreMenu() -> UIMenu {
        UIMenu(children: [UIDeferredMenuElement.uncached { [weak self] completion in
            guard let self else { return completion([]) }
            let item = { (command: CurioCommand, title: String?) in
                UIAction(title: title ?? command.title, image: command.icon.image()) { [weak self] _ in self?.perform(command) }
            }
            let hasPage = !(session.activeTab?.isNewTabPage ?? true)
            let pinned = session.activeTabID.map { session.workspace.activeSpace.strip.isPinned($0) } ?? false
            var page: [UIMenuElement] = []
            if hasPage {
                page = [
                    item(.findInPage, nil),
                    item(.share, nil),
                    item(.copyURL, "Copy Link"),
                    item(.toggleBookmark, session.isActivePageBookmarked ? "Remove Bookmark" : "Bookmark Page"),
                    item(.pinTab, pinned ? "Unpin Tab" : "Pin Tab"),
                    item(.addFavorite, "Add to Favorites"),
                    UIMenu(title: "Zoom", image: Icon.textMagnify.image(), children: [item(.zoomIn, nil), item(.zoomOut, nil), item(.zoomReset, nil)]),
                ]
            }
            completion([
                UIMenu(options: .displayInline, children: [item(.newTab, nil), item(.reopenClosedTab, nil), item(.newSpace, "New Space…")]),
                UIMenu(options: .displayInline, children: page),
                UIMenu(options: .displayInline, children: [item(.toggleLibrary, "Library"), item(.showHistory, "History"), item(.showDownloads, "Downloads")]),
                UIMenu(options: .displayInline, children: [item(.toggleTabLayout, verticalTabs ? "Show Tab Strip" : "Hide Tab Strip"), item(.openSettings, nil)]),
            ])
        }])
    }

    // MARK: - Commands

    /// Runs a browser command from a menu, shortcut, bar or the palette.
    func perform(_ command: CurioCommand) {
        let active = session.activeTabID
        switch command {
        case .newTab: openCommandBar(.newTab)
        case .openCommandBar: openCommandBar(.palette)
        case .editURL: openCommandBar(.editURL)
        case .closeTab: session.closeActiveTab()
        case .reopenClosedTab: session.reopenClosedTab()
        case .duplicateTab: if let active { session.duplicateTab(active) }
        case .pinTab: if let active { session.togglePin(active) }
        case .nextTab: session.cycleTab(forward: true)
        case .previousTab: session.cycleTab(forward: false)
        case .selectTab1: session.selectTab(at: 0)
        case .selectTab2: session.selectTab(at: 1)
        case .selectTab3: session.selectTab(at: 2)
        case .selectTab4: session.selectTab(at: 3)
        case .selectTab5: session.selectTab(at: 4)
        case .selectTab6: session.selectTab(at: 5)
        case .selectTab7: session.selectTab(at: 6)
        case .selectTab8: session.selectTab(at: 7)
        case .selectLastTab: session.selectTab(at: nil)
        case .newGroupFromTab:
            if let active, let group = session.newGroup(with: [active]) { sidebarRenameGroup(group) }
        case .addFavorite: if let active { session.addFavorite(active) }
        case .toggleBookmark: session.toggleBookmark()
        case .copyURL: session.copyActiveURL()
        case .goBack: session.goBack()
        case .goForward: session.goForward()
        case .reload: session.reload()
        case .stopLoading: session.stopLoading()
        case .escape: escape()
        case .findInPage: page.openFind()
        case .findNext: page.findAgain(forward: true)
        case .findPrevious: page.findAgain(forward: false)
        case .zoomIn: session.zoom(by: 0.1)
        case .zoomOut: session.zoom(by: -0.1)
        case .zoomReset: session.resetZoom()
        case .openDevTools: showDevToolsInfo()
        case .print: printPage()
        case .share: sharePage()
        case .showHistory: showHistory()
        case .showDownloads: showDownloads()
        case .newSpace: sidebarEditSpace(nil)
        case .nextSpace: session.switchToAdjacentSpace(forward: true)
        case .previousSpace: session.switchToAdjacentSpace(forward: false)
        case .selectSpace1: session.selectSpace(at: 0)
        case .selectSpace2: session.selectSpace(at: 1)
        case .selectSpace3: session.selectSpace(at: 2)
        case .selectSpace4: session.selectSpace(at: 3)
        case .selectSpace5: session.selectSpace(at: 4)
        case .selectSpace6: session.selectSpace(at: 5)
        case .selectSpace7: session.selectSpace(at: 6)
        case .selectSpace8: session.selectSpace(at: 7)
        case .selectSpace9: session.selectSpace(at: 8)
        case .toggleSidebar: toggleSidebar()
        case .toggleTabLayout:
            services.settings.update { $0.appearance.tabLayout = $0.appearance.tabLayout == .vertical ? .horizontal : .vertical }
        case .toggleAIPanel: toggleAssistant()
        case .explainSelection: askAboutSelection(.explainSelection)
        case .newChat:
            assistant.newConversation()
            showAssistant()
        case .askAboutPage:
            showAssistant(focus: false)
            assistant.quickAction(.summarizePage)
        case .toggleLibrary: toggleLibrary()
        case .openSettings: openSettings(nil)
        case .about: present(SheetStyle.wrap(AboutViewController(), compact: isCompact, size: CGSize(width: 380, height: 420), detents: [.medium()]), animated: true)
        }
    }

    private func toggleSidebar() {
        if isCompact {
            setDrawer(open: !drawerOpen)
        } else if libraryOpen {
            toggleLibrary()
        } else if sidebarYieldsToAssistant {
            setPeek(open: !drawerOpen)
        } else {
            services.settings.update { $0.appearance.sidebarVisible.toggle() }
        }
    }

    /// Closes the topmost transient thing, or stops loading.
    func escape() {
        if commandBar != nil {
            closeCommandBar()
        } else if page.findOpen {
            page.closeFind()
        } else if libraryOpen {
            toggleLibrary()
        } else if drawerOpen {
            setDrawer(open: false)
        } else if session.activeLiveTab?.state.loading == true {
            session.stopLoading()
        }
    }

    // MARK: - Command bar

    func openCommandBar(_ mode: CommandMode) {
        closeCommandBar()
        setDrawer(open: false)
        if presentedViewController != nil && presentedViewController !== presentedAssistantSheet { return }
        let text = mode == .editURL ? (session.activeTab.flatMap { $0.isNewTabPage ? nil : $0.url } ?? "") : ""
        let bar = CommandBarViewController(session: session, mode: mode, text: text, compact: isCompact)
        bar.onDismiss = { [weak self] in self?.closeCommandBar() }
        bar.onExecute = { [weak self] target in
            self?.closeCommandBar()
            self?.execute(target)
        }
        let host: UIViewController = presentedAssistantSheet == nil ? self : (presentedAssistantSheet ?? self)
        if host !== self { dismissAssistantSheet() }
        addChild(bar)
        bar.view.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(bar.view)
        NSLayoutConstraint.activate([
            bar.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bar.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bar.view.topAnchor.constraint(equalTo: view.topAnchor),
            bar.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        bar.didMove(toParent: self)
        bar.animateIn()
        commandBar = bar
        page.suppressSelection = true
        UIAccessibility.post(notification: .screenChanged, argument: bar.view)
    }

    func closeCommandBar() {
        guard let bar = commandBar else { return }
        commandBar = nil
        bar.view.endEditing(true)
        bar.willMove(toParent: nil)
        bar.view.removeFromSuperview()
        bar.removeFromParent()
        page.suppressSelection = false
    }

    private func execute(_ target: CommandTarget) {
        switch target {
        case .navigate(let url, let newTab): session.open(url, newTab: newTab)
        case .switchTab(let id): session.activateTab(id)
        case .command(let command): perform(command)
        case .askAI(let question):
            showAssistant(focus: false)
            assistant.ask(question)
        }
    }

    // MARK: - Assistant

    func toggleAssistant() {
        if assistantOpen { hideAssistant() } else { showAssistant() }
    }

    func showAssistant(focus: Bool = true) {
        assistant.refreshContext()
        if !assistantOpen {
            assistantOpen = true
            if isCompact {
                setDrawer(open: false)
                presentAssistantSheet()
            } else {
                embedAssistantInColumn()
                applyLayout(animated: true)
            }
        }
        if focus && !isCompact { assistant.focusComposer() }
        refreshBars()
    }

    func hideAssistant() {
        assistantOpen = false
        if isCompact {
            dismissAssistantSheet()
        } else {
            view.endEditing(true)
            applyLayout(animated: true)
        }
        refreshBars()
    }

    /// Sends the page selection to the assistant with an action, or puts it
    /// in the message box for "Ask…".
    func askAboutSelection(_ action: QuickAction?) {
        let selection = session.activeLiveTab?.state.selection ?? ""
        guard let action else {
            guard !selection.isEmpty else { return }
            showAssistant(focus: false)
            assistant.prefillQuote(selection)
            return
        }
        showAssistant(focus: false)
        let resolved: QuickAction = if case .translateSelection = action {
            .translateSelection(language: settings.ai.translateTo)
        } else {
            action
        }
        if selection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            assistant.quickAction(.summarizePage)
        } else {
            assistant.askAboutSelection(resolved, selection: selection)
        }
    }

    // MARK: - Screens

    func openSettings(_ section: SettingsSection?) {
        setDrawer(open: false)
        closeCommandBar()
        let controller = SettingsViewController(session: session, section: section, compact: isCompact)
        presentFromTop(SheetStyle.wrap(controller, compact: isCompact, size: CGSize(width: 760, height: 560)))
    }

    func showHistory() {
        setDrawer(open: false)
        let controller = HistoryViewController(history: services.history)
        controller.onOpen = { [weak self] url in self?.session.openInNewTab(url) }
        controller.onCleared = { [weak self] in
            self?.toasts?.show("History cleared")
            self?.page.refreshNewTabPage()
        }
        presentFromTop(SheetStyle.wrap(controller, compact: isCompact, size: CGSize(width: 640, height: 560), detents: [.medium(), .large()]))
    }

    func showDownloads() {
        setDrawer(open: false)
        let controller = DownloadsViewController(store: services.downloads)
        presentFromTop(SheetStyle.wrap(controller, compact: isCompact, size: CGSize(width: 520, height: 480), detents: [.medium(), .large()]))
    }

    /// Presents over whatever is on screen (the assistant sheet included).
    func presentFromTop(_ controller: UIViewController) {
        var top: UIViewController = self
        while let presented = top.presentedViewController { top = presented }
        top.present(controller, animated: true)
    }

    private func sharePage() {
        guard let tab = session.activeTab, !tab.isNewTabPage, let url = URL(string: tab.url) else { return }
        let share = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        share.popoverPresentationController?.sourceView = isCompact ? bottomBar.moreButton : page.pageBar.address
        presentFromTop(share)
    }

    private func printPage() {
        guard let formatter = session.activeLiveTab?.printFormatter else { return }
        let controller = UIPrintInteractionController.shared
        let info = UIPrintInfo.printInfo()
        info.jobName = session.activeTab?.displayTitle ?? "Curio"
        controller.printInfo = info
        controller.printFormatter = formatter
        controller.present(animated: true)
    }

    private func showDevToolsInfo() {
        let alert = UIAlertController(
            title: "Developer Tools",
            message: "Pages in Curio can be inspected with Safari’s Web Inspector. Connect this device to a Mac, open Safari, and choose Develop › \(UIDevice.current.name) › the page.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        presentFromTop(alert)
    }

    // MARK: - Keyboard and menu bar

    /// Target of every Curio key command in the menu bar.
    @objc func performCurioCommand(_ sender: Any?) {
        guard let value = (sender as? UICommand)?.propertyList as? String,
              let name = value.split(separator: "#").first,
              let curio = CurioCommand(rawValue: String(name)) else { return }
        perform(curio)
    }
}

import UIKit

extension BrowserViewController {
    /// Narrow layouts: compact width, or too little room for a sidebar
    /// column beside the page.
    func isCompactLayout(for size: CGSize) -> Bool {
        traitCollection.horizontalSizeClass == .compact || size.width < 600
    }

    /// Switches between the phone and desktop layouts when the width class
    /// changes (rotation, folding, Split View, Stage Manager).
    func updateMode(for size: CGSize, animated: Bool = false) {
        let compact = isCompactLayout(for: size)
        let changed = compact != isCompact || !hasAppliedMode
        isCompact = compact
        hasAppliedMode = true
        if changed {
            closeDrawerImmediately()
            if compact { libraryOpen = false }
            sidebar.compact = compact
            page.compact = compact
            toasts?.bottomInset = compact ? 64 : 16
            moveAssistantForMode()
        }
        placeSidebar()
        applyLayout(animated: animated)
        refreshBars()
    }

    /// The narrowest the page card gets beside the columns.
    static let minimumPageWidth: CGFloat = 380
    static let minimumAssistantWidth: CGFloat = 300

    var verticalTabs: Bool { settings.appearance.tabLayout == .vertical }
    /// The sidebar has a column of its own (wide screens, vertical tabs).
    var sidebarColumnVisible: Bool {
        !isCompact && verticalTabs && settings.appearance.sidebarVisible && !sidebarYieldsToAssistant
    }

    /// On narrower wide screens (an unfolded foldable, iPad mini) the
    /// sidebar, the assistant and a readable page don't fit side by side.
    /// The sidebar then steps aside while the assistant is open; it can
    /// still be peeked from the sidebar button or the left edge.
    var sidebarYieldsToAssistant: Bool {
        guard !isCompact, assistantOpen, verticalTabs, settings.appearance.sidebarVisible, !libraryOpen else { return false }
        let available = view.bounds.width - view.safeAreaInsets.left - view.safeAreaInsets.right
        return available - (sidebarWidth + 6) - 6 - Self.minimumPageWidth < Self.minimumAssistantWidth
    }

    /// Sets every size and visibility for the current mode and state.
    func applyLayout(animated: Bool) {
        placeSidebar()
        let compact = isCompact
        let libraryVisible = !compact && libraryOpen
        let columnVisible = libraryVisible || sidebarColumnVisible
        let aiVisible = !compact && assistantOpen

        sidebarHostWidth.constant = sidebarWidth
        libraryHostWidth.constant = LibraryViewController.railWidth + sidebarWidth
        leftWidth.constant = libraryVisible ? LibraryViewController.railWidth + sidebarWidth : (sidebarColumnVisible ? sidebarWidth : 0)
        sidebarHandleWidth.constant = columnVisible ? 6 : 0
        sidebarHandle.isUserInteractionEnabled = sidebarColumnVisible && !libraryVisible
        // Narrow wide screens (an unfolded foldable, iPad mini) can't fit the
        // sidebar, the assistant and a readable page side by side. The
        // assistant column shrinks first; if it still doesn't fit, it floats
        // over the page instead of squeezing it.
        let available = view.bounds.width - view.safeAreaInsets.left - view.safeAreaInsets.right
        let leftTotal = columnVisible ? leftWidth.constant + 6 : 0
        let room = available - leftTotal - 6 - Self.minimumPageWidth
        let aiFloats = aiVisible && room < Self.minimumAssistantWidth
        let assistantWidth = aiFloats ? min(aiWidth, max(Self.minimumAssistantWidth, available - leftTotal - 2 * Metrics.panelGap)) : min(aiWidth, max(room, Self.minimumAssistantWidth))
        aiColumnWidth.constant = aiVisible ? assistantWidth : 0
        aiHandleWidth.constant = aiVisible && !aiFloats ? 6 : 0
        aiHandle.isUserInteractionEnabled = !aiFloats
        if aiFloats {
            mainTrailingToAI.isActive = false
            mainTrailingToSafe.isActive = true
        } else {
            mainTrailingToSafe.isActive = false
            mainTrailingToAI.isActive = true
        }
        aiCard.shadow = aiFloats ? .xxl : .md

        toolbar.isHidden = compact || verticalTabs
        tabStrip.isHidden = verticalTabs
        page.showsPageBar = !compact && verticalTabs
        bottomBar.isHidden = !compact
        peekEdge.isHidden = compact || !verticalTabs || sidebarColumnVisible || libraryOpen
        if compact {
            mainBottomToSafe.isActive = false
            mainBottomToBar.isActive = true
        } else {
            mainBottomToBar.isActive = false
            mainBottomToSafe.isActive = true
        }

        if compact {
            pageLeading.constant = 6
            pageTrailing.constant = 6
            pageTop.constant = verticalTabs ? 4 : 2
            pageBottom.constant = 4
        } else {
            pageLeading.constant = columnVisible ? 0 : Metrics.panelGap
            pageTrailing.constant = aiVisible && !aiFloats ? 0 : Metrics.panelGap
            pageTop.constant = verticalTabs ? Metrics.panelGap : 0
            pageBottom.constant = Metrics.panelGap
        }

        let changes = {
            self.sidebarHost.alpha = libraryVisible ? 0 : 1
            self.libraryHost.alpha = libraryVisible ? 1 : 0
            self.aiColumn.alpha = aiVisible ? 1 : 0
            self.view.layoutIfNeeded()
        }
        aiColumn.isHidden = false
        if animated && ThemeCenter.shared.motionEnabled && view.window != nil {
            let animator = UIViewPropertyAnimator(duration: 0.28, timingParameters: UICubicTimingParameters(animationCurve: .easeOut))
            animator.addAnimations(changes)
            animator.addCompletion { _ in self.aiColumn.isHidden = !aiVisible }
            animator.startAnimation()
        } else {
            changes()
            aiColumn.isHidden = !aiVisible
        }
    }

    // MARK: - Sidebar placement

    /// Puts the sidebar in its column, or in the drawer (phones, and the
    /// peek overlay when the column is hidden).
    func placeSidebar() {
        let target: UIView = sidebarColumnVisible ? sidebarHost : drawer
        guard sidebar.view.superview !== target else { return }
        sidebar.view.removeFromSuperview()
        sidebar.view.translatesAutoresizingMaskIntoConstraints = false
        target.addSubview(sidebar.view)
        let top: NSLayoutConstraint = if target === drawer && isCompact {
            sidebar.view.topAnchor.constraint(equalTo: drawer.safeAreaLayoutGuide.topAnchor)
        } else {
            sidebar.view.topAnchor.constraint(equalTo: target.topAnchor, constant: target === drawer ? 8 : 0)
        }
        NSLayoutConstraint.activate([
            sidebar.view.leadingAnchor.constraint(equalTo: target.leadingAnchor),
            sidebar.view.trailingAnchor.constraint(equalTo: target.trailingAnchor),
            top,
            sidebar.view.bottomAnchor.constraint(equalTo: target.bottomAnchor),
        ])
    }

    // MARK: - Drawer (phones) and peek (hidden sidebar on wide screens)

    func setDrawer(open: Bool) {
        guard isCompact else {
            setPeek(open: open)
            return
        }
        placeSidebar()
        let width = min(340, view.bounds.width * 0.86)
        drawerWidth.constant = width
        drawerTop.constant = 0
        drawerBottom.constant = 0
        drawer.layer.cornerRadius = 0
        drawer.layer.borderWidth = 0
        drawer.layer.maskedCorners = [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]
        showDrawer(open, closedOffset: -width - 20, openOffset: 0, scrim: true)
        if open { view.endEditing(true) }
        UIAccessibility.post(notification: .screenChanged, argument: open ? sidebar.view : nil)
    }

    func setPeek(open: Bool) {
        guard !isCompact, !sidebarColumnVisible, verticalTabs else { return }
        placeSidebar()
        drawerWidth.constant = sidebarWidth
        drawerTop.constant = view.safeAreaInsets.top + Metrics.toolbarHeight
        drawerBottom.constant = view.safeAreaInsets.bottom + 8
        drawer.layer.cornerRadius = Metrics.cardRadius
        drawer.layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMinYCorner, .layerMinXMaxYCorner, .layerMaxXMaxYCorner]
        drawer.layer.borderWidth = 1
        drawer.layer.borderColor = ThemeCenter.shared.theme.surfaceBorder.uiColor.cgColor
        showDrawer(open, closedOffset: -sidebarWidth - 20, openOffset: view.safeAreaInsets.left + 6, scrim: false)
    }

    private func showDrawer(_ open: Bool, closedOffset: CGFloat, openOffset: CGFloat, scrim: Bool) {
        guard open != drawerOpen || drawer.isHidden == open else { return }
        drawerOpen = open
        // The phone drawer covers the page; VoiceOver stays inside it.
        drawer.accessibilityViewIsModal = open && scrim
        drawer.isHidden = false
        drawerScrim.isHidden = !scrim
        if open {
            drawerLeading.constant = closedOffset
            view.layoutIfNeeded()
        }
        drawerLeading.constant = open ? openOffset : closedOffset
        let changes = {
            self.drawerScrim.alpha = open && scrim ? 1 : 0
            self.view.layoutIfNeeded()
        }
        let done = { (_: UIViewAnimatingPosition) in
            if !self.drawerOpen {
                self.drawer.isHidden = true
                self.drawerScrim.isHidden = true
            }
        }
        if ThemeCenter.shared.motionEnabled {
            let animator = UIViewPropertyAnimator(duration: 0.3, timingParameters: Metrics.easeOutQuint)
            animator.addAnimations(changes)
            animator.addCompletion(done)
            animator.startAnimation()
        } else {
            changes()
            done(.end)
        }
    }

    func closeDrawerImmediately() {
        drawerOpen = false
        drawer.isHidden = true
        drawerScrim.isHidden = true
        drawerScrim.alpha = 0
    }

    @objc func drawerScrimPan(_ pan: UIPanGestureRecognizer) {
        if pan.state == .ended, pan.translation(in: view).x < -40 || pan.velocity(in: view).x < -400 {
            setDrawer(open: false)
        }
    }

    /// Swiping right on the bottom bar opens the tabs drawer.
    @objc func bottomBarPan(_ pan: UIPanGestureRecognizer) {
        if pan.state == .ended, pan.translation(in: view).x > 50 || pan.velocity(in: view).x > 500 {
            setDrawer(open: true)
        }
    }

    // MARK: - Library

    func toggleLibrary() {
        if isCompact {
            presentLibrarySheet()
            return
        }
        guard verticalTabs else {
            presentLibrarySheet()
            return
        }
        libraryOpen.toggle()
        if libraryOpen {
            setPeek(open: false)
            library.reload()
        }
        applyLayout(animated: true)
    }

    private func presentLibrarySheet() {
        setDrawer(open: false)
        let sheetLibrary = LibraryViewController(session: session)
        sheetLibrary.presentedAsSheet = true
        sheetLibrary.delegate = self
        let theme = ThemeCenter.shared.theme
        sheetLibrary.view.backgroundColor = theme.surface.uiColor
        sheetLibrary.overrideUserInterfaceStyle = theme.appearance.interfaceStyle
        sheetLibrary.modalPresentationStyle = isCompact ? .pageSheet : .formSheet
        sheetLibrary.preferredContentSize = CGSize(width: 520, height: 600)
        if let sheet = sheetLibrary.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
        }
        present(sheetLibrary, animated: true)
    }

    // MARK: - Assistant hosting

    /// The assistant is a column on wide screens and a sheet on phones.
    func moveAssistantForMode() {
        guard assistantOpen else { return }
        if isCompact {
            hideAssistantColumnHost()
            presentAssistantSheet()
        } else {
            dismissAssistantSheet { [weak self] in self?.embedAssistantInColumn() }
        }
    }

    func embedAssistantInColumn() {
        guard assistant.parent !== self || assistant.view.superview !== aiCard.contentView else { return }
        if assistant.parent != nil {
            assistant.willMove(toParent: nil)
            assistant.view.removeFromSuperview()
            assistant.removeFromParent()
        }
        addChild(assistant)
        assistant.view.translatesAutoresizingMaskIntoConstraints = false
        aiCard.contentView.addSubview(assistant.view)
        NSLayoutConstraint.activate([
            assistant.view.leadingAnchor.constraint(equalTo: aiCard.contentView.leadingAnchor),
            assistant.view.trailingAnchor.constraint(equalTo: aiCard.contentView.trailingAnchor),
            assistant.view.topAnchor.constraint(equalTo: aiCard.contentView.topAnchor),
            assistant.view.bottomAnchor.constraint(equalTo: aiCard.contentView.bottomAnchor),
        ])
        assistant.didMove(toParent: self)
        assistant.presentedAsSheet = false
    }

    private func hideAssistantColumnHost() {
        guard assistant.parent === self else { return }
        assistant.willMove(toParent: nil)
        assistant.view.removeFromSuperview()
        assistant.removeFromParent()
    }

    func presentAssistantSheet() {
        guard presentedAssistantSheet == nil else { return }
        hideAssistantColumnHost()
        assistant.presentedAsSheet = true
        assistant.overrideUserInterfaceStyle = ThemeCenter.shared.theme.appearance.interfaceStyle
        assistant.modalPresentationStyle = .pageSheet
        if let sheet = assistant.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
            sheet.largestUndimmedDetentIdentifier = .medium
            sheet.prefersScrollingExpandsWhenScrolledToEdge = false
            sheet.delegate = self
        }
        presentedAssistantSheet = assistant
        let presenter = presentedViewController == nil ? self : nil
        presenter?.present(assistant, animated: true)
        if presenter == nil {
            dismiss(animated: true) { [weak self] in
                guard let self else { return }
                present(assistant, animated: true)
            }
        }
    }

    func dismissAssistantSheet(completion: (() -> Void)? = nil) {
        guard let sheet = presentedAssistantSheet else {
            completion?()
            return
        }
        presentedAssistantSheet = nil
        sheet.dismiss(animated: true, completion: completion)
    }
}

extension BrowserViewController: UISheetPresentationControllerDelegate {
    /// Swiping the assistant sheet away closes it.
    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        if presentationController.presentedViewController === assistant {
            presentedAssistantSheet = nil
            assistantOpen = false
            refreshBars()
        }
    }
}

import UIKit

/// The vertical sidebar: favorites, the active space's pinned and regular
/// tabs with folders, and the space switcher. Hosted as a column on wide
/// screens and as a drawer on narrow ones.
final class SidebarViewController: UIViewController, ThemeObserving {
    private let session: BrowserSession
    weak var delegate: SidebarDelegate? {
        didSet { menus.delegate = delegate }
    }
    private var menus: SidebarMenus
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<SidebarSection, SidebarItem>!
    private let footer = SidebarFooterView()
    private var tabRows: [SidebarItem] = []
    private var lastSpace: UUID?
    private var swipeTranslation: CGFloat = 0
    /// The folder whose name is being edited in its row.
    private var renamingGroup: UUID?
    /// Narrow layouts use taller rows for touch.
    var compact = false {
        didSet { if compact != oldValue { reload(animated: false, reconfigure: true) } }
    }
    /// Top padding above the favorites.
    var topInset: CGFloat = 8 {
        didSet { collectionView?.contentInset.top = topInset }
    }

    init(session: BrowserSession) {
        self.session = session
        menus = SidebarMenus(session: session)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        collectionView = UICollectionView(frame: .zero, collectionViewLayout: makeLayout())
        collectionView.backgroundColor = .clear
        collectionView.delegate = self
        collectionView.dragDelegate = self
        collectionView.dropDelegate = self
        collectionView.dragInteractionEnabled = true
        collectionView.contentInset.top = topInset
        collectionView.alwaysBounceVertical = true
        // Scrolling saves a folder name being edited, like tapping away.
        collectionView.keyboardDismissMode = .onDrag
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        footer.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(collectionView)
        view.addSubview(footer)
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: view.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: footer.topAnchor),
            footer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
        ])
        footer.libraryButton.addAction(UIAction { [weak self] _ in self?.delegate?.sidebarToggleLibrary() }, for: .primaryActionTriggered)
        footer.newSpaceButton.addAction(UIAction { [weak self] _ in self?.delegate?.sidebarEditSpace(nil) }, for: .primaryActionTriggered)
        footer.settingsButton.addAction(UIAction { [weak self] _ in self?.delegate?.sidebarOpenSettings() }, for: .primaryActionTriggered)
        configureDataSource()
        addSpaceSwipe()
        let tapAway = UITapGestureRecognizer(target: self, action: #selector(handleTapAway(_:)))
        tapAway.cancelsTouchesInView = false
        collectionView.addGestureRecognizer(tapAway)
        ThemeCenter.shared.observe(self)
        reload(animated: false)
    }

    func themeDidChange(_ theme: CurioTheme) {
        guard isViewLoaded else { return }
        reload(animated: false, reconfigure: true)
    }

    // MARK: - Layout

    private func makeLayout() -> UICollectionViewLayout {
        UICollectionViewCompositionalLayout { [weak self] index, environment in
            guard let self, let section = SidebarSection(rawValue: index) else { return nil }
            switch section {
            case .favorites:
                let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .fractionalWidth(0.25), heightDimension: .absolute(44)))
                item.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 3, bottom: 0, trailing: 3)
                let group = NSCollectionLayoutGroup.horizontal(layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .absolute(44)), subitems: [item])
                let layout = NSCollectionLayoutSection(group: group)
                layout.interGroupSpacing = 6
                let hasFavorites = !session.workspace.favorites.isEmpty
                layout.contentInsets = NSDirectionalEdgeInsets(top: 2, leading: 7, bottom: hasFavorites ? 8 : 0, trailing: 7)
                return layout
            case .header:
                let size = NSCollectionLayoutSize(widthDimension: .fractionalWidth(1), heightDimension: .absolute(compact ? 40 : 34))
                let group = NSCollectionLayoutGroup.horizontal(layoutSize: size, subitems: [NSCollectionLayoutItem(layoutSize: size)])
                let layout = NSCollectionLayoutSection(group: group)
                layout.contentInsets = NSDirectionalEdgeInsets(top: 2, leading: 10, bottom: 2, trailing: 10)
                return layout
            case .tabs:
                var configuration = UICollectionLayoutListConfiguration(appearance: .plain)
                configuration.backgroundColor = .clear
                configuration.showsSeparators = false
                configuration.trailingSwipeActionsConfigurationProvider = { [weak self] indexPath in
                    self?.trailingSwipeActions(at: indexPath)
                }
                configuration.leadingSwipeActionsConfigurationProvider = { [weak self] indexPath in
                    self?.leadingSwipeActions(at: indexPath)
                }
                let layout = NSCollectionLayoutSection.list(using: configuration, layoutEnvironment: environment)
                layout.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 10, bottom: 48, trailing: 10)
                return layout
            }
        }
    }

    private var rowHeight: CGFloat { Metrics.rowHeight(compact: compact) }

    private func configureDataSource() {
        let favoriteCell = UICollectionView.CellRegistration<FavoriteTileCell, UUID> { [weak self] cell, _, id in
            guard let self, let model = session.tabViewModel(id) else { return }
            cell.configure(model)
        }
        let headerCell = UICollectionView.CellRegistration<SpaceHeaderCell, UUID> { [weak self] cell, _, id in
            guard let self, let space = session.workspace.space(id) else { return }
            cell.configure(space, menu: menus.spaceMenu(id))
        }
        let tabCell = UICollectionView.CellRegistration<TabRowCell, UUID> { [weak self] cell, _, id in
            guard let self, let model = session.tabViewModel(id) else { return }
            let grouped = session.workspace.activeSpace.strip.location(of: id)?.group != nil
            cell.configure(model, grouped: grouped, height: rowHeight)
            cell.onClose = { [weak self] model in self?.closeButtonTapped(model) }
        }
        let groupCell = UICollectionView.CellRegistration<GroupRowCell, UUID> { [weak self] cell, _, id in
            guard let self, let group = session.workspace.activeSpace.strip.group(id) else { return }
            cell.onCommitName = { [weak self] name in self?.finishFolderRename(id, name: name) }
            cell.onCancelName = { [weak self] in self?.finishFolderRename(id, name: nil) }
            cell.configure(group, height: rowHeight - 4, editing: renamingGroup == id)
        }
        let splitCell = UICollectionView.CellRegistration<SplitRowCell, UUID> { [weak self] cell, _, id in
            guard let self, let split = session.workspace.activeSpace.strip.split(id) else { return }
            let grouped = session.workspace.activeSpace.strip.location(of: split.tabs[0])?.group != nil
            cell.configure(split.tabs.compactMap(session.tabViewModel), grouped: grouped, height: rowHeight)
            cell.onSelect = { [weak self] tab, flags in self?.selectPane(tab, flags: flags) }
            cell.onClose = { [weak self] tab in self?.session.closeOrUnloadTab(tab) }
        }
        let dividerCell = UICollectionView.CellRegistration<DividerCell, Bool> { [weak self] cell, _, hasPinned in
            cell.configure(hasPinned: hasPinned, height: self?.rowHeight ?? 36)
        }
        let emptyCell = UICollectionView.CellRegistration<EmptyHintCell, Bool> { _, _, _ in }
        dataSource = UICollectionViewDiffableDataSource(collectionView: collectionView) { [weak self] collectionView, indexPath, item in
            switch item {
            case .favorite(let id):
                return collectionView.dequeueConfiguredReusableCell(using: favoriteCell, for: indexPath, item: id)
            case .header(let id):
                return collectionView.dequeueConfiguredReusableCell(using: headerCell, for: indexPath, item: id)
            case .tab(let id):
                return collectionView.dequeueConfiguredReusableCell(using: tabCell, for: indexPath, item: id)
            case .group(let id):
                return collectionView.dequeueConfiguredReusableCell(using: groupCell, for: indexPath, item: id)
            case .split(let id):
                return collectionView.dequeueConfiguredReusableCell(using: splitCell, for: indexPath, item: id)
            case .divider:
                let hasPinned = !(self?.session.workspace.activeSpace.strip.items(.pinned).isEmpty ?? true)
                return collectionView.dequeueConfiguredReusableCell(using: dividerCell, for: indexPath, item: hasPinned)
            case .empty:
                return collectionView.dequeueConfiguredReusableCell(using: emptyCell, for: indexPath, item: true)
            }
        }
    }

    // MARK: - Updating

    /// Rebuilds the rows from the session. Same-identity rows are
    /// reconfigured in place.
    func reload(animated: Bool = true, reconfigure: Bool = true) {
        guard isViewLoaded else { return }
        let workspace = session.workspace
        let space = workspace.activeSpace
        if let renaming = renamingGroup, space.strip.group(renaming) == nil {
            // The folder was deleted, moved or its space switched away.
            renamingGroup = nil
        }
        var snapshot = NSDiffableDataSourceSnapshot<SidebarSection, SidebarItem>()
        snapshot.appendSections(SidebarSection.allCases)
        snapshot.appendItems(workspace.favorites.map { .favorite($0.tab.id) }, toSection: .favorites)
        snapshot.appendItems([.header(space.id)], toSection: .header)
        var rows: [SidebarItem] = []
        var dividerDone = false
        // The single-page layout lists a split's panes as ordinary tabs.
        for row in space.strip.rows(alwaysShow: space.activeTab, showingSplit: session.splitRoom.fits) {
            if row.section == .unpinned && !dividerDone {
                rows.append(.divider)
                dividerDone = true
            }
            switch row {
            case .tab(let id, _, _): rows.append(.tab(id))
            case .group(let id, _): rows.append(.group(id))
            case .split(let id, _, _): rows.append(.split(id))
            }
        }
        if !dividerDone { rows.append(.divider) }
        if space.strip.isEmpty { rows.append(.empty) }
        tabRows = rows
        snapshot.appendItems(rows, toSection: .tabs)
        if reconfigure {
            snapshot.reconfigureItems(snapshot.itemIdentifiers)
        }
        let spaceChanged = lastSpace != nil && lastSpace != space.id
        lastSpace = space.id
        dataSource.apply(snapshot, animatingDifferences: animated && !spaceChanged && ThemeCenter.shared.motionEnabled)
        collectionView.collectionViewLayout.invalidateLayout()
        footer.configure(session: session, menus: menus)
    }

    /// Refreshes one tab's row (title, icon, loading) without a full diff.
    func refreshTab(_ id: UUID) {
        guard isViewLoaded else { return }
        var snapshot = dataSource.snapshot()
        var candidates = [SidebarItem.tab(id), .favorite(id)]
        if let split = session.workspace.activeSpace.strip.split(of: id) { candidates.append(.split(split.id)) }
        let items = candidates.filter { snapshot.indexOfItem($0) != nil }
        guard !items.isEmpty else { return }
        snapshot.reconfigureItems(items)
        dataSource.apply(snapshot, animatingDifferences: false)
    }

    // MARK: - Folder rename

    /// Turns a folder's row into a text field with the name selected,
    /// scrolling it into view if needed.
    func beginFolderRename(_ id: UUID) {
        guard isViewLoaded, session.workspace.activeSpace.strip.group(id) != nil else { return }
        if let current = renamingGroup, current != id { commitFolderRename() }
        renamingGroup = id
        var snapshot = dataSource.snapshot()
        guard snapshot.indexOfItem(.group(id)) != nil else {
            renamingGroup = nil
            return
        }
        snapshot.reconfigureItems([.group(id)])
        dataSource.apply(snapshot, animatingDifferences: false)
        guard let indexPath = dataSource.indexPath(for: .group(id)) else { return }
        collectionView.layoutIfNeeded()
        let visible = collectionView.bounds.inset(by: collectionView.adjustedContentInset)
        if let frame = collectionView.layoutAttributesForItem(at: indexPath)?.frame, !visible.contains(frame) {
            collectionView.scrollToItem(at: indexPath, at: .centeredVertically, animated: false)
        }
    }

    /// Saves the name being edited, if any (the field reports it on ending).
    func commitFolderRename() {
        guard renamingGroup != nil, isViewLoaded else { return }
        collectionView.endEditing(true)
    }

    /// Cancels the rename in progress, keeping the old name. Returns `false`
    /// when nothing was being renamed.
    @discardableResult
    func cancelFolderRename() -> Bool {
        guard let id = renamingGroup else { return false }
        finishFolderRename(id, name: nil)
        return true
    }

    /// Ends a rename: saves `name` (blank keeps the old name), or just leaves
    /// edit mode for `nil`.
    private func finishFolderRename(_ id: UUID, name: String?) {
        guard renamingGroup == id else { return }
        renamingGroup = nil
        if let name {
            session.renameGroup(id, to: name)
        } else {
            var snapshot = dataSource.snapshot()
            guard snapshot.indexOfItem(.group(id)) != nil else { return }
            snapshot.reconfigureItems([.group(id)])
            dataSource.apply(snapshot, animatingDifferences: false)
        }
    }

    /// Tapping anywhere in the sidebar outside the name field saves it.
    @objc private func handleTapAway(_ tap: UITapGestureRecognizer) {
        guard let id = renamingGroup, tap.state == .ended else { return }
        if let indexPath = dataSource.indexPath(for: .group(id)),
           let cell = collectionView.cellForItem(at: indexPath) as? GroupRowCell,
           cell.bounds.contains(tap.location(in: cell)) {
            return
        }
        commitFolderRename()
    }

    // MARK: - Closing tabs

    /// − unloads a saved tab's page; × closes the tab into Archived Tabs.
    /// The session ignores the second tap of a double tap on −.
    private func closeButtonTapped(_ model: TabViewModel) {
        session.unloadOrArchiveTab(model.id)
    }

    /// A tap on a split row's segment focuses that pane; ⌘-tap attaches it
    /// to the assistant instead.
    private func selectPane(_ id: UUID, flags: UIKeyModifierFlags) {
        if renamingGroup != nil { commitFolderRename() }
        if flags.contains(.command) {
            delegate?.sidebarAskAboutTab(id)
            return
        }
        session.activateTab(id)
        delegate?.sidebarDidActivateTab()
    }

    /// The sidebar row an item lives in: a split's tabs share their split's.
    private func row(containing tab: UUID) -> SidebarItem {
        if let split = session.workspace.activeSpace.strip.split(of: tab), tabRows.contains(.split(split.id)) {
            return .split(split.id)
        }
        return .tab(tab)
    }

    /// Slides the tab list in from the direction of the new space.
    func animateSpaceChange(direction: Double) {
        guard isViewLoaded, direction != 0, ThemeCenter.shared.motionEnabled else { return }
        collectionView.transform = CGAffineTransform(translationX: direction * 22, y: 0)
        collectionView.alpha = 0.2
        let animator = UIViewPropertyAnimator(duration: 0.26, timingParameters: Metrics.easeOutQuint)
        animator.addAnimations {
            self.collectionView.transform = .identity
            self.collectionView.alpha = 1
        }
        animator.startAnimation()
    }

    // MARK: - Space swipe

    /// A horizontal swipe outside the tab rows (or a two-finger trackpad
    /// swipe anywhere) moves to the adjacent space, like Arc.
    private func addSpaceSwipe() {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handleSpaceSwipe(_:)))
        pan.allowedScrollTypesMask = .continuous
        pan.delegate = self
        view.addGestureRecognizer(pan)
    }

    @objc private func handleSpaceSwipe(_ pan: UIPanGestureRecognizer) {
        let translation = pan.translation(in: view).x
        switch pan.state {
        case .changed:
            collectionView.transform = CGAffineTransform(translationX: translation * 0.15, y: 0)
        case .ended:
            let velocity = pan.velocity(in: view).x
            UIView.animate(withDuration: 0.2) { self.collectionView.transform = .identity }
            if abs(translation) > 90 || abs(velocity) > 600 {
                // Content follows the fingers: swiping left shows the next space.
                session.switchToAdjacentSpace(forward: translation < 0)
            }
        default:
            UIView.animate(withDuration: 0.2) { self.collectionView.transform = .identity }
        }
    }

    // MARK: - Swipe actions

    private func trailingSwipeActions(at indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard case .tab(let id) = dataSource.itemIdentifier(for: indexPath),
              let model = session.tabViewModel(id) else { return nil }
        // Same as the row's button: unload a live saved tab, else close it.
        let title = model.unloads ? "Unload" : (model.saved ? "Archive" : "Close")
        let action = UIContextualAction(style: model.unloads ? .normal : .destructive, title: title) { [weak self] _, _, done in
            self?.session.unloadOrArchiveTab(id)
            done(true)
        }
        action.image = (model.unloads ? Icon.minus : Icon.close).image(13)
        action.accessibilityLabel = TabRowCell.closeLabel(model)
        if model.unloads { action.backgroundColor = ThemeCenter.shared.theme.textMuted.uiColor }
        return UISwipeActionsConfiguration(actions: [action])
    }

    private func leadingSwipeActions(at indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        guard case .tab(let id) = dataSource.itemIdentifier(for: indexPath),
              let model = session.tabViewModel(id) else { return nil }
        let action = UIContextualAction(style: .normal, title: model.pinned ? "Unpin" : "Pin") { [weak self] _, _, done in
            self?.session.togglePin(id)
            done(true)
        }
        action.image = Icon.star.image(13)
        action.backgroundColor = ThemeCenter.shared.theme.accent.uiColor
        return UISwipeActionsConfiguration(actions: [action])
    }
}

// MARK: - Selection and menus

extension SidebarViewController: UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        collectionView.deselectItem(at: indexPath, animated: false)
        let item = dataSource.itemIdentifier(for: indexPath)
        if let renaming = renamingGroup {
            commitFolderRename()
            // A tap on the folder being renamed only saves the name.
            if item == .group(renaming) { return }
        }
        switch item {
        case .favorite(let id), .tab(let id):
            session.activateTab(id)
            delegate?.sidebarDidActivateTab()
        case .group(let id):
            let collapsed = session.workspace.activeSpace.strip.group(id)?.collapsed ?? false
            session.setGroupCollapsed(id, !collapsed)
        case .divider:
            delegate?.sidebarNewTab()
        default:
            break
        }
    }

    func collectionView(_ collectionView: UICollectionView, contextMenuConfigurationForItemsAt indexPaths: [IndexPath], point: CGPoint) -> UIContextMenuConfiguration? {
        let menus = menus
        guard let indexPath = indexPaths.first, let item = dataSource.itemIdentifier(for: indexPath) else {
            // Empty space below the tabs.
            return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in menus.emptyAreaMenu() }
        }
        let menu: () -> UIMenu?
        switch item {
        case .favorite(let id): menu = { menus.favoriteMenu(tab: id) }
        case .tab(let id): menu = { menus.tabMenu(id) }
        case .split(let id):
            let cellPoint = collectionView.cellForItem(at: indexPath).map { collectionView.convert(point, to: $0) }
            let cell = collectionView.cellForItem(at: indexPath) as? SplitRowCell
            guard let tab = cellPoint.flatMap({ cell?.paneID(at: $0) }) ?? session.workspace.activeSpace.strip.split(id)?.tabs.first else { return nil }
            menu = { menus.splitPaneMenu(tab, split: id) }
        case .group(let id):
            if id == renamingGroup { return nil }
            menu = { menus.groupMenu(id) }
        case .header(let id): menu = { menus.spaceMenu(id) }
        case .divider, .empty: menu = { menus.emptyAreaMenu() }
        }
        return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in menu() }
    }
}

// MARK: - Drag and drop

extension SidebarViewController: UICollectionViewDragDelegate, UICollectionViewDropDelegate {
    func collectionView(_ collectionView: UICollectionView, itemsForBeginning session: UIDragSession, at indexPath: IndexPath) -> [UIDragItem] {
        let drag: SidebarDrag
        let provider: NSItemProvider
        switch dataSource.itemIdentifier(for: indexPath) {
        case .tab(let id):
            drag = .tab(id)
            let url = self.session.workspace.tab(id)?.url ?? ""
            provider = URL(string: url).map { NSItemProvider(object: $0 as NSURL) } ?? NSItemProvider()
        case .group(let id):
            drag = .group(id, space: self.session.workspace.activeSpaceID)
            provider = NSItemProvider()
        case .split(let id):
            // Dragging a split moves all of it (by its first pane).
            guard let first = self.session.workspace.activeSpace.strip.split(id)?.tabs.first else { return [] }
            drag = .tab(first)
            let url = self.session.workspace.tab(first)?.url ?? ""
            provider = URL(string: url).map { NSItemProvider(object: $0 as NSURL) } ?? NSItemProvider()
        default:
            return []
        }
        let item = UIDragItem(itemProvider: provider)
        item.localObject = SidebarDragBox(drag)
        return [item]
    }

    func collectionView(_ collectionView: UICollectionView, dropSessionDidUpdate session: UIDropSession, withDestinationIndexPath destination: IndexPath?) -> UICollectionViewDropProposal {
        guard let box = session.localDragSession?.items.first?.localObject as? SidebarDragBox else {
            return UICollectionViewDropProposal(operation: .forbidden)
        }
        guard let destination else { return UICollectionViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath) }
        switch SidebarSection(rawValue: destination.section) {
        case .favorites:
            if case .tab = box.drag { return UICollectionViewDropProposal(operation: .move, intent: .insertIntoDestinationIndexPath) }
            return UICollectionViewDropProposal(operation: .forbidden)
        case .header:
            return UICollectionViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
        default:
            if case .tab = box.drag, destination.item < tabRows.count, case .group = tabRows[destination.item] {
                return UICollectionViewDropProposal(operation: .move, intent: .insertIntoDestinationIndexPath)
            }
            return UICollectionViewDropProposal(operation: .move, intent: .insertAtDestinationIndexPath)
        }
    }

    func collectionView(_ collectionView: UICollectionView, performDropWith coordinator: UICollectionViewDropCoordinator) {
        guard let box = coordinator.session.localDragSession?.items.first?.localObject as? SidebarDragBox else { return }
        let destination = coordinator.destinationIndexPath
        let section = destination.flatMap { SidebarSection(rawValue: $0.section) } ?? .tabs
        if section == .favorites, case .tab(let id) = box.drag {
            session.addFavorite(id)
            return
        }
        let index = section == .header ? 0 : (destination?.item ?? tabRows.count)
        if coordinator.proposal.intent == .insertIntoDestinationIndexPath, index < tabRows.count,
           case .group(let group) = tabRows[index], case .tab(let id) = box.drag {
            session.dropTab(id, at: .inGroup(group, nil))
            return
        }
        // The index is where the item lands once lifted out of its old place.
        let dragged: SidebarItem = switch box.drag {
        case .tab(let id): row(containing: id)
        case .group(let id, _): .group(id)
        }
        let rows = tabRows.filter { $0 != dragged }
        let anchor: SidebarItem? = index < rows.count ? rows[index] : nil
        switch box.drag {
        case .tab(let id):
            let placement: TabPlacement = switch anchor {
            case .tab(let other): .beforeTab(other)
            case .split(let split): session.workspace.activeSpace.strip.split(split)?.tabs.first.map(TabPlacement.beforeTab) ?? .sectionEnd(.unpinned)
            case .group(let group): .beforeGroup(group)
            case .divider: .sectionEnd(.pinned)
            default: .sectionEnd(.unpinned)
            }
            session.dropTab(id, at: placement)
        case .group(let id, let space):
            guard space == session.workspace.activeSpaceID else { return }
            let placement: GroupPlacement = switch anchor {
            case .tab(let other): .beforeItem(.tab(other))
            case .split(let split): session.workspace.activeSpace.strip.split(split)?.tabs.first.map { GroupPlacement.beforeItem(.tab($0)) } ?? .sectionEnd(.unpinned)
            case .group(let group): .beforeItem(.group(group))
            case .divider: .sectionEnd(.pinned)
            default: .sectionEnd(.unpinned)
            }
            session.dropGroup(id, at: placement)
        }
    }

    func collectionView(_ collectionView: UICollectionView, dragSessionWillBegin session: UIDragSession) {
        if (session.items.first?.localObject as? SidebarDragBox).map({ if case .tab = $0.drag { true } else { false } }) == true {
            delegate?.sidebarTabDrag(active: true)
        }
    }

    func collectionView(_ collectionView: UICollectionView, dragSessionDidEnd session: UIDragSession) {
        delegate?.sidebarTabDrag(active: false)
    }

    func collectionView(_ collectionView: UICollectionView, dragPreviewParametersForItemAt indexPath: IndexPath) -> UIDragPreviewParameters? {
        let parameters = UIDragPreviewParameters()
        if let cell = collectionView.cellForItem(at: indexPath) {
            parameters.visiblePath = UIBezierPath(roundedRect: cell.bounds.insetBy(dx: 0, dy: 1), cornerRadius: Metrics.rowRadius)
        }
        return parameters
    }
}

// MARK: - Gestures

extension SidebarViewController: UIGestureRecognizerDelegate {
    func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
        guard let pan = recognizer as? UIPanGestureRecognizer else { return true }
        let velocity = pan.velocity(in: view)
        guard abs(velocity.x) > abs(velocity.y) * 1.4 else { return false }
        // Touch swipes on tab rows are for the row's swipe actions.
        if pan.numberOfTouches > 0 {
            let point = pan.location(in: collectionView)
            if let indexPath = collectionView.indexPathForItem(at: point), indexPath.section == SidebarSection.tabs.rawValue {
                return false
            }
        }
        return session.workspace.spaces.count > 1
    }

    func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        other == collectionView.panGestureRecognizer
    }
}

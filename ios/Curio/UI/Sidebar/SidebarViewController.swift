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
            cell.onClose = { [weak self] model in
                if model.pinned { self?.session.unloadTab(model.id) } else { self?.session.closeTab(model.id) }
            }
        }
        let groupCell = UICollectionView.CellRegistration<GroupRowCell, UUID> { [weak self] cell, _, id in
            guard let self, let group = session.workspace.activeSpace.strip.group(id) else { return }
            cell.configure(group, height: rowHeight - 4)
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
        var snapshot = NSDiffableDataSourceSnapshot<SidebarSection, SidebarItem>()
        snapshot.appendSections(SidebarSection.allCases)
        snapshot.appendItems(workspace.favorites.map { .favorite($0.tab.id) }, toSection: .favorites)
        snapshot.appendItems([.header(space.id)], toSection: .header)
        var rows: [SidebarItem] = []
        var dividerDone = false
        for row in space.strip.rows(alwaysShow: space.activeTab) {
            if row.section == .unpinned && !dividerDone {
                rows.append(.divider)
                dividerDone = true
            }
            switch row {
            case .tab(let id, _, _): rows.append(.tab(id))
            case .group(let id, _): rows.append(.group(id))
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
        let items = [SidebarItem.tab(id), .favorite(id)].filter { snapshot.indexOfItem($0) != nil }
        guard !items.isEmpty else { return }
        snapshot.reconfigureItems(items)
        dataSource.apply(snapshot, animatingDifferences: false)
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
        let action = UIContextualAction(style: model.pinned ? .normal : .destructive, title: model.pinned ? "Unload" : "Close") { [weak self] _, _, done in
            self?.session.closeOrUnloadTab(id)
            done(true)
        }
        action.image = (model.pinned ? Icon.minus : Icon.close).image(13)
        if model.pinned { action.backgroundColor = ThemeCenter.shared.theme.textMuted.uiColor }
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
        switch dataSource.itemIdentifier(for: indexPath) {
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
        guard let indexPath = indexPaths.first, let item = dataSource.itemIdentifier(for: indexPath) else { return nil }
        let menus = menus
        let menu: () -> UIMenu?
        switch item {
        case .favorite(let id): menu = { menus.favoriteMenu(tab: id) }
        case .tab(let id): menu = { menus.tabMenu(id) }
        case .group(let id): menu = { menus.groupMenu(id) }
        case .header(let id): menu = { menus.spaceMenu(id) }
        default: return nil
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
        case .tab(let id): .tab(id)
        case .group(let id, _): .group(id)
        }
        let rows = tabRows.filter { $0 != dragged }
        let anchor: SidebarItem? = index < rows.count ? rows[index] : nil
        switch box.drag {
        case .tab(let id):
            let placement: TabPlacement = switch anchor {
            case .tab(let other): .beforeTab(other)
            case .group(let group): .beforeGroup(group)
            case .divider: .sectionEnd(.pinned)
            default: .sectionEnd(.unpinned)
            }
            session.dropTab(id, at: placement)
        case .group(let id, let space):
            guard space == session.workspace.activeSpaceID else { return }
            let placement: GroupPlacement = switch anchor {
            case .tab(let other): .beforeItem(.tab(other))
            case .group(let group): .beforeItem(.group(group))
            case .divider: .sectionEnd(.pinned)
            default: .sectionEnd(.unpinned)
            }
            session.dropGroup(id, at: placement)
        }
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

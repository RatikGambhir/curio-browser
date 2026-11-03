import UIKit

/// The horizontal tab strip: favorites and pinned tabs as icons, then the
/// regular tabs with their groups, and a New Tab button.
final class TabStripView: UIView, UIDropInteractionDelegate {
    private let session: BrowserSession
    private let scroll = UIScrollView()
    private let stack = UIStackView()
    private let endZone = UIView()
    var onCommand: ((CurioCommand) -> Void)?
    var onAskAboutTab: ((UUID) -> Void)?

    init(session: BrowserSession) {
        self.session = session
        super.init(frame: .zero)
        scroll.showsHorizontalScrollIndicator = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        stack.spacing = 3
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 38),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -10),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
            stack.widthAnchor.constraint(greaterThanOrEqualTo: scroll.frameLayoutGuide.widthAnchor, constant: -20),
        ])
        endZone.addInteraction(UIDropInteraction(delegate: self))
        endZone.setContentHuggingPriority(.defaultLow, for: .horizontal)
        NSLayoutConstraint.activate([
            endZone.widthAnchor.constraint(greaterThanOrEqualToConstant: 24),
            endZone.heightAnchor.constraint(equalToConstant: 38),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func reload() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let workspace = session.workspace
        let space = workspace.activeSpace
        var compact = workspace.favorites.map(\.tab.id)
        for item in space.strip.items(.pinned) {
            switch item {
            case .tab(let id): compact.append(id)
            case .group(let id): compact += space.strip.group(id)?.tabs ?? []
            }
        }
        for id in compact {
            guard let model = session.tabViewModel(id) else { continue }
            let tile = StripIconTile(model: model)
            tile.addAction(UIAction { [weak session] _ in session?.activateTab(id) }, for: .primaryActionTriggered)
            stack.addArrangedSubview(tile)
        }
        if !compact.isEmpty {
            let divider = DividerView(vertical: true)
            divider.heightAnchor.constraint(equalToConstant: 18).isActive = true
            stack.addArrangedSubview(divider)
            stack.setCustomSpacing(8, after: stack.arrangedSubviews[stack.arrangedSubviews.count - 2])
            stack.setCustomSpacing(8, after: divider)
        }
        var tabViews: [StripTabView] = []
        for item in space.strip.items(.unpinned) {
            switch item {
            case .tab(let id):
                if let view = makeTab(id, groupColor: nil) { tabViews.append(view) }
            case .group(let groupID):
                guard let group = space.strip.group(groupID) else { continue }
                let label = StripGroupLabel(group: group)
                label.addAction(UIAction { [weak session] _ in session?.setGroupCollapsed(groupID, !group.collapsed) }, for: .primaryActionTriggered)
                label.addInteraction(UIDropInteraction(delegate: self))
                stack.addArrangedSubview(label)
                for id in group.tabs where !group.collapsed || id == space.activeTab {
                    if let view = makeTab(id, groupColor: CurioTheme.swatch(group.color)) { tabViews.append(view) }
                }
            }
        }
        if let first = tabViews.first {
            for view in tabViews {
                NSLayoutConstraint.activate([
                    view.widthAnchor.constraint(greaterThanOrEqualToConstant: 96),
                    view.widthAnchor.constraint(lessThanOrEqualToConstant: 220),
                    view.widthAnchor.constraint(equalTo: first.widthAnchor),
                ])
            }
        }
        let newTab = IconButton(.plus, label: "New Tab", action: UIAction { [weak self] _ in self?.onCommand?(.newTab) })
        stack.addArrangedSubview(newTab)
        stack.addArrangedSubview(endZone)
        if let first = tabViews.first {
            let grow = first.widthAnchor.constraint(equalToConstant: 220)
            grow.priority = .defaultLow
            grow.isActive = true
        }
    }

    private func makeTab(_ id: UUID, groupColor: UIColor?) -> StripTabView? {
        guard let model = session.tabViewModel(id) else { return nil }
        let view = StripTabView(model: model, groupColor: groupColor)
        view.addAction(UIAction { [weak session] _ in session?.activateTab(id) }, for: .primaryActionTriggered)
        view.onClose = { [weak session] in session?.closeTab(id) }
        view.menuProvider = { [weak self] in
            guard let self else { return UIMenu() }
            let session = session
            return UIMenu(children: [
                UIMenu(options: .displayInline, children: [
                    UIAction(title: "Pin Tab", image: Icon.star.image()) { _ in session.togglePin(id) },
                    UIAction(title: "Add to Favorites", image: Icon.heart.image()) { _ in session.addFavorite(id) },
                    UIAction(title: "Ask Curio About This Tab", image: Icon.sparkles.image()) { [weak self] _ in self?.onAskAboutTab?(id) },
                ]),
                UIAction(title: "Close Tab", image: Icon.close.image(), attributes: .destructive) { _ in session.closeTab(id) },
            ])
        }
        view.addInteraction(UIDropInteraction(delegate: self))
        stack.addArrangedSubview(view)
        return view
    }

    /// Updates one tab's title, icon and loading state in place.
    func refreshTab(_ id: UUID) {
        guard let model = session.tabViewModel(id) else { return }
        for case let view as StripTabView in stack.arrangedSubviews where view.tabID == id {
            view.configure(model)
        }
    }

    // MARK: Dropping tabs

    func dropInteraction(_ interaction: UIDropInteraction, canHandle session: UIDropSession) -> Bool {
        session.localDragSession?.items.first?.localObject is SidebarDragBox
    }

    func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: UIDropSession) -> UIDropProposal {
        UIDropProposal(operation: .move)
    }

    func dropInteraction(_ interaction: UIDropInteraction, performDrop dropSession: UIDropSession) {
        guard let box = dropSession.localDragSession?.items.first?.localObject as? SidebarDragBox,
              case .tab(let id) = box.drag else { return }
        switch interaction.view {
        case let tab as StripTabView: session.dropTab(id, at: .beforeTab(tab.tabID))
        case let group as StripGroupLabel: session.dropTab(id, at: .inGroup(group.groupID, nil))
        default: session.dropTab(id, at: .sectionEnd(.unpinned))
        }
    }
}

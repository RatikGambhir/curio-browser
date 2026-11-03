import UIKit

/// The sidebar's bottom row: library, the space switcher dots, new space and
/// settings.
final class SidebarFooterView: UIView, ThemeObserving, UIDropInteractionDelegate {
    let libraryButton = IconButton(.downloadCircle, size: .small, label: "Library")
    let newSpaceButton = IconButton(.plus, size: .small, label: "New Space")
    let settingsButton = IconButton(.settings, size: .small, label: "Settings")
    private let dots = UIStackView()
    private let scroll = UIScrollView()
    private let divider = DividerView()
    private var session: BrowserSession?

    init() {
        super.init(frame: .zero)
        libraryButton.setIcon(.library, label: "Library")
        dots.axis = .horizontal
        dots.spacing = 2
        dots.alignment = .center
        dots.translatesAutoresizingMaskIntoConstraints = false
        scroll.showsHorizontalScrollIndicator = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(dots)
        let stack = UIStackView(arrangedSubviews: [libraryButton, scroll, newSpaceButton, settingsButton])
        stack.spacing = 4
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(divider)
        addSubview(stack)
        let centerDots = dots.centerXAnchor.constraint(equalTo: scroll.frameLayoutGuide.centerXAnchor)
        centerDots.priority = .defaultLow
        NSLayoutConstraint.activate([
            divider.topAnchor.constraint(equalTo: topAnchor),
            divider.leadingAnchor.constraint(equalTo: leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            stack.topAnchor.constraint(equalTo: divider.bottomAnchor),
            stack.heightAnchor.constraint(equalToConstant: 44),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            scroll.heightAnchor.constraint(equalToConstant: 36),
            dots.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            dots.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            dots.leadingAnchor.constraint(greaterThanOrEqualTo: scroll.contentLayoutGuide.leadingAnchor),
            dots.trailingAnchor.constraint(lessThanOrEqualTo: scroll.contentLayoutGuide.trailingAnchor),
            dots.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
            scroll.contentLayoutGuide.widthAnchor.constraint(greaterThanOrEqualTo: scroll.frameLayoutGuide.widthAnchor),
            scroll.contentLayoutGuide.widthAnchor.constraint(greaterThanOrEqualTo: dots.widthAnchor),
            centerDots,
        ])
        ThemeCenter.shared.observe(self)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func configure(session: BrowserSession, menus: SidebarMenus) {
        self.session = session
        dots.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let active = session.workspace.activeSpaceID
        for space in session.workspace.spaces {
            let id = space.id
            let dot = SpaceDotButton(space: space, active: id == active, action: UIAction { [weak session] _ in
                session?.switchSpace(id)
            })
            dot.menuProvider = { menus.spaceMenu(id) }
            dot.addInteraction(UIDropInteraction(delegate: self))
            dots.addArrangedSubview(dot)
        }
        libraryButton.isToggled = session.services.downloads.hasActive
    }

    func themeDidChange(_ theme: CurioTheme) {}

    // MARK: Dropping tabs on a space

    func dropInteraction(_ interaction: UIDropInteraction, canHandle session: UIDropSession) -> Bool {
        session.localDragSession?.items.first?.localObject is SidebarDragBox
    }

    func dropInteraction(_ interaction: UIDropInteraction, sessionDidUpdate session: UIDropSession) -> UIDropProposal {
        (interaction.view as? SpaceDotButton)?.setDropHighlight(true)
        return UIDropProposal(operation: .move)
    }

    func dropInteraction(_ interaction: UIDropInteraction, sessionDidExit session: UIDropSession) {
        (interaction.view as? SpaceDotButton)?.setDropHighlight(false)
    }

    func dropInteraction(_ interaction: UIDropInteraction, performDrop dropSession: UIDropSession) {
        guard let dot = interaction.view as? SpaceDotButton,
              let box = dropSession.localDragSession?.items.first?.localObject as? SidebarDragBox,
              let session else { return }
        dot.setDropHighlight(false)
        switch box.drag {
        case .tab(let id): session.moveTabToSpace(id, dot.spaceID)
        case .group(let id, let from): session.moveGroupToSpace(id, from: from, to: dot.spaceID)
        }
    }

    func dropInteraction(_ interaction: UIDropInteraction, concludeDrop session: UIDropSession) {
        (interaction.view as? SpaceDotButton)?.setDropHighlight(false)
    }
}

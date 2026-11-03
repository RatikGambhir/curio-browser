import UIKit

/// The sidebar's context menus, matching the desktop's.
struct SidebarMenus {
    let session: BrowserSession
    weak var delegate: SidebarDelegate?

    private func spaceLabel(_ space: Space) -> String { "\(space.icon)  \(space.name)" }

    /// Edit, ask, move left/right, delete.
    func spaceMenu(_ id: UUID) -> UIMenu {
        let session = session
        let delegate = delegate
        return UIMenu(children: [
            UIMenu(options: .displayInline, children: [
                UIAction(title: "Edit Space…", image: Icon.palette.image()) { _ in delegate?.sidebarEditSpace(id) },
                UIAction(title: "Ask Curio About This Space", image: Icon.sparkles.image()) { _ in delegate?.sidebarAskAboutSpace(id) },
            ]),
            UIMenu(options: .displayInline, children: [
                UIAction(title: "Move Left", image: Icon.chevronLeft.image()) { _ in session.shiftSpace(id, by: -1) },
                UIAction(title: "Move Right", image: Icon.chevronRight.image()) { _ in session.shiftSpace(id, by: 1) },
            ]),
            UIAction(title: "Delete Space…", image: Icon.trash.image(), attributes: .destructive) { _ in delegate?.sidebarConfirmDeleteSpace(id) },
        ])
    }

    func tabMenu(_ id: UUID) -> UIMenu {
        let session = session
        let delegate = delegate
        let strip = session.workspace.activeSpace.strip
        let pinned = strip.isPinned(id)
        let group = strip.location(of: id)?.group
        let groups = strip.groups.sorted { $0.name < $1.name }
        var groupItems: [UIMenuElement] = [UIAction(title: "New Group…", image: Icon.folderPlus.image()) { _ in
            if let group = session.newGroup(with: [id]) { delegate?.sidebarRenameGroup(group) }
        }]
        if !groups.isEmpty {
            groupItems.append(UIMenu(options: .displayInline, children: groups.map { g in
                UIAction(title: g.name, image: Icon.folder.image(), state: group == g.id ? .on : .off) { _ in
                    session.dropTab(id, at: .inGroup(g.id, nil))
                }
            }))
        }
        var organize: [UIMenuElement] = [UIMenu(title: "Move to Group", image: Icon.folder.image(), children: groupItems)]
        if group != nil {
            organize.append(UIAction(title: "Remove from Group", image: Icon.folderMinus.image()) { _ in session.removeFromGroup(id) })
        }
        let otherSpaces = session.workspace.spaces.filter { $0.id != session.workspace.activeSpaceID }
        if !otherSpaces.isEmpty {
            organize.append(UIMenu(title: "Move to Space", image: Icon.layers.image(), children: otherSpaces.map { space in
                UIAction(title: spaceLabel(space)) { _ in session.moveTabToSpace(id, space.id) }
            }))
        }
        return UIMenu(children: [
            UIMenu(options: .displayInline, children: [
                UIAction(title: pinned ? "Unpin Tab" : "Pin Tab", image: Icon.star.image()) { _ in session.togglePin(id) },
                UIAction(title: "Add to Favorites", image: Icon.heart.image()) { _ in session.addFavorite(id) },
                UIAction(title: "Duplicate Tab", image: Icon.copy.image()) { _ in session.duplicateTab(id) },
                UIAction(title: "Copy Link", image: Icon.link.image()) { _ in
                    if let url = session.workspace.tab(id)?.url { UIPasteboard.general.string = url }
                },
                UIAction(title: "Ask Curio About This Tab", image: Icon.sparkles.image()) { _ in delegate?.sidebarAskAboutTab(id) },
            ]),
            UIMenu(options: .displayInline, children: organize),
            UIMenu(options: .displayInline, children: [
                UIAction(title: pinned ? "Unload Tab" : "Close Tab", image: Icon.close.image(), attributes: pinned ? [] : .destructive) { _ in
                    session.closeOrUnloadTab(id)
                },
                UIAction(title: "Close Other Tabs", image: Icon.xCircle.image()) { _ in session.closeOtherTabs(keeping: id) },
            ]),
        ])
    }

    func groupMenu(_ id: UUID) -> UIMenu {
        let session = session
        let delegate = delegate
        let space = session.workspace.activeSpaceID
        let otherSpaces = session.workspace.spaces.filter { $0.id != space }
        let colors = AccentColor.allCases.map { color in
            UIAction(title: color.label, image: Self.swatchImage(color)) { _ in session.setGroupColor(id, color) }
        }
        var organize: [UIMenuElement] = [
            UIAction(title: "Rename Group…", image: Icon.pencil.image()) { _ in delegate?.sidebarRenameGroup(id) },
            UIMenu(title: "Color", image: Icon.palette.image(), children: colors),
        ]
        if !otherSpaces.isEmpty {
            organize.append(UIMenu(title: "Move Group to Space", image: Icon.layers.image(), children: otherSpaces.map { target in
                UIAction(title: spaceLabel(target)) { _ in session.moveGroupToSpace(id, from: space, to: target.id) }
            }))
        }
        return UIMenu(children: [
            UIMenu(options: .displayInline, children: organize),
            UIMenu(options: .displayInline, children: [
                UIAction(title: "Ungroup Tabs", image: Icon.folderMinus.image()) { _ in session.ungroup(id) },
                UIAction(title: "Close Group and Tabs", image: Icon.trash.image(), attributes: .destructive) { _ in session.closeGroup(id) },
            ]),
        ])
    }

    func favoriteMenu(tab: UUID) -> UIMenu {
        let session = session
        let favorite = session.workspace.favorites.first { $0.tab.id == tab }?.id
        return UIMenu(children: [
            UIAction(title: "Go to Saved Address", image: Icon.undo.image()) { _ in session.resetFavorite(tab) },
            UIMenu(options: .displayInline, children: [
                UIAction(title: "Remove from Favorites", image: Icon.trash.image(), attributes: .destructive) { _ in
                    if let favorite { session.removeFavorite(favorite) }
                },
            ]),
        ])
    }

    /// A filled circle in an accent color, for menus.
    static func swatchImage(_ color: AccentColor) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 12, height: 12)).image { context in
            CurioTheme.swatch(color).setFill()
            context.cgContext.fillEllipse(in: CGRect(x: 0, y: 0, width: 12, height: 12))
        }.withRenderingMode(.alwaysOriginal)
    }
}

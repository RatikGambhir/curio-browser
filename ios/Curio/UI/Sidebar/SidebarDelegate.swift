import Foundation

/// Sidebar requests the browser screen handles (dialogs and other panels).
protocol SidebarDelegate: AnyObject {
    func sidebarDidActivateTab()
    func sidebarNewTab()
    func sidebarEditSpace(_ id: UUID?)
    func sidebarConfirmDeleteSpace(_ id: UUID)
    func sidebarNewFolder()
    /// Edit a folder's name in its row (the sidebar may need to be shown).
    func sidebarRenameFolder(_ id: UUID)
    func sidebarAskAboutTab(_ id: UUID)
    func sidebarAskAboutSpace(_ id: UUID)
    func sidebarToggleLibrary()
    func sidebarOpenSettings()
    /// A tab drag started or ended (the page shows split drop zones).
    func sidebarTabDrag(active: Bool)
}

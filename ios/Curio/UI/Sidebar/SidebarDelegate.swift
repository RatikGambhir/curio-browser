import Foundation

/// Sidebar requests the browser screen handles (dialogs and other panels).
protocol SidebarDelegate: AnyObject {
    func sidebarDidActivateTab()
    func sidebarNewTab()
    func sidebarEditSpace(_ id: UUID?)
    func sidebarConfirmDeleteSpace(_ id: UUID)
    func sidebarRenameGroup(_ id: UUID)
    func sidebarAskAboutTab(_ id: UUID)
    func sidebarAskAboutSpace(_ id: UUID)
    func sidebarToggleLibrary()
    func sidebarOpenSettings()
}

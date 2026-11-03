import QuickLook
import UIKit

// MARK: - Session events

extension BrowserViewController: BrowserSessionDelegate {
    func session(_ session: BrowserSession, didChange change: SessionChange) {
        guard isViewLoaded else { return }
        switch change {
        case .tabs:
            sidebar.reload()
            if !verticalTabs { tabStrip.reload() }
            if session.activeTab?.isNewTabPage ?? true { page.refreshNewTabPage() }
            assistant.refreshContext()
            refreshBars()
            if libraryOpen { library.reload() }
        case .activeTab:
            page.showActiveTab()
            assistant.refreshContext()
            refreshBars()
        case .page(let id):
            sidebar.refreshTab(id)
            if !verticalTabs { tabStrip.refreshTab(id) }
            if id == session.activeTabID {
                refreshBars()
                page.refreshOverlays()
                if page.view.window != nil, session.activeLiveTab?.webView?.superview == nil, !(session.activeTab?.isNewTabPage ?? true) {
                    page.showActiveTab()
                }
            }
        case .space(let direction):
            applyTheme(animated: true)
            sidebar.animateSpaceChange(direction: direction)
            if !verticalTabs { tabStrip.reload() }
        case .selection:
            page.refreshOverlays()
        case .downloads:
            sidebar.reload(animated: false, reconfigure: false)
            if libraryOpen { library.reload() }
            var top = presentedViewController
            while let current = top {
                ((current as? UINavigationController)?.topViewController as? DownloadsViewController)?.reload()
                top = current.presentedViewController
            }
        }
    }

    func session(_ session: BrowserSession, showToast message: String, title: String?, kind: ToastPresenter.Kind) {
        toasts?.show(message, title: title, kind: kind)
    }

    /// Links to other apps (mailto:, zoommtg:, …) ask before opening.
    func session(_ session: BrowserSession, confirmExternalOpen url: URL) {
        let scheme = url.scheme ?? ""
        let alert = UIAlertController(title: "Open “\(scheme):” link in another app?", message: String(url.absoluteString.prefix(160)), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Open", style: .default) { _ in UIApplication.shared.open(url) })
        presentFromTop(alert)
    }

    func session(_ session: BrowserSession, present alert: UIAlertController) {
        presentFromTop(alert)
    }

    func session(_ session: BrowserSession, askAboutSelection action: QuickAction?) {
        askAboutSelection(action)
    }
}

// MARK: - Sidebar

extension BrowserViewController: SidebarDelegate {
    func sidebarDidActivateTab() {
        if isCompact { setDrawer(open: false) }
    }

    func sidebarNewTab() {
        perform(.newTab)
    }

    func sidebarEditSpace(_ id: UUID?) {
        setDrawer(open: false)
        let space = id.flatMap(session.workspace.space)
        let defaults = session.newSpaceDefaults
        let editor = SpaceEditorViewController(spaceID: id, name: space?.name ?? "", icon: space?.icon ?? defaults.icon, color: space?.color ?? defaults.color)
        editor.onSave = { [weak self] name, icon, color in
            guard let self else { return }
            session.saveSpace(id, name: name, icon: icon, color: color)
            if id == nil {
                Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(450))
                    self?.openCommandBar(.newTab)
                }
            }
        }
        presentFromTop(SheetStyle.wrap(editor, compact: isCompact, size: CGSize(width: 440, height: 520), detents: [.large()]))
    }

    func sidebarConfirmDeleteSpace(_ id: UUID) {
        guard session.workspace.spaces.count > 1 else {
            toasts?.show("Curio needs at least one space.")
            return
        }
        guard let space = session.workspace.space(id) else { return }
        let alert = UIAlertController(
            title: "Delete “\(space.name)”?",
            message: "Its \(space.strip.count) tabs, pinned tabs and folders will be closed. This can’t be undone.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete Space", style: .destructive) { [weak self] _ in self?.session.deleteSpace(id) })
        presentFromTop(alert)
    }

    func sidebarRenameGroup(_ id: UUID) {
        let current = session.workspace.activeSpace.strip.group(id)?.name ?? ""
        let alert = UIAlertController(title: "Rename Group", message: nil, preferredStyle: .alert)
        alert.addTextField { field in
            field.text = current
            field.placeholder = "Group name"
            field.autocapitalizationType = .words
            field.clearButtonMode = .whileEditing
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        let rename = UIAlertAction(title: "Rename", style: .default) { [weak self, weak alert] _ in
            self?.session.renameGroup(id, to: alert?.textFields?.first?.text ?? "")
        }
        alert.addAction(rename)
        alert.preferredAction = rename
        presentFromTop(alert)
    }

    func sidebarAskAboutTab(_ id: UUID) {
        guard let tab = session.contextTab(id) else { return }
        showAssistant()
        assistant.attachTab(tab)
    }

    /// Opens the assistant on a space, comparing its tabs.
    func sidebarAskAboutSpace(_ id: UUID) {
        session.switchSpace(id)
        showAssistant(focus: false)
        assistant.quickAction(.compareTabs)
    }

    func sidebarToggleLibrary() {
        toggleLibrary()
    }

    func sidebarOpenSettings() {
        openSettings(nil)
    }
}

// MARK: - Assistant

extension BrowserViewController: AssistantDelegate {
    func assistantDidClose() {
        hideAssistant()
    }

    func assistantOpenSettings() {
        openSettings(.ai)
    }

    func assistantOpenURL(_ url: URL) {
        guard url.scheme?.hasPrefix("http") == true else { return }
        if isCompact { dismissAssistantSheet() }
        if isCompact { assistantOpen = false }
        session.openInNewTab(url.absoluteString)
    }
}

// MARK: - Library

extension BrowserViewController: LibraryDelegate {
    func libraryDidClose() {
        if let sheet = presentedViewController as? LibraryViewController {
            sheet.dismiss(animated: true)
        } else if libraryOpen {
            toggleLibrary()
        }
    }

    func libraryPreview(_ url: URL) {
        let preview = QLPreviewController()
        let source = PreviewSource(url: url)
        previewSource = source
        preview.dataSource = source
        presentFromTop(preview)
    }
}

/// Feeds one file to Quick Look.
final class PreviewSource: NSObject, QLPreviewControllerDataSource {
    let url: URL

    init(url: URL) {
        self.url = url
    }

    func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        url as NSURL
    }
}

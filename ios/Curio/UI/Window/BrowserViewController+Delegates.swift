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
            }
            if page.view.window != nil, session.visibleTabIDs.contains(id) {
                page.refreshPane(id)
            }
        case .space(let direction):
            applyTheme(animated: true)
            sidebar.animateSpaceChange(direction: direction)
            if !verticalTabs { tabStrip.reload() }
        case .selection:
            page.refreshOverlays()
        case .split:
            page.refreshSplitLayout()
        case .downloads:
            sidebar.reload(animated: false, reconfigure: false)
            if libraryOpen { library.reloadDownloads() }
            var top = presentedViewController
            while let current = top {
                ((current as? UINavigationController)?.topViewController as? DownloadsViewController)?.reload()
                (current as? LibraryViewController)?.reloadDownloads()
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
        let editor = SpaceEditorViewController(spaceID: id, name: space?.name ?? "", icon: space?.icon ?? defaults.icon, gradient: space?.gradient ?? defaults.gradient)
        editor.onSave = { [weak self] name, icon, gradient in
            guard let self else { return }
            session.saveSpace(id, name: name, icon: icon, gradient: gradient)
            if id == nil {
                Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(450))
                    self?.openCommandBar(.newTab)
                }
            }
        }
        presentFromTop(SheetStyle.wrap(editor, compact: isCompact, size: CGSize(width: 440, height: 640), detents: [.large()]))
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

    func sidebarNewFolder() {
        newFolder()
    }

    func sidebarRenameFolder(_ id: UUID) {
        beginFolderRename(id)
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

    func sidebarTabDrag(active: Bool) {
        page.setDropZonesActive(active)
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

    func librarySheetDidSelect(_ section: LibrarySection) {
        library.select(section)
    }

    func libraryPreview(_ url: URL, retaining export: MediaExport?) {
        let preview = QLPreviewController()
        let source = PreviewSource(url: url, export: export) { [weak self] in self?.previewSource = nil }
        previewSource = source
        preview.dataSource = source
        let sheet = SheetStyle.wrap(preview, compact: isCompact, size: CGSize(width: 640, height: 720))
        preview.navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Close", primaryAction: UIAction { [weak sheet, weak source] _ in
            sheet?.dismiss(animated: true) { source?.didDismiss() }
        })
        sheet.presentationController?.delegate = source
        presentFromTop(sheet)
    }
}

/// Feeds one file to Quick Look.
final class PreviewSource: NSObject, QLPreviewControllerDataSource, UIAdaptivePresentationControllerDelegate {
    private let url: URL
    private let export: MediaExport?
    let didDismiss: () -> Void

    init(url: URL, export: MediaExport?, didDismiss: @escaping () -> Void) {
        self.url = url
        self.export = export
        self.didDismiss = didDismiss
    }

    func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }

    func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem {
        url as NSURL
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        didDismiss()
    }
}

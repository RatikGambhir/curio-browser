import Foundation

/// Saves and restores the session and archive.
final class WorkspaceStore {
    private let file: JSONFile<Workspace>

    init(url: URL = StoragePaths.file("workspace.json")) {
        file = JSONFile(url: url)
    }

    func load(restoreSession: Bool) -> Workspace {
        guard var workspace = file.load() else {
            // The archive can still be read if another workspace field fails to decode.
            let archive = JSONFile<Archive>(url: file.url).load()
            return .firstRun(closed: archive?.closed ?? [])
        }
        guard !restoreSession else { return workspace }

        // Keep spaces, folders, pinned tabs, favorites and the archive.
        for space in workspace.spaces {
            for case .tab(let id) in space.strip.items(.unpinned) {
                _ = workspace.closeTab(id, remember: false)
            }
            workspace.updateSpace(space.id) { $0.activeTab = $0.strip.orderedTabIDs.first }
        }
        return Workspace(spaces: workspace.spaces, favorites: workspace.favorites, closed: workspace.closedTabs)
    }

    func save(_ workspace: Workspace) { file.save(workspace) }
    func saveNow(_ workspace: Workspace) { file.saveNow(workspace) }

    private struct Archive: Codable {
        let closed: [ClosedTab]?
    }
}

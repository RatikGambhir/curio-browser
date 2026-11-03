import Foundation

/// Saves and restores the session (spaces, tabs, favorites).
final class WorkspaceStore {
    private let file = JSONFile<Workspace>("workspace.json")

    func load() -> Workspace? { file.load() }
    func save(_ workspace: Workspace) { file.save(workspace) }
    func saveNow(_ workspace: Workspace) { file.saveNow(workspace) }
}

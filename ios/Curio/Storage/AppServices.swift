import Foundation

/// The app's long-lived services, created once per launch and injected into
/// the browser and its screens.
final class AppServices {
    let settings: SettingsStore
    let workspaceStore: WorkspaceStore
    let history: HistoryStore
    let bookmarks: BookmarkStore
    let conversations: ConversationStore
    let downloads: DownloadStore
    let keychain: KeychainStore

    init() {
        StoragePaths.ensureDirectories()
        settings = SettingsStore()
        workspaceStore = WorkspaceStore()
        history = HistoryStore()
        bookmarks = BookmarkStore()
        conversations = ConversationStore()
        downloads = DownloadStore()
        keychain = KeychainStore()
    }
}

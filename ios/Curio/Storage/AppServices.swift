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

    init(settings: SettingsStore = SettingsStore(),
         workspaceStore: WorkspaceStore = WorkspaceStore(),
         history: HistoryStore = HistoryStore()) {
        StoragePaths.ensureDirectories()
        self.settings = settings
        self.workspaceStore = workspaceStore
        self.history = history
        bookmarks = BookmarkStore()
        conversations = ConversationStore()
        downloads = DownloadStore()
        keychain = KeychainStore()
    }
}

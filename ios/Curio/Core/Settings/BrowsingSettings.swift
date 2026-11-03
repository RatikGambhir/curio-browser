import Foundation

/// Browsing behavior.
nonisolated struct BrowsingSettings: Codable, Equatable, Sendable {
    var searchEngine: SearchEngine = .google
    /// Restore spaces and tabs on launch.
    var restoreSession = true
    /// Record visited pages in history.
    var saveHistory = true
    /// Live web views kept in memory before background tabs sleep.
    var maxLiveTabs = 12
    /// Minutes of inactivity before a background tab sleeps.
    var sleepAfterMinutes = 60

    private enum CodingKeys: String, CodingKey {
        case searchEngine = "search_engine", restoreSession = "restore_session", saveHistory = "save_history"
        case maxLiveTabs = "max_live_tabs", sleepAfterMinutes = "sleep_after_minutes"
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = BrowsingSettings()
        searchEngine = (try? c.decodeIfPresent(SearchEngine.self, forKey: .searchEngine)) ?? d.searchEngine
        restoreSession = try c.decodeIfPresent(Bool.self, forKey: .restoreSession) ?? d.restoreSession
        saveHistory = try c.decodeIfPresent(Bool.self, forKey: .saveHistory) ?? d.saveHistory
        maxLiveTabs = try c.decodeIfPresent(Int.self, forKey: .maxLiveTabs) ?? d.maxLiveTabs
        sleepAfterMinutes = try c.decodeIfPresent(Int.self, forKey: .sleepAfterMinutes) ?? d.sleepAfterMinutes
    }
}

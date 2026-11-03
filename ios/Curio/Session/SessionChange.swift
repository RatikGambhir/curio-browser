import Foundation

/// What changed in the browser session, so the UI refreshes only what it needs.
enum SessionChange {
    /// Tabs, groups, favorites or spaces changed (sidebar and tab strip).
    case tabs
    /// A different tab is now active.
    case activeTab
    /// A tab's live page state changed (title, loading, navigation).
    case page(UUID)
    /// The active space changed; `direction` is +1 moving right, -1 left.
    case space(direction: Double)
    /// The page's text selection changed.
    case selection
    /// Downloads started or finished.
    case downloads
}

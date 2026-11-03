import Foundation

/// One of the two sidebar sections of a space.
nonisolated enum TabSection: String, Codable, CaseIterable, Sendable {
    /// Pinned tabs and folders, kept across sessions like bookmarks.
    case pinned
    /// Everyday tabs.
    case unpinned
}

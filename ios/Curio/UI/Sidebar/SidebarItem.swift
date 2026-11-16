import Foundation

/// One item in the sidebar. Identity only; content is read from the session
/// when the cell is configured.
nonisolated enum SidebarItem: Hashable, Sendable {
    /// A favorite tile, by its tab id.
    case favorite(UUID)
    case addFavorite
    /// The active space's name row.
    case header(UUID)
    case tab(UUID)
    case group(UUID)
    /// A split view, by its split id: one row for all its panes.
    case split(UUID)
    /// The pinned/regular boundary and the New Tab row.
    case divider
    /// The hint shown in an empty space.
    case empty
}

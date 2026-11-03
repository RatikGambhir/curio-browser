import Foundation

/// One item in the sidebar. Identity only; content is read from the session
/// when the cell is configured.
nonisolated enum SidebarItem: Hashable, Sendable {
    /// A favorite tile, by its tab id.
    case favorite(UUID)
    /// The active space's name row.
    case header(UUID)
    case tab(UUID)
    case group(UUID)
    /// The pinned/regular boundary and the New Tab row.
    case divider
    /// The hint shown in an empty space.
    case empty
}

import Foundation

/// Where a tab is inserted or moved to. Positions are relative to other items
/// so they stay valid while the moved tab is detached.
nonisolated enum TabPlacement: Equatable, Codable, Sendable {
    /// First position of a section.
    case sectionStart(TabSection)
    /// Last position of a section.
    case sectionEnd(TabSection)
    /// Immediately before a tab, inside the same group if it has one.
    case beforeTab(UUID)
    /// Immediately after a tab, inside the same group if it has one.
    case afterTab(UUID)
    /// Top-level, immediately before a group.
    case beforeGroup(UUID)
    /// Top-level, immediately after a group.
    case afterGroup(UUID)
    /// Inside a group at an index (clamped), or at its end for `nil`.
    case inGroup(UUID, Int?)
}

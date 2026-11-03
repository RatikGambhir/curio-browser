import Foundation

/// A tab's position in a strip.
nonisolated struct TabLocation: Equatable, Sendable {
    var section: TabSection
    var group: UUID?
    /// Index within the group's tabs when `group` is set, otherwise within the
    /// section's items.
    var index: Int
}

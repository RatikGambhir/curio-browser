import Foundation

/// A closed tab remembered for "Reopen Closed Tab" and the archive.
nonisolated struct ClosedTab: Codable, Equatable, Sendable {
    var space: UUID
    var tab: Tab
    var restoreAt: TabPlacement
}

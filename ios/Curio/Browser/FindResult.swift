import Foundation

/// Find-in-page progress.
nonisolated struct FindResult: Codable, Equatable, Sendable {
    var matches = 0
    /// One-based index of the highlighted match.
    var active = 0
}

import Foundation

/// Milliseconds since the Unix epoch.
typealias Timestamp = Int64

nonisolated extension Timestamp {
    /// The current time in milliseconds.
    static var now: Timestamp {
        Timestamp((Date.now.timeIntervalSince1970 * 1000).rounded())
    }
}

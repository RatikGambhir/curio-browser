import Foundation

/// One dispatched Server-Sent Event.
nonisolated struct SSEEvent: Equatable, Sendable {
    /// The `event:` name, or "message" when absent.
    var event: String
    /// `data:` lines joined with newlines.
    var data: String
}

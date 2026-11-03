import Foundation

/// Why generation stopped.
nonisolated enum StopReason: Equatable, Sendable {
    case endTurn
    /// The output limit was reached; the answer is truncated.
    case maxTokens
    /// The provider's safety system declined the request.
    case refusal
    case other(String)
}

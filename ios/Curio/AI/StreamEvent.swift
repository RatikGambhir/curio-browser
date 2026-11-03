import Foundation

/// Incremental output from a streaming request.
nonisolated enum StreamEvent: Equatable, Sendable {
    /// A chunk of answer text.
    case text(String)
    /// The model is reasoning before answering.
    case thinking
    case done(StopReason)
    /// Generation failed; text already delivered is kept.
    case error(AIError)
}

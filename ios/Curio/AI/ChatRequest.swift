import Foundation

/// A provider-neutral chat completion request.
nonisolated struct ChatRequest: Equatable, Sendable {
    /// System instructions, including any shared page context.
    var system: String
    /// The conversation so far, oldest first, ending with a user message.
    var messages: [WireMessage]
}

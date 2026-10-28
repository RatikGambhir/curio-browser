//! Provider-neutral chat requests and stream events.

use curio_core::chat::Role;

/// One message on the wire.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WireMessage {
    pub role: Role,
    pub content: String,
}

/// A chat completion request.
#[derive(Debug, Clone, PartialEq, Eq, Default)]
pub struct ChatRequest {
    /// System instructions, including any shared page context.
    pub system: String,
    /// The conversation so far, oldest first, ending with a user message.
    pub messages: Vec<WireMessage>,
}

/// Why generation stopped.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum StopReason {
    /// The model finished its answer.
    EndTurn,
    /// The output limit was reached; the answer is truncated.
    MaxTokens,
    /// The provider's safety system declined the request.
    Refusal,
    /// Any other provider-specific reason.
    Other(String),
}

/// Incremental output from a streaming request.
#[derive(Debug, Clone, PartialEq)]
pub enum StreamEvent {
    /// A chunk of answer text.
    Text(String),
    /// The model is reasoning before answering (no text is shown).
    Thinking,
    /// Generation finished.
    Done(StopReason),
    /// Generation failed; partial text already delivered is kept.
    Error(crate::AiError),
}

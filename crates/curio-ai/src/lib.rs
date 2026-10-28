//! Curio's AI subsystem.
//!
//! - [`providers`]: wire formats for Anthropic and OpenAI(-compatible) APIs.
//! - [`client`]: streaming transport on background threads.
//! - [`context`]: turning shared web pages into a safe system prompt.
//! - [`secrets`]: API key storage in the platform keychain.
//!
//! The UI owns conversations ([`curio_core::chat::Conversation`]) and calls
//! [`client::start_stream`] with a [`ChatRequest`] built from them.

pub mod client;
pub mod context;
pub mod providers;
pub mod request;
pub mod secrets;
pub mod sse;

pub use client::{ProviderConfig, StreamHandle, start_stream, verify_provider};
pub use context::{PageContext, QuickAction, build_system_prompt};
pub use request::{ChatRequest, StopReason, StreamEvent, WireMessage};
pub use secrets::SecretStore;

/// Errors from AI requests. Messages are safe to show to the user and never
/// include API keys.
#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum AiError {
    #[error("add your {0} API key in Settings › AI to start chatting")]
    MissingApiKey(String),
    #[error("the API key was rejected: {0}")]
    Unauthorized(String),
    #[error("rate limited by the provider, try again shortly: {0}")]
    RateLimited(String),
    #[error("the provider is overloaded, try again shortly: {0}")]
    Overloaded(String),
    #[error("{message}")]
    Api {
        status: Option<u16>,
        kind: String,
        message: String,
    },
    #[error("network error: {0}")]
    Network(String),
    #[error("unexpected response: {0}")]
    InvalidResponse(String),
    #[error("cancelled")]
    Cancelled,
}

impl AiError {
    /// Whether retrying the same request may succeed.
    #[must_use]
    pub fn is_retryable(&self) -> bool {
        matches!(
            self,
            Self::RateLimited(_) | Self::Overloaded(_) | Self::Network(_)
        ) || matches!(self, Self::Api { status: Some(s), .. } if *s >= 500)
    }
}

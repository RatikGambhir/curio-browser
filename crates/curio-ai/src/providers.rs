//! Wire formats for each provider: request bodies and stream event parsing.
//!
//! Everything here is pure (no I/O) so it can be unit tested; the HTTP
//! transport lives in [`crate::client`].

use curio_core::chat::Role;
use curio_settings::AiProviderKind;
use serde_json::{Value, json};

use crate::AiError;
use crate::request::{ChatRequest, StopReason, StreamEvent, WireMessage};
use crate::sse::SseEvent;

/// Anthropic Messages API version sent with every request.
pub const ANTHROPIC_VERSION: &str = "2026-10-21";
/// Beta header enabling server-side refusal fallbacks (`fallbacks: "default"`).
pub const ANTHROPIC_FALLBACK_BETA: &str = "server-side-fallback-2026-07-01";
/// Output budget for Anthropic streaming requests.
const ANTHROPIC_MAX_TOKENS: u32 = 32_000;

/// Models offered in the model picker for each provider. Users can also type
/// any other model identifier.
#[must_use]
pub fn suggested_models(kind: AiProviderKind) -> &'static [&'static str] {
    match kind {
        AiProviderKind::Anthropic => &[
            "claude-opus-5-5",
            "claude-sonnet-5-5",
            "claude-haiku-5-5",
            "claude-fable-5-1",
        ],
        AiProviderKind::OpenAi => &["gpt-5", "gpt-5-mini", "gpt-4.1"],
        AiProviderKind::OpenAiCompatible => &["llama3.1", "qwen2.5", "mistral"],
    }
}

/// Normalizes a conversation for providers that require strictly
/// alternating turns starting with the user: drops leading assistant turns
/// and empty messages, and merges consecutive messages from the same role.
#[must_use]
pub fn normalize_messages(messages: &[WireMessage]) -> Vec<WireMessage> {
    let mut out: Vec<WireMessage> = Vec::with_capacity(messages.len());
    for message in messages {
        if message.content.trim().is_empty() {
            continue;
        }
        if out.is_empty() && message.role == Role::Assistant {
            continue;
        }
        match out.last_mut() {
            Some(last) if last.role == message.role => {
                last.content.push_str("\n\n");
                last.content.push_str(&message.content);
            }
            _ => out.push(message.clone()),
        }
    }
    out
}

fn wire_messages(request: &ChatRequest) -> Vec<Value> {
    normalize_messages(&request.messages)
        .into_iter()
        .map(|m| json!({ "role": m.role.as_str(), "content": m.content }))
        .collect()
}

// ----- Anthropic ----------------------------------------------------------

/// Whether server-side refusal fallbacks apply: only first-party Claude API
/// requests to the models that support `fallbacks: "default"`.
#[must_use]
pub fn anthropic_uses_fallbacks(base_url: &str, model: &str) -> bool {
    let first_party = base_url.trim_end_matches('/') == "https://api.anthropic.com";
    let supported = matches!(
        model,
        "claude-opus-5-5" | "claude-opus-5" | "claude-fable-5-1" | "claude-sonnet-5-5"
    );
    first_party && supported
}

/// Builds an Anthropic Messages API streaming request body.
#[must_use]
pub fn anthropic_body(request: &ChatRequest, model: &str, with_fallbacks: bool) -> Value {
    let mut body = json!({
        "model": model,
        "max_tokens": ANTHROPIC_MAX_TOKENS,
        "stream": true,
        "messages": wire_messages(request),
    });
    if !request.system.trim().is_empty() {
        body["system"] = Value::String(request.system.clone());
    }
    if with_fallbacks {
        body["fallbacks"] = Value::String("default".to_owned());
    }
    body
}

/// Tracks Anthropic stream state across events.
#[derive(Debug, Default)]
pub struct AnthropicStream {
    stop: Option<StopReason>,
}

impl AnthropicStream {
    /// Translates one SSE event into zero or more stream events.
    pub fn handle(&mut self, event: &SseEvent) -> Vec<StreamEvent> {
        let Ok(data) = serde_json::from_str::<Value>(&event.data) else {
            return Vec::new();
        };
        let kind = data["type"].as_str().unwrap_or(event.event.as_str());
        match kind {
            "content_block_start" => match data["content_block"]["type"].as_str() {
                Some("thinking" | "redacted_thinking") => vec![StreamEvent::Thinking],
                Some("text") => data["content_block"]["text"]
                    .as_str()
                    .filter(|t| !t.is_empty())
                    .map(|t| vec![StreamEvent::Text(t.to_owned())])
                    .unwrap_or_default(),
                _ => Vec::new(),
            },
            "content_block_delta" => match data["delta"]["type"].as_str() {
                Some("text_delta") => data["delta"]["text"]
                    .as_str()
                    .map(|t| vec![StreamEvent::Text(t.to_owned())])
                    .unwrap_or_default(),
                Some("thinking_delta" | "signature_delta") => vec![StreamEvent::Thinking],
                _ => Vec::new(),
            },
            "message_delta" => {
                if let Some(reason) = data["delta"]["stop_reason"].as_str() {
                    self.stop = Some(match reason {
                        "end_turn" | "stop_sequence" => StopReason::EndTurn,
                        "max_tokens" => StopReason::MaxTokens,
                        "refusal" => StopReason::Refusal,
                        other => StopReason::Other(other.to_owned()),
                    });
                }
                Vec::new()
            }
            "message_stop" => vec![StreamEvent::Done(
                self.stop.take().unwrap_or(StopReason::EndTurn),
            )],
            "error" => vec![StreamEvent::Error(api_error(None, &data))],
            _ => Vec::new(),
        }
    }
}

// ----- OpenAI and compatible ----------------------------------------------

/// Builds an OpenAI chat completions streaming request body.
#[must_use]
pub fn openai_body(request: &ChatRequest, model: &str) -> Value {
    let mut messages = Vec::with_capacity(request.messages.len() + 1);
    if !request.system.trim().is_empty() {
        messages.push(json!({ "role": "system", "content": request.system }));
    }
    messages.extend(wire_messages(request));
    json!({
        "model": model,
        "stream": true,
        "messages": messages,
    })
}

/// Tracks OpenAI stream state across events.
#[derive(Debug, Default)]
pub struct OpenAiStream {
    stop: Option<StopReason>,
    done: bool,
}

impl OpenAiStream {
    /// Translates one SSE event into zero or more stream events.
    pub fn handle(&mut self, event: &SseEvent) -> Vec<StreamEvent> {
        if self.done {
            return Vec::new();
        }
        if event.data.trim() == "[DONE]" {
            self.done = true;
            return vec![StreamEvent::Done(
                self.stop.take().unwrap_or(StopReason::EndTurn),
            )];
        }
        let Ok(data) = serde_json::from_str::<Value>(&event.data) else {
            return Vec::new();
        };
        if data.get("error").is_some() {
            self.done = true;
            return vec![StreamEvent::Error(api_error(None, &data))];
        }
        let mut out = Vec::new();
        let choice = &data["choices"][0];
        if let Some(text) = choice["delta"]["content"].as_str()
            && !text.is_empty()
        {
            out.push(StreamEvent::Text(text.to_owned()));
        }
        if choice["delta"]["reasoning_content"].as_str().is_some()
            || choice["delta"]["reasoning"].as_str().is_some()
        {
            out.push(StreamEvent::Thinking);
        }
        if let Some(reason) = choice["finish_reason"].as_str() {
            self.stop = Some(match reason {
                "stop" => StopReason::EndTurn,
                "length" => StopReason::MaxTokens,
                "content_filter" => StopReason::Refusal,
                other => StopReason::Other(other.to_owned()),
            });
        }
        out
    }

    /// Called at end of stream; servers that never send `[DONE]` still
    /// produce a final event.
    pub fn finish(&mut self) -> Option<StreamEvent> {
        if self.done {
            None
        } else {
            self.done = true;
            Some(StreamEvent::Done(self.stop.take().unwrap_or(StopReason::EndTurn)))
        }
    }
}

// ----- Errors ---------------------------------------------------------------

/// Builds an [`AiError`] from an HTTP status and an error body in either
/// Anthropic (`{"type":"error","error":{...}}`) or OpenAI
/// (`{"error":{...}}`) shape.
#[must_use]
pub fn api_error(status: Option<u16>, body: &Value) -> AiError {
    let error = &body["error"];
    let kind = error["type"]
        .as_str()
        .or_else(|| error["code"].as_str())
        .unwrap_or_default()
        .to_owned();
    let message = error["message"]
        .as_str()
        .or_else(|| body["message"].as_str())
        .unwrap_or("the AI provider returned an error")
        .to_owned();
    match (status, kind.as_str()) {
        (Some(401), _) | (_, "authentication_error" | "invalid_api_key") => {
            AiError::Unauthorized(message)
        }
        (Some(429), _) | (_, "rate_limit_error" | "rate_limit_exceeded") => {
            AiError::RateLimited(message)
        }
        (Some(529 | 503), _) | (_, "overloaded_error") => AiError::Overloaded(message),
        _ => AiError::Api {
            status,
            kind,
            message,
        },
    }
}

/// Builds an [`AiError`] for a non-success HTTP response whose body may not
/// be JSON.
#[must_use]
pub fn http_error(status: u16, body: &str) -> AiError {
    match serde_json::from_str::<Value>(body) {
        Ok(value) => api_error(Some(status), &value),
        Err(_) => {
            let snippet: String = body.chars().take(300).collect();
            api_error(
                Some(status),
                &json!({ "error": { "message": if snippet.trim().is_empty() {
                    format!("HTTP {status}")
                } else {
                    snippet
                } } }),
            )
        }
    }
}

/// The provider for a parsed stream, used by the transport.
#[derive(Debug)]
pub enum StreamDecoder {
    Anthropic(AnthropicStream),
    OpenAi(OpenAiStream),
}

impl StreamDecoder {
    /// A decoder for `kind`.
    #[must_use]
    pub fn new(kind: AiProviderKind) -> Self {
        match kind {
            AiProviderKind::Anthropic => Self::Anthropic(AnthropicStream::default()),
            AiProviderKind::OpenAi | AiProviderKind::OpenAiCompatible => {
                Self::OpenAi(OpenAiStream::default())
            }
        }
    }

    /// Translates one SSE event.
    pub fn handle(&mut self, event: &SseEvent) -> Vec<StreamEvent> {
        match self {
            Self::Anthropic(s) => s.handle(event),
            Self::OpenAi(s) => s.handle(event),
        }
    }

    /// Final event when the body ends without an explicit terminator.
    pub fn finish(&mut self) -> Option<StreamEvent> {
        match self {
            Self::Anthropic(s) => s.stop.take().map(StreamEvent::Done),
            Self::OpenAi(s) => s.finish(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sse(event: &str, data: &str) -> SseEvent {
        SseEvent {
            event: event.into(),
            data: data.into(),
        }
    }

    fn msg(role: Role, content: &str) -> WireMessage {
        WireMessage {
            role,
            content: content.into(),
        }
    }

    #[test]
    fn normalize_merges_and_trims_conversation() {
        let normalized = normalize_messages(&[
            msg(Role::Assistant, "hello, I am Curio"),
            msg(Role::User, "a"),
            msg(Role::User, "b"),
            msg(Role::Assistant, "  "),
            msg(Role::Assistant, "c"),
        ]);
        assert_eq!(normalized, vec![msg(Role::User, "a\n\nb"), msg(Role::Assistant, "c")]);
    }

    #[test]
    fn anthropic_body_has_required_fields_and_no_sampling_params() {
        let request = ChatRequest {
            system: "be brief".into(),
            messages: vec![msg(Role::User, "hi")],
        };
        let body = anthropic_body(&request, "claude-opus-5-5", true);
        assert_eq!(body["model"], "claude-opus-5-5");
        assert_eq!(body["stream"], true);
        assert_eq!(body["system"], "be brief");
        assert_eq!(body["fallbacks"], "default");
        assert!(body.get("temperature").is_none());
        assert_eq!(body["messages"][0]["role"], "user");
    }

    #[test]
    fn fallbacks_only_for_first_party_supported_models() {
        assert!(anthropic_uses_fallbacks("https://api.anthropic.com", "claude-opus-5-5"));
        assert!(!anthropic_uses_fallbacks("https://api.anthropic.com", "claude-haiku-5-5"));
        assert!(!anthropic_uses_fallbacks("https://proxy.example", "claude-opus-5-5"));
    }

    #[test]
    fn anthropic_stream_produces_text_and_stop() {
        let mut stream = AnthropicStream::default();
        let mut events = Vec::new();
        for (name, data) in [
            ("message_start", r#"{"type":"message_start","message":{}}"#),
            ("content_block_start", r#"{"type":"content_block_start","index":0,"content_block":{"type":"thinking","thinking":""}}"#),
            ("content_block_start", r#"{"type":"content_block_start","index":1,"content_block":{"type":"text","text":""}}"#),
            ("content_block_delta", r#"{"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"Hel"}}"#),
            ("content_block_delta", r#"{"type":"content_block_delta","index":1,"delta":{"type":"text_delta","text":"lo"}}"#),
            ("message_delta", r#"{"type":"message_delta","delta":{"stop_reason":"max_tokens"}}"#),
            ("message_stop", r#"{"type":"message_stop"}"#),
        ] {
            events.extend(stream.handle(&sse(name, data)));
        }
        assert_eq!(
            events,
            vec![
                StreamEvent::Thinking,
                StreamEvent::Text("Hel".into()),
                StreamEvent::Text("lo".into()),
                StreamEvent::Done(StopReason::MaxTokens),
            ]
        );
    }

    #[test]
    fn anthropic_error_event_maps_to_overloaded() {
        let mut stream = AnthropicStream::default();
        let events = stream.handle(&sse(
            "error",
            r#"{"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}"#,
        ));
        assert_eq!(events, vec![StreamEvent::Error(AiError::Overloaded("Overloaded".into()))]);
    }

    #[test]
    fn openai_stream_produces_text_and_done() {
        let mut stream = OpenAiStream::default();
        let mut events = Vec::new();
        for data in [
            r#"{"choices":[{"delta":{"role":"assistant"}}]}"#,
            r#"{"choices":[{"delta":{"content":"Hi"}}]}"#,
            r#"{"choices":[{"delta":{},"finish_reason":"stop"}]}"#,
            "[DONE]",
        ] {
            events.extend(stream.handle(&sse("message", data)));
        }
        assert_eq!(
            events,
            vec![StreamEvent::Text("Hi".into()), StreamEvent::Done(StopReason::EndTurn)]
        );
        assert!(stream.finish().is_none());
    }

    #[test]
    fn openai_body_puts_system_first() {
        let request = ChatRequest {
            system: "sys".into(),
            messages: vec![msg(Role::User, "q")],
        };
        let body = openai_body(&request, "gpt-5");
        assert_eq!(body["messages"][0]["role"], "system");
        assert_eq!(body["messages"][1]["content"], "q");
    }

    #[test]
    fn http_errors_are_classified() {
        assert!(matches!(
            http_error(401, r#"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#),
            AiError::Unauthorized(m) if m == "invalid x-api-key"
        ));
        assert!(matches!(http_error(429, "slow down"), AiError::RateLimited(_)));
        assert!(matches!(
            http_error(404, r#"{"error":{"type":"not_found_error","message":"model: x"}}"#),
            AiError::Api { status: Some(404), .. }
        ));
    }
}

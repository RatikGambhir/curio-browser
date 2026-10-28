//! HTTP transport for streaming chat requests.
//!
//! Each request runs on its own background thread with a blocking HTTP
//! client and forwards [`StreamEvent`]s over a bounded channel that the UI
//! awaits. This keeps networking entirely off the UI thread without tying the
//! AI layer to a particular async runtime.

use std::fmt;
use std::io::{BufRead, BufReader};
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::Duration;

use curio_settings::{AiProviderKind, AiSettings};
use ureq::tls::{RootCerts, TlsConfig};

use crate::AiError;
use crate::providers::{
    ANTHROPIC_FALLBACK_BETA, ANTHROPIC_VERSION, StreamDecoder, anthropic_body,
    anthropic_uses_fallbacks, http_error, openai_body,
};
use crate::request::{ChatRequest, StreamEvent};
use crate::secrets::SecretStore;
use crate::sse::SseParser;

/// Everything needed to call a provider.
#[derive(Clone)]
pub struct ProviderConfig {
    pub kind: AiProviderKind,
    pub model: String,
    pub base_url: String,
    pub api_key: Option<String>,
}

impl fmt::Debug for ProviderConfig {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        // Never print the key.
        f.debug_struct("ProviderConfig")
            .field("kind", &self.kind)
            .field("model", &self.model)
            .field("base_url", &self.base_url)
            .field("api_key", &self.api_key.as_ref().map(|_| "<redacted>"))
            .finish()
    }
}

impl ProviderConfig {
    /// Resolves the active provider from settings and the secret store.
    #[must_use]
    pub fn from_settings(settings: &AiSettings, secrets: &SecretStore) -> Self {
        let kind = settings.provider;
        Self {
            kind,
            model: settings.model(kind),
            base_url: settings.base_url(kind),
            api_key: secrets.api_key(kind),
        }
    }

    /// Whether a request can be attempted (a key is present when required).
    #[must_use]
    pub fn is_ready(&self) -> bool {
        !self.kind.requires_api_key() || self.api_key.as_deref().is_some_and(|k| !k.is_empty())
    }
}

/// A running request. Dropping the handle cancels it.
pub struct StreamHandle {
    events: async_channel::Receiver<StreamEvent>,
    cancel: Arc<AtomicBool>,
}

impl StreamHandle {
    /// The event receiver.
    #[must_use]
    pub fn events(&self) -> async_channel::Receiver<StreamEvent> {
        self.events.clone()
    }

    /// Stops the request. Already delivered text is kept by the caller.
    pub fn cancel(&self) {
        self.cancel.store(true, Ordering::Relaxed);
        self.events.close();
    }
}

impl Drop for StreamHandle {
    fn drop(&mut self) {
        self.cancel();
    }
}

/// Starts a streaming request on a background thread.
#[must_use]
pub fn start_stream(config: ProviderConfig, request: ChatRequest) -> StreamHandle {
    let (tx, rx) = async_channel::bounded(256);
    let cancel = Arc::new(AtomicBool::new(false));
    let thread_cancel = cancel.clone();
    let spawned = std::thread::Builder::new()
        .name("curio-ai-stream".into())
        .spawn(move || {
            let send = |event: StreamEvent| tx.send_blocking(event).is_ok();
            if let Err(error) = run_stream(&config, &request, &thread_cancel, &send) {
                if !matches!(error, AiError::Cancelled) {
                    tracing::warn!(provider = ?config.kind, error = %error, "AI request failed");
                }
                send(StreamEvent::Error(error));
            }
        });
    if let Err(error) = spawned {
        let (tx, rx) = async_channel::bounded(1);
        let _ = tx.try_send(StreamEvent::Error(AiError::Network(format!(
            "could not start request thread: {error}"
        ))));
        return StreamHandle { events: rx, cancel };
    }
    StreamHandle { events: rx, cancel }
}

fn agent() -> ureq::Agent {
    ureq::Agent::config_builder()
        .http_status_as_error(false)
        .timeout_connect(Some(Duration::from_secs(20)))
        .timeout_global(None)
        .proxy(ureq::Proxy::try_from_env())
        .tls_config(
            TlsConfig::builder()
                .root_certs(RootCerts::PlatformVerifier)
                .build(),
        )
        .user_agent(concat!("Curio/", env!("CARGO_PKG_VERSION")))
        .build()
        .new_agent()
}

/// Runs a request to completion, delivering events through `send`. Returns
/// `Ok` once a terminal event (done or error) was delivered.
fn run_stream(
    config: &ProviderConfig,
    request: &ChatRequest,
    cancel: &AtomicBool,
    send: &dyn Fn(StreamEvent) -> bool,
) -> Result<(), AiError> {
    if !config.is_ready() {
        return Err(AiError::MissingApiKey(config.kind.label().to_owned()));
    }
    let agent = agent();
    let base = config.base_url.trim_end_matches('/');
    let response = match config.kind {
        AiProviderKind::Anthropic => {
            let fallbacks = anthropic_uses_fallbacks(base, &config.model);
            let body = anthropic_body(request, &config.model, fallbacks);
            let mut builder = agent
                .post(format!("{base}/v1/messages"))
                .header("content-type", "application/json")
                .header("accept", "text/event-stream")
                .header("anthropic-version", ANTHROPIC_VERSION)
                .header("x-api-key", config.api_key.as_deref().unwrap_or_default());
            if fallbacks {
                builder = builder.header("anthropic-beta", ANTHROPIC_FALLBACK_BETA);
            }
            builder.send(body.to_string())
        }
        AiProviderKind::OpenAi | AiProviderKind::OpenAiCompatible => {
            let body = openai_body(request, &config.model);
            let mut builder = agent
                .post(format!("{base}/chat/completions"))
                .header("content-type", "application/json")
                .header("accept", "text/event-stream");
            if let Some(key) = config.api_key.as_deref().filter(|k| !k.is_empty()) {
                builder = builder.header("authorization", &format!("Bearer {key}"));
            }
            builder.send(body.to_string())
        }
    }
    .map_err(|error| AiError::Network(error.to_string()))?;

    let status = response.status().as_u16();
    let mut body = response.into_body();
    if !(200..300).contains(&status) {
        let text = body
            .with_config()
            .limit(64 * 1024)
            .read_to_string()
            .unwrap_or_default();
        return Err(http_error(status, &text));
    }

    let reader = BufReader::new(body.into_reader());
    let mut parser = SseParser::new();
    let mut decoder = StreamDecoder::new(config.kind);
    let deliver = |events: Vec<StreamEvent>| -> Result<bool, AiError> {
        for event in events {
            let terminal = matches!(event, StreamEvent::Done(_) | StreamEvent::Error(_));
            if !send(event) {
                return Err(AiError::Cancelled);
            }
            if terminal {
                return Ok(true);
            }
        }
        Ok(false)
    };
    for line in reader.lines() {
        if cancel.load(Ordering::Relaxed) {
            return Err(AiError::Cancelled);
        }
        let line = line.map_err(|error| AiError::Network(error.to_string()))?;
        if let Some(event) = parser.feed(&line)
            && deliver(decoder.handle(&event))?
        {
            return Ok(());
        }
    }
    if let Some(event) = parser.finish()
        && deliver(decoder.handle(&event))?
    {
        return Ok(());
    }
    match decoder.finish() {
        Some(event) => {
            deliver(vec![event])?;
            Ok(())
        }
        None => Err(AiError::InvalidResponse(
            "the response ended before the answer was complete".to_owned(),
        )),
    }
}

/// Sends a tiny request to check that the provider, model and key work.
/// Blocking; call it from a background thread.
///
/// # Errors
/// Returns the provider or network error.
pub fn verify_provider(config: &ProviderConfig) -> Result<(), AiError> {
    let request = ChatRequest {
        system: String::new(),
        messages: vec![crate::request::WireMessage {
            role: curio_core::chat::Role::User,
            content: "Reply with the single word: ok".to_owned(),
        }],
    };
    let cancel = AtomicBool::new(false);
    let result = std::cell::RefCell::new(None);
    let send = |event: StreamEvent| {
        if let StreamEvent::Error(error) = event {
            *result.borrow_mut() = Some(error);
        }
        true
    };
    run_stream(config, &request, &cancel, &send)?;
    match result.into_inner() {
        Some(error) => Err(error),
        None => Ok(()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::{Read, Write};
    use std::net::TcpListener;

    /// Serves one canned HTTP response on a local port.
    fn serve_once(status: &str, content_type: &str, body: &'static str) -> String {
        let listener = TcpListener::bind("127.0.0.1:0").expect("bind");
        let addr = listener.local_addr().expect("addr");
        let status = status.to_owned();
        let content_type = content_type.to_owned();
        std::thread::spawn(move || {
            if let Ok((mut stream, _)) = listener.accept() {
                let mut buf = [0u8; 8192];
                let _ = stream.read(&mut buf);
                let response = format!(
                    "HTTP/1.1 {status}\r\ncontent-type: {content_type}\r\nconnection: close\r\n\r\n{body}"
                );
                let _ = stream.write_all(response.as_bytes());
            }
        });
        format!("http://{addr}")
    }

    fn collect(handle: &StreamHandle) -> Vec<StreamEvent> {
        let rx = handle.events();
        let mut out = Vec::new();
        while let Ok(event) = rx.recv_blocking() {
            let terminal = matches!(event, StreamEvent::Done(_) | StreamEvent::Error(_));
            out.push(event);
            if terminal {
                break;
            }
        }
        out
    }

    fn request() -> ChatRequest {
        ChatRequest {
            system: "test".into(),
            messages: vec![crate::request::WireMessage {
                role: curio_core::chat::Role::User,
                content: "hi".into(),
            }],
        }
    }

    #[test]
    fn streams_openai_compatible_response_from_local_server() {
        let base = serve_once(
            "200 OK",
            "text/event-stream",
            "data: {\"choices\":[{\"delta\":{\"content\":\"Hello\"}}]}\n\n\
             data: {\"choices\":[{\"delta\":{\"content\":\" world\"},\"finish_reason\":\"stop\"}]}\n\n\
             data: [DONE]\n\n",
        );
        let config = ProviderConfig {
            kind: AiProviderKind::OpenAiCompatible,
            model: "local".into(),
            base_url: base,
            api_key: None,
        };
        let events = collect(&start_stream(config, request()));
        let text: String = events
            .iter()
            .filter_map(|e| match e {
                StreamEvent::Text(t) => Some(t.as_str()),
                _ => None,
            })
            .collect();
        assert_eq!(text, "Hello world");
        assert!(matches!(events.last(), Some(StreamEvent::Done(_))));
    }

    #[test]
    fn streams_anthropic_response_from_local_server() {
        let base = serve_once(
            "200 OK",
            "text/event-stream",
            "event: message_start\ndata: {\"type\":\"message_start\",\"message\":{}}\n\n\
             event: content_block_start\ndata: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"text\",\"text\":\"\"}}\n\n\
             event: content_block_delta\ndata: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"Curio\"}}\n\n\
             event: message_delta\ndata: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"end_turn\"}}\n\n\
             event: message_stop\ndata: {\"type\":\"message_stop\"}\n\n",
        );
        let config = ProviderConfig {
            kind: AiProviderKind::Anthropic,
            model: "claude-opus-5-5".into(),
            base_url: base,
            api_key: Some("test-key".into()),
        };
        let events = collect(&start_stream(config, request()));
        assert_eq!(
            events,
            vec![
                StreamEvent::Text("Curio".into()),
                StreamEvent::Done(crate::StopReason::EndTurn)
            ]
        );
    }

    #[test]
    fn http_errors_surface_as_typed_errors() {
        let base = serve_once(
            "401 Unauthorized",
            "application/json",
            r#"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#,
        );
        let config = ProviderConfig {
            kind: AiProviderKind::Anthropic,
            model: "claude-opus-5-5".into(),
            base_url: base,
            api_key: Some("bad".into()),
        };
        let events = collect(&start_stream(config, request()));
        assert!(matches!(
            &events[..],
            [StreamEvent::Error(AiError::Unauthorized(_))]
        ));
    }

    #[test]
    fn missing_key_fails_without_network() {
        let config = ProviderConfig {
            kind: AiProviderKind::OpenAi,
            model: "gpt-5".into(),
            base_url: "http://127.0.0.1:9".into(),
            api_key: None,
        };
        let events = collect(&start_stream(config, request()));
        assert!(matches!(
            &events[..],
            [StreamEvent::Error(AiError::MissingApiKey(_))]
        ));
    }

    #[test]
    fn debug_output_redacts_api_key() {
        let config = ProviderConfig {
            kind: AiProviderKind::Anthropic,
            model: "m".into(),
            base_url: "b".into(),
            api_key: Some("sk-secret".into()),
        };
        assert!(!format!("{config:?}").contains("sk-secret"));
    }
}

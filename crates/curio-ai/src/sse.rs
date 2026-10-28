//! An incremental Server-Sent Events parser.
//!
//! Lines are fed one at a time (without the trailing newline); a complete
//! event is returned when a blank line terminates it. Only the `event` and
//! `data` fields matter for chat streaming; `id`, `retry` and comments are
//! ignored.

/// One dispatched SSE event.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SseEvent {
    /// The `event:` name, or `"message"` when absent.
    pub event: String,
    /// Concatenated `data:` lines, joined with `\n`.
    pub data: String,
}

/// Accumulates fields until an event is complete.
#[derive(Debug, Default)]
pub struct SseParser {
    event: Option<String>,
    data: Option<String>,
}

impl SseParser {
    /// Creates an empty parser.
    #[must_use]
    pub fn new() -> Self {
        Self::default()
    }

    /// Feeds one line. Returns an event when `line` is the blank line that
    /// ends it.
    pub fn feed(&mut self, line: &str) -> Option<SseEvent> {
        let line = line.strip_suffix('\r').unwrap_or(line);
        if line.is_empty() {
            return self.dispatch();
        }
        if line.starts_with(':') {
            return None;
        }
        let (field, value) = match line.split_once(':') {
            Some((field, value)) => (field, value.strip_prefix(' ').unwrap_or(value)),
            None => (line, ""),
        };
        match field {
            "event" => self.event = Some(value.to_owned()),
            "data" => match &mut self.data {
                Some(data) => {
                    data.push('\n');
                    data.push_str(value);
                }
                None => self.data = Some(value.to_owned()),
            },
            _ => {}
        }
        None
    }

    /// Flushes a pending event at end of stream (servers sometimes omit the
    /// final blank line).
    pub fn finish(&mut self) -> Option<SseEvent> {
        self.dispatch()
    }

    fn dispatch(&mut self) -> Option<SseEvent> {
        let data = self.data.take();
        let event = self.event.take();
        data.map(|data| SseEvent {
            event: event.unwrap_or_else(|| "message".to_owned()),
            data,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn parse_all(input: &str) -> Vec<SseEvent> {
        let mut parser = SseParser::new();
        let mut out: Vec<SseEvent> = input.lines().filter_map(|l| parser.feed(l)).collect();
        out.extend(parser.finish());
        out
    }

    #[test]
    fn parses_named_events_and_crlf() {
        let events = parse_all("event: ping\r\ndata: {}\r\n\r\nevent: delta\ndata: {\"a\":1}\n\n");
        assert_eq!(events.len(), 2);
        assert_eq!(events[0].event, "ping");
        assert_eq!(events[1].data, "{\"a\":1}");
    }

    #[test]
    fn joins_multiline_data_and_ignores_comments() {
        let events = parse_all(": keep-alive\ndata: one\ndata: two\n\n");
        assert_eq!(events, vec![SseEvent {
            event: "message".into(),
            data: "one\ntwo".into()
        }]);
    }

    #[test]
    fn flushes_unterminated_final_event() {
        let events = parse_all("data: [DONE]");
        assert_eq!(events[0].data, "[DONE]");
    }

    #[test]
    fn data_without_space_is_accepted() {
        let events = parse_all("data:x\n\n");
        assert_eq!(events[0].data, "x");
    }
}

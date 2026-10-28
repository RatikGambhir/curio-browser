//! Validation of messages posted by the page bridge script.

use serde::Deserialize;

/// A rectangle in page viewport coordinates (CSS pixels).
#[derive(Debug, Clone, Copy, PartialEq, Deserialize)]
pub struct PageRect {
    pub x: f64,
    pub y: f64,
    pub width: f64,
    pub height: f64,
}

/// A validated message from a page.
#[derive(Debug, Clone, PartialEq)]
pub enum PageMessage {
    /// Open a link in a new tab (Cmd-click or middle-click).
    OpenLink { url: String, background: bool },
    /// The selection changed; empty text means it was cleared.
    Selection { text: String, rect: Option<PageRect> },
    /// Page metadata.
    Meta {
        favicon: Option<String>,
        theme_color: Option<String>,
    },
    /// The page scrolled.
    Scroll { y: f64 },
    /// The URL changed without a navigation (single-page apps).
    UrlChanged { url: String, title: String },
    /// A browser shortcut was pressed while the page had focus.
    Key { keystroke: String },
}

#[derive(Deserialize)]
struct Raw {
    token: String,
    #[serde(rename = "type")]
    kind: String,
    #[serde(default)]
    url: Option<String>,
    #[serde(default)]
    background: Option<bool>,
    #[serde(default)]
    text: Option<String>,
    #[serde(default)]
    rect: Option<PageRect>,
    #[serde(default)]
    favicon: Option<String>,
    #[serde(default, rename = "themeColor")]
    theme_color: Option<String>,
    #[serde(default)]
    y: Option<f64>,
    #[serde(default)]
    title: Option<String>,
    #[serde(default)]
    keystroke: Option<String>,
}

/// Only web URLs may be opened or used as favicons.
fn web_url(url: &str) -> Option<String> {
    let parsed = url::Url::parse(url).ok()?;
    matches!(parsed.scheme(), "http" | "https").then(|| parsed.to_string())
}

fn favicon_url(url: &str) -> Option<String> {
    if url.starts_with("data:image/") && url.len() < 64 * 1024 {
        return Some(url.to_owned());
    }
    web_url(url)
}

/// Parses and validates a raw IPC body. Returns `None` for messages that are
/// malformed, carry the wrong token, or contain disallowed values.
#[must_use]
pub fn parse_message(body: &str, token: &str, allowed_keys: &[String]) -> Option<PageMessage> {
    if body.len() > 256 * 1024 {
        return None;
    }
    let raw: Raw = serde_json::from_str(body).ok()?;
    if raw.token != token {
        return None;
    }
    match raw.kind.as_str() {
        "open" => Some(PageMessage::OpenLink {
            url: web_url(raw.url.as_deref()?)?,
            background: raw.background.unwrap_or(false),
        }),
        "selection" => {
            let text: String = raw.text.unwrap_or_default().chars().take(20_000).collect();
            let rect = raw.rect.filter(|r| {
                [r.x, r.y, r.width, r.height].iter().all(|v| v.is_finite())
            });
            Some(PageMessage::Selection { text, rect })
        }
        "meta" => Some(PageMessage::Meta {
            favicon: raw.favicon.as_deref().and_then(favicon_url),
            theme_color: raw
                .theme_color
                .filter(|c| c.len() <= 64)
                .map(|c| c.trim().to_owned()),
        }),
        "scroll" => raw
            .y
            .filter(|y| y.is_finite())
            .map(|y| PageMessage::Scroll { y: y.max(0.0) }),
        "url" => Some(PageMessage::UrlChanged {
            url: web_url(raw.url.as_deref()?)?,
            title: raw.title.unwrap_or_default().chars().take(500).collect(),
        }),
        "key" => {
            let keystroke = raw.keystroke?;
            allowed_keys
                .contains(&keystroke)
                .then_some(PageMessage::Key { keystroke })
        }
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const T: &str = "secret";

    fn keys() -> Vec<String> {
        vec!["cmd-t".into()]
    }

    #[test]
    fn rejects_wrong_token() {
        let body = r#"{"token":"guess","type":"open","url":"https://a.test"}"#;
        assert!(parse_message(body, T, &keys()).is_none());
    }

    #[test]
    fn open_link_requires_web_url() {
        let ok = r#"{"token":"secret","type":"open","url":"https://a.test/x","background":true}"#;
        assert_eq!(
            parse_message(ok, T, &keys()),
            Some(PageMessage::OpenLink {
                url: "https://a.test/x".into(),
                background: true
            })
        );
        let bad = r#"{"token":"secret","type":"open","url":"file:///etc/passwd"}"#;
        assert!(parse_message(bad, T, &keys()).is_none());
        let js = r#"{"token":"secret","type":"open","url":"javascript:alert(1)"}"#;
        assert!(parse_message(js, T, &keys()).is_none());
    }

    #[test]
    fn keys_must_be_registered() {
        let ok = r#"{"token":"secret","type":"key","keystroke":"cmd-t"}"#;
        assert!(parse_message(ok, T, &keys()).is_some());
        let other = r#"{"token":"secret","type":"key","keystroke":"cmd-q"}"#;
        assert!(parse_message(other, T, &keys()).is_none());
    }

    #[test]
    fn selection_and_scroll_are_sanitized() {
        let sel = r#"{"token":"secret","type":"selection","text":"hello","rect":{"x":1,"y":2,"width":3,"height":4}}"#;
        assert!(matches!(
            parse_message(sel, T, &keys()),
            Some(PageMessage::Selection { rect: Some(_), .. })
        ));
        let scroll = r#"{"token":"secret","type":"scroll","y":-40}"#;
        assert_eq!(parse_message(scroll, T, &keys()), Some(PageMessage::Scroll { y: 0.0 }));
    }

    #[test]
    fn favicon_allows_small_data_images_only() {
        let body = r#"{"token":"secret","type":"meta","favicon":"data:image/png;base64,AAAA"}"#;
        assert!(matches!(
            parse_message(body, T, &keys()),
            Some(PageMessage::Meta { favicon: Some(_), .. })
        ));
        let body = r#"{"token":"secret","type":"meta","favicon":"data:text/html,<b>x</b>"}"#;
        assert!(matches!(
            parse_message(body, T, &keys()),
            Some(PageMessage::Meta { favicon: None, .. })
        ));
    }
}

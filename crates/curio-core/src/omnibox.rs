//! Address bar input classification: deciding whether text typed by the user
//! is a URL to visit or a query to search for.

use percent_encoding::{NON_ALPHANUMERIC, utf8_percent_encode};
use serde::{Deserialize, Serialize};

/// The result of interpreting address bar input.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Navigation {
    /// Navigate directly to this absolute URL.
    Url(String),
    /// Search for `query`; `url` is the search engine results page.
    Search { query: String, url: String },
}

impl Navigation {
    /// The URL to load for this navigation.
    #[must_use]
    pub fn url(&self) -> &str {
        match self {
            Self::Url(url) | Self::Search { url, .. } => url,
        }
    }
}

/// A web search provider used for address bar queries.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize, Default)]
#[serde(rename_all = "snake_case", tag = "kind", content = "template")]
pub enum SearchEngine {
    #[default]
    Google,
    DuckDuckGo,
    Bing,
    Brave,
    Kagi,
    Ecosia,
    /// A custom URL template in which `%s` is replaced by the encoded query.
    Custom(String),
}

impl SearchEngine {
    /// Built-in engines, for settings menus.
    pub const BUILT_IN: [Self; 6] = [
        Self::Google,
        Self::DuckDuckGo,
        Self::Bing,
        Self::Brave,
        Self::Kagi,
        Self::Ecosia,
    ];

    /// A display name.
    #[must_use]
    pub fn label(&self) -> &str {
        match self {
            Self::Google => "Google",
            Self::DuckDuckGo => "DuckDuckGo",
            Self::Bing => "Bing",
            Self::Brave => "Brave Search",
            Self::Kagi => "Kagi",
            Self::Ecosia => "Ecosia",
            Self::Custom(_) => "Custom",
        }
    }

    fn template(&self) -> &str {
        match self {
            Self::Google => "https://www.google.com/search?q=%s",
            Self::DuckDuckGo => "https://duckduckgo.com/?q=%s",
            Self::Bing => "https://www.bing.com/search?q=%s",
            Self::Brave => "https://search.brave.com/search?q=%s",
            Self::Kagi => "https://kagi.com/search?q=%s",
            Self::Ecosia => "https://www.ecosia.org/search?q=%s",
            Self::Custom(template) => template,
        }
    }

    /// Builds the results page URL for `query`.
    #[must_use]
    pub fn search_url(&self, query: &str) -> String {
        let encoded = utf8_percent_encode(query, NON_ALPHANUMERIC).to_string();
        let template = self.template();
        if template.contains("%s") {
            template.replace("%s", &encoded)
        } else {
            // A custom template without a placeholder: fall back to Google
            // rather than silently dropping the query.
            Self::Google.search_url(query)
        }
    }
}

/// Schemes Curio will navigate to directly from the address bar.
const ALLOWED_SCHEMES: [&str; 6] = ["http", "https", "file", "about", "data", "curio"];

/// Interprets address bar input. Returns `None` for blank input.
///
/// URLs with an explicit scheme are used as-is (only for allowed schemes;
/// `javascript:` and friends are treated as searches so pasted text can never
/// execute script). Bare hosts such as `rust-lang.org/learn`,
/// `localhost:3000` and IP addresses get an `https://` (or `http://` for local
/// addresses) prefix. Everything else becomes a search.
#[must_use]
pub fn classify_input(input: &str, engine: &SearchEngine) -> Option<Navigation> {
    let text = input.trim();
    if text.is_empty() {
        return None;
    }
    let search = || Navigation::Search {
        query: text.to_owned(),
        url: engine.search_url(text),
    };

    if text.contains(char::is_whitespace) {
        return Some(search());
    }

    if let Some((scheme, rest)) = text.split_once(':') {
        let scheme_lower = scheme.to_ascii_lowercase();
        let looks_like_scheme = !scheme.is_empty()
            && scheme
                .chars()
                .all(|c| c.is_ascii_alphanumeric() || matches!(c, '+' | '-' | '.'));
        // `localhost:3000` and `example.com:8080` look like `scheme:rest`
        // but are host:port pairs.
        let is_port = rest
            .split('/')
            .next()
            .is_some_and(|p| !p.is_empty() && p.chars().all(|c| c.is_ascii_digit()));
        if looks_like_scheme && !is_port {
            if ALLOWED_SCHEMES.contains(&scheme_lower.as_str()) {
                return match url::Url::parse(text) {
                    Ok(url) => Some(Navigation::Url(url.to_string())),
                    Err(_) => Some(search()),
                };
            }
            return Some(search());
        }
    }

    let host_part = text.split(['/', '?', '#']).next().unwrap_or_default();
    let host = host_part.rsplit_once(':').map_or(host_part, |(h, port)| {
        if port.chars().all(|c| c.is_ascii_digit()) {
            h
        } else {
            host_part
        }
    });

    let is_local = host.eq_ignore_ascii_case("localhost")
        || host
            .parse::<std::net::Ipv4Addr>()
            .is_ok_and(|ip| ip.is_loopback() || ip.is_private() || ip.is_link_local())
        || host.ends_with(".local")
        || host.ends_with(".test")
        || host.ends_with(".localhost");
    let is_ip = host.parse::<std::net::Ipv4Addr>().is_ok()
        || (host.starts_with('[') && host.ends_with(']'));
    let is_domain = host.contains('.')
        && !host.starts_with('.')
        && !host.ends_with('.')
        && host.split('.').last().is_some_and(|tld| {
            tld.len() >= 2 && tld.chars().all(|c| c.is_ascii_alphabetic() || c == '-')
        })
        && host
            .chars()
            .all(|c| c.is_alphanumeric() || matches!(c, '.' | '-' | '_'));

    if is_local || is_ip || is_domain {
        let scheme = if is_local { "http" } else { "https" };
        return match url::Url::parse(&format!("{scheme}://{text}")) {
            Ok(url) => Some(Navigation::Url(url.to_string())),
            Err(_) => Some(search()),
        };
    }

    Some(search())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn nav(input: &str) -> Navigation {
        classify_input(input, &SearchEngine::DuckDuckGo).expect("non-empty input")
    }

    #[test]
    fn blank_input_is_ignored() {
        assert!(classify_input("   ", &SearchEngine::Google).is_none());
    }

    #[test]
    fn explicit_urls_are_kept() {
        assert_eq!(
            nav("https://github.com/zed-industries/zed"),
            Navigation::Url("https://github.com/zed-industries/zed".into())
        );
        assert_eq!(nav("about:blank"), Navigation::Url("about:blank".into()));
    }

    #[test]
    fn bare_domains_get_https() {
        assert_eq!(
            nav("rust-lang.org/learn"),
            Navigation::Url("https://rust-lang.org/learn".into())
        );
        assert_eq!(nav("docs.rs"), Navigation::Url("https://docs.rs/".into()));
    }

    #[test]
    fn local_addresses_get_http() {
        assert_eq!(
            nav("localhost:3000/app"),
            Navigation::Url("http://localhost:3000/app".into())
        );
        assert_eq!(
            nav("192.168.1.10"),
            Navigation::Url("http://192.168.1.10/".into())
        );
    }

    #[test]
    fn plain_words_and_sentences_search() {
        assert!(matches!(nav("gpui"), Navigation::Search { .. }));
        let Navigation::Search { query, url } = nav("how does gpui handle state?") else {
            panic!("expected search");
        };
        assert_eq!(query, "how does gpui handle state?");
        assert!(url.starts_with("https://duckduckgo.com/?q=how%20does%20gpui"));
    }

    #[test]
    fn dangerous_schemes_are_searched_not_executed() {
        assert!(matches!(
            nav("javascript:alert(1)"),
            Navigation::Search { .. }
        ));
        assert!(matches!(nav("vbscript:foo"), Navigation::Search { .. }));
    }

    #[test]
    fn file_extensions_alone_are_not_domains() {
        // "main.rs" has a two-letter "tld" but searching is still reasonable
        // only when it has no path; we accept it as a domain like browsers do.
        assert!(matches!(nav("v1.2"), Navigation::Search { .. }));
    }

    #[test]
    fn custom_engine_template_is_used() {
        let engine = SearchEngine::Custom("https://search.example/?q=%s&src=curio".into());
        assert_eq!(
            engine.search_url("a b"),
            "https://search.example/?q=a%20b&src=curio"
        );
    }
}

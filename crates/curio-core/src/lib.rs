//! Shared models, identifiers and utilities used across Curio's crates.
//!
//! This crate has no UI or engine dependencies so it can be unit tested in
//! isolation and reused by every other layer.

pub mod chat;
pub mod color;
pub mod ids;
pub mod omnibox;
pub mod tab;
pub mod time;

pub use color::AccentColor;
pub use ids::{ConversationId, FavoriteId, GroupId, MessageId, SpaceId, TabId};
pub use omnibox::{Navigation, SearchEngine, classify_input};
pub use tab::{Favorite, Tab, TabGroup};

/// The product name, used for window titles, menus and data directories.
pub const APP_NAME: &str = "Curio";

/// Reverse-DNS bundle identifier for the macOS application bundle and
/// platform keychain entries.
pub const BUNDLE_ID: &str = "app.curio.browser";

/// The page shown for new tabs that have not navigated anywhere yet.
pub const NEW_TAB_URL: &str = "curio://newtab";

/// Returns `true` for Curio's internal pages, which are rendered by GPUI and
/// never handed to the web engine.
#[must_use]
pub fn is_internal_url(url: &str) -> bool {
    url.starts_with("curio://")
}

/// Extracts a short, human readable host for display, without `www.`.
#[must_use]
pub fn display_host(url: &str) -> String {
    if is_internal_url(url) {
        return APP_NAME.to_owned();
    }
    match url::Url::parse(url) {
        Ok(parsed) => match parsed.host_str() {
            Some(host) => host.strip_prefix("www.").unwrap_or(host).to_owned(),
            None => url.to_owned(),
        },
        Err(_) => url.to_owned(),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn display_host_strips_www_and_path() {
        assert_eq!(
            display_host("https://www.example.com/a/b?c=d"),
            "example.com"
        );
        assert_eq!(display_host("http://localhost:8080/x"), "localhost");
        assert_eq!(display_host(NEW_TAB_URL), "Curio");
        assert_eq!(display_host("not a url"), "not a url");
    }
}

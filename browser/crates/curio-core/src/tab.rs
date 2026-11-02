//! Persisted tab, group and favorite records.

use serde::{Deserialize, Serialize};

use crate::color::AccentColor;
use crate::ids::{FavoriteId, GroupId, TabId};
use crate::time::{Timestamp, now_ms};
use crate::{NEW_TAB_URL, display_host};

/// A browser tab's persisted state. Live engine state (the webview itself,
/// loading progress, history stack) lives in the browser layer.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct Tab {
    pub id: TabId,
    /// The URL currently displayed.
    pub url: String,
    /// The page title, or empty when unknown.
    pub title: String,
    /// The page's favicon URL, when one was discovered.
    pub favicon_url: Option<String>,
    /// For pinned tabs and favorites: the URL the tab returns to when reset.
    pub home_url: Option<String>,
    /// The last known vertical scroll offset, restored when a discarded tab
    /// is reloaded.
    pub scroll_y: f64,
    pub created_at: Timestamp,
    pub last_active_at: Timestamp,
}

impl Default for Tab {
    fn default() -> Self {
        let now = now_ms();
        Self {
            id: TabId::new(),
            url: NEW_TAB_URL.to_owned(),
            title: String::new(),
            favicon_url: None,
            home_url: None,
            scroll_y: 0.0,
            created_at: now,
            last_active_at: now,
        }
    }
}

impl Tab {
    /// Creates a tab pointing at `url`.
    #[must_use]
    pub fn new(url: impl Into<String>) -> Self {
        Self {
            url: url.into(),
            ..Self::default()
        }
    }

    /// The title to show in the UI, falling back to the host when the page
    /// has not reported a title.
    #[must_use]
    pub fn display_title(&self) -> String {
        if !self.title.trim().is_empty() {
            self.title.trim().to_owned()
        } else if self.url == NEW_TAB_URL {
            "New Tab".to_owned()
        } else {
            display_host(&self.url)
        }
    }

    /// Returns `true` while the tab shows Curio's new tab page.
    #[must_use]
    pub fn is_new_tab_page(&self) -> bool {
        self.url == NEW_TAB_URL
    }

    /// Creates a copy with a fresh identity, as used by "Duplicate Tab".
    #[must_use]
    pub fn duplicate(&self) -> Self {
        let now = now_ms();
        Self {
            id: TabId::new(),
            created_at: now,
            last_active_at: now,
            ..self.clone()
        }
    }
}

/// A named, collapsible group of tabs (a folder in the sidebar).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct TabGroup {
    pub id: GroupId,
    pub name: String,
    pub color: AccentColor,
    pub collapsed: bool,
    /// Member tabs in display order.
    pub tabs: Vec<TabId>,
}

impl Default for TabGroup {
    fn default() -> Self {
        Self {
            id: GroupId::new(),
            name: "New Group".to_owned(),
            color: AccentColor::default(),
            collapsed: false,
            tabs: Vec::new(),
        }
    }
}

impl TabGroup {
    /// Creates an empty, expanded group.
    #[must_use]
    pub fn new(name: impl Into<String>, color: AccentColor) -> Self {
        Self {
            name: name.into(),
            color,
            ..Self::default()
        }
    }
}

/// A global favorite: a site pinned above every space. Each favorite owns a
/// tab so its page state survives switching spaces, like Arc.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Favorite {
    pub id: FavoriteId,
    pub tab: Tab,
}

impl Favorite {
    /// Creates a favorite whose home is `url`.
    #[must_use]
    pub fn new(url: impl Into<String>, title: impl Into<String>) -> Self {
        let url = url.into();
        let mut tab = Tab::new(url.clone());
        tab.title = title.into();
        tab.home_url = Some(url);
        Self {
            id: FavoriteId::new(),
            tab,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn display_title_falls_back_to_host() {
        let mut tab = Tab::new("https://www.rust-lang.org/learn");
        assert_eq!(tab.display_title(), "rust-lang.org");
        tab.title = "  Learn Rust ".to_owned();
        assert_eq!(tab.display_title(), "Learn Rust");
        assert_eq!(Tab::default().display_title(), "New Tab");
    }

    #[test]
    fn duplicate_gets_new_identity_but_same_page() {
        let mut tab = Tab::new("https://example.com");
        tab.scroll_y = 320.0;
        let copy = tab.duplicate();
        assert_ne!(copy.id, tab.id);
        assert_eq!(copy.url, tab.url);
        assert!((copy.scroll_y - tab.scroll_y).abs() < f64::EPSILON);
    }

    #[test]
    fn tab_deserializes_with_missing_fields() {
        let tab: Tab = serde_json::from_str(r#"{"url":"https://a.dev"}"#).expect("parse");
        assert_eq!(tab.url, "https://a.dev");
        assert!(tab.favicon_url.is_none());
    }
}

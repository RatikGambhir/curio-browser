//! Persisted tab, group and favorite records.

use serde::{Deserialize, Serialize};

use crate::color::AccentColor;
use crate::ids::{FavoriteId, GroupId, SplitId, TabId};
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

/// How the panes of a split view are arranged.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum SplitOrientation {
    /// Side by side, left to right.
    #[default]
    Horizontal,
    /// Stacked, top to bottom.
    Vertical,
}

impl SplitOrientation {
    /// The other orientation.
    #[must_use]
    pub const fn flipped(self) -> Self {
        match self {
            Self::Horizontal => Self::Vertical,
            Self::Vertical => Self::Horizontal,
        }
    }
}

/// Two to four tabs shown side by side in one window, like Arc's and Dia's
/// split view. The member tabs stay ordinary tabs of their space (and
/// folder); the split only records which of them are shown together and
/// how much room each pane gets.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct TabSplit {
    pub id: SplitId,
    /// Member tabs, in pane order (left to right, or top to bottom).
    pub tabs: Vec<TabId>,
    /// Each pane's share of the split, parallel to `tabs`. Sums to 1.
    pub sizes: Vec<f32>,
    pub orientation: SplitOrientation,
}

impl TabSplit {
    /// The fewest tabs a split holds; with fewer it dissolves.
    pub const MIN_PANES: usize = 2;
    /// The most tabs a split holds.
    pub const MAX_PANES: usize = 4;
    /// The smallest share a pane can be resized to.
    pub const MIN_SIZE: f32 = 0.15;

    /// Creates a split with equal panes. Duplicate ids are dropped and only
    /// the first [`TabSplit::MAX_PANES`] tabs are kept.
    #[must_use]
    pub fn new(tabs: &[TabId], orientation: SplitOrientation) -> Self {
        let mut split = Self {
            tabs: Vec::with_capacity(tabs.len().min(Self::MAX_PANES)),
            orientation,
            ..Self::default()
        };
        for id in tabs {
            if split.tabs.len() < Self::MAX_PANES && !split.tabs.contains(id) {
                split.tabs.push(*id);
            }
        }
        split.equalize();
        split
    }

    /// Whether `id` is one of the panes.
    #[must_use]
    pub fn contains(&self, id: TabId) -> bool {
        self.tabs.contains(&id)
    }

    /// Whether the split still has enough panes to be shown.
    #[must_use]
    pub fn is_valid(&self) -> bool {
        (Self::MIN_PANES..=Self::MAX_PANES).contains(&self.tabs.len())
    }

    /// Whether another pane can be added.
    #[must_use]
    pub fn is_full(&self) -> bool {
        self.tabs.len() >= Self::MAX_PANES
    }

    /// Gives every pane the same share.
    pub fn equalize(&mut self) {
        let n = self.tabs.len().max(1);
        #[allow(clippy::cast_precision_loss)] // At most four panes.
        let share = 1.0 / n as f32;
        self.sizes = vec![share; self.tabs.len()];
    }

    /// Repairs `sizes` after loading or editing: one finite, positive share
    /// per pane, summing to 1. Anything unusable resets to equal panes.
    pub fn normalize(&mut self) {
        let usable = self.sizes.len() == self.tabs.len()
            && self.sizes.iter().all(|s| s.is_finite() && *s > 0.0);
        let total: f32 = self.sizes.iter().sum();
        if !usable || total <= f32::EPSILON {
            self.equalize();
            return;
        }
        for size in &mut self.sizes {
            *size /= total;
        }
    }

    /// Adds a pane at `index` (clamped to the end), splitting the room
    /// evenly. Returns `false` when the split is full or already has the tab.
    pub fn add_tab(&mut self, id: TabId, index: usize) -> bool {
        if self.is_full() || self.contains(id) {
            return false;
        }
        self.tabs.insert(index.min(self.tabs.len()), id);
        self.equalize();
        true
    }

    /// Removes a pane, giving its room to its neighbors. Returns `false`
    /// when the tab isn't a pane.
    pub fn remove_tab(&mut self, id: TabId) -> bool {
        let Some(index) = self.tabs.iter().position(|t| *t == id) else {
            return false;
        };
        self.tabs.remove(index);
        let freed = if index < self.sizes.len() {
            self.sizes.remove(index)
        } else {
            0.0
        };
        // The pane before takes the room, or the one after for the first.
        let heir = index
            .saturating_sub(1)
            .min(self.sizes.len().saturating_sub(1));
        if let Some(size) = self.sizes.get_mut(heir) {
            *size += freed;
        }
        self.normalize();
        true
    }

    /// Moves the divider after pane `divider` by `delta` (a share of the
    /// whole split), keeping both neighbors at least [`TabSplit::MIN_SIZE`].
    /// Returns `true` when anything moved.
    pub fn resize(&mut self, divider: usize, delta: f32) -> bool {
        if !delta.is_finite() || divider + 1 >= self.sizes.len() {
            return false;
        }
        let (before, after) = (self.sizes[divider], self.sizes[divider + 1]);
        let pair = before + after;
        // Panes already smaller than the minimum may still be resized.
        let min = Self::MIN_SIZE.min(pair / 2.0);
        let next = (before + delta).clamp(min, pair - min);
        if (next - before).abs() < f32::EPSILON {
            return false;
        }
        self.sizes[divider] = next;
        self.sizes[divider + 1] = pair - next;
        true
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
    fn split_starts_with_equal_unique_panes() {
        let a = TabId::new();
        let b = TabId::new();
        let split = TabSplit::new(&[a, b, a], SplitOrientation::Horizontal);
        assert_eq!(split.tabs, vec![a, b]);
        assert_eq!(split.sizes, vec![0.5, 0.5]);
        assert!(split.is_valid());

        let many: Vec<TabId> = (0..6).map(|_| TabId::new()).collect();
        let split = TabSplit::new(&many, SplitOrientation::Vertical);
        assert_eq!(split.tabs.len(), TabSplit::MAX_PANES);
        assert!(split.is_full());
    }

    #[test]
    fn split_resize_keeps_panes_above_the_minimum() {
        let mut split = TabSplit::new(&[TabId::new(), TabId::new()], SplitOrientation::Horizontal);
        assert!(split.resize(0, 0.2));
        assert!((split.sizes[0] - 0.7).abs() < 1e-5);
        assert!((split.sizes[1] - 0.3).abs() < 1e-5);
        split.resize(0, 5.0);
        assert!((split.sizes[1] - TabSplit::MIN_SIZE).abs() < 1e-5);
        assert!(!split.resize(1, 0.1), "no divider after the last pane");
        assert!(!split.resize(0, f32::NAN));
    }

    #[test]
    fn removing_a_pane_gives_its_room_to_a_neighbor() {
        let ids: Vec<TabId> = (0..3).map(|_| TabId::new()).collect();
        let mut split = TabSplit::new(&ids, SplitOrientation::Horizontal);
        split.sizes = vec![0.5, 0.25, 0.25];
        assert!(split.remove_tab(ids[1]));
        assert_eq!(split.tabs, vec![ids[0], ids[2]]);
        assert!((split.sizes[0] - 0.75).abs() < 1e-5);
        assert!(split.remove_tab(ids[0]));
        assert!(!split.is_valid());
    }

    #[test]
    fn split_normalize_repairs_bad_sizes() {
        let mut split = TabSplit::new(&[TabId::new(), TabId::new()], SplitOrientation::Horizontal);
        split.sizes = vec![2.0, 6.0];
        split.normalize();
        assert!((split.sizes[0] - 0.25).abs() < 1e-5);
        split.sizes = vec![f32::NAN];
        split.normalize();
        assert_eq!(split.sizes, vec![0.5, 0.5]);
        let mut grown = split.clone();
        assert!(grown.add_tab(TabId::new(), 1));
        assert_eq!(grown.tabs[0], split.tabs[0]);
        assert_eq!(grown.tabs[2], split.tabs[1]);
    }

    #[test]
    fn tab_deserializes_with_missing_fields() {
        let tab: Tab = serde_json::from_str(r#"{"url":"https://a.dev"}"#).expect("parse");
        assert_eq!(tab.url, "https://a.dev");
        assert!(tab.favicon_url.is_none());
    }
}

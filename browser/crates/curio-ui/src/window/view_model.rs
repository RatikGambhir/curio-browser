//! Plain data the window's render code reads, gathered once per render.
//!
//! Keeping these lookups here means the sidebar, the tab strip and both
//! toolbars agree on what a tab or the address bar shows.

use curio_core::{TabId, display_host};
use gpui_kit::assets::IconName;
use gpui_kit::{App, SharedString};

use super::{BrowserWindow, DraggedTab};

/// What a tab row or strip tab needs to draw one tab.
#[derive(Debug, Clone)]
pub(super) struct TabView {
    pub id: TabId,
    pub title: String,
    pub favicon: Option<String>,
    pub active: bool,
    pub pinned: bool,
    pub loading: bool,
    /// The page is not loaded (the tab is asleep or was never opened).
    pub asleep: bool,
}

impl TabView {
    /// The payload for dragging this tab.
    pub fn drag(&self) -> DraggedTab {
        DraggedTab {
            id: self.id,
            title: SharedString::from(self.title.clone()),
            favicon: self.favicon.clone(),
        }
    }
}

/// The active page's navigation and address state.
#[derive(Debug, Clone, Default, PartialEq)]
pub(super) struct PageNav {
    pub can_go_back: bool,
    pub can_go_forward: bool,
    pub loading: bool,
    pub secure: bool,
    pub zoom: f64,
    /// The address and title, or `None` on the new tab page.
    pub page: Option<PageInfo>,
}

/// The address and title of a loaded page.
#[derive(Debug, Clone, PartialEq)]
pub(super) struct PageInfo {
    pub url: String,
    pub host: String,
    pub title: String,
}

impl PageNav {
    /// The icon before the address: search, a lock or a globe.
    pub fn address_icon(&self) -> IconName {
        match &self.page {
            None => IconName::Search,
            Some(_) if self.secure => IconName::Lock,
            Some(_) => IconName::Globe,
        }
    }

    /// "125%" when the page is zoomed, otherwise `None`.
    pub fn zoom_label(&self) -> Option<SharedString> {
        ((self.zoom - 1.0).abs() > 0.01).then(|| format!("{:.0}%", self.zoom * 100.0).into())
    }
}

impl BrowserWindow {
    /// Gathers what a row needs to draw tab `id`.
    pub(super) fn tab_view(&self, id: TabId, cx: &App) -> Option<TabView> {
        let tab = self.workspace.tab(id)?;
        let live = self.tabs.get(&id).map(|e| e.read(cx));
        Some(TabView {
            id,
            title: tab.display_title(),
            favicon: tab.favicon_url.clone(),
            active: self.workspace.active_tab_id() == Some(id),
            pinned: self.workspace.active_space().strip.is_pinned(id),
            loading: live.is_some_and(|t| t.state().loading),
            asleep: !live.is_some_and(|t| t.is_awake()),
        })
    }

    /// Gathers the active page's navigation state.
    pub(super) fn page_nav(&self, cx: &App) -> PageNav {
        let state = self.active_tab_entity().map(|t| t.read(cx).state());
        let page = self
            .workspace
            .active_tab()
            .filter(|t| !t.is_new_tab_page())
            .map(|t| PageInfo {
                url: t.url.clone(),
                host: display_host(&t.url),
                title: t.display_title(),
            });
        PageNav {
            can_go_back: state.is_some_and(|s| s.history.can_go_back),
            can_go_forward: state.is_some_and(|s| s.history.can_go_forward),
            loading: state.is_some_and(|s| s.loading),
            secure: state.is_some_and(|s| s.secure)
                || page.as_ref().is_some_and(|p| p.url.starts_with("https:")),
            zoom: state.map_or(1.0, |s| s.zoom),
            page,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn page() -> PageInfo {
        PageInfo {
            url: "https://example.com/".to_owned(),
            host: "example.com".to_owned(),
            title: "Example".to_owned(),
        }
    }

    #[test]
    fn address_icon_reflects_page_and_security() {
        let mut nav = PageNav::default();
        assert_eq!(nav.address_icon(), IconName::Search);
        nav.page = Some(page());
        assert_eq!(nav.address_icon(), IconName::Globe);
        nav.secure = true;
        assert_eq!(nav.address_icon(), IconName::Lock);
    }

    #[test]
    fn zoom_label_only_when_zoomed() {
        let nav = PageNav {
            zoom: 1.0,
            ..PageNav::default()
        };
        assert_eq!(nav.zoom_label(), None);
        let nav = PageNav {
            zoom: 1.25,
            ..PageNav::default()
        };
        assert_eq!(nav.zoom_label().as_deref(), Some("125%"));
    }
}

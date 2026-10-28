//! The command bar: one place to type a URL, search the web, jump to an open
//! tab, revisit history or bookmarks, run a browser command, or ask Curio.

use curio_core::omnibox::{Navigation, classify_input};
use curio_core::{SearchEngine, TabId, display_host};
use curio_storage::{Bookmark, HistoryEntry};
use gpui_kit::component::input::{Input, InputEvent, InputState};
use gpui_kit::component::{Icon, Sizable as _, h_flex, v_flex};
use gpui_kit::assets::IconName;
use gpui_kit::{
    AnyElement, AppContext as _, Context, Entity, EventEmitter, FocusHandle, Focusable,
    FontWeight, InteractiveElement as _, IntoElement, KeyDownEvent, ParentElement as _, Render,
    ScrollHandle, SharedString, StatefulInteractiveElement as _, Styled as _, Subscription, Task,
    Window, div, px,
};

use crate::components::{favicon, shortcut_hint};
use crate::theme::CurioTheme;
use crate::{Services, settings};

/// What the command bar was opened for.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CommandMode {
    /// Opening a new tab (⌘T): navigation creates a tab.
    NewTab,
    /// Editing the current tab's address (⌘L): navigation replaces the page.
    EditUrl,
    /// The command palette (⌘K): commands first.
    Palette,
}

/// What executing an item does.
#[derive(Debug, Clone, PartialEq)]
pub enum CommandTarget {
    Navigate { url: String, new_tab: bool },
    SwitchTab(TabId),
    /// Dispatch the GPUI action with this name.
    Action(SharedString),
    AskAi(String),
}

/// Events for the window that owns the bar.
#[derive(Debug, Clone, PartialEq)]
pub enum CommandBarEvent {
    Dismissed,
    Execute(CommandTarget),
}

/// An open tab offered as a "Switch to Tab" result.
#[derive(Debug, Clone)]
pub struct TabSuggestion {
    pub id: TabId,
    pub title: String,
    pub url: String,
    pub favicon: Option<String>,
    pub space: String,
}

#[derive(Debug, Clone)]
enum ItemIcon {
    Icon(IconName),
    Site(Option<String>, String),
}

#[derive(Debug, Clone)]
struct Item {
    key: SharedString,
    icon: ItemIcon,
    title: SharedString,
    subtitle: Option<SharedString>,
    badge: Option<&'static str>,
    target: CommandTarget,
}

/// Browser commands offered in the palette: (action name, label, icon).
const COMMANDS: &[(&str, &str, IconName)] = &[
    ("curio::NewSpace", "New Space", IconName::Plus),
    ("curio::ToggleAiPanel", "Toggle Curio Assistant", IconName::Bot),
    ("curio::AskAboutPage", "Summarize This Page", IconName::Sparkles),
    ("curio::NewChat", "New Chat", IconName::MessageSquare),
    ("curio::ToggleSidebar", "Toggle Sidebar", IconName::PanelLeft),
    ("curio::ToggleTabLayout", "Switch Vertical / Horizontal Tabs", IconName::LayoutDashboard),
    ("curio::PinTab", "Pin or Unpin Tab", IconName::Star),
    ("curio::AddFavorite", "Add Tab to Favorites", IconName::Heart),
    ("curio::ToggleBookmark", "Bookmark Page", IconName::BookOpen),
    ("curio::DuplicateTab", "Duplicate Tab", IconName::Copy),
    ("curio::NewGroupFromTab", "New Group from Tab", IconName::Folder),
    ("curio::CopyUrl", "Copy URL", IconName::Link),
    ("curio::ReopenClosedTab", "Reopen Closed Tab", IconName::Undo2),
    ("curio::CloseTab", "Close Tab", IconName::X),
    ("curio::FindInPage", "Find in Page", IconName::Search),
    ("curio::ShowHistory", "Show History", IconName::CalendarClock),
    ("curio::ShowDownloads", "Show Downloads", IconName::ArrowDown),
    ("curio::OpenSettings", "Settings", IconName::Settings),
    ("curio::ZoomIn", "Zoom In", IconName::Plus),
    ("curio::ZoomOut", "Zoom Out", IconName::Minus),
    ("curio::ZoomReset", "Actual Size", IconName::Maximize),
    ("curio::OpenDevTools", "Developer Tools", IconName::SquareTerminal),
    ("curio::NextSpace", "Next Space", IconName::ChevronRight),
    ("curio::PreviousSpace", "Previous Space", IconName::ChevronLeft),
];

/// Whether every whitespace-separated term of `query` occurs in `haystack`.
fn matches_all(query: &str, haystack: &str) -> bool {
    let haystack = haystack.to_lowercase();
    query
        .to_lowercase()
        .split_whitespace()
        .all(|term| haystack.contains(term))
}

/// The command bar view.
pub struct CommandBar {
    input: Entity<InputState>,
    mode: CommandMode,
    tabs: Vec<TabSuggestion>,
    history: Vec<HistoryEntry>,
    bookmarks: Vec<Bookmark>,
    items: Vec<Item>,
    selected: usize,
    scroll: ScrollHandle,
    query_task: Task<()>,
    query_generation: u64,
    _subscriptions: Vec<Subscription>,
}

impl EventEmitter<CommandBarEvent> for CommandBar {}

impl Focusable for CommandBar {
    fn focus_handle(&self, cx: &gpui_kit::App) -> FocusHandle {
        self.input.read(cx).focus_handle(cx)
    }
}

impl CommandBar {
    /// Creates a hidden command bar.
    pub fn new(window: &mut Window, cx: &mut Context<Self>) -> Self {
        let input = cx.new(|cx| {
            InputState::new(window, cx).placeholder("Search, enter a URL, or ask Curio…")
        });
        let subscription = cx.subscribe_in(&input, window, |this, _, event, _, cx| {
            if matches!(event, InputEvent::Change) {
                this.refresh(cx);
            }
        });
        Self {
            input,
            mode: CommandMode::NewTab,
            tabs: Vec::new(),
            history: Vec::new(),
            bookmarks: Vec::new(),
            items: Vec::new(),
            selected: 0,
            scroll: ScrollHandle::new(),
            query_task: Task::ready(()),
            query_generation: 0,
            _subscriptions: vec![subscription],
        }
    }

    /// Prepares the bar for display.
    pub fn open(
        &mut self,
        mode: CommandMode,
        text: &str,
        tabs: Vec<TabSuggestion>,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        self.mode = mode;
        self.tabs = tabs;
        self.history.clear();
        self.bookmarks.clear();
        self.input.update(cx, |input, cx| {
            input.set_value(text.to_owned(), window, cx);
            input.select_all(window, cx);
        });
        let handle = self.input.read(cx).focus_handle(cx);
        window.focus(&handle, cx);
        self.refresh(cx);
    }

    fn query(&self, cx: &gpui_kit::App) -> String {
        self.input.read(cx).value().trim().to_owned()
    }

    /// Re-runs the async history/bookmark lookup and rebuilds results.
    fn refresh(&mut self, cx: &mut Context<Self>) {
        self.rebuild(cx);
        let query = self.query(cx);
        self.query_generation += 1;
        let generation = self.query_generation;
        let storage = Services::get(cx).storage.clone();
        let background = cx.background_executor().clone();
        self.query_task = cx.spawn(async move |this, cx| {
            let (history, bookmarks) = background
                .spawn(async move {
                    storage.with(|db| {
                        let history = if query.is_empty() {
                            db.recent_history(30).unwrap_or_default()
                        } else {
                            db.search_history(&query, 8).unwrap_or_default()
                        };
                        let bookmarks = if query.is_empty() {
                            Vec::new()
                        } else {
                            db.bookmarks(&query, 4).unwrap_or_default()
                        };
                        (history, bookmarks)
                    })
                })
                .await;
            let _ = this.update(cx, |this, cx| {
                if this.query_generation == generation {
                    this.history = history;
                    this.bookmarks = bookmarks;
                    this.rebuild(cx);
                }
            });
        });
    }

    fn rebuild(&mut self, cx: &mut Context<Self>) {
        let query = self.query(cx);
        let engine: SearchEngine = settings(cx).browsing.search_engine.clone();
        let new_tab = self.mode == CommandMode::NewTab;
        let mut items: Vec<Item> = Vec::new();
        let mut seen_urls = std::collections::HashSet::new();

        let push_commands = |items: &mut Vec<Item>, limit: usize| {
            for (action, label, icon) in COMMANDS
                .iter()
                .filter(|(_, label, _)| query.is_empty() || matches_all(&query, label))
                .take(limit)
            {
                items.push(Item {
                    key: SharedString::from(format!("cmd:{action}")),
                    icon: ItemIcon::Icon(*icon),
                    title: SharedString::from(*label),
                    subtitle: None,
                    badge: Some("Command"),
                    target: CommandTarget::Action(SharedString::from(*action)),
                });
            }
        };

        if self.mode == CommandMode::Palette {
            push_commands(&mut items, if query.is_empty() { COMMANDS.len() } else { 6 });
        }

        if let Some(nav) = classify_input(&query, &engine) {
            match nav {
                Navigation::Url(url) => {
                    seen_urls.insert(url.clone());
                    items.push(Item {
                        key: "primary".into(),
                        icon: ItemIcon::Icon(IconName::Globe),
                        title: SharedString::from(display_host(&url)),
                        subtitle: Some(SharedString::from(url.clone())),
                        badge: Some(if new_tab { "Open" } else { "Go" }),
                        target: CommandTarget::Navigate { url, new_tab },
                    });
                }
                Navigation::Search { query: q, url } => {
                    items.push(Item {
                        key: "primary".into(),
                        icon: ItemIcon::Icon(IconName::Search),
                        title: SharedString::from(q),
                        subtitle: Some(SharedString::from(format!("Search {}", engine.label()))),
                        badge: Some("Search"),
                        target: CommandTarget::Navigate { url, new_tab },
                    });
                }
            }
        }

        // Open tabs.
        let tab_matches = self
            .tabs
            .iter()
            .filter(|t| {
                !query.is_empty() && matches_all(&query, &format!("{} {}", t.title, t.url))
            })
            .take(5);
        for tab in tab_matches {
            seen_urls.insert(tab.url.clone());
            items.push(Item {
                key: SharedString::from(format!("tab:{}", tab.id)),
                icon: ItemIcon::Site(tab.favicon.clone(), tab.title.clone()),
                title: SharedString::from(if tab.title.is_empty() {
                    display_host(&tab.url)
                } else {
                    tab.title.clone()
                }),
                subtitle: Some(SharedString::from(format!("{} · {}", tab.space, display_host(&tab.url)))),
                badge: Some("Switch to Tab"),
                target: CommandTarget::SwitchTab(tab.id),
            });
        }

        // Ask Curio.
        if !query.is_empty()
            && (query.contains(' ') || query.ends_with('?'))
            && self.mode != CommandMode::EditUrl
        {
            items.push(Item {
                key: "ask".into(),
                icon: ItemIcon::Icon(IconName::Sparkles),
                title: SharedString::from(query.clone()),
                subtitle: Some("Ask Curio".into()),
                badge: Some("Ask"),
                target: CommandTarget::AskAi(query.clone()),
            });
        }

        for bookmark in &self.bookmarks {
            if !seen_urls.insert(bookmark.url.clone()) {
                continue;
            }
            items.push(Item {
                key: SharedString::from(format!("bm:{}", bookmark.url)),
                icon: ItemIcon::Site(None, display_host(&bookmark.url)),
                title: SharedString::from(if bookmark.title.is_empty() {
                    display_host(&bookmark.url)
                } else {
                    bookmark.title.clone()
                }),
                subtitle: Some(SharedString::from(bookmark.url.clone())),
                badge: Some("Bookmark"),
                target: CommandTarget::Navigate {
                    url: bookmark.url.clone(),
                    new_tab,
                },
            });
        }

        let history_limit = if query.is_empty() { 6 } else { 6 };
        for entry in self
            .history
            .iter()
            .filter(|h| seen_urls.insert(h.url.clone()))
            .take(history_limit)
        {
            items.push(Item {
                key: SharedString::from(format!("hist:{}", entry.url)),
                icon: ItemIcon::Site(None, display_host(&entry.url)),
                title: SharedString::from(if entry.title.is_empty() {
                    display_host(&entry.url)
                } else {
                    entry.title.clone()
                }),
                subtitle: Some(SharedString::from(entry.url.clone())),
                badge: Some(if query.is_empty() { "Recent" } else { "History" }),
                target: CommandTarget::Navigate {
                    url: entry.url.clone(),
                    new_tab,
                },
            });
        }

        if self.mode != CommandMode::Palette && !query.is_empty() {
            push_commands(&mut items, 3);
        }

        self.items = items;
        self.selected = self.selected.min(self.items.len().saturating_sub(1));
        if self.query_generation == 0 || !query.is_empty() {
            self.selected = 0;
        }
        cx.notify();
    }

    fn move_selection(&mut self, delta: isize, cx: &mut Context<Self>) {
        if self.items.is_empty() {
            return;
        }
        let len = self.items.len() as isize;
        self.selected = ((self.selected as isize + delta).rem_euclid(len)) as usize;
        self.scroll.scroll_to_item(self.selected);
        cx.notify();
    }

    fn execute(&mut self, index: usize, cx: &mut Context<Self>) {
        if let Some(item) = self.items.get(index) {
            cx.emit(CommandBarEvent::Execute(item.target.clone()));
        }
    }

    fn on_key(&mut self, event: &KeyDownEvent, _: &mut Window, cx: &mut Context<Self>) {
        let keystroke = &event.keystroke;
        match keystroke.key.as_str() {
            "up" => {
                self.move_selection(-1, cx);
                cx.stop_propagation();
            }
            "down" => {
                self.move_selection(1, cx);
                cx.stop_propagation();
            }
            "tab" if !keystroke.modifiers.control => {
                self.move_selection(if keystroke.modifiers.shift { -1 } else { 1 }, cx);
                cx.stop_propagation();
            }
            "enter" => {
                self.execute(self.selected, cx);
                cx.stop_propagation();
            }
            "escape" => {
                cx.emit(CommandBarEvent::Dismissed);
                cx.stop_propagation();
            }
            _ => {}
        }
    }

    fn render_item(&self, index: usize, item: &Item, cx: &mut Context<Self>) -> AnyElement {
        let theme = *CurioTheme::get(cx);
        let selected = index == self.selected;
        let icon: AnyElement = match &item.icon {
            ItemIcon::Icon(icon) => div()
                .size(px(26.))
                .rounded(px(7.))
                .flex()
                .items_center()
                .justify_center()
                .bg(if selected { theme.accent_soft } else { theme.row_hover })
                .text_color(if selected { theme.accent_text } else { theme.text_muted })
                .child(Icon::new(icon.clone()).small())
                .into_any_element(),
            ItemIcon::Site(url, label) => div()
                .size(px(26.))
                .flex()
                .items_center()
                .justify_center()
                .child(favicon(url.as_deref(), label, px(18.)))
                .into_any_element(),
        };
        h_flex()
            .id(item.key.clone())
            .h(px(46.))
            .px(px(10.))
            .gap(px(12.))
            .rounded(px(9.))
            .when(selected, |el| el.bg(theme.accent_soft))
            .when(!selected, |el| el.hover(|s| s.bg(theme.row_hover)))
            .cursor_pointer()
            .on_click(cx.listener(move |this, _, _, cx| this.execute(index, cx)))
            .on_mouse_move(cx.listener(move |this, _, _, cx| {
                if this.selected != index {
                    this.selected = index;
                    cx.notify();
                }
            }))
            .child(icon)
            .child(
                v_flex()
                    .flex_1()
                    .min_w_0()
                    .child(
                        div()
                            .text_sm()
                            .font_weight(FontWeight::MEDIUM)
                            .text_color(theme.text)
                            .truncate()
                            .child(item.title.clone()),
                    )
                    .when_some(item.subtitle.clone(), |el, subtitle| {
                        el.child(
                            div()
                                .text_xs()
                                .text_color(theme.text_faint)
                                .truncate()
                                .child(subtitle),
                        )
                    }),
            )
            .when_some(item.badge, |el, badge| {
                el.child(
                    h_flex()
                        .gap(px(6.))
                        .text_xs()
                        .text_color(if selected { theme.accent_text } else { theme.text_faint })
                        .child(badge)
                        .when(selected, |el| el.child(Icon::new(IconName::CornerDownLeft).xsmall())),
                )
            })
            .into_any_element()
    }
}

use gpui_kit::prelude::FluentBuilder as _;

impl Render for CommandBar {
    fn render(&mut self, _: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let theme = *CurioTheme::get(cx);
        let (icon, hint) = match self.mode {
            CommandMode::NewTab => (IconName::Plus, "New Tab"),
            CommandMode::EditUrl => (IconName::Globe, "Go"),
            CommandMode::Palette => (IconName::Command, "Commands"),
        };
        let rows: Vec<AnyElement> = self
            .items
            .iter()
            .enumerate()
            .map(|(i, item)| self.render_item(i, item, cx))
            .collect();
        v_flex()
            .id("command-bar")
            .key_context("CommandBar")
            .capture_key_down(cx.listener(Self::on_key))
            .w(px(660.))
            .max_h(px(520.))
            .rounded(px(16.))
            .bg(theme.surface_raised)
            .border_1()
            .border_color(theme.surface_border)
            .shadow_2xl()
            .overflow_hidden()
            .child(
                h_flex()
                    .h(px(56.))
                    .px(px(16.))
                    .gap(px(10.))
                    .border_b_1()
                    .border_color(theme.divider)
                    .child(
                        div()
                            .text_color(theme.accent_text)
                            .child(Icon::new(icon).small()),
                    )
                    .child(
                        div()
                            .flex_1()
                            .text_size(px(16.))
                            .child(Input::new(&self.input).appearance(false).large()),
                    )
                    .child(shortcut_hint(hint, cx)),
            )
            .child(
                div()
                    .id("command-results")
                    .flex_1()
                    .overflow_y_scroll()
                    .track_scroll(&self.scroll)
                    .p(px(6.))
                    .children(rows),
            )
            .child(
                h_flex()
                    .h(px(30.))
                    .px(px(14.))
                    .gap(px(14.))
                    .border_t_1()
                    .border_color(theme.divider)
                    .text_xs()
                    .text_color(theme.text_faint)
                    .child("↑↓ to navigate")
                    .child("⏎ to open")
                    .child("esc to close"),
            )
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn matches_all_terms_case_insensitively() {
        assert!(matches_all("gpui state", "How GPUI handles State"));
        assert!(!matches_all("gpui react", "How GPUI handles State"));
        assert!(matches_all("", "anything"));
    }
}

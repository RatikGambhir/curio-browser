//! Tab and space orchestration: creating and releasing tab entities,
//! activation, navigation, and syncing live page state into the workspace.

use std::time::Duration;

use curio_ai::PageContext;
use curio_browser::{BrowserTab, BrowserTabEvent};
use curio_core::{NEW_TAB_URL, SpaceId, Tab, TabId, display_host, is_internal_url};
use curio_spaces::TabOwner;
use curio_tabs::{Placement, Section};
use gpui_kit::component::WindowExt as _;
use gpui_kit::component::notification::Notification;
use gpui_kit::Focusable as _;
use gpui_kit::{AppContext as _, Context, Entity, Window};

use super::{BrowserWindow, DownloadItem};
use crate::ai_panel::ContextTab;
use crate::command_bar::TabSuggestion;
use crate::{Services, actions, settings};

impl BrowserWindow {
    /// Open tabs offered by the command bar's "Switch to Tab".
    pub(crate) fn tab_suggestions(&self) -> Vec<TabSuggestion> {
        self.workspace
            .all_tabs()
            .filter(|(_, tab)| !tab.is_new_tab_page())
            .map(|(owner, tab)| TabSuggestion {
                id: tab.id,
                title: tab.display_title(),
                url: tab.url.clone(),
                favicon: tab.favicon_url.clone(),
                space: match owner {
                    TabOwner::Favorite(_) => "Favorites".to_owned(),
                    TabOwner::Space(space) => self
                        .workspace
                        .space(space)
                        .map(|s| s.name.clone())
                        .unwrap_or_default(),
                },
            })
            .collect()
    }

    /// Returns the live entity for a tab, creating it (without a webview) if
    /// needed.
    pub(crate) fn ensure_tab_entity(
        &mut self,
        id: TabId,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) -> Option<Entity<BrowserTab>> {
        if let Some(entity) = self.tabs.get(&id) {
            return Some(entity.clone());
        }
        let tab = self.workspace.tab(id)?.clone();
        let engine = self.engine.clone();
        let entity = cx.new(|_| {
            BrowserTab::new(
                tab.id,
                tab.url.clone(),
                tab.title.clone(),
                tab.favicon_url.clone(),
                tab.scroll_y,
                engine,
            )
        });
        let subscription = cx.subscribe_in(&entity, window, move |this, _, event, window, cx| {
            this.on_tab_event(id, event, window, cx);
        });
        self.tabs.insert(id, entity.clone());
        self.tab_subscriptions.insert(id, subscription);
        Some(entity)
    }

    /// Releases a tab's entity (and with it the webview).
    pub(crate) fn release_tab(&mut self, id: TabId) {
        self.tabs.remove(&id);
        self.tab_subscriptions.remove(&id);
    }

    /// Makes the workspace's active tab visible and every other tab hidden,
    /// creating the active tab's webview on demand.
    pub(crate) fn sync_active_tab(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        let active = self.workspace.active_tab_id();
        for (id, entity) in &self.tabs {
            if Some(*id) != active && entity.read(cx).is_active() {
                entity.update(cx, |tab, cx| tab.set_active(false, window, cx));
            }
        }
        if let Some(active) = active
            && let Some(entity) = self.ensure_tab_entity(active, window, cx)
            && !entity.read(cx).is_active()
        {
            entity.update(cx, |tab, cx| tab.set_active(true, window, cx));
        }
        let title = self
            .workspace
            .active_tab()
            .map_or_else(|| curio_core::APP_NAME.to_owned(), Tab::display_title);
        window.set_window_title(&title);
        if self.find.open {
            self.close_find(window, cx);
        }
        self.update_ai_context(cx);
        cx.notify();
    }

    /// Activates a tab (switching spaces when needed).
    pub(crate) fn activate_tab(&mut self, id: TabId, window: &mut Window, cx: &mut Context<Self>) {
        let previous_space = self.workspace.active_space_id();
        if !self.workspace.activate_tab(id) {
            return;
        }
        if self.workspace.active_space_id() != previous_space {
            self.after_space_change(previous_space, window, cx);
        }
        self.sync_active_tab(window, cx);
        self.schedule_save(cx);
    }

    /// Opens `url` in a new tab of the active space.
    pub(crate) fn open_url_in_new_tab(
        &mut self,
        url: &str,
        after: Option<TabId>,
        activate: bool,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) -> TabId {
        let tab = Tab::new(url);
        let id = tab.id;
        let space = after
            .and_then(|t| self.workspace.space_of_tab(t))
            .unwrap_or_else(|| self.workspace.active_space_id());
        let placement = match after {
            Some(after) if self.workspace.space(space).is_some_and(|s| !s.strip.is_pinned(after)) => {
                Placement::AfterTab(after)
            }
            _ => Placement::SectionStart(Section::Unpinned),
        };
        self.workspace.open_tab(space, tab, placement, false);
        if activate {
            self.activate_tab(id, window, cx);
        } else if let Some(entity) = self.ensure_tab_entity(id, window, cx) {
            // Background tabs start loading right away, hidden.
            entity.update(cx, |tab, cx| tab.navigate(url, window, cx));
            self.schedule_save(cx);
            cx.notify();
        }
        id
    }

    /// Navigates the active tab, or opens a tab when there is none.
    pub(crate) fn navigate_active(&mut self, url: &str, window: &mut Window, cx: &mut Context<Self>) {
        let Some(id) = self.workspace.active_tab_id() else {
            self.open_url_in_new_tab(url, None, true, window, cx);
            return;
        };
        if let Some(tab) = self.workspace.tab_mut(id) {
            tab.url = url.to_owned();
            tab.title.clear();
            tab.favicon_url = None;
            tab.scroll_y = 0.0;
        }
        if let Some(entity) = self.ensure_tab_entity(id, window, cx) {
            entity.update(cx, |tab, cx| tab.navigate(url, window, cx));
            if !entity.read(cx).is_active() {
                entity.update(cx, |tab, cx| tab.set_active(true, window, cx));
            }
        }
        self.schedule_save(cx);
        cx.notify();
    }

    /// Opens Curio's new tab page in a fresh tab.
    pub(crate) fn open_new_tab_page(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        if self.workspace.active_tab().is_some_and(Tab::is_new_tab_page) {
            return;
        }
        self.open_url_in_new_tab(NEW_TAB_URL, self.workspace.active_tab_id(), true, window, cx);
    }

    /// Closes a tab. Favorites are not closed but put to sleep and hidden.
    pub(crate) fn close_tab(&mut self, id: TabId, window: &mut Window, cx: &mut Context<Self>) {
        match self.workspace.find_tab(id).map(|(owner, _)| owner) {
            Some(TabOwner::Favorite(_)) => {
                if let Some(entity) = self.tabs.get(&id).cloned() {
                    entity.update(cx, |tab, cx| tab.sleep(cx));
                }
                if self.workspace.active_tab_id() == Some(id) {
                    let first = self.workspace.active_space().strip.ordered_tab_ids().first().copied();
                    self.workspace.active_space_mut().active_tab = first;
                }
                self.release_tab(id);
            }
            Some(TabOwner::Space(_)) => {
                if self.workspace.close_tab(id).is_some() {
                    self.release_tab(id);
                }
            }
            None => return,
        }
        self.sync_active_tab(window, cx);
        self.schedule_save(cx);
    }

    /// Reopens the most recently closed tab.
    pub(crate) fn reopen_closed_tab(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        let previous_space = self.workspace.active_space_id();
        if self.workspace.reopen_closed_tab().is_some() {
            if self.workspace.active_space_id() != previous_space {
                self.after_space_change(previous_space, window, cx);
            }
            self.sync_active_tab(window, cx);
            self.schedule_save(cx);
        }
    }

    /// Switches to another space with an animated transition.
    pub(crate) fn switch_space(&mut self, id: SpaceId, window: &mut Window, cx: &mut Context<Self>) {
        let previous = self.workspace.active_space_id();
        if !self.workspace.switch_space(id) {
            return;
        }
        self.after_space_change(previous, window, cx);
        self.sync_active_tab(window, cx);
        self.schedule_save(cx);
    }

    fn after_space_change(&mut self, previous: SpaceId, window: &mut Window, cx: &mut Context<Self>) {
        let from = self.workspace.space_index(previous).unwrap_or(0);
        let to = self
            .workspace
            .space_index(self.workspace.active_space_id())
            .unwrap_or(0);
        self.space_direction = if to >= from { 1.0 } else { -1.0 };
        self.space_transition = self.space_transition.wrapping_add(1);
        self.apply_theme(window, cx);
    }

    /// Selects the nth tab of the active space (0-based), or the last.
    pub(crate) fn select_tab_index(&mut self, index: Option<usize>, window: &mut Window, cx: &mut Context<Self>) {
        let order = self.visible_tab_order();
        let target = match index {
            Some(i) => order.get(i).copied(),
            None => order.last().copied(),
        };
        if let Some(id) = target {
            self.activate_tab(id, window, cx);
        }
    }

    /// Favorites then the active space's tabs, in display order.
    pub(crate) fn visible_tab_order(&self) -> Vec<TabId> {
        self.workspace
            .favorites()
            .iter()
            .map(|f| f.tab.id)
            .chain(self.workspace.active_space().strip.ordered_tab_ids())
            .collect()
    }

    pub(crate) fn cycle_tab(&mut self, forward: bool, window: &mut Window, cx: &mut Context<Self>) {
        let order = self.visible_tab_order();
        if order.is_empty() {
            return;
        }
        let current = self
            .workspace
            .active_tab_id()
            .and_then(|id| order.iter().position(|t| *t == id));
        let len = order.len();
        let next = match current {
            Some(i) if forward => (i + 1) % len,
            Some(i) => (i + len - 1) % len,
            None => 0,
        };
        self.activate_tab(order[next], window, cx);
    }

    /// Puts background tabs to sleep: those idle longer than the configured
    /// time, then the least recently used beyond the live-tab limit.
    pub(crate) fn put_idle_tabs_to_sleep(&mut self, cx: &mut Context<Self>) {
        let browsing = settings(cx).browsing.clone();
        let idle_limit = Duration::from_secs(u64::from(browsing.sleep_after_minutes) * 60);
        let mut awake: Vec<(TabId, std::time::Instant)> = self
            .tabs
            .iter()
            .filter(|(_, e)| {
                let tab = e.read(cx);
                tab.is_awake() && !tab.is_active()
            })
            .map(|(id, e)| (*id, e.read(cx).last_active()))
            .collect();
        awake.sort_by_key(|(_, last)| *last);
        let excess = awake.len().saturating_sub(browsing.max_live_tabs.saturating_sub(1));
        for (index, (id, last)) in awake.iter().enumerate() {
            if index < excess || last.elapsed() > idle_limit {
                if let Some(entity) = self.tabs.get(id) {
                    entity.update(cx, |tab, cx| tab.sleep(cx));
                }
            }
        }
    }

    // ----- Tab events -----------------------------------------------------

    pub(crate) fn on_tab_event(
        &mut self,
        id: TabId,
        event: &BrowserTabEvent,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        match event {
            BrowserTabEvent::StateChanged => {
                let Some(entity) = self.tabs.get(&id) else {
                    return;
                };
                let state = entity.read(cx).state().clone();
                let mut changed = false;
                if let Some(tab) = self.workspace.tab_mut(id) {
                    if !state.url.is_empty() && tab.url != state.url {
                        tab.url.clone_from(&state.url);
                        changed = true;
                    }
                    if !state.title.is_empty() && tab.title != state.title {
                        tab.title.clone_from(&state.title);
                        changed = true;
                    }
                    if state.favicon.is_some() && tab.favicon_url != state.favicon {
                        tab.favicon_url.clone_from(&state.favicon);
                        changed = true;
                    }
                }
                if changed {
                    self.schedule_save(cx);
                    if self.workspace.active_tab_id() == Some(id) {
                        let title = self.workspace.tab(id).map(Tab::display_title).unwrap_or_default();
                        window.set_window_title(&title);
                        self.update_ai_context(cx);
                    }
                }
                cx.notify();
            }
            BrowserTabEvent::Navigated { url } => self.record_visit(url, id, cx),
            BrowserTabEvent::LoadFinished { url, title } => {
                if settings(cx).browsing.save_history && !title.is_empty() && url.starts_with("http") {
                    let storage = Services::get(cx).storage.clone();
                    let (url, title) = (url.clone(), title.clone());
                    cx.background_spawn(async move {
                        let _ = storage.with(|db| db.update_history_title(&url, &title));
                    })
                    .detach();
                }
            }
            BrowserTabEvent::OpenInNewTab { url, background } => {
                self.open_url_in_new_tab(url, Some(id), !background, window, cx);
            }
            BrowserTabEvent::ExternalScheme { url } => self.confirm_external_open(url, window, cx),
            BrowserTabEvent::Shortcut { keystroke } => {
                if let Some(action) =
                    actions::action_for_bridge_keystroke(keystroke, &settings(cx).keybindings)
                {
                    window.dispatch_action(action, cx);
                }
            }
            BrowserTabEvent::SelectionChanged => {
                if self.workspace.active_tab_id() == Some(id) {
                    cx.notify();
                }
            }
            BrowserTabEvent::Scrolled { y } => {
                if let Some(tab) = self.workspace.tab_mut(id)
                    && (tab.scroll_y - y).abs() > 1.0
                {
                    tab.scroll_y = *y;
                    self.schedule_save(cx);
                }
            }
            BrowserTabEvent::DownloadStarted { url, path } => {
                self.downloads.insert(
                    0,
                    DownloadItem {
                        url: url.clone(),
                        path: Some(path.clone()),
                        finished: false,
                        success: false,
                    },
                );
                let storage = Services::get(cx).storage.clone();
                let (u, p) = (url.clone(), path.clone());
                cx.background_spawn(async move {
                    let _ = storage.with(|db| db.start_download(&u, Some(&p)));
                })
                .detach();
                let name = std::path::Path::new(path)
                    .file_name()
                    .map_or_else(|| display_host(url), |n| n.to_string_lossy().into_owned());
                window.push_notification(
                    Notification::info(name).title("Downloading"),
                    cx,
                );
                cx.notify();
            }
            BrowserTabEvent::DownloadFinished { url, path, success } => {
                if let Some(item) = self.downloads.iter_mut().find(|d| &d.url == url && !d.finished) {
                    item.finished = true;
                    item.success = *success;
                    if path.is_some() {
                        item.path.clone_from(path);
                    }
                }
                let storage = Services::get(cx).storage.clone();
                let (u, p, ok) = (url.clone(), path.clone(), *success);
                cx.background_spawn(async move {
                    let _ = storage.with(|db| db.finish_download(&u, p.as_deref(), ok));
                })
                .detach();
                let message = if *success { "Download complete" } else { "Download failed" };
                let note = if *success {
                    Notification::success(display_host(url))
                } else {
                    Notification::error(display_host(url))
                };
                window.push_notification(note.title(message), cx);
                cx.notify();
            }
        }
    }

    fn record_visit(&mut self, url: &str, id: TabId, cx: &mut Context<Self>) {
        if !settings(cx).browsing.save_history || !url.starts_with("http") {
            return;
        }
        let title = self.workspace.tab(id).map(|t| t.title.clone()).unwrap_or_default();
        let storage = Services::get(cx).storage.clone();
        let url = url.to_owned();
        cx.background_spawn(async move {
            if let Err(error) = storage.with(|db| db.record_visit(&url, &title)) {
                tracing::warn!(%error, "could not record history");
            }
        })
        .detach();
    }

    // ----- Assistant integration -------------------------------------------

    fn context_tab(&self, id: TabId) -> Option<ContextTab> {
        let tab = self.workspace.tab(id)?;
        Some(ContextTab {
            id,
            title: tab.display_title(),
            url: tab.url.clone(),
            favicon: tab.favicon_url.clone(),
        })
    }

    /// Tells the assistant which tabs it could use.
    pub(crate) fn update_ai_context(&mut self, cx: &mut Context<Self>) {
        let current = self.workspace.active_tab_id().and_then(|id| self.context_tab(id));
        let space = self.workspace.active_space();
        let space_info = (space.id, space.name.clone());
        let space_tabs: Vec<ContextTab> = space
            .strip
            .ordered_tab_ids()
            .into_iter()
            .filter_map(|id| self.context_tab(id))
            .collect();
        self.ai_panel.update(cx, |panel, cx| {
            panel.set_browsing_context(current, space_info, space_tabs, cx);
        });
    }

    /// Extracts the content of `tabs` (waking sleeping tabs first) and hands
    /// it to the assistant.
    pub(crate) fn extract_for_ai(
        &mut self,
        request: u64,
        tabs: Vec<TabId>,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        let mut jobs = Vec::new();
        for id in tabs {
            let Some(model) = self.workspace.tab(id).cloned() else {
                continue;
            };
            if is_internal_url(&model.url) {
                continue;
            }
            let Some(entity) = self.ensure_tab_entity(id, window, cx) else {
                continue;
            };
            let needs_load = !entity.read(cx).is_awake();
            if needs_load {
                // Load hidden; the page is read once it finishes.
                entity.update(cx, |tab, cx| tab.navigate(&model.url, window, cx));
            }
            jobs.push((entity, model, needs_load));
        }
        let panel = self.ai_panel.downgrade();
        cx.spawn(async move |_, cx| {
            let mut pages = Vec::with_capacity(jobs.len());
            for (entity, model, needs_load) in jobs {
                if needs_load {
                    // Wait (bounded) for the page to finish loading.
                    for _ in 0..40 {
                        cx.background_executor().timer(Duration::from_millis(250)).await;
                        let loading = entity.read_with(cx, |tab, _| tab.state().loading);
                        if !loading {
                            break;
                        }
                    }
                }
                let task = entity.read_with(cx, |tab, cx| tab.extract_content(cx));
                let page = match task.await {
                    Ok(json) => serde_json::from_str::<PageContext>(&json).ok(),
                    Err(error) => {
                        tracing::warn!(%error, "page extraction failed");
                        None
                    }
                };
                pages.push(page.unwrap_or_else(|| PageContext {
                    title: model.display_title(),
                    url: model.url.clone(),
                    text: "(The page content could not be read. Only its title and address are known.)".to_owned(),
                    ..PageContext::default()
                }));
            }
            let _ = panel.update(cx, |panel, cx| panel.provide_context(request, pages, cx));
        })
        .detach();
    }

    // ----- Find in page -----------------------------------------------------

    pub(crate) fn open_find(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        if self.active_tab_entity().is_none_or(|t| !t.read(cx).is_awake()) {
            return;
        }
        self.find.open = true;
        let handle = self.find.input.read(cx).focus_handle(cx);
        if let Some(tab) = self.active_tab_entity() {
            tab.read(cx).blur_page(cx);
        }
        self.find.input.update(cx, |input, cx| {
            input.select_all(window, cx);
        });
        window.focus(&handle, cx);
        cx.notify();
    }

    pub(crate) fn close_find(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        self.find.open = false;
        self.find.result = curio_browser::FindResult::default();
        if let Some(tab) = self.active_tab_entity() {
            tab.read(cx).clear_find(cx);
        }
        self.focus_page_or_window(window, cx);
        cx.notify();
    }

    pub(crate) fn run_find(&mut self, forward: bool, _: &mut Window, cx: &mut Context<Self>) {
        if !self.find.open {
            return;
        }
        let query = self.find.input.read(cx).value().to_string();
        let Some(tab) = self.active_tab_entity() else {
            return;
        };
        let task = tab.read(cx).find(&query, forward, cx);
        self.find.task = cx.spawn(async move |this, cx| {
            let result = task.await;
            let _ = this.update(cx, |this, cx| {
                this.find.result = result;
                cx.notify();
            });
        });
    }
}

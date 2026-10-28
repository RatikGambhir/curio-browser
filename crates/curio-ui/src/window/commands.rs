//! Action handlers for the browser window.

use curio_ai::QuickAction;
use curio_core::AccentColor;
use curio_settings::TabLayout;
use curio_spaces::TabOwner;
use gpui_kit::component::WindowExt as _;
use gpui_kit::Focusable as _;
use gpui_kit::{ClipboardItem, Context, Div, InteractiveElement as _, Stateful, Window};

use super::BrowserWindow;
use crate::actions::*;
use crate::command_bar::{CommandMode, CommandTarget};
use crate::settings;

impl BrowserWindow {
    /// Attaches every action handler to the root element.
    pub(crate) fn register_actions(&self, root: Stateful<Div>, cx: &mut Context<Self>) -> Stateful<Div> {
        root
            // Tabs
            .on_action(cx.listener(|this, _: &NewTab, window, cx| {
                this.open_command_bar(CommandMode::NewTab, window, cx);
            }))
            .on_action(cx.listener(|this, _: &OpenCommandBar, window, cx| {
                this.open_command_bar(CommandMode::Palette, window, cx);
            }))
            .on_action(cx.listener(|this, _: &EditUrl, window, cx| {
                this.open_command_bar(CommandMode::EditUrl, window, cx);
            }))
            .on_action(cx.listener(|this, _: &CloseTab, window, cx| {
                if let Some(id) = this.workspace.active_tab_id() {
                    this.close_tab(id, window, cx);
                }
            }))
            .on_action(cx.listener(|this, _: &ReopenClosedTab, window, cx| {
                this.reopen_closed_tab(window, cx);
            }))
            .on_action(cx.listener(|this, _: &DuplicateTab, window, cx| {
                if let Some(id) = this.workspace.active_tab_id()
                    && this.workspace.duplicate_tab(id).is_some()
                {
                    this.sync_active_tab(window, cx);
                    this.schedule_save(cx);
                }
            }))
            .on_action(cx.listener(|this, _: &PinTab, _, cx| {
                if let Some(id) = this.workspace.active_tab_id() {
                    this.toggle_pin(id, cx);
                }
            }))
            .on_action(cx.listener(|this, _: &AddFavorite, window, cx| {
                if let Some(id) = this.workspace.active_tab_id() {
                    this.add_favorite(id, window, cx);
                }
            }))
            .on_action(cx.listener(|this, _: &NewGroupFromTab, window, cx| {
                if let Some(id) = this.workspace.active_tab_id() {
                    this.new_group_with(vec![id], window, cx);
                }
            }))
            .on_action(cx.listener(|this, _: &ToggleBookmark, window, cx| {
                this.toggle_bookmark(window, cx);
            }))
            .on_action(cx.listener(|this, _: &CopyUrl, window, cx| {
                if let Some(tab) = this.workspace.active_tab().filter(|t| !t.is_new_tab_page()) {
                    cx.write_to_clipboard(ClipboardItem::new_string(tab.url.clone()));
                    window.push_notification("Link copied", cx);
                }
            }))
            .on_action(cx.listener(|this, _: &NextTab, window, cx| this.cycle_tab(true, window, cx)))
            .on_action(cx.listener(|this, _: &PreviousTab, window, cx| this.cycle_tab(false, window, cx)))
            .on_action(cx.listener(|this, _: &SelectTab1, w, cx| this.select_tab_index(Some(0), w, cx)))
            .on_action(cx.listener(|this, _: &SelectTab2, w, cx| this.select_tab_index(Some(1), w, cx)))
            .on_action(cx.listener(|this, _: &SelectTab3, w, cx| this.select_tab_index(Some(2), w, cx)))
            .on_action(cx.listener(|this, _: &SelectTab4, w, cx| this.select_tab_index(Some(3), w, cx)))
            .on_action(cx.listener(|this, _: &SelectTab5, w, cx| this.select_tab_index(Some(4), w, cx)))
            .on_action(cx.listener(|this, _: &SelectTab6, w, cx| this.select_tab_index(Some(5), w, cx)))
            .on_action(cx.listener(|this, _: &SelectTab7, w, cx| this.select_tab_index(Some(6), w, cx)))
            .on_action(cx.listener(|this, _: &SelectTab8, w, cx| this.select_tab_index(Some(7), w, cx)))
            .on_action(cx.listener(|this, _: &SelectLastTab, w, cx| this.select_tab_index(None, w, cx)))
            // Navigation
            .on_action(cx.listener(|this, _: &GoBack, _, cx| {
                if let Some(tab) = this.active_tab_entity() {
                    tab.update(cx, |tab, cx| tab.go_back(cx));
                }
            }))
            .on_action(cx.listener(|this, _: &GoForward, _, cx| {
                if let Some(tab) = this.active_tab_entity() {
                    tab.update(cx, |tab, cx| tab.go_forward(cx));
                }
            }))
            .on_action(cx.listener(|this, _: &Reload, window, cx| {
                if let Some(tab) = this.active_tab_entity().cloned() {
                    tab.update(cx, |tab, cx| tab.reload(window, cx));
                }
            }))
            .on_action(cx.listener(|this, _: &StopLoading, _, cx| {
                if let Some(tab) = this.active_tab_entity() {
                    tab.update(cx, |tab, cx| tab.stop(cx));
                }
            }))
            .on_action(cx.listener(|this, _: &Escape, window, cx| this.escape(window, cx)))
            .on_action(cx.listener(|this, _: &FindInPage, window, cx| this.open_find(window, cx)))
            .on_action(cx.listener(|this, _: &FindNext, window, cx| {
                if this.find.open {
                    this.run_find(true, window, cx);
                } else {
                    this.open_find(window, cx);
                }
            }))
            .on_action(cx.listener(|this, _: &FindPrevious, window, cx| this.run_find(false, window, cx)))
            .on_action(cx.listener(|this, _: &ZoomIn, _, cx| this.zoom_by(0.1, cx)))
            .on_action(cx.listener(|this, _: &ZoomOut, _, cx| this.zoom_by(-0.1, cx)))
            .on_action(cx.listener(|this, _: &ZoomReset, _, cx| this.zoom_to(1.0, cx)))
            .on_action(cx.listener(|this, _: &OpenDevTools, _, cx| {
                if let Some(tab) = this.active_tab_entity() {
                    tab.read(cx).open_devtools(cx);
                }
            }))
            .on_action(cx.listener(|this, _: &Print, _, cx| {
                if let Some(tab) = this.active_tab_entity() {
                    tab.read(cx).print(cx);
                }
            }))
            .on_action(cx.listener(|this, _: &ShowHistory, window, cx| this.show_history(window, cx)))
            .on_action(cx.listener(|this, _: &ShowDownloads, window, cx| this.show_downloads(window, cx)))
            // Spaces
            .on_action(cx.listener(|this, _: &NewSpace, window, cx| this.edit_space(None, window, cx)))
            .on_action(cx.listener(|this, _: &NextSpace, window, cx| {
                if let Some(id) = this.workspace.adjacent_space(true) {
                    this.switch_space(id, window, cx);
                }
            }))
            .on_action(cx.listener(|this, _: &PreviousSpace, window, cx| {
                if let Some(id) = this.workspace.adjacent_space(false) {
                    this.switch_space(id, window, cx);
                }
            }))
            .on_action(cx.listener(|this, _: &SelectSpace1, w, cx| this.select_space_index(0, w, cx)))
            .on_action(cx.listener(|this, _: &SelectSpace2, w, cx| this.select_space_index(1, w, cx)))
            .on_action(cx.listener(|this, _: &SelectSpace3, w, cx| this.select_space_index(2, w, cx)))
            .on_action(cx.listener(|this, _: &SelectSpace4, w, cx| this.select_space_index(3, w, cx)))
            .on_action(cx.listener(|this, _: &SelectSpace5, w, cx| this.select_space_index(4, w, cx)))
            .on_action(cx.listener(|this, _: &SelectSpace6, w, cx| this.select_space_index(5, w, cx)))
            .on_action(cx.listener(|this, _: &SelectSpace7, w, cx| this.select_space_index(6, w, cx)))
            .on_action(cx.listener(|this, _: &SelectSpace8, w, cx| this.select_space_index(7, w, cx)))
            .on_action(cx.listener(|this, _: &SelectSpace9, w, cx| this.select_space_index(8, w, cx)))
            // Layout
            .on_action(cx.listener(|this, _: &ToggleSidebar, _, cx| {
                if this.layout(cx) == TabLayout::Horizontal {
                    return;
                }
                this.sidebar_peek = false;
                crate::update_settings(cx, |s| s.appearance.sidebar_visible = !s.appearance.sidebar_visible);
            }))
            .on_action(cx.listener(|_, _: &ToggleTabLayout, _, cx| {
                crate::update_settings(cx, |s| {
                    s.appearance.tab_layout = match s.appearance.tab_layout {
                        TabLayout::Vertical => TabLayout::Horizontal,
                        TabLayout::Horizontal => TabLayout::Vertical,
                    };
                });
            }))
            .on_action(cx.listener(|this, _: &ToggleAiPanel, window, cx| this.toggle_ai(window, cx)))
            .on_action(cx.listener(|this, _: &NewChat, window, cx| {
                this.ai_panel.update(cx, |panel, cx| panel.new_conversation(cx));
                this.show_ai(window, cx);
            }))
            .on_action(cx.listener(|this, _: &AskAboutPage, window, cx| {
                this.show_ai(window, cx);
                this.ai_panel
                    .update(cx, |panel, cx| panel.quick_action(&QuickAction::SummarizePage, window, cx));
            }))
            .on_action(cx.listener(|this, _: &ExplainSelection, window, cx| {
                this.ask_about_selection(QuickAction::ExplainSelection, window, cx);
            }))
            .on_action(cx.listener(|this, _: &SummarizeSelection, window, cx| {
                this.ask_about_selection(QuickAction::SummarizeSelection, window, cx);
            }))
            .on_action(cx.listener(|this, _: &OpenSettings, window, cx| this.open_settings(None, window, cx)))
            .on_action(cx.listener(|this, _: &About, window, cx| this.show_about(window, cx)))
            // Window
            .on_action(cx.listener(|this, _: &Quit, _, cx| {
                this.save_now(cx);
                cx.quit();
            }))
            .on_action(|_: &Hide, _, cx| cx.hide())
            .on_action(|_: &HideOthers, _, cx| cx.hide_other_apps())
            .on_action(|_: &ShowAll, _, cx| cx.unhide_other_apps())
            .on_action(|_: &Minimize, window, _| window.minimize_window())
            .on_action(|_: &Zoom, window, _| window.zoom_window())
            .on_action(|_: &ToggleFullScreen, window, _| window.toggle_fullscreen())
    }

    /// Runs a command bar selection.
    pub(crate) fn execute_command(&mut self, target: CommandTarget, window: &mut Window, cx: &mut Context<Self>) {
        match target {
            CommandTarget::Navigate { url, new_tab } => {
                let reuse = self.workspace.active_tab().is_some_and(curio_core::Tab::is_new_tab_page);
                if new_tab && !reuse {
                    self.open_url_in_new_tab(&url, self.workspace.active_tab_id(), true, window, cx);
                } else {
                    self.navigate_active(&url, window, cx);
                }
                self.focus_page_or_window(window, cx);
            }
            CommandTarget::SwitchTab(id) => {
                self.activate_tab(id, window, cx);
                self.focus_page_or_window(window, cx);
            }
            CommandTarget::Action(name) => match cx.build_action(&name, None) {
                Ok(action) => window.dispatch_action(action, cx),
                Err(error) => tracing::warn!(%name, %error, "unknown command"),
            },
            CommandTarget::AskAi(question) => {
                self.show_ai(window, cx);
                self.ai_panel.update(cx, |panel, cx| panel.ask(&question, window, cx));
            }
        }
    }

    fn escape(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        if self.command_mode.is_some() {
            self.close_command_bar(window, cx);
        } else if self.find.open {
            self.close_find(window, cx);
        } else if self.sidebar_peek {
            self.sidebar_peek = false;
            cx.notify();
        } else if let Some(tab) = self.active_tab_entity()
            && tab.read(cx).state().loading
        {
            tab.update(cx, |tab, cx| tab.stop(cx));
        }
    }

    pub(crate) fn toggle_pin(&mut self, id: curio_core::TabId, cx: &mut Context<Self>) {
        let Some(space) = self.workspace.space_of_tab(id) else {
            return;
        };
        if let Some(space) = self.workspace.space_mut(space) {
            if space.strip.is_pinned(id) {
                space.strip.unpin(id);
            } else {
                space.strip.pin(id);
            }
        }
        self.schedule_save(cx);
        cx.notify();
    }

    pub(crate) fn add_favorite(&mut self, id: curio_core::TabId, window: &mut Window, cx: &mut Context<Self>) {
        if matches!(self.workspace.find_tab(id), Some((TabOwner::Favorite(_), _))) {
            return;
        }
        if self.workspace.tab(id).is_some_and(curio_core::Tab::is_new_tab_page) {
            return;
        }
        if self.workspace.favorite_from_tab(id).is_some() {
            window.push_notification("Added to Favorites", cx);
            self.schedule_save(cx);
            cx.notify();
        }
    }

    pub(crate) fn new_group_with(
        &mut self,
        members: Vec<curio_core::TabId>,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        let Some(first) = members.first().copied() else {
            return;
        };
        let Some(space_id) = self.workspace.space_of_tab(first) else {
            return;
        };
        let color = self
            .workspace
            .space(space_id)
            .map_or(AccentColor::Ocean, |s| {
                let used = s.strip.groups().count();
                AccentColor::ALL[(used + 1) % AccentColor::ALL.len()]
            });
        let group = self
            .workspace
            .space_mut(space_id)
            .map(|s| s.strip.create_group("New Group", color, &members));
        self.schedule_save(cx);
        cx.notify();
        if let Some(group) = group {
            self.rename_group(space_id, group, window, cx);
        }
    }

    fn toggle_bookmark(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        let Some(tab) = self.workspace.active_tab().filter(|t| t.url.starts_with("http")).cloned() else {
            return;
        };
        let storage = crate::Services::get(cx).storage.clone();
        let result = storage.with(|db| -> curio_storage::Result<bool> {
            if db.is_bookmarked(&tab.url)? {
                db.remove_bookmark(&tab.url)?;
                Ok(false)
            } else {
                db.add_bookmark(&tab.url, &tab.display_title())?;
                Ok(true)
            }
        });
        match result {
            Ok(true) => window.push_notification("Bookmarked", cx),
            Ok(false) => window.push_notification("Bookmark removed", cx),
            Err(error) => tracing::error!(%error, "bookmark failed"),
        }
        cx.notify();
    }

    fn zoom_by(&mut self, delta: f64, cx: &mut Context<Self>) {
        if let Some(tab) = self.active_tab_entity() {
            let zoom = tab.read(cx).state().zoom;
            let next = ((zoom + delta) * 10.0).round() / 10.0;
            tab.update(cx, |tab, cx| tab.set_zoom(next, cx));
        }
    }

    fn zoom_to(&mut self, zoom: f64, cx: &mut Context<Self>) {
        if let Some(tab) = self.active_tab_entity() {
            tab.update(cx, |tab, cx| tab.set_zoom(zoom, cx));
        }
    }

    fn select_space_index(&mut self, index: usize, window: &mut Window, cx: &mut Context<Self>) {
        if let Some(id) = self.workspace.spaces().get(index).map(|s| s.id) {
            self.switch_space(id, window, cx);
        }
    }

    pub(crate) fn show_ai(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        if !self.ai_open {
            self.ai_open = true;
            self.update_ai_context(cx);
        }
        if let Some(tab) = self.active_tab_entity() {
            tab.read(cx).blur_page(cx);
        }
        self.ai_panel.update(cx, |panel, cx| panel.focus_composer(window, cx));
        cx.notify();
    }

    pub(crate) fn toggle_ai(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        if self.ai_open {
            self.ai_open = false;
            self.focus_page_or_window(window, cx);
            cx.notify();
        } else {
            self.show_ai(window, cx);
        }
    }

    /// Sends the current page selection to the assistant with an action.
    pub(crate) fn ask_about_selection(&mut self, action: QuickAction, window: &mut Window, cx: &mut Context<Self>) {
        let selection = self
            .active_tab_entity()
            .and_then(|t| t.read(cx).state().selection.clone())
            .map(|s| s.text);
        self.show_ai(window, cx);
        let action = match action {
            QuickAction::TranslateSelection { .. } => QuickAction::TranslateSelection {
                language: settings(cx).ai.translate_to.clone(),
            },
            other => other,
        };
        self.ai_panel.update(cx, |panel, cx| match &selection {
            Some(text) if !text.trim().is_empty() => panel.ask_about_selection(&action, text, window, cx),
            _ => panel.quick_action(&QuickAction::SummarizePage, window, cx),
        });
    }

    /// Prefills the composer with the selection so the user can ask their
    /// own question about it.
    pub(crate) fn send_selection_to_chat(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        let Some(text) = self
            .active_tab_entity()
            .and_then(|t| t.read(cx).state().selection.clone())
            .map(|s| s.text)
        else {
            return;
        };
        self.show_ai(window, cx);
        self.ai_panel.update(cx, |panel, cx| panel.prefill_quote(&text, window, cx));
    }
}

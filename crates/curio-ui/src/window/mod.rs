//! The main browser window.
//!
//! [`BrowserWindow`] owns the [`Workspace`] (spaces, tabs, favorites), the
//! live [`BrowserTab`] entities for tabs whose pages are loaded, and the
//! overlay views (command bar, assistant, find bar). Rendering is split by
//! area into the submodules.

mod commands;
mod content;
mod dialogs;
mod drag;
mod sidebar;
mod tabs;
mod toolbar;

use std::collections::HashMap;
use std::rc::Rc;
use std::time::Duration;

use curio_browser::{BrowserTab, EngineConfig, FindResult};
use curio_core::TabId;
use curio_settings::TabLayout;
use curio_spaces::Workspace;
use curio_storage::HistoryEntry;
use gpui_kit::component::input::{InputEvent, InputState};
use gpui_kit::{
    Animation, AnimationExt as _, AppContext as _, Context, Entity, FocusHandle, Focusable,
    InteractiveElement as _, IntoElement, MouseButton, MouseMoveEvent, MouseUpEvent,
    ParentElement as _, Pixels, Render, StatefulInteractiveElement as _, Styled as _, Subscription, Task, Window, deferred, div,
    linear_color_stop, linear_gradient, px,
};

use crate::ai_panel::{AiPanel, AiPanelEvent};
use crate::command_bar::{CommandBar, CommandBarEvent, CommandMode};
use crate::theme::{Appearance, CurioTheme, metrics, mix};
use crate::{Services, actions, settings};

pub(crate) use drag::{DraggedGroup, DraggedTab};

/// Which divider is being dragged.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum Resize {
    Sidebar,
    AiPanel,
}

/// A download shown in the downloads list.
#[derive(Debug, Clone, PartialEq)]
pub(crate) struct DownloadItem {
    pub url: String,
    pub path: Option<String>,
    pub finished: bool,
    pub success: bool,
}

/// Find-in-page state.
pub(crate) struct FindState {
    pub open: bool,
    pub input: Entity<InputState>,
    pub result: FindResult,
    pub task: Task<()>,
}

/// The browser window's root view.
pub struct BrowserWindow {
    focus_handle: FocusHandle,
    pub(crate) workspace: Workspace,
    pub(crate) tabs: HashMap<TabId, Entity<BrowserTab>>,
    tab_subscriptions: HashMap<TabId, Subscription>,
    pub(crate) engine: Rc<EngineConfig>,
    pub(crate) command_bar: Entity<CommandBar>,
    pub(crate) command_mode: Option<CommandMode>,
    pub(crate) ai_panel: Entity<AiPanel>,
    pub(crate) ai_open: bool,
    pub(crate) find: FindState,
    pub(crate) sidebar_width: Pixels,
    pub(crate) ai_width: Pixels,
    resizing: Option<Resize>,
    /// The sidebar is temporarily shown over the page while hidden.
    pub(crate) sidebar_peek: bool,
    /// Bumped on every space switch to restart the transition animation.
    pub(crate) space_transition: usize,
    pub(crate) space_direction: f32,
    previous_theme: CurioTheme,
    swipe_accumulator: f32,
    save_task: Option<Task<()>>,
    pub(crate) downloads: Vec<DownloadItem>,
    pub(crate) top_sites: Vec<HistoryEntry>,
    _subscriptions: Vec<Subscription>,
    _maintenance: Task<()>,
}

impl Focusable for BrowserWindow {
    fn focus_handle(&self, _: &gpui_kit::App) -> FocusHandle {
        self.focus_handle.clone()
    }
}

impl BrowserWindow {
    /// Creates the window view for a restored (or new) workspace.
    pub fn new(workspace: Workspace, window: &mut Window, cx: &mut Context<Self>) -> Self {
        let settings = settings(cx).clone();
        let download_dir = Some(settings.browsing.download_dir.trim())
            .filter(|d| !d.is_empty())
            .map(std::path::PathBuf::from);
        let engine = Rc::new(EngineConfig::new(
            actions::forwarded_keystrokes(&settings.keybindings),
            download_dir,
        ));

        let command_bar = cx.new(|cx| CommandBar::new(window, cx));
        let ai_panel = cx.new(|cx| AiPanel::new(window, cx));
        let find_input = cx.new(|cx| InputState::new(window, cx).placeholder("Find in page"));

        let mut subscriptions = vec![
            cx.subscribe_in(&command_bar, window, Self::on_command_bar_event),
            cx.subscribe_in(&ai_panel, window, Self::on_ai_panel_event),
            cx.subscribe_in(&find_input, window, |this, _, event, window, cx| match event {
                InputEvent::Change => this.run_find(true, window, cx),
                InputEvent::PressEnter { shift, .. } => this.run_find(!*shift, window, cx),
                _ => {}
            }),
            cx.observe_global_in::<crate::SettingsStore>(window, |this, window, cx| {
                this.apply_theme(window, cx);
                cx.notify();
            }),
            cx.observe_window_appearance(window, |this, window, cx| {
                this.apply_theme(window, cx);
            }),
        ];
        subscriptions.push(cx.on_release(|this, cx| {
            this.save_now(cx);
        }));

        let accent = workspace.active_space().color;
        let appearance = CurioTheme::resolve(settings.appearance.theme, window.appearance());
        CurioTheme::apply(accent, appearance, Some(window), cx);
        let previous_theme = *CurioTheme::get(cx);

        let maintenance = cx.spawn_in(window, async move |this, cx| {
            loop {
                cx.background_executor().timer(Duration::from_secs(60)).await;
                if this
                    .update_in(cx, |this, _, cx| this.put_idle_tabs_to_sleep(cx))
                    .is_err()
                {
                    break;
                }
            }
        });

        let mut this = Self {
            focus_handle: cx.focus_handle(),
            workspace,
            tabs: HashMap::new(),
            tab_subscriptions: HashMap::new(),
            engine,
            command_bar,
            command_mode: None,
            ai_panel,
            ai_open: false,
            find: FindState {
                open: false,
                input: find_input,
                result: FindResult::default(),
                task: Task::ready(()),
            },
            sidebar_width: px(settings.appearance.sidebar_width),
            ai_width: px(settings.appearance.ai_panel_width),
            resizing: None,
            sidebar_peek: false,
            space_transition: 0,
            space_direction: 0.0,
            previous_theme,
            swipe_accumulator: 0.0,
            save_task: None,
            downloads: Vec::new(),
            top_sites: Vec::new(),
            _subscriptions: subscriptions,
            _maintenance: maintenance,
        };
        this.sync_active_tab(window, cx);
        this.load_top_sites(cx);
        if this.workspace.active_tab().is_none_or(curio_core::Tab::is_new_tab_page) {
            // An empty space opens on the command bar, like a fresh Arc window.
            this.open_command_bar(CommandMode::NewTab, window, cx);
        }
        this
    }

    /// The live entity of the active tab.
    pub(crate) fn active_tab_entity(&self) -> Option<&Entity<BrowserTab>> {
        self.workspace.active_tab_id().and_then(|id| self.tabs.get(&id))
    }

    pub(crate) fn layout(&self, cx: &gpui_kit::App) -> TabLayout {
        settings(cx).appearance.tab_layout
    }

    pub(crate) fn sidebar_visible(&self, cx: &gpui_kit::App) -> bool {
        self.layout(cx) == TabLayout::Vertical && settings(cx).appearance.sidebar_visible
    }

    /// Re-applies the theme for the active space and appearance setting.
    pub(crate) fn apply_theme(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        let accent = self.workspace.active_space().color;
        let mode = settings(cx).appearance.theme;
        let appearance = CurioTheme::resolve(mode, window.appearance());
        let current = *CurioTheme::get(cx);
        if current.accent_color != accent || current.appearance != appearance {
            self.previous_theme = current;
            CurioTheme::apply(accent, appearance, Some(window), cx);
            for tab in self.tabs.values() {
                if let Some(webview) = tab.read(cx).webview() {
                    let _ = webview.read(cx).set_theme(match appearance {
                        Appearance::Light => wry::Theme::Light,
                        Appearance::Dark => wry::Theme::Dark,
                    });
                }
            }
        }
        cx.notify();
    }

    // ----- Persistence ----------------------------------------------------

    /// Saves the workspace after a short delay, coalescing bursts of changes.
    pub(crate) fn schedule_save(&mut self, cx: &mut Context<Self>) {
        if self.save_task.is_some() {
            return;
        }
        self.save_task = Some(cx.spawn(async move |this, cx| {
            cx.background_executor().timer(Duration::from_millis(900)).await;
            let Ok((snapshot, storage)) = this.update(cx, |this, cx| {
                this.save_task = None;
                (this.workspace.clone(), Services::get(cx).storage.clone())
            }) else {
                return;
            };
            let result = cx
                .background_spawn(async move { storage.with(|db| db.save_workspace(&snapshot)) })
                .await;
            if let Err(error) = result {
                tracing::error!(%error, "could not save session");
            }
        }));
    }

    /// Saves the workspace synchronously (on quit).
    pub(crate) fn save_now(&mut self, cx: &mut gpui_kit::App) {
        self.save_task = None;
        let storage = Services::get(cx).storage.clone();
        if let Err(error) = storage.with(|db| db.save_workspace(&self.workspace)) {
            tracing::error!(%error, "could not save session on exit");
        }
    }

    fn load_top_sites(&mut self, cx: &mut Context<Self>) {
        let storage = Services::get(cx).storage.clone();
        let task = cx.background_spawn(async move {
            storage.with(|db| db.search_history("", 24)).unwrap_or_default()
        });
        cx.spawn(async move |this, cx| {
            let sites = task.await;
            let _ = this.update(cx, |this, cx| {
                let mut seen = std::collections::HashSet::new();
                this.top_sites = sites
                    .into_iter()
                    .filter(|s| s.url.starts_with("http") && seen.insert(curio_core::display_host(&s.url)))
                    .take(8)
                    .collect();
                cx.notify();
            });
        })
        .detach();
    }

    // ----- Overlays -------------------------------------------------------

    pub(crate) fn open_command_bar(&mut self, mode: CommandMode, window: &mut Window, cx: &mut Context<Self>) {
        let text = match mode {
            CommandMode::EditUrl => self
                .workspace
                .active_tab()
                .filter(|t| !t.is_new_tab_page())
                .map(|t| t.url.clone())
                .unwrap_or_default(),
            CommandMode::NewTab | CommandMode::Palette => String::new(),
        };
        let suggestions = self.tab_suggestions();
        if let Some(tab) = self.active_tab_entity() {
            tab.read(cx).blur_page(cx);
        }
        self.command_mode = Some(mode);
        self.command_bar
            .update(cx, |bar, cx| bar.open(mode, &text, suggestions, window, cx));
        cx.notify();
    }

    pub(crate) fn close_command_bar(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        if self.command_mode.take().is_some() {
            self.focus_page_or_window(window, cx);
            cx.notify();
        }
    }

    pub(crate) fn focus_page_or_window(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        window.focus(&self.focus_handle, cx);
        if let Some(tab) = self.active_tab_entity() {
            tab.read(cx).focus_page(cx);
        }
    }

    fn on_command_bar_event(
        &mut self,
        _: &Entity<CommandBar>,
        event: &CommandBarEvent,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        match event {
            CommandBarEvent::Dismissed => self.close_command_bar(window, cx),
            CommandBarEvent::Execute(target) => {
                let target = target.clone();
                self.command_mode = None;
                window.focus(&self.focus_handle, cx);
                self.execute_command(target, window, cx);
                cx.notify();
            }
        }
    }

    fn on_ai_panel_event(
        &mut self,
        _: &Entity<AiPanel>,
        event: &AiPanelEvent,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        match event {
            AiPanelEvent::Close => {
                self.ai_open = false;
                cx.notify();
            }
            AiPanelEvent::OpenSettings => self.open_settings(Some(crate::settings_view::Section::Ai), window, cx),
            AiPanelEvent::OpenUrl(url) => {
                if url.starts_with("http") {
                    self.open_url_in_new_tab(url, None, true, window, cx);
                }
            }
            AiPanelEvent::NeedsContext { request, tabs } => {
                self.extract_for_ai(*request, tabs.clone(), window, cx);
            }
        }
    }

    // ----- Resizing -------------------------------------------------------

    fn on_root_mouse_move(&mut self, event: &MouseMoveEvent, window: &mut Window, cx: &mut Context<Self>) {
        let Some(resize) = self.resizing else {
            return;
        };
        if event.pressed_button != Some(MouseButton::Left) {
            self.finish_resize(cx);
            return;
        }
        match resize {
            Resize::Sidebar => {
                self.sidebar_width = event.position.x.clamp(px(200.), px(420.));
            }
            Resize::AiPanel => {
                let width = window.viewport_size().width - event.position.x;
                self.ai_width = width.clamp(px(300.), px(640.));
            }
        }
        cx.notify();
    }

    fn finish_resize(&mut self, cx: &mut Context<Self>) {
        if self.resizing.take().is_some() {
            let sidebar = f32::from(self.sidebar_width);
            let ai = f32::from(self.ai_width);
            crate::update_settings(cx, |s| {
                s.appearance.sidebar_width = sidebar;
                s.appearance.ai_panel_width = ai;
            });
        }
    }

    pub(crate) fn resize_handle(&self, which: Resize, cx: &mut Context<Self>) -> impl IntoElement {
        let theme = *CurioTheme::get(cx);
        let active = self.resizing == Some(which);
        div()
            .id(match which {
                Resize::Sidebar => "resize-sidebar",
                Resize::AiPanel => "resize-ai",
            })
            .w(px(6.))
            .h_full()
            .flex_shrink_0()
            .cursor_col_resize()
            .child(
                div()
                    .mx_auto()
                    .w(px(2.))
                    .h_full()
                    .rounded_full()
                    .when(active, |el| el.bg(theme.accent))
                    .hover(|s| s.bg(theme.divider)),
            )
            .on_mouse_down(
                MouseButton::Left,
                cx.listener(move |this, _, _, cx| {
                    this.resizing = Some(which);
                    cx.stop_propagation();
                }),
            )
    }

    /// Accumulates horizontal trackpad scrolling on the sidebar into space
    /// switches (a two-finger swipe, like Arc).
    pub(crate) fn on_sidebar_swipe(
        &mut self,
        event: &gpui_kit::ScrollEvent,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        let delta = event.delta.pixel_delta(px(16.));
        let (dx, dy) = (f32::from(delta.x), f32::from(delta.y));
        if matches!(event.touch_phase, gpui_kit::TouchPhase::Started) {
            self.swipe_accumulator = 0.0;
        }
        if dx.abs() <= dy.abs() * 1.4 {
            return;
        }
        self.swipe_accumulator += dx;
        const THRESHOLD: f32 = 90.0;
        if self.swipe_accumulator.abs() > THRESHOLD {
            // Content moves with the fingers: swiping left reveals the next space.
            let forward = self.swipe_accumulator < 0.0;
            self.swipe_accumulator = 0.0;
            if let Some(target) = self.workspace.adjacent_space(forward) {
                self.switch_space(target, window, cx);
            }
        }
        cx.stop_propagation();
    }
}

use gpui_kit::prelude::FluentBuilder as _;

impl Render for BrowserWindow {
    fn render(&mut self, window: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        let theme = *CurioTheme::get(cx);
        let previous = self.previous_theme;
        let layout = self.layout(cx);
        let sidebar_visible = self.sidebar_visible(cx);
        let reduce_motion = settings(cx).appearance.reduce_motion;

        let mut main = gpui_kit::component::v_flex().flex_1().min_w_0().h_full();
        if layout == TabLayout::Horizontal {
            main = main
                .child(self.render_toolbar(true, window, cx))
                .child(self.render_tab_strip(window, cx));
        } else if !sidebar_visible {
            main = main.child(self.render_toolbar(false, window, cx));
        }
        let card_top = layout == TabLayout::Vertical && sidebar_visible;
        main = main.child(self.render_content(card_top, window, cx));

        let mut row = gpui_kit::component::h_flex().size_full().items_start();
        if sidebar_visible {
            row = row
                .child(
                    div()
                        .w(self.sidebar_width)
                        .h_full()
                        .flex_shrink_0()
                        .child(self.render_sidebar(false, window, cx)),
                )
                .child(self.resize_handle(Resize::Sidebar, cx));
        } else if layout == TabLayout::Vertical {
            // Hovering the left edge peeks the hidden sidebar over the page.
            row = row.child(
                div()
                    .id("sidebar-peek-edge")
                    .absolute()
                    .left_0()
                    .top(metrics::TOOLBAR_HEIGHT)
                    .bottom_0()
                    .w(px(8.))
                    .on_hover(cx.listener(|this, hovered: &bool, _, cx| {
                        if *hovered {
                            this.sidebar_peek = true;
                            cx.notify();
                        }
                    })),
            );
        }
        row = row.child(main);
        if self.ai_open {
            row = row
                .child(self.resize_handle(Resize::AiPanel, cx))
                .child(
                    div()
                        .w(self.ai_width)
                        .h_full()
                        .flex_shrink_0()
                        .py(metrics::PANEL_GAP)
                        .pr(metrics::PANEL_GAP)
                        .child(
                            div()
                                .size_full()
                                .rounded(metrics::CARD_RADIUS)
                                .overflow_hidden()
                                .border_1()
                                .border_color(theme.card_border)
                                .shadow_md()
                                .child(self.ai_panel.clone()),
                        ),
                );
        }

        let transition = self.space_transition;
        let mut root = div()
            .id("browser-window")
            .key_context("BrowserWindow")
            .track_focus(&self.focus_handle)
            .relative()
            .size_full()
            .text_color(theme.text)
            .on_mouse_move(cx.listener(Self::on_root_mouse_move))
            .on_mouse_up(
                MouseButton::Left,
                cx.listener(|this, _: &MouseUpEvent, _, cx| this.finish_resize(cx)),
            )
            .child(row);
        root = self.register_actions(root, cx);

        if self.sidebar_peek && !sidebar_visible && layout == TabLayout::Vertical {
            root = root.child(deferred(
                div()
                    .id("sidebar-peek")
                    .absolute()
                    .left(px(6.))
                    .top(metrics::TOOLBAR_HEIGHT)
                    .bottom(px(8.))
                    .w(self.sidebar_width)
                    .rounded(metrics::CARD_RADIUS)
                    .overflow_hidden()
                    .shadow_2xl()
                    .border_1()
                    .border_color(theme.surface_border)
                    .bg(linear_gradient(
                        180.,
                        linear_color_stop(theme.chrome_top, 0.),
                        linear_color_stop(theme.chrome_bottom, 1.),
                    ))
                    .on_hover(cx.listener(|this, hovered: &bool, _, cx| {
                        if !*hovered {
                            this.sidebar_peek = false;
                            cx.notify();
                        }
                    }))
                    .child(self.render_sidebar(true, window, cx)),
            ));
        }

        if let Some(mode) = self.command_mode {
            let _ = mode;
            root = root.child(deferred(
                div()
                    .id("command-scrim")
                    .absolute()
                    .inset_0()
                    .bg(theme.scrim)
                    .flex()
                    .justify_center()
                    .pt(window.viewport_size().height * 0.16)
                    .on_mouse_down(
                        MouseButton::Left,
                        cx.listener(|this, _, window, cx| this.close_command_bar(window, cx)),
                    )
                    .child(
                        div()
                            .id("command-bar-host")
                            .on_mouse_down(MouseButton::Left, |_, _, cx| cx.stop_propagation())
                            .child(self.command_bar.clone())
                            .with_animation(
                                "command-bar-in",
                                Animation::new(Duration::from_millis(if reduce_motion { 1 } else { 140 }))
                                    .with_easing(gpui_kit::ease_out_quint()),
                                |el, t| el.opacity(t).mt(px(-8. * (1. - t))),
                            ),
                    ),
            ));
        }

        // Cross-fade the chrome tint when switching spaces.
        root.with_animation(
            ("space-tint", transition),
            Animation::new(Duration::from_millis(if reduce_motion { 1 } else { 320 }))
                .with_easing(gpui_kit::ease_in_out),
            move |el, t| {
                el.bg(linear_gradient(
                    180.,
                    linear_color_stop(mix(previous.chrome_top, theme.chrome_top, t), 0.),
                    linear_color_stop(mix(previous.chrome_bottom, theme.chrome_bottom, t), 1.),
                ))
            },
        )
    }
}

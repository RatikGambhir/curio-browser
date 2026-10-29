//! The library: Arc-style collections shown in place of the sidebar. A rail
//! of sections (media, downloads, notes, spaces, calendar, archived tabs)
//! sits under the traffic lights, with a searchable list beside it; the page
//! stays where it is.

use std::path::{Path, PathBuf};
use std::time::Duration;

use curio_core::display_host;
use curio_storage::DownloadRecord;
use gpui_kit::assets::IconName;
use gpui_kit::component::button::{Button, ButtonVariants as _};
use gpui_kit::component::input::{Input, InputEvent, InputState};
use gpui_kit::component::tooltip::Tooltip;
use gpui_kit::component::{Icon, Sizable as _, h_flex, v_flex};
use gpui_kit::prelude::FluentBuilder as _;
use gpui_kit::{
    Animation, AnimationExt as _, AnyElement, AppContext as _, Context, Div, ElementId, Entity,
    FontWeight, InteractiveElement as _, IntoElement, MouseButton, ObjectFit, ParentElement as _,
    Pixels, SharedString, Stateful, StatefulInteractiveElement as _, Styled as _, StyledImage as _,
    Subscription, Window, div, img, px,
};

use super::BrowserWindow;
use crate::components::{chrome_button, favicon};
use crate::theme::{CurioTheme, metrics};
use crate::{Services, actions, settings};

/// Width of the section rail. Wide enough for the traffic lights above it.
const RAIL_WIDTH: Pixels = px(84.);

/// File extensions shown under Media.
const IMAGE_EXTENSIONS: [&str; 8] = ["png", "jpg", "jpeg", "gif", "webp", "heic", "svg", "bmp"];
const VIDEO_EXTENSIONS: [&str; 5] = ["mp4", "mov", "m4v", "webm", "mkv"];

/// A collection in the library.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum LibrarySection {
    Media,
    Downloads,
    Notes,
    Spaces,
    Calendar,
    ArchivedTabs,
    ClipboardHistory,
    GlobalVariables,
    Inbox,
}

impl LibrarySection {
    const ALL: [Self; 9] = [
        Self::Media,
        Self::Downloads,
        Self::Notes,
        Self::Spaces,
        Self::Calendar,
        Self::ArchivedTabs,
        Self::ClipboardHistory,
        Self::GlobalVariables,
        Self::Inbox,
    ];

    fn label(self) -> &'static str {
        match self {
            Self::Media => "Media",
            Self::Downloads => "Downloads",
            Self::Notes => "Notes",
            Self::Spaces => "Spaces",
            Self::Calendar => "Calendar",
            Self::ArchivedTabs => "Archived Tabs",
            Self::ClipboardHistory => "Clipboard History",
            Self::GlobalVariables => "Global Variables",
            Self::Inbox => "Inbox",
        }
    }

    fn icon(self) -> IconName {
        match self {
            Self::Media => IconName::Images,
            Self::Downloads => IconName::Download,
            Self::Notes => IconName::NotebookPen,
            Self::Spaces => IconName::Layers,
            Self::Calendar => IconName::CalendarDays,
            Self::ArchivedTabs => IconName::Archive,
            Self::ClipboardHistory => IconName::ClipboardClock,
            Self::GlobalVariables => IconName::Variable,
            Self::Inbox => IconName::Inbox,
        }
    }

    /// Whether the section lists real items yet (and so can have search
    /// results); the others only show their empty state for now.
    fn has_content(self) -> bool {
        !matches!(
            self,
            Self::Notes
                | Self::Calendar
                | Self::ClipboardHistory
                | Self::GlobalVariables
                | Self::Inbox
        )
    }

    fn search_placeholder(self) -> &'static str {
        match self {
            Self::Media => "Search Media…",
            Self::Downloads => "Search Downloads…",
            Self::Notes => "Search Notes…",
            Self::Spaces => "Search Spaces…",
            Self::Calendar => "Search Calendar…",
            Self::ArchivedTabs => "Search Archive…",
            Self::ClipboardHistory => "Search Clipboard…",
            Self::GlobalVariables => "Search Variables…",
            Self::Inbox => "Search Inbox…",
        }
    }
}

/// Library state owned by the window.
pub(crate) struct Library {
    pub open: bool,
    section: LibrarySection,
    search: Entity<InputState>,
    downloads: Vec<DownloadRecord>,
    /// Bumped on every open to replay the slide-in.
    opened: usize,
    _search_changed: Subscription,
}

impl Library {
    pub(crate) fn new(window: &mut Window, cx: &mut Context<BrowserWindow>) -> Self {
        let section = LibrarySection::ArchivedTabs;
        let search =
            cx.new(|cx| InputState::new(window, cx).placeholder(section.search_placeholder()));
        let search_changed = cx.subscribe(&search, |_, _, event: &InputEvent, cx| {
            if matches!(event, InputEvent::Change) {
                cx.notify();
            }
        });
        Self {
            open: false,
            section,
            search,
            downloads: Vec::new(),
            opened: 0,
            _search_changed: search_changed,
        }
    }
}

/// Whether every word of `query` appears in one of `fields`.
fn matches(query: &str, fields: &[&str]) -> bool {
    query.split_whitespace().all(|word| {
        fields
            .iter()
            .any(|field| field.to_lowercase().contains(word))
    })
}

fn extension(path: &str) -> String {
    Path::new(path)
        .extension()
        .map(|e| e.to_string_lossy().to_lowercase())
        .unwrap_or_default()
}

/// A download's file name, or its host while the name is unknown.
fn download_name(record: &DownloadRecord) -> String {
    record
        .path
        .as_deref()
        .and_then(|p| Path::new(p).file_name())
        .map_or_else(
            || display_host(&record.url),
            |n| n.to_string_lossy().into_owned(),
        )
}

/// One download: status icon, name, host and a Show in Finder button.
pub(super) fn download_row(i: usize, record: &DownloadRecord, theme: &CurioTheme) -> AnyElement {
    let name = download_name(record);
    let path = record.path.clone();
    let (icon, color, status) = match record.state.as_str() {
        "completed" => (IconName::CircleCheck, theme.success, "Completed"),
        "failed" => (IconName::CircleX, theme.danger, "Failed"),
        _ => (IconName::ArrowDown, theme.accent, "Downloading…"),
    };
    let hover = theme.row_hover;
    h_flex()
        .id(SharedString::from(format!("download-{i}")))
        .h(px(44.))
        .px(px(8.))
        .gap(px(10.))
        .rounded(px(8.))
        .hover(move |s| s.bg(hover))
        .child(div().text_color(color).child(Icon::new(icon).small()))
        .child(
            v_flex()
                .flex_1()
                .min_w_0()
                .child(div().text_sm().truncate().child(SharedString::from(name)))
                .child(
                    div()
                        .text_xs()
                        .text_color(theme.text_faint)
                        .truncate()
                        .child(SharedString::from(format!(
                            "{status} · {}",
                            display_host(&record.url)
                        ))),
                ),
        )
        .when_some(path, |el, path| {
            el.child(
                Button::new(SharedString::from(format!("reveal-{i}")))
                    .ghost()
                    .xsmall()
                    .icon(IconName::FolderOpen)
                    .tooltip("Show in Finder")
                    .on_click(move |_, _, cx| cx.reveal_path(Path::new(&path))),
            )
        })
        .into_any_element()
}

/// A clickable two-line row: icon, title and a faint subtitle.
fn library_row(
    id: impl Into<ElementId>,
    icon: AnyElement,
    title: String,
    subtitle: String,
    theme: &CurioTheme,
) -> Stateful<Div> {
    let hover = theme.row_hover;
    h_flex()
        .id(id)
        .h(px(44.))
        .px(px(8.))
        .gap(px(10.))
        .rounded(metrics::ROW_RADIUS)
        .cursor_pointer()
        .hover(move |s| s.bg(hover))
        .child(div().size(px(16.)).flex_shrink_0().child(icon))
        .child(
            v_flex()
                .flex_1()
                .min_w_0()
                .child(
                    div()
                        .text_sm()
                        .text_color(theme.text)
                        .truncate()
                        .child(SharedString::from(title)),
                )
                .child(
                    div()
                        .text_xs()
                        .text_color(theme.text_faint)
                        .truncate()
                        .child(SharedString::from(subtitle)),
                ),
        )
}

fn empty_state(icon: IconName, title: &str, body: String, theme: &CurioTheme) -> AnyElement {
    v_flex()
        .flex_1()
        .items_center()
        .justify_center()
        .gap(px(8.))
        .px(px(20.))
        .pb(px(44.))
        .child(
            div()
                .text_color(theme.text_faint)
                .child(Icon::new(icon).size(px(40.))),
        )
        .child(
            div()
                .text_base()
                .font_weight(FontWeight::SEMIBOLD)
                .text_color(theme.text)
                .child(SharedString::from(title.to_owned())),
        )
        .child(
            div()
                .text_sm()
                .text_center()
                .text_color(theme.text_muted)
                .child(SharedString::from(body)),
        )
        .into_any_element()
}

impl BrowserWindow {
    pub(crate) fn toggle_library(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        if self.library.open {
            self.close_library(window, cx);
        } else {
            self.open_library(cx);
        }
    }

    pub(crate) fn open_library(&mut self, cx: &mut Context<Self>) {
        self.library.open = true;
        self.library.opened += 1;
        self.sidebar_peek = false;
        self.reload_library_downloads(cx);
        cx.notify();
    }

    pub(crate) fn close_library(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        if self.library.open {
            self.library.open = false;
            self.focus_page_or_window(window, cx);
            cx.notify();
        }
    }

    fn select_library_section(
        &mut self,
        section: LibrarySection,
        window: &mut Window,
        cx: &mut Context<Self>,
    ) {
        if self.library.section == section {
            return;
        }
        self.library.section = section;
        self.library.search.update(cx, |search, cx| {
            search.set_value(String::new(), window, cx);
            search.set_placeholder(section.search_placeholder(), window, cx);
        });
        cx.notify();
    }

    /// Reloads the download records shown under Media and Downloads.
    pub(crate) fn reload_library_downloads(&mut self, cx: &mut Context<Self>) {
        if !self.library.open {
            return;
        }
        let storage = Services::get(cx).storage.clone();
        let task =
            cx.background_spawn(
                async move { storage.with(|db| db.downloads(200)).unwrap_or_default() },
            );
        cx.spawn(async move |this, cx| {
            let records = task.await;
            let _ = this.update(cx, |this, cx| {
                this.library.downloads = records;
                cx.notify();
            });
        })
        .detach();
    }

    pub(crate) fn render_library(&mut self, _: &mut Window, cx: &mut Context<Self>) -> AnyElement {
        let theme = *CurioTheme::get(cx);
        let reduce_motion = settings(cx).appearance.reduce_motion;
        let query = self.library.search.read(cx).value().trim().to_lowercase();

        let sections: Vec<AnyElement> = LibrarySection::ALL
            .into_iter()
            .map(|section| self.render_library_section_button(section, cx))
            .collect();
        let rail = v_flex()
            .w(RAIL_WIDTH)
            .h_full()
            .flex_shrink_0()
            .child(
                // The traffic lights sit over this strip; it also moves the window.
                div()
                    .id("library-titlebar")
                    .h(metrics::TOOLBAR_HEIGHT)
                    .w_full()
                    .flex_shrink_0()
                    .on_mouse_down(MouseButton::Left, |event, window, _| {
                        if event.click_count >= 2 {
                            window.titlebar_double_click();
                        } else {
                            window.start_window_move();
                        }
                    }),
            )
            .child(
                v_flex()
                    .id("library-sections")
                    .flex_1()
                    .min_h_0()
                    .overflow_y_scroll()
                    .px(px(8.))
                    .pt(px(8.))
                    .gap(px(4.))
                    .children(sections),
            )
            .child(
                // Same corner as the sidebar's library button, so it toggles in place.
                h_flex().h(px(44.)).flex_shrink_0().px(px(10.)).child(
                    chrome_button("library-close", IconName::ArrowLeft, cx)
                        .tooltip(|w, cx| {
                            Tooltip::new("Back to Sidebar")
                                .action(&actions::ToggleLibrary, None)
                                .build(w, cx)
                        })
                        .on_click(|_, window, cx| {
                            window.dispatch_action(Box::new(actions::ToggleLibrary), cx)
                        }),
                ),
            );

        let body = match self.library.section {
            LibrarySection::Media => self.render_library_media(&query, &theme),
            LibrarySection::Downloads => self.render_library_downloads(&query, &theme),
            LibrarySection::Spaces => self.render_library_spaces(&query, &theme, cx),
            LibrarySection::ArchivedTabs => self.render_library_archive(&query, &theme, cx),
            LibrarySection::Notes
            | LibrarySection::Calendar
            | LibrarySection::ClipboardHistory
            | LibrarySection::GlobalVariables
            | LibrarySection::Inbox => None,
        };
        let body = body.map_or_else(
            || self.render_library_empty(&query, &theme),
            |list| {
                div()
                    .id("library-list")
                    .flex_1()
                    .min_h_0()
                    .overflow_y_scroll()
                    .px(px(10.))
                    .pb(px(10.))
                    .child(list)
                    .into_any_element()
            },
        );

        let field = theme.field;
        let field_hover = theme.field_hover;
        let pane = v_flex()
            .flex_1()
            .min_w_0()
            .h_full()
            .child(
                h_flex()
                    .h(metrics::TOOLBAR_HEIGHT)
                    .flex_shrink_0()
                    .pl(px(2.))
                    .pr(px(10.))
                    .child(
                        h_flex()
                            .id("library-search")
                            .flex_1()
                            .min_w_0()
                            .h(px(34.))
                            .px(px(10.))
                            .gap(px(8.))
                            .rounded(metrics::FIELD_RADIUS)
                            .bg(field)
                            .hover(move |s| s.bg(field_hover))
                            .child(
                                div()
                                    .text_color(theme.text_faint)
                                    .child(Icon::new(IconName::Search).small()),
                            )
                            .child(
                                div().flex_1().min_w_0().child(
                                    Input::new(&self.library.search)
                                        .appearance(false)
                                        .small()
                                        .cleanable(true),
                                ),
                            ),
                    ),
            )
            .child(
                div()
                    .px(px(14.))
                    .pt(px(10.))
                    .pb(px(6.))
                    .text_xs()
                    .font_weight(FontWeight::SEMIBOLD)
                    .text_color(theme.text_faint)
                    .child(SharedString::from(self.library.section.label())),
            )
            .child(body);

        h_flex()
            .id("library")
            .relative()
            .w(RAIL_WIDTH + self.sidebar_width)
            .h_full()
            .flex_shrink_0()
            .child(rail)
            .child(pane)
            .with_animation(
                ("library-in", self.library.opened),
                Animation::new(Duration::from_millis(if reduce_motion { 1 } else { 220 }))
                    .with_easing(gpui_kit::ease_out_quint()),
                |el, t| el.opacity(t).left(px(-16. * (1. - t))),
            )
            .into_any_element()
    }

    fn render_library_section_button(
        &self,
        section: LibrarySection,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        let theme = *CurioTheme::get(cx);
        let active = self.library.section == section;
        v_flex()
            .id(SharedString::from(format!("library-{}", section.label())))
            .w_full()
            .items_center()
            .gap(px(5.))
            .py(px(10.))
            .rounded(px(10.))
            .cursor_pointer()
            .text_xs()
            .font_weight(FontWeight::MEDIUM)
            .when(active, |el| {
                el.bg(theme.row_active)
                    .text_color(theme.row_active_text)
                    .border_1()
                    .border_color(theme.row_active_border)
                    .shadow_xs()
            })
            .when(!active, |el| {
                el.text_color(theme.text_muted)
                    .hover(|s| s.bg(theme.row_hover).text_color(theme.text))
            })
            .child(
                div()
                    .text_color(theme.accent_text)
                    .child(Icon::new(section.icon()).size(px(22.))),
            )
            .child(
                div()
                    .text_center()
                    .child(SharedString::from(section.label())),
            )
            .on_click(cx.listener(move |this, _, window, cx| {
                this.select_library_section(section, window, cx);
            }))
            .into_any_element()
    }

    fn render_library_empty(&self, query: &str, theme: &CurioTheme) -> AnyElement {
        let section = self.library.section;
        if !query.is_empty() && section.has_content() {
            return empty_state(
                IconName::Search,
                "No results",
                format!("Nothing in {} matches “{query}”.", section.label()),
                theme,
            );
        }
        let (title, body) = match section {
            LibrarySection::Media => (
                "No media yet",
                "Images and videos you download show up here.",
            ),
            LibrarySection::Downloads => ("No downloads yet", "Files you download show up here."),
            LibrarySection::Notes => ("No notes yet", "Notes you write will live here."),
            LibrarySection::Spaces => ("No spaces yet", "Create a space to organize your tabs."),
            LibrarySection::Calendar => (
                "Nothing scheduled",
                "Your upcoming events will show up here.",
            ),
            LibrarySection::ArchivedTabs => (
                "Nothing here yet!",
                "Tabs you close are archived here, so you can bring them back.",
            ),
            LibrarySection::ClipboardHistory => (
                "Nothing copied yet",
                "Text and links you copy will show up here.",
            ),
            LibrarySection::GlobalVariables => (
                "No variables yet",
                "Variables you define will be available everywhere in Curio.",
            ),
            LibrarySection::Inbox => ("You’re all caught up", "New items will land here."),
        };
        empty_state(section.icon(), title, body.to_owned(), theme)
    }

    fn render_library_downloads(&self, query: &str, theme: &CurioTheme) -> Option<AnyElement> {
        let rows: Vec<AnyElement> = self
            .library
            .downloads
            .iter()
            .filter(|r| matches(query, &[&download_name(r), &r.url]))
            .enumerate()
            .map(|(i, record)| download_row(i, record, theme))
            .collect();
        (!rows.is_empty()).then(|| v_flex().gap(px(2.)).children(rows).into_any_element())
    }

    fn render_library_media(&self, query: &str, theme: &CurioTheme) -> Option<AnyElement> {
        let items: Vec<(String, PathBuf, bool)> = self
            .library
            .downloads
            .iter()
            .filter(|r| r.state == "completed")
            .filter_map(|r| {
                let path = r.path.as_deref()?;
                let ext = extension(path);
                let image = IMAGE_EXTENSIONS.contains(&ext.as_str());
                let video = VIDEO_EXTENSIONS.contains(&ext.as_str());
                let name = download_name(r);
                ((image || video) && matches(query, &[&name, &r.url]))
                    .then(|| (name, PathBuf::from(path), image))
            })
            .collect();
        if items.is_empty() {
            return None;
        }
        let tiles: Vec<AnyElement> = items
            .into_iter()
            .enumerate()
            .map(|(i, (name, path, image))| {
                let preview = if image {
                    let faint = theme.text_faint;
                    img(path.clone())
                        .size_full()
                        .object_fit(ObjectFit::Cover)
                        .with_fallback(move || {
                            div()
                                .text_color(faint)
                                .child(Icon::new(IconName::Image))
                                .into_any_element()
                        })
                        .into_any_element()
                } else {
                    div()
                        .text_color(theme.text_faint)
                        .child(Icon::new(IconName::Film).size(px(24.)))
                        .into_any_element()
                };
                v_flex()
                    .id(SharedString::from(format!("media-{i}")))
                    .flex_1()
                    .min_w_0()
                    .gap(px(4.))
                    .cursor_pointer()
                    .hover(|s| s.opacity(0.85))
                    .child(
                        div()
                            .h(px(96.))
                            .w_full()
                            .rounded(px(10.))
                            .overflow_hidden()
                            .bg(theme.surface_raised)
                            .border_1()
                            .border_color(theme.surface_border)
                            .flex()
                            .items_center()
                            .justify_center()
                            .child(preview),
                    )
                    .child(
                        div()
                            .text_xs()
                            .text_color(theme.text_muted)
                            .truncate()
                            .child(SharedString::from(name)),
                    )
                    .tooltip(|w, cx| Tooltip::new("Show in Finder").build(w, cx))
                    .on_click(move |_, _, cx| cx.reveal_path(&path))
                    .into_any_element()
            })
            .collect();
        // Two tiles per row; an odd last tile keeps its column width.
        let mut rows = Vec::new();
        let mut tiles = tiles.into_iter();
        while let Some(first) = tiles.next() {
            let second = tiles
                .next()
                .unwrap_or_else(|| div().flex_1().into_any_element());
            rows.push(
                h_flex()
                    .gap(px(8.))
                    .items_start()
                    .child(first)
                    .child(second),
            );
        }
        Some(v_flex().gap(px(10.)).children(rows).into_any_element())
    }

    fn render_library_spaces(
        &self,
        query: &str,
        theme: &CurioTheme,
        cx: &mut Context<Self>,
    ) -> Option<AnyElement> {
        let active_space = self.workspace.active_space_id();
        let mut groups = Vec::new();
        for space in self.workspace.spaces() {
            let space_matches = matches(query, &[&space.name]);
            let tabs: Vec<AnyElement> = space
                .strip
                .ordered_tab_ids()
                .into_iter()
                .filter_map(|id| space.strip.tab(id))
                .filter(|tab| space_matches || matches(query, &[&tab.display_title(), &tab.url]))
                .map(|tab| {
                    let id = tab.id;
                    let title = tab.display_title();
                    let icon = favicon(tab.favicon_url.as_deref(), &title, px(16.));
                    library_row(
                        SharedString::from(format!("library-tab-{id}")),
                        icon,
                        title,
                        display_host(&tab.url),
                        theme,
                    )
                    .on_click(cx.listener(move |this, _, window, cx| {
                        this.activate_tab(id, window, cx);
                        this.close_library(window, cx);
                    }))
                    .into_any_element()
                })
                .collect();
            if !space_matches && tabs.is_empty() {
                continue;
            }
            let id = space.id;
            let count = space.strip.len();
            let hover = theme.row_hover;
            let header = h_flex()
                .id(SharedString::from(format!("library-space-{id}")))
                .h(px(32.))
                .px(px(8.))
                .gap(px(8.))
                .rounded(metrics::ROW_RADIUS)
                .cursor_pointer()
                .hover(move |s| s.bg(hover))
                .child(
                    div()
                        .size(px(8.))
                        .rounded_full()
                        .bg(CurioTheme::swatch(space.color)),
                )
                .child(
                    div()
                        .flex_1()
                        .min_w_0()
                        .truncate()
                        .text_sm()
                        .font_weight(FontWeight::SEMIBOLD)
                        .text_color(theme.text)
                        .child(SharedString::from(format!(
                            "{}  {}",
                            space.icon, space.name
                        ))),
                )
                .when(id == active_space, |el| {
                    el.child(
                        div()
                            .text_xs()
                            .text_color(theme.accent_text)
                            .child("Current"),
                    )
                })
                .child(
                    div()
                        .text_xs()
                        .text_color(theme.text_faint)
                        .child(SharedString::from(count.to_string())),
                )
                .on_click(cx.listener(move |this, _, window, cx| {
                    this.switch_space(id, window, cx);
                    this.close_library(window, cx);
                }));
            groups.push(
                v_flex()
                    .gap(px(2.))
                    .child(header)
                    .child(v_flex().pl(px(8.)).children(tabs))
                    .into_any_element(),
            );
        }
        (!groups.is_empty()).then(|| v_flex().gap(px(12.)).children(groups).into_any_element())
    }

    fn render_library_archive(
        &self,
        query: &str,
        theme: &CurioTheme,
        cx: &mut Context<Self>,
    ) -> Option<AnyElement> {
        let rows: Vec<AnyElement> = self
            .workspace
            .closed_tabs()
            .filter(|closed| matches(query, &[&closed.tab.display_title(), &closed.tab.url]))
            .map(|closed| {
                let id = closed.tab.id;
                let title = closed.tab.display_title();
                let host = display_host(&closed.tab.url);
                let subtitle = match self.workspace.space(closed.space) {
                    Some(space) => format!("{host} · {}", space.name),
                    None => host,
                };
                let icon = favicon(closed.tab.favicon_url.as_deref(), &title, px(16.));
                library_row(
                    SharedString::from(format!("archived-{id}")),
                    icon,
                    title,
                    subtitle,
                    theme,
                )
                .tooltip(|w, cx| Tooltip::new("Reopen Tab").build(w, cx))
                .on_click(cx.listener(move |this, _, window, cx| {
                    this.reopen_archived_tab(id, window, cx);
                }))
                .into_any_element()
            })
            .collect();
        (!rows.is_empty()).then(|| v_flex().gap(px(2.)).children(rows).into_any_element())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn search_matches_every_word() {
        assert!(matches("", &["anything"]));
        assert!(matches(
            "rust book",
            &[
                "The Rust Programming Language",
                "https://doc.rust-lang.org/book"
            ]
        ));
        assert!(!matches("rust python", &["The Rust Book"]));
    }

    #[test]
    fn media_extensions_are_case_insensitive() {
        assert_eq!(extension("/tmp/Photo.JPG"), "jpg");
        assert_eq!(extension("/tmp/archive"), "");
    }
}

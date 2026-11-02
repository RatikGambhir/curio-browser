//! The library: Arc-style collections shown in place of the sidebar. A rail
//! of sections (media, downloads, notes, spaces, calendar, archived tabs)
//! sits under the traffic lights, with a searchable list beside it.
//!
//! Opening and closing morph the left column: it widens or narrows to fit,
//! while the sidebar and the library cross-fade inside it.

use std::path::{Path, PathBuf};
use std::time::{Duration, Instant};

use curio_core::display_host;
use curio_storage::DownloadRecord;
use gpui_kit::assets::IconName;
use gpui_kit::component::button::{Button, ButtonVariants as _};
use gpui_kit::component::input::{InputEvent, InputState};
use gpui_kit::component::{Icon, Sizable as _, h_flex, v_flex};
use gpui_kit::prelude::FluentBuilder as _;
use gpui_kit::{
    AnyElement, AppContext as _, Context, Entity, FontWeight, InteractiveElement as _, IntoElement,
    ObjectFit, ParentElement as _, Pixels, SharedString, StatefulInteractiveElement as _,
    Styled as _, StyledImage as _, Subscription, Window, div, img, px,
};

use super::BrowserWindow;
use crate::components::prelude::*;
use crate::theme::{CurioTheme, metrics};
use crate::{Services, actions, settings};

/// Width of the section rail. Wide enough for the traffic lights above it.
pub(crate) const RAIL_WIDTH: Pixels = px(84.);

/// How long the sidebar ⇄ library morph takes.
const TRANSITION: Duration = Duration::from_millis(280);

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
    Aliases,
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
        Self::Aliases,
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
            Self::Aliases => "Aliases",
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
            Self::Aliases => IconName::AtSign,
            Self::Inbox => IconName::Inbox,
        }
    }

    /// Whether the section lists real items yet (and so can have search
    /// results); the others only show their empty state for now.
    fn has_content(self) -> bool {
        !matches!(
            self,
            Self::Notes | Self::Calendar | Self::ClipboardHistory | Self::Aliases | Self::Inbox
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
            Self::Aliases => "Search Aliases…",
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
    /// The sidebar ⇄ library morph in flight, if any.
    transition: Option<Transition>,
    _search_changed: Subscription,
}

/// A morph between the sidebar (0.0) and the library (1.0), heading
/// towards whichever `Library::open` says.
#[derive(Debug, Clone, Copy)]
struct Transition {
    started: Instant,
    /// Where the morph started, so reversing it mid-way doesn't jump.
    from: f32,
}

impl Library {
    fn target(&self) -> f32 {
        if self.open { 1.0 } else { 0.0 }
    }

    /// How far the left column is towards the library right now, or `None`
    /// once the morph has finished.
    fn progress_at(&self, now: Instant) -> Option<f32> {
        let transition = self.transition?;
        let t = now
            .saturating_duration_since(transition.started)
            .as_secs_f32()
            / TRANSITION.as_secs_f32();
        if t >= 1.0 {
            return None;
        }
        // Cubic ease-out: quick to respond, gentle to settle. The page
        // resizes with the column, so it never has to catch up a jump.
        let eased = 1.0 - (1.0 - t).powi(3);
        Some(transition.from + (self.target() - transition.from) * eased)
    }

    /// Sets the open state, morphing from wherever the column is now.
    fn set_open(&mut self, open: bool, animate: bool) {
        let now = Instant::now();
        let from = self.progress_at(now).unwrap_or_else(|| self.target());
        self.open = open;
        self.transition = animate.then_some(Transition { started: now, from });
    }

    /// Closes without animating, for when the whole layout changes anyway.
    pub(crate) fn close_immediately(&mut self) {
        self.open = false;
        self.transition = None;
    }
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
            transition: None,
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
    let path = record.path.clone();
    let (icon, color, status) = match record.state.as_str() {
        "completed" => (IconName::CircleCheck, theme.success, "Completed"),
        "failed" => (IconName::CircleX, theme.danger, "Failed"),
        _ => (IconName::ArrowDown, theme.accent, "Downloading…"),
    };
    ListItem::new(SharedString::from(format!("download-{i}")))
        .cursor_default()
        .leading(div().text_color(color).child(Icon::new(icon).small()))
        .title(download_name(record))
        .subtitle(format!("{status} · {}", display_host(&record.url)))
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

/// The empty-state copy for each section.
fn empty_copy(section: LibrarySection) -> (&'static str, &'static str) {
    match section {
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
        LibrarySection::Aliases => (
            "No aliases yet",
            "Short names you give to sites and pages will show up here.",
        ),
        LibrarySection::Inbox => ("You’re all caught up", "New items will land here."),
    }
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
        let animate = !settings(cx).appearance.reduce_motion;
        self.library.set_open(true, animate);
        self.sidebar_peek = false;
        self.reload_library_downloads(cx);
        cx.notify();
    }

    pub(crate) fn close_library(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        if self.library.open {
            let animate = !settings(cx).appearance.reduce_motion;
            self.library.set_open(false, animate);
            self.focus_page_or_window(window, cx);
            cx.notify();
        }
    }

    /// How far the left column is from the sidebar (0.0) to the library
    /// (1.0). While a morph is running this asks for the next frame.
    pub(crate) fn library_progress(&mut self, window: &mut Window) -> f32 {
        match self.library.progress_at(Instant::now()) {
            Some(progress) => {
                window.request_animation_frame();
                progress
            }
            None => {
                self.library.transition = None;
                self.library.target()
            }
        }
    }

    /// Whether the sidebar and library are morphing into each other.
    pub(crate) fn library_animating(&self) -> bool {
        self.library.transition.is_some()
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
                    .window_drag_area(),
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
                    IconButton::new("library-close", IconName::ArrowLeft)
                        .tooltip("Back to Sidebar")
                        .action(actions::ToggleLibrary),
                ),
            );

        let body = match self.library.section {
            LibrarySection::Media => self.render_library_media(&query, &theme),
            LibrarySection::Downloads => self.render_library_downloads(&query, &theme),
            LibrarySection::Spaces => self.render_library_spaces(&query, &theme, cx),
            LibrarySection::ArchivedTabs => self.render_library_archive(&query, cx),
            LibrarySection::Notes
            | LibrarySection::Calendar
            | LibrarySection::ClipboardHistory
            | LibrarySection::Aliases
            | LibrarySection::Inbox => None,
        };
        let body = body.map_or_else(
            || self.render_library_empty(&query),
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
                        SearchField::new("library-search", &self.library.search)
                            .cleanable(true)
                            .flex_1(),
                    ),
            )
            .child(
                SectionLabel::new(self.library.section.label())
                    .px(px(14.))
                    .pt(px(10.))
                    .pb(px(6.)),
            )
            .child(body);

        // A fixed width, so the contents don't reflow while the column morphs.
        h_flex()
            .id("library")
            .w(RAIL_WIDTH + self.sidebar_width)
            .h_full()
            .flex_shrink_0()
            .child(rail)
            .child(pane)
            .into_any_element()
    }

    fn render_library_section_button(
        &self,
        section: LibrarySection,
        cx: &mut Context<Self>,
    ) -> AnyElement {
        RailItem::new(
            SharedString::from(format!("library-{}", section.label())),
            section.icon(),
            section.label(),
        )
        .selected(self.library.section == section)
        .on_click(cx.listener(move |this, _, window, cx| {
            this.select_library_section(section, window, cx);
        }))
        .into_any_element()
    }

    fn render_library_empty(&self, query: &str) -> AnyElement {
        let section = self.library.section;
        if !query.is_empty() && section.has_content() {
            return EmptyState::new("No results")
                .icon(IconName::Search)
                .description(format!("Nothing in {} matches “{query}”.", section.label()))
                .into_any_element();
        }
        let (title, description) = empty_copy(section);
        EmptyState::new(title)
            .icon(section.icon())
            .description(description)
            .into_any_element()
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
                            .surface(theme)
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
                    .tooltip_text("Show in Finder")
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
                    ListItem::new(SharedString::from(format!("library-tab-{id}")))
                        .leading(Favicon::new(title.clone()).url(tab.favicon_url.as_deref()))
                        .title(title)
                        .subtitle(display_host(&tab.url))
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
            let header = ListItem::new(SharedString::from(format!("library-space-{id}")))
                .h(px(32.))
                .gap(px(8.))
                .leading(ColorDot::new(CurioTheme::swatch(space.color)))
                .title(format!("{}  {}", space.icon, space.name))
                .title_weight(FontWeight::SEMIBOLD)
                .text_color(theme.text)
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

    fn render_library_archive(&self, query: &str, cx: &mut Context<Self>) -> Option<AnyElement> {
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
                ListItem::new(SharedString::from(format!("archived-{id}")))
                    .leading(Favicon::new(title.clone()).url(closed.tab.favicon_url.as_deref()))
                    .title(title)
                    .subtitle(subtitle)
                    .tooltip_text("Reopen Tab")
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

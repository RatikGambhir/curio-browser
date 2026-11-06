//! The library: Arc-style collections shown in place of the sidebar. A rail
//! of sections (media, downloads, notes, spaces, calendar, archived tabs)
//! sits under the traffic lights, with a searchable list beside it.
//!
//! Opening and closing morph the left column: it widens or narrows to fit,
//! while the sidebar and the library cross-fade inside it.

use std::path::{Path, PathBuf};
use std::rc::Rc;
use std::time::{Duration, Instant};

use curio_core::display_host;
use curio_storage::DownloadRecord;
use curio_storage::media::{self, MediaFile, MediaKind};
use gpui_kit::assets::IconName;
use gpui_kit::component::button::{Button, ButtonVariants as _};
use gpui_kit::component::input::{InputEvent, InputState};
use gpui_kit::component::{Icon, Sizable as _, h_flex, v_flex};
use gpui_kit::prelude::FluentBuilder as _;
use gpui_kit::{
    AnyElement, App, AppContext as _, Context, Entity, FontWeight, InteractiveElement as _,
    IntoElement, ObjectFit, ParentElement as _, Pixels, SharedString,
    StatefulInteractiveElement as _, Styled as _, StyledImage as _, Subscription, Window, div, img,
    px, uniform_list,
};

use super::BrowserWindow;
use super::thumbnails::{MediaThumbnails, Thumbnail};
use crate::components::prelude::*;
use crate::theme::{CurioTheme, metrics};
use crate::{Services, actions, settings};

/// Width of the section rail. Wide enough for the traffic lights above it.
pub(crate) const RAIL_WIDTH: Pixels = px(84.);

/// How long the sidebar ⇄ library morph takes.
const TRANSITION: Duration = Duration::from_millis(280);

/// Height of a Media tile's preview. The preview is fixed so every row is the
/// same height, which `uniform_list` needs.
const MEDIA_PREVIEW_HEIGHT: Pixels = px(140.);

/// A collection in the library.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum LibrarySection {
    Media,
    Downloads,
    // Hidden from the rail for now (see `ALL`).
    #[allow(dead_code)]
    Notes,
    Spaces,
    // Hidden from the rail for now (see `ALL`).
    #[allow(dead_code)]
    Calendar,
    ArchivedTabs,
    ClipboardHistory,
    // Hidden from the rail for now (see `ALL`).
    #[allow(dead_code)]
    Aliases,
    // Hidden from the rail for now (see `ALL`).
    #[allow(dead_code)]
    Inbox,
}

impl LibrarySection {
    // Notes, Calendar, Aliases and Inbox are hidden from the rail until
    // they're built. Uncomment them (and bump the length back to 9) to show
    // them again.
    const ALL: [Self; 5] = [
        Self::Media,
        Self::Downloads,
        // Self::Notes,
        Self::Spaces,
        // Self::Calendar,
        Self::ArchivedTabs,
        Self::ClipboardHistory,
        // Self::Aliases,
        // Self::Inbox,
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
    /// Images and videos found in the user's folders, newest first.
    media: Rc<Vec<MediaFile>>,
    media_scanning: bool,
    /// Whether a scan has finished since the library opened.
    media_scanned: bool,
    thumbnails: Entity<MediaThumbnails>,
    /// The sidebar ⇄ library morph in flight, if any.
    transition: Option<Transition>,
    _search_changed: Subscription,
    _thumbnails_changed: Subscription,
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
        let thumbnails = cx.new(|_| MediaThumbnails::new());
        let thumbnails_changed = cx.observe(&thumbnails, |_, _, cx| cx.notify());
        Self {
            open: false,
            section,
            search,
            downloads: Vec::new(),
            media: Rc::default(),
            media_scanning: false,
            media_scanned: false,
            thumbnails,
            transition: None,
            _search_changed: search_changed,
            _thumbnails_changed: thumbnails_changed,
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
            "Images and videos in your Desktop, Documents, Downloads, Pictures and Movies \
             folders show up here. If some are missing, allow Curio in System Settings › \
             Privacy & Security › Files & Folders.",
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

/// One Media tile: a preview, the file name and its folder. Clicking it
/// shows the file in Finder.
fn media_tile(
    index: usize,
    file: &MediaFile,
    thumbnails: &Entity<MediaThumbnails>,
    theme: &CurioTheme,
    cx: &mut App,
) -> AnyElement {
    let fallback_icon = match file.kind {
        MediaKind::Image => IconName::Image,
        MediaKind::Video => IconName::Film,
    };
    let thumbnail = thumbnails.update(cx, |thumbnails, cx| {
        thumbnails.get(&file.path, file.kind, cx)
    });
    let preview = match thumbnail {
        Thumbnail::Ready(image) => img(image)
            .size_full()
            .object_fit(ObjectFit::Cover)
            .into_any_element(),
        Thumbnail::Loading => div().into_any_element(),
        Thumbnail::Unavailable => div()
            .text_color(theme.text_faint)
            .child(Icon::new(fallback_icon).size(px(24.)))
            .into_any_element(),
    };
    let path = file.path.clone();
    v_flex()
        .id(SharedString::from(format!("media-{index}")))
        .flex_1()
        .min_w_0()
        .gap(px(2.))
        .cursor_pointer()
        .hover(|s| s.opacity(0.85))
        .child(
            div()
                .h(MEDIA_PREVIEW_HEIGHT)
                .w_full()
                .mb(px(2.))
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
                .child(SharedString::from(file.name.clone())),
        )
        .child(
            div()
                .text_xs()
                .text_color(theme.text_faint)
                .truncate()
                .child(SharedString::from(file.folder.clone())),
        )
        .tooltip_text("Show in Finder")
        .on_click(move |_, _, cx| cx.reveal_path(&path))
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
        let animate = !settings(cx).appearance.reduce_motion;
        self.library.set_open(true, animate);
        self.sidebar_peek = false;
        self.library.media_scanned = false;
        self.reload_library_downloads(cx);
        self.reload_library_media(cx);
        cx.notify();
    }

    pub(crate) fn close_library(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        if self.library.open {
            let animate = !settings(cx).appearance.reduce_motion;
            self.library.set_open(false, animate);
            self.library
                .thumbnails
                .update(cx, |thumbnails, cx| thumbnails.clear(window, cx));
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
        self.reload_library_media(cx);
        cx.notify();
    }

    /// Scans the user's folders for Media, while Media is showing. Scanning
    /// only then means macOS asks for folder access when the user is looking
    /// at Media, not as soon as the library opens.
    fn reload_library_media(&mut self, cx: &mut Context<Self>) {
        let library = &self.library;
        if !library.open || library.section != LibrarySection::Media || library.media_scanning {
            return;
        }
        self.library.media_scanning = true;
        let storage = Services::get(cx).storage.clone();
        let task = cx.background_spawn(async move {
            // Downloads saved outside the scanned folders still count.
            let downloads = storage.with(|db| db.downloads(200)).unwrap_or_default();
            let extra = downloads
                .into_iter()
                .filter(|record| record.state == "completed")
                .filter_map(|record| Some((PathBuf::from(record.path?), "Downloads".to_owned())));
            media::scan_home(extra)
        });
        cx.spawn(async move |this, cx| {
            let files = task.await;
            let _ = this.update(cx, |this, cx| {
                this.library.media = Rc::new(files);
                this.library.media_scanning = false;
                this.library.media_scanned = true;
                cx.notify();
            });
        })
        .detach();
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

        let list = match self.library.section {
            LibrarySection::Media => None,
            LibrarySection::Downloads => self.render_library_downloads(&query, &theme),
            LibrarySection::Spaces => self.render_library_spaces(&query, &theme, cx),
            LibrarySection::ArchivedTabs => self.render_library_archive(&query, cx),
            LibrarySection::Notes
            | LibrarySection::Calendar
            | LibrarySection::ClipboardHistory
            | LibrarySection::Aliases
            | LibrarySection::Inbox => None,
        };
        let body = if self.library.section == LibrarySection::Media {
            // Media scrolls itself, rendering only the rows in view.
            self.render_library_media(&query, &theme)
        } else {
            list.map_or_else(
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
            )
        };

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

    /// Media as a list of one tile per row. Only the rows in view are
    /// rendered, so thousands of files cost no more than a screenful.
    fn render_library_media(&self, query: &str, theme: &CurioTheme) -> AnyElement {
        let media = self.library.media.clone();
        let matching: Rc<Vec<usize>> = Rc::new(
            media
                .iter()
                .enumerate()
                .filter(|(_, file)| matches(query, &[&file.name, &file.folder]))
                .map(|(i, _)| i)
                .collect(),
        );
        if matching.is_empty() {
            if self.library.media_scanning && !self.library.media_scanned {
                return EmptyState::new("Looking for images and videos…")
                    .icon(IconName::Images)
                    .into_any_element();
            }
            return self.render_library_empty(query);
        }

        let theme = *theme;
        let thumbnails = self.library.thumbnails.clone();
        uniform_list("library-media", matching.len(), move |range, _, cx| {
            range
                .map(|i| {
                    h_flex().pb(px(10.)).child(media_tile(
                        i,
                        &media[matching[i]],
                        &thumbnails,
                        &theme,
                        cx,
                    ))
                })
                .collect()
        })
        .flex_1()
        .min_h_0()
        .px(px(10.))
        .into_any_element()
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
                .leading(ColorDot::new(CurioTheme::gradient_swatch(space.gradient)))
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

    /// Closed tabs, newest first, each with a dot in its space's color.
    fn render_library_archive(&self, query: &str, cx: &mut Context<Self>) -> Option<AnyElement> {
        let rows: Vec<AnyElement> = self
            .workspace
            .closed_tabs()
            .filter_map(|closed| {
                // A tab whose space was deleted reopens in the active space.
                let space = self.workspace.space(closed.space);
                let space_name = space.map_or("", |s| s.name.as_str());
                let title = closed.tab.display_title();
                matches(query, &[&title, &closed.tab.url, space_name])
                    .then_some((closed, space, title))
            })
            .map(|(closed, space, title)| {
                let id = closed.tab.id;
                let host = display_host(&closed.tab.url);
                let target = space.unwrap_or_else(|| self.workspace.active_space());
                ListItem::new(SharedString::from(format!("archived-{id}")))
                    .leading(Favicon::new(title.clone()).url(closed.tab.favicon_url.as_deref()))
                    .title(title)
                    .subtitle(match space {
                        Some(space) => format!("{host} · {}", space.name),
                        None => host,
                    })
                    .tooltip_text(format!("Reopen in {}", target.name))
                    .when_some(space, |item, space| {
                        item.child(
                            ColorDot::new(CurioTheme::gradient_swatch(space.gradient))
                                .diameter(px(8.)),
                        )
                    })
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
}

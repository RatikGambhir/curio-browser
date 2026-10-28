//! A browser tab backed by a native webview.
//!
//! [`BrowserTab`] owns the engine side of one tab: the webview (created
//! lazily and dropped when the tab is put to sleep), the live page state, and
//! the translation of engine callbacks into [`BrowserTabEvent`]s.
//!
//! Engine callbacks run synchronously inside the platform event loop, where
//! GPUI's app state must not be borrowed. They only push [`RawEvent`]s into
//! a channel; a foreground task drains it and updates the entity.

use std::rc::Rc;
use std::time::{Duration, Instant};

use curio_core::{TabId, is_internal_url};
use gpui_kit::{App, AppContext as _, Context, Entity, EventEmitter, Task, Window};
use gpui_webview::WebView;
use wry::{NewWindowResponse, PageLoadEvent};

use crate::engine::EngineConfig;
use crate::ipc::{PageMessage, PageRect, parse_message};
use crate::native::{self, HistoryState};
use crate::scripts;

/// How long a navigation may go without finishing before the tab stops
/// showing a spinner and offers a retry.
const STALLED_LOAD: Duration = Duration::from_secs(30);

/// Live state of the page shown in a tab.
#[derive(Debug, Clone, Default, PartialEq)]
pub struct PageState {
    pub url: String,
    pub title: String,
    pub favicon: Option<String>,
    pub theme_color: Option<String>,
    pub loading: bool,
    pub history: HistoryState,
    pub secure: bool,
    /// The current text selection in the page, if any.
    pub selection: Option<Selection>,
    /// Set when the last load did not finish in time.
    pub stalled: bool,
    pub zoom: f64,
}

/// A text selection reported by the page.
#[derive(Debug, Clone, PartialEq)]
pub struct Selection {
    pub text: String,
    /// Bounds in page viewport coordinates.
    pub rect: Option<PageRect>,
}

/// Find-in-page result.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct FindResult {
    pub matches: u32,
    /// 1-based index of the highlighted match, 0 when there are none.
    pub active: u32,
}

/// Events emitted by a [`BrowserTab`] for the UI to react to.
#[derive(Debug, Clone, PartialEq)]
pub enum BrowserTabEvent {
    /// URL, title, favicon, loading or history state changed.
    StateChanged,
    /// A navigation committed to a new URL (for history recording).
    Navigated { url: String },
    /// The page finished loading.
    LoadFinished { url: String, title: String },
    /// The page asked to open a link in a new tab.
    OpenInNewTab { url: String, background: bool },
    /// The page tried to open a link with a non-web scheme (mailto:, an app).
    ExternalScheme { url: String },
    /// A browser shortcut was pressed while the page had focus.
    Shortcut { keystroke: String },
    /// The selection changed.
    SelectionChanged,
    /// The page scrolled (debounced).
    Scrolled { y: f64 },
    DownloadStarted { url: String, path: String },
    DownloadFinished { url: String, path: Option<String>, success: bool },
}

/// Engine callbacks, forwarded through a channel.
enum RawEvent {
    Ipc(String),
    Load(PageLoadEvent, String),
    Title(String),
    NewWindow(String),
    External(String),
    DownloadStarted(String, String),
    DownloadFinished(String, Option<String>, bool),
}

/// One browser tab.
pub struct BrowserTab {
    id: TabId,
    engine: Rc<EngineConfig>,
    webview: Option<Entity<WebView>>,
    state: PageState,
    active: bool,
    restore_scroll: Option<f64>,
    last_active: Instant,
    load_started: Option<Instant>,
    _events: Option<Task<()>>,
}

impl EventEmitter<BrowserTabEvent> for BrowserTab {}

impl BrowserTab {
    /// Creates a tab without a webview. The webview is created the first time
    /// the tab is shown ([`BrowserTab::set_active`]) or navigated.
    #[must_use]
    pub fn new(
        id: TabId,
        url: impl Into<String>,
        title: impl Into<String>,
        favicon: Option<String>,
        scroll_y: f64,
        engine: Rc<EngineConfig>,
    ) -> Self {
        Self {
            id,
            engine,
            webview: None,
            state: PageState {
                url: url.into(),
                title: title.into(),
                favicon,
                zoom: 1.0,
                ..PageState::default()
            },
            active: false,
            restore_scroll: (scroll_y > 0.0).then_some(scroll_y),
            last_active: Instant::now(),
            load_started: None,
            _events: None,
        }
    }

    /// The tab's identity.
    #[must_use]
    pub fn id(&self) -> TabId {
        self.id
    }

    /// Live page state.
    #[must_use]
    pub fn state(&self) -> &PageState {
        &self.state
    }

    /// The webview entity to render, when the tab is awake.
    #[must_use]
    pub fn webview(&self) -> Option<&Entity<WebView>> {
        self.webview.as_ref()
    }

    /// Whether the tab currently holds a live webview.
    #[must_use]
    pub fn is_awake(&self) -> bool {
        self.webview.is_some()
    }

    /// Whether this tab shows one of Curio's internal pages.
    #[must_use]
    pub fn is_internal(&self) -> bool {
        is_internal_url(&self.state.url)
    }

    /// When the tab was last shown.
    #[must_use]
    pub fn last_active(&self) -> Instant {
        self.last_active
    }

    /// Whether the tab is the visible tab of its window.
    #[must_use]
    pub fn is_active(&self) -> bool {
        self.active
    }

    fn create_webview(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        if self.webview.is_some() || self.is_internal() {
            return;
        }
        let (tx, rx) = async_channel::unbounded::<RawEvent>();
        let builder = self.engine.builder(&self.state.url);
        let builder = {
            let tx = tx.clone();
            builder.with_ipc_handler(move |request| {
                let _ = tx.try_send(RawEvent::Ipc(request.into_body()));
            })
        };
        let builder = {
            let tx = tx.clone();
            builder.with_on_page_load_handler(move |event, url| {
                let _ = tx.try_send(RawEvent::Load(event, url));
            })
        };
        let builder = {
            let tx = tx.clone();
            builder.with_document_title_changed_handler(move |title| {
                let _ = tx.try_send(RawEvent::Title(title));
            })
        };
        let builder = {
            let tx = tx.clone();
            builder.with_navigation_handler(move |url| {
                if crate::engine::is_engine_navigable(&url) {
                    true
                } else {
                    let _ = tx.try_send(RawEvent::External(url));
                    false
                }
            })
        };
        let builder = {
            let tx = tx.clone();
            builder.with_new_window_req_handler(move |url, _features| {
                // Pop-ups and target=_blank links become Curio tabs.
                if crate::engine::is_engine_navigable(&url) && !url.is_empty() {
                    let _ = tx.try_send(RawEvent::NewWindow(url));
                }
                NewWindowResponse::Deny
            })
        };
        let builder = {
            let tx = tx.clone();
            let download_dir = self.engine.download_dir.clone();
            builder.with_download_started_handler(move |url, path| {
                if let Some(dir) = &download_dir
                    && let Some(name) = path.file_name()
                {
                    *path = crate::engine::unique_path(&dir.join(name));
                }
                let _ = tx.try_send(RawEvent::DownloadStarted(
                    url,
                    path.to_string_lossy().into_owned(),
                ));
                true
            })
        };
        let builder = builder.with_download_completed_handler(move |url, path, success| {
            let _ = tx.try_send(RawEvent::DownloadFinished(
                url,
                path.map(|p| p.to_string_lossy().into_owned()),
                success,
            ));
        });

        let webview = match WebView::build(builder, window, cx) {
            Ok(webview) => webview,
            Err(error) => {
                tracing::error!(%error, "could not create webview");
                return;
            }
        };
        let visible = self.active;
        let webview = cx.new(|_| webview);
        webview.update(cx, |view, _| {
            if !visible {
                view.hide();
            }
        });
        self.webview = Some(webview);
        self.state.loading = true;
        self.load_started = Some(Instant::now());
        self._events = Some(cx.spawn(async move |this, cx| {
            while let Ok(event) = rx.recv().await {
                if this
                    .update(cx, |tab, cx| tab.handle_raw(event, cx))
                    .is_err()
                {
                    break;
                }
            }
        }));
        cx.emit(BrowserTabEvent::StateChanged);
    }

    fn with_raw<R>(&self, cx: &App, f: impl FnOnce(&wry::WebView) -> R) -> Option<R> {
        self.webview.as_ref().map(|webview| f(webview.read(cx).raw()))
    }

    fn refresh_history(&mut self, cx: &App) {
        if let Some((history, secure)) =
            self.with_raw(cx, |raw| (native::history_state(raw), native::is_secure(raw)))
        {
            self.state.history = history;
            self.state.secure = secure;
        }
    }

    fn handle_raw(&mut self, event: RawEvent, cx: &mut Context<Self>) {
        match event {
            RawEvent::Load(PageLoadEvent::Started, url) => {
                self.state.loading = true;
                self.state.stalled = false;
                self.state.selection = None;
                self.load_started = Some(Instant::now());
                if !url.is_empty() && url != self.state.url {
                    self.state.url = url;
                    self.state.favicon = None;
                    self.state.theme_color = None;
                }
                self.refresh_history(cx);
                cx.emit(BrowserTabEvent::StateChanged);
                self.watch_for_stall(cx);
            }
            RawEvent::Load(PageLoadEvent::Finished, url) => {
                self.state.loading = false;
                self.state.stalled = false;
                self.load_started = None;
                if !url.is_empty() {
                    self.state.url = url.clone();
                }
                self.refresh_history(cx);
                if let Some(y) = self.restore_scroll.take() {
                    self.with_raw(cx, |raw| {
                        let _ = raw.evaluate_script(&scripts::restore_scroll_script(y));
                    });
                }
                cx.emit(BrowserTabEvent::Navigated {
                    url: self.state.url.clone(),
                });
                cx.emit(BrowserTabEvent::LoadFinished {
                    url: self.state.url.clone(),
                    title: self.state.title.clone(),
                });
                cx.emit(BrowserTabEvent::StateChanged);
            }
            RawEvent::Title(title) => {
                let title = title.trim().to_owned();
                if title != self.state.title {
                    self.state.title = title;
                    cx.emit(BrowserTabEvent::StateChanged);
                }
            }
            RawEvent::NewWindow(url) => cx.emit(BrowserTabEvent::OpenInNewTab {
                url,
                background: false,
            }),
            RawEvent::External(url) => cx.emit(BrowserTabEvent::ExternalScheme { url }),
            RawEvent::DownloadStarted(url, path) => {
                cx.emit(BrowserTabEvent::DownloadStarted { url, path });
            }
            RawEvent::DownloadFinished(url, path, success) => {
                cx.emit(BrowserTabEvent::DownloadFinished { url, path, success });
            }
            RawEvent::Ipc(body) => {
                let Some(message) =
                    parse_message(&body, &self.engine.token, &self.engine.forwarded_keys)
                else {
                    return;
                };
                self.handle_page_message(message, cx);
            }
        }
    }

    fn handle_page_message(&mut self, message: PageMessage, cx: &mut Context<Self>) {
        match message {
            PageMessage::OpenLink { url, background } => {
                cx.emit(BrowserTabEvent::OpenInNewTab { url, background });
            }
            PageMessage::Selection { text, rect } => {
                self.state.selection = (!text.is_empty()).then_some(Selection { text, rect });
                cx.emit(BrowserTabEvent::SelectionChanged);
            }
            PageMessage::Meta {
                favicon,
                theme_color,
            } => {
                if favicon.is_some() {
                    self.state.favicon = favicon;
                }
                self.state.theme_color = theme_color;
                cx.emit(BrowserTabEvent::StateChanged);
            }
            PageMessage::Scroll { y } => cx.emit(BrowserTabEvent::Scrolled { y }),
            PageMessage::UrlChanged { url, title } => {
                if url != self.state.url {
                    self.state.url = url.clone();
                    if !title.is_empty() {
                        self.state.title = title;
                    }
                    self.refresh_history(cx);
                    cx.emit(BrowserTabEvent::Navigated { url });
                    cx.emit(BrowserTabEvent::StateChanged);
                }
            }
            PageMessage::Key { keystroke } => cx.emit(BrowserTabEvent::Shortcut { keystroke }),
        }
    }

    fn watch_for_stall(&mut self, cx: &mut Context<Self>) {
        let started = self.load_started;
        cx.spawn(async move |this, cx| {
            cx.background_executor().timer(STALLED_LOAD).await;
            let _ = this.update(cx, |tab, cx| {
                if tab.state.loading && tab.load_started == started {
                    tab.state.loading = false;
                    tab.state.stalled = true;
                    cx.emit(BrowserTabEvent::StateChanged);
                }
            });
        })
        .detach();
    }

    // ----- Commands -------------------------------------------------------

    /// Shows or hides the tab. Showing a sleeping tab wakes it.
    pub fn set_active(&mut self, active: bool, window: &mut Window, cx: &mut Context<Self>) {
        self.active = active;
        if active {
            self.last_active = Instant::now();
            self.create_webview(window, cx);
        }
        if let Some(webview) = &self.webview {
            webview.update(cx, |view, _| {
                if active {
                    view.show();
                } else {
                    view.hide();
                }
            });
        }
    }

    /// Hides the webview without changing which tab is active, e.g. while a
    /// full-window GPUI page covers the viewport.
    pub fn set_native_visible(&mut self, visible: bool, cx: &mut Context<Self>) {
        if let Some(webview) = &self.webview {
            webview.update(cx, |view, _| {
                if visible && self.active {
                    view.show();
                } else {
                    view.hide();
                }
            });
        }
    }

    /// Loads `url` in this tab.
    pub fn navigate(&mut self, url: &str, window: &mut Window, cx: &mut Context<Self>) {
        self.restore_scroll = None;
        if is_internal_url(url) {
            self.sleep(cx);
            self.state = PageState {
                url: url.to_owned(),
                zoom: self.state.zoom,
                ..PageState::default()
            };
            cx.emit(BrowserTabEvent::StateChanged);
            return;
        }
        self.state.url = url.to_owned();
        self.state.title.clear();
        self.state.favicon = None;
        match &self.webview {
            Some(webview) => {
                webview.update(cx, |view, _| view.load_url(url));
                self.state.loading = true;
                self.state.stalled = false;
                self.load_started = Some(Instant::now());
                self.watch_for_stall(cx);
            }
            None => self.create_webview(window, cx),
        }
        cx.emit(BrowserTabEvent::StateChanged);
    }

    /// Goes back in history.
    pub fn go_back(&mut self, cx: &mut Context<Self>) {
        self.with_raw(cx, native::go_back);
    }

    /// Goes forward in history.
    pub fn go_forward(&mut self, cx: &mut Context<Self>) {
        self.with_raw(cx, native::go_forward);
    }

    /// Reloads the page (waking the tab if needed).
    pub fn reload(&mut self, window: &mut Window, cx: &mut Context<Self>) {
        match &self.webview {
            Some(webview) => {
                let _ = webview.read(cx).raw().reload();
                self.state.stalled = false;
            }
            None => self.create_webview(window, cx),
        }
    }

    /// Stops loading.
    pub fn stop(&mut self, cx: &mut Context<Self>) {
        self.with_raw(cx, native::stop);
        self.state.loading = false;
        cx.emit(BrowserTabEvent::StateChanged);
    }

    /// Gives keyboard focus to the page.
    pub fn focus_page(&self, cx: &App) {
        self.with_raw(cx, |raw| {
            let _ = raw.focus();
        });
    }

    /// Takes keyboard focus away from the page, back to Curio's UI.
    pub fn blur_page(&self, cx: &App) {
        self.with_raw(cx, |raw| {
            let _ = raw.focus_parent();
        });
    }

    /// Sets the page zoom (1.0 = 100%).
    pub fn set_zoom(&mut self, zoom: f64, cx: &mut Context<Self>) {
        let zoom = zoom.clamp(0.3, 3.0);
        self.state.zoom = zoom;
        if let Some(webview) = &self.webview {
            let _ = webview.read(cx).set_zoom(zoom);
        }
        cx.emit(BrowserTabEvent::StateChanged);
    }

    /// Opens the Web Inspector, when the engine allows it.
    pub fn open_devtools(&self, cx: &App) {
        self.with_raw(cx, wry::WebView::open_devtools);
    }

    /// Prints the page.
    pub fn print(&self, cx: &App) {
        self.with_raw(cx, |raw| {
            let _ = raw.print();
        });
    }

    /// Puts the tab to sleep, releasing its webview and engine memory. The
    /// URL, title and scroll position are kept; the page reloads when shown.
    pub fn sleep(&mut self, cx: &mut Context<Self>) {
        if self.webview.take().is_some() {
            self._events = None;
            self.state.loading = false;
            self.state.selection = None;
            cx.emit(BrowserTabEvent::StateChanged);
        }
    }

    /// Remembers a scroll offset to restore on the next load.
    pub fn set_restore_scroll(&mut self, y: f64) {
        self.restore_scroll = (y > 0.0).then_some(y);
    }

    /// Runs a script and returns its JSON-encoded result.
    fn evaluate(&self, script: &str, cx: &App) -> Task<anyhow::Result<String>> {
        let (tx, rx) = async_channel::bounded::<String>(1);
        let started = self.with_raw(cx, |raw| {
            raw.evaluate_script_with_callback(script, move |result| {
                let _ = tx.try_send(result);
            })
        });
        let executor = cx.background_executor().clone();
        match started {
            None => Task::ready(Err(anyhow::anyhow!("the tab is not loaded"))),
            Some(Err(error)) => Task::ready(Err(anyhow::anyhow!("script failed: {error}"))),
            Some(Ok(())) => cx.foreground_executor().spawn(async move {
                let timeout = executor.timer(Duration::from_secs(10));
                let result = futures_lite_select(rx.recv(), timeout).await;
                match result {
                    Some(Ok(value)) => Ok(value),
                    Some(Err(_)) | None => Err(anyhow::anyhow!("the page did not respond")),
                }
            }),
        }
    }

    /// Extracts the page's readable content for the AI assistant. Returns the
    /// JSON produced by [`scripts::EXTRACT_CONTENT`].
    pub fn extract_content(&self, cx: &App) -> Task<anyhow::Result<String>> {
        let task = self.evaluate(scripts::EXTRACT_CONTENT, cx);
        cx.background_executor().spawn(async move {
            let raw = task.await?;
            decode_script_string(&raw)
        })
    }

    /// Finds `query` in the page, moving to the next (or previous) match.
    pub fn find(&self, query: &str, forward: bool, cx: &App) -> Task<FindResult> {
        let task = self.evaluate(&scripts::find_script(query, forward, false), cx);
        cx.background_executor().spawn(async move {
            task.await
                .ok()
                .and_then(|raw| decode_script_string(&raw).ok())
                .and_then(|json| serde_json::from_str::<serde_json::Value>(&json).ok())
                .map(|v| FindResult {
                    matches: v["matches"].as_u64().and_then(|n| u32::try_from(n).ok()).unwrap_or(0),
                    active: v["active"].as_u64().and_then(|n| u32::try_from(n).ok()).unwrap_or(0),
                })
                .unwrap_or_default()
        })
    }

    /// Removes find highlights.
    pub fn clear_find(&self, cx: &App) {
        self.with_raw(cx, |raw| {
            let _ = raw.evaluate_script(scripts::CLEAR_FIND);
        });
    }
}

/// Engines return script results JSON-encoded; a script that returns a
/// string therefore yields a JSON string literal.
fn decode_script_string(raw: &str) -> anyhow::Result<String> {
    match serde_json::from_str::<serde_json::Value>(raw) {
        Ok(serde_json::Value::String(inner)) => Ok(inner),
        Ok(other) => Ok(other.to_string()),
        Err(_) => Ok(raw.to_owned()),
    }
}

/// Awaits `value` or `timeout`, whichever completes first.
async fn futures_lite_select<T>(
    value: impl std::future::Future<Output = T>,
    timeout: impl std::future::Future,
) -> Option<T> {
    use std::pin::pin;
    use std::task::Poll;
    let mut value = pin!(value);
    let mut timeout = pin!(timeout);
    std::future::poll_fn(|cx| {
        if let Poll::Ready(v) = value.as_mut().poll(cx) {
            return Poll::Ready(Some(v));
        }
        if timeout.as_mut().poll(cx).is_ready() {
            return Poll::Ready(None);
        }
        Poll::Pending
    })
    .await
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn decodes_json_string_results() {
        assert_eq!(decode_script_string("\"{\\\"a\\\":1}\"").expect("ok"), "{\"a\":1}");
        assert_eq!(decode_script_string("{\"a\":1}").expect("ok"), "{\"a\":1}");
    }
}

//! Curio's web engine layer.
//!
//! Curio renders web content with the system WebKit (`WKWebView`) on macOS,
//! embedded as a native child view of the GPUI window through
//! [`gpui_webview`] and wry. The webview is hosted in a GPUI Fast window
//! composition surface, so Curio's GPUI overlays (menus, command bar,
//! dialogs) draw above the page. Only page content is rendered by the
//! engine; every piece of Curio's own interface is GPUI.
//!
//! - [`tab::BrowserTab`]: one tab's webview lifecycle and live page state.
//! - [`engine::EngineConfig`]: shared webview configuration.
//! - [`scripts`]: the page bridge, content extraction and find-in-page.
//! - [`ipc`]: validation of messages from pages.

pub mod engine;
pub mod ipc;
mod native;
pub mod scripts;
pub mod tab;

pub use engine::{ENGINE_NAME, EngineConfig, is_engine_navigable};
pub use native::HistoryState;
pub use tab::{BrowserTab, BrowserTabEvent, FindResult, PageState, Selection};

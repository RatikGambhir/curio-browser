//! Engine calls that wry does not expose: back/forward state, native history
//! navigation and stopping a load.
//!
//! On macOS these go straight to `WKWebView`. On Linux (used only to develop
//! and test Curio) they go to WebKitGTK.

/// Back/forward availability.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub struct HistoryState {
    pub can_go_back: bool,
    pub can_go_forward: bool,
}

#[cfg(target_os = "macos")]
mod imp {
    use super::HistoryState;
    use wry::WebViewExtMacOS as _;

    pub fn history_state(webview: &wry::WebView) -> HistoryState {
        let view = webview.webview();
        // SAFETY: `view` is a live WKWebView retained by wry; these are plain
        // property reads and every caller runs on the main (UI) thread.
        unsafe {
            HistoryState {
                can_go_back: view.canGoBack(),
                can_go_forward: view.canGoForward(),
            }
        }
    }

    pub fn go_back(webview: &wry::WebView) {
        let view = webview.webview();
        // SAFETY: as above; `goBack` returns an optional navigation handle we
        // do not need to keep.
        let _ = unsafe { view.goBack() };
    }

    pub fn go_forward(webview: &wry::WebView) {
        let view = webview.webview();
        // SAFETY: as above.
        let _ = unsafe { view.goForward() };
    }

    pub fn stop(webview: &wry::WebView) {
        let view = webview.webview();
        // SAFETY: as above.
        unsafe { view.stopLoading() };
    }

    pub fn is_secure(webview: &wry::WebView) -> bool {
        let view = webview.webview();
        // SAFETY: as above.
        unsafe { view.hasOnlySecureContent() }
    }
}

#[cfg(target_os = "linux")]
mod imp {
    use super::HistoryState;
    use webkit2gtk::WebViewExt as _;
    use wry::WebViewExtUnix as _;

    pub fn history_state(webview: &wry::WebView) -> HistoryState {
        let view = webview.webview();
        HistoryState {
            can_go_back: view.can_go_back(),
            can_go_forward: view.can_go_forward(),
        }
    }

    pub fn go_back(webview: &wry::WebView) {
        webview.webview().go_back();
    }

    pub fn go_forward(webview: &wry::WebView) {
        webview.webview().go_forward();
    }

    pub fn stop(webview: &wry::WebView) {
        webview.webview().stop_loading();
    }

    pub fn is_secure(webview: &wry::WebView) -> bool {
        webview.url().is_ok_and(|url| url.starts_with("https:"))
    }
}

#[cfg(not(any(target_os = "macos", target_os = "linux")))]
mod imp {
    use super::HistoryState;

    pub fn history_state(_: &wry::WebView) -> HistoryState {
        HistoryState {
            can_go_back: true,
            can_go_forward: true,
        }
    }

    pub fn go_back(webview: &wry::WebView) {
        let _ = webview.evaluate_script("history.back()");
    }

    pub fn go_forward(webview: &wry::WebView) {
        let _ = webview.evaluate_script("history.forward()");
    }

    pub fn stop(webview: &wry::WebView) {
        let _ = webview.evaluate_script("window.stop()");
    }

    pub fn is_secure(webview: &wry::WebView) -> bool {
        webview.url().is_ok_and(|url| url.starts_with("https:"))
    }
}

pub use imp::{go_back, go_forward, history_state, is_secure, stop};

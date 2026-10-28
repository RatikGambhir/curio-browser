//! Engine-wide configuration shared by every tab.

use std::path::{Path, PathBuf};

use crate::scripts;

/// The engine selected for this build. Curio embeds the system WebKit
/// (`WKWebView`) on macOS through wry.
pub const ENGINE_NAME: &str = if cfg!(target_os = "macos") {
    "WebKit (WKWebView)"
} else if cfg!(target_os = "linux") {
    "WebKitGTK"
} else {
    "System WebView"
};

/// Safari-compatible user agent. A bare `WKWebView` omits the `Version/…
/// Safari/…` tokens, which makes many sites serve degraded pages.
#[cfg(target_os = "macos")]
const USER_AGENT: Option<&str> = Some(concat!(
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 ",
    "(KHTML, like Gecko) Version/18.6 Safari/605.1.15 Curio/",
    env!("CARGO_PKG_VERSION")
));
#[cfg(not(target_os = "macos"))]
const USER_AGENT: Option<&str> = None;

/// Configuration applied to every webview.
#[derive(Debug, Clone)]
pub struct EngineConfig {
    /// Random per-session token that authenticates bridge messages.
    pub token: String,
    /// Keystrokes the page forwards to Curio when it has focus.
    pub forwarded_keys: Vec<String>,
    /// Custom download folder, or `None` for the system Downloads folder.
    pub download_dir: Option<PathBuf>,
    /// Allow the Web Inspector.
    pub devtools: bool,
    bridge: String,
}

impl EngineConfig {
    /// Creates a configuration with a fresh session token.
    #[must_use]
    pub fn new(forwarded_keys: Vec<String>, download_dir: Option<PathBuf>) -> Self {
        let token = uuid::Uuid::new_v4().simple().to_string();
        let bridge = scripts::bridge_script(&token, &forwarded_keys);
        Self {
            token,
            forwarded_keys,
            download_dir,
            devtools: true,
            bridge,
        }
    }

    /// A webview builder configured for a tab that starts at `url`.
    pub(crate) fn builder(&self, url: &str) -> wry::WebViewBuilder<'static> {
        let mut builder = wry::WebViewBuilder::new()
            .with_url(url)
            .with_initialization_script_for_main_only(self.bridge.clone(), true)
            .with_back_forward_navigation_gestures(true)
            .with_accept_first_mouse(true)
            .with_hotkeys_zoom(true)
            .with_clipboard(true)
            .with_autoplay(true)
            .with_devtools(self.devtools)
            .with_focused(false);
        if let Some(agent) = USER_AGENT {
            builder = builder.with_user_agent(agent);
        }
        if let Some(proxy) = dev_proxy() {
            builder = builder.with_proxy_config(proxy);
        }
        builder
    }
}

/// `CURIO_PROXY=host:port` routes page traffic through an HTTP proxy. Used
/// for testing in restricted networks.
fn dev_proxy() -> Option<wry::ProxyConfig> {
    let value = std::env::var("CURIO_PROXY").ok()?;
    let value = value.trim_start_matches("http://");
    let (host, port) = value.trim_end_matches('/').rsplit_once(':')?;
    Some(wry::ProxyConfig::Http(wry::ProxyEndpoint {
        host: host.to_owned(),
        port: port.to_owned(),
    }))
}

/// Whether the engine should load `url` itself. Other schemes (mailto:,
/// tel:, app links) are handed back to Curio, which asks before opening an
/// external application.
#[must_use]
pub fn is_engine_navigable(url: &str) -> bool {
    let scheme = url
        .split_once(':')
        .map_or("", |(s, _)| s)
        .to_ascii_lowercase();
    matches!(
        scheme.as_str(),
        "http" | "https" | "about" | "data" | "blob" | "file"
    ) || url.is_empty()
}

/// Returns `path`, or `name (n).ext` when a file already exists there.
#[must_use]
pub fn unique_path(path: &Path) -> PathBuf {
    if !path.exists() {
        return path.to_path_buf();
    }
    let stem = path.file_stem().map_or_else(
        || "download".to_owned(),
        |s| s.to_string_lossy().into_owned(),
    );
    let ext = path
        .extension()
        .map(|e| format!(".{}", e.to_string_lossy()))
        .unwrap_or_default();
    (1..10_000)
        .map(|n| path.with_file_name(format!("{stem} ({n}){ext}")))
        .find(|candidate| !candidate.exists())
        .unwrap_or_else(|| path.to_path_buf())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn navigable_schemes() {
        assert!(is_engine_navigable("https://a.test"));
        assert!(is_engine_navigable("about:blank"));
        assert!(!is_engine_navigable("mailto:a@b.test"));
        assert!(!is_engine_navigable("zoommtg://join"));
    }

    #[test]
    fn unique_path_appends_counter() {
        let dir = std::env::temp_dir().join(format!("curio-test-{}", uuid::Uuid::new_v4()));
        std::fs::create_dir_all(&dir).expect("dir");
        let file = dir.join("report.pdf");
        assert_eq!(unique_path(&file), file);
        std::fs::write(&file, b"x").expect("write");
        assert_eq!(unique_path(&file), dir.join("report (1).pdf"));
        let _ = std::fs::remove_dir_all(&dir);
    }
}

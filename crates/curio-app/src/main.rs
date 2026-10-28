//! Curio: a browser with spaces, vertical tabs and a built-in assistant.
//!
//! Startup: open the local database, restore the previous session, install
//! the theme, key bindings and menus, then open the browser window.

use anyhow::{Context as _, Result};
use curio_ai::SecretStore;
use curio_spaces::Workspace;
use curio_storage::{Storage, paths};
use curio_ui::assets::CurioAssets;
use curio_ui::{BrowserWindow, Services, actions};
use gpui_kit::{
    AppContext as _, Bounds, TitlebarOptions, WindowBounds, WindowOptions, point, px, size,
};

fn init_logging() {
    let filter = tracing_subscriber::EnvFilter::try_from_default_env()
        .unwrap_or_else(|_| tracing_subscriber::EnvFilter::new("info,wgpu=warn,naga=warn"));
    tracing_subscriber::fmt()
        .with_env_filter(filter)
        .with_target(false)
        .init();
}

fn main() -> Result<()> {
    init_logging();

    let storage = Storage::open_default().context("opening Curio's database")?;
    let settings = storage
        .with(|db| db.load_settings())
        .context("loading settings")?;
    let workspace = if settings.browsing.restore_session {
        storage
            .with(|db| db.load_workspace())
            .unwrap_or_else(|error| {
                tracing::error!(%error, "could not restore the previous session");
                None
            })
            .unwrap_or_else(Workspace::first_run)
    } else {
        Workspace::first_run()
    };
    let secrets = SecretStore::new(paths::data_dir()?);
    tracing::info!(
        engine = curio_browser_engine_name(),
        spaces = workspace.spaces().len(),
        "starting Curio"
    );

    // WebKitGTK only embeds into X11 windows; Curio's Linux build exists for
    // development and testing only.
    #[cfg(target_os = "linux")]
    let app = gpui_kit::platform::linux(gpui_kit::WindowingModes::X11);
    #[cfg(not(target_os = "linux"))]
    let app = gpui_kit::application();

    // GPUI's image loader fetches remote favicons through this client.
    let app = match reqwest_client::ReqwestClient::user_agent(concat!(
        "Curio/",
        env!("CARGO_PKG_VERSION")
    )) {
        Ok(client) => app.with_http_client(std::sync::Arc::new(client)),
        Err(error) => {
            tracing::warn!(%error, "no HTTP client; site icons will not load");
            app
        }
    };

    // URLs to open: from the command line now, and from macOS later (links
    // clicked in other apps when Curio is the default browser).
    let (url_tx, url_rx) = async_channel::unbounded::<String>();
    for arg in std::env::args().skip(1) {
        if arg.contains("://") || arg.starts_with("file:") {
            let _ = url_tx.try_send(arg);
        }
    }
    app.on_open_urls(move |urls| {
        for url in urls {
            let _ = url_tx.try_send(url);
        }
    });

    app.with_assets(CurioAssets).run(move |cx| {
        gpui_kit::init(cx);
        curio_ui::init(Services { storage, secrets }, settings, cx);
        cx.set_menus(actions::menus());
        cx.on_action(|_: &actions::Quit, cx| cx.quit());

        let bounds = Bounds::centered(None, size(px(1360.), px(860.)), cx);
        let options = WindowOptions {
            window_bounds: Some(WindowBounds::Windowed(bounds)),
            titlebar: Some(TitlebarOptions {
                title: Some("Curio".into()),
                appears_transparent: true,
                traffic_light_position: Some(point(px(14.), px(15.))),
            }),
            window_min_size: Some(size(px(720.), px(480.))),
            app_id: Some(curio_core::BUNDLE_ID.to_owned()),
            ..WindowOptions::default()
        };
        let opened = gpui_kit::open_window(options, cx, |window, cx| {
            cx.new(|cx| BrowserWindow::new(workspace, window, cx))
        });
        match opened {
            Ok((handle, view)) => {
                cx.activate(true);
                cx.spawn(async move |cx| {
                    while let Ok(url) = url_rx.recv().await {
                        let view = view.clone();
                        let _ = handle.update(cx, |_, window, cx| {
                            view.update(cx, |browser, cx| {
                                browser.open_external_url(&url, window, cx)
                            });
                        });
                    }
                })
                .detach();
            }
            Err(error) => {
                tracing::error!(%error, "could not open the browser window");
                cx.quit();
            }
        }
        cx.on_window_closed(|cx, _| {
            if cx.windows().is_empty() {
                cx.quit();
            }
        })
        .detach();
    });
    Ok(())
}

fn curio_browser_engine_name() -> &'static str {
    if cfg!(target_os = "macos") {
        "WebKit (WKWebView)"
    } else {
        "WebKitGTK (development)"
    }
}

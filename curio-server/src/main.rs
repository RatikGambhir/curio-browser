//! Curio's backend service.
//!
//! Listens on `CURIO_SERVER_ADDR` (default `127.0.0.1:8080`) and shuts down
//! gracefully on Ctrl-C or SIGTERM, letting in-flight requests finish.

mod app;

use std::net::SocketAddr;

use anyhow::{Context as _, Result};

const DEFAULT_ADDR: &str = "127.0.0.1:8080";

fn init_logging() {
    let filter = tracing_subscriber::EnvFilter::try_from_default_env()
        .unwrap_or_else(|_| tracing_subscriber::EnvFilter::new("info,tower_http=debug"));
    tracing_subscriber::fmt()
        .with_env_filter(filter)
        .with_target(false)
        .init();
}

#[tokio::main]
async fn main() -> Result<()> {
    init_logging();

    let addr: SocketAddr = std::env::var("CURIO_SERVER_ADDR")
        .unwrap_or_else(|_| DEFAULT_ADDR.to_owned())
        .parse()
        .context("CURIO_SERVER_ADDR must be an address like 127.0.0.1:8080")?;
    let listener = tokio::net::TcpListener::bind(addr)
        .await
        .with_context(|| format!("binding {addr}"))?;
    tracing::info!(%addr, "curio-server listening");

    axum::serve(listener, app::router())
        .with_graceful_shutdown(shutdown_signal())
        .await
        .context("serving HTTP")?;
    tracing::info!("curio-server stopped");
    Ok(())
}

/// Resolves on Ctrl-C, or on SIGTERM (what container schedulers send).
async fn shutdown_signal() {
    let ctrl_c = async {
        if let Err(error) = tokio::signal::ctrl_c().await {
            tracing::error!(%error, "could not listen for Ctrl-C");
            std::future::pending::<()>().await;
        }
    };

    #[cfg(unix)]
    let terminate = async {
        use tokio::signal::unix::{SignalKind, signal};
        match signal(SignalKind::terminate()) {
            Ok(mut sigterm) => {
                sigterm.recv().await;
            }
            Err(error) => {
                tracing::error!(%error, "could not listen for SIGTERM");
                std::future::pending::<()>().await;
            }
        }
    };
    #[cfg(not(unix))]
    let terminate = std::future::pending::<()>();

    tokio::select! {
        () = ctrl_c => {}
        () = terminate => {}
    }
    tracing::info!("shutting down");
}

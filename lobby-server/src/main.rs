//! Warblade Remake lobby server: identity, lobby list, global chat, talents,
//! NAT rendezvous, self-reported match records, and an owner admin page.
//! Sized for the smallest droplet; it never relays game traffic.

mod accounts;
mod admin;
mod chat;
mod config;
mod db;
mod lobbies;
mod matches;
mod protocol;
mod rendezvous;
mod session;
mod state;
mod stats;
mod sweeper;
mod talents;
mod ws;

use std::net::SocketAddr;
use std::sync::Arc;

use axum::routing::get;
use axum::Router;
use tokio::net::{TcpListener, UdpSocket};
use tracing::info;
use tracing_subscriber::EnvFilter;

use crate::config::Config;
use crate::db::Db;
use crate::state::AppState;
use crate::talents::TalentCatalog;

#[tokio::main(flavor = "multi_thread", worker_threads = 2)]
async fn main() -> anyhow::Result<()> {
    let config = Config::from_env()?;
    tracing_subscriber::fmt()
        .with_env_filter(EnvFilter::try_new(&config.log).unwrap_or_else(|_| EnvFilter::new("info")))
        .with_ansi(false)
        .compact()
        .init();
    let db = Db::open(&config.db_path)?;
    let talents = TalentCatalog::load(&config.talents_path)?;
    info!(
        version = env!("CARGO_PKG_VERSION"),
        db = %config.db_path,
        talents = %config.talents_path,
        talents_sha256 = %talents.sha256,
        talent_nodes = talents.nodes.len(),
        "warblade lobby starting"
    );
    let now = db::now_unix();
    let recovered = db.maintenance(|conn| matches::db_abandon_open_older_than(conn, 0, now))?;
    if recovered > 0 {
        info!(recovered, "abandoned matches left open by a previous run");
    }
    let state = Arc::new(AppState::new(config.clone(), db, talents));

    let app = Router::new()
        .route("/ws", get(ws::ws_handler))
        .route("/healthz", get(|| async { "ok" }))
        .route("/", get(|| async { "warblade lobby server" }))
        .with_state(state.clone());
    let listener = TcpListener::bind(config.ws_bind).await?;
    info!(bind = %config.ws_bind, "websocket listener ready");

    let udp = UdpSocket::bind(config.udp_bind).await?;
    info!(bind = %config.udp_bind, "udp rendezvous ready");
    let rendezvous = tokio::spawn(rendezvous::run(state.clone(), udp));
    let sweeper = tokio::spawn(sweeper::run(state.clone()));
    let admin = match config.admin_token {
        Some(_) => {
            let admin_listener = TcpListener::bind(config.admin_bind).await?;
            info!(bind = %config.admin_bind, "admin listener ready (loopback; use an ssh tunnel)");
            let admin_app = admin::router(state.clone());
            Some(tokio::spawn(async move {
                let _ = axum::serve(admin_listener, admin_app).await;
            }))
        }
        None => {
            info!("WB_ADMIN_TOKEN is not set; the admin listener stays off");
            None
        }
    };

    let (shutdown_tx, shutdown_rx) = tokio::sync::watch::channel(false);
    tokio::spawn(async move {
        wait_for_signal().await;
        let _ = shutdown_tx.send(true);
    });
    let graceful_state = state.clone();
    let mut graceful_rx = shutdown_rx.clone();
    let graceful = async move {
        let _ = graceful_rx.wait_for(|stop| *stop).await;
        info!("shutdown requested; closing sessions");
        graceful_state.close_all_sessions();
    };
    axum::serve(listener, app.into_make_service_with_connect_info::<SocketAddr>())
        .with_graceful_shutdown(graceful)
        .await?;
    sweeper.abort();
    rendezvous.abort();
    if let Some(admin) = admin {
        admin.abort();
    }
    state.db.maintenance(|conn| conn.execute_batch("PRAGMA wal_checkpoint(TRUNCATE);"))?;
    info!("warblade lobby stopped");
    Ok(())
}

async fn wait_for_signal() {
    let ctrl_c = async {
        let _ = tokio::signal::ctrl_c().await;
    };
    #[cfg(unix)]
    let terminate = async {
        match tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate()) {
            Ok(mut signal) => {
                signal.recv().await;
            }
            Err(_) => std::future::pending::<()>().await,
        }
    };
    #[cfg(not(unix))]
    let terminate = std::future::pending::<()>();
    tokio::select! {
        _ = ctrl_c => {},
        _ = terminate => {},
    }
}

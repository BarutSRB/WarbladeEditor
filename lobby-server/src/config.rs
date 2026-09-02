//! Process configuration from environment variables (systemd's
//! EnvironmentFile in production, `make` exports in development).

use std::env;
use std::net::SocketAddr;

use anyhow::{anyhow, Context};

#[derive(Clone, Debug)]
pub struct Config {
    pub ws_bind: SocketAddr,
    pub udp_bind: SocketAddr,
    pub admin_bind: SocketAddr,
    pub admin_token: Option<String>,
    pub db_path: String,
    pub talents_path: String,
    pub expected_content_hash: Option<String>,
    pub max_connections: usize,
    pub max_connections_per_ip: u32,
    pub max_lobbies: usize,
    pub log: String,
}

fn var(name: &str, default: &str) -> String {
    env::var(name).ok().filter(|v| !v.trim().is_empty()).unwrap_or_else(|| default.to_string())
}

fn addr(name: &str, default: &str) -> anyhow::Result<SocketAddr> {
    let raw = var(name, default);
    raw.parse::<SocketAddr>().with_context(|| format!("{name}={raw} is not host:port"))
}

fn number<T: std::str::FromStr>(name: &str, default: T) -> anyhow::Result<T> {
    match env::var(name) {
        Ok(raw) if !raw.trim().is_empty() => raw
            .trim()
            .parse::<T>()
            .map_err(|_| anyhow!("{name}={raw} is not a number")),
        _ => Ok(default),
    }
}

impl Config {
    pub fn from_env() -> anyhow::Result<Config> {
        let admin_token = env::var("WB_ADMIN_TOKEN").ok().filter(|v| !v.trim().is_empty());
        if let Some(token) = &admin_token {
            if token.len() < 16 {
                return Err(anyhow!("WB_ADMIN_TOKEN must be at least 16 characters"));
            }
        }
        let expected_content_hash = env::var("WB_EXPECTED_CONTENT_HASH")
            .ok()
            .map(|v| v.trim().to_lowercase())
            .filter(|v| !v.is_empty());
        if let Some(hash) = &expected_content_hash {
            if !crate::protocol::is_hex(hash, 64) {
                return Err(anyhow!("WB_EXPECTED_CONTENT_HASH must be 64 hex characters"));
            }
        }
        Ok(Config {
            ws_bind: addr("WB_WS_BIND", "0.0.0.0:7400")?,
            udp_bind: addr("WB_UDP_BIND", "0.0.0.0:7401")?,
            admin_bind: addr("WB_ADMIN_BIND", "127.0.0.1:7402")?,
            admin_token,
            db_path: var("WB_DB_PATH", "./lobby.db"),
            talents_path: var("WB_TALENTS_PATH", "../content/talents.json"),
            expected_content_hash,
            max_connections: number("WB_MAX_CONNECTIONS", 500usize)?,
            max_connections_per_ip: number("WB_MAX_CONNECTIONS_PER_IP", 8u32)?,
            max_lobbies: number("WB_MAX_LOBBIES", 100usize)?,
            log: var("WB_LOG", "info"),
        })
    }
}

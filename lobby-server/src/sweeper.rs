//! Periodic housekeeping: handshake deadlines, stale join offers, expired
//! rendezvous entries and unreachable hosts, chat retention, and open
//! matches nobody ever finished.

use std::sync::Arc;
use std::time::{Duration, Instant};

use serde_json::json;
use tracing::{info, warn};

use crate::chat;
use crate::db::now_unix;
use crate::matches;
use crate::protocol::{self, limits};
use crate::state::AppState;

const TICK: Duration = Duration::from_secs(5);
const HOURLY_TICKS: u64 = 720;

pub async fn run(state: Arc<AppState>) {
    let mut ticks: u64 = 0;
    loop {
        tokio::time::sleep(TICK).await;
        ticks += 1;
        let now = Instant::now();
        let mut abandoned = Vec::new();
        {
            let mut hub = state.hub();
            let expired: Vec<(u64, &'static str)> = hub
                .sessions
                .values()
                .filter_map(|session| {
                    let age = now.duration_since(session.connected_at).as_secs();
                    if !session.hello_done && age > limits::HELLO_TIMEOUT_SEC {
                        Some((session.id, "hello timeout"))
                    } else if session.key_hash.is_none() && age > limits::AUTH_TIMEOUT_SEC {
                        Some((session.id, "auth timeout"))
                    } else {
                        None
                    }
                })
                .collect();
            for (sid, reason) in expired {
                hub.close(sid, limits::CLOSE_HANDSHAKE_TIMEOUT, reason);
            }
            let stale_joins: Vec<u64> = hub
                .pending_joins
                .values()
                .filter(|join| now.duration_since(join.created).as_secs() > limits::JOIN_ANSWER_TIMEOUT_SEC)
                .map(|join| join.join_id)
                .collect();
            for join_id in stale_joins {
                if let Some(join) = hub.pending_joins.remove(&join_id) {
                    let text = protocol::push(
                        "lobby_join_rejected",
                        json!({"join_id": join_id, "lobby_id": join.lobby_id, "reason": "host_timeout"}),
                    );
                    hub.send(join.joiner, text);
                }
            }
            let expired_nonces: Vec<[u8; 16]> = hub
                .rendezvous
                .iter()
                .filter(|(_, entry)| now.duration_since(entry.last_seen).as_secs() > limits::RENDEZVOUS_EXPIRE_SEC)
                .map(|(nonce, _)| *nonce)
                .collect();
            for nonce in &expired_nonces {
                hub.rendezvous.remove(nonce);
            }
            let unreachable: Vec<String> = hub
                .lobbies
                .values()
                .filter(|lobby| {
                    lobby.host_public.is_some()
                        && hub
                            .session(lobby.host)
                            .and_then(|session| session.nonce)
                            .map(|nonce| !hub.rendezvous.contains_key(&nonce))
                            .unwrap_or(false)
                })
                .map(|lobby| lobby.id.clone())
                .collect();
            for lobby_id in unreachable {
                warn!(lobby = %lobby_id, "host keepalive expired; closing lobby");
                abandoned.extend(hub.close_lobby(&lobby_id, "host_unreachable"));
            }
        }
        if !abandoned.is_empty() {
            if let Err(error) = state.db.with(|conn| Ok(matches::db_abandon(conn, &abandoned)?)) {
                warn!("could not abandon matches: {}", error.message);
            }
        }
        if ticks % HOURLY_TICKS == 0 {
            let now_unix = now_unix();
            let result = state.db.maintenance(|conn| {
                let pruned = chat::db_prune(conn, limits::CHAT_RETENTION_ROWS)?;
                let abandoned = matches::db_abandon_open_older_than(conn, limits::OPEN_MATCH_ABANDON_SEC, now_unix)?;
                Ok((pruned, abandoned))
            });
            match result {
                Ok((pruned, abandoned)) => info!(pruned, abandoned, "hourly maintenance"),
                Err(error) => warn!("hourly maintenance failed: {error}"),
            }
        }
    }
}

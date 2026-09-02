//! The owner's overview: live counters from the hub plus a few totals from
//! the database.

use rusqlite::params;
use serde_json::{json, Value};

use crate::db::{now_unix, utc_day_start};
use crate::lobbies::LobbyState;
use crate::state::AppState;

pub fn overview(state: &AppState) -> Value {
    let now = now_unix();
    let day_start = utc_day_start(now);
    let (accounts_total, chat_today, matches_today, matches_total) = state
        .db
        .maintenance(|conn| {
            let accounts: i64 = conn.query_row("SELECT COUNT(*) FROM accounts", [], |row| row.get(0))?;
            let chat: i64 =
                conn.query_row("SELECT COUNT(*) FROM chat_messages WHERE sent_at >= ?1", params![day_start], |row| row.get(0))?;
            let matches_today: i64 =
                conn.query_row("SELECT COUNT(*) FROM matches WHERE started_at >= ?1", params![day_start], |row| row.get(0))?;
            let matches_total: i64 = conn.query_row("SELECT COUNT(*) FROM matches", [], |row| row.get(0))?;
            Ok((accounts, chat, matches_today, matches_total))
        })
        .unwrap_or((0, 0, 0, 0));
    let hub = state.hub();
    let mut open = 0;
    let mut full = 0;
    let mut in_match = 0;
    for lobby in hub.lobbies.values() {
        match lobby.state {
            LobbyState::Open => open += 1,
            LobbyState::Full => full += 1,
            LobbyState::InMatch => in_match += 1,
        }
    }
    json!({
        "server_time": now,
        "uptime_sec": state.started_at.elapsed().as_secs(),
        "version": env!("CARGO_PKG_VERSION"),
        "connections": {
            "current": hub.sessions.len(),
            "registered": hub.registered_count(),
            "total": hub.stats.connections_total,
        },
        "lobbies": {"open": open, "full": full, "in_match": in_match},
        "pending_joins": hub.pending_joins.len(),
        "rendezvous_entries": hub.rendezvous.len(),
        "chat": {"total_since_start": hub.stats.chat_total, "today": chat_today},
        "matches": {
            "started_since_start": hub.stats.matches_started,
            "ended_since_start": hub.stats.matches_ended,
            "today": matches_today,
            "total": matches_total,
        },
        "udp": {
            "received": hub.stats.udp_received,
            "echoed": hub.stats.udp_echoed,
            "dropped": hub.stats.udp_dropped,
        },
        "accounts_total": accounts_total,
    })
}

pub fn sessions(state: &AppState) -> Value {
    let hub = state.hub();
    let mut rows: Vec<Value> = hub
        .sessions
        .values()
        .map(|session| {
            json!({
                "session_id": session.id,
                "ip": session.ip.to_string(),
                "connected_for_sec": session.connected_at.elapsed().as_secs(),
                "idle_sec": session.last_seen.elapsed().as_secs(),
                "nickname": session.account.as_ref().map(|a| a.nickname.clone()),
                "account_id": session.account.as_ref().map(|a| a.id),
                "presence": session.presence.label(),
                "client_version": session.client_version,
                "platform": session.platform,
                "has_nonce": session.nonce.is_some(),
            })
        })
        .collect();
    rows.sort_by_key(|row| row["session_id"].as_u64().unwrap_or(0));
    Value::Array(rows)
}

pub fn lobbies(state: &AppState) -> Value {
    let now = std::time::Instant::now();
    let hub = state.hub();
    let mut rows: Vec<Value> = hub
        .lobbies
        .values()
        .map(|lobby| {
            let mut value = lobby.full_json(crate::lobbies::host_fresh(&hub, lobby, now));
            if let Value::Object(object) = &mut value {
                object.insert("host_session".into(), Value::from(lobby.host));
                object.insert("match_id".into(), lobby.match_id.map(Value::from).unwrap_or(Value::Null));
            }
            value
        })
        .collect();
    rows.sort_by_key(|row| std::cmp::Reverse(row["created_at"].as_i64().unwrap_or(0)));
    Value::Array(rows)
}

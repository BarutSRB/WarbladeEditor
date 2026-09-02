//! Identity: hello, device-key auth, nickname registration and renames.
//! An account is a random 32-byte device key the client generated; the
//! server stores only its SHA-256 and the nickname bound to it.

use rusqlite::{params, Connection, OptionalExtension};
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use tracing::info;

use crate::db::now_unix;
use crate::lobbies;
use crate::matches;
use crate::protocol::{
    self, field_i64, field_i64_opt, field_string, field_string_opt, is_hex, is_valid_nickname, limits, ApiError,
    ApiResult, ErrorCode, PROTOCOL_VERSION,
};
use crate::session::{AccountRef, SessionId};
use crate::state::AppState;
use crate::talents;

#[derive(Clone, Debug)]
pub struct Account {
    pub id: i64,
    pub nickname: String,
    pub disabled: bool,
}

pub fn key_hash_from_hex(key: &str) -> Result<Vec<u8>, ApiError> {
    if !is_hex(key, 64) {
        return Err(ApiError::schema("device_key must be 64 hex characters"));
    }
    let bytes = hex::decode(key).map_err(|_| ApiError::schema("device_key must be hex"))?;
    Ok(Sha256::digest(&bytes).to_vec())
}

pub fn db_find_by_key_hash(conn: &Connection, hash: &[u8]) -> rusqlite::Result<Option<Account>> {
    conn.query_row(
        "SELECT id, nickname, disabled FROM accounts WHERE device_key_hash = ?1",
        params![hash],
        |row| Ok(Account { id: row.get(0)?, nickname: row.get(1)?, disabled: row.get::<_, i64>(2)? != 0 }),
    )
    .optional()
}

pub fn db_find_by_id(conn: &Connection, id: i64) -> rusqlite::Result<Option<Account>> {
    conn.query_row(
        "SELECT id, nickname, disabled FROM accounts WHERE id = ?1",
        params![id],
        |row| Ok(Account { id: row.get(0)?, nickname: row.get(1)?, disabled: row.get::<_, i64>(2)? != 0 }),
    )
    .optional()
}

pub fn db_nickname_owner(conn: &Connection, nickname_lc: &str) -> rusqlite::Result<Option<i64>> {
    conn.query_row("SELECT id FROM accounts WHERE nickname_lc = ?1", params![nickname_lc], |row| row.get(0))
        .optional()
}

pub fn db_create(conn: &Connection, hash: &[u8], nickname: &str, now: i64, ip: &str) -> rusqlite::Result<Account> {
    conn.execute(
        "INSERT INTO accounts (nickname, nickname_lc, device_key_hash, created_at, last_login_at, last_ip) VALUES (?1, ?2, ?3, ?4, ?4, ?5)",
        params![nickname, nickname.to_lowercase(), hash, now, ip],
    )?;
    Ok(Account { id: conn.last_insert_rowid(), nickname: nickname.to_string(), disabled: false })
}

pub fn db_rename(conn: &Connection, id: i64, nickname: &str) -> rusqlite::Result<()> {
    conn.execute(
        "UPDATE accounts SET nickname = ?1, nickname_lc = ?2 WHERE id = ?3",
        params![nickname, nickname.to_lowercase(), id],
    )?;
    Ok(())
}

pub fn db_touch_login(conn: &Connection, id: i64, now: i64, ip: &str) -> rusqlite::Result<()> {
    conn.execute("UPDATE accounts SET last_login_at = ?1, last_ip = ?2 WHERE id = ?3", params![now, ip, id])?;
    Ok(())
}

pub fn db_set_disabled(conn: &Connection, id: i64, disabled: bool) -> rusqlite::Result<()> {
    conn.execute("UPDATE accounts SET disabled = ?1 WHERE id = ?2", params![disabled as i64, id])?;
    Ok(())
}

pub fn db_replace_key(conn: &Connection, id: i64, hash: &[u8]) -> rusqlite::Result<()> {
    conn.execute("UPDATE accounts SET device_key_hash = ?1 WHERE id = ?2", params![hash, id])?;
    Ok(())
}

pub fn account_json(account: &Account) -> Value {
    json!({"id": account.id, "nickname": account.nickname})
}

// ----------------------------------------------------------------- handlers

pub fn handle_hello(state: &AppState, sid: SessionId, payload: &Value) -> ApiResult {
    let protocol_version = field_i64(payload, "protocol")?;
    if protocol_version != PROTOCOL_VERSION as i64 {
        return Err(ApiError::new(
            ErrorCode::ProtocolMismatch,
            format!("this server speaks lobby protocol {PROTOCOL_VERSION}"),
        )
        .with("protocol", Value::from(PROTOCOL_VERSION)));
    }
    let content_hash = field_string_opt(payload, "content_hash", 64)?.unwrap_or_default().to_lowercase();
    if !content_hash.is_empty() && !is_hex(&content_hash, 64) {
        return Err(ApiError::schema("content_hash must be empty or 64 hex characters"));
    }
    if let Some(expected) = &state.config.expected_content_hash {
        if !content_hash.is_empty() && &content_hash != expected {
            return Err(ApiError::new(
                ErrorCode::ContentMismatch,
                "this client's game content differs from the server's pinned content",
            ));
        }
    }
    let client_version = field_string_opt(payload, "client_version", 32)?.unwrap_or_default();
    let platform = field_string_opt(payload, "platform", 16)?.unwrap_or_default();
    {
        let mut hub = state.hub();
        let session = hub.require_session_mut(sid)?;
        session.hello_done = true;
        session.content_hash = content_hash;
        session.client_version = client_version;
        session.platform = platform;
    }
    Ok(json!({
        "protocol": PROTOCOL_VERSION,
        "server_version": env!("CARGO_PKG_VERSION"),
        "server_time": now_unix(),
        "udp_port": state.config.udp_bind.port(),
        "talent_catalog_version": state.talents.version,
        "limits": {
            "chat_max_chars": limits::CHAT_MAX_CHARS,
            "lobby_name_max": limits::LOBBY_NAME_MAX,
            "ping_interval_sec": limits::PING_INTERVAL_SEC,
            "idle_timeout_sec": limits::IDLE_TIMEOUT_SEC,
            "rendezvous_keepalive_sec": limits::RENDEZVOUS_KEEPALIVE_SEC,
            "history_page": limits::HISTORY_PAGE,
        },
    }))
}

pub fn handle_ping(_state: &AppState, _sid: SessionId, payload: &Value) -> ApiResult {
    let client_time = field_i64_opt(payload, "client_time")?;
    Ok(json!({"server_time": now_unix(), "client_time": client_time}))
}

pub fn handle_auth(state: &AppState, sid: SessionId, payload: &Value) -> ApiResult {
    let key = field_string(payload, "device_key", 64)?;
    let hash = key_hash_from_hex(&key)?;
    let ip = {
        let mut hub = state.hub();
        let session = hub.require_session_mut(sid)?;
        if session.account.is_some() {
            return Err(ApiError::schema("this connection is already authenticated"));
        }
        session.key_hash = Some(hash.clone());
        session.ip.to_string()
    };
    let found = state.db.with(|conn| Ok(db_find_by_key_hash(conn, &hash)?))?;
    match found {
        Some(account) => {
            if account.disabled {
                return Err(ApiError::new(ErrorCode::AccountDisabled, "this account is disabled"));
            }
            let now = now_unix();
            state.db.with(|conn| Ok(db_touch_login(conn, account.id, now, &ip)?))?;
            let talents = bind_account(state, sid, &account)?;
            info!(session = sid, account = account.id, nickname = %account.nickname, "authenticated");
            Ok(json!({"registered": true, "account": account_json(&account), "talents": talents}))
        }
        None => Ok(json!({"registered": false})),
    }
}

pub fn handle_register(state: &AppState, sid: SessionId, payload: &Value) -> ApiResult {
    let nickname = field_string(payload, "nickname", limits::NICKNAME_MAX)?;
    if !is_valid_nickname(&nickname) {
        return Err(ApiError::new(ErrorCode::InvalidNickname, "nicknames are 3-16 letters, digits, or underscores"));
    }
    let (hash, ip) = {
        let hub = state.hub();
        let session = hub.require_session(sid)?;
        if session.account.is_some() {
            return Err(ApiError::schema("already registered; use set_nickname to rename"));
        }
        let hash = session
            .key_hash
            .clone()
            .ok_or_else(|| ApiError::new(ErrorCode::NotAuthenticated, "send auth before register"))?;
        (hash, session.ip.to_string())
    };
    let now = now_unix();
    let account = state.db.with(|conn| {
        if db_nickname_owner(conn, &nickname.to_lowercase())?.is_some() {
            return Err(ApiError::new(ErrorCode::NicknameTaken, "that nickname is taken"));
        }
        if db_find_by_key_hash(conn, &hash)?.is_some() {
            return Err(ApiError::schema("this device key is already registered"));
        }
        Ok(db_create(conn, &hash, &nickname, now, &ip)?)
    })?;
    let talents = bind_account(state, sid, &account)?;
    info!(session = sid, account = account.id, nickname = %account.nickname, "registered");
    Ok(json!({"account": account_json(&account), "talents": talents}))
}

pub fn handle_set_nickname(state: &AppState, sid: SessionId, payload: &Value) -> ApiResult {
    let nickname = field_string(payload, "nickname", limits::NICKNAME_MAX)?;
    if !is_valid_nickname(&nickname) {
        return Err(ApiError::new(ErrorCode::InvalidNickname, "nicknames are 3-16 letters, digits, or underscores"));
    }
    let account = state.hub().require_account(sid)?;
    state.db.with(|conn| {
        if let Some(owner) = db_nickname_owner(conn, &nickname.to_lowercase())? {
            if owner != account.id {
                return Err(ApiError::new(ErrorCode::NicknameTaken, "that nickname is taken"));
            }
        }
        Ok(db_rename(conn, account.id, &nickname)?)
    })?;
    {
        let mut hub = state.hub();
        if let Some(session) = hub.session_mut(sid) {
            if let Some(bound) = &mut session.account {
                bound.nickname = nickname.clone();
            }
        }
        for lobby in hub.lobbies.values_mut() {
            if lobby.host == sid {
                lobby.host_nickname = nickname.clone();
            }
            if let Some(joiner) = &mut lobby.joiner {
                if joiner.session == sid {
                    joiner.nickname = nickname.clone();
                }
            }
        }
        hub.broadcast_registered(&protocol::push("lobby_list_changed", json!({})));
    }
    let renamed = Account { id: account.id, nickname: nickname.clone(), disabled: false };
    let talents = state.db.with(|conn| talents::state_json(conn, &state.talents, account.id, &nickname))?;
    Ok(json!({"account": account_json(&renamed), "talents": talents}))
}

/// Binds an account to the session. A second live session for the same
/// account kicks the older one (and closes anything it hosted) first.
pub fn bind_account(state: &AppState, sid: SessionId, account: &Account) -> Result<Value, ApiError> {
    let talents = state.db.with(|conn| talents::state_json(conn, &state.talents, account.id, &account.nickname))?;
    let abandoned = {
        let mut hub = state.hub();
        let mut abandoned = Vec::new();
        if let Some(old) = hub.session_for_account(account.id) {
            if old != sid {
                hub.send(old, protocol::push("kicked", json!({"reason": "logged_in_elsewhere"})));
                hub.close(old, limits::CLOSE_KICKED, "logged in elsewhere");
                abandoned = hub.remove_session(old);
            }
        }
        let session = hub.require_session_mut(sid)?;
        session.account = Some(AccountRef { id: account.id, nickname: account.nickname.clone() });
        hub.by_account.insert(account.id, sid);
        abandoned
    };
    if !abandoned.is_empty() {
        state.db.with(|conn| Ok(matches::db_abandon(conn, &abandoned)?))?;
    }
    let _ = lobbies::LobbyState::Open;
    Ok(talents)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::db::Db;

    #[test]
    fn key_hashing_and_accounts() {
        let key = "ab".repeat(32);
        let hash = key_hash_from_hex(&key).unwrap();
        assert_eq!(hash.len(), 32);
        assert!(key_hash_from_hex("zz").is_err());
        let db = Db::open_in_memory().unwrap();
        db.with(|conn| {
            assert!(db_find_by_key_hash(conn, &hash)?.is_none());
            let account = db_create(conn, &hash, "Pilot", 100, "127.0.0.1")?;
            assert_eq!(account.nickname, "Pilot");
            assert_eq!(db_nickname_owner(conn, "pilot")?, Some(account.id));
            let found = db_find_by_key_hash(conn, &hash)?.unwrap();
            assert_eq!(found.id, account.id);
            db_rename(conn, account.id, "Ace")?;
            assert_eq!(db_nickname_owner(conn, "ace")?, Some(account.id));
            assert!(db_nickname_owner(conn, "pilot")?.is_none());
            let duplicate = db_create(conn, &[1u8; 32], "ACE", 100, "127.0.0.1");
            assert!(duplicate.is_err(), "case-insensitive duplicates are rejected");
            Ok(())
        })
        .unwrap();
    }
}

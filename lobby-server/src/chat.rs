//! Global chat: one room, stored history, rate limited per session.

use rusqlite::{params, Connection};
use serde_json::{json, Value};

use crate::db::now_unix;
use crate::protocol::{self, field_i64_opt, field_string, has_control_chars, limits, ApiError, ApiResult, ErrorCode};
use crate::session::SessionId;
use crate::state::AppState;

pub fn db_insert(conn: &Connection, account_id: i64, nickname: &str, body: &str, now: i64) -> rusqlite::Result<i64> {
    conn.execute(
        "INSERT INTO chat_messages (account_id, nickname, body, sent_at) VALUES (?1, ?2, ?3, ?4)",
        params![account_id, nickname, body, now],
    )?;
    Ok(conn.last_insert_rowid())
}

/// The newest `limit` messages before `before_id` (or the newest overall),
/// returned in ascending id order plus whether older ones exist.
pub fn db_history(conn: &Connection, before_id: Option<i64>, limit: usize) -> rusqlite::Result<(Vec<Value>, bool)> {
    let fetch = (limit + 1) as i64;
    let mut rows: Vec<Value> = Vec::new();
    let map_row = |row: &rusqlite::Row| -> rusqlite::Result<Value> {
        Ok(json!({
            "id": row.get::<_, i64>(0)?,
            "account_id": row.get::<_, i64>(1)?,
            "nickname": row.get::<_, String>(2)?,
            "body": row.get::<_, String>(3)?,
            "sent_at": row.get::<_, i64>(4)?,
        }))
    };
    match before_id {
        Some(before) => {
            let mut statement = conn.prepare(
                "SELECT id, account_id, nickname, body, sent_at FROM chat_messages WHERE id < ?1 ORDER BY id DESC LIMIT ?2",
            )?;
            for row in statement.query_map(params![before, fetch], |row| map_row(row))? {
                rows.push(row?);
            }
        }
        None => {
            let mut statement =
                conn.prepare("SELECT id, account_id, nickname, body, sent_at FROM chat_messages ORDER BY id DESC LIMIT ?1")?;
            for row in statement.query_map(params![fetch], |row| map_row(row))? {
                rows.push(row?);
            }
        }
    }
    let has_more = rows.len() > limit;
    rows.truncate(limit);
    rows.reverse();
    Ok((rows, has_more))
}

pub fn db_prune(conn: &Connection, keep: i64) -> rusqlite::Result<usize> {
    conn.execute(
        "DELETE FROM chat_messages WHERE id < (SELECT COALESCE(MAX(id), 0) - ?1 FROM chat_messages)",
        params![keep],
    )
}

pub fn handle_send(state: &AppState, sid: SessionId, payload: &Value) -> ApiResult {
    let body = field_string(payload, "body", limits::CHAT_MAX_CHARS)?;
    if body.is_empty() {
        return Err(ApiError::schema("chat body is empty"));
    }
    if body.len() > limits::CHAT_MAX_BYTES || has_control_chars(&body) {
        return Err(ApiError::schema("chat body has unsupported characters"));
    }
    let account = {
        let mut hub = state.hub();
        let account = hub.require_account(sid)?;
        if !hub.require_session_mut(sid)?.bucket_chat.try_take() {
            return Err(ApiError::new(ErrorCode::RateLimited, "chat is rate limited"));
        }
        account
    };
    let now = now_unix();
    let id = state.db.with(|conn| Ok(db_insert(conn, account.id, &account.nickname, &body, now)?))?;
    let message = protocol::push(
        "chat_message",
        json!({"id": id, "account_id": account.id, "nickname": account.nickname, "body": body, "sent_at": now}),
    );
    {
        let mut hub = state.hub();
        hub.stats.chat_total += 1;
        hub.broadcast_registered(&message);
    }
    Ok(json!({"id": id}))
}

pub fn handle_history(state: &AppState, sid: SessionId, payload: &Value) -> ApiResult {
    state.hub().require_account(sid)?;
    let before_id = field_i64_opt(payload, "before_id")?.filter(|id| *id > 0);
    let limit = field_i64_opt(payload, "limit")?.unwrap_or(limits::HISTORY_PAGE as i64);
    let limit = limit.clamp(1, limits::HISTORY_MAX as i64) as usize;
    let (messages, has_more) = state.db.with(|conn| Ok(db_history(conn, before_id, limit)?))?;
    Ok(json!({"messages": messages, "has_more": has_more}))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::db::Db;

    #[test]
    fn history_pages_backwards() {
        let db = Db::open_in_memory().unwrap();
        db.with(|conn| {
            for index in 1..=7 {
                db_insert(conn, 1, "Pilot", &format!("line {index}"), index)?;
            }
            let (page, more) = db_history(conn, None, 3)?;
            assert!(more);
            let ids: Vec<i64> = page.iter().map(|m| m["id"].as_i64().unwrap()).collect();
            assert_eq!(ids, vec![5, 6, 7]);
            let (older, more) = db_history(conn, Some(5), 3)?;
            let ids: Vec<i64> = older.iter().map(|m| m["id"].as_i64().unwrap()).collect();
            assert_eq!(ids, vec![2, 3, 4]);
            assert!(more);
            let (oldest, more) = db_history(conn, Some(2), 3)?;
            assert_eq!(oldest.len(), 1);
            assert!(!more);
            let removed = db_prune(conn, 2)?;
            assert_eq!(removed, 4);
            Ok(())
        })
        .unwrap();
    }
}

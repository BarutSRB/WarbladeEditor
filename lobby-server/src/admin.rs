//! The owner's admin surface on a loopback-only listener: a static page and
//! JSON endpoints behind a bearer token. Reach it through an SSH tunnel
//! (`ssh -N -L 7402:127.0.0.1:7402 <droplet>`), never through the public port.

use std::collections::HashMap;
use std::sync::Arc;

use axum::extract::{Path, Query, State};
use axum::http::{header, HeaderMap, StatusCode};
use axum::response::{Html, IntoResponse, Response};
use axum::routing::{get, post};
use axum::{Json, Router};
use rusqlite::{params, Connection};
use serde_json::{json, Value};
use tracing::info;

use crate::accounts;
use crate::db::now_unix;
use crate::protocol::{self, is_valid_nickname, limits, ApiError, ErrorCode};
use crate::session::SessionId;
use crate::state::AppState;
use crate::stats;
use crate::talents;

const PAGE: &str = include_str!("admin_page.html");

pub fn router(state: Arc<AppState>) -> Router {
    Router::new()
        .route("/", get(|| async { axum::response::Redirect::temporary("/admin") }))
        .route("/admin", get(page))
        .route("/admin/api/overview", get(overview))
        .route("/admin/api/sessions", get(sessions))
        .route("/admin/api/lobbies", get(lobbies))
        .route("/admin/api/matches", get(matches))
        .route("/admin/api/chat", get(chat))
        .route("/admin/api/accounts", get(accounts_list))
        .route("/admin/api/accounts/{id}/reset_key", post(reset_key))
        .route("/admin/api/accounts/{id}/rename", post(rename))
        .route("/admin/api/accounts/{id}/disable", post(disable))
        .route("/admin/api/accounts/{id}/enable", post(enable))
        .route("/admin/api/accounts/{id}/points", post(points))
        .route("/admin/api/sessions/{id}/kick", post(kick))
        .route("/admin/api/notice", post(notice))
        .with_state(state)
}

async fn page() -> Html<&'static str> {
    Html(PAGE)
}

fn authorized(state: &AppState, headers: &HeaderMap) -> Result<(), Response> {
    let expected = state.config.admin_token.as_deref().unwrap_or("");
    let presented = headers
        .get(header::AUTHORIZATION)
        .and_then(|value| value.to_str().ok())
        .and_then(|value| value.strip_prefix("Bearer "))
        .unwrap_or("");
    if !expected.is_empty() && constant_time_eq(expected.as_bytes(), presented.as_bytes()) {
        return Ok(());
    }
    Err(error_response(StatusCode::UNAUTHORIZED, ApiError::new(ErrorCode::NotAuthenticated, "admin token required")))
}

fn constant_time_eq(a: &[u8], b: &[u8]) -> bool {
    if a.len() != b.len() {
        return false;
    }
    let mut difference = 0u8;
    for (x, y) in a.iter().zip(b.iter()) {
        difference |= x ^ y;
    }
    difference == 0
}

fn ok_response(value: Value) -> Response {
    let mut body = json!({"ok": true});
    if let (Value::Object(target), Value::Object(fields)) = (&mut body, value) {
        for (key, field) in fields {
            target.insert(key, field);
        }
    }
    (StatusCode::OK, Json(body)).into_response()
}

fn error_response(status: StatusCode, error: ApiError) -> Response {
    (status, Json(json!({"ok": false, "error": error.to_json()}))).into_response()
}

fn api_error(error: ApiError) -> Response {
    let status = match error.code {
        ErrorCode::SchemaMismatch | ErrorCode::InvalidNickname => StatusCode::BAD_REQUEST,
        ErrorCode::NicknameTaken => StatusCode::CONFLICT,
        ErrorCode::MatchNotFound | ErrorCode::LobbyNotFound => StatusCode::NOT_FOUND,
        _ => StatusCode::INTERNAL_SERVER_ERROR,
    };
    error_response(status, error)
}

fn log_event(conn: &Connection, kind: &str, account_id: Option<i64>, detail: &str) -> rusqlite::Result<()> {
    conn.execute(
        "INSERT INTO admin_events (at, kind, account_id, detail) VALUES (?1, ?2, ?3, ?4)",
        params![now_unix(), kind, account_id, detail],
    )?;
    Ok(())
}

fn limit_param(params: &HashMap<String, String>, default: i64, max: i64) -> i64 {
    params.get("limit").and_then(|v| v.parse::<i64>().ok()).unwrap_or(default).clamp(1, max)
}

fn before_param(params: &HashMap<String, String>) -> Option<i64> {
    params.get("before").and_then(|v| v.parse::<i64>().ok()).filter(|v| *v > 0)
}

// ------------------------------------------------------------------- reads

async fn overview(State(state): State<Arc<AppState>>, headers: HeaderMap) -> Response {
    if let Err(response) = authorized(&state, &headers) {
        return response;
    }
    ok_response(json!({"overview": stats::overview(&state)}))
}

async fn sessions(State(state): State<Arc<AppState>>, headers: HeaderMap) -> Response {
    if let Err(response) = authorized(&state, &headers) {
        return response;
    }
    ok_response(json!({"sessions": stats::sessions(&state)}))
}

async fn lobbies(State(state): State<Arc<AppState>>, headers: HeaderMap) -> Response {
    if let Err(response) = authorized(&state, &headers) {
        return response;
    }
    ok_response(json!({"lobbies": stats::lobbies(&state)}))
}

async fn matches(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Query(params): Query<HashMap<String, String>>,
) -> Response {
    if let Err(response) = authorized(&state, &headers) {
        return response;
    }
    let limit = limit_param(&params, 100, 500);
    let before = before_param(&params);
    let rows = state.db.maintenance(|conn| {
        let mut statement = conn.prepare(
            "SELECT id, kind, lobby_id, lobby_name, host_account_id, mode, difficulty, coop_balance, seed, started_at, ended_at, result, score, level_reached, duration_ticks, campaign_completed FROM matches WHERE (?1 IS NULL OR id < ?1) ORDER BY id DESC LIMIT ?2",
        )?;
        let mut rows = Vec::new();
        let matches = statement.query_map(params![before, limit], |row| {
            Ok(json!({
                "id": row.get::<_, i64>(0)?,
                "kind": row.get::<_, String>(1)?,
                "lobby_id": row.get::<_, Option<String>>(2)?,
                "lobby_name": row.get::<_, Option<String>>(3)?,
                "host_account_id": row.get::<_, i64>(4)?,
                "mode": row.get::<_, String>(5)?,
                "difficulty": row.get::<_, String>(6)?,
                "coop_balance": row.get::<_, String>(7)?,
                "seed": row.get::<_, Option<String>>(8)?,
                "started_at": row.get::<_, i64>(9)?,
                "ended_at": row.get::<_, Option<i64>>(10)?,
                "result": row.get::<_, Option<String>>(11)?,
                "score": row.get::<_, Option<i64>>(12)?,
                "level_reached": row.get::<_, Option<i64>>(13)?,
                "duration_ticks": row.get::<_, Option<i64>>(14)?,
                "campaign_completed": row.get::<_, i64>(15)? != 0,
            }))
        })?;
        for value in matches {
            rows.push(value?);
        }
        let mut players_statement = conn.prepare(
            "SELECT seat, account_id, nickname, points_awarded FROM match_players WHERE match_id = ?1 ORDER BY seat",
        )?;
        for row in &mut rows {
            let match_id = row["id"].as_i64().unwrap_or(0);
            let players: Vec<Value> = players_statement
                .query_map(params![match_id], |player| {
                    Ok(json!({
                        "seat": player.get::<_, i64>(0)?,
                        "account_id": player.get::<_, Option<i64>>(1)?,
                        "nickname": player.get::<_, String>(2)?,
                        "points_awarded": player.get::<_, i64>(3)?,
                    }))
                })?
                .collect::<rusqlite::Result<Vec<_>>>()?;
            if let Value::Object(object) = row {
                object.insert("players".into(), Value::Array(players));
            }
        }
        Ok(rows)
    });
    match rows {
        Ok(rows) => ok_response(json!({"matches": rows})),
        Err(error) => api_error(ApiError::internal(error.to_string())),
    }
}

async fn chat(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Query(params): Query<HashMap<String, String>>,
) -> Response {
    if let Err(response) = authorized(&state, &headers) {
        return response;
    }
    let limit = limit_param(&params, 200, 1000) as usize;
    let before = before_param(&params);
    match state.db.with(|conn| Ok(crate::chat::db_history(conn, before, limit)?)) {
        Ok((messages, has_more)) => ok_response(json!({"messages": messages, "has_more": has_more})),
        Err(error) => api_error(error),
    }
}

async fn accounts_list(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Query(params): Query<HashMap<String, String>>,
) -> Response {
    if let Err(response) = authorized(&state, &headers) {
        return response;
    }
    let query = params.get("query").cloned().unwrap_or_default().to_lowercase();
    let pattern = format!("%{}%", query);
    let rows = state.db.maintenance(|conn| {
        let mut statement = conn.prepare(
            "SELECT a.id, a.nickname, a.created_at, a.last_login_at, a.last_ip, a.disabled, a.talent_points, a.points_earned_total, (SELECT COUNT(*) FROM talent_nodes t WHERE t.account_id = a.id), (SELECT COUNT(*) FROM match_players p WHERE p.account_id = a.id) FROM accounts a WHERE a.nickname_lc LIKE ?1 ORDER BY a.id DESC LIMIT 500",
        )?;
        let rows = statement
            .query_map(params![pattern], |row| {
                Ok(json!({
                    "id": row.get::<_, i64>(0)?,
                    "nickname": row.get::<_, String>(1)?,
                    "created_at": row.get::<_, i64>(2)?,
                    "last_login_at": row.get::<_, Option<i64>>(3)?,
                    "last_ip": row.get::<_, Option<String>>(4)?,
                    "disabled": row.get::<_, i64>(5)? != 0,
                    "talent_points": row.get::<_, i64>(6)?,
                    "points_earned_total": row.get::<_, i64>(7)?,
                    "talents_owned": row.get::<_, i64>(8)?,
                    "matches_played": row.get::<_, i64>(9)?,
                }))
            })?
            .collect::<rusqlite::Result<Vec<_>>>()?;
        Ok(rows)
    });
    match rows {
        Ok(rows) => ok_response(json!({"accounts": rows})),
        Err(error) => api_error(ApiError::internal(error.to_string())),
    }
}

// ----------------------------------------------------------------- actions

fn require_account(conn: &Connection, id: i64) -> Result<accounts::Account, ApiError> {
    accounts::db_find_by_id(conn, id)?.ok_or_else(|| ApiError::new(ErrorCode::MatchNotFound, "no such account"))
}

fn kick_account_sessions(state: &AppState, account_id: i64, reason: &str) {
    let abandoned = {
        let mut hub = state.hub();
        match hub.session_for_account(account_id) {
            Some(sid) => {
                hub.send(sid, protocol::push("kicked", json!({"reason": reason})));
                hub.close(sid, limits::CLOSE_KICKED, "kicked by the owner");
                hub.remove_session(sid)
            }
            None => Vec::new(),
        }
    };
    if !abandoned.is_empty() {
        let _ = state.db.with(|conn| Ok(crate::matches::db_abandon(conn, &abandoned)?));
    }
}

async fn reset_key(State(state): State<Arc<AppState>>, headers: HeaderMap, Path(id): Path<i64>) -> Response {
    if let Err(response) = authorized(&state, &headers) {
        return response;
    }
    let mut key = [0u8; 32];
    rand::RngCore::fill_bytes(&mut rand::thread_rng(), &mut key);
    let key_hex = hex::encode(key);
    let hash = match accounts::key_hash_from_hex(&key_hex) {
        Ok(hash) => hash,
        Err(error) => return api_error(error),
    };
    let result = state.db.with(|conn| {
        let account = require_account(conn, id)?;
        accounts::db_replace_key(conn, id, &hash)?;
        log_event(conn, "reset_key", Some(id), &format!("device key replaced for {}", account.nickname))?;
        Ok(account)
    });
    match result {
        Ok(account) => {
            kick_account_sessions(&state, id, "key_reset");
            info!(account = id, "device key reset by the owner");
            ok_response(json!({"account": accounts::account_json(&account), "device_key": key_hex}))
        }
        Err(error) => api_error(error),
    }
}

async fn rename(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Path(id): Path<i64>,
    Json(body): Json<Value>,
) -> Response {
    if let Err(response) = authorized(&state, &headers) {
        return response;
    }
    let nickname = body.get("nickname").and_then(Value::as_str).unwrap_or("").trim().to_string();
    if !is_valid_nickname(&nickname) {
        return api_error(ApiError::new(ErrorCode::InvalidNickname, "nicknames are 3-16 letters, digits, or underscores"));
    }
    let result = state.db.with(|conn| {
        let account = require_account(conn, id)?;
        if let Some(owner) = accounts::db_nickname_owner(conn, &nickname.to_lowercase())? {
            if owner != id {
                return Err(ApiError::new(ErrorCode::NicknameTaken, "that nickname is taken"));
            }
        }
        accounts::db_rename(conn, id, &nickname)?;
        log_event(conn, "rename", Some(id), &format!("{} -> {}", account.nickname, nickname))?;
        Ok(())
    });
    if let Err(error) = result {
        return api_error(error);
    }
    {
        let mut hub = state.hub();
        if let Some(sid) = hub.session_for_account(id) {
            if let Some(session) = hub.session_mut(sid) {
                if let Some(account) = &mut session.account {
                    account.nickname = nickname.clone();
                }
            }
            for lobby in hub.lobbies.values_mut() {
                if lobby.host == sid {
                    lobby.host_nickname = nickname.clone();
                }
            }
            hub.send(sid, protocol::push("notice", json!({"kind": "admin", "message": format!("your nickname is now {nickname}")})));
        }
    }
    ok_response(json!({"account": {"id": id, "nickname": nickname}}))
}

async fn set_disabled(state: &AppState, id: i64, disabled: bool) -> Response {
    let result = state.db.with(|conn| {
        let account = require_account(conn, id)?;
        accounts::db_set_disabled(conn, id, disabled)?;
        log_event(conn, if disabled { "disable" } else { "enable" }, Some(id), &account.nickname)?;
        Ok(account)
    });
    match result {
        Ok(account) => {
            if disabled {
                kick_account_sessions(state, id, "disabled");
            }
            ok_response(json!({"account": accounts::account_json(&account), "disabled": disabled}))
        }
        Err(error) => api_error(error),
    }
}

async fn disable(State(state): State<Arc<AppState>>, headers: HeaderMap, Path(id): Path<i64>) -> Response {
    if let Err(response) = authorized(&state, &headers) {
        return response;
    }
    set_disabled(&state, id, true).await
}

async fn enable(State(state): State<Arc<AppState>>, headers: HeaderMap, Path(id): Path<i64>) -> Response {
    if let Err(response) = authorized(&state, &headers) {
        return response;
    }
    set_disabled(&state, id, false).await
}

async fn points(
    State(state): State<Arc<AppState>>,
    headers: HeaderMap,
    Path(id): Path<i64>,
    Json(body): Json<Value>,
) -> Response {
    if let Err(response) = authorized(&state, &headers) {
        return response;
    }
    let delta = body.get("delta").and_then(Value::as_i64).unwrap_or(0).clamp(-100_000, 100_000);
    if delta == 0 {
        return api_error(ApiError::schema("delta must be a non-zero integer"));
    }
    let now = now_unix();
    let result = state.db.with(|conn| {
        let account = require_account(conn, id)?;
        talents::db_credit(conn, id, delta, "admin", "owner", now)?;
        log_event(conn, "points", Some(id), &format!("{delta:+} for {}", account.nickname))?;
        talents::state_json(conn, &state.talents, id, &account.nickname)
    });
    match result {
        Ok(talent_state) => {
            let hub = state.hub();
            if let Some(sid) = hub.session_for_account(id) {
                hub.send(
                    sid,
                    protocol::push("points_credited", json!({"match_id": 0, "points": delta.max(0), "reason": "admin", "state": talent_state})),
                );
            }
            ok_response(json!({"state": talent_state}))
        }
        Err(error) => api_error(error),
    }
}

async fn kick(State(state): State<Arc<AppState>>, headers: HeaderMap, Path(id): Path<SessionId>) -> Response {
    if let Err(response) = authorized(&state, &headers) {
        return response;
    }
    let abandoned = {
        let mut hub = state.hub();
        if hub.session(id).is_none() {
            return api_error(ApiError::new(ErrorCode::MatchNotFound, "no such session"));
        }
        hub.send(id, protocol::push("kicked", json!({"reason": "owner"})));
        hub.close(id, limits::CLOSE_KICKED, "kicked by the owner");
        hub.remove_session(id)
    };
    if !abandoned.is_empty() {
        let _ = state.db.with(|conn| Ok(crate::matches::db_abandon(conn, &abandoned)?));
    }
    let _ = state.db.with(|conn| Ok(log_event(conn, "kick", None, &format!("session {id}"))?));
    ok_response(json!({"kicked": id}))
}

async fn notice(State(state): State<Arc<AppState>>, headers: HeaderMap, Json(body): Json<Value>) -> Response {
    if let Err(response) = authorized(&state, &headers) {
        return response;
    }
    let message = body.get("message").and_then(Value::as_str).unwrap_or("").trim().to_string();
    if message.is_empty() || message.chars().count() > 200 {
        return api_error(ApiError::schema("message must be 1-200 characters"));
    }
    let text = protocol::push("notice", json!({"kind": "admin", "message": message}));
    let recipients = {
        let hub = state.hub();
        hub.broadcast_registered(&text);
        hub.registered_count()
    };
    let _ = state.db.with(|conn| Ok(log_event(conn, "notice", None, &message)?));
    ok_response(json!({"recipients": recipients}))
}

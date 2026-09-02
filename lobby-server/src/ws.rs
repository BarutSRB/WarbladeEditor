//! WebSocket plumbing: one reader loop and one writer task per connection,
//! rate limiting, the request dispatcher, and disconnect cleanup.

use std::net::SocketAddr;
use std::sync::Arc;
use std::time::{Duration, Instant};

use axum::extract::connect_info::ConnectInfo;
use axum::extract::ws::{CloseFrame, Message, WebSocket, WebSocketUpgrade};
use axum::extract::State;
use axum::response::Response;
use futures_util::{SinkExt, StreamExt};
use serde_json::Value;
use tokio::sync::mpsc;
use tracing::{debug, info, warn};

use crate::protocol::{self, limits, ApiError, ApiResult, ErrorCode};
use crate::session::{Outbound, SessionId};
use crate::state::AppState;
use crate::{accounts, chat, lobbies, matches, talents};

/// Delay between a final text frame and the close frame that follows it.
const CLOSE_GRACE: Duration = Duration::from_millis(250);

pub async fn ws_handler(
    ws: WebSocketUpgrade,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    State(state): State<Arc<AppState>>,
) -> Response {
    ws.max_message_size(protocol::MAX_FRAME_BYTES)
        .on_upgrade(move |socket| handle_socket(socket, addr, state))
}

async fn handle_socket(socket: WebSocket, addr: SocketAddr, state: Arc<AppState>) {
    let (mut sink, mut stream) = socket.split();
    let (tx, mut rx) = mpsc::channel::<Outbound>(limits::OUTBOUND_QUEUE);
    let added = {
        let mut hub = state.hub();
        hub.add_session(addr.ip(), tx.clone(), state.config.max_connections, state.config.max_connections_per_ip)
    };
    let sid = match added {
        Ok(sid) => sid,
        Err(error) => {
            let _ = sink.send(Message::Text(protocol::response_error("hello", None, &error).into())).await;
            tokio::time::sleep(CLOSE_GRACE).await;
            let _ = sink
                .send(Message::Close(Some(CloseFrame { code: limits::CLOSE_FULL, reason: "server full".into() })))
                .await;
            return;
        }
    };
    debug!(session = sid, %addr, "connected");
    let writer = tokio::spawn(async move {
        while let Some(outbound) = rx.recv().await {
            match outbound {
                Outbound::Text(text) => {
                    if sink.send(Message::Text(text.into())).await.is_err() {
                        break;
                    }
                }
                Outbound::Close(code, reason) => {
                    // Godot's WebSocketPeer cannot hand queued frames to a script
                    // once the socket leaves the open state, so a final message
                    // (kicked, notice) needs a poll cycle before the close frame.
                    tokio::time::sleep(CLOSE_GRACE).await;
                    let _ = sink.send(Message::Close(Some(CloseFrame { code, reason: reason.into() }))).await;
                    break;
                }
            }
        }
    });
    loop {
        let next = tokio::time::timeout(Duration::from_secs(limits::IDLE_TIMEOUT_SEC), stream.next()).await;
        match next {
            Ok(Some(Ok(Message::Text(text)))) => {
                if !dispatch(&state, sid, text.as_str()) {
                    break;
                }
            }
            Ok(Some(Ok(Message::Binary(_)))) => {
                if !note_malformed(&state, sid, "binary frame") {
                    break;
                }
            }
            Ok(Some(Ok(Message::Ping(_)))) | Ok(Some(Ok(Message::Pong(_)))) => {
                state.hub().touch(sid);
            }
            Ok(Some(Ok(Message::Close(_)))) | Ok(None) | Ok(Some(Err(_))) => break,
            Err(_) => {
                state.hub().close(sid, limits::CLOSE_IDLE, "idle timeout");
                break;
            }
        }
    }
    let abandoned = state.hub().remove_session(sid);
    if !abandoned.is_empty() {
        if let Err(error) = state.db.with(|conn| Ok(matches::db_abandon(conn, &abandoned)?)) {
            warn!(session = sid, "could not abandon matches: {}", error.message);
        }
    }
    drop(tx);
    let _ = tokio::time::timeout(Duration::from_secs(2), writer).await;
    debug!(session = sid, "disconnected");
}

/// Handles one text frame. Returns false when the connection should drop.
fn dispatch(state: &AppState, sid: SessionId, text: &str) -> bool {
    let value: Value = match serde_json::from_str(text) {
        Ok(value) => value,
        Err(_) => return note_malformed(state, sid, "invalid json"),
    };
    let t = value.get("t").and_then(Value::as_str).unwrap_or("").to_string();
    let rid = match value.get("rid").and_then(Value::as_u64) {
        Some(rid) if rid > 0 => rid,
        _ => {
            let error = ApiError::schema("every request needs a positive rid");
            state.hub().send(sid, protocol::response_error(&t, None, &error));
            return note_malformed(state, sid, "missing rid");
        }
    };
    {
        let mut hub = state.hub();
        let Some(session) = hub.session_mut(sid) else { return false };
        let now = Instant::now();
        session.last_seen = now;
        if now.duration_since(session.burst_window) >= Duration::from_secs(1) {
            session.burst_window = now;
            session.burst_count = 0;
        }
        session.burst_count += 1;
        if session.burst_count > 100 {
            hub.close(sid, limits::CLOSE_ABUSE, "message flood");
            return false;
        }
        if !session.bucket_general.try_take() {
            let error = ApiError::new(ErrorCode::RateLimited, "too many requests");
            hub.send(sid, protocol::response_error(&t, Some(rid), &error));
            return true;
        }
    }
    match route(state, sid, &t, &value) {
        Ok(fields) => {
            state.hub().send(sid, protocol::response_ok(&t, rid, fields));
        }
        Err(error) => {
            let hub = state.hub();
            hub.send(sid, protocol::response_error(&t, Some(rid), &error));
            if error.code == ErrorCode::ProtocolMismatch {
                hub.close(sid, limits::CLOSE_PROTOCOL, "protocol mismatch");
                return false;
            }
        }
    }
    true
}

fn note_malformed(state: &AppState, sid: SessionId, what: &str) -> bool {
    let mut hub = state.hub();
    let Some(session) = hub.session_mut(sid) else { return false };
    session.malformed += 1;
    let count = session.malformed;
    warn!(session = sid, what, count, "malformed frame");
    if count >= limits::MAX_MALFORMED {
        hub.close(sid, limits::CLOSE_ABUSE, "malformed frames");
        return false;
    }
    true
}

fn route(state: &AppState, sid: SessionId, t: &str, payload: &Value) -> ApiResult {
    let (hello_done, authed, registered) = {
        let hub = state.hub();
        let session = hub.require_session(sid)?;
        (session.hello_done, session.key_hash.is_some(), session.account.is_some())
    };
    if !hello_done && t != "hello" {
        return Err(ApiError::schema("send hello first"));
    }
    match t {
        "hello" => accounts::handle_hello(state, sid, payload),
        "ping" => accounts::handle_ping(state, sid, payload),
        "auth" => accounts::handle_auth(state, sid, payload),
        "register" => accounts::handle_register(state, sid, payload),
        _ if !authed => Err(ApiError::new(ErrorCode::NotAuthenticated, "send auth first")),
        _ if !registered => Err(ApiError::new(ErrorCode::NotRegistered, "register a nickname first")),
        "set_nickname" => accounts::handle_set_nickname(state, sid, payload),
        "rendezvous_register" => lobbies::handle_rendezvous_register(state, sid, payload),
        "lobby_create" => lobbies::handle_create(state, sid, payload),
        "lobby_update" => lobbies::handle_update(state, sid, payload),
        "lobby_close" => lobbies::handle_close(state, sid, payload),
        "lobby_list" => lobbies::handle_list(state, sid, payload),
        "lobby_join_request" => lobbies::handle_join_request(state, sid, payload),
        "lobby_join_answer" => lobbies::handle_join_answer(state, sid, payload),
        "lobby_leave" => lobbies::handle_leave(state, sid, payload),
        "chat_send" => chat::handle_send(state, sid, payload),
        "chat_history" => chat::handle_history(state, sid, payload),
        "talent_state" => talents::handle_state(state, sid),
        "talent_spend" => talents::handle_spend(state, sid, payload),
        "talent_respec" => talents::handle_respec(state, sid),
        "match_start" => matches::handle_start(state, sid, payload),
        "match_end" => matches::handle_end(state, sid, payload),
        other => {
            info!(session = sid, request = other, "unknown request type");
            Err(ApiError::schema(format!("unknown request type {other}")))
        }
    }
}

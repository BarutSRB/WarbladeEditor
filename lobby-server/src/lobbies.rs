//! Hosted-game lobbies: in-memory records a host advertises, the join
//! handshake (request -> offer to host -> answer -> ready to joiner), and the
//! rendezvous nonce binding the host's UDP endpoint to its session.

use std::time::Instant;

use rand::RngCore;
use serde_json::{json, Value};
use tracing::info;

use crate::db::now_unix;
use crate::matches;
use crate::protocol::{
    self, endpoint_json, field_bool, field_choice, field_endpoint, field_i64, field_i64_opt, field_port,
    field_string, field_string_opt, has_control_chars, is_hex, limits, ApiError, ApiResult, Endpoint, ErrorCode,
    BALANCES, DIFFICULTIES, MODES,
};
use crate::session::{Hub, Presence, SessionId};
use crate::state::AppState;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum LobbyState {
    Open,
    Full,
    InMatch,
}

impl LobbyState {
    pub fn as_str(self) -> &'static str {
        match self {
            LobbyState::Open => "open",
            LobbyState::Full => "full",
            LobbyState::InMatch => "in_match",
        }
    }
}

#[derive(Clone, Debug)]
pub struct Joiner {
    pub session: SessionId,
    pub account_id: i64,
    pub nickname: String,
    pub public: Option<Endpoint>,
    pub lan: Option<Endpoint>,
}

#[derive(Clone, Debug)]
pub struct Lobby {
    pub id: String,
    pub name: String,
    pub host: SessionId,
    pub host_account_id: i64,
    pub host_nickname: String,
    pub mode: String,
    pub difficulty: String,
    pub coop_balance: String,
    pub content_hash: String,
    pub game_token: String,
    pub port: u16,
    pub host_public: Option<Endpoint>,
    pub host_lan: Option<Endpoint>,
    pub upnp_mapped: bool,
    pub upnp_external_port: Option<u16>,
    pub state: LobbyState,
    pub joiner: Option<Joiner>,
    pub match_id: Option<i64>,
    pub created_at: i64,
}

impl Lobby {
    /// The endpoint joiners should dial from the internet: the UDP-observed
    /// address, with the UPnP external port when a mapping exists.
    pub fn public_endpoint(&self) -> Option<Endpoint> {
        match (self.host_public, self.upnp_mapped, self.upnp_external_port) {
            (Some(observed), true, Some(port)) => Some(Endpoint { ip: observed.ip, port }),
            (Some(observed), _, _) => Some(observed),
            (None, _, _) => None,
        }
    }

    pub fn player_count(&self) -> u32 {
        1 + u32::from(self.joiner.is_some())
    }

    pub fn public_json(&self, viewer_hash: &str, host_fresh: bool) -> Value {
        json!({
            "lobby_id": self.id,
            "name": self.name,
            "host_nickname": self.host_nickname,
            "mode": self.mode,
            "difficulty": self.difficulty,
            "coop_balance": self.coop_balance,
            "state": self.state.as_str(),
            "content_matches": viewer_hash.is_empty() || self.content_hash.is_empty() || viewer_hash == self.content_hash,
            "host_fresh": host_fresh,
            "created_at": self.created_at,
            "player_count": self.player_count(),
            "joiner_nickname": self.joiner.as_ref().map(|j| j.nickname.clone()),
        })
    }

    pub fn full_json(&self, host_fresh: bool) -> Value {
        let mut value = self.public_json("", host_fresh);
        if let Value::Object(object) = &mut value {
            object.insert("game_token".into(), Value::String(self.game_token.clone()));
            object.insert("port".into(), Value::from(self.port));
            object.insert("lan".into(), endpoint_json(self.host_lan));
            object.insert("public".into(), endpoint_json(self.public_endpoint()));
            object.insert("upnp_mapped".into(), Value::Bool(self.upnp_mapped));
            object.insert("content_hash".into(), Value::String(self.content_hash.clone()));
        }
        value
    }
}

#[derive(Clone, Debug)]
pub struct PendingJoin {
    pub join_id: u64,
    pub lobby_id: String,
    pub joiner: SessionId,
    pub joiner_nickname: String,
    pub host: SessionId,
    pub created: Instant,
    pub joiner_public: Option<Endpoint>,
    pub joiner_lan: Option<Endpoint>,
}

fn new_lobby_id() -> String {
    let mut bytes = [0u8; 6];
    rand::thread_rng().fill_bytes(&mut bytes);
    hex::encode(bytes)
}

/// Whether the host is still reachable: its rendezvous keepalive is fresh,
/// or (before a nonce was ever registered) its control connection is alive.
pub fn host_fresh(hub: &Hub, lobby: &Lobby, now: Instant) -> bool {
    match hub.session(lobby.host) {
        None => false,
        Some(session) => match session.nonce.and_then(|nonce| hub.rendezvous.get(&nonce)) {
            Some(entry) => entry.is_fresh(now),
            None => session.nonce.is_none(),
        },
    }
}

fn fresh_public(hub: &Hub, sid: SessionId, now: Instant) -> Option<Endpoint> {
    let session = hub.session(sid)?;
    let entry = hub.rendezvous.get(&session.nonce?)?;
    if entry.is_fresh(now) {
        Some(entry.public)
    } else {
        None
    }
}

// ----------------------------------------------------------------- handlers

pub fn handle_rendezvous_register(state: &AppState, sid: SessionId, payload: &Value) -> ApiResult {
    let nonce_hex = field_string(payload, "nonce", 32)?.to_lowercase();
    if !is_hex(&nonce_hex, 32) {
        return Err(ApiError::schema("nonce must be 32 hex characters"));
    }
    let mut nonce = [0u8; 16];
    nonce.copy_from_slice(&hex::decode(&nonce_hex).map_err(|_| ApiError::schema("nonce must be hex"))?);
    let mut hub = state.hub();
    hub.require_account(sid)?;
    if let Some(entry) = hub.rendezvous.get(&nonce) {
        if entry.session != sid && hub.sessions.contains_key(&entry.session) {
            return Err(ApiError::schema("nonce in use"));
        }
    }
    let previous = hub.require_session(sid)?.nonce;
    if let Some(old) = previous {
        if old != nonce {
            hub.rendezvous.remove(&old);
        }
    }
    hub.require_session_mut(sid)?.nonce = Some(nonce);
    if let Some(entry) = hub.rendezvous.get_mut(&nonce) {
        entry.session = sid;
    }
    let observed = hub.rendezvous.get(&nonce).map(|entry| entry.public.to_json()).unwrap_or(Value::Null);
    Ok(json!({"observed": observed}))
}

pub fn handle_create(state: &AppState, sid: SessionId, payload: &Value) -> ApiResult {
    let name = field_string(payload, "name", limits::LOBBY_NAME_MAX)?;
    if name.is_empty() || has_control_chars(&name) {
        return Err(ApiError::schema("lobby name must be 1-32 printable characters"));
    }
    let mode = field_choice(payload, "mode", MODES)?;
    let difficulty = field_choice(payload, "difficulty", DIFFICULTIES)?;
    let coop_balance = field_choice(payload, "coop_balance", BALANCES)?;
    let game_token = field_string(payload, "game_token", limits::GAME_TOKEN_MAX)?;
    if game_token.is_empty() {
        return Err(ApiError::schema("game_token is required"));
    }
    let port = field_port(payload, "port")?;
    let host_lan = field_endpoint(payload, "lan")?;
    let upnp_mapped = field_bool(payload, "upnp_mapped", false);
    let upnp_external_port = optional_port(payload, "upnp_external_port")?;
    let now = Instant::now();
    let mut hub = state.hub();
    let account = hub.require_account(sid)?;
    let (content_hash, presence) = {
        let session = hub.require_session(sid)?;
        (session.content_hash.clone(), session.presence.clone())
    };
    if content_hash.is_empty() {
        return Err(ApiError::schema("hello carried no content_hash; a host must announce its content"));
    }
    if presence != Presence::Idle {
        return Err(ApiError::new(ErrorCode::AlreadyInLobby, "you are already in a lobby"));
    }
    if hub.lobbies.len() >= state.config.max_lobbies {
        return Err(ApiError::new(ErrorCode::LobbyLimit, "the lobby list is full; try again later"));
    }
    let host_public = fresh_public(&hub, sid, now);
    let mut id = new_lobby_id();
    while hub.lobbies.contains_key(&id) {
        id = new_lobby_id();
    }
    let lobby = Lobby {
        id: id.clone(),
        name,
        host: sid,
        host_account_id: account.id,
        host_nickname: account.nickname.clone(),
        mode,
        difficulty,
        coop_balance,
        content_hash,
        game_token,
        port,
        host_public,
        host_lan,
        upnp_mapped,
        upnp_external_port,
        state: LobbyState::Open,
        joiner: None,
        match_id: None,
        created_at: now_unix(),
    };
    let full = lobby.full_json(host_fresh(&hub, &lobby, now));
    hub.lobbies.insert(id.clone(), lobby);
    hub.require_session_mut(sid)?.presence = Presence::Hosting(id.clone());
    hub.broadcast_registered(&protocol::push("lobby_list_changed", json!({})));
    info!(session = sid, lobby = %id, host = %account.nickname, "lobby created");
    Ok(json!({"lobby": full}))
}

fn optional_port(payload: &Value, key: &str) -> Result<Option<u16>, ApiError> {
    match field_i64_opt(payload, key)? {
        None => Ok(None),
        Some(port) if (1..=65535).contains(&port) => Ok(Some(port as u16)),
        Some(_) => Err(ApiError::schema(format!("{key} must be 1-65535"))),
    }
}

pub fn handle_update(state: &AppState, sid: SessionId, payload: &Value) -> ApiResult {
    let lobby_id = field_string(payload, "lobby_id", 32)?;
    let now = Instant::now();
    let mut hub = state.hub();
    hub.require_account(sid)?;
    let (joiner_session, full, public) = {
        let Some(lobby) = hub.lobbies.get(&lobby_id) else {
            return Err(ApiError::new(ErrorCode::LobbyNotFound, "no such lobby"));
        };
        if lobby.host != sid {
            return Err(ApiError::new(ErrorCode::NotLobbyHost, "only the host can change a lobby"));
        }
        let mut updated = lobby.clone();
        if let Some(name) = field_string_opt(payload, "name", limits::LOBBY_NAME_MAX)? {
            if !name.is_empty() && !has_control_chars(&name) {
                updated.name = name;
            }
        }
        if payload.get("difficulty").is_some() {
            updated.difficulty = field_choice(payload, "difficulty", DIFFICULTIES)?;
        }
        if payload.get("coop_balance").is_some() {
            updated.coop_balance = field_choice(payload, "coop_balance", BALANCES)?;
        }
        if payload.get("upnp_mapped").is_some() {
            updated.upnp_mapped = field_bool(payload, "upnp_mapped", false);
        }
        if payload.get("upnp_external_port").is_some() {
            updated.upnp_external_port = optional_port(payload, "upnp_external_port")?;
        }
        if let Some(lan) = field_endpoint(payload, "lan")? {
            updated.host_lan = Some(lan);
        }
        if let Some(open) = payload.get("open").and_then(Value::as_bool) {
            if open && updated.joiner.is_none() {
                updated.state = LobbyState::Open;
            } else if !open && updated.joiner.is_none() {
                updated.state = LobbyState::InMatch;
            }
        }
        if let Some(observed) = fresh_public(&hub, sid, now) {
            updated.host_public = Some(observed);
        }
        let fresh = host_fresh(&hub, &updated, now);
        let full = updated.full_json(fresh);
        let public = updated.public_json("", fresh);
        let joiner_session = updated.joiner.as_ref().map(|j| j.session);
        hub.lobbies.insert(lobby_id.clone(), updated);
        (joiner_session, full, public)
    };
    if let Some(joiner) = joiner_session {
        hub.send(joiner, protocol::push("lobby_updated", json!({"lobby": public})));
    }
    hub.broadcast_registered(&protocol::push("lobby_list_changed", json!({})));
    Ok(json!({"lobby": full}))
}

pub fn handle_close(state: &AppState, sid: SessionId, payload: &Value) -> ApiResult {
    let lobby_id = field_string(payload, "lobby_id", 32)?;
    let abandoned = {
        let mut hub = state.hub();
        hub.require_account(sid)?;
        match hub.lobbies.get(&lobby_id) {
            None => return Err(ApiError::new(ErrorCode::LobbyNotFound, "no such lobby")),
            Some(lobby) if lobby.host != sid => {
                return Err(ApiError::new(ErrorCode::NotLobbyHost, "only the host can close a lobby"))
            }
            Some(_) => {}
        }
        let abandoned = hub.close_lobby(&lobby_id, "host_closed");
        hub.require_session_mut(sid)?.presence = Presence::Idle;
        abandoned
    };
    if !abandoned.is_empty() {
        state.db.with(|conn| Ok(matches::db_abandon(conn, &abandoned)?))?;
    }
    info!(session = sid, lobby = %lobby_id, "lobby closed");
    Ok(json!({}))
}

pub fn handle_list(state: &AppState, sid: SessionId, payload: &Value) -> ApiResult {
    let query = field_string_opt(payload, "query", 32)?.unwrap_or_default().to_lowercase();
    let include_in_match = field_bool(payload, "include_in_match", false);
    let now = Instant::now();
    let mut hub = state.hub();
    hub.require_account(sid)?;
    if !hub.require_session_mut(sid)?.bucket_list.try_take() {
        return Err(ApiError::new(ErrorCode::RateLimited, "lobby list is rate limited"));
    }
    let viewer_hash = hub.require_session(sid)?.content_hash.clone();
    let mut rows: Vec<(i64, Value)> = hub
        .lobbies
        .values()
        .filter(|lobby| include_in_match || lobby.state != LobbyState::InMatch)
        .filter(|lobby| {
            query.is_empty()
                || lobby.name.to_lowercase().contains(&query)
                || lobby.host_nickname.to_lowercase().contains(&query)
        })
        .map(|lobby| (lobby.created_at, lobby.public_json(&viewer_hash, host_fresh(&hub, lobby, now))))
        .collect();
    rows.sort_by_key(|(created, _)| std::cmp::Reverse(*created));
    rows.truncate(100);
    let lobbies: Vec<Value> = rows.into_iter().map(|(_, value)| value).collect();
    Ok(json!({"lobbies": lobbies}))
}

pub fn handle_join_request(state: &AppState, sid: SessionId, payload: &Value) -> ApiResult {
    let lobby_id = field_string(payload, "lobby_id", 32)?;
    let joiner_lan = field_endpoint(payload, "lan")?;
    let now = Instant::now();
    let mut hub = state.hub();
    let account = hub.require_account(sid)?;
    let (joiner_hash, presence) = {
        let session = hub.require_session(sid)?;
        (session.content_hash.clone(), session.presence.clone())
    };
    let (host, host_hash, lobby_state, fresh) = {
        let Some(lobby) = hub.lobbies.get(&lobby_id) else {
            return Err(ApiError::new(ErrorCode::LobbyNotFound, "that lobby is gone"));
        };
        if lobby.host == sid {
            return Err(ApiError::new(ErrorCode::SelfJoin, "you cannot join your own lobby"));
        }
        (lobby.host, lobby.content_hash.clone(), lobby.state, host_fresh(&hub, lobby, now))
    };
    if presence != Presence::Idle {
        return Err(ApiError::new(ErrorCode::AlreadyInLobby, "leave your current lobby first"));
    }
    let joiner_public = fresh_public(&hub, sid, now);
    if lobby_state != LobbyState::Open {
        return Err(ApiError::new(ErrorCode::LobbyNotOpen, "that lobby is not open"));
    }
    if hub.pending_joins.values().any(|join| join.lobby_id == lobby_id) {
        return Err(ApiError::new(ErrorCode::LobbyNotOpen, "another player is joining that lobby"));
    }
    if !host_hash.is_empty() && !joiner_hash.is_empty() && host_hash != joiner_hash {
        return Err(ApiError::new(ErrorCode::ContentMismatch, "the host runs different game content"));
    }
    if !fresh {
        return Err(ApiError::new(ErrorCode::HostUnreachable, "the host is not reachable right now"));
    }
    let join_id = hub.next_join_id();
    hub.pending_joins.insert(
        join_id,
        PendingJoin {
            join_id,
            lobby_id: lobby_id.clone(),
            joiner: sid,
            joiner_nickname: account.nickname.clone(),
            host,
            created: now,
            joiner_public,
            joiner_lan,
        },
    );
    let offer = protocol::push(
        "lobby_join_offer",
        json!({
            "join_id": join_id,
            "lobby_id": lobby_id,
            "joiner": {
                "account_id": account.id,
                "nickname": account.nickname,
                "public": endpoint_json(joiner_public),
                "lan": endpoint_json(joiner_lan),
            },
        }),
    );
    hub.send(host, offer);
    Ok(json!({"join_id": join_id, "status": "pending"}))
}

pub fn handle_join_answer(state: &AppState, sid: SessionId, payload: &Value) -> ApiResult {
    let join_id = field_i64(payload, "join_id")?;
    let accept = field_bool(payload, "accept", false);
    let reason = field_string_opt(payload, "reason", 64)?;
    let now = Instant::now();
    let mut hub = state.hub();
    hub.require_account(sid)?;
    let join = match hub.pending_joins.get(&(join_id.max(0) as u64)) {
        Some(join) if join.host == sid => join.clone(),
        Some(_) => return Err(ApiError::new(ErrorCode::NotLobbyHost, "that join is not yours to answer")),
        None => return Err(ApiError::new(ErrorCode::JoinNotPending, "that join is no longer pending")),
    };
    hub.pending_joins.remove(&join.join_id);
    if !accept {
        let rejection = protocol::push(
            "lobby_join_rejected",
            json!({"join_id": join.join_id, "lobby_id": join.lobby_id, "reason": reason.unwrap_or_else(|| "host_rejected".to_string())}),
        );
        hub.send(join.joiner, rejection);
        return Ok(json!({}));
    }
    let Some(joiner_account) = hub.session(join.joiner).and_then(|session| session.account.clone()) else {
        return Err(ApiError::new(ErrorCode::JoinNotPending, "the joining player left"));
    };
    let host_ip = hub.require_session(sid)?.ip;
    let joiner_ip = hub.session(join.joiner).map(|session| session.ip);
    let host_public = fresh_public(&hub, sid, now);
    let same_public_ip = match (host_public, join.joiner_public) {
        (Some(host), Some(joiner)) => host.ip == joiner.ip,
        _ => joiner_ip == Some(host_ip),
    };
    let ready = {
        let Some(lobby) = hub.lobbies.get_mut(&join.lobby_id) else {
            return Err(ApiError::new(ErrorCode::LobbyNotFound, "that lobby is gone"));
        };
        if lobby.joiner.is_some() {
            return Err(ApiError::new(ErrorCode::LobbyNotOpen, "the lobby already has a second player"));
        }
        if let Some(observed) = host_public {
            lobby.host_public = Some(observed);
        }
        lobby.joiner = Some(Joiner {
            session: join.joiner,
            account_id: joiner_account.id,
            nickname: joiner_account.nickname.clone(),
            public: join.joiner_public,
            lan: join.joiner_lan,
        });
        if lobby.state == LobbyState::Open {
            lobby.state = LobbyState::Full;
        }
        json!({
            "join_id": join.join_id,
            "lobby_id": lobby.id,
            "game_token": lobby.game_token,
            "content_hash": lobby.content_hash,
            "host_public": endpoint_json(lobby.public_endpoint()),
            "host_lan": endpoint_json(lobby.host_lan),
            "port": lobby.port,
            "upnp_mapped": lobby.upnp_mapped,
            "same_public_ip": same_public_ip,
            "host_nickname": lobby.host_nickname,
            "lobby": lobby.public_json("", true),
        })
    };
    if let Some(session) = hub.session_mut(join.joiner) {
        session.presence = Presence::Joined(join.lobby_id.clone());
    }
    hub.send(join.joiner, protocol::push("lobby_join_ready", ready));
    hub.broadcast_registered(&protocol::push("lobby_list_changed", json!({})));
    info!(lobby = %join.lobby_id, joiner = %joiner_account.nickname, "join accepted");
    Ok(json!({}))
}

pub fn handle_leave(state: &AppState, sid: SessionId, _payload: &Value) -> ApiResult {
    let mut hub = state.hub();
    hub.require_account(sid)?;
    let Some(lobby_id) = hub.lobby_joined_by(sid).map(|lobby| lobby.id.clone()) else {
        return Err(ApiError::new(ErrorCode::NotInLobby, "you are not in a lobby"));
    };
    hub.joiner_left(&lobby_id, "left");
    hub.require_session_mut(sid)?.presence = Presence::Idle;
    Ok(json!({}))
}

//! In-memory state: connected sessions, the lobby table, pending joins, and
//! the rendezvous registry. One `Hub` lives behind a std mutex in AppState
//! and is never held across an await.

use std::collections::HashMap;
use std::net::IpAddr;
use std::time::Instant;

use serde_json::json;
use tokio::sync::mpsc;
use tracing::warn;

use crate::lobbies::{Lobby, LobbyState, PendingJoin};
use crate::protocol::{self, limits, ApiError, Endpoint, ErrorCode};

pub type SessionId = u64;

pub enum Outbound {
    Text(String),
    Close(u16, &'static str),
}

pub struct TokenBucket {
    capacity: f64,
    tokens: f64,
    refill_per_sec: f64,
    last: Instant,
}

impl TokenBucket {
    pub fn new(capacity: f64, refill_per_sec: f64) -> TokenBucket {
        TokenBucket { capacity, tokens: capacity, refill_per_sec, last: Instant::now() }
    }

    pub fn try_take(&mut self) -> bool {
        let now = Instant::now();
        let elapsed = now.duration_since(self.last).as_secs_f64();
        self.last = now;
        self.tokens = (self.tokens + elapsed * self.refill_per_sec).min(self.capacity);
        if self.tokens >= 1.0 {
            self.tokens -= 1.0;
            true
        } else {
            false
        }
    }
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Presence {
    Idle,
    Hosting(String),
    Joined(String),
    InMatch { lobby_id: Option<String>, match_id: i64 },
}

impl Presence {
    pub fn label(&self) -> String {
        match self {
            Presence::Idle => "idle".to_string(),
            Presence::Hosting(lobby) => format!("hosting {lobby}"),
            Presence::Joined(lobby) => format!("joined {lobby}"),
            Presence::InMatch { lobby_id, match_id } => match lobby_id {
                Some(lobby) => format!("in match {match_id} ({lobby})"),
                None => format!("in match {match_id}"),
            },
        }
    }
}

#[derive(Clone, Debug)]
pub struct AccountRef {
    pub id: i64,
    pub nickname: String,
}

pub struct Session {
    pub id: SessionId,
    pub ip: IpAddr,
    pub connected_at: Instant,
    pub last_seen: Instant,
    pub tx: mpsc::Sender<Outbound>,
    pub hello_done: bool,
    pub content_hash: String,
    pub client_version: String,
    pub platform: String,
    /// The hashed device key after a successful `auth`, registered or not.
    pub key_hash: Option<Vec<u8>>,
    pub account: Option<AccountRef>,
    pub presence: Presence,
    pub nonce: Option<[u8; 16]>,
    pub bucket_general: TokenBucket,
    pub bucket_chat: TokenBucket,
    pub bucket_list: TokenBucket,
    pub bucket_talent: TokenBucket,
    pub bucket_match: TokenBucket,
    pub burst_window: Instant,
    pub burst_count: u32,
    pub malformed: u32,
}

#[derive(Clone, Debug)]
pub struct RendezvousEntry {
    pub session: SessionId,
    pub public: Endpoint,
    pub first_seen: Instant,
    pub last_seen: Instant,
}

impl RendezvousEntry {
    pub fn is_fresh(&self, now: Instant) -> bool {
        now.duration_since(self.last_seen).as_secs() <= limits::RENDEZVOUS_FRESH_SEC
    }
}

#[derive(Default)]
pub struct HubStats {
    pub connections_total: u64,
    pub chat_total: u64,
    pub matches_started: u64,
    pub matches_ended: u64,
    pub udp_received: u64,
    pub udp_echoed: u64,
    pub udp_dropped: u64,
}

#[derive(Default)]
pub struct Hub {
    pub sessions: HashMap<SessionId, Session>,
    pub by_account: HashMap<i64, SessionId>,
    pub by_ip: HashMap<IpAddr, u32>,
    pub lobbies: HashMap<String, Lobby>,
    pub pending_joins: HashMap<u64, PendingJoin>,
    pub rendezvous: HashMap<[u8; 16], RendezvousEntry>,
    pub stats: HubStats,
    next_session_id: SessionId,
    next_join_id: u64,
}

impl Hub {
    pub fn add_session(
        &mut self,
        ip: IpAddr,
        tx: mpsc::Sender<Outbound>,
        max_connections: usize,
        max_per_ip: u32,
    ) -> Result<SessionId, ApiError> {
        if self.sessions.len() >= max_connections {
            return Err(ApiError::new(ErrorCode::ServerFull, "the lobby server is full"));
        }
        let per_ip = self.by_ip.get(&ip).copied().unwrap_or(0);
        if per_ip >= max_per_ip {
            return Err(ApiError::new(ErrorCode::ServerFull, "too many connections from this address"));
        }
        self.next_session_id += 1;
        let id = self.next_session_id;
        let now = Instant::now();
        self.sessions.insert(
            id,
            Session {
                id,
                ip,
                connected_at: now,
                last_seen: now,
                tx,
                hello_done: false,
                content_hash: String::new(),
                client_version: String::new(),
                platform: String::new(),
                key_hash: None,
                account: None,
                presence: Presence::Idle,
                nonce: None,
                bucket_general: TokenBucket::new(40.0, 20.0),
                bucket_chat: TokenBucket::new(3.0, 0.5),
                bucket_list: TokenBucket::new(3.0, 1.0),
                bucket_talent: TokenBucket::new(5.0, 0.5),
                bucket_match: TokenBucket::new(10.0, 10.0 / 60.0),
                burst_window: now,
                burst_count: 0,
                malformed: 0,
            },
        );
        *self.by_ip.entry(ip).or_insert(0) += 1;
        self.stats.connections_total += 1;
        Ok(id)
    }

    pub fn next_join_id(&mut self) -> u64 {
        self.next_join_id += 1;
        self.next_join_id
    }

    pub fn session(&self, sid: SessionId) -> Option<&Session> {
        self.sessions.get(&sid)
    }

    pub fn session_mut(&mut self, sid: SessionId) -> Option<&mut Session> {
        self.sessions.get_mut(&sid)
    }

    pub fn require_session(&self, sid: SessionId) -> Result<&Session, ApiError> {
        self.sessions.get(&sid).ok_or_else(|| ApiError::internal("session is gone"))
    }

    pub fn require_session_mut(&mut self, sid: SessionId) -> Result<&mut Session, ApiError> {
        self.sessions.get_mut(&sid).ok_or_else(|| ApiError::internal("session is gone"))
    }

    /// The bound account of a session, or the precise reason there is none.
    pub fn require_account(&self, sid: SessionId) -> Result<AccountRef, ApiError> {
        let session = self.require_session(sid)?;
        if session.key_hash.is_none() {
            return Err(ApiError::new(ErrorCode::NotAuthenticated, "send auth first"));
        }
        session
            .account
            .clone()
            .ok_or_else(|| ApiError::new(ErrorCode::NotRegistered, "register a nickname first"))
    }

    pub fn touch(&mut self, sid: SessionId) {
        if let Some(session) = self.sessions.get_mut(&sid) {
            session.last_seen = Instant::now();
        }
    }

    /// Queues a text frame; a full queue means a stalled client, which is
    /// disconnected rather than allowed to hold memory.
    pub fn send(&self, sid: SessionId, text: String) -> bool {
        match self.sessions.get(&sid) {
            Some(session) => match session.tx.try_send(Outbound::Text(text)) {
                Ok(()) => true,
                Err(_) => {
                    warn!(session = sid, "outbound queue full; closing");
                    let _ = session.tx.try_send(Outbound::Close(limits::CLOSE_ABUSE, "slow consumer"));
                    false
                }
            },
            None => false,
        }
    }

    pub fn close(&self, sid: SessionId, code: u16, reason: &'static str) {
        if let Some(session) = self.sessions.get(&sid) {
            let _ = session.tx.try_send(Outbound::Close(code, reason));
        }
    }

    pub fn broadcast_registered(&self, text: &str) {
        for session in self.sessions.values() {
            if session.account.is_some() {
                let _ = session.tx.try_send(Outbound::Text(text.to_string()));
            }
        }
    }

    pub fn session_for_account(&self, account_id: i64) -> Option<SessionId> {
        self.by_account.get(&account_id).copied()
    }

    pub fn lobby_hosted_by(&self, sid: SessionId) -> Option<&Lobby> {
        self.lobbies.values().find(|lobby| lobby.host == sid)
    }

    pub fn lobby_joined_by(&self, sid: SessionId) -> Option<&Lobby> {
        self.lobbies
            .values()
            .find(|lobby| lobby.joiner.as_ref().map(|joiner| joiner.session == sid).unwrap_or(false))
    }

    /// Removes a session and unwinds everything it owned. Returns the ids of
    /// matches that were running in a lobby this session hosted, so the
    /// caller can mark them abandoned in the database.
    pub fn remove_session(&mut self, sid: SessionId) -> Vec<i64> {
        let Some(session) = self.sessions.remove(&sid) else { return Vec::new() };
        if let Some(account) = &session.account {
            if self.by_account.get(&account.id) == Some(&sid) {
                self.by_account.remove(&account.id);
            }
        }
        if let Some(count) = self.by_ip.get_mut(&session.ip) {
            *count = count.saturating_sub(1);
            if *count == 0 {
                self.by_ip.remove(&session.ip);
            }
        }
        if let Some(nonce) = session.nonce {
            self.rendezvous.remove(&nonce);
        }
        let mut abandoned = Vec::new();
        let hosted: Vec<String> = self.lobbies.values().filter(|l| l.host == sid).map(|l| l.id.clone()).collect();
        for lobby_id in hosted {
            abandoned.extend(self.close_lobby(&lobby_id, "host_left"));
        }
        let joined: Vec<String> = self
            .lobbies
            .values()
            .filter(|l| l.joiner.as_ref().map(|j| j.session == sid).unwrap_or(false))
            .map(|l| l.id.clone())
            .collect();
        for lobby_id in joined {
            self.joiner_left(&lobby_id, "disconnected");
        }
        let stale: Vec<u64> = self
            .pending_joins
            .values()
            .filter(|join| join.joiner == sid)
            .map(|join| join.join_id)
            .collect();
        for join_id in stale {
            if let Some(join) = self.pending_joins.remove(&join_id) {
                let text = protocol::push(
                    "lobby_joiner_left",
                    json!({"lobby_id": join.lobby_id, "join_id": join_id, "nickname": join.joiner_nickname, "reason": "disconnected", "pending": true}),
                );
                self.send(join.host, text);
            }
        }
        abandoned
    }

    /// Closes a lobby: the joiner learns why, pending joins are rejected,
    /// and a running match id is handed back for abandonment.
    pub fn close_lobby(&mut self, lobby_id: &str, reason: &str) -> Vec<i64> {
        let Some(lobby) = self.lobbies.remove(lobby_id) else { return Vec::new() };
        if let Some(joiner) = &lobby.joiner {
            let text = protocol::push("lobby_closed", json!({"lobby_id": lobby.id, "reason": reason}));
            self.send(joiner.session, text);
            if let Some(session) = self.sessions.get_mut(&joiner.session) {
                session.presence = Presence::Idle;
            }
        }
        if let Some(host) = self.sessions.get_mut(&lobby.host) {
            if matches!(host.presence, Presence::Hosting(_) | Presence::InMatch { .. }) {
                host.presence = Presence::Idle;
            }
        }
        let pending: Vec<u64> = self
            .pending_joins
            .values()
            .filter(|join| join.lobby_id == lobby_id)
            .map(|join| join.join_id)
            .collect();
        for join_id in pending {
            if let Some(join) = self.pending_joins.remove(&join_id) {
                let text = protocol::push(
                    "lobby_join_rejected",
                    json!({"join_id": join_id, "lobby_id": lobby_id, "reason": reason}),
                );
                self.send(join.joiner, text);
            }
        }
        self.broadcast_registered(&protocol::push("lobby_list_changed", json!({})));
        lobby.match_id.into_iter().collect()
    }

    /// The joiner left (or dropped): the seat frees, the host is told, and
    /// an in-progress match keeps its state so a replacement can join.
    pub fn joiner_left(&mut self, lobby_id: &str, reason: &str) {
        let Some(lobby) = self.lobbies.get_mut(lobby_id) else { return };
        let Some(joiner) = lobby.joiner.take() else { return };
        if lobby.state == LobbyState::Full {
            lobby.state = LobbyState::Open;
        }
        let host = lobby.host;
        let text = protocol::push(
            "lobby_joiner_left",
            json!({"lobby_id": lobby_id, "nickname": joiner.nickname, "reason": reason}),
        );
        self.send(host, text);
        if let Some(session) = self.sessions.get_mut(&joiner.session) {
            if matches!(session.presence, Presence::Joined(_)) {
                session.presence = Presence::Idle;
            }
        }
        self.broadcast_registered(&protocol::push("lobby_list_changed", json!({})));
    }

    pub fn registered_count(&self) -> usize {
        self.sessions.values().filter(|s| s.account.is_some()).count()
    }
}

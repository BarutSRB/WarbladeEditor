//! The WebSocket JSON protocol: envelope, error codes, limits, and field
//! validators. The Godot mirror is src/online/lobby_contract.gd — keep them
//! in step.
//!
//! Request:  {"t": <type>, "rid": <n>, ...fields}
//! Response: {"t": <type>, "rid": <n>, "ok": true, ...fields}
//!        or {"t": <type>, "rid": <n>, "ok": false, "error": {"code", "message"}}
//! Push:     {"t": <type>, ...fields} (no rid)

use std::net::Ipv4Addr;

use serde_json::{json, Map, Value};

pub const PROTOCOL_VERSION: u64 = 1;
pub const MAX_FRAME_BYTES: usize = 16 * 1024;

pub mod limits {
    pub const NICKNAME_MIN: usize = 3;
    pub const NICKNAME_MAX: usize = 16;
    pub const CHAT_MAX_CHARS: usize = 200;
    pub const CHAT_MAX_BYTES: usize = 800;
    pub const LOBBY_NAME_MAX: usize = 32;
    pub const GAME_TOKEN_MAX: usize = 64;
    pub const HISTORY_PAGE: usize = 50;
    pub const HISTORY_MAX: usize = 100;
    pub const PING_INTERVAL_SEC: u64 = 20;
    pub const IDLE_TIMEOUT_SEC: u64 = 60;
    pub const HELLO_TIMEOUT_SEC: u64 = 10;
    pub const AUTH_TIMEOUT_SEC: u64 = 30;
    pub const JOIN_ANSWER_TIMEOUT_SEC: u64 = 15;
    pub const RENDEZVOUS_KEEPALIVE_SEC: u64 = 15;
    pub const RENDEZVOUS_FRESH_SEC: u64 = 45;
    pub const RENDEZVOUS_EXPIRE_SEC: u64 = 120;
    pub const MAX_MALFORMED: u32 = 5;
    pub const OUTBOUND_QUEUE: usize = 64;
    pub const MAX_POINTS_PER_MATCH: i64 = 250;
    pub const MAX_SCORE: i64 = 50_000_000;
    pub const MAX_LEVEL: i64 = 3999;
    pub const CHAT_RETENTION_ROWS: i64 = 5000;
    pub const OPEN_MATCH_ABANDON_SEC: i64 = 6 * 3600;
    pub const CLOSE_SHUTDOWN: u16 = 1001;
    pub const CLOSE_PROTOCOL: u16 = 4000;
    pub const CLOSE_HANDSHAKE_TIMEOUT: u16 = 4001;
    pub const CLOSE_KICKED: u16 = 4002;
    pub const CLOSE_IDLE: u16 = 4003;
    pub const CLOSE_FULL: u16 = 4004;
    pub const CLOSE_ABUSE: u16 = 4005;
}

pub const MODES: &[&str] = &["solo", "coop", "time_trial"];
pub const DIFFICULTIES: &[&str] = &["easy", "normal", "hard", "ace"];
pub const BALANCES: &[&str] = &["classic", "balanced"];
pub const MATCH_KINDS: &[&str] = &["solo", "couch", "hosted"];
pub const MATCH_RESULTS: &[&str] = &["completed", "game_over", "retired", "disconnected"];

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ErrorCode {
    NotAuthenticated,
    NotRegistered,
    RateLimited,
    SchemaMismatch,
    ProtocolMismatch,
    ContentMismatch,
    InvalidNickname,
    NicknameTaken,
    AccountDisabled,
    ServerFull,
    LobbyNotFound,
    LobbyNotOpen,
    LobbyLimit,
    AlreadyInLobby,
    NotInLobby,
    NotLobbyHost,
    SelfJoin,
    JoinNotPending,
    RendezvousNotObserved,
    HostUnreachable,
    MatchNotFound,
    NotHostedMatch,
    TalentUnknownNode,
    TalentAlreadyOwned,
    TalentPrereqMissing,
    InsufficientPoints,
    RespecCooldown,
    Internal,
}

impl ErrorCode {
    pub fn as_str(self) -> &'static str {
        match self {
            ErrorCode::NotAuthenticated => "NOT_AUTHENTICATED",
            ErrorCode::NotRegistered => "NOT_REGISTERED",
            ErrorCode::RateLimited => "RATE_LIMITED",
            ErrorCode::SchemaMismatch => "SCHEMA_MISMATCH",
            ErrorCode::ProtocolMismatch => "PROTOCOL_MISMATCH",
            ErrorCode::ContentMismatch => "CONTENT_MISMATCH",
            ErrorCode::InvalidNickname => "INVALID_NICKNAME",
            ErrorCode::NicknameTaken => "NICKNAME_TAKEN",
            ErrorCode::AccountDisabled => "ACCOUNT_DISABLED",
            ErrorCode::ServerFull => "SERVER_FULL",
            ErrorCode::LobbyNotFound => "LOBBY_NOT_FOUND",
            ErrorCode::LobbyNotOpen => "LOBBY_NOT_OPEN",
            ErrorCode::LobbyLimit => "LOBBY_LIMIT",
            ErrorCode::AlreadyInLobby => "ALREADY_IN_LOBBY",
            ErrorCode::NotInLobby => "NOT_IN_LOBBY",
            ErrorCode::NotLobbyHost => "NOT_LOBBY_HOST",
            ErrorCode::SelfJoin => "SELF_JOIN",
            ErrorCode::JoinNotPending => "JOIN_NOT_PENDING",
            ErrorCode::RendezvousNotObserved => "RENDEZVOUS_NOT_OBSERVED",
            ErrorCode::HostUnreachable => "HOST_UNREACHABLE",
            ErrorCode::MatchNotFound => "MATCH_NOT_FOUND",
            ErrorCode::NotHostedMatch => "NOT_HOSTED_MATCH",
            ErrorCode::TalentUnknownNode => "TALENT_UNKNOWN_NODE",
            ErrorCode::TalentAlreadyOwned => "TALENT_ALREADY_OWNED",
            ErrorCode::TalentPrereqMissing => "TALENT_PREREQ_MISSING",
            ErrorCode::InsufficientPoints => "INSUFFICIENT_POINTS",
            ErrorCode::RespecCooldown => "RESPEC_COOLDOWN",
            ErrorCode::Internal => "INTERNAL",
        }
    }
}

#[derive(Debug, Clone)]
pub struct ApiError {
    pub code: ErrorCode,
    pub message: String,
    pub extra: Map<String, Value>,
}

impl ApiError {
    pub fn new(code: ErrorCode, message: impl Into<String>) -> ApiError {
        ApiError { code, message: message.into(), extra: Map::new() }
    }

    pub fn with(mut self, key: &str, value: Value) -> ApiError {
        self.extra.insert(key.to_string(), value);
        self
    }

    pub fn schema(message: impl Into<String>) -> ApiError {
        ApiError::new(ErrorCode::SchemaMismatch, message)
    }

    pub fn internal(message: impl Into<String>) -> ApiError {
        ApiError::new(ErrorCode::Internal, message)
    }

    pub fn to_json(&self) -> Value {
        let mut error = Map::new();
        error.insert("code".into(), Value::String(self.code.as_str().to_string()));
        error.insert("message".into(), Value::String(self.message.clone()));
        for (key, value) in &self.extra {
            error.insert(key.clone(), value.clone());
        }
        Value::Object(error)
    }
}

impl From<rusqlite::Error> for ApiError {
    fn from(error: rusqlite::Error) -> ApiError {
        tracing::error!("database error: {error}");
        ApiError::internal("database error")
    }
}

pub type ApiResult = Result<Value, ApiError>;

pub fn response_ok(t: &str, rid: u64, fields: Value) -> String {
    let mut object = Map::new();
    object.insert("t".into(), Value::String(t.to_string()));
    object.insert("rid".into(), Value::from(rid));
    object.insert("ok".into(), Value::Bool(true));
    if let Value::Object(extra) = fields {
        for (key, value) in extra {
            object.insert(key, value);
        }
    }
    Value::Object(object).to_string()
}

pub fn response_error(t: &str, rid: Option<u64>, error: &ApiError) -> String {
    let mut object = Map::new();
    object.insert("t".into(), Value::String(t.to_string()));
    if let Some(rid) = rid {
        object.insert("rid".into(), Value::from(rid));
    }
    object.insert("ok".into(), Value::Bool(false));
    object.insert("error".into(), error.to_json());
    Value::Object(object).to_string()
}

pub fn push(t: &str, fields: Value) -> String {
    let mut object = Map::new();
    object.insert("t".into(), Value::String(t.to_string()));
    if let Value::Object(extra) = fields {
        for (key, value) in extra {
            object.insert(key, value);
        }
    }
    Value::Object(object).to_string()
}

// ---------------------------------------------------------------- endpoints

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Endpoint {
    pub ip: Ipv4Addr,
    pub port: u16,
}

impl Endpoint {
    pub fn to_json(self) -> Value {
        json!({"ip": self.ip.to_string(), "port": self.port})
    }
}

pub fn endpoint_json(endpoint: Option<Endpoint>) -> Value {
    endpoint.map(Endpoint::to_json).unwrap_or(Value::Null)
}

// --------------------------------------------------------------- validators

pub fn is_hex(value: &str, len: usize) -> bool {
    value.len() == len && value.bytes().all(|b| b.is_ascii_hexdigit())
}

pub fn is_valid_nickname(name: &str) -> bool {
    let len = name.chars().count();
    len >= limits::NICKNAME_MIN
        && len <= limits::NICKNAME_MAX
        && name.chars().all(|c| c.is_ascii_alphanumeric() || c == '_')
}

pub fn field_str<'a>(value: &'a Value, key: &str) -> Option<&'a str> {
    value.get(key).and_then(Value::as_str)
}

/// A required string field, trimmed and bounded by character count.
pub fn field_string(value: &Value, key: &str, max_chars: usize) -> Result<String, ApiError> {
    match value.get(key) {
        Some(Value::String(text)) => {
            let trimmed = text.trim();
            if trimmed.chars().count() > max_chars {
                return Err(ApiError::schema(format!("{key} is longer than {max_chars} characters")));
            }
            Ok(trimmed.to_string())
        }
        _ => Err(ApiError::schema(format!("{key} must be a string"))),
    }
}

/// An optional string field; absent or null yields None.
pub fn field_string_opt(value: &Value, key: &str, max_chars: usize) -> Result<Option<String>, ApiError> {
    match value.get(key) {
        None | Some(Value::Null) => Ok(None),
        Some(_) => field_string(value, key, max_chars).map(Some),
    }
}

pub fn field_i64(value: &Value, key: &str) -> Result<i64, ApiError> {
    match value.get(key) {
        Some(Value::Number(number)) => number
            .as_i64()
            .or_else(|| number.as_f64().map(|f| f as i64))
            .ok_or_else(|| ApiError::schema(format!("{key} must be an integer"))),
        _ => Err(ApiError::schema(format!("{key} must be an integer"))),
    }
}

pub fn field_i64_opt(value: &Value, key: &str) -> Result<Option<i64>, ApiError> {
    match value.get(key) {
        None | Some(Value::Null) => Ok(None),
        Some(_) => field_i64(value, key).map(Some),
    }
}

pub fn field_i64_or(value: &Value, key: &str, default: i64) -> Result<i64, ApiError> {
    Ok(field_i64_opt(value, key)?.unwrap_or(default))
}

pub fn field_bool(value: &Value, key: &str, default: bool) -> bool {
    match value.get(key) {
        Some(Value::Bool(flag)) => *flag,
        Some(Value::Number(number)) => number.as_i64().unwrap_or(0) != 0,
        _ => default,
    }
}

pub fn field_choice(value: &Value, key: &str, allowed: &[&str]) -> Result<String, ApiError> {
    let choice = field_string(value, key, 32)?;
    if allowed.contains(&choice.as_str()) {
        Ok(choice)
    } else {
        Err(ApiError::schema(format!("{key} must be one of {}", allowed.join("/"))))
    }
}

pub fn field_port(value: &Value, key: &str) -> Result<u16, ApiError> {
    let port = field_i64(value, key)?;
    if (1024..=65535).contains(&port) {
        Ok(port as u16)
    } else {
        Err(ApiError::schema(format!("{key} must be 1024-65535")))
    }
}

/// An optional {"ip": "a.b.c.d", "port": n} object (IPv4 only in v1).
pub fn field_endpoint(value: &Value, key: &str) -> Result<Option<Endpoint>, ApiError> {
    let Some(object) = value.get(key) else { return Ok(None) };
    if object.is_null() {
        return Ok(None);
    }
    let ip_text = field_str(object, "ip").ok_or_else(|| ApiError::schema(format!("{key}.ip must be a string")))?;
    let ip = ip_text
        .parse::<Ipv4Addr>()
        .map_err(|_| ApiError::schema(format!("{key}.ip must be an IPv4 address")))?;
    let port = field_i64(object, "port")?;
    if !(1..=65535).contains(&port) {
        return Err(ApiError::schema(format!("{key}.port must be 1-65535")));
    }
    Ok(Some(Endpoint { ip, port: port as u16 }))
}

/// Chat and lobby text: printable, no control characters.
pub fn has_control_chars(text: &str) -> bool {
    text.chars().any(|c| c.is_control())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn nickname_rules() {
        for good in ["abc", "Pilot_9", "A_B_C_D_E_F_G_H_"] {
            assert!(is_valid_nickname(good), "{good} should pass");
        }
        for bad in ["ab", "seventeen_chars__", "h\u{e9}llo", "a-b", "a b", ""] {
            assert!(!is_valid_nickname(bad), "{bad} should fail");
        }
    }

    #[test]
    fn envelope_shapes() {
        let ok = response_ok("ping", 3, json!({"server_time": 1}));
        let parsed: Value = serde_json::from_str(&ok).unwrap();
        assert_eq!(parsed["t"], "ping");
        assert_eq!(parsed["rid"], 3);
        assert_eq!(parsed["ok"], true);
        assert_eq!(parsed["server_time"], 1);
        let err = response_error("auth", Some(4), &ApiError::new(ErrorCode::NotAuthenticated, "nope"));
        let parsed: Value = serde_json::from_str(&err).unwrap();
        assert_eq!(parsed["ok"], false);
        assert_eq!(parsed["error"]["code"], "NOT_AUTHENTICATED");
        assert_eq!(parsed["error"]["message"], "nope");
        let pushed = push("notice", json!({"message": "hi"}));
        let parsed: Value = serde_json::from_str(&pushed).unwrap();
        assert!(parsed.get("rid").is_none());
        assert_eq!(parsed["message"], "hi");
    }

    #[test]
    fn field_validators() {
        let value = json!({"name": "  SMOKE ", "port": 42000, "lan": {"ip": "192.168.1.9", "port": 42000}, "flag": true});
        assert_eq!(field_string(&value, "name", 32).unwrap(), "SMOKE");
        assert!(field_string(&value, "name", 3).is_err());
        assert!(field_string(&value, "missing", 3).is_err());
        assert_eq!(field_port(&value, "port").unwrap(), 42000);
        let endpoint = field_endpoint(&value, "lan").unwrap().unwrap();
        assert_eq!(endpoint.port, 42000);
        assert_eq!(endpoint.ip.to_string(), "192.168.1.9");
        assert!(field_endpoint(&value, "none").unwrap().is_none());
        assert!(field_bool(&value, "flag", false));
        assert!(field_choice(&value, "name", MODES).is_err());
        assert!(is_hex("ab".repeat(32).as_str(), 64));
        assert!(!is_hex("zz".repeat(32).as_str(), 64));
    }
}

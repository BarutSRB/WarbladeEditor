class_name WBLobbyContract
extends RefCounted

## Shared constants for the lobby server protocol (WebSocket + JSON). The
## Rust counterpart lives in lobby-server/src/protocol.rs — keep them in step.
## Every request carries {"t": <type>, "rid": <n>, ...}; a response echoes the
## rid with "ok" and either payload fields or {"error": {"code", "message"}};
## pushes carry no rid.

const PROTOCOL_VERSION := 1

## Request types (client -> server).
const T_HELLO := "hello"
const T_AUTH := "auth"
const T_REGISTER := "register"
const T_SET_NICKNAME := "set_nickname"
const T_PING := "ping"
const T_RENDEZVOUS_REGISTER := "rendezvous_register"
const T_LOBBY_CREATE := "lobby_create"
const T_LOBBY_UPDATE := "lobby_update"
const T_LOBBY_CLOSE := "lobby_close"
const T_LOBBY_LIST := "lobby_list"
const T_LOBBY_JOIN_REQUEST := "lobby_join_request"
const T_LOBBY_JOIN_ANSWER := "lobby_join_answer"
const T_LOBBY_LEAVE := "lobby_leave"
const T_CHAT_SEND := "chat_send"
const T_CHAT_HISTORY := "chat_history"
const T_TALENT_STATE := "talent_state"
const T_TALENT_SPEND := "talent_spend"
const T_TALENT_RESPEC := "talent_respec"
const T_MATCH_START := "match_start"
const T_MATCH_END := "match_end"

## Push types (server -> client, no rid).
const PUSH_RENDEZVOUS_OBSERVED := "rendezvous_observed"
const PUSH_LOBBY_JOIN_OFFER := "lobby_join_offer"
const PUSH_LOBBY_JOIN_READY := "lobby_join_ready"
const PUSH_LOBBY_JOIN_REJECTED := "lobby_join_rejected"
const PUSH_LOBBY_JOINER_LEFT := "lobby_joiner_left"
const PUSH_LOBBY_CLOSED := "lobby_closed"
const PUSH_LOBBY_UPDATED := "lobby_updated"
const PUSH_LOBBY_LIST_CHANGED := "lobby_list_changed"
const PUSH_CHAT_MESSAGE := "chat_message"
const PUSH_POINTS_CREDITED := "points_credited"
const PUSH_KICKED := "kicked"
const PUSH_NOTICE := "notice"

## Stable error codes carried in the JSON envelope.
const ERR_NOT_AUTHENTICATED := "NOT_AUTHENTICATED"
const ERR_NOT_REGISTERED := "NOT_REGISTERED"
const ERR_RATE_LIMITED := "RATE_LIMITED"
const ERR_SCHEMA_MISMATCH := "SCHEMA_MISMATCH"
const ERR_PROTOCOL_MISMATCH := "PROTOCOL_MISMATCH"
const ERR_CONTENT_MISMATCH := "CONTENT_MISMATCH"
const ERR_INVALID_NICKNAME := "INVALID_NICKNAME"
const ERR_NICKNAME_TAKEN := "NICKNAME_TAKEN"
const ERR_SERVER_FULL := "SERVER_FULL"
const ERR_LOBBY_NOT_FOUND := "LOBBY_NOT_FOUND"
const ERR_LOBBY_NOT_OPEN := "LOBBY_NOT_OPEN"
const ERR_LOBBY_LIMIT := "LOBBY_LIMIT"
const ERR_ALREADY_IN_LOBBY := "ALREADY_IN_LOBBY"
const ERR_NOT_IN_LOBBY := "NOT_IN_LOBBY"
const ERR_NOT_LOBBY_HOST := "NOT_LOBBY_HOST"
const ERR_SELF_JOIN := "SELF_JOIN"
const ERR_JOIN_NOT_PENDING := "JOIN_NOT_PENDING"
const ERR_RENDEZVOUS_NOT_OBSERVED := "RENDEZVOUS_NOT_OBSERVED"
const ERR_HOST_UNREACHABLE := "HOST_UNREACHABLE"
const ERR_MATCH_NOT_FOUND := "MATCH_NOT_FOUND"
const ERR_NOT_HOSTED_MATCH := "NOT_HOSTED_MATCH"
const ERR_TALENT_UNKNOWN_NODE := "TALENT_UNKNOWN_NODE"
const ERR_TALENT_ALREADY_OWNED := "TALENT_ALREADY_OWNED"
const ERR_TALENT_PREREQ_MISSING := "TALENT_PREREQ_MISSING"
const ERR_INSUFFICIENT_POINTS := "INSUFFICIENT_POINTS"
const ERR_RESPEC_COOLDOWN := "RESPEC_COOLDOWN"
const ERR_INTERNAL := "INTERNAL"
## Client-side only: the socket is not connected / the server did not answer.
const ERR_OFFLINE := "OFFLINE"
const ERR_UNREACHABLE := "UNREACHABLE"
const ERR_TIMEOUT := "TIMEOUT"

## Limits mirrored from the server.
const NICKNAME_MIN_CHARS := 3
const NICKNAME_MAX_CHARS := 16
const CHAT_MAX_CHARS := 200
const LOBBY_NAME_MAX_CHARS := 32
const CHAT_HISTORY_PAGE := 50
const DEFAULT_WS_PORT := 7400
const DEFAULT_UDP_PORT := 7401
const DEFAULT_HOST_PORT := 42000
const PING_INTERVAL_SEC := 20.0
const REQUEST_TIMEOUT_SEC := 8.0
const CONNECT_TIMEOUT_SEC := 6.0
const RECONNECT_BACKOFF_SEC := [1.0, 2.0, 4.0, 8.0, 16.0, 30.0]


static func error_result(code: String, message: String) -> Dictionary:
	return {"ok": false, "error": {"code": code, "message": message}}


static func error_code(result: Dictionary) -> String:
	var error_value: Variant = result.get("error", {})
	if error_value is Dictionary:
		return str((error_value as Dictionary).get("code", ""))
	return ""


## Nicknames are 3-16 characters of [A-Za-z0-9_]; uniqueness is case-insensitive
## and decided by the server.
static func is_valid_nickname(name: String) -> bool:
	if name.length() < NICKNAME_MIN_CHARS or name.length() > NICKNAME_MAX_CHARS:
		return false
	for character in name:
		if not "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_".contains(character):
			return false
	return true


static func ws_url(host: String, port: int) -> String:
	return "ws://%s:%d/ws" % [host, port]


## Reconnect delay for the given attempt index (0-based), capped at the last
## entry of RECONNECT_BACKOFF_SEC.
static func backoff_seconds(attempt: int) -> float:
	var index := clampi(attempt, 0, RECONNECT_BACKOFF_SEC.size() - 1)
	return float(RECONNECT_BACKOFF_SEC[index])

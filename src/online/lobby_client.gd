class_name WBLobbyClient
extends Node

## The client seam to the lobby server: identity, lobby list, global chat,
## talents, and match reports over one WebSocket carrying JSON envelopes
## (see WBLobbyContract). Every call returns {"ok": bool, ...} and never
## throws; failures carry {"error": {"code": <stable>, "message": <text>}}.
## Solo and couch play never depend on it — while offline every request
## answers ERR_OFFLINE and the cached profile state keeps feeding grants.
## The socket reconnects with backoff until disconnect_now(); a fresh socket
## replays hello + auth before the client reports itself online.
## WBFakeLobbyClient is the deterministic in-memory double for tests and
## --fake-lobby runs.

signal state_changed(state: String)
signal profile_state_updated(state: Dictionary)
signal points_credited(amount: int, reason: String)
signal request_failed(operation: String, error: Dictionary)
signal chat_message(message: Dictionary)
signal lobby_list_changed()
signal lobby_join_offer(offer: Dictionary)
signal lobby_join_ready(info: Dictionary)
signal lobby_join_rejected(info: Dictionary)
signal lobby_joiner_left(info: Dictionary)
signal lobby_closed(info: Dictionary)
signal lobby_updated(lobby: Dictionary)
signal rendezvous_observed(info: Dictionary)
signal kicked(reason: String)
signal notice(message: Dictionary)

const STATE_OFFLINE := "offline"
const STATE_CONNECTING := "connecting"
const STATE_ONLINE := "online"


## One in-flight request; the awaiting caller resumes on `completed`.
class PendingRequest:
	extends RefCounted
	signal completed(response: Dictionary)
	var type := ""
	var deadline_usec := 0


## Cached copy of the last talent/profile state (empty until fetched or seeded).
var profile_state: Dictionary = {}

var _identity: WBIdentityStore = null
var _cache: WBTalentCache = null
var _host := ""
var _port := WBLobbyContract.DEFAULT_WS_PORT
var _udp_port := WBLobbyContract.DEFAULT_UDP_PORT
var _content_hash := ""
var _client_version := ""
var _state := STATE_OFFLINE
var _wanted := false
var _registered := false
var _nickname := ""
var _account_id := 0
var _server_info: Dictionary = {}
var _socket: WebSocketPeer = null
var _pending: Dictionary = {}
var _next_rid := 1
var _handshake_stage := ""
var _connect_started_usec := 0
var _reconnect_attempt := 0
var _reconnect_deadline_usec := 0
var _last_ping_usec := 0
var _last_drop_reason := ""


func configure(
	identity: WBIdentityStore,
	host: String,
	port: int,
	udp_port: int = WBLobbyContract.DEFAULT_UDP_PORT,
	cache: WBTalentCache = null
) -> void:
	_identity = identity
	_cache = cache
	_host = host.strip_edges()
	_port = port
	_udp_port = udp_port
	if _identity != null and _identity.has_nickname():
		_nickname = _identity.nickname()


## The compiled-content hash rides the hello so hosts and joiners can be
## matched on identical game content.
func set_content_hash(content_hash: String) -> void:
	_content_hash = content_hash


func set_client_version(version: String) -> void:
	_client_version = version


func host() -> String:
	return _host


func port() -> int:
	return _port


func udp_port() -> int:
	return _udp_port


func is_configured() -> bool:
	return not _host.is_empty() and _port >= 1024 and _port <= 65535


func describe_endpoint() -> String:
	if not is_configured():
		return "NOT CONFIGURED"
	return "%s:%d" % [_host, _port]


## Starts (or resumes) the background connection; the socket reconnects with
## backoff until disconnect_now().
func connect_now() -> void:
	_wanted = true
	_reconnect_attempt = 0
	_reconnect_deadline_usec = 0
	if _socket == null:
		_open_socket()


func disconnect_now() -> void:
	_wanted = false
	_drop_socket("closed by the client")


func state() -> String:
	return _state


func is_online() -> bool:
	return _state == STATE_ONLINE


## Online and bound to a registered nickname.
func is_registered() -> bool:
	return is_online() and _registered


func nickname() -> String:
	return _nickname


func account_id() -> int:
	return _account_id


func server_info() -> Dictionary:
	return _server_info.duplicate(true)


func last_drop_reason() -> String:
	return _last_drop_reason


## Loads a cached profile state at boot without announcing it as fresh.
func seed_profile_state(state: Dictionary) -> void:
	profile_state = state.duplicate(true)


## --- Requests -------------------------------------------------------------

func register_nickname(name: String) -> Dictionary:
	if not WBLobbyContract.is_valid_nickname(name):
		return _fail(
			WBLobbyContract.T_REGISTER,
			WBLobbyContract.ERR_INVALID_NICKNAME,
			"nicknames are 3-16 letters, digits, or underscores"
		)
	var response: Dictionary = await request(WBLobbyContract.T_REGISTER, {"nickname": name})
	if bool(response.get("ok", false)):
		_adopt_account(response)
	return response


func set_nickname(name: String) -> Dictionary:
	if not WBLobbyContract.is_valid_nickname(name):
		return _fail(
			WBLobbyContract.T_SET_NICKNAME,
			WBLobbyContract.ERR_INVALID_NICKNAME,
			"nicknames are 3-16 letters, digits, or underscores"
		)
	var response: Dictionary = await request(WBLobbyContract.T_SET_NICKNAME, {"nickname": name})
	if bool(response.get("ok", false)):
		_adopt_account(response)
	return response


func fetch_profile_state() -> Dictionary:
	var response: Dictionary = await request(WBLobbyContract.T_TALENT_STATE, {})
	if not bool(response.get("ok", false)):
		return response
	_store_profile_state(response.get("state", {}) as Dictionary)
	return {"ok": true, "state": values_profile_state()}


func spend_talent(node_id: String) -> Dictionary:
	var response: Dictionary = await request(
		WBLobbyContract.T_TALENT_SPEND, {"node_id": node_id}
	)
	if bool(response.get("ok", false)) and response.get("state") is Dictionary:
		_store_profile_state(response["state"] as Dictionary)
	return response


func respec() -> Dictionary:
	var response: Dictionary = await request(WBLobbyContract.T_TALENT_RESPEC, {})
	if bool(response.get("ok", false)) and response.get("state") is Dictionary:
		_store_profile_state(response["state"] as Dictionary)
	return response


func list_lobbies(query: String = "") -> Dictionary:
	return await request(WBLobbyContract.T_LOBBY_LIST, {"query": query})


func create_lobby(fields: Dictionary) -> Dictionary:
	return await request(WBLobbyContract.T_LOBBY_CREATE, fields)


func update_lobby(lobby_id: String, fields: Dictionary) -> Dictionary:
	return await request(WBLobbyContract.T_LOBBY_UPDATE, fields.merged({"lobby_id": lobby_id}))


func close_lobby(lobby_id: String) -> Dictionary:
	return await request(WBLobbyContract.T_LOBBY_CLOSE, {"lobby_id": lobby_id})


func request_join(lobby_id: String, fields: Dictionary = {}) -> Dictionary:
	return await request(
		WBLobbyContract.T_LOBBY_JOIN_REQUEST, fields.merged({"lobby_id": lobby_id})
	)


func answer_join(join_id: int, accept: bool, reason: String = "") -> Dictionary:
	return await request(WBLobbyContract.T_LOBBY_JOIN_ANSWER, {
		"join_id": join_id,
		"accept": accept,
		"reason": reason,
	})


func leave_lobby() -> Dictionary:
	return await request(WBLobbyContract.T_LOBBY_LEAVE, {})


func register_rendezvous(nonce: String) -> Dictionary:
	return await request(WBLobbyContract.T_RENDEZVOUS_REGISTER, {"nonce": nonce})


func send_chat(body: String) -> Dictionary:
	var text := body.strip_edges()
	if text.is_empty() or text.length() > WBLobbyContract.CHAT_MAX_CHARS:
		return _fail(
			WBLobbyContract.T_CHAT_SEND,
			WBLobbyContract.ERR_SCHEMA_MISMATCH,
			"chat messages are 1-%d characters" % WBLobbyContract.CHAT_MAX_CHARS
		)
	return await request(WBLobbyContract.T_CHAT_SEND, {"body": text})


func chat_history(before_id: int = 0, limit: int = WBLobbyContract.CHAT_HISTORY_PAGE) -> Dictionary:
	var payload := {"limit": clampi(limit, 1, 100)}
	if before_id > 0:
		payload["before_id"] = before_id
	return await request(WBLobbyContract.T_CHAT_HISTORY, payload)


func report_match_start(fields: Dictionary) -> Dictionary:
	return await request(WBLobbyContract.T_MATCH_START, fields)


## A finished run: the reply carries the points the server credited and the
## refreshed talent state.
func report_match_end(fields: Dictionary) -> Dictionary:
	var response: Dictionary = await request(WBLobbyContract.T_MATCH_END, fields)
	if not bool(response.get("ok", false)):
		return response
	if response.get("state") is Dictionary:
		_store_profile_state(response["state"] as Dictionary)
	var awarded := int(response.get("points_awarded", 0))
	if awarded > 0:
		points_credited.emit(awarded, "match_end")
	return response


func ping() -> Dictionary:
	return await request(WBLobbyContract.T_PING, {
		"client_time": int(Time.get_unix_time_from_system()),
	})


## Sends one request and returns its response, resuming the caller when the
## matching rid arrives (or the request times out / the socket drops).
func request(type: String, payload: Dictionary) -> Dictionary:
	if _socket == null or _socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		return _fail(type, WBLobbyContract.ERR_OFFLINE, "the lobby server is not connected")
	var rid := _next_rid
	_next_rid += 1
	var message := payload.duplicate(true)
	message["t"] = type
	message["rid"] = rid
	var error := _socket.send_text(JSON.stringify(message))
	if error != OK:
		return _fail(type, WBLobbyContract.ERR_UNREACHABLE, "the lobby socket refused the request")
	var handle := PendingRequest.new()
	handle.type = type
	handle.deadline_usec = Time.get_ticks_usec() + int(WBLobbyContract.REQUEST_TIMEOUT_SEC * 1_000_000.0)
	_pending[rid] = handle
	var response: Dictionary = await handle.completed
	if not bool(response.get("ok", false)):
		var error_value: Variant = response.get("error", {})
		request_failed.emit(type, error_value if error_value is Dictionary else {})
	return response


## --- Socket lifecycle ----------------------------------------------------

func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _socket == null:
		if _wanted and is_configured() and now >= _reconnect_deadline_usec:
			_open_socket()
		return
	_socket.poll()
	# Drain queued frames before acting on the state: a server that pushes a
	# final message (kicked, notice) and closes right away leaves both queued
	# at once, and the message must not be lost with the socket.
	while _socket != null and _socket.get_available_packet_count() > 0:
		var packet := _socket.get_packet()
		if _socket.was_string_packet():
			_handle_socket_text(packet.get_string_from_utf8())
	if _socket == null:
		return
	match _socket.get_ready_state():
		WebSocketPeer.STATE_CONNECTING:
			if now - _connect_started_usec > int(WBLobbyContract.CONNECT_TIMEOUT_SEC * 1_000_000.0):
				_drop_socket("the lobby server did not answer")
		WebSocketPeer.STATE_OPEN:
			if _handshake_stage.is_empty():
				_begin_handshake()
			_expire_pending(now)
			if (
				_socket != null
				and _handshake_stage == "done"
				and now - _last_ping_usec > int(WBLobbyContract.PING_INTERVAL_SEC * 1_000_000.0)
			):
				_last_ping_usec = now
				ping()
		WebSocketPeer.STATE_CLOSING:
			pass
		WebSocketPeer.STATE_CLOSED:
			var code := _socket.get_close_code()
			var reason := _socket.get_close_reason()
			_drop_socket("connection closed (%d %s)" % [code, reason])


func _open_socket() -> void:
	if not is_configured():
		return
	_socket = WebSocketPeer.new()
	_handshake_stage = ""
	_connect_started_usec = Time.get_ticks_usec()
	var error := _socket.connect_to_url(WBLobbyContract.ws_url(_host, _port))
	if error != OK:
		_socket = null
		_schedule_reconnect()
		return
	_set_state(STATE_CONNECTING)


func _drop_socket(reason: String) -> void:
	_last_drop_reason = reason
	if _socket != null:
		if _socket.get_ready_state() in [WebSocketPeer.STATE_CONNECTING, WebSocketPeer.STATE_OPEN]:
			_socket.close(1000, "bye")
		_socket = null
	_handshake_stage = ""
	_fail_all_pending(WBLobbyContract.ERR_UNREACHABLE, reason)
	_registered = false
	_set_state(STATE_OFFLINE)
	if _wanted:
		_schedule_reconnect()


func _schedule_reconnect() -> void:
	var delay := WBLobbyContract.backoff_seconds(_reconnect_attempt)
	_reconnect_attempt += 1
	_reconnect_deadline_usec = Time.get_ticks_usec() + int(delay * 1_000_000.0)


## hello then auth; only a finished handshake reports the client online.
func _begin_handshake() -> void:
	_handshake_stage = "hello"
	var hello: Dictionary = await request(WBLobbyContract.T_HELLO, {
		"protocol": WBLobbyContract.PROTOCOL_VERSION,
		"content_hash": _content_hash,
		"client_version": _client_version,
		"platform": OS.get_name().to_lower(),
	})
	if not bool(hello.get("ok", false)):
		if WBLobbyContract.error_code(hello) == WBLobbyContract.ERR_PROTOCOL_MISMATCH:
			# Reconnecting cannot help until the game is updated.
			_wanted = false
			notice.emit({"kind": "protocol", "message": "this game version cannot talk to the lobby server"})
		_drop_socket("hello rejected")
		return
	if _socket == null:
		return
	_server_info = hello
	_handshake_stage = "auth"
	var auth: Dictionary = await request(WBLobbyContract.T_AUTH, {
		"device_key": _identity.device_key() if _identity != null else "",
	})
	if not bool(auth.get("ok", false)):
		_drop_socket("auth rejected")
		return
	if _socket == null:
		return
	_handshake_stage = "done"
	_reconnect_attempt = 0
	_last_ping_usec = Time.get_ticks_usec()
	if bool(auth.get("registered", false)):
		_adopt_account(auth)
	else:
		_registered = false
	_set_state(STATE_ONLINE)


func _handle_socket_text(text: String) -> void:
	var parsed: Variant = JSON.parse_string(text)
	if not parsed is Dictionary:
		return
	var message := parsed as Dictionary
	if message.has("rid"):
		var rid := int(message.get("rid", 0))
		if _pending.has(rid):
			var handle: PendingRequest = _pending[rid]
			_pending.erase(rid)
			handle.completed.emit(message)
		return
	_handle_push(message)


func _expire_pending(now_usec: int) -> void:
	var expired: Array = []
	for rid: Variant in _pending.keys():
		if int((_pending[rid] as PendingRequest).deadline_usec) <= now_usec:
			expired.append(rid)
	for rid: Variant in expired:
		var handle: PendingRequest = _pending[rid]
		_pending.erase(rid)
		handle.completed.emit(WBLobbyContract.error_result(
			WBLobbyContract.ERR_TIMEOUT, "the lobby server did not answer " + handle.type
		))


func _fail_all_pending(code: String, message: String) -> void:
	var handles: Array = _pending.values()
	_pending.clear()
	for handle_value: Variant in handles:
		var handle: PendingRequest = handle_value
		handle.completed.emit(WBLobbyContract.error_result(code, message))


## --- Profile state helpers -----------------------------------------------

## Composed grants for the bound account: {start_state, starting_rockets,
## shop_unlocks}. Empty when nothing is cached.
func current_grants() -> Dictionary:
	var grants: Variant = profile_state.get("grants", {})
	return (grants as Dictionary).duplicate(true) if grants is Dictionary else {}


func current_points() -> int:
	var wallet: Variant = profile_state.get("wallet", {})
	if wallet is Dictionary:
		return int((wallet as Dictionary).get("talent_points", 0))
	return 0


func owned_talents() -> Dictionary:
	var talents: Variant = profile_state.get("talents", {})
	if talents is Dictionary:
		var nodes: Variant = (talents as Dictionary).get("nodes", {})
		if nodes is Dictionary:
			return (nodes as Dictionary).duplicate(true)
	return {}


func values_profile_state() -> Dictionary:
	return profile_state.duplicate(true)


func _store_profile_state(state: Dictionary) -> void:
	profile_state = state.duplicate(true)
	if _cache != null:
		_cache.store_state(profile_state)
	profile_state_updated.emit(values_profile_state())


## Spend/respec deltas carry {talents, grants, wallet}; fold them into the
## cached state so every consumer sees one coherent shape.
func _merge_profile_delta(delta: Dictionary) -> void:
	var merged := profile_state.duplicate(true)
	for key: String in ["talents", "grants", "wallet"]:
		if delta.has(key):
			merged[key] = delta[key]
	_store_profile_state(merged)


## --- Session helpers ------------------------------------------------------

func _set_state(state: String) -> void:
	if state == _state:
		return
	_state = state
	if state != STATE_ONLINE:
		_registered = false
	state_changed.emit(_state)


## A successful auth/register/rename reply binds the account: nickname,
## account id, the identity file, and the talent state that rides along.
func _adopt_account(response: Dictionary) -> void:
	var account_value: Variant = response.get("account", {})
	var account: Dictionary = account_value if account_value is Dictionary else {}
	_nickname = str(account.get("nickname", _nickname))
	_account_id = int(account.get("id", _account_id))
	_registered = not _nickname.is_empty()
	if _identity != null and _identity.nickname() != _nickname:
		_identity.set_nickname(_nickname)
	if response.get("talents") is Dictionary:
		_store_profile_state(response["talents"] as Dictionary)
	state_changed.emit(_state)


func _fail(operation: String, code: String, message: String) -> Dictionary:
	var error := WBLobbyContract.error_result(code, message)
	request_failed.emit(operation, error["error"])
	return error


## Routes a server push to its signal. Shared by the networked client and
## the fake so both raise identical events.
func _handle_push(message: Dictionary) -> void:
	var type := str(message.get("t", ""))
	match type:
		WBLobbyContract.PUSH_CHAT_MESSAGE:
			chat_message.emit(message)
		WBLobbyContract.PUSH_LOBBY_LIST_CHANGED:
			lobby_list_changed.emit()
		WBLobbyContract.PUSH_LOBBY_JOIN_OFFER:
			lobby_join_offer.emit(message)
		WBLobbyContract.PUSH_LOBBY_JOIN_READY:
			lobby_join_ready.emit(message)
		WBLobbyContract.PUSH_LOBBY_JOIN_REJECTED:
			lobby_join_rejected.emit(message)
		WBLobbyContract.PUSH_LOBBY_JOINER_LEFT:
			lobby_joiner_left.emit(message)
		WBLobbyContract.PUSH_LOBBY_CLOSED:
			lobby_closed.emit(message)
		WBLobbyContract.PUSH_LOBBY_UPDATED:
			lobby_updated.emit(message.get("lobby", message) as Dictionary)
		WBLobbyContract.PUSH_RENDEZVOUS_OBSERVED:
			rendezvous_observed.emit(message)
		WBLobbyContract.PUSH_POINTS_CREDITED:
			if message.get("state") is Dictionary:
				_store_profile_state(message["state"] as Dictionary)
			var amount := int(message.get("points", 0))
			if amount > 0:
				points_credited.emit(amount, str(message.get("reason", "push")))
		WBLobbyContract.PUSH_KICKED:
			# Reconnecting would only kick the other session back; stay off
			# until the player asks for a connection again.
			_wanted = false
			kicked.emit(str(message.get("reason", "")))
		WBLobbyContract.PUSH_NOTICE:
			notice.emit(message)

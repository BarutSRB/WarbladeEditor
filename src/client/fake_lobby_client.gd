class_name WBFakeLobbyClient
extends WBLobbyClient

## Deterministic in-memory lobby server for client tests and --fake-lobby
## development runs. Mirrors the server's response shapes and validation
## rules via WBTalentCatalog; it is never a trust path.

var catalog := WBTalentCatalog.new()
var points := 0
var owned: Dictionary = {}
var respec_count := 0
## Lower-case nicknames the fake server already knows (registration fails).
var taken_nicknames: Array[String] = []
var lobbies: Array = []
var chat_log: Array = []
var matches: Array = []
## Forces the next request of this type to fail with ERR_UNREACHABLE (one-shot).
var fail_next_operation := ""
var credit_points_per_match := 7
var _next_id := 1


func _init() -> void:
	catalog.load_catalog()


func connect_now() -> void:
	_wanted = true
	_set_state(STATE_ONLINE)
	# An identity that already carries a nickname authenticates as registered,
	# the way the real auth handshake binds a known device key.
	if _identity != null and _identity.has_nickname() and not _registered:
		_registered = true
		_nickname = _identity.nickname()
		_account_id = 1
		_store_profile_state(_state_snapshot())
		state_changed.emit(_state)


func disconnect_now() -> void:
	_wanted = false
	_set_state(STATE_OFFLINE)


## The fake has no socket; the base class's reconnect loop must stay idle.
func _process(_delta: float) -> void:
	pass


## Dev faucet for tests and --fake-lobby sessions.
func grant_points(amount: int) -> void:
	points += maxi(amount, 0)
	if _registered:
		_store_profile_state(_state_snapshot())


func request(type: String, payload: Dictionary) -> Dictionary:
	if fail_next_operation == type:
		fail_next_operation = ""
		return _fail(type, WBLobbyContract.ERR_UNREACHABLE, "forced test failure")
	if not is_online():
		return _fail(type, WBLobbyContract.ERR_OFFLINE, "the lobby server is not connected")
	match type:
		WBLobbyContract.T_PING:
			return {"ok": true, "server_time": int(Time.get_unix_time_from_system())}
		WBLobbyContract.T_REGISTER, WBLobbyContract.T_SET_NICKNAME:
			return _register(type, str(payload.get("nickname", "")))
		WBLobbyContract.T_TALENT_STATE:
			if not _registered:
				return _fail(type, WBLobbyContract.ERR_NOT_REGISTERED, "set a nickname first")
			return {"ok": true, "state": _state_snapshot()}
		WBLobbyContract.T_TALENT_SPEND:
			return _spend(type, str(payload.get("node_id", "")))
		WBLobbyContract.T_TALENT_RESPEC:
			if not _registered:
				return _fail(type, WBLobbyContract.ERR_NOT_REGISTERED, "set a nickname first")
			points += catalog.spent_total(owned)
			owned = {}
			respec_count += 1
			return {"ok": true, "state": _state_snapshot()}
		WBLobbyContract.T_LOBBY_LIST:
			return {"ok": true, "lobbies": lobbies.duplicate(true)}
		WBLobbyContract.T_LOBBY_CREATE:
			var lobby := payload.duplicate(true)
			lobby["lobby_id"] = "fake-lobby-%d" % _take_id()
			lobby["host_nickname"] = _nickname
			lobby["state"] = "open"
			lobby["player_count"] = 1
			lobby["created_at"] = int(Time.get_unix_time_from_system())
			lobbies.append(lobby)
			return {"ok": true, "lobby": lobby.duplicate(true)}
		WBLobbyContract.T_LOBBY_UPDATE:
			var lobby_id := str(payload.get("lobby_id", ""))
			for lobby_value: Variant in lobbies:
				var lobby := lobby_value as Dictionary
				if str(lobby.get("lobby_id", "")) == lobby_id:
					lobby.merge(payload, true)
					return {"ok": true, "lobby": lobby.duplicate(true)}
			return _fail(type, WBLobbyContract.ERR_LOBBY_NOT_FOUND, "no such lobby")
		WBLobbyContract.T_LOBBY_CLOSE:
			var lobby_id := str(payload.get("lobby_id", ""))
			for index in range(lobbies.size()):
				if str((lobbies[index] as Dictionary).get("lobby_id", "")) == lobby_id:
					lobbies.remove_at(index)
					return {"ok": true}
			return _fail(type, WBLobbyContract.ERR_LOBBY_NOT_FOUND, "no such lobby")
		WBLobbyContract.T_LOBBY_JOIN_REQUEST:
			return {"ok": true, "join_id": _take_id(), "status": "pending"}
		WBLobbyContract.T_LOBBY_JOIN_ANSWER, WBLobbyContract.T_LOBBY_LEAVE:
			return {"ok": true}
		WBLobbyContract.T_RENDEZVOUS_REGISTER:
			return {"ok": true, "observed": {"ip": "127.0.0.1", "port": 42000}}
		WBLobbyContract.T_CHAT_SEND:
			if not _registered:
				return _fail(type, WBLobbyContract.ERR_NOT_REGISTERED, "set a nickname first")
			var message := {
				"t": WBLobbyContract.PUSH_CHAT_MESSAGE,
				"id": _take_id(),
				"account_id": _account_id,
				"nickname": _nickname,
				"body": str(payload.get("body", "")),
				"sent_at": int(Time.get_unix_time_from_system()),
			}
			chat_log.append(message)
			_handle_push(message)
			return {"ok": true, "id": int(message["id"])}
		WBLobbyContract.T_CHAT_HISTORY:
			return {"ok": true, "messages": chat_log.duplicate(true), "has_more": false}
		WBLobbyContract.T_MATCH_START:
			var record := payload.duplicate(true)
			record["match_id"] = _take_id()
			matches.append(record)
			return {"ok": true, "match_id": int(record["match_id"])}
		WBLobbyContract.T_MATCH_END:
			if not _registered:
				return _fail(type, WBLobbyContract.ERR_NOT_REGISTERED, "set a nickname first")
			var record := payload.duplicate(true)
			if int(record.get("match_id", 0)) <= 0:
				record["match_id"] = _take_id()
			record["points_awarded"] = credit_points_per_match
			matches.append(record)
			points += credit_points_per_match
			return {
				"ok": true,
				"match_id": int(record["match_id"]),
				"points_awarded": credit_points_per_match,
				"already_recorded": false,
				"state": _state_snapshot(),
			}
	return _fail(type, WBLobbyContract.ERR_SCHEMA_MISMATCH, "unknown request type " + type)


## Injects a server push (a join offer, a chat line from another player) so
## tests can drive the shell's push handlers.
func push_server_message(message: Dictionary) -> void:
	_handle_push(message)


func _register(type: String, name: String) -> Dictionary:
	if not WBLobbyContract.is_valid_nickname(name):
		return _fail(type, WBLobbyContract.ERR_INVALID_NICKNAME, "invalid nickname")
	if taken_nicknames.has(name.to_lower()):
		return _fail(type, WBLobbyContract.ERR_NICKNAME_TAKEN, "nickname already taken")
	_registered = true
	_nickname = name
	if _account_id == 0:
		_account_id = 1
	return {
		"ok": true,
		"account": {"id": _account_id, "nickname": _nickname},
		"talents": _state_snapshot(),
	}


func _spend(type: String, node_id: String) -> Dictionary:
	if not _registered:
		return _fail(type, WBLobbyContract.ERR_NOT_REGISTERED, "set a nickname first")
	var validated := catalog.validate_spend(owned, node_id)
	if not bool(validated["ok"]):
		request_failed.emit(type, validated["error"])
		return validated
	var cost := int(validated["cost"])
	if points < cost:
		return _fail(type, WBLobbyContract.ERR_INSUFFICIENT_POINTS, "not enough talent points")
	points -= cost
	owned[node_id] = 1
	return {"ok": true, "state": _state_snapshot()}


func _state_snapshot() -> Dictionary:
	return {
		"schema_version": 1,
		"nickname": _nickname,
		"wallet": {"talent_points": points},
		"talents": {
			"nodes": owned.duplicate(true),
			"spent_total": catalog.spent_total(owned),
			"respec_count": respec_count,
			"last_respec_unix": 0,
		},
		"grants": catalog.compose_grants(owned),
		"talent_catalog_version": catalog.version(),
		"points_earned_total": points + catalog.spent_total(owned),
		"server_time_unix": int(Time.get_unix_time_from_system()),
	}


func _take_id() -> int:
	var value := _next_id
	_next_id += 1
	return value

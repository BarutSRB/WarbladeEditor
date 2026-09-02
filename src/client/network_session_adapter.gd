class_name WBNetworkSessionAdapter
extends RefCounted

signal snapshot_received(snapshot: Dictionary)
signal status_changed(status: String)
signal session_failed(message: String)
signal command_acknowledged(request_type: int, accepted: bool, details: Dictionary)
signal replay_ready(replay: Dictionary)
signal replay_failed(reason: String)
signal chat_received(seat_id: int, nickname: String, text: String)
signal punch_acknowledged(accepted: bool, details: Dictionary)

const Protocol := preload("res://src/net/protocol_codec.gd")
const Catalog := preload("res://src/sim/content_catalog.gd")
const MatchContract := preload("res://src/shared/match_contract.gd")

const LOOPBACK_HOST := "127.0.0.1"
const SERVER_PEER_ID := 1
const CONNECT_TIMEOUT_USEC := 12_000_000
const DIAL_PUBLIC_TIMEOUT_SEC := 4.0
const DIAL_LAN_TIMEOUT_SEC := 2.0
const INPUT_REFRESH_TICKS := 6
const HEARTBEAT_INTERVAL_USEC := 1_000_000

var _config: Dictionary = {}
var _content_hash := ""
var _snapshot: Dictionary = {}
var _connections: Array[Dictionary] = []
var _replay_chunks: Dictionary = {}
var _replay_chunk_count := 0
var _replay_total_bytes := 0
var _replay_pending := false
var _input_masks: Array[int] = [0, 0]
var _last_sent_input_masks: Array[int] = [-1, -1]
var _last_sent_input_ticks: Array[int] = [-INPUT_REFRESH_TICKS, -INPUT_REFRESH_TICKS]
var _active := false
var _ready := false
var _failed := false
var _started_at_usec := 0
var _endpoint_host := LOOPBACK_HOST
var _endpoint_port := 0
var _session_token := ""
var _sidecar_pid := 0
var _sidecar_ready_path := ""
var _sidecar_heartbeat_path := ""
var _last_heartbeat_write_usec := 0
var _heartbeat_generation := 0
var _owns_sidecar := false
var _sidecar_shutdown_requested := false
var _requested_seat := 0
var _last_snapshot_tick := -1
var _last_error := ""
var _connection_kind := "local"
var _host_bind_port := 0
var _join_candidates: Array = []
var _join_index := -1
var _join_local_port := 0
var _dialing := false
var _dial_started_usec := 0
var _dial_timeout_usec := 0


## Connection options select the game server by kind:
##   local  (default) spawn the loopback sidecar for solo and couch play
##   direct connect to an explicit host/port/token (manual entry, --connect)
##   host   spawn the sidecar bound publicly on the given port and author the
##          match as seat 0 (online co-op host)
##   join   dial the host's candidate endpoints from a fixed local port and
##          join as seat 1 (online co-op joiner)
func configure(match_config: Dictionary, connection_options: Dictionary = {}) -> bool:
	close()
	_config = match_config.duplicate(true)
	var catalog := Catalog.load_catalog(
		str(_config.get("content_base_path", "res://content")),
		str(_config.get("content_hash", ""))
	)
	if not bool(catalog.get("ok", false)):
		return _fail(str(catalog.get("error", "Unable to validate the local content catalog.")))
	_content_hash = str(catalog.get("content_hash", ""))
	if _content_hash.is_empty():
		return _fail("The local content catalog did not produce a content hash.")

	_started_at_usec = Time.get_ticks_usec()
	_active = true
	_failed = false
	_last_error = ""
	_requested_seat = _resolve_requested_seat(connection_options)
	var kind := str(connection_options.get("kind", ""))
	if kind.is_empty():
		kind = (
			"direct"
			if not str(connection_options.get("host", "")).strip_edges().is_empty()
			else "local"
		)
	_connection_kind = kind
	match kind:
		"direct":
			_endpoint_host = str(connection_options.get("host", "")).strip_edges()
			_endpoint_port = int(connection_options.get("port", 0))
			_session_token = str(connection_options.get("token", ""))
			if _endpoint_port < 1024 or _endpoint_port > 65535:
				return _fail("The game server port must be from 1024 through 65535.")
			if _session_token.is_empty():
				return _fail("The game server session token is missing.")
			if _session_token.to_utf8_buffer().size() > Protocol.MAX_TOKEN_BYTES:
				return _fail("The game server session token is too long.")
			if not _connect_to_endpoint():
				return false
		"host":
			# The host plays seat 0 alone; seat 1 belongs to the remote joiner.
			_requested_seat = 0
			_host_bind_port = int(connection_options.get("port", 0))
			if _host_bind_port < 1024 or _host_bind_port > 65535:
				return _fail("The host port must be from 1024 through 65535.")
			var token := str(connection_options.get("token", "")).strip_edges()
			if token.to_utf8_buffer().size() > Protocol.MAX_TOKEN_BYTES:
				return _fail("The game token is too long.")
			if not _launch_sidecar(token, connection_options):
				return false
		"join":
			if not _begin_join(connection_options):
				return false
		_:
			if not _launch_sidecar():
				return false
	status_changed.emit("connecting")
	return true


func is_local_test_server() -> bool:
	return _owns_sidecar and _connection_kind != "host"


func connection_kind() -> String:
	return _connection_kind


## The UDP port the hosting sidecar actually bound (0 until its ready file).
func listen_port() -> int:
	return _endpoint_port if _connection_kind == "host" else 0


func endpoint_description() -> String:
	match _connection_kind:
		"host":
			return "HOSTING ON UDP PORT %d" % _endpoint_port if _endpoint_port > 0 else "HOSTING"
		"local":
			return "LOCAL SERVER"
	if _endpoint_host.is_empty():
		return ""
	return "%s:%d" % [_endpoint_host, _endpoint_port]


## v8 party chat: the line travels to the host's game server, which relays
## it to every peer (this one included) as a CHAT packet.
func send_chat(text: String, nickname: String) -> bool:
	if not _active or not _ready or _connections.is_empty():
		return false
	var connection: Dictionary = _connections[0]
	var remote_seat := _remote_seat_for_local_seat(connection, 0)
	var packet := Protocol.encode_chat(remote_seat, nickname, text, _next_control_sequence(connection))
	if packet.is_empty():
		return false
	return _send(connection, packet, true)


## v8 hole punching: only meaningful for the host (seat 0) whose sidecar is
## bound publicly; the ACK reports whether datagrams were queued.
func punch_request(address: String, port: int) -> bool:
	if not _active or not _ready or _connections.is_empty():
		return false
	var connection: Dictionary = _connections[0]
	if int(connection.get("requested_seat", 0)) not in [0, Protocol.SEAT_BOTH]:
		return false
	var packet := Protocol.encode_punch(0, address, port, _next_control_sequence(connection))
	if packet.is_empty():
		return false
	return _send(connection, packet, true)


func poll() -> Dictionary:
	if not _active or _failed:
		return _snapshot
	_update_sidecar_heartbeat()
	if _dialing:
		_poll_dial()
		return _snapshot
	if Time.get_ticks_usec() - _started_at_usec > CONNECT_TIMEOUT_USEC and not _ready:
		_fail(
			"The local test server did not complete its handshake."
			if _owns_sidecar
			else "The game server at %s did not complete its handshake."
			% endpoint_description()
		)
		return _snapshot
	if _owns_sidecar and _endpoint_port == 0:
		_poll_sidecar_ready_file()
	if _endpoint_port == 0:
		return _snapshot
	for index in range(_connections.size()):
		_poll_connection(index)
	return _snapshot


func submit_input(local_seat: int, action_mask: int) -> bool:
	if not _active or local_seat < 0 or local_seat >= _input_masks.size():
		return false
	_input_masks[local_seat] = WBInputRouter.normalize_mask(action_mask)
	if not _ready:
		return true
	var connection_index := _connection_for_local_seat(local_seat)
	if connection_index < 0:
		return false
	var connection: Dictionary = _connections[connection_index]
	var remote_seat := _remote_seat_for_local_seat(connection, local_seat)
	var server_tick := maxi(0, int(_snapshot.get("tick", 0)))
	var bonus_kind := str(_snapshot.get("bonus_mode", {}).get("kind", ""))
	var semantic_held := (
		bonus_kind == "memory_station"
		and (_input_masks[local_seat] & (WBInputRouter.INPUT_FIRE | WBInputRouter.INPUT_SECONDARY)) != 0
	)
	if (
		not semantic_held
		and
		_input_masks[local_seat] == _last_sent_input_masks[local_seat]
		and server_tick - _last_sent_input_ticks[local_seat] < INPUT_REFRESH_TICKS
	):
		return true
	var packet := Protocol.encode_input(
		remote_seat,
		server_tick,
		_input_masks[local_seat],
		_next_input_sequence(connection)
	)
	var sent := _send(connection, packet, false)
	if sent:
		_last_sent_input_masks[local_seat] = _input_masks[local_seat]
		_last_sent_input_ticks[local_seat] = server_tick
	return sent


func submit_bonus_action(
	local_seat: int,
	action_kind: int,
	tile_index: int = -1
) -> Dictionary:
	if not _active or not _ready:
		return {"accepted": false, "reason": "server_not_ready"}
	var connection_index := _connection_for_local_seat(local_seat)
	if connection_index < 0:
		return {"accepted": false, "reason": "seat_not_owned"}
	var connection: Dictionary = _connections[connection_index]
	var remote_seat := _remote_seat_for_local_seat(connection, local_seat)
	# Commands target the next authoritative simulation tick. This makes a
	# mouse click produce the same normalized replay frame as a keyboard or
	# gamepad action sampled by the next local physics update.
	var client_tick := maxi(1, int(_snapshot.get("tick", 0)) + 1)
	var packet := Protocol.encode_bonus_action(
		remote_seat,
		client_tick,
		action_kind,
		tile_index,
		_next_control_sequence(connection)
	)
	if not _send(connection, packet, true):
		return {"accepted": false, "reason": "send_failed"}
	return {
		"accepted": true,
		"pending": true,
		"reason": "queued",
		"action_kind": action_kind,
		"tile_index": tile_index,
	}


func submit_shop_purchase(local_seat: int, item_id: int, nonce: int) -> Dictionary:
	if not _active or not _ready:
		return {"accepted": false, "reason": "server_not_ready"}
	var connection_index := _connection_for_local_seat(local_seat)
	if connection_index < 0:
		return {"accepted": false, "reason": "seat_not_owned"}
	var connection: Dictionary = _connections[connection_index]
	var remote_seat := _remote_seat_for_local_seat(connection, local_seat)
	var packet := Protocol.encode_shop(remote_seat, item_id, nonce, _next_control_sequence(connection))
	if not _send(connection, packet, true):
		return {"accepted": false, "reason": "send_failed"}
	return {"accepted": true, "pending": true, "reason": "queued", "nonce": nonce}


func set_shop_ready(local_seat: int, ready: bool) -> bool:
	if not _active or not _ready:
		return false
	var connection_index := _connection_for_local_seat(local_seat)
	if connection_index < 0:
		return false
	var connection: Dictionary = _connections[connection_index]
	var remote_seat := _remote_seat_for_local_seat(connection, local_seat)
	var packet := Protocol.encode_ready(remote_seat, ready, _next_control_sequence(connection))
	return _send(connection, packet, true)


## v7: asks the server for the finished match's replay. Chunked REPLAY_DATA
## responses reassemble into the replay dictionary and emit replay_ready;
## request or transport failures emit replay_failed. One request at a time.
func request_replay(local_seat: int = 0) -> bool:
	if not _active or not _ready:
		return false
	var connection_index := _connection_for_local_seat(local_seat)
	if connection_index < 0:
		return false
	var connection: Dictionary = _connections[connection_index]
	var remote_seat := _remote_seat_for_local_seat(connection, local_seat)
	var packet := Protocol.encode_replay_request(remote_seat, _next_control_sequence(connection))
	if not _send(connection, packet, true):
		return false
	_replay_chunks = {}
	_replay_chunk_count = 0
	_replay_total_bytes = 0
	_replay_pending = true
	return true


func request_pause(paused: bool) -> bool:
	if not _active or not _ready:
		return false
	var connection_index := _connection_for_local_seat(0)
	if connection_index < 0:
		return false
	var connection: Dictionary = _connections[connection_index]
	var requested_seat := int(connection.get("requested_seat", 0))
	if requested_seat not in [0, Protocol.SEAT_BOTH]:
		return false
	var packet := Protocol.encode_pause(0, paused, _next_control_sequence(connection))
	return _send(connection, packet, true)


func request_retire() -> bool:
	if not _active or not _ready:
		return false
	var connection_index := _connection_for_local_seat(0)
	if connection_index < 0:
		return false
	var connection: Dictionary = _connections[connection_index]
	var remote_seat := _remote_seat_for_local_seat(connection, 0)
	var packet := Protocol.encode_retire(remote_seat, _next_control_sequence(connection))
	return _send(connection, packet, true)


func request_save(slot: int) -> bool:
	if not _active or not _ready:
		return false
	var connection_index := _connection_for_local_seat(0)
	if connection_index < 0:
		return false
	var connection: Dictionary = _connections[connection_index]
	var remote_seat := _remote_seat_for_local_seat(connection, 0)
	var packet := Protocol.encode_save(
		remote_seat,
		slot,
		_next_control_sequence(connection)
	)
	return _send(connection, packet, true)


func get_snapshot() -> Dictionary:
	return _snapshot.duplicate(true)


func state_hash() -> String:
	return str(_snapshot.get("state_hash", ""))


func content_hash() -> String:
	return _content_hash


func local_seat_for_authoritative(authoritative_seat: int) -> int:
	if _connections.is_empty():
		return -1
	var requested := int(_connections[0].get("requested_seat", 0))
	if requested == Protocol.SEAT_BOTH:
		return authoritative_seat if authoritative_seat in [0, 1] else -1
	return 0 if authoritative_seat == requested else -1


func is_ready() -> bool:
	return _ready


func is_active() -> bool:
	return _active


func last_error() -> String:
	return _last_error


func close() -> void:
	for connection in _connections:
		var peer: ENetMultiplayerPeer = connection.get("peer")
		if peer != null:
			peer.close()
	_connections.clear()
	_active = false
	_ready = false
	_failed = false
	_snapshot.clear()
	_last_snapshot_tick = -1
	_input_masks = [0, 0]
	_last_sent_input_masks = [-1, -1]
	_last_sent_input_ticks = [-INPUT_REFRESH_TICKS, -INPUT_REFRESH_TICKS]
	_endpoint_port = 0
	if not _sidecar_ready_path.is_empty() and FileAccess.file_exists(_sidecar_ready_path):
		DirAccess.remove_absolute(_sidecar_ready_path)
	if _owns_sidecar:
		_request_sidecar_shutdown()
	_sidecar_pid = 0
	_sidecar_ready_path = ""
	_sidecar_heartbeat_path = ""
	_last_heartbeat_write_usec = 0
	_heartbeat_generation = 0
	_owns_sidecar = false
	_sidecar_shutdown_requested = false
	_connection_kind = "local"
	_host_bind_port = 0
	_join_candidates = []
	_join_index = -1
	_join_local_port = 0
	_dialing = false


## The sidecar: the same lobby server binary the dedicated export uses,
## spawned headless and configured through the ordinary HELLO match request.
## Solo and couch play bind it to 127.0.0.1 on a random port with a random
## token; a host binds it publicly on its chosen port with the token joiners
## receive from the lobby server. The match itself never rides process
## arguments, so every role runs identical server code.
func _launch_sidecar(token: String = "", options: Dictionary = {}) -> bool:
	_owns_sidecar = true
	_sidecar_shutdown_requested = false
	_heartbeat_generation = 0
	_session_token = token if not token.is_empty() else Crypto.new().generate_random_bytes(24).hex_encode()
	var bind_host := "*" if _connection_kind == "host" else LOOPBACK_HOST
	var bind_port := _host_bind_port if _connection_kind == "host" else 0
	_sidecar_ready_path = ProjectSettings.globalize_path(
		"user://local_server_%d_%d.json" % [OS.get_process_id(), Time.get_ticks_usec()]
	)
	_sidecar_heartbeat_path = _sidecar_ready_path.trim_suffix(".json") + ".heartbeat"
	if FileAccess.file_exists(_sidecar_ready_path):
		DirAccess.remove_absolute(_sidecar_ready_path)
	if FileAccess.file_exists(_sidecar_heartbeat_path):
		DirAccess.remove_absolute(_sidecar_heartbeat_path)
	if not _write_heartbeat():
		return _fail("The client could not create the local test server heartbeat.")
	var executable := OS.get_executable_path()
	var arguments := PackedStringArray(["--headless"])
	if OS.has_feature("editor"):
		arguments.append_array([
			"--path",
			ProjectSettings.globalize_path("res://"),
		])
	arguments.append("--")
	arguments.append_array([
		"--server",
		"--host=%s" % bind_host,
		"--port=%d" % bind_port,
		"--token=%s" % _session_token,
		"--content-hash=%s" % _content_hash,
		"--ready-file=%s" % _sidecar_ready_path,
		"--parent-heartbeat=%s" % _sidecar_heartbeat_path,
	])
	var rendezvous := str(options.get("rendezvous", "")).strip_edges()
	if not rendezvous.is_empty():
		arguments.append("--rendezvous=%s" % rendezvous)
		arguments.append("--rendezvous-nonce=%s" % str(options.get("nonce", "")))
	_sidecar_pid = OS.create_process(executable, arguments)
	if _sidecar_pid <= 0:
		return _fail("The local test server process could not be launched.")
	return true


func _poll_sidecar_ready_file() -> void:
	if not FileAccess.file_exists(_sidecar_ready_path):
		return
	var file := FileAccess.open(_sidecar_ready_path, FileAccess.READ)
	if file == null:
		return
	var json := JSON.new()
	var parsed := json.parse(file.get_as_text())
	file.close()
	if parsed != OK or typeof(json.data) != TYPE_DICTIONARY:
		_fail("The local test server produced an invalid startup response.")
		return
	var response: Dictionary = json.data
	DirAccess.remove_absolute(_sidecar_ready_path)
	if not bool(response.get("ok", false)):
		_fail(str(response.get("error", "The local test server rejected startup.")))
		return
	if str(response.get("content_hash", "")) != _content_hash:
		_fail("The local test server loaded different game content.")
		return
	_endpoint_host = LOOPBACK_HOST
	_endpoint_port = int(response.get("port", 0))
	if _endpoint_port < 1024 or _endpoint_port > 65535:
		_fail("The local test server returned an invalid port.")
		return
	_connect_to_endpoint()


func _connect_to_endpoint(local_port: int = 0) -> bool:
	_connections.clear()
	var remote_seats: Array[int] = [_requested_seat]
	for remote_seat in remote_seats:
		var peer := ENetMultiplayerPeer.new()
		var error := peer.create_client(_endpoint_host, _endpoint_port, 0, 0, 0, local_port)
		if error != OK:
			peer.close()
			return _fail("The client could not open a connection to the game server.")
		_connections.append({
			"peer": peer,
			"requested_seat": remote_seat,
			"control_sequence": 1,
			"input_sequence": 1,
			"hello_sent": false,
			"welcomed": false,
			"last_server_sequence": -1,
		})
	return true


## A joiner dials the host's candidate endpoints in order (LAN first when both
## sit behind one router, then the public endpoint), always from the same
## local UDP port the rendezvous probe used, so the hole the host punched
## matches. ENet itself keeps retrying a connect for ~30 s, so each candidate
## gets its own shorter budget and a fresh peer.
func _begin_join(options: Dictionary) -> bool:
	_session_token = str(options.get("token", "")).strip_edges()
	if _session_token.is_empty():
		return _fail("The game token is missing.")
	if _session_token.to_utf8_buffer().size() > Protocol.MAX_TOKEN_BYTES:
		return _fail("The game token is too long.")
	_join_local_port = int(options.get("local_port", 0))
	_join_candidates = []
	var candidates_value: Variant = options.get("candidates", [])
	if candidates_value is Array:
		for candidate_value: Variant in (candidates_value as Array):
			if not candidate_value is Dictionary:
				continue
			var candidate := candidate_value as Dictionary
			var host := str(candidate.get("host", "")).strip_edges()
			var port := int(candidate.get("port", 0))
			if host.is_empty() or port < 1 or port > 65535:
				continue
			_join_candidates.append({
				"host": host,
				"port": port,
				"timeout_sec": float(candidate.get(
					"timeout_sec",
					DIAL_LAN_TIMEOUT_SEC if bool(candidate.get("lan", false)) else DIAL_PUBLIC_TIMEOUT_SEC
				)),
			})
	if _join_candidates.is_empty():
		return _fail("The host did not provide an address to join.")
	_join_index = -1
	_dialing = true
	return _dial_next_candidate()


func _dial_next_candidate() -> bool:
	_join_index += 1
	if _join_index >= _join_candidates.size():
		_dialing = false
		return _fail(
			"Could not reach the host. Ask them to enable UPnP or forward UDP port %d, or use CONNECT TO HOST."
			% int((_join_candidates[0] as Dictionary).get("port", 0))
		)
	var candidate: Dictionary = _join_candidates[_join_index]
	_endpoint_host = str(candidate.host)
	_endpoint_port = int(candidate.port)
	_dial_started_usec = Time.get_ticks_usec()
	_dial_timeout_usec = int(float(candidate.timeout_sec) * 1_000_000.0)
	for connection in _connections:
		var previous: ENetMultiplayerPeer = connection.get("peer")
		if previous != null:
			previous.close()
	if not _connect_to_endpoint(_join_local_port):
		return false
	status_changed.emit("dialing")
	return true


func _poll_dial() -> void:
	if _connections.is_empty():
		_dialing = false
		return
	var peer: ENetMultiplayerPeer = _connections[0].get("peer")
	if peer == null:
		_dialing = false
		return
	peer.poll()
	var status := peer.get_connection_status()
	if status == MultiplayerPeer.CONNECTION_CONNECTED:
		# The handshake budget starts now, not when dialing began.
		_dialing = false
		_started_at_usec = Time.get_ticks_usec()
		status_changed.emit("connecting")
		return
	var elapsed := Time.get_ticks_usec() - _dial_started_usec
	if status == MultiplayerPeer.CONNECTION_DISCONNECTED or elapsed > _dial_timeout_usec:
		_dial_next_candidate()


func dial_candidate_index() -> int:
	return _join_index


func _poll_connection(index: int) -> void:
	var connection: Dictionary = _connections[index]
	var peer: ENetMultiplayerPeer = connection.get("peer")
	if peer == null:
		return
	peer.poll()
	var state := peer.get_connection_status()
	if state == MultiplayerPeer.CONNECTION_DISCONNECTED:
		if bool(connection.get("hello_sent", false)):
			_fail("The game server disconnected.")
		return
	if state != MultiplayerPeer.CONNECTION_CONNECTED:
		return
	if not bool(connection.get("hello_sent", false)):
		# Seat 0 and couch clients author the match: their HELLO carries the
		# complete requested contract. A seat-1 client joins the match the
		# seat-0 author already configured, so it sends no request and adopts
		# the authoritative contract from the first snapshot.
		var match_request: Dictionary = {}
		if not _joins_existing_match():
			match_request = MatchContract.network_match_request(_config)
		var hello := Protocol.encode_hello(
			_session_token,
			int(connection.get("requested_seat", 0)),
			_content_hash,
			_next_control_sequence(connection),
			match_request
		)
		if not _send(connection, hello, true):
			_fail("The client could not authenticate with the game server.")
			return
		connection["hello_sent"] = true
	while peer.get_available_packet_count() > 0:
		_process_packet(connection, peer.get_packet())


func _process_packet(connection: Dictionary, packet: PackedByteArray) -> void:
	var decoded := Protocol.decode_packet(packet)
	if not bool(decoded.get("ok", false)):
		_fail("The game server sent a malformed packet.")
		return
	var message_type := int(decoded.get("type", 0))
	var payload: Dictionary = decoded.get("payload", {})
	if message_type != Protocol.MessageType.REJECT:
		var server_sequence := int(decoded.get("sequence", -1))
		if server_sequence <= int(connection.get("last_server_sequence", -1)):
			_fail("The game server sent a stale packet sequence.")
			return
		connection["last_server_sequence"] = server_sequence
	match message_type:
		Protocol.MessageType.WELCOME:
			_accept_welcome(connection, payload)
		Protocol.MessageType.SNAPSHOT:
			_accept_snapshot(payload)
		Protocol.MessageType.ACK:
			var request_type := int(payload.get("request_type", 0))
			var accepted := bool(payload.get("accepted", false))
			var details: Dictionary = payload.get("details", {})
			if request_type == Protocol.MessageType.PUNCH:
				punch_acknowledged.emit(accepted, details)
			command_acknowledged.emit(request_type, accepted, details)
		Protocol.MessageType.CHAT:
			chat_received.emit(
				int(payload.get("seat_id", 0)),
				str(payload.get("nickname", "")),
				str(payload.get("text", ""))
			)
		Protocol.MessageType.REPLAY_DATA:
			_accept_replay_chunk(payload)
		Protocol.MessageType.REJECT:
			_handle_reject(payload)
		_:
			_fail("The game server sent a forbidden message type.")


func _accept_welcome(connection: Dictionary, payload: Dictionary) -> void:
	if str(payload.get("content_hash", "")) != _content_hash:
		_fail("The game server handshake has a content hash mismatch.")
		return
	var expected_seat := int(connection.get("requested_seat", 0))
	var accepted_seat := int(payload.get("seat_id", -1))
	if accepted_seat != expected_seat:
		_fail("The game server assigned an unexpected seat.")
		return
	connection["welcomed"] = true
	_ready = _connections.all(
		func(candidate: Dictionary) -> bool: return bool(candidate.get("welcomed", false))
	)
	if _ready:
		status_changed.emit("ready")


func _accept_snapshot(snapshot: Dictionary) -> void:
	if not _ready:
		_fail("The game server sent state before authentication.")
		return
	if str(snapshot.get("content_hash", "")) != _content_hash:
		_fail("The authoritative snapshot has a content hash mismatch.")
		return
	if int(snapshot.get("version", 0)) != Protocol.SNAPSHOT_VERSION:
		_fail("The game server uses a different snapshot schema.")
		return
	if _joins_existing_match():
		_adopt_authoritative_contract(snapshot)
	if int(snapshot.get("start_level_id", 0)) != int(_config.get("start_level", 1)):
		_fail("The game server runs a different start level.")
		return
	if int(snapshot.get("end_level_id", 0)) != int(_config.get(
		"end_level",
		WBMatchConfig.MAX_END_LEVEL
	)):
		_fail("The game server runs a different end level.")
		return
	var expected_contract := {
		"mode": str(_config.get("mode", "solo")),
		"difficulty": str(_config.get("difficulty", "normal")),
		"coop_balance": str(_config.get("coop_balance", "classic")),
		"collision_mode": str(_config.get("collision_mode", "pixel")),
	}
	for field in expected_contract:
		if str(snapshot.get(field, "")) != str(expected_contract[field]):
			_fail(
				"The game server runs a different %s setting."
				% str(field).replace("_", " ")
			)
			return
	var tick := int(snapshot.get("tick", -1))
	if tick < _last_snapshot_tick:
		return
	if (
		tick == _last_snapshot_tick
		and bool(snapshot.get("paused", false))
		== bool(_snapshot.get("paused", false))
		and bool(snapshot.get("waiting_for_seats", false))
		== bool(_snapshot.get("waiting_for_seats", false))
		and int(snapshot.get("required_seats", 0))
		== int(_snapshot.get("required_seats", 0))
	):
		return
	_last_snapshot_tick = tick
	_snapshot = snapshot.duplicate(true)
	snapshot_received.emit(_snapshot)


const REPLAY_DECOMPRESSED_CAP_BYTES := 268_435_456


func _accept_replay_chunk(payload: Dictionary) -> void:
	if not _replay_pending:
		return
	var chunk_count := int(payload.get("chunk_count", 0))
	var chunk_index := int(payload.get("chunk_index", -1))
	if _replay_chunk_count == 0:
		_replay_chunk_count = chunk_count
		_replay_total_bytes = int(payload.get("total_bytes", 0))
	if chunk_count != _replay_chunk_count or chunk_index < 0 or chunk_index >= chunk_count:
		_finish_replay_failure("replay_chunk_mismatch")
		return
	_replay_chunks[chunk_index] = payload.get("bytes", PackedByteArray())
	if _replay_chunks.size() < _replay_chunk_count:
		return
	var compressed := PackedByteArray()
	for index in range(_replay_chunk_count):
		compressed.append_array(_replay_chunks[index])
	if compressed.size() != _replay_total_bytes:
		_finish_replay_failure("replay_size_mismatch")
		return
	var raw := compressed.decompress_dynamic(
		REPLAY_DECOMPRESSED_CAP_BYTES, FileAccess.COMPRESSION_GZIP
	)
	if raw.is_empty():
		_finish_replay_failure("replay_decompress_failed")
		return
	var parsed: Variant = JSON.parse_string(raw.get_string_from_utf8())
	if not (parsed is Dictionary) or (parsed as Dictionary).is_empty():
		_finish_replay_failure("replay_parse_failed")
		return
	_replay_pending = false
	_replay_chunks = {}
	replay_ready.emit(parsed as Dictionary)


func _finish_replay_failure(reason: String) -> void:
	_replay_pending = false
	_replay_chunks = {}
	_replay_chunk_count = 0
	replay_failed.emit(reason)


func _handle_reject(payload: Dictionary) -> void:
	var code := int(payload.get("code", 0))
	var reason := str(payload.get("reason", "rejected"))
	if _replay_pending and reason in ["no_match", "match_not_terminal", "replay_unavailable"]:
		_finish_replay_failure(reason)
		return
	if code in [2, 5, 8]:
		_fail("The game server rejected the session: %s" % reason)
		return
	var match_failure := _match_request_failure_message(reason)
	if not match_failure.is_empty():
		_fail(match_failure)
		return
	status_changed.emit("server_rejected:%s" % reason)


## Match-request rejections end the session with a readable explanation
## instead of dangling until the handshake timeout.
static func _match_request_failure_message(reason: String) -> String:
	if reason == "match_contract_mismatch" or reason == "match_in_progress":
		return "The game server is already running a different match."
	if reason == "match_request_required":
		return "The game server is idle; the first player must start the match."
	if reason == "resume_contract_mismatch":
		return "The saved run on the game server does not match this one."
	if reason.begins_with("resume_failed:"):
		return (
			"The game server could not resume the saved run: %s"
			% reason.trim_prefix("resume_failed:")
		)
	if reason.begins_with("match_request_rejected:"):
		return (
			"The game server rejected the requested match: %s"
			% reason.trim_prefix("match_request_rejected:")
		)
	return ""


func _send(connection: Dictionary, packet: PackedByteArray, reliable: bool) -> bool:
	if packet.is_empty():
		return false
	var peer: ENetMultiplayerPeer = connection.get("peer")
	if peer == null or peer.get_connection_status() != MultiplayerPeer.CONNECTION_CONNECTED:
		return false
	peer.set_target_peer(SERVER_PEER_ID)
	peer.transfer_mode = (
		MultiplayerPeer.TRANSFER_MODE_RELIABLE
		if reliable
		else MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED
	)
	return peer.put_packet(packet) == OK


func _update_sidecar_heartbeat() -> void:
	if not _owns_sidecar or _sidecar_heartbeat_path.is_empty():
		return
	var now := Time.get_ticks_usec()
	if now - _last_heartbeat_write_usec >= HEARTBEAT_INTERVAL_USEC:
		_write_heartbeat()


func _write_heartbeat() -> bool:
	var file := FileAccess.open(_sidecar_heartbeat_path, FileAccess.WRITE)
	if file == null:
		return false
	_heartbeat_generation += 1
	file.store_string(str(_heartbeat_generation))
	file.close()
	_last_heartbeat_write_usec = Time.get_ticks_usec()
	return true


func _request_sidecar_shutdown() -> void:
	if _sidecar_shutdown_requested or _sidecar_heartbeat_path.is_empty():
		return
	var file := FileAccess.open(_sidecar_heartbeat_path, FileAccess.WRITE)
	if file == null:
		return
	file.store_string("shutdown")
	file.close()
	_sidecar_shutdown_requested = true


func _next_control_sequence(connection: Dictionary) -> int:
	var sequence := int(connection.get("control_sequence", 1))
	connection["control_sequence"] = sequence + 1
	return sequence


func _next_input_sequence(connection: Dictionary) -> int:
	var sequence := int(connection.get("input_sequence", 1))
	connection["input_sequence"] = sequence + 1
	return sequence


func _resolve_requested_seat(options: Dictionary) -> int:
	if options.has("seat"):
		return clampi(int(options.get("seat", 0)), 0, 1)
	return Protocol.SEAT_BOTH if int(_config.get("seat_count", 1)) == 2 else 0


func _joins_existing_match() -> bool:
	return _requested_seat == 1


## A joining client plays whatever match the author configured; the fields the
## snapshot validator would otherwise compare against local menu choices are
## adopted from the first authoritative snapshot instead.
func _adopt_authoritative_contract(snapshot: Dictionary) -> void:
	for field in ["mode", "difficulty", "coop_balance", "collision_mode"]:
		if snapshot.has(field):
			_config[field] = str(snapshot[field])
	if snapshot.has("start_level_id"):
		_config["start_level"] = int(snapshot.start_level_id)
	if snapshot.has("end_level_id"):
		_config["end_level"] = int(snapshot.end_level_id)


func _connection_for_local_seat(local_seat: int) -> int:
	if _connections.is_empty():
		return -1
	var requested := int(_connections[0].get("requested_seat", 0))
	if requested == Protocol.SEAT_BOTH:
		return 0 if local_seat in [0, 1] else -1
	return 0 if local_seat == 0 else -1


func _remote_seat_for_local_seat(connection: Dictionary, local_seat: int) -> int:
	var requested := int(connection.get("requested_seat", 0))
	return local_seat if requested == Protocol.SEAT_BOTH else requested


func _fail(message: String) -> bool:
	if _failed:
		return false
	_failed = true
	_active = false
	_ready = false
	_last_error = message
	if _owns_sidecar:
		_request_sidecar_shutdown()
	session_failed.emit(message)
	return false

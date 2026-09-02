class_name AuthoritativeServer
extends Node

const Simulation := preload("res://src/sim/game_simulation.gd")
const Protocol := preload("res://src/net/protocol_codec.gd")
const MatchContract := preload("res://src/shared/match_contract.gd")
const Catalog := preload("res://src/sim/content_catalog.gd")
const RendezvousCodec := preload("res://src/shared/rendezvous_codec.gd")

const LOOPBACK_HOST := "127.0.0.1"

const MAX_CLIENTS: int = 2
## A publicly bound host keeps spare ENet slots: a joiner whose punched
## connect attempt half-opened a slot must be able to retry within ~30 s.
const MAX_PUBLIC_CLIENTS: int = 4
const PUNCH_BURST_COUNT: int = 5
const PUNCH_BURST_INTERVAL_MSEC: int = 100
const PUNCH_TAIL_INTERVAL_MSEC: int = 1000
const PUNCH_DURATION_MSEC: int = 12000
const MAX_PUNCH_TARGETS: int = 4
const MAX_CHAT_PER_WINDOW: int = 8
const RENDEZVOUS_KEEPALIVE_MSEC: int = 15000
const MIN_DYNAMIC_PORT: int = 42000
const DYNAMIC_PORT_SPAN: int = 16000
const INPUT_MESSAGES_PER_SECOND_PER_SEAT: int = 60
const MAX_SEATS_PER_PEER: int = 2
const RATE_CONTROL_HEADROOM: int = 32
const MAX_MESSAGES_PER_RATE_WINDOW: int = (
	INPUT_MESSAGES_PER_SECOND_PER_SEAT * MAX_SEATS_PER_PEER + RATE_CONTROL_HEADROOM
)
const RATE_WINDOW_MSEC: int = 1000
const HANDSHAKE_TIMEOUT_MSEC: int = 3000
const MAX_UNAUTHENTICATED_REJECTIONS: int = 4
const MAX_FUTURE_INPUT_TICKS: int = 8
const MAX_OLD_INPUT_TICKS: int = 120
const SNAPSHOT_INTERVAL_TICKS: int = 3
const MAX_BUFFERED_SNAPSHOT_EVENTS: int = 256

const REJECT_MALFORMED: int = 1
const REJECT_AUTH: int = 2
const REJECT_SEQUENCE: int = 3
const REJECT_RATE: int = 4
const REJECT_SEAT: int = 5
const REJECT_TICK: int = 6
const REJECT_COMMAND: int = 7
const REJECT_CONTENT: int = 8

var simulation: GameSimulation
var session_token: String = ""
var listen_port: int = 0
var running: bool = false
var paused: bool = false
var _saved_games := WBSaveGameStore.new()
var _resume_error := ""
var _lobby := false
var _bind_host := LOOPBACK_HOST
var _expected_content_hash := ""
var _match_contract: Dictionary = {}
var _welcome_broadcast_pending := false

var _peer: ENetMultiplayerPeer
var _peers: Dictionary = {}
var _seat_owners: Dictionary = {}
var _server_sequence: int = 1
var _rejection_counters: Dictionary = {"total": 0, "by_reason": {}}
var _snapshot_events: Array = []
var _last_buffered_event_id: int = 0
# Gzip of the finished match's replay JSON, built on the first
# REPLAY_REQUEST and reused for retries until the match resets.
var _replay_export_cache := PackedByteArray()
var _punch_targets: Array[Dictionary] = []
var _raw_datagrams_sent := 0
var _rendezvous: Dictionary = {}
var _rendezvous_next_msec := 0
var _rendezvous_keepalives_sent := 0


func configure_only(match_config: Dictionary, expected_content_hash: String = "") -> bool:
	if not _configure_simulation(match_config, expected_content_hash):
		return false
	_peers.clear()
	_seat_owners.clear()
	_server_sequence = 1
	paused = false
	_rejection_counters = {"total": 0, "by_reason": {}}
	_snapshot_events.clear()
	_last_buffered_event_id = 0
	_replay_export_cache = PackedByteArray()
	return true


## Builds and validates the authoritative simulation without touching peer or
## sequence state, so an idle lobby can configure a match inside a live
## handshake.
func _configure_simulation(match_config: Dictionary, expected_content_hash: String = "") -> bool:
	var authoritative_config := match_config.duplicate(true)
	if not expected_content_hash.is_empty():
		authoritative_config["content_hash"] = expected_content_hash
	simulation = Simulation.new()
	if int(authoritative_config.get("protocol_version", -1)) != Protocol.VERSION:
		simulation.last_error = "match configuration requires protocol version %d" % Protocol.VERSION
		return false
	if int(authoritative_config.get("content_version", -1)) != MatchContract.CONTENT_VERSION:
		simulation.last_error = (
			"match configuration requires content version %d" % MatchContract.CONTENT_VERSION
		)
		return false
	if not MatchContract.has_valid_level_range(authoritative_config):
		simulation.last_error = "match configuration level range is outside 1 through %d" % (
			MatchContract.MAX_END_LEVEL
		)
		return false
	if not simulation.configure(authoritative_config):
		return false
	_match_contract = MatchContract.network_contract(authoritative_config)
	_expected_content_hash = simulation.get_content_hash()
	return true


func start_local(
	match_config: Dictionary,
	expected_content_hash: String = "",
	requested_port: int = 0,
	requested_token: String = "",
	resume_slot: int = -1
) -> Dictionary:
	stop()
	if resume_slot >= 0:
		if not _resume_saved_run(resume_slot):
			return _start_result(false, _resume_error)
	elif not configure_only(match_config, expected_content_hash):
		return _start_result(false, simulation.get_last_error())
	return _start_listening(LOOPBACK_HOST, requested_port, requested_token)


## An online game server: it binds, authenticates, and waits with no match
## configured. The first authenticated HELLO's match request configures or
## resumes the simulation; when the last authenticated peer leaves, the server
## returns to this idle state and accepts the next match. A non-loopback bind
## must be deliberate, so it requires an explicit port and session token.
func start_lobby(
	bind_host: String = LOOPBACK_HOST,
	requested_port: int = 0,
	requested_token: String = "",
	content_base_path: String = "res://content"
) -> Dictionary:
	stop()
	var catalog := Catalog.load_catalog(content_base_path, "")
	if not bool(catalog.get("ok", false)):
		return _start_result(false, str(catalog.get("error", "content catalog failed to load")))
	_expected_content_hash = str(catalog.get("content_hash", ""))
	if _expected_content_hash.is_empty():
		return _start_result(false, "content catalog produced no content hash")
	if bind_host != LOOPBACK_HOST:
		if bind_host != "*" and not bind_host.is_valid_ip_address():
			return _start_result(false, "bind host must be 127.0.0.1, *, or a valid IP address")
		if requested_port == 0:
			return _start_result(false, "a non-loopback server requires an explicit --port")
		if requested_token.is_empty():
			return _start_result(false, "a non-loopback server requires an explicit --token")
	_lobby = true
	return _start_listening(bind_host, requested_port, requested_token)


func _start_listening(
	bind_host: String,
	requested_port: int,
	requested_token: String
) -> Dictionary:
	if requested_port != 0 and (requested_port < 1024 or requested_port > 65535):
		return _start_result(false, "requested port is out of range")
	if requested_token.to_utf8_buffer().size() > Protocol.MAX_TOKEN_BYTES:
		return _start_result(false, "session token is too long")
	session_token = requested_token if not requested_token.is_empty() else _generate_session_token()
	var bind_result := _bind(bind_host, requested_port)
	if not bind_result.ok:
		return _start_result(false, String(bind_result.error))
	_bind_host = bind_host
	listen_port = int(bind_result.port)
	if not _peer.peer_connected.is_connected(_on_peer_connected):
		_peer.peer_connected.connect(_on_peer_connected)
	if not _peer.peer_disconnected.is_connected(_on_peer_disconnected):
		_peer.peer_disconnected.connect(_on_peer_disconnected)
	running = true
	set_process(true)
	set_physics_process(true)
	return _start_result(true, "")


func stop() -> void:
	running = false
	paused = false
	set_process(false)
	set_physics_process(false)
	if _peer != null:
		_peer.close()
	_peer = null
	_peers.clear()
	_seat_owners.clear()
	_snapshot_events.clear()
	_last_buffered_event_id = 0
	_replay_export_cache = PackedByteArray()
	listen_port = 0
	session_token = ""
	_lobby = false
	_bind_host = LOOPBACK_HOST
	_expected_content_hash = ""
	_match_contract = {}
	_welcome_broadcast_pending = false
	_punch_targets.clear()
	_rendezvous = {}
	_rendezvous_next_msec = 0


func poll_network() -> void:
	if not running or _peer == null:
		return
	_peer.poll()
	while _peer.get_available_packet_count() > 0:
		var peer_id := _peer.get_packet_peer()
		var packet := _peer.get_packet()
		var response := process_packet_for_test(peer_id, packet)
		if not response.is_empty():
			_send_to_peer(peer_id, response, true)
		# A successful HELLO immediately publishes the current authoritative
		# state, queued strictly after the WELCOME. The joining peer sees the
		# exact configure-time state (or the waiting-for-seats interim) instead
		# of waiting out the snapshot cadence.
		if _welcome_broadcast_pending:
			_welcome_broadcast_pending = false
			if simulation != null:
				_broadcast_snapshot()
	var now_msec := Time.get_ticks_msec()
	_expire_unauthenticated_peers(now_msec)
	_process_punch_queue(now_msec)
	if not _rendezvous.is_empty() and now_msec >= _rendezvous_next_msec:
		send_rendezvous_keepalive()


func get_rejection_counters() -> Dictionary:
	var result := _rejection_counters.duplicate(true)
	var peer_counts: Dictionary = {}
	for peer_id in _peers:
		peer_counts[peer_id] = int(_peers[peer_id].rejections)
	result["by_peer"] = peer_counts
	return result


func get_connection_state() -> Dictionary:
	var peers: Dictionary = {}
	for peer_id in _peers:
		var state: Dictionary = _peers[peer_id]
		peers[peer_id] = {
			"authenticated": bool(state.authenticated),
			"seat_id": int(state.seat_id),
			"seat_ids": state.seat_ids.duplicate(),
			"last_sequence": int(state.last_sequence),
			"last_control_sequence": int(state.last_control_sequence),
			"last_input_sequence": int(state.last_input_sequence),
			"rejections": int(state.rejections),
		}
	return {
		"running": running,
		"paused": paused,
		"waiting_for_seats": _seat_owners.size() < _required_seat_count(),
		"required_seats": _required_seat_count(),
		"port": listen_port,
		"content_hash": _content_hash(),
		"lobby": _lobby,
		"match_configured": simulation != null,
		"bind_host": _bind_host,
		"punch_targets": _punch_targets.size(),
		"raw_datagrams_sent": _raw_datagrams_sent,
		"rendezvous": {
			"configured": not _rendezvous.is_empty(),
			"address": str(_rendezvous.get("address", "")),
			"port": int(_rendezvous.get("port", 0)),
			"keepalives_sent": _rendezvous_keepalives_sent,
		},
		"peers": peers,
	}


func process_packet_for_test(peer_id: int, packet: PackedByteArray) -> PackedByteArray:
	_ensure_peer(peer_id)
	var state: Dictionary = _peers[peer_id]
	if not _consume_rate_budget(state):
		_record_rejection(peer_id, "rate_limit")
		_record_unauthenticated_rejection(peer_id)
		return PackedByteArray()
	var decoded := Protocol.decode_packet(packet)
	if not bool(decoded.get("ok", false)):
		return _reject(peer_id, REJECT_MALFORMED, String(decoded.get("error", "malformed_packet")), 0)
	var server_tick := _server_tick()
	var sequence := int(decoded.sequence)
	var message_type := int(decoded.type)
	var sequence_key := (
		"last_input_sequence"
		if message_type == Protocol.MessageType.INPUT
		else "last_control_sequence"
	)
	if sequence <= int(state.get(sequence_key, -1)):
		return _reject(peer_id, REJECT_SEQUENCE, "stale_sequence", sequence)
	state[sequence_key] = sequence
	state.last_sequence = maxi(int(state.last_sequence), sequence)
	var payload: Dictionary = decoded.payload
	if not bool(state.authenticated):
		if message_type != Protocol.MessageType.HELLO:
			return _reject(peer_id, REJECT_AUTH, "hello_required", sequence)
		return _handle_hello(peer_id, state, payload, sequence)
	if message_type == Protocol.MessageType.HELLO:
		return _reject(peer_id, REJECT_AUTH, "already_authenticated", sequence)
	match message_type:
		Protocol.MessageType.INPUT:
			return _handle_input(peer_id, state, payload, sequence)
		Protocol.MessageType.SHOP:
			return _handle_shop(peer_id, state, payload, sequence)
		Protocol.MessageType.READY:
			return _handle_ready(peer_id, state, payload, sequence)
		Protocol.MessageType.PING:
			return Protocol.encode_ack(
				Protocol.MessageType.PING,
				true,
				server_tick,
				{"client_tick": int(payload.client_tick)},
				_next_server_sequence()
			)
		Protocol.MessageType.PAUSE:
			return _handle_pause(peer_id, state, payload, sequence)
		Protocol.MessageType.BONUS_ACTION:
			return _handle_bonus_action(peer_id, state, payload, sequence)
		Protocol.MessageType.RETIRE:
			return _handle_retire(peer_id, state, payload, sequence)
		Protocol.MessageType.SAVE:
			return _handle_save(peer_id, state, payload, sequence)
		Protocol.MessageType.REPLAY_REQUEST:
			return _handle_replay_request(peer_id, state, payload, sequence)
		Protocol.MessageType.CHAT:
			return _handle_chat(peer_id, state, payload, sequence)
		Protocol.MessageType.PUNCH:
			return _handle_punch(peer_id, state, payload, sequence)
	return _reject(peer_id, REJECT_COMMAND, "client_message_type_not_allowed", sequence)


func _process(_delta: float) -> void:
	poll_network()


func _physics_process(_delta: float) -> void:
	if not running or simulation == null:
		return
	if _seat_owners.size() < _required_seat_count():
		return
	if paused:
		return
	var stepped_snapshot := simulation.step()
	_buffer_snapshot_events(stepped_snapshot.get("events", []))
	if _server_tick() % SNAPSHOT_INTERVAL_TICKS == 0:
		_broadcast_snapshot()


func _handle_hello(
	peer_id: int,
	state: Dictionary,
	payload: Dictionary,
	sequence: int
) -> PackedByteArray:
	if String(payload.token) != session_token:
		return _reject(peer_id, REJECT_AUTH, "invalid_session_token", sequence)
	if String(payload.content_hash) != _content_hash():
		return _reject(peer_id, REJECT_CONTENT, "content_hash_mismatch", sequence)
	var request_value: Variant = payload.get("match_request", {})
	var match_request: Dictionary = request_value if request_value is Dictionary else {}
	if simulation == null:
		# An idle lobby: the first authenticated request configures or resumes
		# the match. The normalizer is the validation boundary; nothing from the
		# raw request reaches the simulation.
		if match_request.is_empty():
			return _reject(peer_id, REJECT_COMMAND, "match_request_required", sequence)
		var requested := _normalize_match_request(match_request)
		var contract: Dictionary = requested.contract
		var resume_slot := int(requested.resume_slot)
		if resume_slot >= 0:
			if not _resume_saved_run(resume_slot):
				return _reject(
					peer_id,
					REJECT_COMMAND,
					"resume_failed:%s" % _resume_error,
					sequence
				)
			if contract != _match_contract:
				_reset_lobby_match()
				return _reject(peer_id, REJECT_COMMAND, "resume_contract_mismatch", sequence)
		elif not _configure_simulation(MatchContract.config_from_network_contract(contract)):
			var error := simulation.get_last_error() if simulation != null else "invalid match request"
			_reset_lobby_match()
			return _reject(
				peer_id,
				REJECT_COMMAND,
				"match_request_rejected:%s" % error,
				sequence
			)
	elif not match_request.is_empty():
		# A match is already configured. A request may join it only by asking
		# for exactly the same contract; there is no reconfiguration underneath
		# a live match.
		var requested := _normalize_match_request(match_request)
		if int(requested.resume_slot) >= 0:
			return _reject(peer_id, REJECT_COMMAND, "match_in_progress", sequence)
		if requested.contract != _match_contract:
			return _reject(peer_id, REJECT_COMMAND, "match_contract_mismatch", sequence)
	var requested_seat := int(payload.requested_seat)
	if requested_seat != Protocol.SEAT_BOTH and (requested_seat < 0 or requested_seat > 1):
		return _reject(peer_id, REJECT_SEAT, "seat_out_of_range", sequence)
	var seat_count := MatchContract.seat_count_for_mode(
		str(_match_contract.get("mode", "solo"))
	)
	if requested_seat == Protocol.SEAT_BOTH and seat_count < 2:
		return _reject(peer_id, REJECT_SEAT, "seat_not_in_match", sequence)
	if requested_seat != Protocol.SEAT_BOTH and requested_seat >= seat_count:
		return _reject(peer_id, REJECT_SEAT, "seat_not_in_match", sequence)
	var claimed_seats: Array[int] = []
	if requested_seat == Protocol.SEAT_BOTH:
		claimed_seats.assign([0, 1])
	else:
		claimed_seats.append(requested_seat)
	for seat_id in claimed_seats:
		if _seat_owners.has(seat_id) and int(_seat_owners[seat_id]) != peer_id:
			return _reject(peer_id, REJECT_SEAT, "seat_already_owned", sequence)
	state.authenticated = true
	state.seat_id = claimed_seats[0]
	state.seat_ids = claimed_seats
	for seat_id in claimed_seats:
		_seat_owners[seat_id] = peer_id
	_welcome_broadcast_pending = true
	return Protocol.encode_welcome(
		requested_seat,
		_server_tick(),
		listen_port,
		_content_hash(),
		_next_server_sequence()
	)


func _normalize_match_request(match_request: Dictionary) -> Dictionary:
	var contract_value: Variant = match_request.get("contract", {})
	return {
		"contract": MatchContract.network_contract(
			contract_value if contract_value is Dictionary else {}
		),
		"resume_slot": maxi(-1, int(match_request.get("resume_slot", -1))),
	}


func _content_hash() -> String:
	if simulation != null:
		return simulation.get_content_hash()
	return _expected_content_hash


func _handle_input(
	peer_id: int,
	state: Dictionary,
	payload: Dictionary,
	sequence: int
) -> PackedByteArray:
	if not _state_owns_seat(state, int(payload.seat_id)):
		return _reject(peer_id, REJECT_SEAT, "wrong_seat", sequence)
	var client_tick := int(payload.client_tick)
	var server_tick := _server_tick()
	if client_tick > server_tick + MAX_FUTURE_INPUT_TICKS:
		return _reject(peer_id, REJECT_TICK, "input_too_far_ahead", sequence)
	if client_tick + MAX_OLD_INPUT_TICKS < server_tick:
		return _reject(peer_id, REJECT_TICK, "input_too_old", sequence)
	if not simulation.set_input(int(payload.seat_id), int(payload.action_mask)):
		return _reject(peer_id, REJECT_COMMAND, simulation.get_last_error(), sequence)
	return PackedByteArray()


func _handle_bonus_action(
	peer_id: int,
	state: Dictionary,
	payload: Dictionary,
	sequence: int
) -> PackedByteArray:
	var seat_id := int(payload.seat_id)
	if not _state_owns_seat(state, seat_id):
		return _reject(peer_id, REJECT_SEAT, "wrong_seat", sequence)
	if paused:
		return Protocol.encode_ack(
			Protocol.MessageType.BONUS_ACTION,
			false,
			_server_tick(),
			{"accepted": false, "reason": "paused", "seat_id": seat_id},
			_next_server_sequence()
		)
	var client_tick := int(payload.client_tick)
	var server_tick := _server_tick()
	if client_tick > server_tick + MAX_FUTURE_INPUT_TICKS:
		return _reject(peer_id, REJECT_TICK, "input_too_far_ahead", sequence)
	if client_tick + MAX_OLD_INPUT_TICKS < server_tick:
		return _reject(peer_id, REJECT_TICK, "input_too_old", sequence)
	# The packet tick is a bounded freshness claim. The authoritative sampling
	# tick is server-owned so a client working from the most recent three-tick
	# snapshot cadence cannot create stale controller input or divergent replay
	# metadata.
	var result := simulation.submit_bonus_action(
		seat_id,
		server_tick,
		int(payload.action_kind),
		int(payload.tile_index)
	)
	_buffer_snapshot_events(simulation.get_snapshot().get("events", []))
	return Protocol.encode_ack(
		Protocol.MessageType.BONUS_ACTION,
		bool(result.get("accepted", false)),
		server_tick,
		result,
		_next_server_sequence()
	)


func _handle_shop(
	peer_id: int,
	state: Dictionary,
	payload: Dictionary,
	sequence: int
) -> PackedByteArray:
	if not _state_owns_seat(state, int(payload.seat_id)):
		return _reject(peer_id, REJECT_SEAT, "wrong_seat", sequence)
	var result := simulation.submit_shop_purchase(
		int(payload.seat_id),
		int(payload.item_id),
		int(payload.nonce)
	)
	_buffer_snapshot_events(simulation.get_snapshot().get("events", []))
	return Protocol.encode_ack(
		Protocol.MessageType.SHOP,
		bool(result.accepted),
		_server_tick(),
		result,
		_next_server_sequence()
	)


func _handle_ready(
	peer_id: int,
	state: Dictionary,
	payload: Dictionary,
	sequence: int
) -> PackedByteArray:
	if not _state_owns_seat(state, int(payload.seat_id)):
		return _reject(peer_id, REJECT_SEAT, "wrong_seat", sequence)
	var accepted := simulation.set_shop_ready(int(payload.seat_id), bool(payload.ready))
	_buffer_snapshot_events(simulation.get_snapshot().get("events", []))
	var details := {
		"reason": "accepted" if accepted else simulation.get_last_error(),
		"ready": bool(payload.ready),
	}
	return Protocol.encode_ack(
		Protocol.MessageType.READY,
		accepted,
		_server_tick(),
		details,
		_next_server_sequence()
	)


func _handle_pause(
	peer_id: int,
	state: Dictionary,
	payload: Dictionary,
	sequence: int
) -> PackedByteArray:
	if int(payload.seat_id) != 0 or not _state_owns_seat(state, 0):
		return _reject(peer_id, REJECT_SEAT, "pause_requires_seat_zero", sequence)
	paused = bool(payload.paused)
	var details := {"paused": paused}
	_broadcast_snapshot()
	return Protocol.encode_ack(
		Protocol.MessageType.PAUSE,
		true,
		_server_tick(),
		details,
		_next_server_sequence()
	)


func _handle_retire(
	peer_id: int,
	state: Dictionary,
	payload: Dictionary,
	sequence: int
) -> PackedByteArray:
	var seat_id := int(payload.seat_id)
	if not _state_owns_seat(state, seat_id):
		return _reject(peer_id, REJECT_SEAT, "wrong_seat", sequence)
	# Retail retire lives on the pause menu, so a paused match may retire;
	# the command unpauses into the terminal game-over sequence.
	var result := simulation.request_retire(seat_id)
	if bool(result.get("accepted", false)):
		paused = false
	_buffer_snapshot_events(simulation.get_snapshot().get("events", []))
	_broadcast_snapshot()
	return Protocol.encode_ack(
		Protocol.MessageType.RETIRE,
		bool(result.get("accepted", false)),
		_server_tick(),
		result,
		_next_server_sequence()
	)


## Retail resumes a saved run in place of a fresh one (loader FUN_005384f0).
## The authoritative server owns the numbered slots, so a resumed online match
## reads the slot the SAVE command previously wrote on this same server.
func _resume_saved_run(slot: int) -> bool:
	_resume_error = ""
	var save := _saved_games.load_slot(slot)
	if save.is_empty():
		_resume_error = (
			_saved_games.last_error
			if not _saved_games.last_error.is_empty()
			else "save slot %d is empty" % slot
		)
		return false
	simulation = Simulation.new()
	if not simulation.restore_shop_save(save):
		_resume_error = simulation.get_last_error()
		return false
	_seat_owners.clear()
	_snapshot_events.clear()
	_replay_export_cache = PackedByteArray()
	_match_contract = MatchContract.network_contract(save.get("match_config", {}))
	_expected_content_hash = simulation.get_content_hash()
	return true


## Retail writes its in-shop save from the running game (FUN_00537c80). The
## authoritative simulation owns the state here, so the server writes the slot
## and acknowledges the outcome; the client never serializes gameplay state.
func _handle_save(
	peer_id: int,
	state: Dictionary,
	payload: Dictionary,
	sequence: int
) -> PackedByteArray:
	var seat_id := int(payload.seat_id)
	if not _state_owns_seat(state, seat_id):
		return _reject(peer_id, REJECT_SEAT, "wrong_seat", sequence)
	var slot := int(payload.slot)
	var details := {"slot": slot, "reason": ""}
	var save: Dictionary = simulation.export_shop_save()
	var accepted := false
	if save.is_empty():
		details["reason"] = simulation.get_last_error()
	elif not _saved_games.save_slot(slot, save):
		details["reason"] = _saved_games.last_error
	else:
		accepted = true
	return Protocol.encode_ack(
		Protocol.MessageType.SAVE,
		accepted,
		_server_tick(),
		details,
		_next_server_sequence()
	)


## v7: a seat owner may export the finished match's replay for submission.
## Only terminal matches export — the recording is complete then, and the
## gzip is cached for retries. Chunks ride reliable ordered REPLAY_DATA.
func _handle_replay_request(
	peer_id: int,
	state: Dictionary,
	payload: Dictionary,
	sequence: int
) -> PackedByteArray:
	var seat_id := int(payload.seat_id)
	if not _state_owns_seat(state, seat_id):
		return _reject(peer_id, REJECT_SEAT, "wrong_seat", sequence)
	if simulation == null:
		return _reject(peer_id, REJECT_COMMAND, "no_match", sequence)
	var result: Dictionary = simulation.get_snapshot().get("result", {})
	if result.is_empty():
		return _reject(peer_id, REJECT_COMMAND, "match_not_terminal", sequence)
	if _replay_export_cache.is_empty():
		var replay: Dictionary = simulation.get_replay()
		if replay.is_empty():
			return _reject(peer_id, REJECT_COMMAND, "replay_unavailable", sequence)
		_replay_export_cache = JSON.stringify(replay).to_utf8_buffer().compress(
			FileAccess.COMPRESSION_GZIP
		)
	var total := _replay_export_cache.size()
	var chunk_size := Protocol.MAX_SNAPSHOT_SIZE - 64
	var chunk_count := maxi(1, ceili(float(total) / float(chunk_size)))
	for index in range(chunk_count):
		var start := index * chunk_size
		var chunk := _replay_export_cache.slice(start, mini(start + chunk_size, total))
		_send_to_peer(
			peer_id,
			Protocol.encode_replay_data(index, chunk_count, total, chunk, _next_server_sequence()),
			true
		)
	return Protocol.encode_ack(
		Protocol.MessageType.REPLAY_REQUEST,
		true,
		_server_tick(),
		{"chunk_count": chunk_count, "total_bytes": total},
		_next_server_sequence()
	)


## v8 party chat: the host's game server relays every seat owner's line to
## every authenticated peer. The sender's copy rides back as the response so
## the in-process tests can decode it, and the others get a reliable send.
func _handle_chat(
	peer_id: int,
	state: Dictionary,
	payload: Dictionary,
	sequence: int
) -> PackedByteArray:
	var seat_id := int(payload.seat_id)
	if not _state_owns_seat(state, seat_id):
		return _reject(peer_id, REJECT_SEAT, "wrong_seat", sequence)
	if not _consume_chat_budget(state):
		return Protocol.encode_ack(
			Protocol.MessageType.CHAT,
			false,
			_server_tick(),
			{"reason": "chat_rate"},
			_next_server_sequence()
		)
	var nickname := str(payload.get("nickname", ""))
	if nickname.is_empty():
		nickname = "P%d" % (seat_id + 1)
	var packet := Protocol.encode_chat(seat_id, nickname, str(payload.text), _next_server_sequence())
	if packet.is_empty():
		return _reject(peer_id, REJECT_MALFORMED, "malformed_chat", sequence)
	for other_id in _peers:
		if int(other_id) != peer_id and bool(_peers[other_id].authenticated):
			_send_to_peer(int(other_id), packet, true)
	return packet


## v8 hole punching: only the seat-0 owner (the host) may ask, and only a
## publicly bound server sends. Five quick datagrams open the host's router
## toward the joiner, then one per second keeps the path open while the
## joiner retries its connect.
func _handle_punch(
	peer_id: int,
	state: Dictionary,
	payload: Dictionary,
	sequence: int
) -> PackedByteArray:
	if not _state_owns_seat(state, 0):
		return _reject(peer_id, REJECT_SEAT, "punch_requires_seat_zero", sequence)
	var details := {
		"address": str(payload.address),
		"port": int(payload.port),
		"datagrams": PUNCH_BURST_COUNT,
	}
	if not _lobby or _bind_host == LOOPBACK_HOST:
		details["reason"] = "not_public_bind"
		return Protocol.encode_ack(
			Protocol.MessageType.PUNCH, false, _server_tick(), details, _next_server_sequence()
		)
	if _punch_targets.size() >= MAX_PUNCH_TARGETS:
		details["reason"] = "punch_queue_full"
		return Protocol.encode_ack(
			Protocol.MessageType.PUNCH, false, _server_tick(), details, _next_server_sequence()
		)
	var now_msec := Time.get_ticks_msec()
	_punch_targets.append({
		"address": str(payload.address),
		"port": int(payload.port),
		"burst_left": PUNCH_BURST_COUNT,
		"next_msec": now_msec,
		"deadline_msec": now_msec + PUNCH_DURATION_MSEC,
	})
	_process_punch_queue(now_msec)
	return Protocol.encode_ack(
		Protocol.MessageType.PUNCH, true, _server_tick(), details, _next_server_sequence()
	)


## v8 rendezvous: a hosting server keeps pinging the lobby server's UDP
## socket with its nonce so the router mapping toward the internet stays
## open and the lobby server knows the host's public endpoint. Replies land
## on the ENet socket and are discarded there; the host client learns the
## endpoint from the lobby server over WebSocket instead.
func configure_rendezvous(address: String, port: int, nonce_hex: String) -> Dictionary:
	if not address.is_valid_ip_address():
		return _start_result(false, "rendezvous address must be an IP address")
	if port < 1 or port > 65535:
		return _start_result(false, "rendezvous port is out of range")
	var nonce := RendezvousCodec.nonce_from_hex(nonce_hex)
	if nonce.is_empty():
		return _start_result(false, "rendezvous nonce must be 32 hex characters")
	_rendezvous = {"address": address, "port": port, "nonce": nonce}
	_rendezvous_next_msec = 0
	if running:
		send_rendezvous_keepalive()
	return _start_result(true, "")


func send_rendezvous_keepalive() -> bool:
	if _rendezvous.is_empty():
		return false
	_rendezvous_next_msec = Time.get_ticks_msec() + RENDEZVOUS_KEEPALIVE_MSEC
	var sent := _send_raw_datagram(
		str(_rendezvous.address),
		int(_rendezvous.port),
		RendezvousCodec.encode_ping(_rendezvous.nonce)
	)
	if sent:
		_rendezvous_keepalives_sent += 1
	return sent


func _process_punch_queue(now_msec: int) -> void:
	if _punch_targets.is_empty():
		return
	var remaining: Array[Dictionary] = []
	for target in _punch_targets:
		if now_msec > int(target.deadline_msec):
			continue
		while now_msec >= int(target.next_msec) and now_msec <= int(target.deadline_msec):
			_send_raw_datagram(
				str(target.address),
				int(target.port),
				RendezvousCodec.encode_punch(_rendezvous.get("nonce", PackedByteArray()))
			)
			if int(target.burst_left) > 0:
				target.burst_left = int(target.burst_left) - 1
				target.next_msec = int(target.next_msec) + PUNCH_BURST_INTERVAL_MSEC
			else:
				target.next_msec = int(target.next_msec) + PUNCH_TAIL_INTERVAL_MSEC
		remaining.append(target)
	_punch_targets = remaining


## Raw datagrams leave through the very socket ENet listens on, so the
## router mapping they open is the one joiners must hit.
func _send_raw_datagram(address: String, port: int, bytes: PackedByteArray) -> bool:
	if _peer == null:
		return false
	var host: ENetConnection = _peer.host
	if host == null:
		return false
	host.socket_send(address, port, bytes)
	_raw_datagrams_sent += 1
	return true


func _consume_chat_budget(state: Dictionary) -> bool:
	var now_msec := Time.get_ticks_msec()
	if now_msec - int(state.get("chat_window_started_msec", 0)) >= RATE_WINDOW_MSEC:
		state.chat_window_started_msec = now_msec
		state.chat_in_window = 0
	if int(state.get("chat_in_window", 0)) >= MAX_CHAT_PER_WINDOW:
		return false
	state.chat_in_window = int(state.get("chat_in_window", 0)) + 1
	return true


func _broadcast_snapshot() -> Dictionary:
	var snapshot := simulation.get_snapshot()
	snapshot["events"] = _snapshot_events.duplicate(true)
	snapshot["state_hash"] = simulation.state_hash()
	snapshot["paused"] = paused
	snapshot["waiting_for_seats"] = _seat_owners.size() < _required_seat_count()
	snapshot["required_seats"] = _required_seat_count()
	var packet := Protocol.encode_snapshot(snapshot, _next_server_sequence())
	if packet.is_empty():
		_snapshot_events.clear()
		return snapshot
	_snapshot_events.clear()
	for peer_id in _peers:
		var state: Dictionary = _peers[peer_id]
		if bool(state.authenticated):
			_send_to_peer(int(peer_id), packet, true)
	return snapshot


func _buffer_snapshot_events(events: Array) -> void:
	for event_value in events:
		if not event_value is Dictionary:
			continue
		var event: Dictionary = event_value
		var event_id := int(event.get("event_id", 0))
		if event_id > 0:
			if event_id <= _last_buffered_event_id:
				continue
			_last_buffered_event_id = event_id
		_snapshot_events.append(event.duplicate(true))
	if _snapshot_events.size() > MAX_BUFFERED_SNAPSHOT_EVENTS:
		_snapshot_events = _snapshot_events.slice(
			_snapshot_events.size() - MAX_BUFFERED_SNAPSHOT_EVENTS
		)


func _send_to_peer(peer_id: int, packet: PackedByteArray, reliable: bool) -> void:
	if _peer == null or packet.is_empty():
		return
	# A peer that is mid-disconnect still sits in the ENet map for a moment
	# with no channels; sending to it only prints an engine error.
	if not _peers.has(peer_id):
		return
	var enet_peer: ENetPacketPeer = _peer.get_peer(peer_id)
	if enet_peer == null or enet_peer.get_state() != ENetPacketPeer.STATE_CONNECTED:
		return
	_peer.set_target_peer(peer_id)
	_peer.transfer_mode = (
		MultiplayerPeer.TRANSFER_MODE_RELIABLE
		if reliable
		else MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED
	)
	_peer.put_packet(packet)


## Binds the requested port first and otherwise walks the dynamic range, so a
## host whose preferred port is busy still starts; the ready file reports
## the port that actually bound.
func _bind(bind_host: String, requested_port: int) -> Dictionary:
	var candidates: Array[int] = []
	if requested_port != 0:
		candidates.append(requested_port)
	var random_bytes := Crypto.new().generate_random_bytes(2)
	var random_value := (int(random_bytes[0]) << 8) | int(random_bytes[1])
	var start_port := MIN_DYNAMIC_PORT + random_value % DYNAMIC_PORT_SPAN
	for attempt in range(64):
		candidates.append(MIN_DYNAMIC_PORT + ((start_port - MIN_DYNAMIC_PORT + attempt) % DYNAMIC_PORT_SPAN))
	var max_clients := MAX_CLIENTS if bind_host == LOOPBACK_HOST else MAX_PUBLIC_CLIENTS
	for candidate in candidates:
		var candidate_peer := ENetMultiplayerPeer.new()
		candidate_peer.set_bind_ip(bind_host)
		var error := candidate_peer.create_server(candidate, max_clients)
		if error == OK:
			_peer = candidate_peer
			return {"ok": true, "error": "", "port": candidate}
	return {
		"ok": false,
		"error": "could not bind an available port on %s" % bind_host,
		"port": 0,
	}


func _generate_session_token() -> String:
	return Crypto.new().generate_random_bytes(24).hex_encode()


func _on_peer_connected(peer_id: int) -> void:
	_ensure_peer(peer_id)


func _on_peer_disconnected(peer_id: int) -> Dictionary:
	if not _peers.has(peer_id):
		return {}
	var state: Dictionary = _peers[peer_id]
	var released_seat := false
	for seat_id in state.seat_ids:
		if _seat_owners.has(seat_id) and int(_seat_owners[seat_id]) == peer_id:
			if simulation != null:
				simulation.clear_transient_seat_state(int(seat_id))
			_seat_owners.erase(seat_id)
			released_seat = true
	_peers.erase(peer_id)
	var snapshot: Dictionary = {}
	if released_seat and simulation != null:
		snapshot = _broadcast_snapshot()
	if _lobby and simulation != null and not _has_authenticated_peer():
		# A lobby server outlives its matches: when the last authenticated
		# peer leaves, the match is torn down and the listener waits for the
		# next HELLO-configured match.
		_reset_lobby_match()
	return snapshot


func _has_authenticated_peer() -> bool:
	for peer_id in _peers:
		if bool(_peers[peer_id].authenticated):
			return true
	return false


func _reset_lobby_match() -> void:
	simulation = null
	_match_contract = {}
	_seat_owners.clear()
	_snapshot_events.clear()
	_last_buffered_event_id = 0
	_replay_export_cache = PackedByteArray()
	paused = false


func _ensure_peer(peer_id: int) -> void:
	if _peers.has(peer_id):
		return
	var now_msec := Time.get_ticks_msec()
	_peers[peer_id] = {
		"authenticated": false,
		"seat_id": -1,
		"seat_ids": [],
		"last_sequence": -1,
		"last_control_sequence": -1,
		"last_input_sequence": -1,
		"window_started_msec": now_msec,
		"messages_in_window": 0,
		"rejections": 0,
		"unauthenticated_rejections": 0,
		"handshake_deadline_msec": now_msec + HANDSHAKE_TIMEOUT_MSEC,
		"chat_window_started_msec": now_msec,
		"chat_in_window": 0,
	}


func _expire_unauthenticated_peers(now_msec: int) -> Array[int]:
	var expired_peer_ids: Array[int] = []
	for peer_id_value in _peers.keys():
		var peer_id := int(peer_id_value)
		var state: Dictionary = _peers[peer_id]
		if (
			not bool(state.authenticated)
			and now_msec >= int(state.handshake_deadline_msec)
		):
			expired_peer_ids.append(peer_id)
	for peer_id in expired_peer_ids:
		_record_rejection(peer_id, "handshake_timeout")
		_drop_peer(peer_id)
	return expired_peer_ids


func _consume_rate_budget(state: Dictionary) -> bool:
	var now_msec := Time.get_ticks_msec()
	if now_msec - int(state.window_started_msec) >= RATE_WINDOW_MSEC:
		state.window_started_msec = now_msec
		state.messages_in_window = 0
	if int(state.messages_in_window) >= MAX_MESSAGES_PER_RATE_WINDOW:
		return false
	state.messages_in_window = int(state.messages_in_window) + 1
	return true


func _reject(peer_id: int, code: int, reason: String, request_sequence: int) -> PackedByteArray:
	_record_rejection(peer_id, reason)
	if code in [REJECT_AUTH, REJECT_CONTENT, REJECT_SEAT]:
		if _record_unauthenticated_rejection(peer_id):
			return PackedByteArray()
	return Protocol.encode_reject(code, reason, request_sequence)


func _record_rejection(peer_id: int, reason: String) -> void:
	_rejection_counters.total = int(_rejection_counters.total) + 1
	var by_reason: Dictionary = _rejection_counters.by_reason
	by_reason[reason] = int(by_reason.get(reason, 0)) + 1
	if _peers.has(peer_id):
		_peers[peer_id].rejections = int(_peers[peer_id].rejections) + 1


func _record_unauthenticated_rejection(peer_id: int) -> bool:
	if not _peers.has(peer_id):
		return false
	var state: Dictionary = _peers[peer_id]
	if bool(state.authenticated):
		return false
	state.unauthenticated_rejections = int(state.unauthenticated_rejections) + 1
	if int(state.unauthenticated_rejections) < MAX_UNAUTHENTICATED_REJECTIONS:
		return false
	_drop_peer(peer_id)
	return true


func _drop_peer(peer_id: int) -> void:
	if _peer != null:
		_peer.disconnect_peer(peer_id)
	if _peers.has(peer_id):
		_on_peer_disconnected(peer_id)


func _server_tick() -> int:
	if simulation == null:
		return 0
	return int(simulation.get_snapshot().get("tick", 0))


func _required_seat_count() -> int:
	if simulation == null or _match_contract.is_empty():
		return 0
	# Time Trial is single-seat like solo; only simultaneous co-op fills two
	# seats. The previous solo-only test left a networked Time Trial waiting
	# for a second seat that could never exist.
	return MatchContract.seat_count_for_mode(str(_match_contract.get("mode", "solo")))


func _state_owns_seat(state: Dictionary, seat_id: int) -> bool:
	return state.seat_ids.has(seat_id)


func _next_server_sequence() -> int:
	var value := _server_sequence
	_server_sequence += 1
	return value


func _start_result(ok: bool, error: String) -> Dictionary:
	return {
		"ok": ok,
		"error": error,
		"port": listen_port,
		"token": session_token,
		"content_hash": _content_hash(),
	}

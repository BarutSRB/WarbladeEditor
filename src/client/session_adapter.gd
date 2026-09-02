class_name WBClientSession
extends Node

signal snapshot_received(snapshot: Dictionary)
signal status_changed(status: String)
signal session_failed(message: String)
signal sound_requested(key: String)
signal audio_requested(request: Dictionary)
signal pause_changed(paused: bool)
signal purchase_completed(result: Dictionary)
signal save_completed(accepted: bool, details: Dictionary)
signal replay_ready(replay: Dictionary)
signal replay_failed(reason: String)
signal chat_received(seat_id: int, nickname: String, text: String)
signal punch_acknowledged(accepted: bool, details: Dictionary)

const WEAPON_CONTENT_PATH := "res://content/weapons.json"
const MAX_SEEN_AUDIO_EVENTS := 4096

var _network := WBNetworkSessionAdapter.new()
var _config: Dictionary = {}
var _snapshot: Dictionary = {}
var _active := false
var _paused := false
var _pause_pending := false
var _nonce := 1
var _weapon_sounds: Dictionary = {}
var _seen_audio_events: Dictionary = {}
var _seen_audio_event_order: Array[String] = []


func _init() -> void:
	_weapon_sounds = load_weapon_sounds(WEAPON_CONTENT_PATH)
	_network.snapshot_received.connect(_on_network_snapshot)
	_network.status_changed.connect(func(status: String) -> void: status_changed.emit(status))
	_network.session_failed.connect(_on_network_failure)
	_network.command_acknowledged.connect(_on_command_acknowledged)
	_network.replay_ready.connect(func(replay: Dictionary) -> void: replay_ready.emit(replay))
	_network.replay_failed.connect(func(reason: String) -> void: replay_failed.emit(reason))
	_network.chat_received.connect(
		func(seat_id: int, nickname: String, text: String) -> void:
			chat_received.emit(seat_id, nickname, text)
	)
	_network.punch_acknowledged.connect(
		func(accepted: bool, details: Dictionary) -> void:
			punch_acknowledged.emit(accepted, details)
	)


func _process(_delta: float) -> void:
	if _active:
		_network.poll()


func _exit_tree() -> void:
	close()


## Every session is a game-server connection; the client never simulates
## gameplay. The server is resolved in this order: an explicit --connect
## override, the match configuration's "server" dictionary (a direct
## endpoint, a hosted game, or a join), and otherwise the local sidecar this
## machine spawns for solo and couch play.
func begin(match_config: Dictionary) -> bool:
	close()
	_config = match_config.duplicate(true)
	_nonce = 1
	_paused = false
	_pause_pending = false
	status_changed.emit("starting")
	if not WBMatchConfig.validate(_config):
		session_failed.emit("The selected match configuration is invalid.")
		return false
	var options := _resolve_connection_options()
	if not bool(options.get("ok", false)):
		session_failed.emit(str(options.get("error", "The game server is not configured.")))
		return false
	if not _network.configure(_config, options.get("connection", {})):
		session_failed.emit(_network.last_error())
		return false
	_active = true
	return true


func _resolve_connection_options() -> Dictionary:
	var args := WBCliArgs.new()
	var connect_host := args.value("connect")
	if not connect_host.is_empty():
		return {"ok": true, "connection": {
			"kind": "direct",
			"host": connect_host,
			"port": args.integer("port", 0),
			"token": args.value("token"),
			"seat": args.integer("client-seat", 0),
		}}
	var server_value: Variant = _config.get("server", {})
	var server: Dictionary = server_value if server_value is Dictionary else {}
	match str(server.get("kind", "local")):
		"direct":
			var host := str(server.get("host", "")).strip_edges()
			var port := int(server.get("port", 0))
			var token := str(server.get("token", ""))
			if host.is_empty() or port < 1024 or port > 65535 or token.is_empty():
				return {
					"ok": false,
					"error": (
						"The host connection is incomplete. "
						+ "Enter the host's address, port, and token."
					),
				}
			var connection := server.duplicate(true)
			connection["host"] = host
			return {"ok": true, "connection": connection}
		"host", "join":
			return {"ok": true, "connection": server.duplicate(true)}
	# The local sidecar: empty connection options make the network adapter
	# spawn and manage the loopback lobby server.
	return {"ok": true, "connection": {}}


func server_description() -> String:
	return _network.endpoint_description()


## The UDP port the hosting sidecar actually bound (0 when not hosting).
func listen_port() -> int:
	return _network.listen_port()


## v8 party chat through the host's game server.
func send_chat(text: String, nickname: String) -> bool:
	if not _active:
		return false
	return _network.send_chat(text, nickname)


## v8 hole punching: the host asks its sidecar to open the path to a joiner.
func punch_request(address: String, port: int) -> bool:
	if not _active:
		return false
	return _network.punch_request(address, port)


func is_local_test_server() -> bool:
	return _network.is_local_test_server()


func submit_input(seat: int, mask: int) -> bool:
	if not _active or _paused or _pause_pending:
		return false
	return _network.submit_input(seat, mask)


func submit_bonus_action(
	seat: int,
	action_kind: int,
	tile_index: int = -1
) -> Dictionary:
	if not _active or _paused or _pause_pending:
		return {"accepted": false, "reason": "inactive"}
	return _network.submit_bonus_action(seat, action_kind, tile_index)


func advance_tick() -> Dictionary:
	if not _active:
		return _snapshot
	_network.poll()
	return _snapshot


func snapshot() -> Dictionary:
	return _snapshot.duplicate(true)


func request_purchase(seat: int, item_id: int) -> Dictionary:
	if not _active:
		return {"accepted": false, "reason": "inactive"}
	var result := _network.submit_shop_purchase(seat, item_id, _nonce)
	_nonce += 1
	if bool(result.get("accepted", false)) and not bool(result.get("pending", false)):
		sound_requested.emit("purchase")
	return result


func set_ready(seat: int, ready: bool) -> bool:
	if not _active:
		return false
	return _network.set_shop_ready(seat, ready)


func set_paused(paused: bool) -> void:
	if not _active or _pause_pending or paused == _paused:
		return
	if _network.request_pause(paused):
		_pause_pending = true
		status_changed.emit("pause_pending")


func request_retire() -> bool:
	# Retail pause-menu retire: ends the run as if the last fighter was lost;
	# the standard game-over tally and profile statistics follow.
	if not _active:
		return false
	return _network.request_retire()


## Retail only offers a saved game from the shop. The authoritative server
## owns the run state and writes the numbered slot itself; the client only
## carries the request.
func can_save_run() -> bool:
	return _active


## v7: exports the finished match's replay for submission (replay_ready /
## replay_failed answer asynchronously). Call before close() — closing kills
## the sidecar and the recording with it.
func request_replay(seat: int = 0) -> bool:
	return _network.request_replay(seat)


func request_save(slot: int) -> bool:
	if not _active:
		return false
	return _network.request_save(slot)


func is_paused() -> bool:
	return _paused


func is_active() -> bool:
	return _active


func state_hash() -> String:
	return _network.state_hash()


func local_seat_for_authoritative(authoritative_seat: int) -> int:
	return _network.local_seat_for_authoritative(authoritative_seat)


func is_placeholder() -> bool:
	return bool(_snapshot.get("using_fallback_content", false))


func close() -> void:
	_network.close()
	_active = false
	_paused = false
	_pause_pending = false
	_snapshot.clear()
	_seen_audio_events.clear()
	_seen_audio_event_order.clear()
	status_changed.emit("closed")


func _on_network_snapshot(snapshot: Dictionary) -> void:
	var previous := _snapshot
	_snapshot = snapshot.duplicate(true)
	var waiting_for_seats := bool(_snapshot.get("waiting_for_seats", false))
	var was_waiting := bool(previous.get("waiting_for_seats", false))
	if waiting_for_seats:
		status_changed.emit("waiting_for_seats")
	elif was_waiting:
		status_changed.emit("paused" if _paused else "ready")
	if _snapshot.has("paused"):
		var authoritative_pause := bool(_snapshot.paused)
		if authoritative_pause != _paused:
			_pause_pending = false
			_apply_pause(authoritative_pause)
	_emit_audio_events(previous, _snapshot)
	snapshot_received.emit(_snapshot)


func _on_network_failure(message: String) -> void:
	_active = false
	session_failed.emit(message)


func _on_command_acknowledged(request_type: int, accepted: bool, details: Dictionary) -> void:
	if request_type == ProtocolCodec.MessageType.SHOP:
		var result := details.duplicate(true)
		result["accepted"] = accepted
		purchase_completed.emit(result)
		if accepted:
			sound_requested.emit("purchase")
	if request_type == ProtocolCodec.MessageType.SAVE:
		save_completed.emit(accepted, details)
	if request_type == ProtocolCodec.MessageType.PAUSE:
		_pause_pending = false
		if accepted:
			_apply_pause(bool(details.get("paused", _paused)))
		else:
			status_changed.emit("ready" if not _paused else "paused")


func _apply_pause(paused: bool) -> void:
	if paused == _paused:
		return
	_paused = paused
	status_changed.emit("paused" if paused else "ready")
	pause_changed.emit(paused)


func _emit_audio_events(previous: Dictionary, current: Dictionary) -> void:
	if previous.is_empty():
		return
	var emitted_level_complete := false
	var event_index := 0
	for event_value in current.get("events", []):
		if not event_value is Dictionary:
			event_index += 1
			continue
		var event: Dictionary = event_value
		var event_identity := _audio_event_identity(event, current, event_index)
		event_index += 1
		if not _remember_audio_event(event_identity):
			continue
		var request := _audio_request_for_event(event, current)
		if request.is_empty():
			continue
		request["event_id"] = event_identity
		request["tick"] = int(event.get("tick", current.get("tick", 0)))
		if str(request.get("kind", "")) == "level_completed":
			emitted_level_complete = true
		_dispatch_audio_request(request)
	if str(previous.get("phase", "")) != str(current.get("phase", "")):
		match str(current.get("phase", "")):
			"shop":
				sound_requested.emit("music_shop")
			"bonus_mode":
				var bonus_kind := str(
					current.get("bonus_mode", {}).get("kind", "")
				)
				if bonus_kind == "memory_station":
					sound_requested.emit("music_memory")
				elif bonus_kind == "meteor_storm":
					sound_requested.emit("music_meteor")
			"level":
				var boss_value: Variant = current.get("boss", {})
				var boss_active := (
					boss_value is Dictionary
					and bool((boss_value as Dictionary).get("active", false))
				)
				if not boss_active:
					sound_requested.emit("music_warblade")
			"get_ready":
				var previous_phase := str(previous.get("phase", ""))
				var came_from_promotion := previous_phase == "rank_promotion"
				if came_from_promotion or previous_phase == "credits":
					sound_requested.emit("music_warblade")
				_dispatch_audio_request({
					"category": "voice",
					"key": "getready",
					"priority": 90,
					"max_voices": 1,
				})
			"rank_promotion":
				sound_requested.emit("music_promoted")
			"complete":
				if not emitted_level_complete:
					sound_requested.emit("levelcomplete")
			"game_over":
				sound_requested.emit("gameover")
				_dispatch_audio_request({
					"category": "voice",
					"key": "gameover",
					"priority": 100,
					"max_voices": 1,
				})


static func load_weapon_sounds(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	var result: Dictionary = {}
	if not parsed is Dictionary:
		return result
	for weapon_value in parsed.get("weapons", []):
		if not weapon_value is Dictionary:
			continue
		var weapon: Dictionary = weapon_value
		var weapon_id := int(weapon.get("id", -1))
		var sound := str(weapon.get("sound", "")).strip_edges().to_lower()
		if weapon_id >= 0 and not sound.is_empty():
			result[weapon_id] = sound
	return result


func _audio_request_for_event(event: Dictionary, current: Dictionary) -> Dictionary:
	var kind := _event_kind(event)
	var request: Dictionary = {"category": "sfx", "kind": kind}
	match kind:
		"weapon_fired":
			request["key"] = str(_weapon_sounds.get(int(event.get("weapon_id", 0)), "singleshot"))
			request["priority"] = 45
		"enemy_fired", "enemy_fire", "enemy_weapon_fired":
			request["key"] = _enemy_shot_sound(event, current)
			request["priority"] = 25
			request["max_voices"] = 15
		"enemy_hit", "enemy_damaged":
			request["key"] = "hit1"
			request["priority"] = 25
			request["max_voices"] = 12
		"enemy_destroyed":
			request["key"] = "explo1"
			request["priority"] = 35
			request["max_voices"] = 8
		"armour_hit":
			request["key"] = "hit2"
			request["priority"] = 70
			request["max_voices"] = 4
		"player_destroyed":
			request["key"] = "explo3"
			request["priority"] = 90
			request["max_voices"] = 4
		"rank_promotion_firework":
			var firework_key := _event_sound_key(event)
			request["key"] = "explo3" if firework_key.is_empty() else firework_key
			request["priority"] = 35
			request["max_voices"] = 8
		"rank_promotion_voice":
			var promotion_voice_key := _event_voice_key(event)
			if promotion_voice_key.is_empty():
				return {}
			request["category"] = "voice"
			request["key"] = promotion_voice_key
			request["priority"] = 95
			request["max_voices"] = 1
		"voice_cue":
			var voice_key := _event_voice_key(event)
			if voice_key.is_empty():
				return {}
			request["category"] = "voice"
			request["key"] = voice_key
			request["priority"] = 95
			request["max_voices"] = 1
		"music_cue":
			var music_key := str(event.get("key", "")).strip_edges().to_lower()
			var music_action := str(event.get("action", "play")).to_lower()
			if music_key.is_empty() or music_action != "play":
				return {}
			request["category"] = "music"
			request["key"] = music_key
			request["action"] = "play"
		"sound_cue":
			var cue_key := str(event.get("key", _event_sound_key(event))).to_lower()
			if cue_key.is_empty():
				return {}
			request["key"] = cue_key
			request["priority"] = 80
			request["max_voices"] = 2
		"memory_countdown":
			request["key"] = _countdown_voice_key(int(event.get("seconds", 0)))
			if str(request.key).is_empty():
				return {}
			request["category"] = "voice"
			request["priority"] = 90
			request["max_voices"] = 1
			request["drop_if_voice_busy"] = true
		"countdown_cue":
			request["key"] = _countdown_voice_key(int(event.get("value", 0)))
			if str(request.key).is_empty():
				return {}
			request["category"] = "voice"
			request["priority"] = 90
			request["max_voices"] = 1
		"player_reentry_requested":
			request["key"] = "coming"
			request["priority"] = 60
			request["max_voices"] = 2
		"player_respawned":
			request["key"] = "birth"
			request["priority"] = 65
			request["max_voices"] = 4
		"pickup_collected":
			request["key"] = _pickup_sound(event)
			request["priority"] = 55
			request["max_voices"] = 6
		"level_completed":
			request["key"] = "fanfare"
			request["priority"] = 100
			request["max_voices"] = 2
		"ui_click":
			request["key"] = "buttonclick"
			request["priority"] = 75
			request["max_voices"] = 4
		"ui_hover":
			request["key"] = "rollover"
			request["priority"] = 15
			request["max_voices"] = 2
		"shop_purchase_rejected":
			request["key"] = "buzzer"
			request["priority"] = 80
			request["max_voices"] = 2
		"warp_malfunction_started":
			request["key"] = _event_sound_key(event)
			request["priority"] = 80
			request["max_voices"] = 1
		"warp_malfunction_message_cue":
			request["category"] = "voice"
			request["key"] = _event_voice_key(event)
			request["priority"] = 100
			request["max_voices"] = 1
		"audio_loop_started", "ambience_started":
			var loop_key := _event_sound_key(event)
			if loop_key.is_empty():
				return {}
			request["key"] = loop_key
			request["action"] = "start_loop"
			request["handle"] = _event_loop_handle(event)
			request["priority"] = 20
		"audio_loop_stopped", "ambience_stopped":
			request["action"] = "stop_loop"
			request["handle"] = _event_loop_handle(event)
		"boss_hum_pitch":
			var hum_handle := _event_loop_handle(event)
			if hum_handle.is_empty():
				return {}
			request["key"] = _event_sound_key(event)
			request["action"] = "update_loop"
			request["handle"] = hum_handle
			request["duration_ms"] = maxi(0, int(event.get("duration_ms", 0)))
		_:
			return {}
	_attach_event_position(request, event, current)
	_copy_presentation_fields(request, event)
	return request


func _countdown_voice_key(value: int) -> String:
	if value < 1 or value > 10:
		return ""
	return [
		"", "one", "two", "three", "four", "five",
		"six", "seven", "eight", "nine", "ten",
	][value]


func _event_kind(event: Dictionary) -> String:
	if event.has("type"):
		return str(event.get("type", ""))
	return str(event.get("kind", ""))


func _pickup_sound(event: Dictionary) -> String:
	var pickup_kind := str(event.get("pickup_kind", ""))
	if pickup_kind.is_empty() and event.has("type"):
		pickup_kind = str(event.get("kind", ""))
	match pickup_kind:
		"money":
			return "coin"
		"armour":
			return "bing"
		"letter":
			return "bell1"
		"bonus_time":
			return "bell2"
	return "bing"


func _enemy_shot_sound(event: Dictionary, _current: Dictionary) -> String:
	var explicit := _event_sound_key(event)
	if not explicit.is_empty():
		return explicit
	if int(event.get("enemy_projectile_type", 7)) == 6:
		return "alienshoot2"
	return "alienshoot10"


func _event_sound_key(event: Dictionary) -> String:
	for field in ["sound_key", "sfx_key", "sample"]:
		var value := str(event.get(field, "")).strip_edges().to_lower()
		if not value.is_empty():
			return value
	return ""


func _event_voice_key(event: Dictionary) -> String:
	for field in ["voice_key", "key", "sound_key", "sfx_key", "sample"]:
		var value := str(event.get(field, "")).strip_edges().to_lower()
		if not value.is_empty():
			return value.replace("_", "").replace("-", "").replace(" ", "")
	return ""


func _event_loop_handle(event: Dictionary) -> String:
	var explicit := str(event.get("handle", ""))
	if not explicit.is_empty():
		return explicit
	return "%s:%s" % [
		str(event.get("entity_id", event.get("enemy_id", event.get("seat_id", 0)))),
		_event_sound_key(event),
	]


func _attach_event_position(request: Dictionary, event: Dictionary, current: Dictionary) -> void:
	if event.has("x_fp"):
		request["x_fp"] = int(event.get("x_fp", 0))
		request["y_fp"] = int(event.get("y_fp", 0))
		return
	if event.has("seat_id"):
		var seat_id := int(event.get("seat_id", -1))
		for player_value in current.get("players", []):
			if not player_value is Dictionary:
				continue
			var player: Dictionary = player_value
			if int(player.get("seat_id", -2)) == seat_id:
				request["x_fp"] = int(player.get("x_fp", 400 * 65536))
				request["y_fp"] = int(player.get("y_fp", 300 * 65536))
				return
	var entity_id := int(event.get("entity_id", event.get("enemy_id", -1)))
	if entity_id < 0:
		return
	for enemy_value in current.get("enemies", []):
		if not enemy_value is Dictionary:
			continue
		var enemy: Dictionary = enemy_value
		if int(enemy.get("id", -2)) == entity_id:
			request["x_fp"] = int(enemy.get("x_fp", 400 * 65536))
			request["y_fp"] = int(enemy.get("y_fp", 300 * 65536))
			return


func _copy_presentation_fields(request: Dictionary, event: Dictionary) -> void:
	if event.get("presentation") is Dictionary:
		request["presentation"] = (event["presentation"] as Dictionary).duplicate(true)
	for field in [
		"priority",
		"max_voices",
		"volume_index",
		"volume_linear",
		"frequency_hz",
		"source_hz",
		"pitch_scale",
		"pitch_min",
		"pitch_max",
		"delay_ms",
		"queue_padding_ms",
		"drop_if_voice_busy",
		# Gem Drop preserves the executable's raw BASS pan attribute as
		# evidence. The AudioDirector performs the explicit Godot adaptation
		# from its accompanying source-table index.
		"legacy_pan_attribute_raw",
		"legacy_pan_table_index",
	]:
		if event.has(field):
			request[field] = event[field]


func _audio_event_identity(event: Dictionary, current: Dictionary, event_index: int) -> String:
	if event.has("event_id"):
		return "event:%s" % str(event["event_id"])
	return "fallback:%s:%s:%s:%s:%s:%s:%s" % [
		str(event.get("tick", current.get("tick", 0))),
		str(event_index),
		_event_kind(event),
		str(event.get("entity_id", event.get("enemy_id", ""))),
		str(event.get("seat_id", "")),
		str(event.get("weapon_id", "")),
		str(event.get("pickup_kind", event.get("kind", ""))),
	]


func _remember_audio_event(identity: String) -> bool:
	if _seen_audio_events.has(identity):
		return false
	_seen_audio_events[identity] = true
	_seen_audio_event_order.append(identity)
	while _seen_audio_event_order.size() > MAX_SEEN_AUDIO_EVENTS:
		_seen_audio_events.erase(_seen_audio_event_order.pop_front())
	return true


func _dispatch_audio_request(request: Dictionary) -> void:
	if audio_requested.get_connections().is_empty():
		sound_requested.emit(str(request.get("key", "")))
		return
	audio_requested.emit(request)

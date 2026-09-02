class_name GemDropSimulation
extends RefCounted

# WarBlade 1.34 state-18 Gem Drop controller. The ordinary combat-pool reset
# remains a parent callback because its RNG count depends on the live captive
# slots. The callback is deliberately invoked before the ten-slot initializer
# and again at terminal completion, at the executable's exact call sites.

const RETAIL_EXECUTABLE_SHA256: String = (
	"ddf1778c307af1087ff9dcb512786111e665d972298aeaac3f1b4b2996d079ef"
)
const FP_ONE: int = 65536
const SLOT_COUNT: int = 10
const INTRO_MS: int = 4000
const DURATION_INITIAL: float = 2680.0
const ACTIVE_TARGET_INITIAL: float = 1.0
const ACTIVE_TARGET_GROWTH: float = 0.0020000000949949026
const GEM_WIDTH: int = 80
const GEM_HEIGHT: int = 51
const PLAYER_WIDTH: int = 40
const PLAYER_COLLISION_HEIGHT: int = 27
const OFFSCREEN_BOTTOM: float = 656.0
const MAX_SCORE: int = 250000000

const STAGE_IDLE: String = "idle"
const STAGE_INTRO: String = "intro"
const STAGE_ACTIVE: String = "active"
const STAGE_COMPLETE: String = "complete"

const NORMAL_REWARDS: Array[int] = [50000, 100000, 500000]
const SUPER_REWARDS: Array[int] = [1000000, 5000000, 10000000]

var _configured: bool = false
var _last_error: String = ""
var _config: Dictionary = {}
var _rng_source: Variant = null
var _rng_draws_since_enter: int = 0

var _owner_seat_id: int = -1
var _source_mode: String = ""
var _session_mode: String = "solo"
var _super_gem_drop: bool = false
var _stage: String = STAGE_IDLE
var _tick: int = 0
var _now_ms: int = 0
var _entry_tick: int = 0
var _entry_ms: int = 0
var _intro_until_ms: int = 0
var _remaining: float = DURATION_INITIAL
var _active_target: float = ACTIVE_TARGET_INITIAL
var _active_count: int = 0
var _next_spawn_serial: int = 1
var _slots: Array[Dictionary] = []
var _players: Array[Dictionary] = []
var _starting_scores: Array[int] = [0, 0]
var _score_deltas: Array[int] = [0, 0]
var _score_multipliers: Array[int] = [1, 1]
var _next_event_id: int = 1
var _completion_state: Dictionary = {}
var _pool_reset_entry: Dictionary = {}
var _pool_reset_terminal: Dictionary = {}


static func retail_contract() -> Dictionary:
	return {
		"executable_sha256": RETAIL_EXECUTABLE_SHA256,
		"surface_width": 800,
		"surface_height": 600,
		"intro_ms": INTRO_MS,
		"slot_count": SLOT_COUNT,
		"tick_scale": 1.0,
		"collision_query": Callable(),
		"pool_reset_callback": Callable(),
		"assets": {
			"texture": "diamantbig",
			"mask": "diamantbig",
			"music": "gems",
		},
		"evidence": {
			"entry": "0x005f8750",
			"pool_reset": "0x0059bb90",
			"update": "0x006014d0",
			"collision": "0x00600e90",
			"renderer": "0x00600b20",
			"terminal": "0x00601a0f",
		},
	}


func configure(contract: Dictionary) -> bool:
	_last_error = ""
	var merged := retail_contract()
	merged.merge(contract, true)
	if String(merged.get("executable_sha256", "")) != RETAIL_EXECUTABLE_SHA256:
		return _set_error("Gem Drop contract does not match the pinned executable")
	if int(merged.get("surface_width", 0)) != 800 or int(merged.get("surface_height", 0)) != 600:
		return _set_error("Gem Drop retail coordinates require an 800x600 surface")
	if int(merged.get("slot_count", 0)) != SLOT_COUNT:
		return _set_error("Gem Drop retail state requires exactly 10 slots")
	if float(merged.get("tick_scale", 0.0)) <= 0.0:
		return _set_error("tick_scale must be positive")
	for callable_key in ["collision_query", "pool_reset_callback"]:
		var candidate: Variant = merged.get(callable_key, Callable())
		if candidate != null and not (candidate is Callable):
			return _set_error("%s must be a Callable" % callable_key)
	_config = merged.duplicate(true)
	_configured = true
	return true


func enter(
	owner_seat_id: int,
	source_mode: String,
	super_gem_drop: bool,
	players_value: Array,
	progressions_value: Array,
	session_mode: String,
	rng_source: Variant,
	tick: int = 0,
	now_ms: int = 0,
	restart_music: bool = true
) -> Dictionary:
	_last_error = ""
	if not _configured:
		_set_error("Gem Drop is not configured")
		return _error_result(tick, now_ms)
	if owner_seat_id < 0 or owner_seat_id > 1:
		_set_error("owner_seat_id must identify seat zero or one")
		return _error_result(tick, now_ms)
	if tick < 0 or now_ms < 0:
		_set_error("entry tick and milliseconds must be non-negative")
		return _error_result(tick, now_ms)
	if not _is_rng_source_valid(rng_source):
		_set_error("rng_source must expose next_range(), next_float32(), and snapshot()")
		return _error_result(tick, now_ms)

	_owner_seat_id = owner_seat_id
	_source_mode = source_mode
	_session_mode = session_mode
	_super_gem_drop = super_gem_drop
	_tick = tick
	_now_ms = now_ms
	_entry_tick = tick
	_entry_ms = now_ms
	_intro_until_ms = now_ms + int(_config.get("intro_ms", INTRO_MS))
	_stage = STAGE_INTRO
	_remaining = _f32(DURATION_INITIAL)
	_active_target = _f32(ACTIVE_TARGET_INITIAL)
	_active_count = 0
	_next_spawn_serial = 1
	_rng_source = rng_source
	_rng_draws_since_enter = 0
	_next_event_id = 1
	_completion_state.clear()
	_pool_reset_terminal.clear()
	_players = _normalize_players(players_value)
	_starting_scores = [0, 0]
	_score_deltas = [0, 0]
	_score_multipliers = [1, 1]
	for seat_id in range(2):
		var progression: Dictionary = (
			progressions_value[seat_id] as Dictionary
			if seat_id < progressions_value.size() and progressions_value[seat_id] is Dictionary
			else {}
		)
		_starting_scores[seat_id] = maxi(0, int(progression.get("score", 0)))
		_score_multipliers[seat_id] = maxi(1, int(progression.get("score_multiplier", 1)))

	# FUN_0059bb90 consumes its live-pool-dependent words before the ten slots.
	_pool_reset_entry = _invoke_pool_reset("entry")
	_slots.clear()
	for slot_id in range(SLOT_COUNT):
		_slots.append(_initialized_inactive_slot(slot_id))

	var events: Array[Dictionary] = [
		_make_event("gem_drop_entered", {
			"source_mode": _source_mode,
			"super_gem_drop": _super_gem_drop,
			"intro_until_ms": _intro_until_ms,
			"pool_reset": _pool_reset_entry.duplicate(true),
		}),
	]
	if restart_music:
		events.append(_make_event("music_cue", {"key": "gems", "action": "play"}))
	return _result(events, [])


func step(
	tick: int,
	now_ms: int,
	players_value: Array
) -> Dictionary:
	_last_error = ""
	if _stage == STAGE_IDLE:
		_set_error("Gem Drop has not been entered")
		return _error_result(tick, now_ms)
	if tick <= _tick:
		_set_error("step tick must increase monotonically")
		return _error_result(tick, now_ms)
	if now_ms < _now_ms:
		_set_error("step milliseconds must not move backwards")
		return _error_result(tick, now_ms)
	_tick = tick
	_now_ms = now_ms
	_players = _normalize_players(players_value)
	var events: Array[Dictionary] = []
	var rewards: Array[Dictionary] = []
	if _stage == STAGE_COMPLETE:
		return _result(events, rewards)

	# Unsigned JNB at the state-18 dispatcher makes equality the first active
	# update. Player movement is parent-owned and remains live during this gate.
	if now_ms < _intro_until_ms:
		_stage = STAGE_INTRO
		return _result(events, rewards)
	_stage = STAGE_ACTIVE
	var tick_scale := _f32(float(_config.get("tick_scale", 1.0)))
	_active_target = _f32(_active_target + _f32(ACTIVE_TARGET_GROWTH))
	if _active_count < int(floor(_active_target)) and _remaining > 0.0:
		_spawn_first_free(true)
	_update_slots(tick_scale)
	_remaining = _f32(_remaining - tick_scale)
	if _remaining < 0.0:
		_complete(events)
		return _result(events, rewards)
	_resolve_collisions(events, rewards)
	return _result(events, rewards)


func snapshot() -> Dictionary:
	return {
		"kind": "gem_drop",
		"owner_seat_id": _owner_seat_id,
		"source_mode": _source_mode,
		"session_mode": _session_mode,
		"super_gem_drop": _super_gem_drop,
		"title": "S U P E R   G E M   D R O P" if _super_gem_drop else "G E M   D R O P",
		"stage": _stage,
		"tick": _tick,
		"now_ms": _now_ms,
		"entry_tick": _entry_tick,
		"entry_ms": _entry_ms,
		"intro_until_ms": _intro_until_ms,
		"intro_remaining_ms": maxi(0, _intro_until_ms - _now_ms),
		"remaining_fp": _to_fp(_remaining),
		"remaining": _remaining,
		"active_target_fp": _to_fp(_active_target),
		"active_count": _active_count,
		"slot_count": SLOT_COUNT,
		"slots": _ordered_slots(),
		"players": _players.duplicate(true),
		"score_deltas_by_seat": _score_deltas.duplicate(),
		"completion": _completion_state.duplicate(true),
		"pool_reset_entry": _pool_reset_entry.duplicate(true),
		"pool_reset_terminal": _pool_reset_terminal.duplicate(true),
	}


func state_for_hash() -> Dictionary:
	var result := snapshot()
	result["starting_scores"] = _starting_scores.duplicate()
	result["score_multipliers"] = _score_multipliers.duplicate()
	result["next_event_id"] = _next_event_id
	result["next_spawn_serial"] = _next_spawn_serial
	result["rng_draws_since_enter"] = _rng_draws_since_enter
	result["rng"] = _rng_snapshot()
	return result


func is_complete() -> bool:
	return _stage == STAGE_COMPLETE


func get_last_error() -> String:
	return _last_error


func _initialized_inactive_slot(slot_id: int) -> Dictionary:
	var source_x := _rng_range(3) * GEM_WIDTH
	var frame_index := _rng_range(11)
	var animation_period := 3 + _rng_range(3)
	return {
		"slot_id": slot_id,
		"spawn_serial": 0,
		"active": false,
		"source_x": source_x,
		"frame_index": frame_index,
		"animation_period": animation_period,
		"animation_countdown": animation_period,
		"x": _f32(0.0),
		"y": _f32(0.0),
		"fall_speed": _f32(0.0),
	}


func _spawn_first_free(growth_spawn: bool) -> bool:
	for slot_id in range(SLOT_COUNT):
		if not bool(_slots[slot_id].active):
			_spawn_slot(slot_id, growth_spawn)
			return true
	return false


func _spawn_slot(slot_id: int, growth_spawn: bool) -> void:
	var slot: Dictionary = _slots[slot_id]
	slot.spawn_serial = _next_spawn_serial
	_next_spawn_serial += 1
	var color_roll := _rng_range(100)
	if color_roll <= 50:
		slot.source_x = 0
	elif color_roll <= 84:
		slot.source_x = 80
	else:
		slot.source_x = 160
	slot.frame_index = _rng_range(11)
	slot.animation_period = 1 + _rng_range(3)
	slot.animation_countdown = int(slot.animation_period)
	slot.y = _f32(-60.0)
	slot.fall_speed = _rng_float(7.0, 14.0) if growth_spawn else _rng_float(6.0, 10.0)
	slot.x = _rng_float(70.0, 650.0)
	slot.active = true
	_active_count += 1


func _update_slots(tick_scale: float) -> void:
	for slot_id in range(SLOT_COUNT):
		var slot: Dictionary = _slots[slot_id]
		if not bool(slot.active):
			continue
		slot.animation_countdown = int(slot.animation_countdown) - 1
		if int(slot.animation_countdown) < 0:
			slot.animation_countdown = int(slot.animation_period)
			slot.frame_index = int(slot.frame_index) + 1
			if int(slot.frame_index) > 10:
				slot.frame_index = 0
		slot.y = _f32(float(slot.y) + _f32(float(slot.fall_speed) * tick_scale))
		if float(slot.y) <= OFFSCREEN_BOTTOM:
			continue
		slot.active = false
		_active_count = maxi(0, _active_count - 1)
		if _active_count < int(floor(_active_target)) and _remaining > 0.0:
			_spawn_first_free(false)


func _resolve_collisions(
	events: Array[Dictionary],
	rewards: Array[Dictionary]
) -> void:
	var query: Variant = _config.get("collision_query", Callable())
	if not (query is Callable) or not (query as Callable).is_valid():
		return
	var seat_order: Array[int] = [_owner_seat_id]
	if _session_mode == "coop":
		# Co-op is remake-only. Keep the retail stream free of an ownership draw
		# and resolve contested slots deterministically from the triggering owner.
		seat_order = [_owner_seat_id, 1 - _owner_seat_id]
	for seat_id in seat_order:
		if seat_id < 0 or seat_id >= _players.size():
			continue
		var player: Dictionary = _players[seat_id]
		if not bool(player.get("active", false)) or not bool(player.get("alive", false)):
			continue
		var player_x := _trunc_fp_to_int(int(player.get("x_fp", 400 * FP_ONE)))
		if bool(player.get("drunk_active", false)) and _rng_range(128) >= 64:
			# Retail mirrors the 40-pixel top-left as width-40-x. Remake players
			# store their normalized center, so the equivalent center is width-x.
			player_x = int(_config.get("surface_width", 800)) - player_x
		var player_y := _trunc_fp_to_int(int(player.get("y_fp", 564 * FP_ONE)))
		var player_left := player_x - PLAYER_WIDTH / 2
		var player_top := player_y - 14
		for slot_id in range(SLOT_COUNT):
			var slot: Dictionary = _slots[slot_id]
			if not bool(slot.active):
				continue
			var slot_left := int(float(slot.x))
			var slot_top := int(float(slot.y))
			if not _strict_aabb_overlap(
				slot_left, slot_top, GEM_WIDTH, GEM_HEIGHT,
				player_left, player_top, PLAYER_WIDTH, PLAYER_COLLISION_HEIGHT
			):
				continue
			var frame_index := int(player.get("mask_frame", 5))
			var payload := {
				"slot_id": slot_id,
				"slot_kind": "gem_drop",
				"slot_mask_id": "diamantbig",
				"slot_source_rect": [
					int(slot.source_x), int(slot.frame_index) * GEM_HEIGHT,
					GEM_WIDTH, GEM_HEIGHT,
				],
				"slot_destination_rect": [slot_left, slot_top, GEM_WIDTH, GEM_HEIGHT],
				"fighter_mask_id": String(player.get("fighter_id", "fighter%d" % (seat_id + 1))),
				"fighter_frame_index": frame_index,
				"fighter_source_rect": [
					frame_index * PLAYER_WIDTH, 0, PLAYER_WIDTH, PLAYER_COLLISION_HEIGHT,
				],
				"fighter_destination_rect": [
					player_left, player_top, PLAYER_WIDTH, PLAYER_COLLISION_HEIGHT,
				],
			}
			if bool((query as Callable).call(payload)):
				_collect_slot(slot_id, seat_id, events, rewards)


func _collect_slot(
	slot_id: int,
	seat_id: int,
	events: Array[Dictionary],
	rewards: Array[Dictionary]
) -> void:
	var slot: Dictionary = _slots[slot_id]
	slot.active = false
	_active_count = maxi(0, _active_count - 1)
	var pan_index := clampi(int(float(slot.x)) + 40, 0, 799)
	var raw_pan := _f32(float(pan_index) * 255.0 / 800.0)
	# Audio precedes the score mutation in FUN_00600e90. The retail wrapper
	# passes this raw pan float unchanged to BASS; clients may adapt it.
	events.append(_make_event("sound_cue", {
		"key": "jingles",
		"frequency_hz": 30000 + _rng_range(15000),
		"volume_index": 255,
		"legacy_pan_attribute_raw": raw_pan,
		"legacy_pan_table_index": pan_index,
		"slot_id": slot_id,
		"seat_id": seat_id,
	}))
	events.append(_make_event("voice_cue", {
		"key": "bonus",
		"queue_tag": 0,
		"queue_padding_ms": 50,
		"drop_if_voice_busy": true,
		"seat_id": seat_id,
	}))
	var reward_index := clampi(int(slot.source_x) / GEM_WIDTH, 0, 2)
	var reward_table := SUPER_REWARDS if _super_gem_drop else NORMAL_REWARDS
	var base_score := int(reward_table[reward_index])
	var requested_score := base_score * int(_score_multipliers[seat_id])
	var score_origin := int(_starting_scores[seat_id])
	var score_delta := int(_score_deltas[seat_id])
	if _session_mode == "coop":
		# Both remake co-op seats write the shared progression.
		score_origin = int(_starting_scores[_owner_seat_id])
		score_delta = int(_score_deltas[0]) + int(_score_deltas[1])
	var available := maxi(0, MAX_SCORE - score_origin - score_delta)
	var applied_score := mini(requested_score, available)
	_score_deltas[seat_id] = int(_score_deltas[seat_id]) + applied_score
	var reward := {
		"seat_id": seat_id,
		"slot_id": slot_id,
		"reward_index": reward_index,
		"base_score": base_score,
		"score_multiplier": int(_score_multipliers[seat_id]),
		"requested_score": requested_score,
		"score": applied_score,
		"score_cap": MAX_SCORE,
		"super_gem_drop": _super_gem_drop,
	}
	rewards.append(reward)
	events.append(_make_event("gem_drop_collected", reward))


func _complete(events: Array[Dictionary]) -> void:
	_pool_reset_terminal = _invoke_pool_reset("terminal")
	_stage = STAGE_COMPLETE
	_super_gem_drop = false
	_completion_state = {
		"success": true,
		"outcome": "complete",
		"retail_transition_ms": 500,
		"next_main_state": 2,
		"originating_bonus_mode_resumed": false,
		"music_restored": false,
		"score_deltas_by_seat": _score_deltas.duplicate(),
		"pool_reset": _pool_reset_terminal.duplicate(true),
	}
	events.append(_make_event("gem_drop_completed", _completion_state))


func _invoke_pool_reset(reason: String) -> Dictionary:
	var callback: Variant = _config.get("pool_reset_callback", Callable())
	if not (callback is Callable) or not (callback as Callable).is_valid():
		return {"reason": reason, "rng_draws": 0}
	var result: Variant = (callback as Callable).call(reason, _owner_seat_id)
	if result is Dictionary:
		return (result as Dictionary).duplicate(true)
	return {"reason": reason, "rng_draws": 0}


func _normalize_players(players_value: Array) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for seat_id in range(2):
		var source: Dictionary = (
			players_value[seat_id] as Dictionary
			if seat_id < players_value.size() and players_value[seat_id] is Dictionary
			else {}
		)
		result.append({
			"seat_id": seat_id,
			"active": bool(source.get("active", seat_id == _owner_seat_id)),
			"alive": bool(source.get("alive", seat_id == _owner_seat_id)),
			"x_fp": int(source.get("x_fp", 400 * FP_ONE)),
			"y_fp": int(source.get("y_fp", 564 * FP_ONE)),
			"mask_frame": clampi(int(source.get("mask_frame", 5)), 0, 10),
			"fighter_id": String(source.get("fighter_id", "fighter%d" % (seat_id + 1))),
			"drunk_active": bool(source.get("drunk_active", false)),
		})
	return result


func _ordered_slots() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for slot_id in range(SLOT_COUNT):
		var slot: Dictionary = _slots[slot_id]
		result.append({
			"slot_id": slot_id,
			"spawn_serial": int(slot.get("spawn_serial", 0)),
			"active": bool(slot.active),
			"texture_id": "diamantbig",
			"collision_mask": "diamantbig",
			"source_x": int(slot.source_x),
			"frame_index": int(slot.frame_index),
			"source_rect": [
				int(slot.source_x), int(slot.frame_index) * GEM_HEIGHT,
				GEM_WIDTH, GEM_HEIGHT,
			],
			"x_fp": _to_fp(float(slot.x)),
			"y_fp": _to_fp(float(slot.y)),
			"fall_speed_fp": _to_fp(float(slot.fall_speed)),
			"animation_period": int(slot.animation_period),
			"animation_countdown": int(slot.animation_countdown),
		})
	return result


func _strict_aabb_overlap(
	a_x: int, a_y: int, a_width: int, a_height: int,
	b_x: int, b_y: int, b_width: int, b_height: int
) -> bool:
	return (
		a_x < b_x + b_width
		and a_x + a_width > b_x
		and a_y < b_y + b_height
		and a_y + a_height > b_y
	)


func _rng_range(upper_exclusive: int) -> int:
	_rng_draws_since_enter += 1
	return int(_rng_source.next_range(upper_exclusive))


func _rng_float(minimum: float, maximum: float) -> float:
	_rng_draws_since_enter += 1
	return _f32(float(_rng_source.next_float32(minimum, maximum)))


func _rng_snapshot() -> Dictionary:
	if _rng_source != null and _rng_source.has_method("snapshot"):
		return (_rng_source.snapshot() as Dictionary).duplicate(true)
	return {}


func _is_rng_source_valid(source: Variant) -> bool:
	return (
		source is Object
		and source.has_method("next_range")
		and source.has_method("next_float32")
		and source.has_method("snapshot")
	)


func _make_event(kind: String, payload: Dictionary) -> Dictionary:
	var event := {
		"event_id": _next_event_id,
		"tick": _tick,
		"now_ms": _now_ms,
		"kind": kind,
		"owner_seat_id": _owner_seat_id,
	}
	_next_event_id += 1
	for key in payload:
		event[key] = payload[key]
	return event


func _result(events: Array[Dictionary], rewards: Array[Dictionary]) -> Dictionary:
	return {
		"ok": true,
		"tick": _tick,
		"now_ms": _now_ms,
		"events": events.duplicate(true),
		"rewards": rewards.duplicate(true),
		"complete": _stage == STAGE_COMPLETE,
		"completion": _completion_state.duplicate(true) if _stage == STAGE_COMPLETE else {},
		"snapshot": snapshot(),
	}


func _error_result(tick: int, now_ms: int) -> Dictionary:
	return {
		"ok": false,
		"error": _last_error,
		"tick": tick,
		"now_ms": now_ms,
		"events": [],
		"rewards": [],
		"complete": _stage == STAGE_COMPLETE,
		"completion": {},
		"snapshot": snapshot(),
	}


func _set_error(message: String) -> bool:
	_last_error = message
	return false


func _trunc_fp_to_int(value_fp: int) -> int:
	if value_fp >= 0:
		return value_fp / FP_ONE
	return -((-value_fp) / FP_ONE)


static func _to_fp(value: float) -> int:
	return int(round(value * FP_ONE))


static func _f32(value: float) -> float:
	var storage := PackedFloat32Array([value])
	return float(storage[0])

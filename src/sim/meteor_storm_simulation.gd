class_name MeteorStormSimulation
extends RefCounted

# WarBlade 1.34 Meteor Storm controller. Every retail default below is pinned
# to the executable named by RETAIL_EXECUTABLE_SHA256; callers may inject only
# the collision query and presentation offsets without changing gameplay RNG.

const ACTION_LEFT: int = 1
const ACTION_RIGHT: int = 2
const ACTION_FIRE: int = 4
const ACTION_MASK_ALL: int = ACTION_LEFT | ACTION_RIGHT | ACTION_FIRE

const STAGE_IDLE: String = "idle"
const STAGE_INTRO: String = "intro"
const STAGE_ACTIVE: String = "active"
const STAGE_COMPLETE: String = "complete"

const OUTCOME_NONE: String = ""
const OUTCOME_SUCCESS: String = "success"
const OUTCOME_FAILURE: String = "failure"

const RETAIL_EXECUTABLE_SHA256: String = (
	"ddf1778c307af1087ff9dcb512786111e665d972298aeaac3f1b4b2996d079ef"
)
const FP_ONE: int = 65536
const SLOT_COUNT: int = 30
const INTRO_MS: int = 4000
const PLAYER_WIDTH: int = 40
const PLAYER_HEIGHT: int = 28
const PLAYER_COLLISION_HEIGHT: int = 27
const PLAYER_MIN_X: float = 84.0
const PLAYER_MAX_X: float = 716.0
const PLAYER_Y: float = 564.0
const SPEED_MAX: float = 15.0
const SPEED_ACCELERATION: float = 0.10000000149011612
const SPEED_DECELERATION: float = 0.18000000715255737
const BASE_SCROLL_INITIAL: float = 1.5
const BASE_SCROLL_GROWTH: float = 0.0012000000569969416
const PERFORMANCE_SPEED_THRESHOLD: float = 30.0 / 7.0
const ACTIVE_TARGET_INITIAL: float = 20.0
const METEOR_DISTANCE_INCREMENT: int = 134
const RETAIL_TRANSITION_MS: int = 3000
const GEM_DROP_TRANSITION_MS: int = 4000

const DIFFICULTY_DISTANCE: Dictionary = {
	"easy": 12090.0,
	"normal": 14000.0,
	"hard": 15540.0,
	"ace": 17000.0,
}
const DIFFICULTY_TARGET_GROWTH: Dictionary = {
	"easy": 0.00139999995008111,
	"normal": 0.00144999998155981,
	"hard": 0.00150000001303852,
	"ace": 0.00170000002253801,
}
const DIFFICULTY_SPECIAL_THRESHOLD: Dictionary = {
	"easy": 7,
	"normal": 6,
	"hard": 5,
	"ace": 4,
}

# u32[45] tables at 0x007d0c70..0x007d0f4b. RNG_int(0,45) is
# half-open, so the adjacent 46th values are deliberately excluded.
const METEOR_SOURCE_X: Array[int] = [
	0, 64, 64, 96, 96, 128, 160, 224, 256, 384,
	0, 160, 256, 160, 0, 128, 192, 288, 400, 480,
	0, 176, 272, 400, 432, 176, 240, 288, 352, 424,
	0, 148, 276, 424, 0, 128, 208, 256, 320, 384,
	384, 320, 224, 128, 0,
]
const METEOR_SOURCE_Y: Array[int] = [
	0, 0, 26, 0, 28, 0, 0, 0, 0, 0,
	52, 52, 72, 136, 193, 193, 187, 127, 195, 195,
	276, 277, 255, 291, 291, 349, 349, 344, 344, 333,
	410, 410, 409, 424, 515, 514, 514, 510, 510, 510,
	550, 588, 553, 576, 616,
]
const METEOR_WIDTH: Array[int] = [
	64, 32, 32, 32, 32, 32, 64, 32, 128, 160,
	160, 96, 96, 64, 128, 64, 96, 96, 80, 144,
	176, 96, 128, 32, 32, 64, 48, 64, 48, 96,
	148, 128, 148, 96, 128, 80, 48, 48, 64, 48,
	32, 144, 96, 32, 144,
]
const METEOR_HEIGHT: Array[int] = [
	53, 26, 21, 28, 25, 28, 36, 18, 72, 193,
	141, 85, 54, 49, 82, 42, 67, 117, 95, 136,
	132, 71, 88, 39, 31, 45, 59, 43, 46, 90,
	104, 90, 100, 73, 99, 63, 38, 24, 77, 36,
	16, 71, 113, 25, 99,
]

const BONUS_WEIGHTS: Array[int] = [50, 30, 10, 150, 80, 40]
const BONUS_SOURCE_X: Array[int] = [0, 64, 128, 192, 256, 320]
const BONUS_SCORE: Array[int] = [0, 0, 0, 1000, 5000, 10000]
const BONUS_CASH: Array[int] = [50, 100, 250, 0, 0, 0]
const METEOR_FLYBY_VOLUME_INDEX: Array[int] = [
	87, 21, 17, 23, 20, 23, 59, 14, 238, 255,
	255, 211, 134, 81, 255, 69, 166, 255, 196, 255,
	255, 176, 255, 32, 25, 74, 73, 71, 57, 223,
]
const GEM_SCORE: Array[int] = [2500, 5000, 10000]

var _configured: bool = false
var _last_error: String = ""
var _config: Dictionary = {}
var _rng_source: Variant = null
var _rng_draws_since_enter: int = 0

var _owner_seat_id: int = -1
var _stage: String = STAGE_IDLE
var _tick: int = 0
var _now_ms: int = 0
var _entry_tick: int = 0
var _entry_ms: int = 0
var _intro_until_ms: int = 0
var _previous_action_mask: int = 0

var _ship_x: float = 400.0
var _ship_y: float = PLAYER_Y
var _ship_phase_half_steps: int = 10
var _ship_frame_index: int = 0
var _fighter_id: String = "fighter1"
var _fighter_source_rect: Array[int] = [0, 0, PLAYER_WIDTH, PLAYER_COLLISION_HEIGHT]
var _player_move_speed: float = 4.0
var _speed: float = 0.0
var _base_scroll: float = BASE_SCROLL_INITIAL
var _distance: float = 0.0
var _distance_total: float = 0.0
var _active_target: float = ACTIVE_TARGET_INITIAL
var _counted_active_slots: int = 0
var _low_speed_updates: int = 0
var _high_speed_updates: int = 0
var _accelerator_released: bool = false

var _drunk_ticks_remaining: int = 0
var _secret_drunk_meteor: bool = false
var _starting_money: int = 0
var _maximum_money: int = 99990
var _starting_meteor_streak: int = 0
var _gem_progress: int = 452
var _gem_progress_origin: int = 452
var _gem_progress_step: int = 8
var _score_multiplier_numerator: int = 1
var _score_multiplier_denominator: int = 1
var _parent_state_hash: Variant = null

var _slots: Array[Dictionary] = []
var _next_spawn_serial: int = 1
var _next_event_id: int = 1
var _countdown_three_emitted: bool = false
var _countdown_two_emitted: bool = false
var _countdown_one_emitted: bool = false
var _pending_events: Array[Dictionary] = []

var _score_delta_total: int = 0
var _cash_delta_total: int = 0
var _gems_delta_total: int = 0
var _meteor_score_delta_total: int = 0
var _completion_state: Dictionary = {}


static func retail_contract() -> Dictionary:
	return {
		"executable_sha256": RETAIL_EXECUTABLE_SHA256,
		"surface_width": 800,
		"surface_height": 600,
		"surface_offset_x": 0,
		"surface_offset_y": 0,
		"intro_ms": INTRO_MS,
		"slot_count": SLOT_COUNT,
		"tick_scale": 1.0,
		"difficulty": "normal",
		"collision_query": Callable(),
		"gem_drop_start_callback": Callable(),
		"profile_delta_contract": {
			"score": "progression.score",
			"money": "progression.money",
			"gem_count": "progression.gem_count",
			"gem_progress": "progression.gem_progress",
			"meteor_score": "profile_stats.meteor_score",
			"meteor_distance": "progression.meteor_distance",
			"meteor_streak": "progression.meteor_streak",
		},
		"assets": {
			"meteor_texture": "meteors",
			"meteor_mask": "meteors",
			"bonus_texture": "meteorbonuses",
			"bonus_mask": "meteorbonuses",
			"gem_texture": "diamantbig",
			"gem_mask": "diamantbig",
			"meter_texture": "meteormeter2",
		},
		"meter": {
			"atlas_size": [64, 640],
			"column_source_rect": [0, 0, 64, 600],
			"left_distance_source_rect": [0, 619, 48, 18],
			"right_distance_source_rect": [0, 600, 48, 18],
			"distance_track_pixels": 455,
			"distance_y_offset": 67,
			"left_anchor_x": 32,
			"right_anchor_x": 768,
		},
		"evidence": {
			"executable_sha256": RETAIL_EXECUTABLE_SHA256,
			"entry": "0x005f8630",
			"spawn": "0x005f8000",
			"update": "0x005f9f60",
			"collision": "0x005fda70",
			"entity_renderer": "0x005fc9b0",
			"meter_renderer": "0x005d7903",
			"result": "0x005dcd80",
			"player_movement": "0x005eb550",
			"meteor_source_x": "u32[45]@0x007d0c70",
			"meteor_source_y": "u32[45]@0x007d0d28",
			"meteor_width": "u32[45]@0x007d0de0",
			"meteor_height": "u32[45]@0x007d0e98",
			"difficulty_target_growth": "f32[4]@0x008f2094",
			"difficulty_distance": "f32[4]@0x008f2098",
			"difficulty_special_threshold": "u32[4]@0x008f209c",
			"base_scroll_growth": "f64@0x00786748",
			"performance_tiers": "f64@0x007863d0,0x00786438",
			"meter_distance_divisor": "f64 455.0@0x00785fe0",
		},
	}


func configure(contract: Dictionary) -> bool:
	_last_error = ""
	var merged := retail_contract()
	merged.merge(contract, true)
	if String(merged.get("executable_sha256", "")) != RETAIL_EXECUTABLE_SHA256:
		return _set_error("Meteor Storm contract does not match the pinned executable")
	if int(merged.get("surface_width", 0)) != 800 or int(merged.get("surface_height", 0)) != 600:
		return _set_error("Meteor Storm retail coordinates require an 800x600 surface")
	if int(merged.get("slot_count", 0)) != SLOT_COUNT:
		return _set_error("Meteor Storm retail state requires exactly 30 slots")
	if float(merged.get("tick_scale", 0.0)) <= 0.0:
		return _set_error("tick_scale must be positive")
	var difficulty := String(merged.get("difficulty", "normal")).to_lower()
	if not DIFFICULTY_DISTANCE.has(difficulty):
		return _set_error("difficulty must be easy, normal, hard, or ace")
	var collision_query: Variant = merged.get("collision_query", Callable())
	if collision_query is Callable and (collision_query as Callable).is_valid():
		pass
	elif collision_query != null and not (collision_query is Callable):
		return _set_error("collision_query must be a Callable")
	var gem_drop_callback: Variant = merged.get("gem_drop_start_callback", Callable())
	if gem_drop_callback != null and not (gem_drop_callback is Callable):
		return _set_error("gem_drop_start_callback must be a Callable")
	merged["difficulty"] = difficulty
	_config = merged.duplicate(true)
	_configured = true
	return true


func enter(
	owner_seat_id: int,
	progression: Dictionary,
	rng_source: Variant,
	tick: int = 0,
	now_ms: int = 0
) -> Dictionary:
	_last_error = ""
	if not _configured:
		_set_error("Meteor Storm is not configured")
		return _error_result(tick, now_ms)
	if owner_seat_id < 0:
		_set_error("owner_seat_id must be non-negative")
		return _error_result(tick, now_ms)
	if tick < 0 or now_ms < 0:
		_set_error("entry tick and milliseconds must be non-negative")
		return _error_result(tick, now_ms)
	if not _is_rng_source_valid(rng_source):
		_set_error("rng_source must expose next_range(), next_float32(), and snapshot()")
		return _error_result(tick, now_ms)

	_owner_seat_id = owner_seat_id
	_tick = tick
	_now_ms = now_ms
	_entry_tick = tick
	_entry_ms = now_ms
	_intro_until_ms = now_ms + int(_config.get("intro_ms", INTRO_MS))
	_previous_action_mask = 0
	_stage = STAGE_INTRO
	_rng_source = rng_source
	_rng_draws_since_enter = 0

	_ship_x = _f32(float(progression.get("ship_x", 400.0)))
	_ship_y = _f32(float(progression.get("ship_y", PLAYER_Y)))
	var supplied_frame := clampi(int(progression.get("fighter_frame_index", 5)), 0, 10)
	_ship_phase_half_steps = clampi(int(progression.get(
		"fighter_phase_half_steps", supplied_frame * 2
	)), 0, 20)
	_ship_frame_index = mini(10, int(_ship_phase_half_steps / 2))
	_fighter_id = String(progression.get(
		"fighter_id", "fighter1" if owner_seat_id == 0 else "fighter2"
	))
	_fighter_source_rect = [
		_ship_frame_index * PLAYER_WIDTH, 0, PLAYER_WIDTH, PLAYER_COLLISION_HEIGHT,
	]
	_player_move_speed = _f32(float(progression.get("player_move_speed", 4.0)))
	_speed = _f32(0.0)
	_base_scroll = _f32(BASE_SCROLL_INITIAL)
	var difficulty := String(_config.get("difficulty", "normal"))
	_distance_total = _f32(float(DIFFICULTY_DISTANCE[difficulty]))
	_distance = _distance_total
	_active_target = _f32(ACTIVE_TARGET_INITIAL)
	_counted_active_slots = 0
	_low_speed_updates = 0
	_high_speed_updates = 0
	_accelerator_released = false

	_drunk_ticks_remaining = maxi(0, int(progression.get(
		"drunk_ticks", progression.get("drunk_remaining_ticks", 0)
	)))
	if bool(progression.get("drunk_active", false)) and _drunk_ticks_remaining == 0:
		_drunk_ticks_remaining = 1
	_secret_drunk_meteor = bool(progression.get("secret_drunk_meteor", false))
	_starting_money = maxi(0, int(progression.get("money", 0)))
	_maximum_money = maxi(_starting_money, int(progression.get("max_money", 99990)))
	_starting_meteor_streak = maxi(0, int(progression.get("meteor_streak", 0)))
	_gem_progress = maxi(0, int(progression.get("gem_progress", 452)))
	_gem_progress_origin = maxi(0, int(progression.get(
		"gem_progress_origin", 452
	)))
	_gem_progress_step = maxi(1, int(progression.get("gem_progress_step", 8)))
	_score_multiplier_numerator = maxi(1, int(progression.get(
		"score_multiplier_numerator", progression.get("score_multiplier", 1)
	)))
	_score_multiplier_denominator = maxi(1, int(progression.get(
		"score_multiplier_denominator", 1
	)))
	_parent_state_hash = progression.get("parent_state_hash", null)

	_slots.clear()
	for slot_id in range(SLOT_COUNT):
		_slots.append(_empty_slot(slot_id))
	_next_spawn_serial = 1
	_next_event_id = 1
	_countdown_three_emitted = false
	_countdown_two_emitted = false
	_countdown_one_emitted = false
	_score_delta_total = 0
	_cash_delta_total = 0
	_gems_delta_total = 0
	_meteor_score_delta_total = 0
	_completion_state = {}
	_pending_events = [
		_make_event("meteor_storm_entered", {
			"owner_seat_id": _owner_seat_id,
			"intro_until_ms": _intro_until_ms,
			"difficulty": difficulty,
		}),
		_make_event("music_cue", {"key": "meteor", "action": "play"}),
		_make_event("voice_cue", {
			"key": "meteorstorm",
			"rank_variant": 0,
			"queue_padding_ms": 50,
		}),
	]
	var entry_events: Array[Dictionary] = _pending_events
	_pending_events = []
	return _result(entry_events, {}, {})


func step(tick: int, now_ms: int, action_mask: int) -> Dictionary:
	_last_error = ""
	if _stage == STAGE_IDLE:
		_set_error("Meteor Storm has not been entered")
		return _error_result(tick, now_ms)
	if tick <= _tick:
		_set_error("step tick must increase monotonically")
		return _error_result(tick, now_ms)
	if now_ms < _now_ms:
		_set_error("step milliseconds must not move backwards")
		return _error_result(tick, now_ms)
	if action_mask < 0 or (action_mask & ~ACTION_MASK_ALL) != 0:
		_set_error("action_mask contains unsupported actions")
		return _error_result(tick, now_ms)

	var elapsed_ticks := tick - _tick
	_tick = tick
	_now_ms = now_ms
	_drunk_ticks_remaining = maxi(0, _drunk_ticks_remaining - elapsed_ticks)
	var events: Array[Dictionary] = _pending_events
	_pending_events = []
	var progression_deltas: Dictionary = {}
	var completion: Dictionary = {}

	if _stage == STAGE_COMPLETE:
		_previous_action_mask = action_mask
		return _result(events, progression_deltas, completion)

	var tick_scale := _f32(float(_config.get("tick_scale", 1.0)))
	_update_ship(action_mask, tick_scale)
	_update_intro_countdown(events)
	if _intro_until_ms >= now_ms:
		_ensure_target_slot()
		_previous_action_mask = action_mask
		return _result(events, progression_deltas, completion)

	_stage = STAGE_ACTIVE
	_update_accelerator(action_mask, tick_scale)
	_grow_active_target(tick_scale)
	_ensure_target_slot()
	_update_slots(tick_scale, events)
	_update_performance_and_distance(tick_scale, progression_deltas)
	if _distance <= 0.0:
		completion = _complete_success(events, progression_deltas)
	else:
		completion = _resolve_collisions(events, progression_deltas)

	_previous_action_mask = action_mask
	return _result(events, progression_deltas, completion)


func snapshot() -> Dictionary:
	var meter := _meter_snapshot()
	return {
		"kind": "meteor_storm",
		"owner_seat_id": _owner_seat_id,
		"stage": _stage,
		"tick": _tick,
		"now_ms": _now_ms,
		"entry_tick": _entry_tick,
		"entry_ms": _entry_ms,
		"intro_until_ms": _intro_until_ms,
		"intro_remaining_ms": maxi(0, _intro_until_ms - _now_ms),
		"surface_width": int(_config.get("surface_width", 800)),
		"surface_height": int(_config.get("surface_height", 600)),
		"surface_offset_x": int(_config.get("surface_offset_x", 0)),
		"surface_offset_y": int(_config.get("surface_offset_y", 0)),
		"ship": _ship_snapshot(),
		"speed_fp": _to_fp(_speed),
		"speed": _speed,
		"speed_max_fp": _to_fp(SPEED_MAX),
		"base_scroll_fp": _to_fp(_base_scroll),
		"base_scroll": _base_scroll,
		"distance_fp": _to_fp(_distance),
		"distance_total_fp": _to_fp(_distance_total),
		"distance_percent": _distance_percent(),
		"speed_percentage": _speed_percentage(),
		"performance_threshold_fp": _to_fp(PERFORMANCE_SPEED_THRESHOLD),
		"low_speed_updates": _low_speed_updates,
		"high_speed_updates": _high_speed_updates,
		"accelerator_released": _accelerator_released,
		"drunk_active": _drunk_ticks_remaining > 0,
		"drunk_ticks_remaining": _drunk_ticks_remaining,
		"secret_drunk_meteor": _secret_drunk_meteor,
		"slot_count": SLOT_COUNT,
		"active_target_fp": _to_fp(_active_target),
		"counted_active_slots": _counted_active_slots,
		"slots": _ordered_slots(),
		"meter": meter,
		"score_delta_total": _score_delta_total,
		"cash_delta_total": _cash_delta_total,
		"gem_count_delta_total": _gems_delta_total,
		"gem_progress": _gem_progress,
		"gem_progress_origin": _gem_progress_origin,
		"gem_progress_step": _gem_progress_step,
		"meteor_score_delta_total": _meteor_score_delta_total,
		"completion": _completion_state.duplicate(true),
		"parent_state_hash": _parent_state_hash,
	}


func state_for_hash() -> Dictionary:
	return {
		"kind": "meteor_storm",
		"owner_seat_id": _owner_seat_id,
		"stage": _stage,
		"tick": _tick,
		"now_ms": _now_ms,
		"entry_tick": _entry_tick,
		"entry_ms": _entry_ms,
		"intro_until_ms": _intro_until_ms,
		"previous_action_mask": _previous_action_mask,
		"ship": _ship_snapshot(),
		"ship_phase_half_steps": _ship_phase_half_steps,
		"speed_fp": _to_fp(_speed),
		"base_scroll_fp": _to_fp(_base_scroll),
		"distance_fp": _to_fp(_distance),
		"distance_total_fp": _to_fp(_distance_total),
		"active_target_fp": _to_fp(_active_target),
		"counted_active_slots": _counted_active_slots,
		"low_speed_updates": _low_speed_updates,
		"high_speed_updates": _high_speed_updates,
		"accelerator_released": _accelerator_released,
		"drunk_ticks_remaining": _drunk_ticks_remaining,
		"secret_drunk_meteor": _secret_drunk_meteor,
		"slots": _ordered_slots(),
		"next_spawn_serial": _next_spawn_serial,
		"next_event_id": _next_event_id,
		"countdown_three_emitted": _countdown_three_emitted,
		"countdown_two_emitted": _countdown_two_emitted,
		"countdown_one_emitted": _countdown_one_emitted,
		"score_delta_total": _score_delta_total,
		"cash_delta_total": _cash_delta_total,
		"gem_count_delta_total": _gems_delta_total,
		"gem_progress": _gem_progress,
		"gem_progress_origin": _gem_progress_origin,
		"gem_progress_step": _gem_progress_step,
		"meteor_score_delta_total": _meteor_score_delta_total,
		"starting_money": _starting_money,
		"maximum_money": _maximum_money,
		"starting_meteor_streak": _starting_meteor_streak,
		"score_multiplier_numerator": _score_multiplier_numerator,
		"score_multiplier_denominator": _score_multiplier_denominator,
		"rng_draws_since_enter": _rng_draws_since_enter,
		"rng": _rng_snapshot(),
		"completion": _completion_state.duplicate(true),
		"parent_state_hash": _parent_state_hash,
	}


func is_complete() -> bool:
	return _stage == STAGE_COMPLETE


func get_last_error() -> String:
	return _last_error


func _update_ship(action_mask: int, tick_scale: float) -> void:
	var raw_direction := 0
	if (action_mask & ACTION_LEFT) != 0:
		raw_direction = -1
		_ship_phase_half_steps = maxi(0, _ship_phase_half_steps - 1)
	elif (action_mask & ACTION_RIGHT) != 0:
		raw_direction = 1
		_ship_phase_half_steps += 1
		if _ship_phase_half_steps >= 22:
			_ship_phase_half_steps = 20
	else:
		if _ship_phase_half_steps < 10:
			_ship_phase_half_steps += 1
		elif _ship_phase_half_steps > 10:
			_ship_phase_half_steps -= 1
	_ship_frame_index = mini(10, int(_ship_phase_half_steps / 2))
	var direction := raw_direction
	if _drunk_ticks_remaining > 0 and not _secret_drunk_meteor:
		direction = -direction
	var capped_speed := minf(14.0, _player_move_speed)
	_ship_x = _f32(clampf(
		_ship_x + _f32(_f32(float(direction) * capped_speed) * tick_scale),
		PLAYER_MIN_X,
		PLAYER_MAX_X
	))
	_fighter_source_rect = [
		_ship_frame_index * PLAYER_WIDTH, 0, PLAYER_WIDTH, PLAYER_COLLISION_HEIGHT,
	]


func _update_intro_countdown(events: Array[Dictionary]) -> void:
	var remaining := _intro_until_ms - _now_ms
	if remaining < 2000 and not _countdown_three_emitted:
		_countdown_three_emitted = true
		events.append(_make_event("countdown_cue", {"value": 3, "remaining_ms": remaining}))
	if remaining < 1000 and not _countdown_two_emitted:
		_countdown_two_emitted = true
		events.append(_make_event("countdown_cue", {"value": 2, "remaining_ms": remaining}))
	if remaining < 10 and not _countdown_one_emitted:
		_countdown_one_emitted = true
		events.append(_make_event("countdown_cue", {"value": 1, "remaining_ms": remaining}))


func _update_accelerator(action_mask: int, tick_scale: float) -> void:
	if (action_mask & ACTION_FIRE) != 0:
		if _speed < SPEED_MAX:
			_speed = _f32(_speed + _f32(SPEED_ACCELERATION * tick_scale))
	else:
		_accelerator_released = true
		_speed = _f32(_speed - _f32(SPEED_DECELERATION * tick_scale))
		if _speed < 0.0:
			_speed = _f32(0.0)


func _grow_active_target(tick_scale: float) -> void:
	var growth := _f32(float(DIFFICULTY_TARGET_GROWTH[String(_config.difficulty)]))
	var speed_term := _f32(_f32(_speed / 30.0) * tick_scale)
	var increment := _f32(_f32(speed_term + 1.0) * growth)
	_active_target = _f32(_active_target + _f32(increment * tick_scale))


func _ensure_target_slot() -> void:
	if _distance <= 0.0 or _counted_active_slots >= int(_active_target):
		return
	var free_slot := _first_free_slot()
	if free_slot < 0:
		return
	_spawn_slot(free_slot)
	# The top-level fill increments this counter for every kind. Retail's
	# meteor-offscreen replacement below has a distinct meteor-only increment.
	_counted_active_slots += 1


func _update_slots(tick_scale: float, events: Array[Dictionary]) -> void:
	for slot_id in range(SLOT_COUNT):
		var slot: Dictionary = _slots[slot_id]
		if not bool(slot.active):
			continue
		var old_y := float(slot.y)
		slot.x = _f32(float(slot.x) + _f32(float(slot.velocity_x) * tick_scale))
		var vertical_velocity := _f32(float(slot.velocity_y) + _base_scroll + _speed)
		slot.y = _f32(float(slot.y) + _f32(vertical_velocity * tick_scale))
		if String(slot.kind) == "meteor" and old_y <= -40.0 and float(slot.y) >= -40.0:
			events.append(_make_event("meteor_flyby", {
				"slot_id": slot_id,
				"spawn_serial": int(slot.spawn_serial),
				"x_fp": _to_fp(float(slot.x)),
			}))
			events.append(_make_event("sound_cue", {
				"key": "meteorpass",
				"frequency_hz": 15000,
				"source_hz": 32000,
				"volume_index": int(slot.flyby_volume_index),
				"slot_id": slot_id,
				"spawn_serial": int(slot.spawn_serial),
				"x_fp": _to_fp(float(slot.x)),
			}))
		if String(slot.kind) != "meteor":
			_update_slot_animation(slot, tick_scale)
		if float(slot.y) <= float(_config.get("surface_height", 600)):
			continue
		var old_kind := String(slot.kind)
		_deactivate_slot(slot_id)
		if old_kind != "meteor":
			continue
		_counted_active_slots = maxi(0, _counted_active_slots - 1)
		if _counted_active_slots >= int(_active_target):
			continue
		var replacement := _first_free_slot()
		if replacement >= 0:
			_spawn_slot(replacement)
			if String(_slots[replacement].kind) == "meteor":
				_counted_active_slots += 1


func _update_slot_animation(slot: Dictionary, tick_scale: float) -> void:
	slot.animation_ticks = _f32(float(slot.animation_ticks) - tick_scale)
	if float(slot.animation_ticks) >= 0.0:
		return
	slot.animation_ticks = _f32(5.0)
	var source_rect: Array = slot.source_rect
	var frame_height := int(source_rect[3])
	var next_y := int(source_rect[1]) + frame_height
	var atlas_height := 370 if String(slot.kind) == "bonus" else 561
	if next_y == atlas_height:
		next_y = 0
	source_rect[1] = next_y
	slot.source_rect = source_rect


func _update_performance_and_distance(
	tick_scale: float,
	progression_deltas: Dictionary
) -> void:
	_base_scroll = _f32(_base_scroll + _f32(BASE_SCROLL_GROWTH * tick_scale))
	if _speed < PERFORMANCE_SPEED_THRESHOLD:
		_low_speed_updates += 1
	else:
		_high_speed_updates += 1
	var speed_factor := int(_f32(_f32(_speed / SPEED_MAX) * 50.0)) + 1
	_award_score(speed_factor * 10, progression_deltas, true)
	var distance_step := _f32(_f32(_speed / 2.0) + 3.0)
	_distance = _f32(_distance - _f32(distance_step * tick_scale))


func _resolve_collisions(
	events: Array[Dictionary],
	progression_deltas: Dictionary
) -> Dictionary:
	var query: Variant = _config.get("collision_query", Callable())
	if not (query is Callable) or not (query as Callable).is_valid():
		return {}
	var player_left := int(_ship_x - 20.0)
	var player_top := int(_ship_y - 14.0)
	for slot_id in range(SLOT_COUNT):
		var slot: Dictionary = _slots[slot_id]
		if not bool(slot.active):
			continue
		var source_rect: Array = slot.source_rect
		var slot_left := int(float(slot.x))
		var slot_top := int(float(slot.y))
		var slot_width := int(source_rect[2])
		var slot_height := int(source_rect[3])
		if not _strict_aabb_overlap(
			slot_left, slot_top, slot_width, slot_height,
			player_left, player_top, PLAYER_WIDTH, PLAYER_COLLISION_HEIGHT
		):
			continue
		var payload := {
			"slot_id": slot_id,
			"spawn_serial": int(slot.spawn_serial),
			"slot_kind": String(slot.kind),
			"slot_mask_id": String(slot.collision_mask),
			"slot_source_rect": source_rect.duplicate(),
			"slot_destination_rect": [slot_left, slot_top, slot_width, slot_height],
			"fighter_mask_id": _fighter_id,
			"fighter_frame_index": _ship_frame_index,
			"fighter_source_rect": _fighter_source_rect.duplicate(),
			"fighter_destination_rect": [
				player_left, player_top, PLAYER_WIDTH, PLAYER_COLLISION_HEIGHT,
			],
		}
		if not bool((query as Callable).call(payload)):
			continue
		match String(slot.kind):
			"meteor":
				if _secret_drunk_meteor:
					var evade_roll := _rng_range(1000)
					if evade_roll < 992:
						events.append(_make_event("meteor_secret_evade", {
							"slot_id": slot_id,
							"roll": evade_roll,
						}))
						return {}
				return _complete_failure(events, progression_deltas, slot_id)
			"bonus":
				_collect_bonus(slot_id, events, progression_deltas)
			"gem":
				_collect_gem(slot_id, events, progression_deltas)
	return {}


func _collect_bonus(
	slot_id: int,
	events: Array[Dictionary],
	progression_deltas: Dictionary
) -> void:
	var slot: Dictionary = _slots[slot_id]
	var reward_index := int(slot.frame_index)
	var score := int(BONUS_SCORE[reward_index])
	var cash := int(BONUS_CASH[reward_index])
	if score > 0:
		_award_score(score, progression_deltas, true)
	if cash > 0:
		cash = _award_cash(cash, progression_deltas)
	_deactivate_slot(slot_id)
	events.append(_make_event("meteor_bonus_collected", {
		"slot_id": slot_id,
		"reward_index": reward_index,
		"score": _multiply_score(score),
		"cash": cash,
	}))
	events.append(_make_event("sound_cue", {
		"key": "bing",
		"slot_id": slot_id,
	}))


func _collect_gem(
	slot_id: int,
	events: Array[Dictionary],
	progression_deltas: Dictionary
) -> void:
	var slot: Dictionary = _slots[slot_id]
	var frame_index := int(slot.frame_index)
	var score := _multiply_score(int(GEM_SCORE[frame_index]))
	_score_delta_total += score
	_meteor_score_delta_total += score
	_gems_delta_total += 5
	_add_delta(progression_deltas, "score", score)
	_add_delta(progression_deltas, "meteor_score", score)
	_add_delta(progression_deltas, "gem_count", 5)
	var previous_gem_progress := _gem_progress
	var gem_drop_triggered := false
	for _gem_award in range(5):
		_gem_progress += _gem_progress_step
		var quotient := int(
			(_gem_progress - _gem_progress_origin) / _gem_progress_step
		)
		if posmod(quotient, 100) == 0:
			gem_drop_triggered = true
	var super_gem_drop := false
	if gem_drop_triggered:
		var final_quotient := int(
			(_gem_progress - _gem_progress_origin) / _gem_progress_step
		)
		if final_quotient >= 1000:
			super_gem_drop = true
			_gem_progress -= _gem_progress_step * 1000
	_add_delta(
		progression_deltas,
		"gem_progress",
		_gem_progress - previous_gem_progress
	)
	if gem_drop_triggered:
		events.append(_make_event("voice_cue", {
			"key": "gemdrop",
			"queue_padding_ms": 50,
			"drop_if_voice_busy": true,
		}))
		events.append(_make_event("meteor_gem_drop_started", {
			"transition_ms": GEM_DROP_TRANSITION_MS,
			"super_gem_drop": super_gem_drop,
			"gem_progress": _gem_progress,
		}))
		# The executable initializes state 18 at this exact point. That initializer
		# consumes the live-pool reset RNG and all ten Gem Drop slot triples before
		# this Meteor loop deactivates the current gem, draws its bell pitch, or
		# scans later slots. A parent callback is therefore part of simulation RNG,
		# not a deferred presentation transition.
		var callback: Variant = _config.get("gem_drop_start_callback", Callable())
		if callback is Callable and (callback as Callable).is_valid():
			var entered_value: Variant = (callback as Callable).call({
				"owner_seat_id": _owner_seat_id,
				"source_mode": "meteor_storm",
				"super_gem_drop": super_gem_drop,
				"gem_progress": _gem_progress,
				"ship": _ship_snapshot(),
				"progression_deltas": progression_deltas.duplicate(true),
			})
			if entered_value is Dictionary:
				for callback_event_value in (entered_value as Dictionary).get("events", []):
					if callback_event_value is Dictionary:
						events.append((callback_event_value as Dictionary).duplicate(true))
	_deactivate_slot(slot_id)
	events.append(_make_event("meteor_gem_collected", {
		"slot_id": slot_id,
		"frame_index": frame_index,
		"score": score,
		"gem_count": 5,
		"gem_progress": _gem_progress,
		"gem_drop_triggered": gem_drop_triggered,
		"super_gem_drop": super_gem_drop,
	}))
	events.append(_make_event("voice_cue", {
		"key": "bonus",
		"queue_padding_ms": 50,
		"drop_if_voice_busy": true,
	}))
	events.append(_make_event("sound_cue", {
		"key": "bell1",
		"frequency_hz": 22000 + _rng_range(10000),
		"source_hz": 32000,
		"volume_index": 255,
		"slot_id": slot_id,
	}))


func _complete_success(
	events: Array[Dictionary],
	progression_deltas: Dictionary
) -> Dictionary:
	var percentage := _speed_percentage()
	var tier := "below_90"
	var reward_score := 1000000
	var reward_cash := 0
	if percentage >= 99.0:
		tier = "at_least_99"
		reward_score = 5000000
		reward_cash = 5000
	elif percentage >= 90.0:
		tier = "at_least_90"
		reward_score = 2000000
		reward_cash = 1000
	if int(percentage) == 100 and not _accelerator_released:
		tier = "perfect"
		reward_score = 10000000
		reward_cash = 25000
	if _drunk_ticks_remaining > 0:
		match tier:
			"below_90":
				reward_score = 2000000
				reward_cash = 0
			"at_least_90":
				reward_score = 5000000
				reward_cash = 5000
			"at_least_99":
				reward_score = 10000000
				reward_cash = 10000
			"perfect":
				reward_score = 20000000
				reward_cash = 50000
	var applied_score := _award_score(reward_score, progression_deltas, true)
	var applied_cash := _award_cash(reward_cash, progression_deltas)
	_add_delta(progression_deltas, "meteor_distance", METEOR_DISTANCE_INCREMENT)
	var new_streak := 0
	if percentage >= 99.0:
		new_streak = _starting_meteor_streak + 1
	_add_delta(progression_deltas, "meteor_streak", new_streak - _starting_meteor_streak)
	_stage = STAGE_COMPLETE
	_completion_state = {
		"success": true,
		"outcome": OUTCOME_SUCCESS,
		"tier": tier,
		"speed_percentage": percentage,
		"drunk_reward": _drunk_ticks_remaining > 0,
		"score_reward": applied_score,
		"cash_reward": applied_cash,
		"score_delta_total": _score_delta_total,
		"cash_delta_total": _cash_delta_total,
		"gem_count_delta_total": _gems_delta_total,
		"meteor_score_delta_total": _meteor_score_delta_total,
		"meteor_distance_increment": METEOR_DISTANCE_INCREMENT,
		"meteor_streak": new_streak,
		"retail_transition_ms": RETAIL_TRANSITION_MS,
	}
	events.append(_make_event("meteor_storm_completed", _completion_state))
	return _completion_state.duplicate(true)


func _complete_failure(
	events: Array[Dictionary],
	progression_deltas: Dictionary,
	slot_id: int
) -> Dictionary:
	_distance = _f32(1.0)
	_add_delta(progression_deltas, "meteor_streak", -_starting_meteor_streak)
	_stage = STAGE_COMPLETE
	_completion_state = {
		"success": false,
		"outcome": OUTCOME_FAILURE,
		"tier": "collision",
		"collision_slot_id": slot_id,
		"score_delta_total": _score_delta_total,
		"cash_delta_total": _cash_delta_total,
		"gem_count_delta_total": _gems_delta_total,
		"meteor_score_delta_total": _meteor_score_delta_total,
		"meteor_streak": 0,
		"retail_transition_ms": RETAIL_TRANSITION_MS,
	}
	events.append(_make_event("sound_cue", {
		"key": "thumpbig",
		"frequency_hz": 30000,
		"source_hz": 32000,
		"volume_linear": 1.0,
	}))
	events.append(_make_event("meteor_storm_failed", _completion_state))
	return _completion_state.duplicate(true)


func _spawn_slot(slot_id: int) -> void:
	var special_roll := _rng_range(99)
	var kind := "meteor"
	var frame_index := 0
	var source_rect: Array[int] = []
	var mask_id := "meteors"
	var texture_id := "meteors"
	if special_roll < int(DIFFICULTY_SPECIAL_THRESHOLD[String(_config.difficulty)]):
		var type_roll := _rng_range(99)
		if type_roll < 50:
			kind = "gem"
			frame_index = _rng_range(3)
			source_rect = [frame_index * 80, 0, 80, 51]
			mask_id = "diamantbig"
			texture_id = "diamantbig"
		else:
			kind = "bonus"
			frame_index = _select_bonus_index(_rng_range(359))
			source_rect = [BONUS_SOURCE_X[frame_index], 0, 64, 37]
			mask_id = "meteorbonuses"
			texture_id = "meteorbonuses"
	else:
		frame_index = _rng_range(45)
		source_rect = [
			METEOR_SOURCE_X[frame_index],
			METEOR_SOURCE_Y[frame_index],
			METEOR_WIDTH[frame_index],
			METEOR_HEIGHT[frame_index],
		]
	var slot: Dictionary = _slots[slot_id]
	slot.active = true
	slot.kind = kind
	slot.frame_index = frame_index
	slot.source_rect = source_rect
	slot.x = _rng_float(-30.0, 800.0)
	slot.y = _rng_float(-700.0, -200.0)
	slot.velocity_x = _rng_float(-0.30000001192092896, 0.30000001192092896)
	slot.velocity_y = _rng_float(1.0, 4.0)
	slot.animation_ticks = _f32(5.0)
	slot.collision_mask = mask_id
	slot.texture_id = texture_id
	slot.flyby_volume_index = METEOR_FLYBY_VOLUME_INDEX[slot_id]
	slot.spawn_serial = _next_spawn_serial
	_next_spawn_serial += 1


func _select_bonus_index(draw: int) -> int:
	var index := 0
	var remainder := draw
	while index < BONUS_WEIGHTS.size() - 1 and int(BONUS_WEIGHTS[index]) < remainder:
		remainder -= int(BONUS_WEIGHTS[index])
		index += 1
	return index


func _empty_slot(slot_id: int) -> Dictionary:
	return {
		"slot_id": slot_id,
		"active": false,
		"kind": "",
		"frame_index": -1,
		"source_rect": [0, 0, 0, 0],
		"x": _f32(0.0),
		"y": _f32(0.0),
		"velocity_x": _f32(0.0),
		"velocity_y": _f32(0.0),
		"animation_ticks": _f32(0.0),
		"collision_mask": "",
		"texture_id": "",
		"flyby_volume_index": METEOR_FLYBY_VOLUME_INDEX[slot_id],
		"spawn_serial": 0,
	}


func _deactivate_slot(slot_id: int) -> void:
	_slots[slot_id].active = false


func _first_free_slot() -> int:
	for slot_id in range(SLOT_COUNT):
		if not bool(_slots[slot_id].active):
			return slot_id
	return -1


func _ordered_slots() -> Array[Dictionary]:
	var ordered: Array[Dictionary] = []
	for slot_id in range(SLOT_COUNT):
		var slot: Dictionary = _slots[slot_id]
		ordered.append({
			"slot_id": slot_id,
			"active": bool(slot.active),
			"kind": String(slot.kind),
			"frame_index": int(slot.frame_index),
			"source_rect": (slot.source_rect as Array).duplicate(),
			"x_fp": _to_fp(float(slot.x)),
			"y_fp": _to_fp(float(slot.y)),
			"velocity_x_fp": _to_fp(float(slot.velocity_x)),
			"velocity_y_fp": _to_fp(float(slot.velocity_y)),
			"animation_ticks_fp": _to_fp(float(slot.animation_ticks)),
			"collision_mask": String(slot.collision_mask),
			"texture_id": String(slot.texture_id),
			"flyby_volume_index": int(slot.flyby_volume_index),
			"spawn_serial": int(slot.spawn_serial),
		})
	return ordered


func _ship_snapshot() -> Dictionary:
	return {
		"x_fp": _to_fp(_ship_x),
		"y_fp": _to_fp(_ship_y),
		"width": PLAYER_WIDTH,
		"height": PLAYER_HEIGHT,
		"collision_height": PLAYER_COLLISION_HEIGHT,
		"phase_half_steps": _ship_phase_half_steps,
		"frame_index": _ship_frame_index,
		"fighter_id": _fighter_id,
		"render_source_rect": [
			_ship_frame_index * PLAYER_WIDTH,
			0,
			PLAYER_WIDTH,
			PLAYER_HEIGHT,
		],
		"source_rect": _fighter_source_rect.duplicate(),
	}


func _meter_snapshot() -> Dictionary:
	var meter_config: Dictionary = _config.get("meter", {})
	var right_side := _ship_x >= 400.0
	var anchor_x := int(meter_config.get(
		"right_anchor_x" if right_side else "left_anchor_x",
		768 if right_side else 32
	))
	var scale_per_unit := maxf(1.0, _distance_total / 455.0)
	var distance_y := int(_distance / scale_per_unit) + int(
		meter_config.get("distance_y_offset", 67)
	)
	var surface_offset_x := int(_config.get("surface_offset_x", 0))
	var surface_offset_y := int(_config.get("surface_offset_y", 0))
	return {
		"texture_id": "meteormeter2",
		"side": "right" if right_side else "left",
		"atlas_size": (meter_config.get("atlas_size", [64, 640]) as Array).duplicate(),
		"column_source_rect": (
			meter_config.get("column_source_rect", [0, 0, 64, 600]) as Array
		).duplicate(),
		"column_destination": [
			anchor_x - 32 + surface_offset_x,
			surface_offset_y,
			64,
			600,
		],
		"distance_source_rect": (
			meter_config.get(
				"right_distance_source_rect" if right_side else "left_distance_source_rect",
				[0, 600, 48, 18] if right_side else [0, 619, 48, 18]
			) as Array
		).duplicate(),
		"distance_destination": [
			anchor_x - 32 + surface_offset_x,
			distance_y + surface_offset_y,
			48,
			18,
		],
		"distance_track_pixels": 455,
		"distance_scale_fp": _to_fp(scale_per_unit),
		"speed_threshold_fp": _to_fp(PERFORMANCE_SPEED_THRESHOLD),
		"speed_max_fp": _to_fp(SPEED_MAX),
	}


func _distance_percent() -> float:
	if _distance_total <= 0.0:
		return 0.0
	return clampf((1.0 - float(_distance) / float(_distance_total)) * 100.0, 0.0, 100.0)


func _speed_percentage() -> float:
	if _low_speed_updates >= _high_speed_updates or _high_speed_updates <= 0:
		return 0.0
	return (1.0 - float(_low_speed_updates) / float(_high_speed_updates)) * 100.0


func _award_score(
	base_amount: int,
	progression_deltas: Dictionary,
	meteor_score: bool
) -> int:
	var amount := _multiply_score(base_amount)
	_score_delta_total += amount
	_add_delta(progression_deltas, "score", amount)
	if meteor_score:
		_meteor_score_delta_total += amount
		_add_delta(progression_deltas, "meteor_score", amount)
	return amount


func _multiply_score(base_amount: int) -> int:
	return int(base_amount * _score_multiplier_numerator / _score_multiplier_denominator)


func _award_cash(base_amount: int, progression_deltas: Dictionary) -> int:
	var available := maxi(0, _maximum_money - (_starting_money + _cash_delta_total))
	var amount := mini(maxi(0, base_amount), available)
	_cash_delta_total += amount
	_add_delta(progression_deltas, "money", amount)
	return amount


func _add_delta(deltas: Dictionary, key: String, amount: int) -> void:
	if amount == 0:
		return
	deltas[key] = int(deltas.get(key, 0)) + amount


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


func _result(
	events: Array[Dictionary],
	progression_deltas: Dictionary,
	completion: Dictionary
) -> Dictionary:
	return {
		"ok": true,
		"tick": _tick,
		"now_ms": _now_ms,
		"score_delta": int(progression_deltas.get("score", 0)),
		"cash_delta": int(progression_deltas.get("money", 0)),
		"profile_deltas": progression_deltas.duplicate(true),
		"events": events.duplicate(true),
		"complete": _stage == STAGE_COMPLETE,
		"outcome": String(_completion_state.get("outcome", OUTCOME_NONE)),
		"completion": completion.duplicate(true),
		"snapshot": snapshot(),
	}


func _error_result(tick: int, now_ms: int) -> Dictionary:
	return {
		"ok": false,
		"error": _last_error,
		"tick": tick,
		"now_ms": now_ms,
		"score_delta": 0,
		"cash_delta": 0,
		"profile_deltas": {},
		"events": [],
		"complete": _stage == STAGE_COMPLETE,
		"outcome": String(_completion_state.get("outcome", OUTCOME_NONE)),
		"completion": {},
		"snapshot": snapshot(),
	}


func _set_error(message: String) -> bool:
	_last_error = message
	return false


static func _to_fp(value: float) -> int:
	return int(round(value * FP_ONE))


static func _f32(value: float) -> float:
	var storage := PackedFloat32Array([value])
	return float(storage[0])

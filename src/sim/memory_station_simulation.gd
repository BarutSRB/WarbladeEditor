class_name MemoryStationSimulation
extends RefCounted

# WarBlade 1.34 Memory Station controller. The entry/grid routine is at
# 0x005f7ab0, the update routine is at 0x005e16c0, and completion is at
# 0x005ac450 in the pinned retail executable.

const ACTION_LEFT: int = 1
const ACTION_RIGHT: int = 2
const ACTION_FIRE: int = 4
const ACTION_UP: int = 64
const ACTION_DOWN: int = 128
const ACTION_SECONDARY: int = 256
const ACTION_MASK_ALL: int = 511

const BONUS_ACTION_SELECT_TILE: int = 1
const BONUS_ACTION_KILL_TIME: int = 2

const STAGE_IDLE: String = "idle"
const STAGE_ACTIVE: String = "active"
const STAGE_SUCCESS_HOLD: String = "success_hold"
const STAGE_COMPLETE: String = "complete"

const TILE_SIZE: int = 64
const MAX_GRID_DIMENSION: int = 8
const RETAIL_PLACEMENT_ITERATIONS: int = 2000
const RETAIL_SUCCESS_HOLD_MS: int = 3000
const RETAIL_SKIP_GATE_MS: int = 25

const RETAIL_TILE_TYPES: Array[int] = [
	1, 2, 3, 4, 5, 6, 7, 8, 9, 10,
	11, 12, 13, 14, 15, 16, 17, 18, 19,
	23, 24, 25, 26, 27, 28, 29, 30, 31,
	32, 33, 34, 35, 36, 37, 38,
]
const RETAIL_TILE_WEIGHTS: Array[int] = [
	50, 200, 200, 200, 100, 50, 20, 150, 100, 50,
	150, 50, 80, 80, 80, 80, 80, 80, 200, 200,
	120, 120, 120, 120, 120, 120, 120, 100, 100,
	100, 100, 100, 200, 50, 15,
]

var _configured: bool = false
var _last_error: String = ""
var _config: Dictionary = {}
var _rng_source: Variant = null
var _rng_draws_since_enter: int = 0

var _owner_seat_id: int = -1
var _stage: String = STAGE_IDLE
var _tick: int = 0
var _now_ms: int = 0
var _entry_ms: int = 0
var _mode_deadline_ms: int = 0
var _reveal_deadline_ms: int = 0
var _success_deadline_ms: int = 0
var _skip_gate_ms: int = 0
var _countdown_gate: int = 11

var _columns: int = 4
var _rows: int = 4
var _grid_origin_x: int = 0
var _grid_origin_y: int = 0
var _cursor_col: int = 0
var _cursor_row: int = 0
var _cursor_animation_frame: int = 0
var _cursor_animation_deadline_ms: int = 0
var _tiles: Array[Dictionary] = []

var _pending_kind: String = ""
var _pending_tile_type: int = -1
var _previous_action_mask: int = 0
var _tries: int = 0
var _matches: int = 0
var _mismatches: int = 0

var _memory_success_streak: int = 0
var _progression_columns: int = 4
var _progression_rows: int = 4
var _memory_point_bonus: int = 0
var _memory_point_step: int = 0
var _score_multiplier: int = 1
var _bonus_time: int = 20
var _bonus_time_max: int = 45
var _money: int = 0
var _money_cap: int = 99990
var _lives: int = 3
var _lives_max: int = 5
var _lives_step: int = 1
var _armour_fp: int = 0
var _armour_max_fp: int = 131072
var _armour_step_fp: int = 65536
var _bullet_capacity: int = 5
var _bullet_capacity_max: int = 50
var _rank_markers: int = 0
var _letter_bits: int = 0
var _speed_fp: int = 262144
var _speed_step_fp: int = 45875
var _speed_cap_fp: int = 996144
var _gem_progress: int = 452
var _gem_progress_origin: int = 452
var _gem_progress_step: int = 8
var _memory_money_stars: int = 0
var _memory_star_floor: int = 20
var _memory_star_cycle: int = 3
var _stars_collected_this_board: int = 0
var _score_delta_total: int = 0
var _next_event_id: int = 1
var _completion_state: Dictionary = {}


static func retail_contract() -> Dictionary:
	return {
		"field_width": 800,
		"field_height": 600,
		"tile_size": TILE_SIZE,
		"max_grid_dimension": MAX_GRID_DIMENSION,
		"placement_iterations": RETAIL_PLACEMENT_ITERATIONS,
		"tile_types": RETAIL_TILE_TYPES.duplicate(),
		"tile_weights": RETAIL_TILE_WEIGHTS.duplicate(),
		"special_roll_min": 1,
		"special_roll_max_exclusive": 1000,
		"special_roll_threshold": 7,
		"special_tile_type": 1,
		"success_hold_ms": RETAIL_SUCCESS_HOLD_MS,
		"skip_gate_ms": RETAIL_SKIP_GATE_MS,
		"initial_columns": 4,
		"initial_rows": 4,
		"initial_success_streak": 0,
		"initial_point_bonus": 25000,
		"point_bonus_step": 25000,
		"effect_defaults": {
			"bonus_time_max": 45,
			"money_cap": 99990,
			"expanded_money_cap": 999990,
			"money_doubler_malfunction_threshold": 450000,
			"lives_max": 5,
			"lives_step": 1,
			"armour_max_fp": 131072,
			"armour_step_fp": 65536,
			"bullet_capacity_max": 50,
			"speed_base_fp": 262144,
			"speed_step_fp": 45875,
			"speed_cap_fp": 996144,
			# Fighter configuration zero at 0x007d1524. Other fighter
			# configurations must supply their session values on enter.
			"gem_progress_initial": 452,
			"gem_progress_step": 8,
			"memory_star_floor": 20,
			"memory_star_cycle": 3,
		},
		"tile_effects": _retail_tile_effects(),
		"atlas": {
			"asset_key": "memoryblocks",
			"source_member": "memoryblocks.tga",
			"source_sha256": "0222a6a6885ef96cf4aa9b534d8505d31d4f8e062c91cdff407dfdc8086dc2cf",
			"width": 256,
			"height": 640,
			"face_down_source_rect": {"x": 0, "y": 0, "width": 64, "height": 64},
			"cursor_frame_source_rects": [
				{"x": 0, "y": 320, "width": 64, "height": 64},
				{"x": 0, "y": 320, "width": 64, "height": 64},
				{"x": 64, "y": 320, "width": 64, "height": 64},
				{"x": 128, "y": 320, "width": 64, "height": 64},
				{"x": 64, "y": 320, "width": 64, "height": 64},
				{"x": 0, "y": 320, "width": 64, "height": 64},
			],
			"cursor_frame_period_ms": 50,
		},
		"evidence": {
			"executable_sha256": "ddf1778c307af1087ff9dcb512786111e665d972298aeaac3f1b4b2996d079ef",
			"entry_and_grid": "0x005f7ab0",
			"update_and_effect_dispatch": "0x005e16c0",
			"renderer": "0x005fcdc0",
			"completion": "0x005ac450",
			"integer_range_thunk": "0x005295dd->0x0052f6e0",
			"no_pair_thunk": "0x00525ce9->0x005e1220",
			"remaining_pairs": "0x005e1470",
			"surface_width": "u32@0x007d32f8",
			"surface_height": "u32@0x007d32fc",
			"tile_type_table": "u32[35]@0x007d0b10",
			"tile_weight_table": "u32[35]@0x007d0ba0",
			"tile_size": "shl 6@0x005f7af2,0x005f7bba,0x005f7bdd",
			"tile_atlas_rects": "0x005fce62-0x005fceeb",
			"cursor_atlas_and_animation": "0x005fd340-0x005fd4df",
			"grid_growth": "0x005ac4d1-0x005ac57a",
			"player_memory_initialization": "0x00623f60-0x00623fbe",
			"point_step_scalar_25000": "push 0x61a8@0x00775283; globals 0x00e11d88/0x00e11d8c",
			"point_step_and_award": "0x005ac580-0x005ac672",
			"point_bonus_display": "0x005dcb52-0x005dcb90",
			"success_hold_ms": "add 0x0bb8@0x005e7a20",
			"remaining_timing_and_input": "0x005e16c0",
			"effect_jump_table": "u32[38]@0x005e84b4; selector tile_type-1@0x005e23b2",
			"effect_cases": "0x005e23be-0x005e79d4",
			"effect_scalars": "0x00775283-0x007755cc",
			"memory_money_star_adaptation": "0x005e7829-0x005e79ad,0x005e7a34-0x005e7ac4",
		},
	}


static func _retail_tile_effects() -> Dictionary:
	return {
		0: {"effect_key": "no_effect", "case_address": "not_dispatched"},
		1: {"effect_key": "deadline_delta_applied", "case_address": "0x005e23be", "delta_ms": -15000},
		2: {"effect_key": "timed_score_multiplier", "case_address": "0x005e2400", "multiplier": 2},
		3: {"effect_key": "timed_score_multiplier", "case_address": "0x005e2476", "multiplier": 5},
		4: {"effect_key": "score_applied", "case_address": "0x005e24ec", "base_score": 100},
		5: {"effect_key": "score_applied", "case_address": "0x005e2687", "base_score": 1000},
		6: {"effect_key": "score_applied", "case_address": "0x005e2822", "base_score": 10000},
		7: {"effect_key": "money_doubler", "case_address": "0x005e29bd", "malfunction_threshold": 450000},
		8: {"effect_key": "money_or_score", "case_address": "0x005e2d7a", "amount": 50},
		9: {"effect_key": "money_or_score", "case_address": "0x005e30b4", "amount": 100},
		10: {"effect_key": "money_or_score", "case_address": "0x005e33ee", "amount": 200},
		11: {"effect_key": "deadline_delta_applied", "case_address": "0x005e3728", "delta_ms": 10000},
		12: {"effect_key": "life_armour_or_score", "case_address": "0x005e3770", "fallback_base_score": 1000000},
		13: {"effect_key": "rank_marker_or_score", "case_address": "0x005e3b8b", "marker_bit": 0x20, "base_score": 5000},
		14: {"effect_key": "rank_marker_or_score", "case_address": "0x005e3d99", "marker_bit": 0x10, "base_score": 5000},
		15: {"effect_key": "rank_marker_or_score", "case_address": "0x005e3fa7", "marker_bit": 0x08, "base_score": 5000},
		16: {"effect_key": "rank_marker_or_score", "case_address": "0x005e41b5", "marker_bit": 0x04, "base_score": 5000},
		17: {"effect_key": "rank_marker_or_score", "case_address": "0x005e43c3", "marker_bit": 0x02, "base_score": 5000},
		18: {"effect_key": "rank_marker_or_score", "case_address": "0x005e45d1", "marker_bit": 0x01, "base_score": 5000},
		19: {"effect_key": "bullet_capacity_or_score", "case_address": "0x005e47df", "fallback_base_score": 25000},
		20: {"effect_key": "no_effect", "case_address": "0x005e79d4"},
		21: {"effect_key": "no_effect", "case_address": "0x005e79d4"},
		22: {"effect_key": "no_effect", "case_address": "0x005e79d4"},
		23: {"effect_key": "no_effect", "case_address": "0x005e79d4"},
		24: {"effect_key": "gem_drop_progress_or_score", "case_address": "0x005e4a51", "fallback_base_score": 500},
		25: {"effect_key": "gem_drop_progress_or_score", "case_address": "0x005e4a51", "fallback_base_score": 500},
		26: {"effect_key": "gem_drop_progress_or_score", "case_address": "0x005e4a51", "fallback_base_score": 500},
		27: {"effect_key": "gem_drop_progress_or_score", "case_address": "0x005e4a51", "fallback_base_score": 500},
		28: {"effect_key": "gem_drop_progress_or_score", "case_address": "0x005e4a51", "fallback_base_score": 500},
		29: {"effect_key": "gem_drop_progress_or_score", "case_address": "0x005e4a51", "fallback_base_score": 500},
		30: {"effect_key": "gem_drop_progress_or_score", "case_address": "0x005e4a51", "fallback_base_score": 500},
		31: {"effect_key": "extra_letter_or_score", "case_address": "0x005e503e", "letter_index": 0, "duplicate_base_score": 100},
		32: {"effect_key": "extra_letter_or_score", "case_address": "0x005e5730", "letter_index": 1, "duplicate_base_score": 100},
		33: {"effect_key": "extra_letter_or_score", "case_address": "0x005e5e22", "letter_index": 2, "duplicate_base_score": 100},
		34: {"effect_key": "extra_letter_or_score", "case_address": "0x005e6514", "letter_index": 3, "duplicate_base_score": 100},
		35: {"effect_key": "extra_letter_or_score", "case_address": "0x005e6c06", "letter_index": 4, "duplicate_base_score": 100},
		36: {"effect_key": "extra_speed_or_score", "case_address": "0x005e72f8", "fallback_base_score": 25000},
		37: {"effect_key": "bonus_time_or_score", "case_address": "0x005e75a1", "bonus_time_delta": 5, "fallback_base_score": 25000},
		38: {"effect_key": "money_cap_star", "case_address": "0x005e7829", "star_cap": 10, "expanded_money_cap": 999990},
	}


func configure(contract: Dictionary) -> bool:
	_last_error = ""
	var merged := retail_contract()
	merged.merge(contract, true)
	var tile_types: Array = merged.get("tile_types", [])
	var tile_weights: Array = merged.get("tile_weights", [])
	if tile_types.is_empty() or tile_types.size() != tile_weights.size():
		return _set_error("tile_types and tile_weights must have the same non-zero size")
	var total_weight := 0
	for weight_value in tile_weights:
		var weight := int(weight_value)
		if weight <= 0:
			return _set_error("tile weights must be positive")
		total_weight += weight
	if total_weight <= 0:
		return _set_error("tile weight total must be positive")
	if int(merged.get("field_width", 0)) <= 0 or int(merged.get("field_height", 0)) <= 0:
		return _set_error("field dimensions must be positive")
	if int(merged.get("tile_size", 0)) <= 0:
		return _set_error("tile_size must be positive")
	if int(merged.get("max_grid_dimension", 0)) <= 0:
		return _set_error("max_grid_dimension must be positive")
	if int(merged.get("placement_iterations", 0)) <= 0:
		return _set_error("placement_iterations must be positive")
	if int(merged.get("success_hold_ms", -1)) < 0:
		return _set_error("success_hold_ms must be non-negative")
	if int(merged.get("skip_gate_ms", 0)) <= 0:
		return _set_error("skip_gate_ms must be positive")
	if int(merged.get("special_roll_max_exclusive", 0)) <= int(
		merged.get("special_roll_min", 0)
	):
		return _set_error("special roll range must be non-empty")
	var effects_value: Variant = merged.get("tile_effects", {})
	if not effects_value is Dictionary:
		return _set_error("tile_effects must be a dictionary")
	var effects := effects_value as Dictionary
	for tile_type in range(39):
		var descriptor_value: Variant = effects.get(
			tile_type,
			effects.get(str(tile_type), null)
		)
		if not descriptor_value is Dictionary:
			return _set_error("tile_effects must explicitly cover tile %d" % tile_type)
		var descriptor := descriptor_value as Dictionary
		if String(descriptor.get("effect_key", "")).is_empty():
			return _set_error("tile effect %d must name an effect_key" % tile_type)
		if String(descriptor.get("case_address", "")).is_empty():
			return _set_error("tile effect %d must pin its case_address" % tile_type)
	_config = merged.duplicate(true)
	_config["tile_types"] = tile_types.duplicate()
	_config["tile_weights"] = tile_weights.duplicate()
	_config["tile_weight_total"] = total_weight
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
		_set_error("Memory Station is not configured")
		return _error_result(tick, now_ms)
	if owner_seat_id < 0:
		_set_error("owner_seat_id must be non-negative")
		return _error_result(tick, now_ms)
	if tick < 0 or now_ms < 0:
		_set_error("entry tick and milliseconds must be non-negative")
		return _error_result(tick, now_ms)
	if not _is_rng_source_valid(rng_source):
		_set_error("rng_source must be a Callable or expose next_u32()")
		return _error_result(tick, now_ms)

	var maximum_dimension := int(_config.get("max_grid_dimension", MAX_GRID_DIMENSION))
	var columns := int(progression.get("memory_columns", _config.get("initial_columns", 4)))
	var rows := int(progression.get("memory_rows", _config.get("initial_rows", 4)))
	if (
		columns <= 0
		or rows <= 0
		or columns != rows
		or columns > maximum_dimension
		or rows > maximum_dimension
	):
		_set_error("Memory Station grid dimensions are outside the configured bounds")
		return _error_result(tick, now_ms)

	_owner_seat_id = owner_seat_id
	_tick = tick
	_now_ms = now_ms
	_entry_ms = now_ms
	_rng_source = rng_source
	_rng_draws_since_enter = 0
	_columns = columns
	_rows = rows
	_cursor_col = 0
	_cursor_row = 0
	_cursor_animation_frame = 0
	_cursor_animation_deadline_ms = 0
	_previous_action_mask = 0
	_pending_kind = ""
	_pending_tile_type = -1
	_reveal_deadline_ms = 0
	_success_deadline_ms = 0
	_skip_gate_ms = 0
	_countdown_gate = 11
	_tries = 0
	_matches = 0
	_mismatches = 0
	_memory_success_streak = maxi(0, int(progression.get(
		"memory_success_streak",
		_config.get("initial_success_streak", 0)
	)))
	_progression_columns = columns
	_progression_rows = rows
	_memory_point_bonus = maxi(0, int(progression.get(
		"memory_point_bonus",
		_config.get("initial_point_bonus", 25000)
	)))
	_memory_point_step = maxi(0, int(progression.get(
		"memory_point_step",
		_config.get("point_bonus_step", 25000)
	)))
	_score_multiplier = maxi(1, int(progression.get("score_multiplier", 1)))
	var effect_defaults: Dictionary = _config.get("effect_defaults", {})
	_bonus_time = maxi(0, int(progression.get("bonus_time", 20)))
	_bonus_time_max = maxi(_bonus_time, int(progression.get(
		"bonus_time_max",
		effect_defaults.get("bonus_time_max", 45)
	)))
	_money = maxi(0, int(progression.get("money", 0)))
	_money_cap = maxi(_money, int(progression.get(
		"money_cap",
		effect_defaults.get("money_cap", 99990)
	)))
	_lives = maxi(0, int(progression.get("lives", 3)))
	_lives_max = maxi(_lives, int(progression.get(
		"lives_max",
		effect_defaults.get("lives_max", 5)
	)))
	_lives_step = maxi(1, int(progression.get(
		"lives_step",
		effect_defaults.get("lives_step", 1)
	)))
	_armour_fp = maxi(0, int(progression.get("armour_fp", 0)))
	_armour_max_fp = maxi(_armour_fp, int(progression.get(
		"armour_max_fp",
		effect_defaults.get("armour_max_fp", 131072)
	)))
	_armour_step_fp = maxi(1, int(progression.get(
		"armour_step_fp",
		effect_defaults.get("armour_step_fp", 65536)
	)))
	_bullet_capacity = maxi(0, int(progression.get("bullet_capacity", 5)))
	_bullet_capacity_max = maxi(_bullet_capacity, int(progression.get(
		"bullet_capacity_max",
		effect_defaults.get("bullet_capacity_max", 50)
	)))
	_rank_markers = int(progression.get("rank_markers", 0)) & 0x3f
	_letter_bits = int(progression.get("letter_bits", 0)) & 0x1f
	_speed_fp = int(progression.get(
		"speed_fp",
		effect_defaults.get("speed_base_fp", 262144)
	))
	_speed_step_fp = maxi(1, int(progression.get(
		"speed_step_fp",
		effect_defaults.get("speed_step_fp", 45875)
	)))
	_speed_cap_fp = maxi(_speed_fp, int(progression.get(
		"speed_cap_fp",
		effect_defaults.get("speed_cap_fp", 996144)
	)))
	_gem_progress = maxi(0, int(progression.get(
		"gem_progress",
		effect_defaults.get("gem_progress_initial", 452)
	)))
	_gem_progress_origin = maxi(0, int(progression.get(
		"gem_progress_origin",
		effect_defaults.get("gem_progress_initial", 452)
	)))
	_gem_progress_step = maxi(1, int(progression.get(
		"gem_progress_step",
		effect_defaults.get("gem_progress_step", 8)
	)))
	_memory_money_stars = clampi(int(progression.get("memory_money_stars", 0)), 0, 10)
	_memory_star_floor = maxi(0, int(progression.get(
		"memory_star_floor",
		effect_defaults.get("memory_star_floor", 20)
	)))
	_memory_star_cycle = maxi(1, int(progression.get(
		"memory_star_cycle",
		effect_defaults.get("memory_star_cycle", 3)
	)))
	_stars_collected_this_board = 0
	_score_delta_total = 0
	_next_event_id = 1
	_completion_state = {}

	var duration_seconds := mini(int(_bonus_time * 3 / 2), 300)
	_mode_deadline_ms = now_ms + duration_seconds * 1000
	_stage = STAGE_ACTIVE
	_generate_grid()

	var events: Array[Dictionary] = []
	events.append(_make_event("memory_station_entered", {
		"owner_seat_id": _owner_seat_id,
		"columns": _columns,
		"rows": _rows,
		"deadline_ms": _mode_deadline_ms,
	}))
	events.append(_make_event("music_cue", {"key": "memory", "action": "play"}))
	events.append(_make_event("voice_cue", {
		"key": "memorystation",
		"rank_variant": 0,
		"queue_padding_ms": 50,
	}))
	return _result(events, {}, [], {})


func step(
	tick: int,
	now_ms: int,
	action_mask: int,
	semantic_actions: Array = []
) -> Dictionary:
	_last_error = ""
	if _stage == STAGE_IDLE:
		_set_error("Memory Station has not been entered")
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

	_tick = tick
	_now_ms = now_ms
	_advance_cursor_animation()
	var events: Array[Dictionary] = []
	var progression_deltas: Dictionary = {}
	var bonus_actions: Array[Dictionary] = []
	var completion: Dictionary = {}

	_apply_resolved_semantic_actions(
		semantic_actions,
		events,
		progression_deltas
	)

	var resolved_pending := false
	if _stage == STAGE_ACTIVE and not _pending_kind.is_empty():
		if now_ms > _reveal_deadline_ms:
			_resolve_pending(events, progression_deltas, bonus_actions)
			resolved_pending = true

	if _stage == STAGE_SUCCESS_HOLD:
		if now_ms > _success_deadline_ms:
			completion = _complete_success(events, progression_deltas)
	elif _stage == STAGE_ACTIVE:
		_update_countdown(
			events,
			_countdown_suppressed_by_kill_time(action_mask, semantic_actions)
		)
		if _pending_kind.is_empty() and not resolved_pending:
			_process_gameplay_actions(
				action_mask,
				semantic_actions,
				events,
				progression_deltas
			)
		if _stage == STAGE_ACTIVE and now_ms > _mode_deadline_ms:
			completion = _complete_failure(events)

	_previous_action_mask = action_mask
	return _result(events, progression_deltas, bonus_actions, completion)


func snapshot() -> Dictionary:
	return {
		"owner_seat_id": _owner_seat_id,
		"stage": _stage,
		"tick": _tick,
		"now_ms": _now_ms,
		"entry_ms": _entry_ms,
		"mode_deadline_ms": _mode_deadline_ms,
		"remaining_ms": _mode_deadline_ms - _now_ms,
		"reveal_deadline_ms": _reveal_deadline_ms,
		"success_deadline_ms": _success_deadline_ms,
		"skip_gate_ms": _skip_gate_ms,
		"countdown_gate": _countdown_gate,
		"columns": _columns,
		"rows": _rows,
		"surface_width": int(_config.get("field_width", 800)),
		"surface_height": int(_config.get("field_height", 600)),
		"tile_size": int(_config.get("tile_size", TILE_SIZE)),
		"grid_origin_x": _grid_origin_x,
		"grid_origin_y": _grid_origin_y,
		"cursor_col": _cursor_col,
		"cursor_row": _cursor_row,
		"cursor_highlight": _cursor_highlight_snapshot(),
		"tiles": _ordered_tiles(),
		"pending_kind": _pending_kind,
		"pending_tile_type": _pending_tile_type,
		"previous_action_mask": _previous_action_mask,
		"tries": _tries,
		"matches": _matches,
		"mismatches": _mismatches,
		"memory_success_streak": _memory_success_streak,
		"progression_columns": _progression_columns,
		"progression_rows": _progression_rows,
		"memory_point_bonus": _memory_point_bonus,
		"memory_point_step": _memory_point_step,
		"score_multiplier": _score_multiplier,
		"bonus_time": _bonus_time,
		"bonus_time_max": _bonus_time_max,
		"money": _money,
		"money_cap": _money_cap,
		"lives": _lives,
		"lives_max": _lives_max,
		"lives_step": _lives_step,
		"armour_fp": _armour_fp,
		"armour_max_fp": _armour_max_fp,
		"armour_step_fp": _armour_step_fp,
		"bullet_capacity": _bullet_capacity,
		"bullet_capacity_max": _bullet_capacity_max,
		"rank_markers": _rank_markers,
		"letter_bits": _letter_bits,
		"speed_fp": _speed_fp,
		"speed_step_fp": _speed_step_fp,
		"speed_cap_fp": _speed_cap_fp,
		"gem_progress": _gem_progress,
		"gem_progress_origin": _gem_progress_origin,
		"gem_progress_step": _gem_progress_step,
		"memory_money_stars": _memory_money_stars,
		"memory_star_floor": _memory_star_floor,
		"memory_star_cycle": _memory_star_cycle,
		"stars_collected_this_board": _stars_collected_this_board,
		"score_delta_total": _score_delta_total,
		"rng_draws_since_enter": _rng_draws_since_enter,
		"rng": _rng_snapshot(),
		"next_event_id": _next_event_id,
		"completion": _completion_state.duplicate(true),
	}


func state_for_hash() -> Dictionary:
	# Keep the tile array explicitly column-major; callers can serialize this
	# dictionary without relying on hash-map iteration for gameplay collections.
	return {
		"owner_seat_id": _owner_seat_id,
		"stage": _stage,
		"tick": _tick,
		"now_ms": _now_ms,
		"entry_ms": _entry_ms,
		"mode_deadline_ms": _mode_deadline_ms,
		"reveal_deadline_ms": _reveal_deadline_ms,
		"success_deadline_ms": _success_deadline_ms,
		"skip_gate_ms": _skip_gate_ms,
		"countdown_gate": _countdown_gate,
		"columns": _columns,
		"rows": _rows,
		"surface_width": int(_config.get("field_width", 800)),
		"surface_height": int(_config.get("field_height", 600)),
		"tile_size": int(_config.get("tile_size", TILE_SIZE)),
		"grid_origin_x": _grid_origin_x,
		"grid_origin_y": _grid_origin_y,
		"cursor_col": _cursor_col,
		"cursor_row": _cursor_row,
		"cursor_highlight": _cursor_highlight_snapshot(),
		"tiles": _ordered_tiles(),
		"pending_kind": _pending_kind,
		"pending_tile_type": _pending_tile_type,
		"previous_action_mask": _previous_action_mask,
		"tries": _tries,
		"matches": _matches,
		"mismatches": _mismatches,
		"memory_success_streak": _memory_success_streak,
		"progression_columns": _progression_columns,
		"progression_rows": _progression_rows,
		"memory_point_bonus": _memory_point_bonus,
		"memory_point_step": _memory_point_step,
		"score_multiplier": _score_multiplier,
		"bonus_time": _bonus_time,
		"bonus_time_max": _bonus_time_max,
		"money": _money,
		"money_cap": _money_cap,
		"lives": _lives,
		"lives_max": _lives_max,
		"lives_step": _lives_step,
		"armour_fp": _armour_fp,
		"armour_max_fp": _armour_max_fp,
		"armour_step_fp": _armour_step_fp,
		"bullet_capacity": _bullet_capacity,
		"bullet_capacity_max": _bullet_capacity_max,
		"rank_markers": _rank_markers,
		"letter_bits": _letter_bits,
		"speed_fp": _speed_fp,
		"speed_step_fp": _speed_step_fp,
		"speed_cap_fp": _speed_cap_fp,
		"gem_progress": _gem_progress,
		"gem_progress_origin": _gem_progress_origin,
		"gem_progress_step": _gem_progress_step,
		"memory_money_stars": _memory_money_stars,
		"memory_star_floor": _memory_star_floor,
		"memory_star_cycle": _memory_star_cycle,
		"stars_collected_this_board": _stars_collected_this_board,
		"score_delta_total": _score_delta_total,
		"rng_draws_since_enter": _rng_draws_since_enter,
		"rng": _rng_snapshot(),
		"next_event_id": _next_event_id,
		"completion": _completion_state.duplicate(true),
	}


func get_last_error() -> String:
	return _last_error


func validate_action(
	action_kind: int,
	tile_index: int,
	target_tick: int,
	now_ms: int
) -> Dictionary:
	if _stage != STAGE_ACTIVE:
		return {"ok": false, "reason": "memory_station_not_active"}
	if target_tick < _tick:
		return {"ok": false, "reason": "target_tick_is_old"}
	if now_ms < _now_ms:
		return {"ok": false, "reason": "milliseconds_move_backwards"}
	if not _pending_kind.is_empty():
		return {
			"ok": false,
			"reason": "reveal_pending",
			"until_ms": _reveal_deadline_ms,
		}
	match action_kind:
		BONUS_ACTION_SELECT_TILE:
			var cell := _cell_from_semantic_action({"tile_index": tile_index})
			if cell.is_empty():
				return {"ok": false, "reason": "tile_is_outside_active_grid"}
			var array_index := _tile_array_index(int(cell.col), int(cell.row))
			var tile: Dictionary = _tiles[array_index]
			if not bool(tile.get("active", false)):
				return {"ok": false, "reason": "tile_is_inactive"}
			if not bool(tile.get("face_down", false)):
				return {"ok": false, "reason": "tile_is_already_revealed"}
			if _last_revealed_active_tile_index() == array_index:
				return {"ok": false, "reason": "tile_is_current_selection"}
			return {
				"ok": true,
				"action_kind": action_kind,
				"tile_index": tile_index,
				"target_tick": target_tick,
			}
		BONUS_ACTION_KILL_TIME:
			if tile_index != -1:
				return {"ok": false, "reason": "kill_time_must_not_name_a_tile"}
			if _skip_gate_ms >= now_ms:
				return {
					"ok": false,
					"reason": "kill_time_throttled",
					"until_ms": _skip_gate_ms,
				}
			if _mode_deadline_ms - now_ms == 0:
				return {"ok": false, "reason": "kill_time_at_deadline_equality"}
			return {
				"ok": true,
				"action_kind": action_kind,
				"tile_index": -1,
				"target_tick": target_tick,
			}
	return {"ok": false, "reason": "unsupported_action_kind"}


func _generate_grid() -> void:
	_tiles.clear()
	var tile_size := int(_config.get("tile_size", TILE_SIZE))
	_grid_origin_x = int(
		(int(_config.get("field_width", 800)) - _columns * tile_size) / 2
	)
	_grid_origin_y = int(
		(int(_config.get("field_height", 600)) - _rows * tile_size) / 2
	)
	for col in range(_columns):
		for row in range(_rows):
			_tiles.append({
				"tile_index": col * MAX_GRID_DIMENSION + row,
				"col": col,
				"row": row,
				"x": _grid_origin_x + col * tile_size,
				"y": _grid_origin_y + row * tile_size,
				"active": true,
				"face_down": true,
				"state": 0,
				"type": 0,
			})

	var tile_types: Array = _config.get("tile_types", [])
	var tile_weights: Array = _config.get("tile_weights", [])
	var total_weight := int(_config.get("tile_weight_total", 0))
	var placement_iterations := int(
		_config.get("placement_iterations", RETAIL_PLACEMENT_ITERATIONS)
	)
	var special_injected := false
	var last_special_col := 0
	var last_special_row := 0
	while true:
		for placement in range(placement_iterations):
			last_special_col = _retail_range(0, _columns)
			var selection := _retail_range(0, total_weight)
			var type_index := 0
			while selection > int(tile_weights[type_index]):
				selection -= int(tile_weights[type_index])
				type_index += 1
				last_special_row = _retail_range(0, _rows)
			var target_col := _retail_range(0, _columns)
			var target_row := _retail_range(0, _rows)
			_tiles[_tile_array_index(target_col, target_row)]["type"] = int(
				tile_types[type_index]
			)
		var special_roll := _retail_range(
			int(_config.get("special_roll_min", 1)),
			int(_config.get("special_roll_max_exclusive", 1000))
		)
		if (
			not special_injected
			and special_roll < int(_config.get("special_roll_threshold", 7))
		):
			_tiles[_tile_array_index(last_special_col, last_special_row)]["type"] = int(
				_config.get("special_tile_type", 1)
			)
			special_injected = true
		if not _has_no_face_down_pair():
			break


func _apply_resolved_semantic_actions(
	semantic_actions: Array,
	events: Array[Dictionary],
	progression_deltas: Dictionary
) -> void:
	for action_value in semantic_actions:
		if not action_value is Dictionary:
			continue
		var action: Dictionary = action_value
		var kind := String(action.get("kind", ""))
		match kind:
			"memory_time_delta":
				var time_delta_ms := int(action.get("milliseconds", action.get("delta_ms", 0)))
				_mode_deadline_ms += time_delta_ms
				events.append(_make_event("memory_time_changed", {
					"milliseconds": time_delta_ms,
					"deadline_ms": _mode_deadline_ms,
				}))
			"score_delta":
				var score_delta := int(action.get("amount", 0))
				_add_progression_delta(progression_deltas, "score", score_delta)
				_score_delta_total += score_delta
				events.append(_make_event("memory_score_changed", {
					"score": score_delta,
				}))


func _process_gameplay_actions(
	action_mask: int,
	semantic_actions: Array,
	events: Array[Dictionary],
	progression_deltas: Dictionary
) -> void:
	var pointer_selection_consumed := false
	for action_value in semantic_actions:
		if not action_value is Dictionary:
			continue
		var action: Dictionary = action_value
		var kind := String(action.get("kind", ""))
		var numeric_kind := int(action.get("action_kind", 0))
		if kind in ["select_cell", "select_tile"] or numeric_kind == BONUS_ACTION_SELECT_TILE:
			var cell := _cell_from_semantic_action(action)
			if int(cell.get("col", -1)) < 0:
				continue
			_cursor_col = int(cell.col)
			_cursor_row = int(cell.row)
			_select_cursor_tile(events)
			pointer_selection_consumed = true
		elif kind == "kill_time" or numeric_kind == BONUS_ACTION_KILL_TIME:
			_try_kill_time(events, progression_deltas)

	if (action_mask & ACTION_SECONDARY) != 0:
		_try_kill_time(events, progression_deltas)
	if not pointer_selection_consumed and (action_mask & ACTION_FIRE) != 0:
		_select_cursor_tile(events)

	# Retail tests Fire before applying the edge-latched cursor movement.
	if _just_pressed(action_mask, ACTION_LEFT):
		_cursor_col = maxi(0, _cursor_col - 1)
	elif _just_pressed(action_mask, ACTION_RIGHT):
		_cursor_col = mini(_columns - 1, _cursor_col + 1)
	if _just_pressed(action_mask, ACTION_UP):
		_cursor_row = maxi(0, _cursor_row - 1)
	elif _just_pressed(action_mask, ACTION_DOWN):
		_cursor_row = mini(_rows - 1, _cursor_row + 1)


func _select_cursor_tile(events: Array[Dictionary]) -> void:
	var selected_index := _tile_array_index(_cursor_col, _cursor_row)
	if selected_index < 0 or selected_index >= _tiles.size():
		return
	var selected: Dictionary = _tiles[selected_index]
	if not bool(selected.get("active", false)) or not bool(selected.get("face_down", false)):
		return

	# The executable scans row-major and retains the last revealed active tile.
	var previous_index := _last_revealed_active_tile_index()
	if previous_index == selected_index:
		return
	selected["face_down"] = false
	events.append(_make_event("memory_tile_revealed", {
		"tile_index": int(selected.tile_index),
		"col": _cursor_col,
		"row": _cursor_row,
		"tile_type": int(selected.type),
	}))

	if previous_index < 0:
		if _is_instant_tile_type(int(selected.type)):
			_pending_kind = "effect"
			_pending_tile_type = int(selected.type)
			_reveal_deadline_ms = _now_ms + _instant_delay_ms(int(selected.type))
		return

	_tries += 1
	var previous: Dictionary = _tiles[previous_index]
	var delay_ms := 450
	_pending_kind = "mismatch"
	_pending_tile_type = int(selected.type)
	if _is_instant_tile_type(int(selected.type)):
		_tries -= 1
		_pending_kind = "effect"
		delay_ms = _instant_delay_ms(int(selected.type))
	if int(previous.type) == int(selected.type):
		_pending_kind = "match"
		_pending_tile_type = int(selected.type)
		delay_ms = 150
	_reveal_deadline_ms = _now_ms + delay_ms


func _resolve_pending(
	events: Array[Dictionary],
	progression_deltas: Dictionary,
	bonus_actions: Array[Dictionary]
) -> void:
	var resolved_kind := _pending_kind
	var tile_type := _pending_tile_type
	var removed_count := 0
	var gem_drop_transition_requested := false
	if resolved_kind in ["match", "effect"]:
		for tile in _tiles:
			if (
				bool(tile.get("active", false))
				and not bool(tile.get("face_down", true))
				and int(tile.get("type", -1)) == tile_type
			):
				tile["active"] = false
				tile["state"] = 0
				removed_count += 1
		if resolved_kind == "match":
			_matches += 1
		_dispatch_tile_effect(
			tile_type,
			removed_count,
			resolved_kind,
			events,
			progression_deltas,
			bonus_actions
		)
		if not bonus_actions.is_empty():
			gem_drop_transition_requested = (
				String((bonus_actions[-1] as Dictionary).get("branch", ""))
				== "gem_drop_transition"
			)
	else:
		_mismatches += 1
		for tile in _tiles:
			if bool(tile.get("active", false)) and not bool(tile.get("face_down", true)):
				tile["face_down"] = true
				tile["state"] = 0
		events.append(_make_event("memory_tiles_concealed", {}))

	_pending_kind = ""
	_pending_tile_type = -1
	_reveal_deadline_ms = 0
	if _has_no_face_down_pair() and not gem_drop_transition_requested:
		_stage = STAGE_SUCCESS_HOLD
		_apply_no_star_adaptation(progression_deltas)
		_success_deadline_ms = _now_ms + int(
			_config.get("success_hold_ms", RETAIL_SUCCESS_HOLD_MS)
		)
		events.append(_make_event("sound_cue", {
			"key": "harpgliss1",
			"volume_index": 255,
		}))
		events.append(_make_event("memory_station_success_started", {
			"until_ms": _success_deadline_ms,
		}))


func _dispatch_tile_effect(
	tile_type: int,
	removed_count: int,
	resolution: String,
	events: Array[Dictionary],
	progression_deltas: Dictionary,
	bonus_actions: Array[Dictionary]
) -> void:
	var effects: Dictionary = _config.get("tile_effects", _retail_tile_effects())
	var descriptor_value: Variant = effects.get(
		tile_type,
		effects.get(str(tile_type), {"effect_key": "no_effect", "case_address": "not_dispatched"})
	)
	var action: Dictionary = (descriptor_value as Dictionary).duplicate(true)
	action["kind"] = "memory_effect"
	action["owner_seat_id"] = _owner_seat_id
	action["tile_type"] = tile_type
	action["removed_count"] = removed_count
	action["resolution"] = resolution
	var effect_key := String(action.get("effect_key", "no_effect"))

	match effect_key:
		"deadline_delta_applied":
			var deadline_delta := int(action.get("delta_ms", 0))
			_mode_deadline_ms += deadline_delta
			_countdown_gate = 11
			action["deadline_ms"] = _mode_deadline_ms
			action["applied_by_controller"] = true
		"timed_score_multiplier":
			var previous_multiplier := _score_multiplier
			_score_multiplier = maxi(1, int(action.get("multiplier", 1)))
			_add_progression_delta(
				progression_deltas,
				"score_multiplier",
				_score_multiplier - previous_multiplier
			)
			action["duration_ms"] = _bonus_time * 1000
			action["absolute_expiry_ms"] = _now_ms + int(action.duration_ms)
			action["previous_multiplier"] = previous_multiplier
			action["applied_multiplier_via_progression_deltas"] = true
		"score_applied":
			action["score"] = _apply_score(
				int(action.get("base_score", 0)),
				progression_deltas
			)
			action["applied_via_progression_deltas"] = true
		"money_doubler":
			_apply_money_doubler_effect(action, progression_deltas)
		"money_or_score":
			_apply_money_or_score_effect(action, progression_deltas)
		"life_armour_or_score":
			_apply_life_armour_or_score_effect(action, progression_deltas)
		"rank_marker_or_score":
			var previous_markers := _rank_markers
			_rank_markers |= int(action.get("marker_bit", 0))
			_add_progression_delta(
				progression_deltas,
				"rank_markers",
				_rank_markers - previous_markers
			)
			action["rank_markers"] = _rank_markers
			action["score"] = _apply_score(
				int(action.get("base_score", 5000)),
				progression_deltas
			)
			action["applied_via_progression_deltas"] = true
		"bullet_capacity_or_score":
			if _bullet_capacity < _bullet_capacity_max:
				_bullet_capacity += 1
				_add_progression_delta(progression_deltas, "bullet_capacity", 1)
				action["branch"] = "bullet_capacity"
			else:
				action["branch"] = "score"
				action["score"] = _apply_score(
					int(action.get("fallback_base_score", 25000)),
					progression_deltas
				)
			action["bullet_capacity"] = _bullet_capacity
			action["applied_via_progression_deltas"] = true
		"gem_drop_progress_or_score":
			_apply_gem_progress_effect(action, progression_deltas, events)
		"extra_letter_or_score":
			_apply_extra_letter_effect(action, progression_deltas)
		"extra_speed_or_score":
			var previous_speed := _speed_fp
			_speed_fp += _speed_step_fp
			if _speed_fp >= _speed_cap_fp:
				_speed_fp = _speed_cap_fp
				action["branch"] = "score"
				action["score"] = _apply_score(
					int(action.get("fallback_base_score", 25000)),
					progression_deltas
				)
			else:
				action["branch"] = "speed"
			_add_progression_delta(
				progression_deltas,
				"speed_fp",
				_speed_fp - previous_speed
			)
			action["speed_fp"] = _speed_fp
			action["speed_step_fp"] = _speed_step_fp
			action["speed_cap_fp"] = _speed_cap_fp
			action["applied_via_progression_deltas"] = true
		"bonus_time_or_score":
			var previous_bonus_time := _bonus_time
			if _bonus_time < _bonus_time_max:
				_bonus_time += int(action.get("bonus_time_delta", 5))
				action["branch"] = "bonus_time"
			else:
				_bonus_time = _bonus_time_max
				action["branch"] = "score"
				action["score"] = _apply_score(
					int(action.get("fallback_base_score", 25000)),
					progression_deltas
				)
			_add_progression_delta(
				progression_deltas,
				"bonus_time",
				_bonus_time - previous_bonus_time
			)
			action["bonus_time"] = _bonus_time
			action["bonus_time_max"] = _bonus_time_max
			action["applied_via_progression_deltas"] = true
		"money_cap_star":
			_apply_money_cap_star_effect(action, progression_deltas)
		"no_effect":
			action["applied_by_controller"] = true

	bonus_actions.append(action)
	events.append(_make_event("memory_tile_effect", action))


func _apply_score(base_score: int, progression_deltas: Dictionary) -> int:
	var score := base_score * _score_multiplier
	_add_progression_delta(progression_deltas, "score", score)
	_score_delta_total += score
	return score


func _apply_money_doubler_effect(
	action: Dictionary,
	progression_deltas: Dictionary
) -> void:
	var previous_money := _money
	var threshold := int(action.get("malfunction_threshold", 450000))
	if _money >= threshold:
		action["branch"] = "malfunction"
	else:
		var doubled := _money * 2
		if doubled > _money_cap:
			_money = _money_cap
			action["branch"] = "cap_and_score"
			action["score"] = _apply_score(2 * _money_cap, progression_deltas)
		else:
			_money = doubled
			action["branch"] = "double"
	_add_progression_delta(progression_deltas, "money", _money - previous_money)
	action["money"] = _money
	action["money_cap"] = _money_cap
	action["applied_via_progression_deltas"] = true


func _apply_money_or_score_effect(
	action: Dictionary,
	progression_deltas: Dictionary
) -> void:
	var previous_money := _money
	var amount := int(action.get("amount", 0))
	_money += amount
	if _money > _money_cap:
		_money = _money_cap
		action["branch"] = "cap_and_score"
		action["score"] = _apply_score(amount, progression_deltas)
	else:
		action["branch"] = "money"
	_add_progression_delta(progression_deltas, "money", _money - previous_money)
	action["money"] = _money
	action["money_cap"] = _money_cap
	action["applied_via_progression_deltas"] = true


func _apply_life_armour_or_score_effect(
	action: Dictionary,
	progression_deltas: Dictionary
) -> void:
	if _lives < _lives_max:
		var previous_lives := _lives
		_lives = mini(_lives_max, _lives + _lives_step)
		_add_progression_delta(
			progression_deltas,
			"lives",
			_lives - previous_lives
		)
		action["branch"] = "life"
	elif _armour_fp < _armour_max_fp:
		var previous_armour := _armour_fp
		_armour_fp = mini(_armour_max_fp, _armour_fp + _armour_step_fp)
		_add_progression_delta(
			progression_deltas,
			"armour_fp",
			_armour_fp - previous_armour
		)
		action["branch"] = "armour"
	else:
		action["branch"] = "score"
		action["score"] = _apply_score(
			int(action.get("fallback_base_score", 1000000)),
			progression_deltas
		)
	action["lives"] = _lives
	action["lives_max"] = _lives_max
	action["lives_step"] = _lives_step
	action["armour_fp"] = _armour_fp
	action["armour_max_fp"] = _armour_max_fp
	action["armour_step_fp"] = _armour_step_fp
	action["applied_via_progression_deltas"] = true


func _apply_gem_progress_effect(
	action: Dictionary,
	progression_deltas: Dictionary,
	events: Array[Dictionary]
) -> void:
	# The tile branch plays its randomized bell before touching shared gem
	# progress. This draw is unconditional, including when no Gem Drop starts.
	events.append(_make_event("sound_cue", {
		"key": "bell1",
		"frequency_hz": _retail_range(22000, 32000),
		"source_hz": 32000,
		"volume_index": 255,
	}))
	var previous_progress := _gem_progress
	var triggered := false
	var super_drop := false
	for _pair_tile in range(2):
		_gem_progress += _gem_progress_step
		var quotient := int((_gem_progress - _gem_progress_origin) / _gem_progress_step)
		if posmod(quotient, 100) == 0:
			triggered = true
	if triggered:
		var final_quotient := int(
			(_gem_progress - _gem_progress_origin) / _gem_progress_step
		)
		if final_quotient >= 1000:
			super_drop = true
			_gem_progress -= _gem_progress_step * 1000
		action["branch"] = "gem_drop_transition"
		action["transition_ms"] = 4000
		action["super_gem_drop"] = super_drop
		events.append(_make_event("voice_cue", {
			"key": "gemdrop",
			"queue_padding_ms": 50,
			"drop_if_voice_busy": true,
		}))
	else:
		action["branch"] = "score"
		action["score"] = _apply_score(
			int(action.get("fallback_base_score", 500)),
			progression_deltas
		)
	_add_progression_delta(
		progression_deltas,
		"gem_progress",
		_gem_progress - previous_progress
	)
	action["gem_progress"] = _gem_progress
	action["gem_progress_origin"] = _gem_progress_origin
	action["gem_progress_step"] = _gem_progress_step
	action["applied_via_progression_deltas"] = true


func _apply_extra_letter_effect(
	action: Dictionary,
	progression_deltas: Dictionary
) -> void:
	var previous_bits := _letter_bits
	var letter_bit := 1 << int(action.get("letter_index", 0))
	if (_letter_bits & letter_bit) != 0:
		action["duplicate_score"] = _apply_score(
			int(action.get("duplicate_base_score", 100)),
			progression_deltas
		)
	_letter_bits |= letter_bit
	action["branch"] = "letter"
	if _letter_bits == 0x1f:
		_apply_life_armour_or_score_effect(action, progression_deltas)
		action["completion_branch"] = String(action.get("branch", ""))
		action["branch"] = "extra_complete"
		_letter_bits = 0
	_add_progression_delta(
		progression_deltas,
		"letter_bits",
		_letter_bits - previous_bits
	)
	action["letter_bits"] = _letter_bits
	action["letters"] = _letters_from_bits(_letter_bits)
	action["applied_via_progression_deltas"] = true


func _apply_money_cap_star_effect(
	action: Dictionary,
	progression_deltas: Dictionary
) -> void:
	var previous_stars := _memory_money_stars
	var previous_floor := _memory_star_floor
	var previous_cycle := _memory_star_cycle
	var previous_money_cap := _money_cap
	if _memory_money_stars < int(action.get("star_cap", 10)):
		_stars_collected_this_board += 1
		_memory_star_cycle = 3
		_memory_star_floor = maxi(20, _memory_star_floor - 1)
		_memory_money_stars += 1
		if _memory_money_stars >= int(action.get("star_cap", 10)):
			_memory_star_floor = 0
			_money_cap = int(action.get("expanded_money_cap", 999990))
		action["branch"] = "star_collected"
	else:
		action["branch"] = "at_cap"
	_add_progression_delta(
		progression_deltas,
		"memory_money_stars",
		_memory_money_stars - previous_stars
	)
	_add_progression_delta(
		progression_deltas,
		"memory_star_floor",
		_memory_star_floor - previous_floor
	)
	_add_progression_delta(
		progression_deltas,
		"memory_star_cycle",
		_memory_star_cycle - previous_cycle
	)
	_add_progression_delta(
		progression_deltas,
		"money_cap",
		_money_cap - previous_money_cap
	)
	action["memory_money_stars"] = _memory_money_stars
	action["memory_star_floor"] = _memory_star_floor
	action["memory_star_cycle"] = _memory_star_cycle
	action["money_cap"] = _money_cap
	action["applied_via_progression_deltas"] = true


func _apply_no_star_adaptation(
	progression_deltas: Dictionary
) -> void:
	if _stars_collected_this_board != 0 or _memory_star_floor == 0:
		return
	var previous_floor := _memory_star_floor
	var previous_cycle := _memory_star_cycle
	_memory_star_cycle -= 1
	if _memory_star_cycle == 0:
		_memory_star_cycle = 3
		_memory_star_floor += 1
	_add_progression_delta(
		progression_deltas,
		"memory_star_floor",
		_memory_star_floor - previous_floor
	)
	_add_progression_delta(
		progression_deltas,
		"memory_star_cycle",
		_memory_star_cycle - previous_cycle
	)


func _letters_from_bits(bits: int) -> String:
	var result := ""
	var letters := "EXTRA"
	for index in range(5):
		if (bits & (1 << index)) != 0:
			result += letters[index]
	return result


func _try_kill_time(
	events: Array[Dictionary],
	progression_deltas: Dictionary
) -> void:
	if _skip_gate_ms >= _now_ms:
		return
	_skip_gate_ms = _now_ms + int(_config.get("skip_gate_ms", RETAIL_SKIP_GATE_MS))
	if _mode_deadline_ms - _now_ms == 0:
		return
	_mode_deadline_ms -= 1000
	var score := _retail_range(1, 11) * 100
	var offset_x := _retail_range(0, 300)
	var offset_y := _retail_range(0, 300)
	var pitch := _retail_range(10000, 41000)
	_add_progression_delta(progression_deltas, "score", score)
	_score_delta_total += score
	events.append(_make_event("memory_kill_time", {
		"score": score,
		"deadline_ms": _mode_deadline_ms,
		"presentation_x_offset": offset_x,
		"presentation_y_offset": offset_y,
		"presentation_pitch": pitch,
	}))


func _countdown_suppressed_by_kill_time(
	action_mask: int,
	semantic_actions: Array
) -> bool:
	if (action_mask & ACTION_SECONDARY) != 0:
		return true
	for action_value in semantic_actions:
		if not action_value is Dictionary:
			continue
		var action: Dictionary = action_value
		if (
			String(action.get("kind", "")) == "kill_time"
			or int(action.get("action_kind", 0)) == BONUS_ACTION_KILL_TIME
		):
			return true
	return false


func _update_countdown(
	events: Array[Dictionary],
	suppress_voice: bool = false
) -> void:
	var remaining := _mode_deadline_ms - _now_ms
	for spoken_second in range(10, 0, -1):
		if (
			remaining > spoken_second * 1000
			and remaining < (spoken_second + 1) * 1000
			and _countdown_gate == spoken_second + 1
		):
			_countdown_gate = spoken_second
			if not suppress_voice:
				events.append(_make_event("memory_countdown", {
					"seconds": spoken_second,
					"remaining_ms": remaining,
				}))
			return
	if remaining > 0 and remaining < 1000 and _countdown_gate == 1:
		_countdown_gate = 11


func _complete_success(
	events: Array[Dictionary],
	progression_deltas: Dictionary
) -> Dictionary:
	_stage = STAGE_COMPLETE
	var previous_success_streak := _memory_success_streak
	_memory_success_streak += 1
	var previous_columns := _progression_columns
	var previous_rows := _progression_rows
	if _memory_success_streak == 2:
		_memory_success_streak = 0
		if _progression_columns < int(_config.get("max_grid_dimension", MAX_GRID_DIMENSION)):
			_progression_columns += 1
			_progression_rows += 1

	var previous_point_bonus := _memory_point_bonus
	_memory_point_bonus += _memory_point_step
	var score_award := _memory_point_bonus * _score_multiplier
	_score_delta_total += score_award
	_add_progression_delta(progression_deltas, "score", score_award)
	_add_progression_delta(
		progression_deltas,
		"memory_success_streak",
		_memory_success_streak - previous_success_streak
	)
	_add_progression_delta(
		progression_deltas,
		"memory_point_bonus",
		_memory_point_bonus - previous_point_bonus
	)
	_add_progression_delta(
		progression_deltas,
		"memory_columns",
		_progression_columns - previous_columns
	)
	_add_progression_delta(
		progression_deltas,
		"memory_rows",
		_progression_rows - previous_rows
	)
	_completion_state = {
		"success": true,
		"owner_seat_id": _owner_seat_id,
		"score_award": score_award,
		"memory_columns": _progression_columns,
		"memory_rows": _progression_rows,
		"memory_success_streak": _memory_success_streak,
		"memory_point_bonus": _memory_point_bonus,
		"tries": _tries,
		"matches": _matches,
		"mismatches": _mismatches,
	}
	events.append(_make_event("memory_station_completed", _completion_state))
	return _completion_state.duplicate(true)


func _complete_failure(events: Array[Dictionary]) -> Dictionary:
	_stage = STAGE_COMPLETE
	_completion_state = {
		"success": false,
		"owner_seat_id": _owner_seat_id,
		"memory_columns": _progression_columns,
		"memory_rows": _progression_rows,
		"memory_success_streak": _memory_success_streak,
		"memory_point_bonus": _memory_point_bonus,
		"tries": _tries,
		"matches": _matches,
		"mismatches": _mismatches,
	}
	events.append(_make_event("memory_station_completed", _completion_state))
	return _completion_state.duplicate(true)


func _cell_from_semantic_action(action: Dictionary) -> Dictionary:
	if action.has("col") and action.has("row"):
		var col := int(action.col)
		var row := int(action.row)
		if col >= 0 and col < _columns and row >= 0 and row < _rows:
			return {"col": col, "row": row}
		return {}
	var tile_index := int(action.get("tile_index", -1))
	if tile_index < 0 or tile_index >= MAX_GRID_DIMENSION * MAX_GRID_DIMENSION:
		return {}
	var fixed_col := int(tile_index / MAX_GRID_DIMENSION)
	var fixed_row := tile_index % MAX_GRID_DIMENSION
	if fixed_col >= _columns or fixed_row >= _rows:
		return {}
	return {"col": fixed_col, "row": fixed_row}


func _last_revealed_active_tile_index() -> int:
	var result := -1
	for row in range(_rows):
		for col in range(_columns):
			var index := _tile_array_index(col, row)
			var tile: Dictionary = _tiles[index]
			if bool(tile.get("active", false)) and not bool(tile.get("face_down", true)):
				result = index
	return result


func _has_no_face_down_pair() -> bool:
	var counts: Dictionary = {}
	for tile in _tiles:
		if not bool(tile.get("active", false)) or not bool(tile.get("face_down", false)):
			continue
		var tile_type := int(tile.get("type", 0))
		var count := int(counts.get(tile_type, 0)) + 1
		if count >= 2:
			return false
		counts[tile_type] = count
	return true


func _is_instant_tile_type(tile_type: int) -> bool:
	return tile_type in [0, 1, 11, 38]


func _instant_delay_ms(tile_type: int) -> int:
	match tile_type:
		0:
			return 150
		1:
			return 350
		11, 38:
			return 450
	return 450


func _tile_array_index(col: int, row: int) -> int:
	return col * _rows + row


func _ordered_tiles() -> Array[Dictionary]:
	var ordered: Array[Dictionary] = []
	for col in range(_columns):
		for row in range(_rows):
			var tile: Dictionary = _tiles[_tile_array_index(col, row)].duplicate(true)
			var face_up_rect := _tile_face_up_source_rect(int(tile.get("type", 0)))
			tile["face_up_source_rect"] = face_up_rect
			tile["source_rect"] = (
				_retail_contract_atlas().face_down_source_rect.duplicate(true)
				if bool(tile.get("face_down", true))
				else face_up_rect.duplicate(true)
			)
			ordered.append(tile)
	return ordered


func _tile_face_up_source_rect(tile_type: int) -> Dictionary:
	return {
		"x": posmod(tile_type, 4) * TILE_SIZE,
		"y": int(tile_type / 4) * TILE_SIZE,
		"width": TILE_SIZE,
		"height": TILE_SIZE,
	}


func _cursor_highlight_snapshot() -> Dictionary:
	var atlas := _retail_contract_atlas()
	var frames: Array = atlas.cursor_frame_source_rects
	return {
		"animation_frame": _cursor_animation_frame,
		"animation_deadline_ms": _cursor_animation_deadline_ms,
		"source_rect": (frames[_cursor_animation_frame] as Dictionary).duplicate(true),
		"destination_rect": {
			"x": _grid_origin_x + _cursor_col * int(_config.get("tile_size", TILE_SIZE)),
			"y": _grid_origin_y + _cursor_row * int(_config.get("tile_size", TILE_SIZE)),
			"width": int(_config.get("tile_size", TILE_SIZE)),
			"height": int(_config.get("tile_size", TILE_SIZE)),
		},
	}


func _advance_cursor_animation() -> void:
	if _stage == STAGE_COMPLETE or _now_ms <= _cursor_animation_deadline_ms:
		return
	_cursor_animation_deadline_ms = _now_ms + 50
	_cursor_animation_frame += 1
	if _cursor_animation_frame > 5:
		_cursor_animation_frame = 0


func _retail_contract_atlas() -> Dictionary:
	return _config.get("atlas", retail_contract().atlas) as Dictionary


func _retail_range(minimum: int, maximum_exclusive: int) -> int:
	# The executable helper consumes no draw for an empty span and otherwise
	# applies modulo to one full-width raw generator word.
	if maximum_exclusive <= minimum:
		return minimum
	return minimum + int(_next_u32() % (maximum_exclusive - minimum))


func _next_u32() -> int:
	var value := 0
	if _rng_source is Callable:
		value = int((_rng_source as Callable).call())
	else:
		value = int((_rng_source as Object).call("next_u32"))
	_rng_draws_since_enter += 1
	return value & 0xffffffff


func _rng_snapshot() -> Dictionary:
	if _rng_source is Object and (_rng_source as Object).has_method("snapshot"):
		var value: Variant = (_rng_source as Object).call("snapshot")
		if value is Dictionary:
			return (value as Dictionary).duplicate(true)
	return {"draws_since_enter": _rng_draws_since_enter}


func _is_rng_source_valid(source: Variant) -> bool:
	if source is Callable:
		return (source as Callable).is_valid()
	return source is Object and (source as Object).has_method("next_u32")


func _just_pressed(action_mask: int, action: int) -> bool:
	return (
		(action_mask & action) != 0
		and (_previous_action_mask & action) == 0
	)


func _add_progression_delta(deltas: Dictionary, key: String, amount: int) -> void:
	if amount == 0:
		return
	deltas[key] = int(deltas.get(key, 0)) + amount


func _make_event(kind: String, payload: Dictionary) -> Dictionary:
	var event := payload.duplicate(true)
	event["id"] = _next_event_id
	event["kind"] = kind
	event["tick"] = _tick
	event["now_ms"] = _now_ms
	_next_event_id += 1
	return event


func _result(
	events: Array[Dictionary],
	progression_deltas: Dictionary,
	bonus_actions: Array[Dictionary],
	completion: Dictionary
) -> Dictionary:
	return {
		"ok": true,
		"tick": _tick,
		"now_ms": _now_ms,
		"events": events.duplicate(true),
		"progression_deltas": progression_deltas.duplicate(true),
		"bonus_actions": bonus_actions.duplicate(true),
		"completion": completion.duplicate(true),
		"snapshot": snapshot(),
	}


func _error_result(requested_tick: int, requested_now_ms: int) -> Dictionary:
	return {
		"ok": false,
		"tick": requested_tick,
		"now_ms": requested_now_ms,
		"error": _last_error,
		"events": [],
		"progression_deltas": {},
		"bonus_actions": [],
		"completion": {},
		"snapshot": snapshot(),
	}


func _set_error(message: String) -> bool:
	_last_error = message
	return false

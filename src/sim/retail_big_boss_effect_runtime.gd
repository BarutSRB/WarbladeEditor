class_name RetailBigBossEffectRuntime
extends RefCounted

# Root-authoritative, bounded runtime for the visual-effect calls made by the
# WarBlade 1.34 state-13 collision branch. Pool occupancy is gameplay-relevant:
# a full pool returns before its per-record RNG draws, so these records belong
# in deterministic state even though their pixels are presentation.

const CONTRACT_ID: String = "retail_big_boss_effects_v1"
const RETAIL_EXECUTABLE_SHA256: String = (
	"ddf1778c307af1087ff9dcb512786111e665d972298aeaac3f1b4b2996d079ef"
)
const U32_MASK: int = 0xffffffff

const FLASH_POOL_CAPACITY: int = 50
const DEBRIS_POOL_CAPACITY: int = 150
const SMOKE_POOL_CAPACITY: int = 500
const PARTICLE_POOL_CAPACITY: int = 1000
const SCREEN_POOL_CAPACITY: int = 4

const HIGH_EFFECTS: bool = true
const PARTICLE_DENSITY: int = 100

const VELOCITY_DECAY: float = 0.9800000190734863
const SMOKE_MAGNITUDE_CUTOFF: float = 0.019999999552965164
const FLASH_FADE_MULTIPLIER: float = 0.8500000238418579
const FLASH_FADE_CUTOFF: float = 20.0
const SCREEN_RADIAL_STEP: float = 35.0
const SCREEN_ALPHA: float = 500.0
const SCREEN_ALPHA_MULTIPLIER: float = 0.949999988079071
const SCREEN_ALPHA_CUTOFF: float = 10.0
const DEBRIS_LIFE: float = 10.0
const DEBRIS_COUNT_MULTIPLIER: float = 0.6000000238418579
const DEBRIS_FRAME_COUNT: int = 10
const SMALL_EXPLOSION_PERIOD: float = 6.0
const SMALL_EXPLOSION_VELOCITY_Y: Array[float] = [1.5, 3.0, 4.0, 5.0, 6.0, 7.0, 10.0]
const SMALL_EXPLOSION_RENDER_TYPE: Array[int] = [48, 49, 50, 51, 52, 53, 64]

var _configured: bool = false
var _blocked: bool = false
var _last_error: String = ""
var _root_rng_draw_count: int = 0
var _frame: int = 0

var _flash_pool: Array[Dictionary] = []
var _debris_pool: Array[Dictionary] = []
var _smoke_pool: Array[Dictionary] = []
var _particle_pool: Array[Dictionary] = []
var _screen_pool: Array[Dictionary] = []


static func retail_contract() -> Dictionary:
	return {
		"id": CONTRACT_ID,
		"executable_sha256": RETAIL_EXECUTABLE_SHA256,
		"preset": {
			"id": "retail_high",
			"high_effects": HIGH_EFFECTS,
			"particle_density": PARTICLE_DENSITY,
			"evidence": "0x005bab12/0x005bab3a",
		},
		"pools": {
			"flash": {"capacity": FLASH_POOL_CAPACITY, "base": "DAT_00847720"},
			"debris": {"capacity": DEBRIS_POOL_CAPACITY, "base": "DAT_00b04a54"},
			"smoke": {"capacity": SMOKE_POOL_CAPACITY, "base": "DAT_00ac5c98"},
			"particle": {"capacity": PARTICLE_POOL_CAPACITY, "base": "DAT_007e3948"},
			"screen": {"capacity": SCREEN_POOL_CAPACITY, "base": "DAT_008ff578"},
		},
		"creation_order": {
			"FUN_005dfee0": ["scan_flash", "RngInt(0,2)"],
			"FUN_005e0650": [
				"scan_screen_if_variant_positive",
				"scan_flash",
				"RngInt(0,3)",
				"RngInt(0,150)",
				"FUN_005df370(density*3)",
			],
			"FUN_005defe0_each_allocated": [
				"RngInt(0,359)",
				"RngFloat(1,6)",
				"RngFloat(2,3)",
				"RngInt(0,5)",
				"RngInt(0,2)",
				"RngFloat(5,45)",
				"RngInt(0,100)",
				"RngInt(150,255)",
			],
			"FUN_0052f440": [
				"RngFloat(1.5,6) x3 before scan",
				"count+1 allocation attempts",
				"each: RngFloat(1,40), RngFloat(2,4), RngFloat(.01,.2), RngInt(0,3600)",
			],
			"FUN_00570420": {
				"rank_ready_false": ["RngInt(0,6)"],
				"rank_ready_true": [
					"RngInt(0,5)",
					"RngInt(0,7) if eligibility roll is 0, otherwise RngInt(0,6)",
				],
			},
			"FUN_00571080_each_allocated": {
				"only_blue_coins_false": ["RngInt(0,100)", "remaining record draws"],
				"only_blue_coins_true": ["force base type 32", "remaining record draws"],
			},
		},
		"same_tick_update_order": [
			"FUN_00622150_flash",
			"FUN_00622540_screen",
			"FUN_00622be0_smoke",
			"FUN_0052f8a0_particle",
			"FUN_005f4210_debris",
		],
		"exact_trace_complete": true,
	}


func configure(contract: Dictionary) -> bool:
	_last_error = ""
	_configured = false
	if String(contract.get("id", "")) != CONTRACT_ID:
		return _set_error("boss effect contract id must be retail_big_boss_effects_v1")
	if String(contract.get("executable_sha256", "")) != RETAIL_EXECUTABLE_SHA256:
		return _set_error("boss effect contract does not match the pinned executable")
	if not bool(contract.get("exact_trace_complete", false)):
		return _set_error("boss effect runtime trace is incomplete")
	if not _contract_value_matches(contract, retail_contract()):
		return _set_error(
			"boss effect contract differs from the pinned pools, preset, or RNG order"
		)
	_configured = true
	reset()
	return true


func reset() -> void:
	_blocked = false
	_last_error = ""
	_root_rng_draw_count = 0
	_frame = 0
	_flash_pool = _empty_pool(FLASH_POOL_CAPACITY)
	_debris_pool = _empty_pool(DEBRIS_POOL_CAPACITY)
	_smoke_pool = _empty_pool(SMOKE_POOL_CAPACITY)
	_particle_pool = _empty_pool(PARTICLE_POOL_CAPACITY)
	_screen_pool = _empty_pool(SCREEN_POOL_CAPACITY)


func dispatch_retail_effect(
	call_name: String,
	payload: Dictionary,
	rng_source: Variant
) -> Dictionary:
	_last_error = ""
	if not _configured:
		return _error_result("boss effect runtime is not configured")
	if not _is_rng_source_valid(rng_source):
		return _error_result("effect dispatch requires the authoritative root RNG")
	var draws_before := _root_rng_draw_count
	var occupied_before := _occupied_slots_by_pool()
	var allocated_slots: Array[int] = []
	match call_name:
		"FUN_005dfee0":
			allocated_slots = _create_hit_flash(payload, rng_source)
		"FUN_00570420":
			allocated_slots = _create_small_explosion(payload, rng_source)
		"FUN_00571080":
			allocated_slots = _create_debris_burst(payload, rng_source)
		"FUN_005e0650":
			allocated_slots = _create_large_burst(payload, rng_source)
		"FUN_0052f440":
			allocated_slots = _create_particle_field(payload, rng_source)
		"FUN_005defe0":
			allocated_slots = _create_smoke(payload, rng_source)
		_:
			return _error_result("unrecognized retail effect call %s" % call_name)
	if _blocked:
		return _error_result(_last_error)
	var allocations := _allocation_delta(occupied_before, _occupied_slots_by_pool())
	var allocated_count := 0
	for pool_slots_value in allocations.values():
		allocated_count += (pool_slots_value as Array).size()
	var result := {
		"ok": true,
		"call": call_name,
		"allocations": allocations,
		"allocated_count": allocated_count,
		"rng_draws": _root_rng_draw_count - draws_before,
	}
	if call_name == "FUN_005dfee0" and allocated_count > 0:
		var flash_slots := allocations.get("flash", []) as Array
		if flash_slots.size() != 1:
			return _error_result("FUN_005dfee0 must allocate exactly one flash record")
		var flash_record := _flash_pool[int(flash_slots[0])] as Dictionary
		result["frame_period"] = int(flash_record.get("period", -1))
	return result


func step(tick_scale: float, rng_source: Variant, context: Dictionary = {}) -> Dictionary:
	_last_error = ""
	if not _configured:
		return _error_result("boss effect runtime is not configured")
	var scale := _f32(tick_scale)
	if scale <= 0.0:
		return _error_result("boss effect tick_scale must be positive")
	if not _is_rng_source_valid(rng_source):
		return _error_result("effect update requires the authoritative root RNG")
	if bool(context.get("paused", false)):
		return _error_result("paused retail effect state is outside the deterministic match contract")
	_frame += 1
	_update_flash_pool()
	_update_screen_pool()
	_update_smoke_pool()
	_update_particle_pool(scale)
	_update_debris_pool(scale, rng_source, context)
	return {"ok": not _blocked, "error": _last_error, "snapshot": snapshot()}


func snapshot() -> Dictionary:
	return {
		"contract_id": CONTRACT_ID,
		"blocked": _blocked,
		"frame": _frame,
		"root_rng_draw_count": _root_rng_draw_count,
		"preset": "retail_high",
		"pools": {
			"flash": _pool_snapshot(_flash_pool, FLASH_POOL_CAPACITY),
			"debris": _pool_snapshot(_debris_pool, DEBRIS_POOL_CAPACITY),
			"smoke": _pool_snapshot(_smoke_pool, SMOKE_POOL_CAPACITY),
			"particle": _pool_snapshot(_particle_pool, PARTICLE_POOL_CAPACITY),
			"screen": _pool_snapshot(_screen_pool, SCREEN_POOL_CAPACITY),
		},
	}


func state_hash_payload() -> Dictionary:
	# Active records include their ascending slot index; inactive holes therefore
	# remain reconstructible without hashing thousands of identical false rows.
	return snapshot()


func get_last_error() -> String:
	return _last_error


func _create_hit_flash(payload: Dictionary, rng: Variant) -> Array[int]:
	if not _require_kind(payload, ["boss_hit"]):
		return []
	var slot := _first_free(_flash_pool)
	if slot < 0:
		return []
	var period := _rng_int(rng, 0, 2)
	_flash_pool[slot] = {
		"active": true,
		"slot": slot,
		"kind": "boss_hit",
		"x": _f32(float(payload.get("x", 0.0))),
		"y": _f32(float(payload.get("y", 0.0))),
		"effect_type": 10,
		"frame": 0,
		"period": float(period),
		"countdown": float(period),
		"special": false,
	}
	return [slot]


func _create_large_burst(payload: Dictionary, rng: Variant) -> Array[int]:
	var kind := String(payload.get("kind", ""))
	if not kind in ["boss_death_burst_left", "boss_death_burst_right"]:
		_set_blocked("FUN_005e0650 payload has an invalid state-13 kind")
		return []
	var first := kind == "boss_death_burst_left"
	var expected_size := [256, 128]
	var expected_palette := [255, 200, 255] if first else [255, 0, 0]
	var expected_variant := 1 if first else 0
	if (
		payload.get("size", []) != expected_size
		or payload.get("palette", []) != expected_palette
		or int(payload.get("variant", -1)) != expected_variant
	):
		_set_blocked("FUN_005e0650 payload differs from the pinned death call")
		return []
	var left := _f32(float(payload.get("x", 0.0)))
	var top := _f32(float(payload.get("y", 0.0)))
	var center_x := _f32(left + 128.0)
	var center_y := _f32(top + 64.0)
	if first:
		var screen_slot := _first_free(_screen_pool)
		if screen_slot >= 0:
			_screen_pool[screen_slot] = {
				"active": true,
				"slot": screen_slot,
				"kind": "boss_death_screen_wave",
				"center_x": int(center_x),
				"center_y": int(center_y),
				"radius": 16,
				"radial_step": SCREEN_RADIAL_STEP,
				"red": 255,
				"green": 200,
				"blue": 255,
				"alpha": SCREEN_ALPHA,
				"variant": 1,
			}
	var slot := _first_free(_flash_pool)
	if slot < 0:
		return []
	var period := _rng_int(rng, 0, 3) + 2
	var fade := _rng_int(rng, 0, 150) + 400
	_flash_pool[slot] = {
		"active": true,
		"slot": slot,
		"kind": kind,
		"x": center_x,
		"y": center_y,
		"effect_type": 3 if first else 0,
		"frame": 0,
		"period": float(period),
		"countdown": float(period),
		"special": HIGH_EFFECTS,
		"red": int(expected_palette[0]),
		"green": int(expected_palette[1]),
		"blue": int(expected_palette[2]),
		"fade": float(fade),
		"fade_multiplier": FLASH_FADE_MULTIPLIER,
	}
	var smoke_slots := _create_smoke_records(
		PARTICLE_DENSITY * 3,
		center_x,
		center_y,
		2.0,
		8.0,
		1.5,
		3.5,
		[int(expected_palette[0]), int(expected_palette[1]), int(expected_palette[2])],
		false,
		rng,
		kind + "_particles"
	)
	var result: Array[int] = [slot]
	# Pool identity is explicit in the response; smoke slots are offset so a
	# consumer cannot accidentally treat them as flash-pool indexes.
	for smoke_slot in smoke_slots:
		result.append(FLASH_POOL_CAPACITY + int(smoke_slot))
	return result


func _create_smoke(payload: Dictionary, rng: Variant) -> Array[int]:
	var kind := String(payload.get("kind", ""))
	if not kind in ["boss_terminal_hit_smoke", "boss_death_smoke"]:
		_set_blocked("FUN_005defe0 payload has an invalid state-13 kind")
		return []
	var count := int(payload.get("count", 0))
	var minimum_count := 10 if kind == "boss_terminal_hit_smoke" else 50
	var maximum_count := 20 if kind == "boss_terminal_hit_smoke" else 100
	if count < minimum_count or count >= maximum_count:
		_set_blocked("FUN_005defe0 count is outside the traced half-open range")
		return []
	return _create_smoke_records(
		count,
		_f32(float(payload.get("x", 0.0))),
		_f32(float(payload.get("y", 0.0))),
		1.0,
		6.0,
		2.0,
		3.0,
		[255, 255, 255],
		true,
		rng,
		kind
	)


func _create_smoke_records(
	count: int,
	x: float,
	y: float,
	speed_min: float,
	speed_max: float,
	secondary_min: float,
	secondary_max: float,
	palette: Array[int],
	random_color: bool,
	rng: Variant,
	kind: String
) -> Array[int]:
	var allocated: Array[int] = []
	var remaining := count
	for slot in range(SMOKE_POOL_CAPACITY):
		if remaining < 1:
			break
		if bool((_smoke_pool[slot] as Dictionary).get("active", false)):
			continue
		var angle_index := _rng_int(rng, 0, 359)
		var speed := _rng_float(rng, speed_min, speed_max)
		var secondary := _f32(_rng_float(rng, secondary_min, secondary_max) / 20.0)
		# FUN_0059f1a0 fills DAT_D55e48 with sin and DAT_AF5270 with cos.
		var velocity_x := _f32(sin(deg_to_rad(float(angle_index))) * speed)
		var velocity_y := _f32(cos(deg_to_rad(float(angle_index))) * speed)
		var ratio := 1.0 if secondary == 0.0 else _f32(speed / secondary)
		if ratio == 0.0:
			ratio = 1.0
		var frame_step := _f32(10.0 / ratio)
		var source_variant := _rng_int(rng, 0, 5)
		var source_row := _rng_int(rng, 0, 2) * 13
		var rotation_speed := _rng_float(rng, 5.0, 45.0)
		var red := int(palette[0])
		var green := int(palette[1])
		var blue := int(palette[2])
		if random_color:
			red = _rng_int(rng, 0, 100)
			green = _rng_int(rng, 150, 255)
			blue = 255
		_smoke_pool[slot] = {
			"active": true,
			"slot": slot,
			"kind": kind,
			"x": x,
			"y": y,
			"velocity_x": velocity_x,
			"velocity_y": velocity_y,
			"secondary_velocity_x": _f32(sin(deg_to_rad(float(angle_index))) * secondary),
			"secondary_velocity_y": _f32(cos(deg_to_rad(float(angle_index))) * secondary),
			"angle_index": angle_index,
			"speed": speed,
			"secondary_speed": secondary,
			"frame_accumulator": 0.0,
			"frame_step": frame_step,
			"frame": 0,
			"source_variant": source_variant,
			"source_row": source_row,
			"rotation_speed": rotation_speed,
			"red": red,
			"green": green,
			"blue": blue,
		}
		allocated.append(slot)
		remaining -= 1
	return allocated


func _create_particle_field(payload: Dictionary, rng: Variant) -> Array[int]:
	if not _require_kind(payload, ["boss_death_particles"]):
		return []
	if int(payload.get("count", -1)) != 500 or payload.get("palette", []) != [100, 255, 100]:
		_set_blocked("FUN_0052f440 payload differs from the pinned count/palette")
		return []
	var red_decay := _rng_float(rng, 1.5, 6.0)
	var green_decay := _rng_float(rng, 1.5, 6.0)
	var blue_decay := _rng_float(rng, 1.5, 6.0)
	var allocated: Array[int] = []
	var parameter_count := 500
	for slot in range(PARTICLE_POOL_CAPACITY):
		if bool((_particle_pool[slot] as Dictionary).get("active", false)):
			continue
		var vertical_position := _rng_float(rng, 1.0, 40.0)
		var vertical_velocity := _rng_float(rng, 2.0, 4.0)
		var vertical_deceleration := _rng_float(rng, 0.009999999776482582, 0.20000000298023224)
		var angle := _rng_int(rng, 0, 3600)
		_particle_pool[slot] = {
			"active": true,
			"slot": slot,
			"kind": "boss_death_particles",
			"x": _f32(float(payload.get("x", 0.0))),
			"y": _f32(float(payload.get("y", 0.0))),
			"vertical_position": vertical_position,
			"vertical_velocity": vertical_velocity,
			"vertical_deceleration": vertical_deceleration,
			"red": 100.0,
			"green": 255.0,
			"blue": 100.0,
			"red_decay": red_decay,
			"green_decay": green_decay,
			"blue_decay": blue_decay,
			"angle": angle,
		}
		allocated.append(slot)
		var old_count := parameter_count
		parameter_count -= 1
		if old_count == 0:
			break
	return allocated


func _create_small_explosion(payload: Dictionary, rng: Variant) -> Array[int]:
	if not _require_kind(payload, ["boss_death_small_explosion"]):
		return []
	var slot := _first_free(_debris_pool)
	if slot < 0:
		return []
	if (
		not payload.has("rank_ready")
		or typeof(payload.rank_ready) != TYPE_BOOL
	):
		_set_blocked("FUN_00570420 requires the killer's rank-ready boolean")
		return []
	var rank_ready := bool(payload.rank_ready)
	var bound := 6
	if rank_ready and _rng_int(rng, 0, 5) == 0:
		bound = 7
	var variant := _rng_int(rng, 0, bound)
	_debris_pool[slot] = {
		"active": true,
		"slot": slot,
		"kind": "boss_death_small_explosion",
		"x": _f32(float(payload.get("x", 0.0)) + 22.0),
		"y": _f32(float(payload.get("y", 0.0))),
		"velocity_x": 0.0,
		"velocity_y": SMALL_EXPLOSION_VELOCITY_Y[variant],
		"variant": variant,
		"rank_ready": rank_ready,
		"render_type": SMALL_EXPLOSION_RENDER_TYPE[variant],
		"base_type": SMALL_EXPLOSION_RENDER_TYPE[variant],
		"frame": 0,
		"frame_count": DEBRIS_FRAME_COUNT,
		"period": SMALL_EXPLOSION_PERIOD,
		"countdown": SMALL_EXPLOSION_PERIOD,
	}
	return [slot]


func _create_debris_burst(payload: Dictionary, rng: Variant) -> Array[int]:
	if not _require_kind(payload, ["boss_death_flash"]):
		return []
	if payload.get("flags", []) != [1, 1]:
		_set_blocked("FUN_00571080 requires the traced [1,1] flags")
		return []
	if (
		not payload.has("only_blue_coins_active")
		or typeof(payload.only_blue_coins_active) != TYPE_BOOL
	):
		_set_blocked("FUN_00571080 requires the active progression force-type flag")
		return []
	var force_type_32 := bool(payload.only_blue_coins_active)
	var count := _rng_int(rng, 0, 15) + 30
	count = int(float(count) * DEBRIS_COUNT_MULTIPLIER)
	var segment_remaining := _rng_int(rng, 0, 6) + 6
	var angle_index := _rng_int(rng, 0, 360)
	var segment_step := int(360.0 / float(segment_remaining))
	var allocated: Array[int] = []
	var remaining := count
	for slot in range(DEBRIS_POOL_CAPACITY):
		if remaining < 1:
			break
		if bool((_debris_pool[slot] as Dictionary).get("active", false)):
			continue
		var base_type := 32
		if not force_type_32:
			var type_roll := _rng_int(rng, 0, 100)
			base_type = 29
			if type_roll > 40 and type_roll < 68:
				base_type = 30
			elif type_roll > 67 and type_roll < 88:
				base_type = 31
			elif type_roll > 87:
				base_type = 32
		var speed := _rng_float(rng, 2.0, 8.0)
		var velocity_x := _f32(sin(deg_to_rad(float(angle_index))) * speed)
		var velocity_y := _f32(cos(deg_to_rad(float(angle_index))) * speed)
		angle_index += segment_step
		if angle_index > 359:
			angle_index -= 360
		segment_remaining -= 1
		if segment_remaining < 0:
			segment_remaining = _rng_int(rng, 0, 6) + 6
			angle_index = _rng_int(rng, 0, 360)
			segment_step = int(360.0 / float(segment_remaining))
		var period := _rng_float(rng, 3.0, 7.0)
		var frame := _rng_int(rng, 0, 10)
		_debris_pool[slot] = {
			"active": true,
			"slot": slot,
			"kind": "boss_death_debris",
			"x": _f32(float(payload.get("x", 0.0))),
			"y": _f32(float(payload.get("y", 0.0))),
			"velocity_x": velocity_x,
			"velocity_y": velocity_y,
			"life": DEBRIS_LIFE,
			"transitioned": false,
			"render_type": base_type + 9,
			"base_type": base_type,
			"period": period,
			"countdown": period,
			"frame": frame,
			"frame_count": DEBRIS_FRAME_COUNT,
			"boss_bool": true,
			"force_type_32": force_type_32,
		}
		allocated.append(slot)
		remaining -= 1
	return allocated


func _update_flash_pool() -> void:
	for slot in range(FLASH_POOL_CAPACITY):
		var record := _flash_pool[slot] as Dictionary
		if not bool(record.get("active", false)):
			continue
		record.countdown = _f32(float(record.countdown) - 1.0)
		if float(record.countdown) >= 0.0:
			continue
		record.countdown = float(record.period)
		if bool(record.get("special", false)):
			var fade := float(record.get("fade", 0.0))
			if fade <= 0.0:
				record.active = false
			else:
				fade = _f32(fade * FLASH_FADE_MULTIPLIER)
				record.fade = fade
				if fade < FLASH_FADE_CUTOFF:
					record.active = false
		record.frame = int(record.frame) + 1
		if int(record.effect_type) == 10:
			if int(record.frame) > 12:
				record.active = false
		elif int(record.frame) > 13:
			record.active = false


func _update_screen_pool() -> void:
	for slot in range(SCREEN_POOL_CAPACITY):
		var record := _screen_pool[slot] as Dictionary
		if not bool(record.get("active", false)):
			continue
		record.radius = int(record.radius) + int(float(record.radial_step))
		if int(record.radius) > 1000:
			record.active = false
		record.radial_step = _f32(float(record.radial_step) * VELOCITY_DECAY)
		record.alpha = _f32(float(record.alpha) * SCREEN_ALPHA_MULTIPLIER)
		if float(record.alpha) < SCREEN_ALPHA_CUTOFF:
			record.active = false


func _update_smoke_pool() -> void:
	for slot in range(SMOKE_POOL_CAPACITY):
		var record := _smoke_pool[slot] as Dictionary
		if not bool(record.get("active", false)):
			continue
		record.x = _f32(float(record.x) + float(record.velocity_x))
		record.velocity_x = _f32(float(record.velocity_x) * VELOCITY_DECAY)
		record.y = _f32(float(record.y) + float(record.velocity_y))
		record.velocity_y = _f32(float(record.velocity_y) * VELOCITY_DECAY)
		var magnitude := _f32(sqrt(absf(
			_f32(float(record.velocity_x) * float(record.velocity_y))
		)))
		if magnitude < SMOKE_MAGNITUDE_CUTOFF:
			record.active = false
		record.frame_accumulator = _f32(
			float(record.frame_accumulator) + float(record.frame_step)
		)
		record.frame = int(float(record.frame_accumulator))
		if int(record.frame) > 9:
			record.active = false


func _update_particle_pool(tick_scale: float) -> void:
	for slot in range(PARTICLE_POOL_CAPACITY):
		var record := _particle_pool[slot] as Dictionary
		if not bool(record.get("active", false)):
			continue
		record.vertical_position = _f32(
			float(record.vertical_position) + float(record.vertical_velocity) * tick_scale
		)
		record.vertical_velocity = _f32(
			float(record.vertical_velocity) - float(record.vertical_deceleration) * tick_scale
		)
		for color in ["red", "green", "blue"]:
			var value := _f32(
				float(record[color]) - float(record[color + "_decay"]) * tick_scale
			)
			record[color] = maxf(0.0, value)
		if (
			float(record.vertical_velocity) < 0.0
			or (
				float(record.red) == 0.0
				and float(record.green) == 0.0
				and float(record.blue) == 0.0
			)
		):
			record.active = false


func _update_debris_pool(tick_scale: float, rng: Variant, _context: Dictionary) -> void:
	for slot in range(DEBRIS_POOL_CAPACITY):
		var record := _debris_pool[slot] as Dictionary
		if not bool(record.get("active", false)):
			continue
		var render_type := int(record.get("render_type", 0))
		if render_type in [38, 39, 40, 41]:
			record.x = _f32(float(record.x) + float(record.velocity_x) * tick_scale)
			record.y = _f32(float(record.y) + float(record.velocity_y) * tick_scale)
			var divisor := _f32(tick_scale * SMOKE_MAGNITUDE_CUTOFF + 1.0)
			record.velocity_x = _f32(float(record.velocity_x) / divisor)
			record.velocity_y = _f32(float(record.velocity_y) / divisor)
			record.life = _f32(float(record.life) - tick_scale)
			if float(record.life) < 0.0:
				record.render_type = int(record.base_type)
				record.transitioned = true
				record.velocity_x = 0.0
				if bool(record.get("boss_bool", false)):
					record.velocity_y = _f32(1.0 + _rng_float(rng, 1.0, 6.0))
				else:
					record.velocity_y = _f32(1.0 + _rng_float(rng, 0.0, 1.0))
		# FUN_005f4210's generic branch also runs in the transition tick, so a
		# fresh velocity moves the record a second time before animation.
		record.x = _f32(float(record.x) + float(record.velocity_x) * tick_scale)
		record.y = _f32(float(record.y) + float(record.velocity_y) * tick_scale)
		record.countdown = _f32(float(record.countdown) - tick_scale)
		if float(record.countdown) < 0.0:
			record.countdown = float(record.period)
			record.frame = int(record.frame) + 1
			if int(record.frame) >= int(record.frame_count):
				record.frame = 0
		if float(record.y) > 630.0:
			record.active = false
		if float(record.x) > 900.0:
			record.x = -100.0


func _pool_snapshot(pool: Array[Dictionary], capacity: int) -> Dictionary:
	var records: Array[Dictionary] = []
	for slot in range(capacity):
		var record := pool[slot] as Dictionary
		if bool(record.get("active", false)):
			records.append(record.duplicate(true))
	return {
		"capacity": capacity,
		"active_count": records.size(),
		"records": records,
	}


func _occupied_slots_by_pool() -> Dictionary:
	return {
		"flash": _active_slot_ids(_flash_pool),
		"debris": _active_slot_ids(_debris_pool),
		"smoke": _active_slot_ids(_smoke_pool),
		"particle": _active_slot_ids(_particle_pool),
		"screen": _active_slot_ids(_screen_pool),
	}


func _active_slot_ids(pool: Array[Dictionary]) -> Array[int]:
	var slots: Array[int] = []
	for slot in range(pool.size()):
		if bool((pool[slot] as Dictionary).get("active", false)):
			slots.append(slot)
	return slots


func _allocation_delta(before: Dictionary, after: Dictionary) -> Dictionary:
	var delta := {}
	for pool_name in ["flash", "debris", "smoke", "particle", "screen"]:
		var before_slots := before.get(pool_name, []) as Array
		var added: Array[int] = []
		for slot_value in (after.get(pool_name, []) as Array):
			var slot := int(slot_value)
			if not before_slots.has(slot):
				added.append(slot)
		delta[pool_name] = added
	return delta


func _empty_pool(capacity: int) -> Array[Dictionary]:
	var pool: Array[Dictionary] = []
	for slot in range(capacity):
		pool.append({"active": false, "slot": slot})
	return pool


func _first_free(pool: Array[Dictionary]) -> int:
	for slot in range(pool.size()):
		if not bool((pool[slot] as Dictionary).get("active", false)):
			return slot
	return -1


func _require_kind(payload: Dictionary, allowed: Array[String]) -> bool:
	if allowed.has(String(payload.get("kind", ""))):
		return true
	return _set_blocked("retail effect payload kind is not valid for this call")


func _rng_int(rng: Variant, minimum: int, maximum: int) -> int:
	_root_rng_draw_count += 1
	var span := (maximum - minimum) & U32_MASK
	if span == 0:
		return minimum
	var raw := int(rng.next_u32()) & U32_MASK
	return _signed_i32((raw % span + minimum) & U32_MASK)


func _rng_float(rng: Variant, minimum: float, maximum: float) -> float:
	_root_rng_draw_count += 1
	return _f32(float(rng.next_float32(minimum, maximum)))


func _signed_i32(value: int) -> int:
	var normalized := value & U32_MASK
	return normalized - 0x100000000 if normalized >= 0x80000000 else normalized


func _is_rng_source_valid(source: Variant) -> bool:
	return source != null and source.has_method("next_u32") and source.has_method("next_float32")


func _error_result(message: String) -> Dictionary:
	_set_blocked(message)
	return {"ok": false, "error": _last_error}


func _set_blocked(message: String) -> bool:
	_blocked = true
	_last_error = message
	return false


func _set_error(message: String) -> bool:
	_last_error = message
	return false


static func _contract_value_matches(actual: Variant, expected: Variant) -> bool:
	if expected is Dictionary:
		if not actual is Dictionary:
			return false
		var actual_dictionary := actual as Dictionary
		var expected_dictionary := expected as Dictionary
		if actual_dictionary.size() != expected_dictionary.size():
			return false
		for key_value in expected_dictionary.keys():
			if (
				not actual_dictionary.has(key_value)
				or not _contract_value_matches(
					actual_dictionary[key_value],
					expected_dictionary[key_value]
				)
			):
				return false
		return true
	if expected is Array:
		if not actual is Array:
			return false
		var actual_array := actual as Array
		var expected_array := expected as Array
		if actual_array.size() != expected_array.size():
			return false
		for index in range(expected_array.size()):
			if not _contract_value_matches(actual_array[index], expected_array[index]):
				return false
		return true
	match typeof(expected):
		TYPE_INT, TYPE_FLOAT:
			return typeof(actual) in [TYPE_INT, TYPE_FLOAT] and float(actual) == float(expected)
		TYPE_BOOL:
			return typeof(actual) == TYPE_BOOL and bool(actual) == bool(expected)
		TYPE_STRING, TYPE_STRING_NAME:
			return typeof(actual) in [TYPE_STRING, TYPE_STRING_NAME] and str(actual) == str(expected)
		_:
			return actual == expected


static func _f32(value: float) -> float:
	var storage := PackedFloat32Array([value])
	return float(storage[0])

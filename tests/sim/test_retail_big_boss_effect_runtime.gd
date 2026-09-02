extends SceneTree

const Effects := preload("res://src/sim/retail_big_boss_effect_runtime.gd")

var _failures: Array[String] = []


class ScriptedRng extends RefCounted:
	var raw_values: Array[int] = []
	var float_values: Array[float] = []
	var calls: Array = []

	func _init(raws: Array[int] = [], floats: Array[float] = []) -> void:
		raw_values = raws.duplicate()
		float_values = floats.duplicate()

	func next_u32() -> int:
		calls.append(["u32"])
		if raw_values.is_empty():
			return 0
		return int(raw_values.pop_front())

	func next_float32(minimum: float, maximum: float) -> float:
		calls.append(["float", minimum, maximum])
		if float_values.is_empty():
			return minimum
		return float(float_values.pop_front())

	func snapshot() -> Dictionary:
		return {"calls": calls.duplicate(true)}


func _initialize() -> void:
	_test_contract_is_pinned_and_fail_closed()
	_test_flash_pool_capacity_draw_order_and_lifetime()
	_test_rank_ready_small_explosion_rng_branches()
	_test_only_blue_coins_debris_rng_and_transition()
	_test_terminal_hit_smoke_semantics()
	_test_large_burst_pool_order_and_particle_bounds()
	if _failures.is_empty():
		print("RETAIL BIG BOSS EFFECT RUNTIME TESTS PASSED")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _test_contract_is_pinned_and_fail_closed() -> void:
	var contract := Effects.retail_contract()
	_expect(
		String(contract.executable_sha256)
		== "ddf1778c307af1087ff9dcb512786111e665d972298aeaac3f1b4b2996d079ef",
		"the effect contract must pin the audited WarBlade 1.34 executable"
	)
	_expect(
		contract.preset == {
			"id": "retail_high",
			"high_effects": true,
			"particle_density": 100,
			"evidence": "0x005bab12/0x005bab3a",
		},
		"authoritative effects must pin retail's high/100 preset"
	)
	_expect(
		int(contract.pools.flash.capacity) == 50
		and int(contract.pools.debris.capacity) == 150
		and int(contract.pools.smoke.capacity) == 500
		and int(contract.pools.particle.capacity) == 1000
		and int(contract.pools.screen.capacity) == 4,
		"all five executable effect pool capacities must be explicit"
	)
	var invalid := Effects.new()
	var invalid_contract := contract.duplicate(true)
	invalid_contract.preset.particle_density = 150
	_expect(
		not invalid.configure(invalid_contract),
		"the effect runtime must reject a client-selected particle preset"
	)
	invalid = Effects.new()
	invalid_contract = contract.duplicate(true)
	invalid_contract.exact_trace_complete = false
	_expect(
		not invalid.configure(invalid_contract),
		"the effect runtime must reject an unresolved executable trace"
	)
	var catalog_runtime := Effects.new()
	_expect(
		catalog_runtime.configure(_effect_catalog_contract()),
		"the effect runtime must accept its generated JSON contract with normalized numbers"
	)


func _test_flash_pool_capacity_draw_order_and_lifetime() -> void:
	var effects: Variant = _configured_runtime()
	var rng := ScriptedRng.new()
	for index in range(Effects.FLASH_POOL_CAPACITY):
		var result: Dictionary = effects.dispatch_retail_effect("FUN_005dfee0", {
			"kind": "boss_hit",
			"x": float(index),
			"y": 20.0,
		}, rng)
		_expect(
			bool(result.ok)
			and int(result.rng_draws) == 1
			and int(result.frame_period) == 0
			and _allocation_count(result, "flash") == 1,
			"each successful FUN_005dfee0 allocation must consume one period draw"
		)
	var full_result: Dictionary = effects.dispatch_retail_effect("FUN_005dfee0", {
		"kind": "boss_hit",
		"x": 0.0,
		"y": 0.0,
	}, rng)
	_expect(
		int(full_result.rng_draws) == 0
		and int(full_result.allocated_count) == 0
		and int(effects.snapshot().pools.flash.active_count) == 50,
		"a full 50-record flash pool must return before consuming RNG"
	)
	for frame in range(12):
		effects.step(1.0, rng)
	_expect(
		int(effects.snapshot().pools.flash.active_count) == 50,
		"type-10 hit flashes must remain active through frame 12"
	)
	effects.step(1.0, rng)
	_expect(
		int(effects.snapshot().pools.flash.active_count) == 0,
		"period-zero type-10 hit flashes must clear when the frame becomes 13"
	)
	var slow_effects: Variant = _configured_runtime()
	var slow_rng := ScriptedRng.new([1])
	var slow_result: Dictionary = slow_effects.dispatch_retail_effect("FUN_005dfee0", {
		"kind": "boss_hit",
		"x": 10.0,
		"y": 20.0,
	}, slow_rng)
	_expect(
		bool(slow_result.ok)
		and int(slow_result.frame_period) == 1
		and int(slow_result.allocated_count) == 1,
		"the upper RNG residue must retain the exact period-one type-10 allocation"
	)
	slow_effects.step(1.0, slow_rng)
	_expect(
		int(_first_record(slow_effects, "flash").frame) == 0,
		"period one must retain frame zero for the first effect update"
	)
	slow_effects.step(1.0, slow_rng)
	_expect(
		int(_first_record(slow_effects, "flash").frame) == 1,
		"period one must advance on the second effect update"
	)
	for _frame in range(23):
		slow_effects.step(1.0, slow_rng)
	_expect(
		int(slow_effects.snapshot().pools.flash.active_count) == 1
		and int(_first_record(slow_effects, "flash").frame) == 12,
		"period-one type-10 flashes must retain frame twelve through update 25"
	)
	slow_effects.step(1.0, slow_rng)
	_expect(
		int(slow_effects.snapshot().pools.flash.active_count) == 0,
		"period-one type-10 flashes must clear on update 26"
	)


func _test_rank_ready_small_explosion_rng_branches() -> void:
	var effects: Variant = _configured_runtime()
	var plain_rng := ScriptedRng.new([5])
	var plain: Dictionary = effects.dispatch_retail_effect("FUN_00570420", {
		"kind": "boss_death_small_explosion",
		"x": 10.0,
		"y": 20.0,
		"rank_ready": false,
	}, plain_rng)
	var record := _first_record(effects, "debris")
	_expect(
		int(plain.rng_draws) == 1
		and int(record.variant) == 5
		and float(record.x) == 32.0
		and int(record.render_type) == 53,
		"rank-ready false must consume only RngInt(0,6) and preserve the +22 x offset"
	)

	effects = _configured_runtime()
	var ready_common_rng := ScriptedRng.new([1, 5])
	var ready_common: Dictionary = effects.dispatch_retail_effect("FUN_00570420", {
		"kind": "boss_death_small_explosion",
		"x": 10.0,
		"y": 20.0,
		"rank_ready": true,
	}, ready_common_rng)
	_expect(
		int(ready_common.rng_draws) == 2
		and int(_first_record(effects, "debris").variant) == 5,
		"rank-ready true must consume the eligibility draw before the common bound-six draw"
	)

	effects = _configured_runtime()
	var ready_rare_rng := ScriptedRng.new([0, 6])
	var ready_rare: Dictionary = effects.dispatch_retail_effect("FUN_00570420", {
		"kind": "boss_death_small_explosion",
		"x": 10.0,
		"y": 20.0,
		"rank_ready": true,
	}, ready_rare_rng)
	record = _first_record(effects, "debris")
	_expect(
		int(ready_rare.rng_draws) == 2
		and int(record.variant) == 6
		and int(record.render_type) == 64
		and float(record.velocity_y) == 10.0,
		"eligibility roll zero must expand the second draw to bound seven and admit variant six"
	)

	effects = _configured_runtime()
	var missing_flag: Dictionary = effects.dispatch_retail_effect("FUN_00570420", {
		"kind": "boss_death_small_explosion",
		"x": 0.0,
		"y": 0.0,
	}, ScriptedRng.new())
	_expect(
		not bool(missing_flag.ok) and bool(effects.snapshot().blocked),
		"FUN_00570420 must fail closed instead of guessing the killer's rank-ready flag"
	)


func _test_only_blue_coins_debris_rng_and_transition() -> void:
	var effects: Variant = _configured_runtime()
	var ordinary_rng := ScriptedRng.new()
	var ordinary: Dictionary = effects.dispatch_retail_effect("FUN_00571080", {
		"kind": "boss_death_flash",
		"x": 0.0,
		"y": 0.0,
		"flags": [1, 1],
		"only_blue_coins_active": false,
	}, ordinary_rng)
	var ordinary_first := _first_record(effects, "debris")
	_expect(
		int(ordinary.rng_draws) == 79
		and _allocation_count(ordinary, "debris") == 18
		and int(ordinary_first.base_type) == 29
		and int(ordinary_first.render_type) == 38,
		"clean progression must allocate 18 debris records and consume each type-selection draw"
	)
	effects = _configured_runtime()
	var blue_rng := ScriptedRng.new()
	var forced: Dictionary = effects.dispatch_retail_effect("FUN_00571080", {
		"kind": "boss_death_flash",
		"x": 0.0,
		"y": 0.0,
		"flags": [1, 1],
		"only_blue_coins_active": true,
	}, blue_rng)
	var forced_first := _first_record(effects, "debris")
	_expect(
		int(forced.rng_draws) == 61
		and _allocation_count(forced, "debris") == 18
		and int(forced_first.base_type) == 32
		and int(forced_first.render_type) == 41,
		"only-blue-coins mode must force type 32 and skip exactly 18 type-selection draws"
	)
	effects.step(11.0, blue_rng)
	forced_first = _first_record(effects, "debris")
	_expect(
		bool(forced_first.transitioned)
		and int(forced_first.render_type) == 32
		and float(forced_first.y) == 44.0
		and float(forced_first.velocity_y) == 2.0
		and int(effects.snapshot().root_rng_draw_count) == 79,
		"life expiry must use the boss fall-speed draw and run the generic movement in the same tick"
	)


func _test_terminal_hit_smoke_semantics() -> void:
	var effects: Variant = _configured_runtime()
	var rng := ScriptedRng.new()
	var terminal: Dictionary = effects.dispatch_retail_effect("FUN_005defe0", {
		"kind": "boss_terminal_hit_smoke",
		"x": 128.0,
		"y": 64.0,
		"count": 10,
	}, rng)
	_expect(
		bool(terminal.ok)
		and int(terminal.rng_draws) == 80
		and _allocation_count(terminal, "smoke") == 10,
		"strict-negative terminal smoke must allocate the traced ten-record minimum"
	)

	var legacy: Variant = _configured_runtime()
	var rejected: Dictionary = legacy.dispatch_retail_effect("FUN_005defe0", {
		"kind": "boss_low_health_smoke",
		"x": 128.0,
		"y": 64.0,
		"count": 10,
	}, ScriptedRng.new())
	_expect(
		not bool(rejected.ok) and bool(legacy.snapshot().blocked),
		"the effect runtime must reject the disproven positive low-health semantic"
	)


func _test_large_burst_pool_order_and_particle_bounds() -> void:
	var effects: Variant = _configured_runtime()
	var rng := ScriptedRng.new()
	var left: Dictionary = effects.dispatch_retail_effect("FUN_005e0650", {
		"kind": "boss_death_burst_left",
		"x": 0.0,
		"y": 0.0,
		"size": [256, 128],
		"palette": [255, 200, 255],
		"variant": 1,
	}, rng)
	_expect(
		int(left.rng_draws) == 1802
		and _allocation_count(left, "screen") == 1
		and _allocation_count(left, "flash") == 1
		and _allocation_count(left, "smoke") == 300
		and int(left.allocated_count) == 302,
		"the first large burst must allocate screen, flash, then 300 high-preset smoke records"
	)
	var first_smoke := _first_record(effects, "smoke")
	_expect(
		float(first_smoke.x) == 128.0
		and float(first_smoke.y) == 64.0
		and float(first_smoke.velocity_x) == 0.0
		and float(first_smoke.velocity_y) == 2.0,
		"smoke angle zero must use the executable's sin-x/cos-y tables around the burst center"
	)
	var right: Dictionary = effects.dispatch_retail_effect("FUN_005e0650", {
		"kind": "boss_death_burst_right",
		"x": 0.0,
		"y": -32.0,
		"size": [256, 128],
		"palette": [255, 0, 0],
		"variant": 0,
	}, rng)
	_expect(
		int(right.rng_draws) == 1202
		and _allocation_count(right, "screen") == 0
		and _allocation_count(right, "flash") == 1
		and _allocation_count(right, "smoke") == 200
		and int(effects.snapshot().pools.smoke.active_count) == 500,
		"the second burst must stop at the remaining 200 smoke slots without extra RNG"
	)
	var full_smoke: Dictionary = effects.dispatch_retail_effect("FUN_005defe0", {
		"kind": "boss_death_smoke",
		"x": 0.0,
		"y": 0.0,
		"count": 50,
	}, rng)
	_expect(
		int(full_smoke.rng_draws) == 0 and int(full_smoke.allocated_count) == 0,
		"a full smoke pool must suppress every per-record draw"
	)
	var particles: Dictionary = effects.dispatch_retail_effect("FUN_0052f440", {
		"kind": "boss_death_particles",
		"x": 128.0,
		"y": 64.0,
		"count": 500,
		"palette": [100, 255, 100],
	}, rng)
	_expect(
		int(particles.rng_draws) == 2007
		and _allocation_count(particles, "particle") == 501
		and int(effects.snapshot().pools.particle.active_count) == 501,
		"FUN_0052f440 must take three upfront draws and perform count+1 allocations"
	)
	effects.step(1.0, rng)
	var first_particle := _first_record(effects, "particle")
	_expect(
		float(first_particle.vertical_position) == 3.0
		and is_equal_approx(float(first_particle.vertical_velocity), 1.9900000095367432),
		"new particles must receive the executable's same-tick position and deceleration update"
	)
	effects.reset()
	var reset_snapshot: Dictionary = effects.snapshot()
	_expect(
		int(reset_snapshot.root_rng_draw_count) == 0
		and int(reset_snapshot.pools.flash.active_count) == 0
		and int(reset_snapshot.pools.debris.active_count) == 0
		and int(reset_snapshot.pools.smoke.active_count) == 0
		and int(reset_snapshot.pools.particle.active_count) == 0
		and int(reset_snapshot.pools.screen.active_count) == 0,
		"level/session reset must clear all five retail pools and their RNG counter"
	)


func _configured_runtime() -> Variant:
	var effects := Effects.new()
	_expect(
		effects.configure(Effects.retail_contract()),
		"the pinned effect contract should configure"
	)
	return effects


func _effect_catalog_contract() -> Dictionary:
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://content/bosses.json")
	)
	if not parsed is Dictionary:
		return {}
	var boss_contract := (((parsed as Dictionary).get("bosses", {}) as Dictionary).get(
		"retail_big_boss_v1",
		{}
	) as Dictionary)
	return (boss_contract.get("effect_runtime", {}) as Dictionary).duplicate(true)


func _allocation_count(result: Dictionary, pool_name: String) -> int:
	return ((result.get("allocations", {}) as Dictionary).get(pool_name, []) as Array).size()


func _first_record(effects: Variant, pool_name: String) -> Dictionary:
	var records := ((effects.snapshot().pools as Dictionary)[pool_name] as Dictionary).records as Array
	if records.is_empty():
		return {}
	return records[0] as Dictionary


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

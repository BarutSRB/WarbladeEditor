extends SceneTree

const MeteorStorm := preload("res://src/sim/meteor_storm_simulation.gd")
const Rng := preload("res://src/sim/deterministic_rng.gd")

var _failures: Array[String] = []


class ScriptedRng extends RefCounted:
	var range_values: Array[int] = []
	var float_values: Array[float] = []
	var calls: Array = []

	func _init(ranges: Array[int], floats: Array[float]) -> void:
		range_values = ranges.duplicate()
		float_values = floats.duplicate()

	func next_range(upper_exclusive: int) -> int:
		calls.append(["range", upper_exclusive])
		if range_values.is_empty():
			return 0
		return int(range_values.pop_front()) % upper_exclusive

	func next_float32(minimum: float, maximum: float) -> float:
		calls.append(["float", minimum, maximum])
		if float_values.is_empty():
			return minimum
		return float(float_values.pop_front())

	func snapshot() -> Dictionary:
		return {"calls": calls.duplicate(true)}


class CollisionProbe extends RefCounted:
	var should_hit: bool = true
	var calls: Array[Dictionary] = []

	func query(payload: Dictionary) -> bool:
		calls.append(payload.duplicate(true))
		return should_hit


func _initialize() -> void:
	_test_contract_and_executable_tables()
	_test_spawn_rng_order_and_source_frames()
	_test_intro_pool_countdown_and_strict_activation()
	_test_meteor_flyby_audio_boundary()
	_test_acceleration_deceleration_distance_and_score()
	_test_drunk_controls_and_secret_override()
	_test_collision_hook_bonus_gem_and_failure()
	_test_gem_drop_progress_and_audio_order()
	_test_secret_meteor_collision_roll()
	_test_bonus_selection_bias_boundaries()
	_test_success_reward_tiers_and_drunk_rewards()
	_test_ordered_state_and_deterministic_replay()
	_test_parent_state_is_frozen()
	if _failures.is_empty():
		print("METEOR STORM TESTS PASSED")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _test_contract_and_executable_tables() -> void:
	var contract := MeteorStorm.retail_contract()
	_expect(
		String(contract.executable_sha256)
		== "ddf1778c307af1087ff9dcb512786111e665d972298aeaac3f1b4b2996d079ef",
		"Meteor Storm must pin the audited WarBlade 1.34 executable"
	)
	_expect(
		MeteorStorm.METEOR_SOURCE_X.size() == 45
		and MeteorStorm.METEOR_SOURCE_Y.size() == 45
		and MeteorStorm.METEOR_WIDTH.size() == 45
		and MeteorStorm.METEOR_HEIGHT.size() == 45,
		"all four executable meteor-frame tables must contain exactly 45 entries"
	)
	_expect(
		MeteorStorm.METEOR_SOURCE_X[44] == 0
		and MeteorStorm.METEOR_SOURCE_Y[44] == 616
		and MeteorStorm.METEOR_WIDTH[44] == 144
		and MeteorStorm.METEOR_HEIGHT[44] == 99,
		"the final half-open meteor frame must not consume the adjacent 46th table value"
	)
	var invalid := MeteorStorm.new()
	var invalid_contract := contract.duplicate(true)
	invalid_contract.executable_sha256 = "wrong-build"
	_expect(
		not invalid.configure(invalid_contract),
		"configure should reject constants attributed to a different executable"
	)
	_expect(
		String(contract.evidence.meter_distance_divisor).contains("455.0"),
		"the render contract should retain the executable-pinned 455px meter divisor"
	)


func _test_spawn_rng_order_and_source_frames() -> void:
	var ordinary_rng := ScriptedRng.new(
		[50, 3],
		[-10.0, -300.0, 0.25, 2.5]
	)
	var ordinary := _fixture_with_rng(ordinary_rng)
	ordinary.step(1, 0, 0)
	var ordinary_slot: Dictionary = ordinary.snapshot().slots[0]
	_expect(
		ordinary_rng.calls == [
			["range", 99],
			["range", 45],
			["float", -30.0, 800.0],
			["float", -700.0, -200.0],
			["float", -0.30000001192092896, 0.30000001192092896],
			["float", 1.0, 4.0],
		],
		"ordinary meteor spawn must preserve the executable's six-draw order"
	)
	_expect(
		String(ordinary_slot.kind) == "meteor"
		and int(ordinary_slot.frame_index) == 3
		and ordinary_slot.source_rect == [96, 0, 32, 28]
		and int(ordinary_slot.x_fp) == -10 * MeteorStorm.FP_ONE
		and int(ordinary_slot.y_fp) == -300 * MeteorStorm.FP_ONE,
		"ordinary spawn should use the selected meteor atlas frame and top-left coordinates"
	)

	var gem_rng := ScriptedRng.new([0, 0, 2], [12.0, -250.0, 0.0, 1.0])
	var gem := _fixture_with_rng(gem_rng)
	gem.step(1, 0, 0)
	var gem_slot: Dictionary = gem.snapshot().slots[0]
	_expect(
		String(gem_slot.kind) == "gem"
		and int(gem_slot.frame_index) == 2
		and gem_slot.source_rect == [160, 0, 80, 51]
		and String(gem_slot.collision_mask) == "diamantbig"
		and gem_rng.calls.size() == 7,
		"gem spawn should consume three integer and four float draws"
	)

	var bonus_rng := ScriptedRng.new([0, 98, 358], [0.0, -220.0, 0.0, 1.0])
	var bonus := _fixture_with_rng(bonus_rng)
	bonus.step(1, 0, 0)
	var bonus_slot: Dictionary = bonus.snapshot().slots[0]
	_expect(
		String(bonus_slot.kind) == "bonus"
		and int(bonus_slot.frame_index) == 5
		and bonus_slot.source_rect == [320, 0, 64, 37]
		and String(bonus_slot.collision_mask) == "meteorbonuses"
		and bonus_rng.calls.size() == 7,
		"bonus spawn should use the biased 0..358 selection draw before four floats"
	)


func _test_intro_pool_countdown_and_strict_activation() -> void:
	var simulation := _fixture(2)
	var entered: Dictionary = simulation.get_meta("test_enter_result", {})
	_expect(
		_event_kinds(entered.events).slice(0, 3) == [
			"meteor_storm_entered", "music_cue", "voice_cue",
		],
		"entry should return deterministic start, music, and rank-0 voice cues"
	)
	_expect(
		int(entered.events[2].queue_padding_ms) == 50,
		"Meteor entry announcement should retain its recovered 50-ms queue padding"
	)
	var first: Dictionary = simulation.step(1, 0, 0)
	_expect(
		_event_kinds(first.events).is_empty(),
		"entry cues must not be replayed by the first simulation step"
	)
	var initial_y := int(first.snapshot.slots[0].y_fp)
	for tick in range(2, 21):
		simulation.step(tick, tick, 0)
	var filled := simulation.snapshot()
	_expect(
		int(filled.counted_active_slots) == 20
		and _active_slot_count(filled.slots) == 20,
		"intro updates should fill one slot per update to the retail target of 20"
	)
	_expect(
		int(filled.slots[0].y_fp) == initial_y,
		"spawned objects must remain stationary throughout the intro"
	)

	var equality_three: Dictionary = simulation.step(21, 2000, 0)
	_expect(
		not _event_kinds(equality_three.events).has("countdown_cue"),
		"three cue should not fire at the exact 2000ms remaining equality"
	)
	var three: Dictionary = simulation.step(22, 2001, 0)
	_expect(_countdown_values(three.events) == [3], "three cue should fire below 2000ms")
	var equality_two: Dictionary = simulation.step(23, 3000, 0)
	_expect(_countdown_values(equality_two.events).is_empty(), "two cue uses a strict 1000ms bound")
	var two: Dictionary = simulation.step(24, 3001, 0)
	_expect(_countdown_values(two.events) == [2], "two cue should fire below 1000ms")
	var equality_one: Dictionary = simulation.step(25, 3990, 0)
	_expect(_countdown_values(equality_one.events).is_empty(), "one cue uses a strict 10ms bound")
	var one: Dictionary = simulation.step(26, 3991, 0)
	_expect(_countdown_values(one.events) == [1], "one cue should fire below 10ms")
	var intro_equality: Dictionary = simulation.step(27, 4000, MeteorStorm.ACTION_FIRE)
	_expect(
		String(intro_equality.snapshot.stage) == "intro"
		and int(intro_equality.snapshot.speed_fp) == 0,
		"gameplay must remain suspended at exact intro deadline equality"
	)
	var activated: Dictionary = simulation.step(28, 4001, MeteorStorm.ACTION_FIRE)
	_expect(
		String(activated.snapshot.stage) == "active"
		and int(activated.snapshot.slots[0].y_fp) != initial_y,
		"entities should begin moving only after the strict intro boundary"
	)


func _test_acceleration_deceleration_distance_and_score() -> void:
	var simulation := _fixture(3)
	simulation._intro_until_ms = 0
	simulation._counted_active_slots = 20
	var accelerated: Dictionary = simulation.step(1, 1, MeteorStorm.ACTION_FIRE)
	_expect(
		is_equal_approx(float(accelerated.snapshot.speed), 0.10000000149011612),
		"holding Fire should add one float32 0.1 accelerator step"
	)
	_expect(
		is_equal_approx(float(accelerated.snapshot.base_scroll), 1.5011999607086182),
		"active updates should grow base scroll by the pinned float32 increment"
	)
	_expect(
		int(accelerated.score_delta) == 10
		and int(accelerated.profile_deltas.meteor_score) == 10,
		"each active update should award (trunc(speed/15*50)+1)*10"
	)
	var expected_distance := _f32(14000.0 - _f32(_f32(0.10000000149011612 / 2.0) + 3.0))
	_expect(
		is_equal_approx(
			float(accelerated.snapshot.distance_fp) / MeteorStorm.FP_ONE,
			expected_distance
		),
		"distance should consume (speed/2+3) with retail float32 stores"
	)
	var released: Dictionary = simulation.step(2, 2, 0)
	_expect(
		int(released.snapshot.speed_fp) == 0
		and bool(released.snapshot.accelerator_released),
		"releasing from 0.1 should decelerate by 0.18, clamp at zero, and latch release"
	)


func _test_drunk_controls_and_secret_override() -> void:
	var drunk := _fixture(4, {"drunk_ticks": 10})
	drunk.step(1, 0, MeteorStorm.ACTION_LEFT)
	_expect(
		int(drunk.snapshot().ship.x_fp) == 404 * MeteorStorm.FP_ONE,
		"Drunk should reverse horizontal movement"
	)
	_expect(
		int(drunk.snapshot().drunk_ticks_remaining) == 9,
		"controller snapshot should expose the decremented Drunk timer for restoration"
	)
	var secret := _fixture(4, {"drunk_ticks": 10, "secret_drunk_meteor": true})
	secret.step(1, 0, MeteorStorm.ACTION_LEFT)
	_expect(
		int(secret.snapshot().ship.x_fp) == 396 * MeteorStorm.FP_ONE,
		"secret Drunk Meteor should disable the Drunk direction reversal"
	)


func _test_collision_hook_bonus_gem_and_failure() -> void:
	var bonus_probe := CollisionProbe.new()
	var bonus := _fixture(5, {"money": 99980, "max_money": 99990}, bonus_probe)
	_prepare_collision_slot(bonus, "bonus", 1)
	var bonus_result: Dictionary = bonus.step(1, 1, 0)
	_expect(
		int(bonus_result.cash_delta) == 10
		and int(bonus_result.profile_deltas.money) == 10,
		"bonus cash should clamp authoritatively at the profile maximum"
	)
	_expect(
		bonus_probe.calls.size() == 1
		and String(bonus_probe.calls[0].slot_mask_id) == "meteorbonuses"
		and String(bonus_probe.calls[0].fighter_mask_id) == "fighter1",
		"collision hook should receive exact slot and fighter HMA identifiers"
	)
	_expect(
		_has_sound_event(bonus_result.events, "bing"),
		"Meteor bonus pickup should emit its executable-traced bing cue"
	)

	var gem_probe := CollisionProbe.new()
	var gem := _fixture(6, {"score_multiplier": 2}, gem_probe)
	_prepare_collision_slot(gem, "gem", 2)
	var gem_result: Dictionary = gem.step(1, 1, 0)
	_expect(
		int(gem_result.profile_deltas.gem_count) == 5
		and int(gem_result.score_delta) == 20020,
		"gem frame 2 should award 10,000 times multiplier, five gems, and active-tick score"
	)

	var meteor_probe := CollisionProbe.new()
	var meteor := _fixture(7, {"meteor_streak": 4, "fighter_frame_index": 5}, meteor_probe)
	_prepare_collision_slot(meteor, "meteor", 0)
	var failed: Dictionary = meteor.step(1, 1, 0)
	_expect(
		bool(failed.complete)
		and String(failed.outcome) == "failure"
		and int(failed.profile_deltas.meteor_streak) == -4,
		"an HMA-confirmed ordinary meteor hit should fail and clear the streak"
	)
	_expect(
		meteor_probe.calls[0].fighter_source_rect == [200, 0, 40, 27]
		and meteor_probe.calls[0].fighter_destination_rect == [380, 550, 40, 27],
		"collision payload should expose the exact current fighter frame and retail 40x27 rect"
	)
	_expect(
		meteor.snapshot().ship.render_source_rect == [200, 0, 40, 28]
		and int(meteor.snapshot().ship.height) == 28,
		"presentation should retain the fighter's full 40x28 raster independently of its 40x27 HMA"
	)
	_expect(
		_event_kinds(failed.events).has("meteor_storm_failed")
		and not _event_kinds(failed.events).has("music_cue")
		and _has_sound_event(failed.events, "thumpbig", 30000),
		"failure should play thumpbig without stopping Meteor music during the result hold"
	)


func _test_meteor_flyby_audio_boundary() -> void:
	var simulation := _fixture(71)
	simulation._intro_until_ms = 0
	simulation._active_target = 1.0
	simulation._counted_active_slots = 1
	for slot_value in simulation._slots:
		(slot_value as Dictionary).active = false
	var slot: Dictionary = simulation._slots[0]
	slot.active = true
	slot.kind = "meteor"
	slot.source_rect = [0, 0, 64, 53]
	slot.collision_mask = "meteors"
	slot.texture_id = "meteors"
	slot.x = 123.0
	slot.y = -40.0
	slot.velocity_x = 0.0
	slot.velocity_y = 0.0
	slot.flyby_volume_index = 87
	slot.spawn_serial = 88
	var result: Dictionary = simulation.step(1, 1, 0)
	var flyby_events: Array = result.events.filter(
		func(event: Dictionary) -> bool:
			return String(event.kind) == "sound_cue" and String(event.key) == "meteorpass"
	)
	_expect(
		flyby_events.size() == 1
		and int(flyby_events[0].frequency_hz) == 15000
		and int(flyby_events[0].volume_index) == 87
		and int(flyby_events[0].x_fp) == 123 * MeteorStorm.FP_ONE,
		"a normal meteor crossing downward from exact -40 should emit the spatial 15-kHz flyby cue"
	)


func _test_gem_drop_progress_and_audio_order() -> void:
	var probe := CollisionProbe.new()
	var rng := ScriptedRng.new([2345], [])
	var ordinary := _fixture_with_rng(rng, {
		"gem_progress_origin": 452,
		"gem_progress": 452 + 98 * 8,
		"gem_progress_step": 8,
	}, probe)
	_prepare_collision_slot(ordinary, "gem", 0)
	var result: Dictionary = ordinary.step(1, 1, 0)
	var started := _first_event(result.events, "meteor_gem_drop_started")
	var bell := _first_sound_event(result.events, "bell1")
	_expect(
		int(result.profile_deltas.get("gem_progress", 0)) == 5 * 8
		and int(result.snapshot.gem_progress) == 452 + 103 * 8
		and not started.is_empty()
		and not bool(started.get("super_gem_drop", true))
		and int(started.get("transition_ms", 0)) == 4000,
		"five shared progress increments crossing quotient 100 should start an ordinary four-second Gem Drop"
	)
	_expect(
		_voice_keys(result.events) == ["gemdrop", "bonus"]
		and bool(_first_voice_event(result.events, "gemdrop").get("drop_if_voice_busy", false))
		and bool(_first_voice_event(result.events, "bonus").get("drop_if_voice_busy", false))
		and int(_first_voice_event(result.events, "gemdrop").get("queue_padding_ms", 0)) == 50
		and int(_first_voice_event(result.events, "bonus").get("queue_padding_ms", 0)) == 50,
		"Gem Drop should attempt tag-0 gemdrop before the same-tick generic bonus voice"
	)
	_expect(
		rng.calls == [["range", 10000]]
		and int(bell.get("frequency_hz", 0)) == 24345
		and int(bell.get("source_hz", 0)) == 32000
		and int(bell.get("volume_index", 0)) == 255,
		"every gem pickup should consume one 22000..31999 bell-frequency draw after both voice attempts"
	)

	var super_probe := CollisionProbe.new()
	var super_rng := ScriptedRng.new([9999], [])
	var super_drop := _fixture_with_rng(super_rng, {
		"gem_progress_origin": 452,
		"gem_progress": 452 + 998 * 8,
		"gem_progress_step": 8,
	}, super_probe)
	_prepare_collision_slot(super_drop, "gem", 2)
	var super_result: Dictionary = super_drop.step(1, 1, 0)
	var super_started := _first_event(super_result.events, "meteor_gem_drop_started")
	_expect(
		bool(super_started.get("super_gem_drop", false))
		and int(super_result.snapshot.gem_progress) == 452 + 3 * 8
		and int(super_result.profile_deltas.get("gem_progress", 0)) == -995 * 8
		and int(_first_sound_event(super_result.events, "bell1").get("frequency_hz", 0)) == 31999,
		"quotient 1000 should wrap exactly one thousand progress steps and mark Super Gem Drop"
	)
func _test_secret_meteor_collision_roll() -> void:
	var evade_rng := ScriptedRng.new([991], [])
	var evade_probe := CollisionProbe.new()
	var evade := _fixture_with_rng(
		evade_rng,
		{"secret_drunk_meteor": true},
		evade_probe
	)
	_prepare_collision_slot(evade, "meteor", 0)
	var evaded: Dictionary = evade.step(1, 1, 0)
	_expect(
		not bool(evaded.complete)
		and evade_rng.calls == [["range", 1000]]
		and _event_kinds(evaded.events).has("meteor_secret_evade"),
		"secret collision rolls 0..991 should consume one draw and evade"
	)

	var crash_rng := ScriptedRng.new([992], [])
	var crash_probe := CollisionProbe.new()
	var crash := _fixture_with_rng(
		crash_rng,
		{"secret_drunk_meteor": true},
		crash_probe
	)
	_prepare_collision_slot(crash, "meteor", 0)
	var crashed: Dictionary = crash.step(1, 1, 0)
	_expect(
		bool(crashed.complete) and String(crashed.outcome) == "failure",
		"secret collision rolls 992..999 should retain the retail crash path"
	)


func _test_bonus_selection_bias_boundaries() -> void:
	var simulation := MeteorStorm.new()
	var cases := {
		0: 0, 50: 0,
		51: 1, 80: 1,
		81: 2, 90: 2,
		91: 3, 240: 3,
		241: 4, 320: 4,
		321: 5, 358: 5,
	}
	for draw_value in cases:
		_expect(
			simulation._select_bonus_index(int(draw_value)) == int(cases[draw_value]),
			"bonus draw %d should retain the executable's strict weighted boundary" % draw_value
		)


func _test_success_reward_tiers_and_drunk_rewards() -> void:
	var cases := [
		{"low": 10, "high": 0, "tier": "below_90", "score": 1000000, "cash": 0},
		{"low": 10, "high": 99, "tier": "at_least_90", "score": 2000000, "cash": 1000},
		{"low": 50, "high": 10000, "tier": "at_least_99", "score": 5000000, "cash": 5000},
		{"low": 0, "high": 1, "tier": "perfect", "score": 10000000, "cash": 25000},
	]
	for case_value in cases:
		var case: Dictionary = case_value
		var simulation := _fixture(20 + int(case.low))
		_prepare_success(simulation, int(case.low), int(case.high))
		var result: Dictionary = simulation.step(1, 1, MeteorStorm.ACTION_FIRE)
		_expect(
			String(result.completion.tier) == String(case.tier)
			and int(result.completion.score_reward) == int(case.score)
			and int(result.completion.cash_reward) == int(case.cash),
			"tier %s should use the executable-pinned normal reward" % String(case.tier)
		)
		_expect(
			int(result.profile_deltas.meteor_distance) == 134,
			"successful Meteor Storm should add the retail distance increment"
		)
		_expect(
			int(result.completion.retail_transition_ms) == 3000,
			"terminal result should request the strict retail three-second parent hold"
		)

	var drunk := _fixture(30, {"drunk_ticks": 100})
	_prepare_success(drunk, 0, 1)
	var drunk_result: Dictionary = drunk.step(1, 1, MeteorStorm.ACTION_FIRE)
	_expect(
		String(drunk_result.completion.tier) == "perfect"
		and bool(drunk_result.completion.drunk_reward)
		and int(drunk_result.completion.score_reward) == 20000000
		and int(drunk_result.completion.cash_reward) == 50000,
		"active Drunk should switch perfect completion to the doubled reward table"
	)


func _test_ordered_state_and_deterministic_replay() -> void:
	var first := _fixture(41)
	var second := _fixture(41)
	for tick in range(1, 121):
		var now_ms := tick * 50
		var action := 0
		if tick % 7 < 5:
			action |= MeteorStorm.ACTION_FIRE
		if tick % 11 < 4:
			action |= MeteorStorm.ACTION_LEFT
		elif tick % 11 > 8:
			action |= MeteorStorm.ACTION_RIGHT
		var first_result: Dictionary = first.step(tick, now_ms, action)
		var second_result: Dictionary = second.step(tick, now_ms, action)
		_expect(
			first_result == second_result,
			"same seed and action stream should produce identical result at tick %d" % tick
		)
		_expect(
			first.state_for_hash() == second.state_for_hash(),
			"same seed and action stream should produce identical hash state at tick %d" % tick
		)
	var state := first.state_for_hash()
	var slot_ids: Array[int] = []
	for slot_value in state.slots:
		slot_ids.append(int((slot_value as Dictionary).slot_id))
	_expect(
		slot_ids == range(30),
		"hash state must serialize all 30 slots in stable slot-id order"
	)
	_expect(
		int(state.rng_draws_since_enter) > 0
		and int(state.rng.draw_count) == int(state.rng_draws_since_enter),
		"hash state should include the shared generator state and exact local draw count"
	)


func _test_parent_state_is_frozen() -> void:
	var parent_state := {
		"combat_tick": 900,
		"enemies": [{"id": 1, "x_fp": 1234}],
		"projectiles": [{"id": 9, "velocity_y_fp": -999}],
	}
	var frozen_copy := parent_state.duplicate(true)
	var parent_hash := {"fnv64": "8f5a7c2d"}
	var simulation := _fixture(50, {"parent_state_hash": parent_hash})
	for tick in range(1, 8):
		simulation.step(tick, tick * 20, MeteorStorm.ACTION_FIRE)
	_expect(
		parent_state == frozen_copy,
		"Meteor Storm stepping must not mutate a suspended parent combat snapshot"
	)
	_expect(
		simulation.state_for_hash().parent_state_hash == parent_hash,
		"controller hash state should retain the frozen parent hash for integration checks"
	)
	var meter: Dictionary = simulation.snapshot().meter
	_expect(
		meter.column_source_rect == [0, 0, 64, 600]
		and int(meter.distance_track_pixels) == 455
		and int(meter.column_destination[2]) == 64,
		"snapshot should be self-sufficient for exact 800x600 meter rendering"
	)


func _fixture(
	seed_value: int,
	progression_overrides: Dictionary = {},
	collision_probe: CollisionProbe = null
) -> MeteorStormSimulation:
	return _fixture_with_rng(Rng.new(seed_value), progression_overrides, collision_probe)


func _fixture_with_rng(
	rng_source,
	progression_overrides: Dictionary = {},
	collision_probe: CollisionProbe = null
) -> MeteorStormSimulation:
	var contract := MeteorStorm.retail_contract()
	if collision_probe != null:
		contract.collision_query = collision_probe.query
	var simulation := MeteorStorm.new()
	_expect(simulation.configure(contract), simulation.get_last_error())
	var progression := {
		"ship_x": 400.0,
		"ship_y": 564.0,
		"player_move_speed": 4.0,
		"money": 0,
		"max_money": 99990,
		"meteor_streak": 0,
		"score_multiplier": 1,
	}
	progression.merge(progression_overrides, true)
	var entered: Dictionary = simulation.enter(0, progression, rng_source, 0, 0)
	_expect(bool(entered.get("ok", false)), simulation.get_last_error())
	simulation.set_meta("test_enter_result", entered.duplicate(true))
	return simulation


func _prepare_collision_slot(simulation, kind: String, frame_index: int) -> void:
	simulation._intro_until_ms = 0
	simulation._counted_active_slots = 20
	var slot: Dictionary = simulation._slots[0]
	slot.active = true
	slot.kind = kind
	slot.frame_index = frame_index
	slot.x = 380.0
	slot.y = 550.0
	slot.velocity_x = 0.0
	slot.velocity_y = 0.0
	slot.animation_ticks = 5.0
	slot.spawn_serial = 99
	match kind:
		"meteor":
			slot.source_rect = [0, 0, 64, 53]
			slot.collision_mask = "meteors"
			slot.texture_id = "meteors"
		"bonus":
			slot.source_rect = [frame_index * 64, 0, 64, 37]
			slot.collision_mask = "meteorbonuses"
			slot.texture_id = "meteorbonuses"
		"gem":
			slot.source_rect = [frame_index * 80, 0, 80, 51]
			slot.collision_mask = "diamantbig"
			slot.texture_id = "diamantbig"


func _prepare_success(simulation, low_updates: int, high_updates: int) -> void:
	simulation._intro_until_ms = 0
	simulation._distance = 0.01
	simulation._counted_active_slots = 20
	simulation._low_speed_updates = low_updates
	simulation._high_speed_updates = high_updates
	simulation._speed = 15.0
	simulation._accelerator_released = false


func _active_slot_count(slots: Array) -> int:
	var count := 0
	for slot_value in slots:
		if bool((slot_value as Dictionary).active):
			count += 1
	return count


func _event_kinds(events: Array) -> Array[String]:
	var kinds: Array[String] = []
	for event_value in events:
		kinds.append(String((event_value as Dictionary).kind))
	return kinds


func _countdown_values(events: Array) -> Array[int]:
	var values: Array[int] = []
	for event_value in events:
		var event: Dictionary = event_value
		if String(event.kind) == "countdown_cue":
			values.append(int(event.value))
	return values


func _voice_keys(events: Array) -> Array[String]:
	var keys: Array[String] = []
	for event_value in events:
		var event: Dictionary = event_value
		if String(event.get("kind", "")) == "voice_cue":
			keys.append(String(event.get("key", "")))
	return keys


func _first_event(events: Array, kind: String) -> Dictionary:
	for event_value in events:
		var event: Dictionary = event_value
		if String(event.get("kind", "")) == kind:
			return event
	return {}


func _first_voice_event(events: Array, key: String) -> Dictionary:
	for event_value in events:
		var event: Dictionary = event_value
		if (
			String(event.get("kind", "")) == "voice_cue"
			and String(event.get("key", "")) == key
		):
			return event
	return {}


func _first_sound_event(events: Array, key: String) -> Dictionary:
	for event_value in events:
		var event: Dictionary = event_value
		if (
			String(event.get("kind", "")) == "sound_cue"
			and String(event.get("key", "")) == key
		):
			return event
	return {}


func _has_sound_event(events: Array, key: String, frequency_hz: int = -1) -> bool:
	for event_value in events:
		var event: Dictionary = event_value
		if String(event.get("kind", "")) != "sound_cue":
			continue
		if String(event.get("key", "")) != key:
			continue
		if frequency_hz >= 0 and int(event.get("frequency_hz", -1)) != frequency_hz:
			continue
		return true
	return false


func _f32(value: float) -> float:
	var storage := PackedFloat32Array([value])
	return float(storage[0])


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

extends SceneTree

const GemDrop := preload("res://src/sim/gem_drop_simulation.gd")
const Rng := preload("res://src/sim/deterministic_rng.gd")

var _failures: Array[String] = []


class ScriptedRng extends RefCounted:
	var range_values: Array[int] = []
	var float_values: Array[float] = []
	var calls: Array = []

	func _init(ranges: Array[int] = [], floats: Array[float] = []) -> void:
		range_values = ranges.duplicate()
		float_values = floats.duplicate()

	func next_range(upper_exclusive: int) -> int:
		calls.append(["range", upper_exclusive])
		if range_values.is_empty():
			return 0
		return posmod(int(range_values.pop_front()), upper_exclusive)

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


class PoolResetProbe extends RefCounted:
	var rng: Variant
	var calls: Array[Dictionary] = []

	func _init(rng_source: Variant) -> void:
		rng = rng_source

	func reset(reason: String, seat_id: int) -> Dictionary:
		var call_count := 0
		if rng is ScriptedRng:
			call_count = (rng as ScriptedRng).calls.size()
		elif rng is Rng:
			call_count = int((rng as Rng).snapshot().draw_count)
		var record := {
			"reason": reason,
			"seat_id": seat_id,
			"rng_call_count": call_count,
		}
		calls.append(record)
		return record


func _initialize() -> void:
	_test_contract_and_initialization_rng()
	_test_growth_spawn_rng_order_and_color_boundaries()
	_test_animation_motion_offscreen_and_refill()
	_test_intro_deadline_duration_and_terminal_reset()
	_test_collision_payload_rewards_audio_and_cap()
	_test_drunk_and_coop_ownership_routes()
	_test_strict_aabb_and_multiple_collection_scan()
	_test_deterministic_hash_state()
	if _failures.is_empty():
		print("GEM DROP TESTS PASSED")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _test_contract_and_initialization_rng() -> void:
	var contract := GemDrop.retail_contract()
	_expect(
		String(contract.executable_sha256)
		== "ddf1778c307af1087ff9dcb512786111e665d972298aeaac3f1b4b2996d079ef",
		"Gem Drop must pin the audited WarBlade 1.34 executable"
	)
	_expect(
		int(contract.slot_count) == 10
		and int(contract.intro_ms) == 4000
		and String(contract.assets.texture) == "diamantbig"
		and String(contract.assets.mask) == "diamantbig"
		and String(contract.assets.music) == "gems",
		"the retail contract should expose the ten-slot diamantbig/gems state"
	)
	var invalid := GemDrop.new()
	var invalid_contract := contract.duplicate(true)
	invalid_contract.executable_sha256 = "wrong-build"
	_expect(
		not invalid.configure(invalid_contract),
		"configure should reject constants attributed to another executable"
	)

	var ranges: Array[int] = []
	var expected_calls: Array = []
	for slot_id in range(GemDrop.SLOT_COUNT):
		ranges.append_array([slot_id % 3, slot_id % 11, slot_id % 3])
		expected_calls.append_array([
			["range", 3], ["range", 11], ["range", 3],
		])
	var rng := ScriptedRng.new(ranges, [])
	var reset_probe := PoolResetProbe.new(rng)
	var simulation := _fixture_with_rng(
		rng, CollisionProbe.new(), reset_probe, "solo", false, [0, 0], [1, 1]
	)
	var entered: Dictionary = simulation.get_meta("test_enter_result", {})
	_expect(
		reset_probe.calls.size() == 1
		and String(reset_probe.calls[0].reason) == "entry"
		and int(reset_probe.calls[0].rng_call_count) == 0,
		"the shared combat-pool reset must run before Gem Drop's slot RNG"
	)
	_expect(
		rng.calls == expected_calls,
		"initialization must consume source/frame/period for all ten slots in order"
	)
	_expect(
		int(simulation.state_for_hash().rng_draws_since_enter) == 30,
		"the ten inactive slots must consume exactly 30 controller RNG draws"
	)
	var slots: Array = entered.snapshot.slots
	_expect(
		int(slots[0].source_x) == 0
		and int(slots[0].frame_index) == 0
		and int(slots[0].animation_period) == 3
		and int(slots[0].animation_countdown) == 3
		and int(slots[2].source_x) == 160
		and int(slots[2].animation_period) == 5,
		"initialized slots must retain both the 3..5 baseline and current countdown"
	)
	_expect(
		_event_kinds(entered.events) == ["gem_drop_entered", "music_cue"]
		and String(entered.events[1].key) == "gems",
		"entry should switch directly to the recovered gems music"
	)
	_expect(
		String(entered.snapshot.title) == "G E M   D R O P"
		and String(entered.snapshot.stage) == "intro"
		and int(entered.snapshot.intro_until_ms) == 4000,
		"ordinary Gem Drop should expose its exact title and four-second gate"
	)


func _test_growth_spawn_rng_order_and_color_boundaries() -> void:
	var rng := ScriptedRng.new()
	var simulation := _fixture_with_rng(rng)
	rng.calls.clear()
	rng.range_values = [50, 10, 2]
	rng.float_values = [13.5, 649.5]
	simulation._intro_until_ms = 0
	var active: Dictionary = simulation.step(1, 0, _players())
	_expect(
		rng.calls == [
			["range", 100],
			["range", 11],
			["range", 3],
			["float", 7.0, 14.0],
			["float", 70.0, 650.0],
		],
		"growth spawn must preserve color/frame/period/speed/x RNG ordering"
	)
	var slot: Dictionary = active.snapshot.slots[0]
	_expect(
		String(active.snapshot.stage) == "active"
		and int(active.snapshot.active_count) == 1
		and int(slot.spawn_serial) == 1
		and int(slot.source_x) == 0
		and int(slot.frame_index) == 10
		and int(slot.animation_period) == 3
		and int(slot.animation_countdown) == 2
		and int(slot.x_fp) == _to_fp(649.5)
		and int(slot.y_fp) == _to_fp(-46.5)
		and int(slot.fall_speed_fp) == _to_fp(13.5),
		"the spawned slot should update once on its allocation frame"
	)
	_expect(
		int(simulation.state_for_hash().next_spawn_serial) == 2,
		"spawn serial allocation must be hash-visible for interpolation parity"
	)
	_expect(
		is_equal_approx(float(active.snapshot.remaining), 2679.0)
		and is_equal_approx(
			float(active.snapshot.active_target_fp) / GemDrop.FP_ONE,
			_f32(1.0 + GemDrop.ACTIVE_TARGET_GROWTH)
		),
		"each active update should grow the target once and decrement duration once"
	)

	for case_value in [[50, 0], [51, 80], [84, 80], [85, 160]]:
		var case_rng := ScriptedRng.new()
		var case_simulation := _fixture_with_rng(case_rng)
		case_rng.calls.clear()
		case_rng.range_values = [int(case_value[0]), 0, 0]
		case_rng.float_values = [7.0, 70.0]
		case_simulation._spawn_slot(0, true)
		_expect(
			int(case_simulation._slots[0].source_x) == int(case_value[1]),
			"color roll %d should select source x %d" % case_value
		)

	var high_target_rng := ScriptedRng.new()
	var high_target := _fixture_with_rng(high_target_rng)
	high_target_rng.calls.clear()
	high_target_rng.range_values = [0, 0, 0]
	high_target_rng.float_values = [7.0, 70.0]
	high_target._intro_until_ms = 0
	high_target._active_target = 5.0
	var one_growth_spawn: Dictionary = high_target.step(1, 0, _players())
	_expect(
		int(one_growth_spawn.snapshot.active_count) == 1
		and high_target_rng.calls.size() == 5,
		"a high active target may allocate at most one pre-scan growth slot per update"
	)


func _test_animation_motion_offscreen_and_refill() -> void:
	var simulation := _fixture_with_rng(ScriptedRng.new())
	simulation._intro_until_ms = 0
	simulation._active_target = 1.0
	simulation._active_count = 2
	_prepare_slot(simulation, 0, 300.0, 100.0, 1.0, 0, 10, 4)
	_prepare_slot(simulation, 1, 500.0, 100.0, 0.0, 1, 4, 4)
	var animated: Dictionary = simulation.step(1, 0, _players())
	_expect(
		int(animated.snapshot.slots[0].frame_index) == 0
		and int(animated.snapshot.slots[0].animation_countdown) == 4
		and int(animated.snapshot.slots[0].y_fp) == _to_fp(101.0),
		"negative countdown should restore the baseline, advance, wrap, then move"
	)
	_expect(
		int(animated.snapshot.slots[1].frame_index) == 4
		and int(animated.snapshot.slots[1].animation_countdown) == 0,
		"animation countdown equality at zero must not advance the frame"
	)

	var threshold := _fixture_with_rng(ScriptedRng.new())
	threshold._intro_until_ms = 0
	threshold._active_target = 1.0
	threshold._active_count = 2
	_prepare_slot(threshold, 0, 300.0, 650.0, 6.0, 3, 0, 3)
	_prepare_slot(threshold, 1, 500.0, 100.0, 0.0, 3, 0, 3)
	var equality: Dictionary = threshold.step(1, 0, _players())
	_expect(
		bool(equality.snapshot.slots[0].active)
		and int(equality.snapshot.slots[0].y_fp) == _to_fp(656.0),
		"offscreen equality at height+51+5 must remain active"
	)
	var beyond: Dictionary = threshold.step(2, 1, _players())
	_expect(
		not bool(beyond.snapshot.slots[0].active)
		and int(beyond.snapshot.active_count) == 1,
		"a slot should deactivate only after moving strictly beyond y=656"
	)

	var refill_rng := ScriptedRng.new()
	var refill := _fixture_with_rng(refill_rng)
	refill_rng.calls.clear()
	refill._intro_until_ms = 0
	refill._active_target = 1.0
	refill._active_count = 1
	_prepare_slot(refill, 0, 300.0, 656.0, 1.0, 3, 0, 3)
	refill_rng.range_values = [85, 10, 2]
	refill_rng.float_values = [9.5, 600.0]
	var replaced: Dictionary = refill.step(1, 0, _players())
	_expect(
		refill_rng.calls == [
			["range", 100],
			["range", 11],
			["range", 3],
			["float", 6.0, 10.0],
			["float", 70.0, 650.0],
		],
		"offscreen refill must substitute the recovered 6..10 fall-speed draw"
	)
	_expect(
		bool(replaced.snapshot.slots[0].active)
		and int(replaced.snapshot.slots[0].spawn_serial) == 1
		and int(replaced.snapshot.slots[0].source_x) == 160
		and int(replaced.snapshot.slots[0].y_fp) == _to_fp(-60.0)
		and int(replaced.snapshot.slots[0].fall_speed_fp) == _to_fp(9.5),
		"the lowest free slot should be reinitialized immediately after expiry"
	)


func _test_intro_deadline_duration_and_terminal_reset() -> void:
	var rng := ScriptedRng.new()
	var reset_probe := PoolResetProbe.new(rng)
	var simulation := _fixture_with_rng(
		rng, CollisionProbe.new(), reset_probe, "solo", true
	)
	var before: Dictionary = simulation.step(1, 3999, _players())
	_expect(
		String(before.snapshot.stage) == "intro"
		and int(before.snapshot.active_count) == 0
		and is_equal_approx(float(before.snapshot.remaining), 2680.0),
		"now < deadline should suppress updater, collision, and duration changes"
	)
	var equality: Dictionary = simulation.step(2, 4000, _players())
	_expect(
		String(equality.snapshot.stage) == "active"
		and int(equality.snapshot.active_count) == 1
		and is_equal_approx(float(equality.snapshot.remaining), 2679.0),
		"deadline equality should execute the first active update"
	)
	_expect(
		String(equality.snapshot.title) == "S U P E R   G E M   D R O P",
		"the super flag should select the exact alternate title"
	)

	simulation._remaining = 1.0
	simulation._active_target = 0.0
	simulation._active_count = 0
	for slot in simulation._slots:
		(slot as Dictionary).active = false
	var exact_zero: Dictionary = simulation.step(3, 4001, _players())
	_expect(
		not bool(exact_zero.complete)
		and is_equal_approx(float(exact_zero.snapshot.remaining), 0.0),
		"duration equality at zero must survive for one more active update"
	)
	var completed: Dictionary = simulation.step(4, 4002, _players())
	_expect(
		bool(completed.complete)
		and String(completed.snapshot.stage) == "complete"
		and not bool(completed.snapshot.super_gem_drop),
		"remaining < 0 should complete and clear the super flag"
	)
	_expect(
		reset_probe.calls.size() == 2
		and String(reset_probe.calls[1].reason) == "terminal",
		"completion must rerun the live shared-pool reset instead of caching entry"
	)
	_expect(
		int(completed.completion.retail_transition_ms) == 500
		and int(completed.completion.next_main_state) == 2
		and not bool(completed.completion.originating_bonus_mode_resumed)
		and not bool(completed.completion.music_restored),
		"terminal state should hand off to main state 2 without resuming or restoring music"
	)
	_expect(
		_event_kinds(completed.events) == ["gem_drop_completed"],
		"the terminal tail must not synthesize a music-restoration cue"
	)
	_expect(
		int(GemDrop.DURATION_INITIAL) + 1 == 2681,
		"normal tick scale should require 2681 active updates through completion"
	)


func _test_collision_payload_rewards_audio_and_cap() -> void:
	var rng := ScriptedRng.new()
	var probe := CollisionProbe.new()
	var simulation := _fixture_with_rng(
		rng, probe, null, "solo", false, [0, 0], [2, 1]
	)
	rng.calls.clear()
	rng.range_values = [0, 14999, 7777]
	_prepare_active_collision_state(simulation, 3)
	for slot_id in range(3):
		_prepare_slot(
			simulation, slot_id, 279.0, 550.0, 0.0, 3, slot_id, 3,
			slot_id * GemDrop.GEM_WIDTH
		)
	var result: Dictionary = simulation.step(1, 0, _players(300, 500))
	_expect(
		result.rewards.size() == 3
		and int(result.rewards[0].score) == 100000
		and int(result.rewards[1].score) == 200000
		and int(result.rewards[2].score) == 1000000,
		"ordinary source columns should award 50k/100k/500k times multiplier"
	)
	_expect(
		int(result.snapshot.score_deltas_by_seat[0]) == 1300000
		and int(result.snapshot.active_count) == 0,
		"all overlapping slots should collect in ascending order in one scan"
	)
	_expect(
		_event_kinds(result.events) == [
			"sound_cue", "voice_cue", "gem_drop_collected",
			"sound_cue", "voice_cue", "gem_drop_collected",
			"sound_cue", "voice_cue", "gem_drop_collected",
		],
		"each collection must emit jingles, bonus voice, then reward text/event"
	)
	_expect(
		int(result.events[0].frequency_hz) == 30000
		and int(result.events[3].frequency_hz) == 44999
		and int(result.events[0].volume_index) == 255
		and int(result.events[0].legacy_pan_table_index) == 319
		and is_equal_approx(
			float(result.events[0].legacy_pan_attribute_raw),
			_f32(319.0 * 255.0 / 800.0)
		),
		"jingles should use one [30000,45000) draw and preserve the raw BASS pan float"
	)
	_expect(
		String(result.events[1].key) == "bonus"
		and int(result.events[1].queue_tag) == 0
		and int(result.events[1].queue_padding_ms) == 50
		and bool(result.events[1].drop_if_voice_busy),
		"the generic bonus voice should retain its queue semantics"
	)
	_expect(
		probe.calls.size() == 3
		and probe.calls[0].slot_source_rect == [0, 0, 80, 51]
		and probe.calls[0].slot_destination_rect == [279, 550, 80, 51]
		and probe.calls[0].fighter_source_rect == [200, 0, 40, 27]
		and probe.calls[0].fighter_destination_rect == [280, 550, 40, 27],
		"narrow phase should receive exact diamantbig/fighter source and destination rectangles"
	)

	var cap_rng := ScriptedRng.new()
	var capped := _fixture_with_rng(
		cap_rng, CollisionProbe.new(), null, "solo", true,
		[249000000, 0], [2, 1]
	)
	cap_rng.calls.clear()
	cap_rng.range_values = [0]
	_prepare_active_collision_state(capped, 1)
	_prepare_slot(capped, 0, 380.0, 550.0, 0.0, 3, 0, 3, 160)
	var capped_result: Dictionary = capped.step(1, 0, _players())
	_expect(
		int(capped_result.rewards[0].base_score) == 10000000
		and int(capped_result.rewards[0].requested_score) == 20000000
		and int(capped_result.rewards[0].score) == 1000000
		and int(capped_result.snapshot.score_deltas_by_seat[0]) == 1000000,
		"super rewards must apply the live multiplier and clamp at 250,000,000"
	)


func _test_drunk_and_coop_ownership_routes() -> void:
	var solo_rng := ScriptedRng.new()
	var solo_probe := CollisionProbe.new()
	var solo := _fixture_with_rng(solo_rng, solo_probe)
	solo_rng.calls.clear()
	_prepare_active_collision_state(solo, 1)
	_prepare_slot(solo, 0, 480.0, 550.0, 0.0, 3, 0, 3, 0)
	var solo_result: Dictionary = solo.step(1, 0, _players(300, 500))
	_expect(
		solo_result.rewards.is_empty()
		and solo_probe.calls.is_empty()
		and solo_rng.calls.is_empty(),
		"retail solo should scan only its owner even when the other fighter overlaps"
	)

	var drunk_normal_rng := ScriptedRng.new()
	var drunk_normal_probe := CollisionProbe.new()
	var drunk_normal := _fixture_with_rng(drunk_normal_rng, drunk_normal_probe)
	drunk_normal_rng.calls.clear()
	drunk_normal_rng.range_values = [63, 4321]
	_prepare_active_collision_state(drunk_normal, 1)
	_prepare_slot(drunk_normal, 0, 280.0, 550.0, 0.0, 3, 0, 3, 0)
	var drunk_players := _players(300, 500)
	drunk_players[0].drunk_active = true
	var drunk_normal_result: Dictionary = drunk_normal.step(1, 0, drunk_players)
	_expect(
		drunk_normal_rng.calls == [["range", 128], ["range", 15000]]
		and drunk_normal_result.rewards.size() == 1
		and drunk_normal_probe.calls[0].fighter_destination_rect == [280, 550, 40, 27],
		"Drunk draw <64 should retain the normalized player collision position"
	)

	var drunk_mirror_rng := ScriptedRng.new()
	var drunk_mirror_probe := CollisionProbe.new()
	var drunk_mirror := _fixture_with_rng(drunk_mirror_rng, drunk_mirror_probe)
	drunk_mirror_rng.calls.clear()
	drunk_mirror_rng.range_values = [64, 4321]
	_prepare_active_collision_state(drunk_mirror, 1)
	_prepare_slot(drunk_mirror, 0, 480.0, 550.0, 0.0, 3, 0, 3, 0)
	var drunk_mirror_result: Dictionary = drunk_mirror.step(1, 0, drunk_players)
	_expect(
		drunk_mirror_rng.calls == [["range", 128], ["range", 15000]]
		and drunk_mirror_result.rewards.size() == 1
		and drunk_mirror_probe.calls[0].fighter_destination_rect == [480, 550, 40, 27],
		"Drunk draw >=64 should mirror normalized center x as width-x"
	)

	var coop_rng := ScriptedRng.new()
	var coop_probe := CollisionProbe.new()
	var coop := _fixture_with_rng(
		coop_rng, coop_probe, null, "coop", false,
		[249900000, 249900000], [2, 2]
	)
	coop_rng.calls.clear()
	coop_rng.range_values = [0, 0]
	_prepare_active_collision_state(coop, 2)
	_prepare_slot(coop, 0, 280.0, 550.0, 0.0, 3, 0, 3, 0)
	_prepare_slot(coop, 1, 480.0, 550.0, 0.0, 3, 0, 3, 0)
	var coop_result: Dictionary = coop.step(1, 0, _players(300, 500))
	_expect(
		coop_rng.calls == [["range", 15000], ["range", 15000]]
		and coop_result.rewards.size() == 2
		and int(coop_result.rewards[0].seat_id) == 0
		and int(coop_result.rewards[1].seat_id) == 1,
		"remake co-op should scan owner then complement without a retail ownership draw"
	)
	_expect(
		coop_result.snapshot.score_deltas_by_seat == [100000, 0],
		"co-op collections must share the global retail score cap"
	)


func _test_strict_aabb_and_multiple_collection_scan() -> void:
	var rng := ScriptedRng.new()
	var probe := CollisionProbe.new()
	var simulation := _fixture_with_rng(rng, probe)
	rng.calls.clear()
	_prepare_active_collision_state(simulation, 1)
	_prepare_slot(simulation, 0, 420.0, 550.0, 0.0, 3, 0, 3, 0)
	var touching: Dictionary = simulation.step(1, 0, _players())
	_expect(
		probe.calls.is_empty()
		and touching.rewards.is_empty()
		and bool(touching.snapshot.slots[0].active),
		"strict broad phase must reject exact edge contact before HMA lookup"
	)
	rng.range_values = [0]
	simulation._slots[0].x = 419.0
	var overlapping: Dictionary = simulation.step(2, 1, _players())
	_expect(
		probe.calls.size() == 1
		and overlapping.rewards.size() == 1
		and not bool(overlapping.snapshot.slots[0].active),
		"one-pixel overlap should reach the injected HMA query and collect"
	)


func _test_deterministic_hash_state() -> void:
	var probe_a := CollisionProbe.new()
	probe_a.should_hit = false
	var probe_b := CollisionProbe.new()
	probe_b.should_hit = false
	var a := _fixture_with_rng(Rng.new(0x13579bdf), probe_a)
	var b := _fixture_with_rng(Rng.new(0x13579bdf), probe_b)
	for tick in range(1, 32):
		var now_ms := 4000 + tick - 1
		var players := _players(300 + tick, 500 - tick)
		var result_a: Dictionary = a.step(tick, now_ms, players)
		var result_b: Dictionary = b.step(tick, now_ms, players)
		_expect(
			result_a == result_b,
			"same seed/player stream should produce the same result at tick %d" % tick
		)
		_expect(
			a.state_for_hash() == b.state_for_hash(),
			"same seed/player stream should produce the same hash state at tick %d" % tick
		)
	_expect(
		int(a.state_for_hash().rng.draw_count) == 30 + 5,
		"30 initialization draws plus one five-draw growth spawn should remain replay-visible"
	)


func _fixture_with_rng(
	rng_source: Variant,
	collision_probe: CollisionProbe = null,
	reset_probe: PoolResetProbe = null,
	session_mode: String = "solo",
	super_gem_drop: bool = false,
	starting_scores: Array[int] = [0, 0],
	score_multipliers: Array[int] = [1, 1],
	owner_seat_id: int = 0
) -> GemDropSimulation:
	if collision_probe == null:
		collision_probe = CollisionProbe.new()
	if reset_probe == null:
		reset_probe = PoolResetProbe.new(rng_source)
	var contract := GemDrop.retail_contract()
	contract.collision_query = collision_probe.query
	contract.pool_reset_callback = reset_probe.reset
	var simulation := GemDrop.new()
	_expect(simulation.configure(contract), simulation.get_last_error())
	var progressions: Array = []
	for seat_id in range(2):
		progressions.append({
			"score": int(starting_scores[seat_id]),
			"score_multiplier": int(score_multipliers[seat_id]),
		})
	var entered: Dictionary = simulation.enter(
		owner_seat_id,
		"memory_station",
		super_gem_drop,
		_players(),
		progressions,
		session_mode,
		rng_source,
		0,
		0
	)
	_expect(bool(entered.get("ok", false)), simulation.get_last_error())
	simulation.set_meta("test_enter_result", entered.duplicate(true))
	simulation.set_meta("test_collision_probe", collision_probe)
	simulation.set_meta("test_reset_probe", reset_probe)
	return simulation


func _prepare_active_collision_state(simulation: GemDropSimulation, active_count: int) -> void:
	simulation._intro_until_ms = 0
	simulation._stage = GemDrop.STAGE_ACTIVE
	simulation._remaining = 100.0
	simulation._active_target = 0.0
	simulation._active_count = active_count
	for slot_value in simulation._slots:
		(slot_value as Dictionary).active = false


func _prepare_slot(
	simulation: GemDropSimulation,
	slot_id: int,
	x: float,
	y: float,
	fall_speed: float,
	countdown: int,
	frame_index: int,
	period: int,
	source_x: int = 0
) -> void:
	var slot: Dictionary = simulation._slots[slot_id]
	slot.active = true
	slot.source_x = source_x
	slot.frame_index = frame_index
	slot.animation_period = period
	slot.animation_countdown = countdown
	slot.x = _f32(x)
	slot.y = _f32(y)
	slot.fall_speed = _f32(fall_speed)


func _players(x0: int = 400, x1: int = 500) -> Array:
	return [
		{
			"seat_id": 0,
			"active": true,
			"alive": true,
			"x_fp": x0 * GemDrop.FP_ONE,
			"y_fp": 564 * GemDrop.FP_ONE,
			"mask_frame": 5,
			"fighter_id": "fighter1",
			"drunk_active": false,
		},
		{
			"seat_id": 1,
			"active": true,
			"alive": true,
			"x_fp": x1 * GemDrop.FP_ONE,
			"y_fp": 564 * GemDrop.FP_ONE,
			"mask_frame": 5,
			"fighter_id": "fighter2",
			"drunk_active": false,
		},
	]


func _event_kinds(events: Array) -> Array[String]:
	var result: Array[String] = []
	for event_value in events:
		result.append(String((event_value as Dictionary).kind))
	return result


func _to_fp(value: float) -> int:
	return int(round(value * GemDrop.FP_ONE))


func _f32(value: float) -> float:
	var storage := PackedFloat32Array([value])
	return float(storage[0])


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

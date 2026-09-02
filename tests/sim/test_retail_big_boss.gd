extends SceneTree

const Boss := preload("res://src/sim/retail_big_boss_simulation.gd")

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


class RuntimeProbe extends RefCounted:
	var projectile_requests: Array[Dictionary] = []
	var finalized_projectiles: Array[Dictionary] = []
	var effect_calls: Array[Dictionary] = []
	var next_projectile_id: int = 1000
	var reject_effects: bool = false
	var effect_allocated_count: int = 1
	var effect_frame_period: int = 0
	var malformed_effect_response: bool = false
	var reject_finalizer: bool = false
	var malformed_allocator: bool = false
	var reject_allocator: bool = false
	var projectile_pool_full: bool = false
	var retained_animation_frame: int = 0
	var retained_animation_period: float = 0.0
	var retained_animation_countdown: float = 0.0

	func allocate_common_projectile(request: Dictionary) -> Dictionary:
		projectile_requests.append(request.duplicate(true))
		if malformed_allocator:
			return {"allocated": true}
		if reject_allocator:
			return {
				"ok": false,
				"error": "injected projectile reservation failure",
				"allocated": false,
				"common_slot": -1,
				"projectile_id": 0,
			}
		if projectile_pool_full:
			return {
				"ok": true,
				"error": "",
				"allocated": false,
				"common_slot": -1,
				"projectile_id": 0,
			}
		var slot := projectile_requests.size() - 1
		next_projectile_id += 1
		return {
			"ok": true,
			"error": "",
			"allocated": true,
			"common_slot": slot,
			"projectile_id": next_projectile_id,
			"retained_animation_frame": retained_animation_frame,
			"retained_animation_period": retained_animation_period,
			"retained_animation_countdown": retained_animation_countdown,
		}

	func finalize_common_projectile(request: Dictionary) -> Dictionary:
		finalized_projectiles.append(request.duplicate(true))
		return {
			"ok": not reject_finalizer,
			"error": "injected projectile finalizer failure" if reject_finalizer else "",
		}

	func dispatch_retail_effect(
		call_name: String,
		payload: Dictionary,
		_rng_source: Variant
	) -> Dictionary:
		effect_calls.append({
			"call": call_name,
			"payload": payload.duplicate(true),
		})
		if malformed_effect_response:
			return {"ok": true}
		var result := {
			"ok": not reject_effects,
			"allocated_count": 0 if reject_effects else effect_allocated_count,
		}
		if call_name == "FUN_005dfee0" and effect_allocated_count > 0:
			result["frame_period"] = effect_frame_period
		return result


func _initialize() -> void:
	_test_contract_is_executable_pinned_and_fail_closed()
	_test_initial_stage_health_and_exact_two_part_renderer()
	_test_entry_rng_music_and_hum_are_emitted_once()
	_test_shared_hit_flash_countdown_and_laser_policy()
	_test_full_effect_pool_suppresses_the_presentation_event()
	_test_render_handoff_and_sound_deadline_hash_state()
	_test_strict_animation_boundary_and_no_bounce()
	_test_aimed_fire_and_opcode_two_projectile_golden()
	_test_common_pool_reservation_and_retained_animation_golden()
	_test_strict_death_boundary_and_completion_marks()
	_test_progression_effect_flags_are_required_and_propagated()
	_test_runtime_callback_failures_block_the_encounter()
	if _failures.is_empty():
		print("RETAIL BIG BOSS TESTS PASSED")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _test_contract_is_executable_pinned_and_fail_closed() -> void:
	var contract := Boss.retail_contract()
	_expect(
		String(contract.executable_sha256)
		== "ddf1778c307af1087ff9dcb512786111e665d972298aeaac3f1b4b2996d079ef",
		"the state-13 contract must pin the audited WarBlade 1.34 executable"
	)
	_expect(
		contract.resources.slots == [1, 2, 3, 4, 5, 6]
		and contract.animation.stage_to_resource_slot == [1, 2, 3, 4, 5, 6]
		and contract.rendering.part_count == 2
		and contract.authored_level_payload.canonicalization
		== "warblade_canonical_payload_v1"
		and contract.authored_level_payload.sha256
		== "6ec7ac4f9f5eb5ea7a074d0315a2393acc37da1b0f1fd8f08f9b2c9032a6498f",
		"the contract must bind all six stages and the retail two-part renderer"
	)
	_expect(
		bool(contract.reward.rank_markers_unchanged)
		and contract.reward.destroyed_count == {
			"killer_delta": 1,
			"classic_coop_partner_delta": 1,
			"completion_condition": "destroyed_plus_partner>=authored_total",
			"completion_timestamp": "set_if_zero",
		},
		"boss defeat must use ordinary completion counters without rank markers"
	)
	_expect(
		contract.health.terminal_hit_below == 0
		and contract.projectile_allocation.protocol == "reserve_then_finalize"
		and contract.aimed_fire.size == [32, 32]
		and contract.aimed_fire.broadphase_inset == [8, 8]
		and contract.opcode_2.size == [32, 32]
		and contract.opcode_2.broadphase_inset == [4, 4]
		and contract.sounds == {
			"music": "boss",
			"hum": "boss",
			"hit": "hit1",
			"terminal_hit": "hit2",
			"death": "explo4",
			"aimed_projectile": "bigsmall",
			"opcode_2_deferred": "alienshoot2",
			"opcode_2_direct": "bigfire",
		},
		"the contract must pin common-pool geometry, terminal health, and sample identities"
	)
	_expect(
		contract.evidence.projectile_type_15_spawn == "0x00612fc7-0x006132bf"
		and contract.evidence.projectile_type_14_spawn == "0x00614031-0x006143cf"
		and contract.evidence.common_projectile_update == "0x006027e3-0x00602de0"
		and contract.evidence.projectile_renderer == "0x00603808/0x00603b32"
		and contract.evidence.projectile_player_collision == "0x005842c0"
		and contract.evidence.projectile_hma_collision == "0x00625a50"
		and contract.evidence.global_sound_gate_thunk == "0x00525924->0x00567990"
		and contract.evidence.global_sound_gate_dispatch_calls
		== "0x005b0c72/0x005b0d96/0x005b10ac/0x005b1191/0x005b1280"
		and contract.evidence.get_ready_to_level_transitions == "0x005abac2/0x005abfc0"
		and contract.evidence.warp_to_shop_transitions
		== "0x0061bce8/0x0061be78/0x0061c082",
		"the boss contract must retain every executable-backed projectile and sound-gate address"
	)
	var catalog_controller := Boss.new()
	_expect(
		catalog_controller.configure(_boss_catalog_contract()),
		"the controller must accept the generated JSON boss contract"
	)
	var legacy_controller := Boss.new()
	var legacy_contract := contract.duplicate(true)
	legacy_contract.routing.erase("campaign_wrapper_policy")
	legacy_contract.routing.erase("explicit_end_level_25_policy")
	legacy_contract.routing.erase("extended_campaign_policy")
	legacy_contract.routing.terminal_level_25_policy = (
		"wrapper completes campaign and never loads 26"
	)
	_expect(
		legacy_controller.configure(legacy_contract),
		"the controller must normalize the exact legacy bosses-v1 routing alias"
	)
	var invalid := Boss.new()
	var invalid_contract := contract.duplicate(true)
	invalid_contract.rendering.parts[1].source_rect = [255, 0, 256, 64]
	_expect(
		not invalid.configure(invalid_contract),
		"configure must fail closed on a renderer contract that differs from the trace"
	)
	invalid = Boss.new()
	invalid_contract = contract.duplicate(true)
	invalid_contract.reward.rank_markers_unchanged = false
	_expect(
		not invalid.configure(invalid_contract),
		"configure must fail closed if boss defeat is allowed to mutate rank markers"
	)
	invalid = Boss.new()
	invalid_contract = contract.duplicate(true)
	invalid_contract.effects.progression_inputs.erase("rank_ready")
	_expect(
		not invalid.configure(invalid_contract),
		"configure must fail closed if a traced persistent progression input is omitted"
	)
	for mutation in [
		["health", "retail", 301],
		["death", "post_effect_count", 499],
		["aimed_fire", "projectile_type", 7],
		["path", "crossing", "progress>=duration"],
		["routing", "retail_next_level_intent", false],
	]:
		invalid = Boss.new()
		invalid_contract = contract.duplicate(true)
		(invalid_contract[mutation[0]] as Dictionary)[mutation[1]] = mutation[2]
		_expect(
			not invalid.configure(invalid_contract),
			"configure must reject drift in the %s trace section" % String(mutation[0])
		)

	var payload_controller := Boss.new()
	_expect(
		payload_controller.configure(contract),
		"the pinned controller configures before authored-payload mutation testing"
	)
	var changed_level := _level_twenty_five()
	changed_level.authored_lvd.groups[1].path_points[0].acceleration_x_milli += 1
	var runtime := RuntimeProbe.new()
	var changed_entry: Dictionary = payload_controller.enter(
		changed_level,
		ScriptedRng.new(),
		{
			"allocate_common_projectile": Callable(runtime, "allocate_common_projectile"),
			"finalize_common_projectile": Callable(runtime, "finalize_common_projectile"),
			"dispatch_retail_effect": Callable(runtime, "dispatch_retail_effect"),
		},
		{
			"mode": "solo",
			"coop_balance": "classic",
			"difficulty": "normal",
			"tick": 0,
			"now_ms": 0,
			"tick_scale": 1.0,
			"only_blue_coins_active": false,
		}
	)
	_expect(
		not bool(changed_entry.get("ok", false))
		and String(changed_entry.get("error", "")).contains("authored payload"),
		"controller entry must reject gameplay-critical level-25 path drift"
	)


func _test_initial_stage_health_and_exact_two_part_renderer() -> void:
	var fixture := _fixture(ScriptedRng.new())
	var boss: Variant = fixture.boss
	var snapshot: Dictionary = boss.snapshot()
	_expect(
		int(snapshot.stage) == 0
		and String(snapshot.sheet) == "alien_big1_1"
		and float(snapshot.health) == 300.0
		and float(snapshot.max_health) == 300.0,
		"classic solo entry must start at stage zero with retail health"
	)
	_expect(
		snapshot.parts.size() == 2
		and String(snapshot.parts[0].part_id) == "0"
		and String(snapshot.parts[1].part_id) == "1"
		and snapshot.parts[0].source_rect == [0, 0, 256, 64]
		and snapshot.parts[1].source_rect == [256, 0, 256, 64]
		and snapshot.parts[0].destination_rect == [272, -189, 256, 64]
		and snapshot.parts[1].destination_rect == [272, -125, 256, 64],
		"snapshot parts must reproduce state-13's packed 256x64 draw calls"
	)
	var balanced := _fixture(
		ScriptedRng.new(),
		{"mode": "coop", "coop_balance": "balanced"}
	)
	_expect(
		float(balanced.boss.snapshot().health) == 600.0
		and float(balanced.boss.snapshot().max_health) == 600.0,
		"Balanced co-op must apply the established two-times health rule"
	)


func _test_entry_rng_music_and_hum_are_emitted_once() -> void:
	var rng := ScriptedRng.new([0, 7500, 100])
	var fixture := _fixture(rng)
	var kinds: Array[String] = []
	for event_value in fixture.entered.events:
		kinds.append(String((event_value as Dictionary).kind))
	_expect(
		rng.calls == [["u32"], ["u32"], ["u32"]]
		and kinds == ["boss_music", "boss_hum", "boss_entered"],
		"state-13 entry must take period/pitch/delta draws then emit boss music and hum once"
	)
	var update: Dictionary = fixture.boss.step(1, 1.0, [])
	var repeated_music := false
	for event_value in update.events:
		if String((event_value as Dictionary).kind) == "boss_music":
			repeated_music = true
	_expect(not repeated_music, "ordinary boss updates must not overwrite or restart boss music")


func _test_shared_hit_flash_countdown_and_laser_policy() -> void:
	var fixture := _fixture(ScriptedRng.new())
	var boss: Variant = fixture.boss
	var snapshot: Dictionary = boss.snapshot()
	var hit: Dictionary = boss.resolve_player_projectile({
		"owner_id": 0,
		"midpoint_x": float(snapshot.x) - 100.0,
		"midpoint_y": float(snapshot.y) + 60.0,
		"damage_fp": Boss.FP_ONE * 10,
		"is_laser": true,
	}, 0)
	_expect(
		bool(hit.hit)
		and not bool(hit.consume_projectile)
		and int(hit.remaining_damage_fp) == Boss.FP_ONE * 5
		and float(hit.damage) == 1.0,
		"a laser hit must deal current damage/10, survive, then halve its remaining damage"
	)
	var retail_effect_events: Array = hit.events.filter(
		func(event: Dictionary) -> bool:
			return String(event.kind) == "boss_retail_effect"
	)
	var runtime: RuntimeProbe = fixture.runtime
	_expect(
		retail_effect_events.size() == 1
			and runtime.effect_calls.size() == 1
			and String(retail_effect_events[0].call) == "FUN_005dfee0"
			and String(retail_effect_events[0].payload.kind) == "boss_hit"
			and int(retail_effect_events[0].allocated_count) == 1
			and int(retail_effect_events[0].frame_period) == 0
			and retail_effect_events[0].payload == runtime.effect_calls[0].payload,
			"an allocated state-13 impact must publish the exact retail effect call, allocation, and nested coordinates"
		)
	snapshot = boss.snapshot()
	_expect(
		int(snapshot.hit_flash_countdown) == 5
		and String(snapshot.parts[0].render_handle) == "alien_big1_1_mask"
		and String(snapshot.parts[1].render_handle) == "alien_big1_1_mask",
		"a successful hit must assign the shared retail flash countdown to five"
	)
	boss.complete_render_pass()
	_expect(
		int(boss.snapshot().hit_flash_countdown) == 3,
		"one render pass must decrement the shared flash countdown once per flashed part"
	)
	boss.complete_render_pass()
	var third_pass_projection: Dictionary = boss.snapshot()
	_expect(
		int(third_pass_projection.hit_flash_countdown) == 1
		and bool(third_pass_projection.parts[0].hit_flash)
		and not bool(third_pass_projection.parts[1].hit_flash),
		"countdown one must flash part zero and render part one normally"
	)
	var final_handoff: Dictionary = boss.complete_render_pass()
	_expect(
		bool(final_handoff.render_snapshot.parts[0].hit_flash)
		and not bool(final_handoff.render_snapshot.parts[1].hit_flash)
		and int(final_handoff.snapshot.hit_flash_countdown) == 0,
		"the sequential part renderer must exhaust the shared countdown without underflow"
	)


func _test_full_effect_pool_suppresses_the_presentation_event() -> void:
	var runtime := RuntimeProbe.new()
	runtime.effect_allocated_count = 0
	var fixture := _fixture(ScriptedRng.new(), {}, runtime)
	var boss: Variant = fixture.boss
	var before: Dictionary = boss.snapshot()
	var hit: Dictionary = boss.resolve_player_projectile({
		"owner_id": 0,
		"midpoint_x": float(before.x) - 100.0,
		"midpoint_y": float(before.y) + 60.0,
		"damage": 10.0,
	}, 0)
	var retail_effect_events: Array = hit.events.filter(
		func(event: Dictionary) -> bool:
			return String(event.kind) == "boss_retail_effect"
	)
	_expect(
		bool(hit.ok)
		and bool(hit.hit)
		and float(hit.snapshot.health) < float(before.health)
		and runtime.effect_calls.size() == 1
		and retail_effect_events.is_empty(),
		"a successful hit must continue without publishing a type-10 event when the retail flash pool is full"
	)


func _test_render_handoff_and_sound_deadline_hash_state() -> void:
	var fixture := _fixture(ScriptedRng.new())
	var boss: Variant = fixture.boss
	var visible_before: Dictionary = boss.snapshot()
	var hash_before: Dictionary = boss.state_hash_payload()
	boss._hit_sound_deadline_ms = 123
	var visible_after: Dictionary = boss.snapshot()
	var hash_after: Dictionary = boss.state_hash_payload()
	_expect(
		visible_before == visible_after
		and int(hash_before.hit_sound_deadline_ms) == -1
		and int(hash_after.hit_sound_deadline_ms) == 123
		and JSON.stringify(hash_before) != JSON.stringify(hash_after),
		"invisible sound cooldown state must distinguish future-affecting boss hashes"
	)


func _test_strict_animation_boundary_and_no_bounce() -> void:
	var fixture := _fixture(ScriptedRng.new())
	var boss: Variant = fixture.boss
	boss.step(1, 2.0, [])
	_expect(
		int(boss.snapshot().stage) == 0,
		"animation countdown equal to zero must not advance the stage"
	)
	boss.step(2, 0.25, [])
	_expect(
		int(boss.snapshot().stage) == 1
		and String(boss.snapshot().sheet) == "alien_big1_2",
		"animation advances only after the countdown becomes strictly negative"
	)
	for tick in range(3, 18):
		boss.step(tick, 3.0, [])
	_expect(
		int(boss.snapshot().stage) >= 0
		and int(boss.snapshot().stage) <= 5
		and int(boss.snapshot().animation_direction) == 1,
		"the six-sheet animation must wrap forward and never bounce"
	)


func _test_aimed_fire_and_opcode_two_projectile_golden() -> void:
	var aimed_rng := ScriptedRng.new(
		[0, 7500, 100, 6, 0],
		[0.0, 50.0, 0.0, 0.0, 0.0, 0.0, 904.0]
	)
	var aimed := _fixture(aimed_rng)
	aimed.boss._current_group_id = int(
		(aimed.level.authored_lvd.groups[1] as Dictionary).id
	)
	aimed.boss._aim_enabled = true
	var aimed_step: Dictionary = aimed.boss.step(1, 2.0, [{
		"retail_left": 400.0,
		"retail_top": 550.0,
		"active": true,
		"alive": true,
	}])
	_expect(
		aimed.runtime.projectile_requests.size() == 1
		and aimed.runtime.finalized_projectiles.size() == 1,
		"only the scripted passing mode-7 origin should allocate an aimed projectile"
	)
	if aimed.runtime.finalized_projectiles.size() == 1:
		var aimed_reservation := aimed.runtime.projectile_requests[0] as Dictionary
		var aimed_request := aimed.runtime.finalized_projectiles[0] as Dictionary
		_expect(
			String(aimed_reservation.reservation_phase) == "active_and_top_left"
			and not aimed_reservation.has("velocity_x")
			and int(aimed_request.enemy_projectile_type) == 15
			and float(aimed_request.retail_left) == 403.0
			and float(aimed_request.retail_top) == -138.0
			and float(aimed_request.x) == 419.0
			and float(aimed_request.y) == -122.0
			and is_equal_approx(float(aimed_request.velocity_x), 0.290909081697464)
			and is_equal_approx(float(aimed_request.velocity_y), 13.4363632202148)
			and int(aimed_request.width) == 32
			and int(aimed_request.broadphase_inset_x) == 8
			and int(aimed_request.broadphase_width) == 24
			and int(aimed_request.resource_slot_id) == 1
			and String(aimed_request.enemy_sheet_id) == "alien_big1_1"
			and aimed_request.source_rect == [0, 64, 32, 32],
			"type-15 spawn geometry and tick-scaled aim vector must match the state-13 trace"
		)
	var spawned_count := 0
	var aimed_effect_index := -1
	var aimed_spawn_index := -1
	var aimed_event_index := 0
	for event_value in aimed_step.events:
		var event := event_value as Dictionary
		if String(event.kind) == "boss_projectile_effect":
			aimed_effect_index = aimed_event_index
		elif String(event.kind) == "boss_projectile_spawned":
			spawned_count += 1
			aimed_spawn_index = aimed_event_index
		aimed_event_index += 1
	_expect(
		spawned_count == 1
		and aimed_effect_index >= 0
		and aimed_effect_index < aimed_spawn_index,
		"type 15 must emit its visual effect before final projectile initialization"
	)

	var burst_rng := ScriptedRng.new([0, 7500, 100])
	var burst := _fixture(burst_rng)
	burst.boss._current_group_id = int(
		(burst.level.authored_lvd.groups[1] as Dictionary).id
	)
	burst.boss._path_index = 8
	burst.boss._path_progress = 0.0
	burst.boss._velocity_x = 0.0
	burst.boss._velocity_y = 0.0
	burst.boss._acceleration_x = 0.0
	burst.boss._acceleration_y = 0.0
	burst.boss._update_path(1.0)
	_expect(
		burst.runtime.projectile_requests.is_empty(),
		"opcode 2 must not fire when truncated progress equals the opcode-1 duration"
	)
	burst.boss._update_path(1.0)
	_expect(
		burst.runtime.projectile_requests.size() == 12
		and burst.runtime.finalized_projectiles.size() == 12,
		"opcode 2 must reverse-walk all twelve authored vectors after strict boundary crossing"
	)
	if burst.runtime.finalized_projectiles.size() == 12:
		var first_burst_reservation := burst.runtime.projectile_requests[0] as Dictionary
		var first_burst := burst.runtime.finalized_projectiles[0] as Dictionary
		var last_burst := burst.runtime.finalized_projectiles[11] as Dictionary
		_expect(
			not first_burst_reservation.has("animation_period")
			and int(first_burst_reservation.width) == 32
			and int(first_burst.source_record_index) == 11
			and int(last_burst.source_record_index) == 0
			and int(first_burst.enemy_projectile_type) == 14
			and float(first_burst.retail_left) == 384.0
			and float(first_burst.retail_top) == -110.0
			and float(first_burst.x) == 400.0
			and float(first_burst.y) == -94.0
			and int(first_burst.width) == 32
			and int(first_burst.broadphase_inset_x) == 4
			and int(first_burst.broadphase_width) == 28
			and first_burst.source_rect == [512, 0, 32, 32]
			and float(first_burst.animation_period) == 1.0
			and float(first_burst.animation_countdown) == 1.0,
			"type-14 opcode burst must publish exact reverse order, animation, and geometry"
		)
	_expect(
		burst_rng.calls.count(["u32"]) == 40,
		"twelve type-14 shots must each consume period, countdown, and deferred-sound draws"
	)
	var burst_sounds: Array[String] = []
	var bigfire_event_index := -1
	var deferred_event_index := -1
	var pending_event_index := 0
	for event_value in burst.boss._pending_events:
		var event := event_value as Dictionary
		if String(event.kind) in ["sound", "boss_deferred_sound"]:
			burst_sounds.append(String(event.key))
		if String(event.get("key", "")) == "bigfire":
			bigfire_event_index = pending_event_index
		elif String(event.kind) == "boss_deferred_sound":
			deferred_event_index = pending_event_index
		pending_event_index += 1
	_expect(
		burst_sounds.count("alienshoot2") == 1
		and burst_sounds.count("bigfire") == 1
		and bigfire_event_index >= 0
		and deferred_event_index > bigfire_event_index,
		"opcode 2 must defer one final-shot cue until after the direct bigfire cue"
	)


func _test_common_pool_reservation_and_retained_animation_golden() -> void:
	var retained_runtime := RuntimeProbe.new()
	retained_runtime.retained_animation_frame = 5
	retained_runtime.retained_animation_period = 2.5
	retained_runtime.retained_animation_countdown = 1.25
	var retained := _fixture(
		ScriptedRng.new(
			[0, 7500, 100, 6, 0],
			[0.0, 50.0, 0.0, 0.0, 0.0, 0.0, 904.0]
		),
		{},
		retained_runtime
	)
	retained.boss._current_group_id = int(
		(retained.level.authored_lvd.groups[1] as Dictionary).id
	)
	retained.boss._aim_enabled = true
	retained.boss.step(1, 2.0, [{
		"retail_left": 400.0,
		"retail_top": 550.0,
		"active": true,
		"alive": true,
	}])
	_expect(
		retained_runtime.finalized_projectiles.size() == 1,
		"a reserved type-15 slot must be finalized once"
	)
	if retained_runtime.finalized_projectiles.size() == 1:
		var projectile := retained_runtime.finalized_projectiles[0] as Dictionary
		_expect(
			int(projectile.animation_frame) == 5
			and float(projectile.animation_period) == 2.5
			and float(projectile.animation_countdown) == 1.25
			and projectile.source_rect == [160, 64, 32, 32]
			and bool(projectile.animation_source_unclamped),
			"type 15 must retain stale common-slot animation fields without clamping"
		)

	var full_runtime := RuntimeProbe.new()
	full_runtime.projectile_pool_full = true
	var full_rng := ScriptedRng.new()
	var full := _fixture(full_rng, {}, full_runtime)
	full.boss._current_group_id = int(
		(full.level.authored_lvd.groups[1] as Dictionary).id
	)
	full.boss._path_index = 8
	full.boss._path_progress = 1.0
	full.boss._velocity_x = 0.0
	full.boss._velocity_y = 0.0
	full.boss._acceleration_x = 0.0
	full.boss._acceleration_y = 0.0
	full.boss._update_path(1.0)
	_expect(
		full_runtime.projectile_requests.size() == 1
		and full_runtime.finalized_projectiles.is_empty()
		and full_rng.calls.count(["u32"]) == 4,
		"a full pool must consume no type-14 animation or per-shot sound RNG"
	)


func _test_strict_death_boundary_and_completion_marks() -> void:
	var fixture := _fixture(ScriptedRng.new())
	var boss: Variant = fixture.boss
	var snapshot: Dictionary = boss.snapshot()
	var projectile := {
		"owner_id": 0,
		"rank_ready": false,
		"midpoint_x": float(snapshot.x) - 100.0,
		"midpoint_y": float(snapshot.y) + 60.0,
		"damage": 3000.0,
	}
	var zero_health: Dictionary = boss.resolve_player_projectile(projectile, 0)
	var zero_health_sound_keys: Array[String] = []
	for event_value in zero_health.events:
		var event := event_value as Dictionary
		if String(event.kind) == "sound":
			zero_health_sound_keys.append(String(event.key))
	_expect(
		float(zero_health.snapshot.health) == 0.0
		and not bool(zero_health.defeated)
		and zero_health_sound_keys.has("hit1")
		and not zero_health_sound_keys.has("hit2"),
		"retail state 13 must remain alive at zero health without a terminal-hit cue"
	)
	projectile.damage = 10.0
	var defeated: Dictionary = boss.resolve_player_projectile(projectile, 1)
	var kinds: Array[String] = []
	var defeated_sound_keys: Array[String] = []
	var completion_event: Dictionary = {}
	for event_value in defeated.events:
		var event := event_value as Dictionary
		kinds.append(String(event.kind))
		if String(event.kind) == "sound":
			defeated_sound_keys.append(String(event.key))
		if String(event.kind) == "boss_level_complete_mark":
			completion_event = event
	_expect(
		bool(defeated.defeated)
		and not bool(defeated.snapshot.active)
		and kinds.has("boss_reward")
		and kinds.has("boss_level_complete_mark")
		and not kinds.has("boss_rank_mark")
		and defeated_sound_keys.has("hit2")
		and defeated_sound_keys.count("explo4") == 3,
		"strict-negative defeat must reward and mark completion without a rank marker event"
	)
	_expect(
		bool(completion_event.get("rank_markers_unchanged", false))
		and int(completion_event.get("increment_killer_destroyed_count", 0)) == 1
		and int(completion_event.get("classic_coop_partner_delta", 0)) == 1
		and String(completion_event.get("completion_timestamp", "")) == "set_if_zero",
		"the completion event must expose the pinned FUN_00555c40 counter/timestamp semantics"
	)


func _test_runtime_callback_failures_block_the_encounter() -> void:
	var rejected_runtime := RuntimeProbe.new()
	rejected_runtime.reject_effects = true
	var rejected := _fixture(ScriptedRng.new(), {}, rejected_runtime)
	var snapshot: Dictionary = rejected.boss.snapshot()
	var result: Dictionary = rejected.boss.resolve_player_projectile({
		"owner_id": 0,
		"midpoint_x": float(snapshot.x) - 100.0,
		"midpoint_y": float(snapshot.y) + 60.0,
		"damage": 10.0,
	}, 0)
	_expect(
		not bool(result.ok)
		and bool(result.snapshot.blocked)
		and not bool(result.snapshot.active),
		"a failed retail-effect dispatch must synchronously block the encounter"
	)
	var malformed_effect_runtime := RuntimeProbe.new()
	malformed_effect_runtime.malformed_effect_response = true
	var malformed_effect := _fixture(ScriptedRng.new(), {}, malformed_effect_runtime)
	snapshot = malformed_effect.boss.snapshot()
	result = malformed_effect.boss.resolve_player_projectile({
		"owner_id": 0,
		"midpoint_x": float(snapshot.x) - 100.0,
		"midpoint_y": float(snapshot.y) + 60.0,
		"damage": 10.0,
	}, 0)
	_expect(
		not bool(result.ok)
		and bool(result.snapshot.blocked)
		and not bool(result.snapshot.active),
		"a successful effect response without allocated_count must fail closed"
	)

	var malformed_runtime := RuntimeProbe.new()
	malformed_runtime.malformed_allocator = true
	var malformed := _fixture(ScriptedRng.new([0xffffffff]), {}, malformed_runtime)
	# Force the first loop-group fire roll to pass and validate the allocator's
	# exact response schema. A malformed success must fail closed.
	malformed.boss._current_group_id = int(
		(malformed.level.authored_lvd.groups[1] as Dictionary).id
	)
	malformed.boss._aim_enabled = true
	malformed.boss.step(1, 1000.0, [{"x": 400.0, "y": 560.0, "active": true, "alive": true}])
	_expect(
		bool(malformed.boss.snapshot().blocked),
		"a successful allocator response without slot/id must block state 13"
	)
	_expect(
		malformed_runtime.projectile_requests.size() == 1,
		"a malformed allocation must stop the tick before a second origin or post-allocation RNG"
	)

	var rejected_allocator_runtime := RuntimeProbe.new()
	rejected_allocator_runtime.reject_allocator = true
	var rejected_allocator := _fixture(
		ScriptedRng.new([0xffffffff]),
		{},
		rejected_allocator_runtime
	)
	rejected_allocator.boss._current_group_id = int(
		(rejected_allocator.level.authored_lvd.groups[1] as Dictionary).id
	)
	rejected_allocator.boss._aim_enabled = true
	var rejected_allocation_result: Dictionary = rejected_allocator.boss.step(
		1,
		1000.0,
		[{"x": 400.0, "y": 560.0, "active": true, "alive": true}]
	)
	_expect(
		not bool(rejected_allocation_result.get("ok", true))
		and bool(rejected_allocator.boss.snapshot().blocked)
		and String(rejected_allocation_result.get("error", "")).contains(
			"injected projectile reservation failure"
		)
		and rejected_allocator_runtime.projectile_requests.size() == 1,
		"an explicit allocator error must stop state 13 instead of looking like pool exhaustion"
	)

	var rejected_finalizer_runtime := RuntimeProbe.new()
	rejected_finalizer_runtime.reject_finalizer = true
	var rejected_finalizer_rng := ScriptedRng.new(
		[0, 7500, 100, 6, 0],
		[0.0, 50.0, 0.0, 0.0, 0.0, 0.0, 904.0]
	)
	var rejected_finalizer := _fixture(
		rejected_finalizer_rng,
		{},
		rejected_finalizer_runtime
	)
	rejected_finalizer.boss._current_group_id = int(
		(rejected_finalizer.level.authored_lvd.groups[1] as Dictionary).id
	)
	rejected_finalizer.boss._aim_enabled = true
	rejected_finalizer.boss.step(1, 2.0, [{
		"retail_left": 400.0,
		"retail_top": 550.0,
		"active": true,
		"alive": true,
	}])
	_expect(
		bool(rejected_finalizer.boss.snapshot().blocked)
		and rejected_finalizer_runtime.finalized_projectiles.size() == 1
		and rejected_finalizer_rng.calls.count(["u32"]) == 4,
		"a failed type-15 finalizer must block before consuming its sound-frequency draw"
	)


func _test_progression_effect_flags_are_required_and_propagated() -> void:
	var missing_context_boss := Boss.new()
	_expect(
		missing_context_boss.configure(Boss.retail_contract()),
		"the pinned boss contract should configure for progression-input validation"
	)
	var missing_context_runtime := RuntimeProbe.new()
	var missing_context: Dictionary = missing_context_boss.enter(
		_level_twenty_five(),
		ScriptedRng.new(),
		{
			"allocate_common_projectile": Callable(
				missing_context_runtime,
				"allocate_common_projectile"
			),
			"finalize_common_projectile": Callable(
				missing_context_runtime,
				"finalize_common_projectile"
			),
			"dispatch_retail_effect": Callable(
				missing_context_runtime,
				"dispatch_retail_effect"
			),
		},
		{"tick_scale": 1.0}
	)
	_expect(
		not bool(missing_context.ok),
		"state 13 must not guess the selected player's only-blue-coins state"
	)

	var missing_rank := _fixture(ScriptedRng.new())
	var missing_rank_snapshot: Dictionary = missing_rank.boss.snapshot()
	var missing_rank_result: Dictionary = missing_rank.boss.resolve_player_projectile({
		"owner_id": 0,
		"midpoint_x": float(missing_rank_snapshot.x) - 100.0,
		"midpoint_y": float(missing_rank_snapshot.y) + 60.0,
		"damage": 3010.0,
	}, 0)
	_expect(
		not bool(missing_rank_result.ok)
		and bool(missing_rank_result.snapshot.blocked)
		and not bool(missing_rank_result.defeated),
		"a killing projectile must carry its physical owner's rank-ready state"
	)

	var propagated := _fixture(
		ScriptedRng.new(),
		{"only_blue_coins_active": true}
	)
	var propagated_snapshot: Dictionary = propagated.boss.snapshot()
	var propagated_result: Dictionary = propagated.boss.resolve_player_projectile({
		"owner_id": 1,
		"rank_ready": true,
		"midpoint_x": float(propagated_snapshot.x) - 100.0,
		"midpoint_y": float(propagated_snapshot.y) + 60.0,
		"damage": 3010.0,
	}, 0)
	var small_explosion_count := 0
	var saw_forced_debris := false
	for call_value in propagated.runtime.effect_calls:
		var effect_call := call_value as Dictionary
		var payload := effect_call.payload as Dictionary
		if String(effect_call.call) == "FUN_00570420":
			small_explosion_count += 1
			_expect(
				bool(payload.get("rank_ready", false))
				and int(payload.get("owner_seat_id", -1)) == 1,
				"each small explosion must receive the projectile owner's rank-ready flag"
			)
		elif String(effect_call.call) == "FUN_00571080":
			saw_forced_debris = bool(payload.get("only_blue_coins_active", false))
	_expect(
		bool(propagated_result.defeated)
		and small_explosion_count >= 8
		and saw_forced_debris,
		"boss defeat must propagate both persistent progression flags to their exact calls"
	)


func _fixture(
	rng: Variant,
	context: Dictionary = {},
	runtime_override: RuntimeProbe = null
) -> Dictionary:
	var boss := Boss.new()
	_expect(boss.configure(Boss.retail_contract()), "the pinned boss contract should configure")
	var runtime := runtime_override if runtime_override != null else RuntimeProbe.new()
	var level := _level_twenty_five()
	var enter_context := {
		"mode": "solo",
		"coop_balance": "classic",
		"difficulty": "normal",
		"tick": 0,
		"now_ms": 0,
		"tick_scale": 1.0,
		"only_blue_coins_active": false,
	}
	enter_context.merge(context, true)
	var entered := boss.enter(level, rng, {
		"allocate_common_projectile": Callable(runtime, "allocate_common_projectile"),
		"finalize_common_projectile": Callable(runtime, "finalize_common_projectile"),
		"dispatch_retail_effect": Callable(runtime, "dispatch_retail_effect"),
	}, enter_context)
	_expect(bool(entered.ok), "the exact level-25 fixture should enter state 13")
	return {"boss": boss, "runtime": runtime, "level": level, "entered": entered}


func _level_twenty_five() -> Dictionary:
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://content/levels.json")
	)
	if not parsed is Dictionary:
		return {}
	for level_value in (parsed as Dictionary).get("levels", []):
		var level := level_value as Dictionary
		if int(level.get("id", 0)) == 25:
			return level.duplicate(true)
	return {}


func _boss_catalog_contract() -> Dictionary:
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://content/bosses.json")
	)
	if not parsed is Dictionary:
		return {}
	return (((parsed as Dictionary).get("bosses", {}) as Dictionary).get(
		"retail_big_boss_v1",
		{}
	) as Dictionary).duplicate(true)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

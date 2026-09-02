extends SceneTree

const Boss := preload("res://src/sim/retail_big_boss_simulation.gd")
const MatchContract := preload("res://src/shared/match_contract.gd")
const Rng := preload("res://src/sim/deterministic_rng.gd")
const Simulation := preload("res://src/sim/game_simulation.gd")

var _failures: Array[String] = []


class RuntimeProbe extends RefCounted:
	var requests: Array[Dictionary] = []
	var finalized: Array[Dictionary] = []
	var next_id: int = 10000
	var pool_full: bool = false

	func allocate_common_projectile(request: Dictionary) -> Dictionary:
		requests.append(request.duplicate(true))
		if pool_full:
			return {
				"ok": true,
				"error": "",
				"allocated": false,
				"common_slot": -1,
				"projectile_id": 0,
			}
		next_id += 1
		return {
			"ok": true,
			"error": "",
			"allocated": true,
			"common_slot": requests.size() - 1,
			"projectile_id": next_id,
			"retained_animation_frame": 0,
			"retained_animation_period": 1.0,
			"retained_animation_countdown": 1.0,
		}

	func finalize_common_projectile(request: Dictionary) -> Dictionary:
		finalized.append(request.duplicate(true))
		return {"ok": true, "error": ""}

	func dispatch_retail_effect(
		_call_name: String,
		_payload: Dictionary,
		_rng_source: Variant
	) -> Dictionary:
		return {"ok": true}


func _initialize() -> void:
	_test_mirror_origins_and_ordered_two_group_burst()
	_test_full_pool_preserves_per_group_effect_and_rng_order()
	_test_level_one_hundred_is_the_hard_terminal()
	if _failures.is_empty():
		print("LEVEL 100 BOSS INTEGRATION TESTS PASSED")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _test_mirror_origins_and_ordered_two_group_burst() -> void:
	var generated := _generated_contract()
	var controller := Boss.new()
	_expect(
		controller.configure(generated, 4),
		"generated level-100 contract must recursively match the runtime: %s"
		% controller.get_last_error()
	)
	if not controller.configure(generated, 4):
		return
	var canonical := Boss.contract_for_id(Boss.LEVEL_100_CONTRACT_ID)
	_expect(
		canonical.initialization.group_modes == [4, 5, 6, 6, 7, 7]
		and canonical.initialization.mirror_x == true
		and canonical.path.opcode_allowlist == [0, 1, 2, 6, 7]
		and canonical.path.group_opcode_sequences["3"] == [6, 1]
		and canonical.aimed_fire.origin_groups == [
			{"group_id": 4, "path_opcodes": [6, 1]},
			{"group_id": 5, "path_opcodes": [6, 1]},
		]
		and canonical.opcode_2.hma_occupied_pixels
		== [671, 588, 773, 698, 659, 661]
		and canonical.aimed_fire.hma_occupied_pixels == [91, 90, 97, 87]
		and int(canonical.reward.base_score) == 10000000,
		"level 100 must retain its mirror signature, [6,1] origins, HMA, and reward"
	)
	var missing_v4_field := generated.duplicate(true)
	missing_v4_field.initialization.erase("mirror_x")
	missing_v4_field.opcode_2.erase("burst_groups")
	_expect(
		not Boss.new().configure(missing_v4_field, 4),
		"bosses v4 must reject simultaneous mirror and burst omission"
	)

	var level := _authored_level()
	var rng := Rng.new(100100)
	var runtime := RuntimeProbe.new()
	var entered: Dictionary = controller.enter(
		level,
		rng,
		_runtime_callbacks(runtime),
		_match_context()
	)
	_expect(
		bool(entered.get("ok", false)),
		"the exact level-100 authored payload must enter: %s"
		% controller.get_last_error()
	)
	if not bool(entered.get("ok", false)):
		return
	var groups := level.authored_lvd.groups as Array
	var entry_group := groups[0] as Dictionary
	var origin_four := groups[4] as Dictionary
	var origin_five := groups[5] as Dictionary
	var expected_entry_x := (
		float(level.authored_lvd.logical_width) / 2.0
		- float(entry_group.entry_origin_x)
		- 16.0
	)
	var snapshot := controller.snapshot()
	_expect(
		bool(snapshot.mirror_x)
		and is_equal_approx(float(snapshot.x), expected_entry_x)
		and String(snapshot.sheet) == "alien_big4_1"
		and float(snapshot.max_health) == 500.0
		and controller._aim_origins == [
			Vector2(-float(origin_four.entry_origin_x), float(origin_four.entry_origin_y) + 48.0),
			Vector2(-float(origin_five.entry_origin_x), float(origin_five.entry_origin_y) + 48.0),
		],
		"level-100 entry and both aimed origins must mirror around the boss base"
	)

	controller._fire_opcode_two_burst(1.0)
	var result: Dictionary = controller._result()
	_expect(runtime.finalized.size() == 8, "level 100 must emit both four-shot groups")
	if runtime.finalized.size() == 8:
		var group_ids: Array[int] = []
		var record_indices: Array[int] = []
		for projectile in runtime.finalized:
			group_ids.append(int(projectile.source_group_id))
			record_indices.append(int(projectile.source_record_index))
			_expect(
				String(projectile.enemy_sheet_id) == "alien_big4_1"
				and String(projectile.mask_id) == "alien_big4_1"
				and is_equal_approx(Vector2(
					float(projectile.velocity_x),
					float(projectile.velocity_y)
				).length(), 7.5),
				"every level-100 burst shot must use Big4 and speed 7.5"
			)
		_expect(
			group_ids == [2, 2, 2, 2, 3, 3, 3, 3]
			and record_indices == [3, 2, 1, 0, 3, 2, 1, 0]
			and float(runtime.finalized[0].velocity_x) < 0.0
			and float(runtime.finalized[4].velocity_x) > 0.0,
			"level 100 must fire group 2 reverse, then group 3 reverse, with mirrored vectors"
		)
	var events := result.get("events", []) as Array
	_expect(
		_event_count(events, "boss_burst_effect") == 2
		and _sound_count(events, "bigfire") == 2
		and _event_count(events, "boss_deferred_sound") == 2
		and _event_source_groups(events, "boss_burst_effect") == [2, 3]
		and _event_source_groups(events, "boss_deferred_sound") == [2, 3],
		"each ordered level-100 burst group must emit its own effect and sound chain"
	)


func _test_full_pool_preserves_per_group_effect_and_rng_order() -> void:
	var controller := Boss.new()
	if not controller.configure(_generated_contract(), 4):
		_expect(false, "full-pool level-100 controller should configure")
		return
	var rng := Rng.new(100101)
	var runtime := RuntimeProbe.new()
	runtime.pool_full = true
	var entered: Dictionary = controller.enter(
		_authored_level(),
		rng,
		_runtime_callbacks(runtime),
		_match_context()
	)
	if not bool(entered.get("ok", false)):
		_expect(false, "full-pool level-100 fixture should enter")
		return
	var draws_before := int(rng.snapshot().draw_count)
	controller._fire_opcode_two_burst(1.0)
	var result: Dictionary = controller._result()
	var events := result.get("events", []) as Array
	_expect(
		runtime.requests.size() == 2
		and runtime.finalized.is_empty()
		and int(rng.snapshot().draw_count) == draws_before + 6
		and _event_count(events, "boss_burst_effect") == 2
		and _sound_count(events, "bigfire") == 2
		and _event_count(events, "boss_deferred_sound") == 0
		and not controller.snapshot().blocked,
		"a full pool must try each group, consume only its effect/sound RNG, and omit deferred cues"
	)


func _test_level_one_hundred_is_the_hard_terminal() -> void:
	_expect(
		MatchContract.MAX_END_LEVEL == 3999,
		"the authoritative campaign boundary must be the retail level clamp"
	)
	var simulation := Simulation.new()
	if not simulation.configure(_simulation_config(100, 100, 100500)):
		_expect(false, "direct level-100 match should configure: %s" % simulation.get_last_error())
		return
	var final_snapshot := _defeat_active_boss(simulation)
	var result := final_snapshot.get("result", {}) as Dictionary
	var terminal := result.get("campaign_terminal", {}) as Dictionary
	_expect(
		String(final_snapshot.get("phase", "")) == Simulation.PHASE_COMPLETE
		and int(simulation._shared.score) == 10000000
		and int((final_snapshot.get("level_resolution", {}) as Dictionary).get(
			"pending_level_id", -1
		)) == 0
		and String(terminal.get("kind", "")) == "level_100"
		and bool(terminal.get("full_campaign_completed", false))
		and bool(terminal.get("credits_required", false))
		and int(terminal.get("level_100_score", 0)) == 10000000
		and not _snapshot_has_event(final_snapshot, "shop_started")
		and _event_level_count(final_snapshot, "get_ready_started", 101) == 0,
		"bounded level-100 match must award ten million and end with credits, no shop, and no level 101"
	)
	var beyond := Simulation.new()
	_expect(
		beyond.configure(_simulation_config(100, 101, 100101)),
		"the simulation must accept an endless level-101 boundary"
	)
	var credits_snapshot := _defeat_active_boss(beyond)
	var credits_block := credits_snapshot.get("credits", {}) as Dictionary
	_expect(
		String(credits_snapshot.get("phase", "")) == Simulation.PHASE_CREDITS
		and String(credits_block.get("milestone", "")) == "level_100"
		and int(credits_block.get("score", 0)) == 10000000
		and int(credits_block.get("next_level_id", 0)) == 101
		and _event_level_count(credits_snapshot, "get_ready_started", 101) == 0,
		"an endless match must roll the level-100 credits interstitial instead of ending"
	)
	beyond.set_input(0, 0)
	for _wait in range(Simulation.CREDITS_INTERSTITIAL_MIN_TICKS + 2):
		beyond.step()
	_expect(
		String(beyond.get_snapshot().get("phase", "")) == Simulation.PHASE_CREDITS,
		"the credits interstitial waits for input after its minimum display time"
	)
	beyond.set_input(0, Simulation.ACTION_CONFIRM)
	var continued := beyond.step()
	beyond.set_input(0, 0)
	_expect(
		String(continued.get("phase", "")) == Simulation.PHASE_GET_READY
		and int((continued.get("level_resolution", {}) as Dictionary).get(
			"pending_level_id", 0
		)) == 101
		and _event_level_count(continued, "get_ready_started", 101) == 1,
		"confirm must dismiss the credits and begin level 101"
	)


func _defeat_active_boss(simulation: Variant) -> Dictionary:
	_expect(simulation.set_input(0, Simulation.ACTION_FIRE), "level-100 defeat shot should be accepted")
	simulation.step()
	simulation.set_input(0, 0)
	var player_projectile: Dictionary = {}
	for value in simulation._projectiles:
		var projectile := value as Dictionary
		if String(projectile.get("owner_kind", "")) == "player":
			player_projectile = projectile
			break
	if player_projectile.is_empty():
		_expect(false, "level-100 defeat shot should allocate a player projectile")
		return simulation.get_snapshot()
	simulation._retail_big_boss._x = 400.0
	simulation._retail_big_boss._y = 180.0
	player_projectile.x_fp = 400 * Simulation.FP_ONE
	player_projectile.y_fp = 240 * Simulation.FP_ONE
	player_projectile.damage_fp = 5010 * Simulation.FP_ONE
	return simulation.step()


func _generated_contract() -> Dictionary:
	var document: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://content/bosses.json")
	)
	if not document is Dictionary:
		_expect(false, "bosses.json should parse")
		return {}
	return ((document as Dictionary).get("bosses", {}) as Dictionary).get(
		Boss.LEVEL_100_CONTRACT_ID,
		{}
	) as Dictionary


func _authored_level() -> Dictionary:
	var document: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://content/levels.json")
	)
	if document is Dictionary:
		return ((document as Dictionary).get("levels", []) as Array)[99].duplicate(true)
	return {}


func _runtime_callbacks(runtime: RuntimeProbe) -> Dictionary:
	return {
		"allocate_common_projectile": Callable(runtime, "allocate_common_projectile"),
		"finalize_common_projectile": Callable(runtime, "finalize_common_projectile"),
		"dispatch_retail_effect": Callable(runtime, "dispatch_retail_effect"),
	}


func _match_context() -> Dictionary:
	return {
		"mode": "solo",
		"coop_balance": "classic",
		"difficulty": "normal",
		"tick": 0,
		"now_ms": 0,
		"tick_scale": 1.0,
		"only_blue_coins_active": false,
	}


func _simulation_config(start_level: int, end_level: int, seed: int) -> Dictionary:
	return {
		"mode": "solo",
		"difficulty": "normal",
		"coop_balance": "classic",
		"collision_mode": "simple",
		"start_level": start_level,
		"end_level": end_level,
		"seed": seed,
	}


func _event_count(events: Array, kind: String) -> int:
	var count := 0
	for value in events:
		if String((value as Dictionary).get("kind", "")) == kind:
			count += 1
	return count


func _sound_count(events: Array, key: String) -> int:
	var count := 0
	for value in events:
		var event := value as Dictionary
		if String(event.get("kind", "")) == "sound" and String(event.get("key", "")) == key:
			count += 1
	return count


func _event_source_groups(events: Array, kind: String) -> Array[int]:
	var result: Array[int] = []
	for value in events:
		var event := value as Dictionary
		if String(event.get("kind", "")) == kind:
			result.append(int(event.get("source_group_id", -1)))
	return result


func _snapshot_has_event(snapshot: Dictionary, kind: String) -> bool:
	return _event_count(snapshot.get("events", []) as Array, kind) > 0


func _event_level_count(snapshot: Dictionary, kind: String, level_id: int) -> int:
	var count := 0
	for value in snapshot.get("events", []):
		var event := value as Dictionary
		if String(event.get("kind", "")) == kind and int(event.get("level_id", 0)) == level_id:
			count += 1
	return count


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

extends SceneTree

const Boss := preload("res://src/sim/retail_big_boss_simulation.gd")
const Rng := preload("res://src/sim/deterministic_rng.gd")
const Simulation := preload("res://src/sim/game_simulation.gd")

var _failures: Array[String] = []


class RuntimeProbe extends RefCounted:
	var requests: Array[Dictionary] = []
	var finalized: Array[Dictionary] = []
	var next_id: int = 7500

	func allocate_common_projectile(request: Dictionary) -> Dictionary:
		requests.append(request.duplicate(true))
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
	_test_contract_entry_and_burst()
	_test_configured_boundary_and_level_seventy_six_handoff()
	if _failures.is_empty():
		print("LEVEL 75 BOSS INTEGRATION TESTS PASSED")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _test_contract_entry_and_burst() -> void:
	var generated := _generated_contract(Boss.LEVEL_75_CONTRACT_ID)
	var controller := Boss.new()
	_expect(
		controller.configure(generated, 4),
		"generated level-75 contract must recursively match the runtime: %s"
		% controller.get_last_error()
	)
	if not controller.configure(generated, 4):
		return
	var canonical := Boss.contract_for_id(Boss.LEVEL_75_CONTRACT_ID)
	_expect(
		int(canonical.health.retail) == 613
		and int(canonical.reward.base_score) == 5000000
		and canonical.initialization.group_modes == [4, 5, 6, 7, 7]
		and canonical.initialization.mirror_x == false
		and canonical.opcode_2.hma_occupied_pixels
		== [441, 469, 487, 494, 496, 479]
		and canonical.aimed_fire.hma_occupied_pixels == [95, 91, 100, 0]
		and canonical.aimed_fire.origin_groups == [
			{"group_id": 3, "path_opcodes": [3]},
			{"group_id": 4, "path_opcodes": [3]},
		]
		and canonical.routing.explicit_end_level_75_policy
		== "complete_without_requesting_level_76",
		"level 75 must retain its exact health, HMA, origins, reward, and route"
	)
	var missing_v4_field := generated.duplicate(true)
	missing_v4_field.initialization.erase("mirror_x")
	missing_v4_field.opcode_2.erase("burst_groups")
	_expect(
		not Boss.new().configure(missing_v4_field, 4),
		"an explicit bosses-v4 contract must fail closed when v4 fields are omitted"
	)

	var level := _authored_level(75)
	var rng := Rng.new(750075)
	var runtime := RuntimeProbe.new()
	var entered: Dictionary = controller.enter(
		level,
		rng,
		_runtime_callbacks(runtime),
		_match_context()
	)
	_expect(
		bool(entered.get("ok", false)),
		"the exact level-75 authored payload must enter state 13: %s"
		% controller.get_last_error()
	)
	if not bool(entered.get("ok", false)):
		return
	var snapshot := controller.snapshot()
	_expect(
		String(snapshot.sheet) == "alien_big3_1"
		and float(snapshot.max_health) == 613.0
		and snapshot.mirror_x == false
		and controller._aim_origins.size() == 2,
		"level 75 must enter with Big3 rendering, 613 health, and two ordered origins"
	)

	controller._fire_opcode_two_burst(1.0)
	var result: Dictionary = controller._result()
	_expect(
		runtime.finalized.size() == 16,
		"level-75 opcode 2 must allocate all sixteen authored shots"
	)
	if runtime.finalized.size() == 16:
		var indices: Array[int] = []
		for projectile in runtime.finalized:
			indices.append(int(projectile.source_record_index))
			_expect(
				int(projectile.source_group_id) == 2
				and String(projectile.enemy_sheet_id) == "alien_big3_1"
				and String(projectile.mask_id) == "alien_big3_1"
				and is_equal_approx(Vector2(
					float(projectile.velocity_x),
					float(projectile.velocity_y)
				).length(), 4.6),
				"every level-75 burst projectile must use group 2, Big3, and speed 4.6"
			)
		var expected_indices: Array[int] = []
		for index in range(15, -1, -1):
			expected_indices.append(index)
		_expect(
			indices == expected_indices,
			"level-75 group 2 must traverse authored records 15 through 0"
		)
	var events := result.get("events", []) as Array
	_expect(
		_event_count(events, "boss_burst_effect") == 1
		and _sound_count(events, "bigfire") == 1
		and _event_count(events, "boss_deferred_sound") == 1
		and String((events[-2] as Dictionary).get("key", "")) == "bigfire"
		and String((events[-1] as Dictionary).get("kind", ""))
		== "boss_deferred_sound",
		"level-75 burst effects and direct/deferred sound must retain retail order"
	)


func _test_configured_boundary_and_level_seventy_six_handoff() -> void:
	var terminal := Simulation.new()
	if not terminal.configure(_simulation_config(75, 75, 757575)):
		_expect(false, "direct level-75 match should configure: %s" % terminal.get_last_error())
		return
	var terminal_snapshot := _defeat_active_boss(terminal, 6140)
	_expect(
		String(terminal_snapshot.get("phase", "")) == Simulation.PHASE_COMPLETE
		and int(terminal._shared.score) == 5000000
		and int((terminal_snapshot.get("level_resolution", {}) as Dictionary).get(
			"pending_level_id", -1
		)) == 0
		and not _snapshot_has_event(terminal_snapshot, "get_ready_started"),
		"configured end 75 must award five million and complete without level 76"
	)

	var extended := Simulation.new()
	if not extended.configure(_simulation_config(75, 100, 751000)):
		_expect(false, "extended level-75 match should configure: %s" % extended.get_last_error())
		return
	var handoff := _defeat_active_boss(extended, 6140)
	_expect(
		String(handoff.get("phase", "")) == Simulation.PHASE_GET_READY
		and int((handoff.get("level_resolution", {}) as Dictionary).get(
			"pending_level_id", 0
		)) == 76
		and _event_level_count(handoff, "get_ready_started", 76) == 1,
		"an extended campaign must hand boss 75 to level 76 exactly once"
	)


func _defeat_active_boss(simulation: Variant, damage_fp_units: int) -> Dictionary:
	_expect(simulation.set_input(0, Simulation.ACTION_FIRE), "boss defeat shot should be accepted")
	simulation.step()
	simulation.set_input(0, 0)
	var player_projectile: Dictionary = {}
	for value in simulation._projectiles:
		var projectile := value as Dictionary
		if String(projectile.get("owner_kind", "")) == "player":
			player_projectile = projectile
			break
	if player_projectile.is_empty():
		_expect(false, "boss defeat shot should allocate a player projectile")
		return simulation.get_snapshot()
	simulation._retail_big_boss._x = 400.0
	simulation._retail_big_boss._y = 180.0
	player_projectile.x_fp = 400 * Simulation.FP_ONE
	player_projectile.y_fp = 240 * Simulation.FP_ONE
	player_projectile.damage_fp = damage_fp_units * Simulation.FP_ONE
	return simulation.step()


func _generated_contract(contract_id: String) -> Dictionary:
	var document: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://content/bosses.json")
	)
	if not document is Dictionary:
		_expect(false, "bosses.json should parse")
		return {}
	return ((document as Dictionary).get("bosses", {}) as Dictionary).get(
		contract_id,
		{}
	) as Dictionary


func _authored_level(level_id: int) -> Dictionary:
	var document: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://content/levels.json")
	)
	if document is Dictionary:
		for value in (document as Dictionary).get("levels", []):
			if value is Dictionary and int((value as Dictionary).get("id", 0)) == level_id:
				return (value as Dictionary).duplicate(true)
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

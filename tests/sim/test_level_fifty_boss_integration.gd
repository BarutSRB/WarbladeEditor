extends SceneTree

const Boss := preload("res://src/sim/retail_big_boss_simulation.gd")
const Rng := preload("res://src/sim/deterministic_rng.gd")
const Simulation := preload("res://src/sim/game_simulation.gd")

var _failures: Array[String] = []


class RuntimeProbe extends RefCounted:
	var projectile_requests: Array[Dictionary] = []
	var finalized_projectiles: Array[Dictionary] = []
	var effect_calls: Array[Dictionary] = []
	var next_projectile_id: int = 1000

	func allocate_common_projectile(request: Dictionary) -> Dictionary:
		projectile_requests.append(request.duplicate(true))
		next_projectile_id += 1
		return {
			"ok": true,
			"error": "",
			"allocated": true,
			"common_slot": projectile_requests.size() - 1,
			"projectile_id": next_projectile_id,
			"retained_animation_frame": 0,
			"retained_animation_period": 1.0,
			"retained_animation_countdown": 1.0,
		}

	func finalize_common_projectile(request: Dictionary) -> Dictionary:
		finalized_projectiles.append(request.duplicate(true))
		return {"ok": true, "error": ""}

	func dispatch_retail_effect(
		call_name: String,
		payload: Dictionary,
		_rng_source: Variant
	) -> Dictionary:
		effect_calls.append({
			"call": call_name,
			"payload": payload.duplicate(true),
		})
		return {"ok": true}


func _initialize() -> void:
	_test_level_fifty_contract_and_opcode_three_semantics()
	_test_level_fifty_projectile_and_sound_bridge()
	_test_level_fifty_registry_entry_and_terminal_defeat()
	_test_level_fifty_extended_campaign_handoff()
	_test_explicit_level_forty_nine_boundary_remains_terminal()
	if _failures.is_empty():
		print("LEVEL 50 BOSS INTEGRATION TESTS PASSED")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _test_level_fifty_contract_and_opcode_three_semantics() -> void:
	var contract := Boss.contract_for_id(Boss.LEVEL_50_CONTRACT_ID)
	var bosses_document: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://content/bosses.json")
	)
	if bosses_document is Dictionary:
		var generated_bosses := (bosses_document as Dictionary).get(
			"bosses",
			{}
		) as Dictionary
		for contract_id in [Boss.CONTRACT_ID, Boss.LEVEL_50_CONTRACT_ID]:
			var generated_controller := Boss.new()
			_expect(
				generated_controller.configure(generated_bosses.get(
					contract_id,
					{}
				) as Dictionary),
				"generated %s should recursively equal the controller's full exact contract: %s"
				% [contract_id, generated_controller.get_last_error()]
			)
	else:
		_expect(false, "the generated boss contract document should parse")
	_expect(
		int(contract.get("level_id", 0)) == 50
		and int((contract.get("health", {}) as Dictionary).get("retail", 0)) == 500
		and int((contract.get("health", {}) as Dictionary).get(
			"damage_divisor",
			0
		)) == 10
		and int((contract.get("aimed_fire", {}) as Dictionary).get(
			"runtime_rng_upper",
			0
		)) == 1377
		and int((contract.get("opcode_2", {}) as Dictionary).get(
			"dynamic_record_count",
			0
		)) == 10,
		"the level-50 controller contract should expose its exact health, timer, divisor, and dynamic burst count"
	)
	var opcode_three := (
		(contract.get("path", {}) as Dictionary).get("opcode_3", {}) as Dictionary
	)
	_expect(
		String(opcode_three.get("effect", "")) == "set_mode_7_aim_enabled"
		and int(opcode_three.get("rng_draws", -1)) == 0
		and not bool(opcode_three.get("loads_acceleration", true))
		and not bool(opcode_three.get("resets_progress", true))
		and not bool((contract.get("path", {}) as Dictionary).get(
			"point_zero_opcode_dispatch",
			true
		)),
		"the exact path contract should pin opcode 3 and point-zero restart semantics"
	)
	var malformed := contract.duplicate(true)
	malformed.aimed_fire.runtime_rng_upper = 1376
	var rejected := Boss.new()
	_expect(
		not rejected.configure(malformed),
		"level-50 whole-contract validation should reject a changed aimed-fire RNG bound"
	)

	var controller := Boss.new()
	if not controller.configure(contract):
		_expect(false, "the canonical level-50 controller contract should configure")
		return
	var level := _authored_level(50)
	if level.is_empty():
		_expect(false, "the level-50 integration fixture should load authored level 50")
		return
	var rng := Rng.new(505003)
	var runtime := RuntimeProbe.new()
	var entered: Dictionary = controller.enter(
		level,
		rng,
		{
			"allocate_common_projectile": Callable(
				runtime,
				"allocate_common_projectile"
			),
			"finalize_common_projectile": Callable(
				runtime,
				"finalize_common_projectile"
			),
			"dispatch_retail_effect": Callable(
				runtime,
				"dispatch_retail_effect"
			),
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
	if not bool(entered.get("ok", false)):
		_expect(
			false,
			"the canonical authored level 50 should enter state 13: %s"
			% controller.get_last_error()
		)
		return

	# Point 19 dispatches opcode 3 by advancing to point 20. Preserve deliberately
	# nonzero acceleration/progress values so every no-op part of the opcode is
	# observable, and compare the shared-generator draw count across the call.
	controller._current_group_id = 1
	controller._path_index = 19
	controller._path_progress = 2.0
	controller._velocity_x = 0.0
	controller._velocity_y = 0.0
	controller._acceleration_x = 0.125
	controller._acceleration_y = -0.25
	controller._aim_enabled = false
	var draws_before_opcode_three := int(rng.snapshot().draw_count)
	controller._update_path(1.0)
	_expect(
		controller._aim_enabled
		and int(controller._path_index) == 20
		and float(controller._path_progress) == 3.0
		and float(controller._acceleration_x) == 0.125
		and float(controller._acceleration_y) == -0.25
		and int(rng.snapshot().draw_count) == draws_before_opcode_three,
		"opcode 3 should only enable aimed fire, with no RNG, acceleration load, or progress reset"
	)

	controller._aim_enabled = false
	var draws_before_restart := int(rng.snapshot().draw_count)
	var requests_before_restart := runtime.projectile_requests.size()
	controller._restart_loop_group()
	_expect(
		int(controller._path_index) == 0
		and float(controller._path_progress) == 0.0
		and int(rng.snapshot().draw_count) == draws_before_restart
		and runtime.projectile_requests.size() == requests_before_restart,
		"loop restart should load point zero without dispatching its authored opcode 2"
	)

	controller._fire_opcode_two_burst(1.0)
	_expect(
		runtime.finalized_projectiles.size() == 10,
		"level 50 opcode 2 should dynamically emit ten reverse-order projectiles"
	)
	if runtime.finalized_projectiles.size() == 10:
		var first := runtime.finalized_projectiles[0]
		var last := runtime.finalized_projectiles[-1]
		var speed := Vector2(
			float(first.get("velocity_x", 0.0)),
			float(first.get("velocity_y", 0.0))
		).length()
		_expect(
			int(first.get("source_record_index", -1)) == 9
			and int(last.get("source_record_index", -1)) == 0
			and String(first.get("enemy_sheet_id", "")) == "alien_big2_1"
			and is_equal_approx(speed, 5.0),
			"level-50 burst order, sheet, and speed should come from the active contract"
		)


func _test_level_fifty_projectile_and_sound_bridge() -> void:
	var simulation := Simulation.new()
	if not simulation.configure(_simulation_config(50, 50, 505014)):
		_expect(
			false,
			"the level-50 projectile bridge should configure: %s"
			% simulation.get_last_error()
		)
		return
	simulation._events.clear()
	simulation._retail_global_sound_gate = 0
	simulation._retail_big_boss._fire_opcode_two_burst(
		simulation._boss_tick_scale()
	)
	simulation._ingest_boss_controller_result(
		simulation._retail_big_boss._result()
	)
	simulation._advance_retail_global_sound_gate()
	var boss_projectiles: Array[Dictionary] = []
	for projectile_value in simulation._projectiles:
		var projectile := projectile_value as Dictionary
		if String(projectile.get("owner_kind", "")) == "boss":
			boss_projectiles.append(projectile)
	var sounds: Array[String] = []
	for event_value in simulation._events:
		var event := event_value as Dictionary
		if String(event.get("kind", "")) == "sound_cue":
			sounds.append(String(event.get("key", "")))
	_expect(
		boss_projectiles.size() == 10
		and sounds.has("bigfire")
		and sounds.has("alienshoot2")
		and not simulation._boss_runtime_blocked,
		"the active level-50 bridge should finalize all ten shots and preserve direct/deferred sound routing"
	)
	if boss_projectiles.size() == 10:
		var first := boss_projectiles[0]
		_expect(
			String(first.get("enemy_sheet", "")) == "alien_big2_1"
			and String(first.get("mask_id", "")) == "alien_big2_1"
			and String(first.get("sprite_sheet_id", "")) == "alien_big2_1"
			and (first.get("source_rect", []) as Array) == [512, 0, 32, 32],
			"level-50 finalized projectiles should publish the active big2 sheet and unchanged wire geometry"
		)


func _test_level_fifty_registry_entry_and_terminal_defeat() -> void:
	var simulation := Simulation.new()
	if not simulation.configure(_simulation_config(50, 50, 505050)):
		_expect(
			false,
			"direct level-50 simulation should configure: %s"
			% simulation.get_last_error()
		)
		return
	var initial := simulation.get_snapshot()
	_expect(
		simulation._boss_runtimes_by_level.has(25)
		and simulation._boss_runtimes_by_level.has(50)
		and String(simulation._boss_contract.get("id", ""))
		== Boss.LEVEL_50_CONTRACT_ID
		and int(initial.get("level_id", 0)) == 50
		and String(initial.get("phase", "")) == Simulation.PHASE_LEVEL
		and bool((initial.get("boss", {}) as Dictionary).get("active", false))
		and float((initial.get("boss", {}) as Dictionary).get("max_health", 0.0))
		== 500.0
		and String((initial.get("boss", {}) as Dictionary).get("sheet", ""))
		== "alien_big2_1"
		and (initial.get("enemies", []) as Array).is_empty(),
		"the registry should select the level-50 contract while keeping generic enemies out of state 13"
	)

	simulation._shared.score_multiplier = 2
	simulation._shared.score_multiplier_ticks = 100
	var projectile := _fire_public_projectile(simulation)
	if projectile.is_empty():
		return
	simulation._retail_big_boss._x = 400.0
	simulation._retail_big_boss._y = 180.0
	projectile.x_fp = 400 * Simulation.FP_ONE
	projectile.y_fp = 240 * Simulation.FP_ONE
	projectile.damage_fp = 5010 * Simulation.FP_ONE
	var defeated := simulation.step()
	var kinds := _event_kinds(defeated)
	_expect(
		String(defeated.get("phase", "")) == Simulation.PHASE_COMPLETE
		and int((defeated.get("result", {}) as Dictionary).get(
			"level_reached",
			0
		)) == 50
		and int((defeated.get("level_resolution", {}) as Dictionary).get(
			"pending_level_id",
			-1
		)) == 0
		and int(simulation._shared.score) == 2000000
		and kinds.has("boss_reward")
		and kinds.has("boss_level_complete_mark")
		and kinds.has("boss_defeated")
		and kinds.has("level_completed")
		and not kinds.has("get_ready_started"),
		"strict-negative level-50 defeat should award its dynamic reward and complete without requesting level 51"
	)
	var replay := simulation.get_replay()
	var frames := replay.get("frames", []) as Array
	_expect(
		int(replay.get("version", 0)) == Simulation.REPLAY_VERSION
		and not frames.is_empty()
		and String((frames[-1] as Dictionary).get("state_hash", ""))
		== simulation.state_hash(),
		"level-50 terminal state should retain the existing replay and hash wire shapes"
	)


func _test_level_fifty_extended_campaign_handoff() -> void:
	var simulation := Simulation.new()
	if not simulation.configure(_simulation_config(50, 62, 505162)):
		_expect(
			false,
			"extended level-50 simulation should configure: %s"
			% simulation.get_last_error()
		)
		return
	var projectile := _fire_public_projectile(simulation)
	if projectile.is_empty():
		return
	simulation._retail_big_boss._x = 400.0
	simulation._retail_big_boss._y = 180.0
	projectile.x_fp = 400 * Simulation.FP_ONE
	projectile.y_fp = 240 * Simulation.FP_ONE
	projectile.damage_fp = 5010 * Simulation.FP_ONE
	var defeated := simulation.step()
	_expect(
		String(defeated.get("phase", "")) == Simulation.PHASE_GET_READY
		and int((defeated.get("level_resolution", {}) as Dictionary).get(
			"pending_level_id",
			0
		)) == 51
		and _event_count(defeated, "get_ready_started", 51) == 1
		and not (defeated.get("result", {}) as Dictionary).get("completed", false),
		"an extended campaign should hand level 50 off to level 51 exactly once"
	)


func _test_explicit_level_forty_nine_boundary_remains_terminal() -> void:
	var simulation := Simulation.new()
	if not simulation.configure(_simulation_config(49, 49, 504949)):
		_expect(
			false,
			"explicit level-49 simulation should configure: %s"
			% simulation.get_last_error()
		)
		return
	# This is the terminal-shop routing boundary reached by level 49's recurring
	# mode-three result flow. Level 50 exists in the catalog, but explicit end 49
	# must keep the zero sentinel and complete instead of constructing Get Ready.
	simulation._phase = Simulation.PHASE_SHOP
	simulation._pending_level_id = 0
	simulation._events.clear()
	simulation._route_after_shop()
	var terminal := simulation.get_snapshot()
	_expect(
		String(terminal.get("phase", "")) == Simulation.PHASE_COMPLETE
		and int((terminal.get("result", {}) as Dictionary).get(
			"level_reached",
			0
		)) == 49
		and int((terminal.get("level_resolution", {}) as Dictionary).get(
			"pending_level_id",
			-1
		)) == 0
		and not _event_kinds({"events": simulation._events}).has("get_ready_started"),
		"an explicit level-49 boundary should remain terminal even when level 50 is authored"
	)


func _authored_level(level_id: int) -> Dictionary:
	var parsed: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://content/levels.json")
	)
	if not parsed is Dictionary:
		return {}
	for level_value in (parsed as Dictionary).get("levels", []):
		if level_value is Dictionary and int((level_value as Dictionary).get(
			"id",
			0
		)) == level_id:
			return (level_value as Dictionary).duplicate(true)
	return {}


func _simulation_config(start_level: int, end_level: int, seed: int) -> Dictionary:
	return {
		"mode": "solo",
		"difficulty": "normal",
		"coop_balance": "classic",
		"collision_mode": "simple",
		"seed": seed,
		"start_level": start_level,
		"end_level": end_level,
		"record_replay": true,
	}


func _fire_public_projectile(simulation) -> Dictionary:
	_expect(
		simulation.set_input(0, Simulation.ACTION_FIRE),
		"level-50 public fire input should be accepted"
	)
	simulation.step()
	simulation.set_input(0, 0)
	for projectile_value in simulation._projectiles:
		var projectile := projectile_value as Dictionary
		if String(projectile.get("owner_kind", "")) == "player":
			return projectile
	_expect(false, "level-50 public fire should allocate a player projectile")
	return {}


func _event_kinds(snapshot: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for event_value in snapshot.get("events", []):
		result.append(String((event_value as Dictionary).get("kind", "")))
	return result


func _event_count(snapshot: Dictionary, kind: String, level_id: int) -> int:
	var count := 0
	for event_value in snapshot.get("events", []):
		var event := event_value as Dictionary
		if (
			String(event.get("kind", "")) == kind
			and int(event.get("level_id", 0)) == level_id
		):
			count += 1
	return count


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

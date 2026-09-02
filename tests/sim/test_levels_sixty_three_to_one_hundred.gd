extends SceneTree

const Catalog := preload("res://src/sim/content_catalog.gd")
const Rng := preload("res://src/sim/deterministic_rng.gd")
const Simulation := preload("res://src/sim/game_simulation.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_mode_six_projectile_rng_and_rewards()
	_test_mode_six_uses_retail_top_left_side_predicate()
	_test_mode_six_entry_and_terminal_opcodes()
	_test_nonterminal_opcode_one_resumes_after_strict_hold()
	_test_level_ninety_four_opcode_two_is_inert()
	_test_late_catalog_membership()
	if _failures.is_empty():
		print("LEVELS 63-100 RUNTIME TESTS PASSED")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _test_mode_six_projectile_rng_and_rewards() -> void:
	var simulation: Variant = _fallback_simulation()
	if simulation == null:
		return
	_install_mode_six_level(simulation)
	var enemy := _ordinary_enemy(9001, 500 * Simulation.FP_ONE)
	var predictor := Rng.new()
	predictor.restore(simulation._rng.snapshot())
	var component := predictor.next_float32(-1.5, 0.0)
	var expected_velocity := roundi(
		Rng._float32(component * 1.0) * Simulation.FP_ONE
	)
	var draws_before := int(simulation._rng.snapshot().draw_count)
	simulation._fire_enemy_projectile(enemy)
	_expect(
		simulation._projectiles.size() == 1
		and int(simulation._rng.snapshot().draw_count) == draws_before + 1
		and int(simulation._projectiles[0].velocity_x_fp) == expected_velocity
		and int(simulation._projectiles[0].velocity_x_fp) <= 0
		and int(simulation._projectiles[0].velocity_y_fp) == 282624,
		"mode 6 must consume one post-allocation target-facing lateral draw and retain base vertical speed"
	)
	for slot_value in simulation._common_projectile_slots:
		(slot_value as Dictionary).active = true
	var projectile_count: int = simulation._projectiles.size()
	draws_before = int(simulation._rng.snapshot().draw_count)
	simulation._fire_enemy_projectile(enemy)
	_expect(
		simulation._projectiles.size() == projectile_count
		and int(simulation._rng.snapshot().draw_count) == draws_before,
		"a full common pool must reject a mode-6 shot before its lateral RNG draw"
	)
	_expect(
		not simulation._level_is_retail_special(63),
		"mode 6 must remain outside the retail special-level classifier"
	)
	var progression: Dictionary = simulation._progression_for_seat(0)
	progression.rockets = 0
	simulation._rocket_fired_this_level = false
	simulation._alien_projectile_processed_this_level = true
	simulation._events.clear()
	simulation._award_final_kill_rockets(0)
	_expect(
		int(progression.rockets) == 10
		and _event_count(simulation._events, "final_kill_reward") == 1,
		"mode 6 must retain the ordinary final-kill rocket reward"
	)
	simulation._group_totals = {0: 1}
	simulation._group_kill_counts = {0: 0}
	var completion_score: int = simulation._award_group_or_cohort_completion({
		"group_id": 0,
		"kill_cohort_id": 0,
		"x_fp": 0,
		"y_fp": 0,
		"authored_state": "hold",
	})
	_expect(
		completion_score == Simulation.GROUP_COMPLETION_SCORE,
		"mode 6 must use ordinary mode-1 group completion scoring"
	)


func _test_mode_six_uses_retail_top_left_side_predicate() -> void:
	var simulation: Variant = _fallback_simulation()
	if simulation == null:
		return
	_install_mode_six_level(simulation)
	var enemy := _ordinary_enemy(9003, 400 * Simulation.FP_ONE)
	var player := simulation._players[0] as Dictionary
	player.x_fp = int(enemy.x_fp)
	_expect_mode_six_lateral_draw(
		simulation,
		enemy,
		true,
		"equal centers still put the wider fighter's retail left edge left of the alien"
	)
	player.x_fp = int(enemy.x_fp) + 3 * Simulation.FP_ONE
	_expect_mode_six_lateral_draw(
		simulation,
		enemy,
		true,
		"a fighter center three pixels right remains left by retail top-left comparison"
	)
	player.x_fp = int(enemy.x_fp) + 4 * Simulation.FP_ONE
	_expect_mode_six_lateral_draw(
		simulation,
		enemy,
		false,
		"equal retail top-left X at a four-pixel center offset selects the non-left interval"
	)


func _expect_mode_six_lateral_draw(
	simulation: Variant,
	enemy: Dictionary,
	expect_left_interval: bool,
	message: String
) -> void:
	var predictor := Rng.new()
	predictor.restore(simulation._rng.snapshot())
	var component := (
		predictor.next_float32(-1.5, 0.0)
		if expect_left_interval
		else predictor.next_float32(0.0, 1.5)
	)
	var expected_velocity := roundi(
		Rng._float32(component * 1.0) * Simulation.FP_ONE
	)
	var draws_before := int(simulation._rng.snapshot().draw_count)
	var actual_velocity := int(
		simulation._ordinary_enemy_projectile_lateral_velocity_fp(enemy)
	)
	_expect(
		actual_velocity == expected_velocity
		and int(simulation._rng.snapshot().draw_count) == draws_before + 1,
		message
	)


func _test_mode_six_entry_and_terminal_opcodes() -> void:
	var simulation: Variant = _fallback_simulation()
	if simulation == null:
		return
	_install_mode_six_level(simulation)
	var entry_enemy := _path_enemy(63, 1, 100)
	simulation._advance_authored_path(entry_enemy)
	_expect(
		String(entry_enemy.authored_state) == "formation"
		and int(entry_enemy.behavior_state_id) == 2
		and not bool(entry_enemy.dead),
		"mode-6 terminal opcode 1 must enter ordinary state 2"
	)
	var terminal_enemy := _path_enemy(63, 6, 1)
	var draws_before := int(simulation._rng.snapshot().draw_count)
	simulation._level_total_entities = 1
	simulation._level_escaped_entities = 0
	simulation._level_killed_entities = 0
	simulation._level_resolved = false
	simulation._advance_authored_path(terminal_enemy)
	_expect(
		bool(terminal_enemy.dead)
		and int(simulation._level_escaped_entities) == 1
		and int(simulation._rng.snapshot().draw_count) == draws_before,
		"mode-6 opcode 6 must deactivate through the ordinary zero-RNG escape path"
	)


func _test_nonterminal_opcode_one_resumes_after_strict_hold() -> void:
	var simulation: Variant = _fallback_simulation()
	if simulation == null:
		return
	var enemy := _path_enemy(74, 1, 1)
	enemy.level_mode_id = 3
	enemy.path_points.append({
		"acceleration_x_milli": 250,
		"acceleration_y_milli": -125,
		"opcode": 0,
		"duration_threshold_ticks": 5,
	})
	var draws_before := int(simulation._rng.snapshot().draw_count)
	simulation._advance_authored_path(enemy)
	_expect(
		String(enemy.authored_state) == "entry"
		and int(enemy.behavior_state_id) == 1
		and int(enemy.path_index) == 1
		and int(enemy.path_progress_sixths) == 0
		and int(enemy.velocity_x_fp) == 0
		and int(enemy.velocity_y_fp) == 0
		and int(enemy.acceleration_x_fp) == 0
		and int(enemy.acceleration_y_fp) == 0,
		"nonterminal opcode 1 must remain in state-1 path dispatch as a zero-motion hold"
	)
	simulation._update_authored_enemy(enemy)
	_expect(
		int(enemy.path_index) == 1
		and int(enemy.path_progress_ticks) == 1
		and int(enemy.x_fp) == 400 * Simulation.FP_ONE
		and int(enemy.y_fp) == 100 * Simulation.FP_ONE,
		"opcode-1 progress equality must preserve the zero-motion hold"
	)
	simulation._update_authored_enemy(enemy)
	_expect(
		int(enemy.path_index) == 2
		and int(enemy.path_progress_ticks) == 0
		and int(enemy.acceleration_x_fp) == 16384
		and int(enemy.acceleration_y_fp) == -8192
		and int(simulation._rng.snapshot().draw_count) == draws_before,
		"opcode-1 strict N+1 crossing must resume the next authored segment with zero RNG"
	)


func _test_level_ninety_four_opcode_two_is_inert() -> void:
	var simulation: Variant = _fallback_simulation()
	if simulation == null:
		return
	simulation._level_id = 94
	simulation._levels_by_id[94] = {
		"id": 94,
		"title": "",
		"authored_lvd": {"level_mode_id": 1},
	}
	var enemy := _path_enemy(94, 2, 1)
	var draws_before := int(simulation._rng.snapshot().draw_count)
	var events_before: int = simulation._events.size()
	var projectiles_before: int = simulation._projectiles.size()
	simulation._advance_authored_path(enemy)
	_expect(
		int(enemy.path_index) == 1
		and not bool(enemy.dead)
		and int(simulation._rng.snapshot().draw_count) == draws_before
		and simulation._events.size() == events_before
		and simulation._projectiles.size() == projectiles_before,
		"level-94 opcode 2 must be a deterministic scan with zero observable effects"
	)


func _test_late_catalog_membership() -> void:
	var catalog := Catalog.load_catalog()
	_expect(
		bool(catalog.get("ok", false)),
		"the generated 1-100 catalog should load: %s"
		% String(catalog.get("error", "unknown error"))
	)
	if not bool(catalog.get("ok", false)):
		return
	var levels: Array = catalog.levels
	_expect(levels.size() == 100, "the runtime catalog must expose all 100 levels")
	var level_eighty := levels[79] as Dictionary
	var level_ninety_four := levels[93] as Dictionary
	var group_modes: Array[int] = []
	for group_value in level_eighty.authored_lvd.groups:
		group_modes.append(int((group_value as Dictionary).group_mode_id))
	_expect(
		group_modes == [3, 3, 1, 1, 1, 1, 1, 1, 1, 1],
		"only level-80 groups 0/1 may use ordinary-fallthrough group mode 3"
	)
	var opcode_two_count := 0
	for group_value in level_ninety_four.authored_lvd.groups:
		var group := group_value as Dictionary
		for point_index in range((group.path_points as Array).size()):
			if int((group.path_points[point_index] as Dictionary).opcode) == 2:
				opcode_two_count += 1
				_expect(
					point_index == 1 and int(group.group_mode_id) == 1,
					"level-94 opcode 2 must remain path index 1 in a mode-1 group"
				)
	_expect(opcode_two_count == 4, "level 94 must retain exactly four inert opcode-2 scans")
	for level_id in Catalog.MODE_SIX_LEVEL_IDS:
		var level := levels[level_id - 1] as Dictionary
		_expect(
			int(level.authored_lvd.level_mode_id) == 6
			and bool(level.level_mode_runtime.ordinary_projectile_aim.enabled),
			"each exact mode-6 level must bind the validated lateral-shot runtime"
		)


func _install_mode_six_level(simulation: Variant) -> void:
	simulation._level_id = 63
	simulation._levels_by_id[63] = {
		"id": 63,
		"title": "",
		"authored_lvd": {"level_mode_id": 6},
		"level_mode_runtime": {
			"ordinary_projectile_aim": {
				"enabled": true,
				"horizontal_speed_magnitude_rng_fp": [0, 98304],
			},
			"ordinary_projectile_vertical_speed": {
				"base_multiplier_fp": 65536,
				"accelerated_multiplier_fp": 81920,
				"accelerated_when_level_strictly_above": 500,
			},
		},
	}


func _ordinary_enemy(entity_id: int, x_fp: int) -> Dictionary:
	return {
		"id": entity_id,
		"x_fp": x_fp,
		"y_fp": 100 * Simulation.FP_ONE,
		"projectile_speed_fp": 282624,
		"sprite": "alien001",
		"level_mode_id": 6,
		"authored_state": "hold",
	}


func _path_enemy(level_id: int, opcode: int, duration: int) -> Dictionary:
	return {
		"id": level_id * 100,
		"x_fp": 400 * Simulation.FP_ONE,
		"y_fp": 100 * Simulation.FP_ONE,
		"dead": false,
		"authored_state": "entry",
		"behavior_state_id": 1,
		"level_mode_id": 6 if level_id == 63 else 1,
		"mirror_x": false,
		"path_index": 0,
		"path_progress_ticks": 1,
		"path_progress_sixths": 6,
		"velocity_x_fp": 123,
		"velocity_y_fp": 456,
		"acceleration_x_fp": 0,
		"acceleration_y_fp": 0,
		"path_points": [
			{
				"acceleration_x_milli": 0,
				"acceleration_y_milli": 0,
				"opcode": 0,
				"duration_threshold_ticks": 1,
			},
			{
				"acceleration_x_milli": 0,
				"acceleration_y_milli": 0,
				"opcode": opcode,
				"duration_threshold_ticks": duration,
			},
		],
	}


func _fallback_simulation(mode: String = "solo") -> Variant:
	var simulation := Simulation.new()
	var configured := simulation.configure({
		"mode": mode,
		"difficulty": "normal",
		"coop_balance": "classic",
		"collision_mode": "simple",
		"start_level": 1,
		"end_level": 5,
		"seed": 630094,
		"content_base_path": "res://missing-levels-63-100-content",
		"allow_fallback_content": true,
	})
	_expect(
		configured,
		"late-level fixture should configure: %s" % simulation.get_last_error()
	)
	return simulation if configured else null


func _event_count(events: Array, kind: String) -> int:
	var count := 0
	for event_value in events:
		if String((event_value as Dictionary).get("kind", "")) == kind:
			count += 1
	return count


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

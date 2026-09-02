extends SceneTree

const Simulation := preload("res://src/sim/game_simulation.gd")
const Catalog := preload("res://src/sim/content_catalog.gd")
const Rng := preload("res://src/sim/deterministic_rng.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_entry_terminal_preserves_integrated_motion()
	_test_platform_oscillator_and_strict_bounds()
	_test_tail_cutoff_rng_policy()
	_test_state_four_strict_roaming_bounds()
	_test_state_six_vectors_wraps_and_steering_edges()
	_test_state_ten_strict_top_and_flip_edges()
	_test_state_two_has_no_timer_a_fire()
	_test_first_five_lvd_scores_and_completion_awards()
	_test_ordinary_enemy_body_contact_is_inert()
	_test_freeze_and_scoop_runtime_contracts()
	_test_final_kill_rockets_and_watchdogs()
	_test_render_watchdog_refresh_contract()
	_test_pickup_scan_owner_contract()
	_test_death_is_accounted_at_the_respawn_deadline()
	_test_level_resolution_and_get_ready_deadlines()
	_test_level_four_shop_warp_contract()
	_test_warp_bonus_and_malfunction_contracts()
	_test_rank_promotion_runtime_contract()
	_test_first_shop_effect_contracts()
	_test_bonus_catalog_and_drop_contract()
	_test_retail_bonus_effect_contracts()
	_test_captive_weapon_mapping_and_projectile_animation()
	_test_mirror_runtime_contract()
	_test_drunk_and_bonus_mode_boundaries()
	if _failures.is_empty():
		print("FIRST-FIVE FIDELITY TESTS PASSED")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _test_entry_terminal_preserves_integrated_motion() -> void:
	var simulation = _new_simulation(1)
	_spawn_authored_entities(simulation)
	var enemy: Dictionary = simulation._enemies[0]
	enemy.x_fp = 123 * Simulation.FP_ONE + 17
	enemy.y_fp = -41 * Simulation.FP_ONE + 29
	enemy.velocity_x_fp = 34567
	enemy.velocity_y_fp = -45678
	simulation._finish_authored_entry(enemy)
	_expect(
		String(enemy.authored_state) == "formation"
		and int(enemy.behavior_state_id) == 2,
		"entry terminal opcode should change an ordinary alien to retail state 2"
	)
	_expect(
		int(enemy.x_fp) == 123 * Simulation.FP_ONE + 17
		and int(enemy.y_fp) == -41 * Simulation.FP_ONE + 29
		and int(enemy.velocity_x_fp) == 34567
		and int(enemy.velocity_y_fp) == -45678,
		"entry terminal opcode must not snap position or zero integrated velocity"
	)


func _test_platform_oscillator_and_strict_bounds() -> void:
	var simulation = _new_simulation(1)
	for tick in range(15):
		simulation._update_platform_oscillator()
	_expect(
		int(simulation._platform_x_fp) == 560295
		and int(simulation._platform_velocity_x_fp) == 42593,
		"platform tick 15 should preserve the executable's position-before-acceleration order"
	)
	simulation._update_platform_oscillator()
	_expect(
		int(simulation._platform_x_fp) == 9 * Simulation.FP_ONE
		and int(simulation._platform_velocity_x_fp) == -43248,
		"platform tick 16 should clamp at +9 and reverse the post-acceleration velocity"
	)

	simulation._platform_x_fp = 9 * Simulation.FP_ONE
	simulation._platform_velocity_x_fp = 0
	simulation._platform_acceleration_x_fp = 0
	simulation._update_platform_oscillator()
	_expect(
		int(simulation._platform_x_fp) == 9 * Simulation.FP_ONE,
		"platform should survive exact equality at its +9 bound"
	)
	simulation._platform_x_fp = 9 * Simulation.FP_ONE + 1
	simulation._update_platform_oscillator()
	_expect(
		int(simulation._platform_x_fp) == 9 * Simulation.FP_ONE,
		"platform should clamp only after moving one fixed unit beyond +9"
	)
	simulation._platform_x_fp = -9 * Simulation.FP_ONE - 1
	simulation._update_platform_oscillator()
	_expect(
		int(simulation._platform_x_fp) == -9 * Simulation.FP_ONE,
		"platform should clamp only after moving one fixed unit beyond -9"
	)


func _test_tail_cutoff_rng_policy() -> void:
	var solo = _new_simulation(1, "solo", "normal", 73)
	var coop = _new_simulation(1, "coop", "normal", 73)
	_expect(
		int(solo._tail_cutoff) >= 2 and int(solo._tail_cutoff) <= 5,
		"solo should draw one shared state-4 tail cutoff in the inclusive range 2...5"
	)
	_expect(
		int(coop._tail_cutoff) == 0,
		"simultaneous co-op should force the state-4 tail cutoff to zero"
	)
	_expect(
		int(solo._rng.draw_count) == 552
		and int(coop._rng.draw_count) == 551,
		"startup should draw the warp-malfunction interval first, then only solo should consume the tail-cutoff draw"
	)


func _test_state_four_strict_roaming_bounds() -> void:
	var simulation = _new_simulation(1)
	_spawn_authored_entities(simulation)
	var enemy: Dictionary = simulation._enemies[0]
	_prepare_state_four_enemy(enemy)
	enemy.x_fp = (Simulation.FIELD_WIDTH + 48) * Simulation.FP_ONE
	simulation._update_state_four(enemy)
	_expect(
		int(enemy.x_fp) == (Simulation.FIELD_WIDTH + 48) * Simulation.FP_ONE,
		"state 4 should survive equality at center x=848"
	)
	enemy.x_fp = (Simulation.FIELD_WIDTH + 48) * Simulation.FP_ONE + 1
	simulation._update_state_four(enemy)
	_expect(
		int(enemy.x_fp) == -16 * Simulation.FP_ONE,
		"state 4 should wrap right to center x=-16 only beyond x=848"
	)
	enemy.x_fp = -16 * Simulation.FP_ONE - 1
	simulation._update_state_four(enemy)
	_expect(
		int(enemy.x_fp) == (Simulation.FIELD_WIDTH + 48) * Simulation.FP_ONE,
		"state 4 should wrap left to center x=848 only below x=-16"
	)

	_prepare_state_four_enemy(enemy)
	enemy.y_fp = (Simulation.FIELD_HEIGHT + 31) * Simulation.FP_ONE
	simulation._update_state_four(enemy)
	_expect(
		int(enemy.y_fp) == (Simulation.FIELD_HEIGHT + 31) * Simulation.FP_ONE,
		"state 4 should survive equality at center y=631"
	)
	enemy.y_fp = (Simulation.FIELD_HEIGHT + 31) * Simulation.FP_ONE + 1
	simulation._update_state_four(enemy)
	_expect(
		int(enemy.y_fp) == -34 * Simulation.FP_ONE,
		"state 4 should wrap to center y=-34 only below the strict bottom bound"
	)

	_prepare_state_four_enemy(enemy)
	enemy.velocity_x_fp = 250 * Simulation.FP_ONE
	var initial_x := int(enemy.x_fp)
	simulation._update_state_four(enemy)
	_expect(
		int(enemy.x_fp) == initial_x,
		"state 4 should ignore entry-path horizontal velocity and use its dedicated retail vector"
	)

	_prepare_state_four_enemy(enemy)
	enemy.x_fp = (Simulation.FIELD_WIDTH - 116) * Simulation.FP_ONE
	enemy.state_four_acceleration_x_fp = Simulation.PLATFORM_ACCELERATION_FP
	simulation._update_state_four(enemy)
	_expect(
		int(enemy.state_four_acceleration_x_fp) > 0,
		"state 4 should not turn at exact center x=684"
	)
	_prepare_state_four_enemy(enemy)
	enemy.x_fp = (Simulation.FIELD_WIDTH - 116) * Simulation.FP_ONE + 1
	enemy.state_four_acceleration_x_fp = Simulation.PLATFORM_ACCELERATION_FP
	simulation._update_state_four(enemy)
	_expect(
		int(enemy.state_four_acceleration_x_fp) < 0,
		"state 4 should turn once it is one fixed unit beyond center x=684"
	)

	_prepare_state_four_enemy(enemy)
	enemy.authored_animation_frame = 2
	enemy.animation_countdown_sixths = simulation._simulation_scale_numerator()
	simulation._update_state_four_animation(enemy)
	_expect(
		int(enemy.authored_animation_frame) == 2,
		"state-4 animation should not advance when its countdown reaches exact zero"
	)
	enemy.animation_countdown_sixths = simulation._simulation_scale_numerator() - 1
	simulation._update_state_four_animation(enemy)
	_expect(
		int(enemy.authored_animation_frame) == 3,
		"state-4 animation should advance only after countdown underflow"
	)


func _test_state_six_vectors_wraps_and_steering_edges() -> void:
	var simulation = _new_simulation(3)
	_spawn_authored_entities(simulation)
	var enemy: Dictionary = _find_enemy_in_state(simulation, "supplemental_large")
	_expect(not enemy.is_empty(), "level 3 should expose the executable-backed state-6 entity")
	if enemy.is_empty():
		return
	_prepare_state_six_enemy(enemy)
	enemy.heading = 0
	enemy.x_fp = 400 * Simulation.FP_ONE
	enemy.y_fp = 300 * Simulation.FP_ONE
	simulation._update_state_six(enemy)
	_expect(
		int(enemy.x_fp) == 400 * Simulation.FP_ONE
		and int(enemy.y_fp) == 299 * Simulation.FP_ONE,
		"state-6 heading 0 should use the exact (0,-1) executable direction vector"
	)
	_prepare_state_six_enemy(enemy)
	enemy.heading = 10
	enemy.x_fp = 400 * Simulation.FP_ONE
	enemy.y_fp = 300 * Simulation.FP_ONE
	simulation._update_state_six(enemy)
	_expect(
		int(enemy.x_fp) == 401 * Simulation.FP_ONE
		and int(enemy.y_fp) == 300 * Simulation.FP_ONE,
		"state-6 heading 10 should use the exact (+1,0) executable direction vector"
	)

	_prepare_state_six_enemy(enemy)
	enemy.speed_fp = 0
	enemy.x_fp = (Simulation.FIELD_WIDTH + 152) * Simulation.FP_ONE
	simulation._update_state_six(enemy)
	_expect(
		int(enemy.x_fp) == (Simulation.FIELD_WIDTH + 152) * Simulation.FP_ONE,
		"state 6 should survive equality at center x=952"
	)
	enemy.x_fp = (Simulation.FIELD_WIDTH + 152) * Simulation.FP_ONE + 1
	simulation._update_state_six(enemy)
	_expect(
		int(enemy.x_fp) == -88 * Simulation.FP_ONE,
		"state 6 should wrap right only beyond center x=952"
	)
	_prepare_state_six_enemy(enemy)
	enemy.speed_fp = 0
	enemy.y_fp = (Simulation.FIELD_HEIGHT + 152) * Simulation.FP_ONE + 1
	simulation._update_state_six(enemy)
	_expect(
		int(enemy.y_fp) == -88 * Simulation.FP_ONE,
		"state 6 should wrap below only beyond center y=752"
	)

	_prepare_state_six_enemy(enemy)
	enemy.steering_mode = 3
	enemy.heading = 0
	enemy.steering_countdown_fp = Simulation.FP_ONE
	enemy.heading_step_countdown_sixths = simulation._simulation_scale_numerator()
	simulation._update_state_six_steering(enemy)
	_expect(
		int(enemy.steering_countdown_fp) == 0
		and int(enemy.heading_step_countdown_sixths) == 0
		and int(enemy.steering_mode) == 3
		and int(enemy.heading) == 0,
		"state-6 steering and heading timers should survive exact zero"
	)
	enemy.steering_countdown_fp = 100 * Simulation.FP_ONE
	enemy.heading_step_countdown_sixths = simulation._simulation_scale_numerator() - 1
	simulation._update_state_six_steering(enemy)
	_expect(
		int(enemy.heading) == 1,
		"state-6 steering mode 3 should increment heading only after timer underflow"
	)

	_prepare_state_six_enemy(enemy)
	enemy.heading = 0
	enemy.x_fp = (Simulation.FIELD_WIDTH - 68) * Simulation.FP_ONE
	enemy.y_fp = 150 * Simulation.FP_ONE
	enemy.steering_countdown_fp = 0
	simulation._update_state_six_steering(enemy)
	_expect(
		int(enemy.steering_mode) == 2,
		"state-6 edge steering should not trigger at exact center x=732"
	)
	enemy.x_fp = (Simulation.FIELD_WIDTH - 68) * Simulation.FP_ONE + 1
	enemy.steering_countdown_fp = 0
	simulation._update_state_six_steering(enemy)
	_expect(
		int(enemy.steering_mode) == 1,
		"state-6 edge steering should trigger one fixed unit beyond center x=732"
	)

	_prepare_state_six_enemy(enemy)
	enemy.speed_fp = 0
	enemy.behavior_timer_a = 1
	enemy.x_fp = 400 * Simulation.FP_ONE
	enemy.y_fp = 300 * Simulation.FP_ONE
	simulation._projectiles.clear()
	for slot_value in simulation._common_projectile_slots:
		var slot: Dictionary = slot_value
		slot.active = false
		slot.entity_id = 0
	simulation._rng.seed(2026)
	simulation._update_state_six(enemy)
	_expect(
		int(simulation._rng.draw_count) == 4
		and simulation._projectiles.size() == 1,
		"a state-6 fire pass should consume roll, travel, X-jitter, and Y-jitter draws"
	)
	var aimed: Dictionary = simulation._projectiles[0]
	_expect(
		int(aimed.enemy_projectile_type) == 6
		and int(aimed.x_fp) == 416 * Simulation.FP_ONE
		and int(aimed.y_fp) == 309 * Simulation.FP_ONE
		and int(aimed.velocity_y_fp) > 0
		and int(aimed.mask_source_x) == 448
		and int(aimed.mask_source_y) == int(aimed.animation_frame) * 32
		and int(aimed.mask_source_width) == 32
		and int(aimed.mask_source_height) == 32,
		"level-3 state 6 should launch an aimed type-6 shot from its recovered center offset"
	)
	_expect(
		int(simulation.get_snapshot().projectiles[0].enemy_projectile_type) == 6,
		"type-6 identity should survive the authoritative snapshot boundary"
	)
	var player: Dictionary = simulation._players[0]
	aimed.x_fp = int(player.x_fp) - 15 * Simulation.FP_ONE
	aimed.y_fp = int(player.y_fp) + 2 * Simulation.FP_ONE
	_expect(
		not simulation._enemy_projectile_hits_object(aimed, player),
		"type-6 broad collision should miss when its right edge only touches the fighter"
	)
	aimed.x_fp += Simulation.FP_ONE
	_expect(
		simulation._enemy_projectile_hits_object(aimed, player),
		"type-6 broad collision should hit after one integer pixel of strict overlap"
	)

	simulation._projectiles.clear()
	for slot_value in simulation._common_projectile_slots:
		var slot: Dictionary = slot_value
		slot.active = true
		slot.entity_id = 999
	_prepare_state_six_enemy(enemy)
	enemy.speed_fp = 0
	enemy.behavior_timer_a = 1
	simulation._rng.seed(2026)
	simulation._update_state_six(enemy)
	_expect(
		simulation._projectiles.is_empty()
		and int(simulation._rng.draw_count) == 4,
		"a full common pool should reject state-6 allocation only after all four gameplay draws"
	)


func _test_state_ten_strict_top_and_flip_edges() -> void:
	var simulation = _new_simulation(4)
	_spawn_authored_entities(simulation)
	var enemy: Dictionary = simulation._enemies[0]
	simulation._begin_state_ten(enemy)
	_prepare_state_ten_enemy(enemy)
	enemy.y_fp = -116 * Simulation.FP_ONE
	simulation._update_state_ten(enemy)
	_expect(
		not bool(enemy.dead),
		"state 10 should survive equality at center y+16=-100"
	)


func _test_state_two_has_no_timer_a_fire() -> void:
	var simulation = _new_simulation(1)
	_spawn_authored_entities(simulation)
	var enemy: Dictionary = simulation._enemies[0]
	enemy.authored_state = "formation"
	enemy.behavior_state_id = 2
	enemy.x_fp = int(enemy.formation_target_x_fp) + 19
	enemy.y_fp = int(enemy.formation_target_y_fp) - 19
	enemy.behavior_timer_b = 0
	enemy.animation_countdown_sixths = simulation._simulation_scale_numerator() - 1
	var phase_before := int(enemy.authored_animation_frame)
	simulation._update_state_two(enemy)
	_expect(
		int(enemy.x_fp) == int(enemy.formation_target_x_fp)
		and int(enemy.y_fp) == int(enemy.formation_target_y_fp)
		and int(enemy.authored_animation_frame) != phase_before,
		"fixed-point formation easing should converge below one representable retail step and resume animation"
	)
	enemy.authored_state = "formation"
	enemy.behavior_state_id = 2
	enemy.x_fp = int(enemy.formation_target_x_fp)
	enemy.y_fp = int(enemy.formation_target_y_fp)
	enemy.behavior_timer_a = 1
	enemy.behavior_timer_b = 0
	simulation._rng.seed(123)
	simulation._projectiles.clear()
	simulation._update_state_two(enemy)
	_expect(
		simulation._projectiles.is_empty()
		and int(simulation._rng.draw_count) == 0,
		"retail state 2 should have no Timer-A firing branch or firing RNG draw"
	)
	for slot_value in simulation._common_projectile_slots:
		(slot_value as Dictionary).active = true
	enemy.authored_state = "swd_attack"
	enemy.behavior_state_id = 3
	enemy.behavior_timer_a = 1
	enemy.y_fp = 100 * Simulation.FP_ONE
	simulation._rng.seed(123)
	_expect(
		bool(simulation._authored_enemy_should_fire(enemy, false))
		and int(simulation._rng.draw_count) == 1,
		"an eligible Timer-A check should consume its roll before a full projectile pool rejects allocation"
	)
	_prepare_state_ten_enemy(enemy)
	enemy.y_fp = -116 * Simulation.FP_ONE - 1
	simulation._update_state_ten(enemy)
	_expect(
		bool(enemy.dead),
		"state 10 should escape one fixed unit above center y+16=-100"
	)

	var flip_enemy: Dictionary = simulation._enemies[1]
	simulation._begin_state_ten(flip_enemy)
	_prepare_state_ten_enemy(flip_enemy)
	flip_enemy.horizontal_acceleration_fp = 123
	flip_enemy.horizontal_flip_countdown_sixths = simulation._simulation_scale_numerator()
	simulation._update_state_ten(flip_enemy)
	_expect(
		int(flip_enemy.horizontal_acceleration_fp) == -123
		and int(flip_enemy.horizontal_velocity_fp) == -123,
		"state 10 should flip acceleration when its countdown reaches exact zero, before velocity integration"
	)


func _test_first_five_lvd_scores_and_completion_awards() -> void:
	var expected_enemy_counts := [18, 22, 25, 25, 22]
	var expected_scores := [20900, 20440, 21200, 74500, 21100]
	for level_index in range(5):
		var level_id := level_index + 1
		var simulation = _new_simulation(level_id)
		_spawn_authored_entities(simulation)
		_expect(
			simulation._enemies.size() == expected_enemy_counts[level_index],
			"level %d should spawn the expected score-bearing entity population" % level_id
		)
		# A full bonus pool also makes this score audit independent of drop rolls.
		for slot in range(Simulation.BONUS_POOL_SLOT_COUNT):
			simulation._pickups.append({})
		for enemy_value in simulation._enemies:
			simulation._kill_enemy(enemy_value as Dictionary, 0)
		_expect(
			int(simulation._shared.score) == expected_scores[level_index],
			"level %d no-miss/no-recruit score should be %d" % [
				level_id,
				expected_scores[level_index],
			]
		)
		_expect(
			int(simulation._shared.money) == 0,
			"level %d ordinary alien kills should award zero cash" % level_id
		)
		if level_id == 1:
			_expect(
				_event_scores(simulation._events, "group_completed") == [10000, 10000],
				"level 1 should award 10,000 once for each of its two complete groups"
			)
		elif level_id == 4:
			_expect(
				_event_scores(simulation._events, "cohort_completed")
				== [2000, 4000, 8000, 16000, 32000],
				"level 4 should double its five cohort awards from 2,000 through 32,000"
			)

	var state_four = _new_simulation(1)
	_spawn_authored_entities(state_four)
	for slot in range(Simulation.BONUS_POOL_SLOT_COUNT):
		state_four._pickups.append({})
	var roaming_enemy: Dictionary = state_four._enemies[0]
	roaming_enemy.behavior_state_id = 4
	roaming_enemy.authored_state = "return"
	state_four._kill_enemy(roaming_enemy, 0)
	_expect(
		int(state_four._shared.score) == 50
		and int(state_four._group_kill_counts.get(0, -1)) == 0,
		"a state-4 ordinary alien should retain its level-tail score without group accounting"
	)


func _test_ordinary_enemy_body_contact_is_inert() -> void:
	var simulation = _new_simulation(1)
	_spawn_authored_entities(simulation)
	var player: Dictionary = simulation._players[0]
	var enemy: Dictionary = simulation._enemies[0]
	enemy.x_fp = int(player.x_fp)
	enemy.y_fp = int(player.y_fp)
	var lives_before := int(simulation._shared.lives)
	simulation._resolve_enemy_player_collisions()
	_expect(
		bool(player.alive)
		and int(player.respawn_ticks) == 0
		and int(simulation._shared.lives) == lives_before,
		"ordinary alien/body overlap should not damage the fighter in levels 1-5"
	)


func _test_freeze_and_scoop_runtime_contracts() -> void:
	var freeze = _new_simulation(1)
	_spawn_authored_entities(freeze)
	var roaming: Dictionary = freeze._enemies[0]
	_prepare_state_four_enemy(roaming)
	roaming.velocity_x_fp = Simulation.FP_ONE
	var delayed: Dictionary = freeze._enemies[1]
	delayed.authored_state = "delayed"
	delayed.behavior_state_id = 1
	delayed.activation_delay_sixths = freeze._simulation_scale_numerator()
	var x_before := int(roaming.x_fp)
	var platform_before := int(freeze._platform_x_fp)
	freeze._shared.freeze_ticks = 1
	freeze._update_enemies()
	_expect(
		int(roaming.x_fp) == x_before
		and int(freeze._platform_x_fp) != platform_before,
		"Freeze should halt complete active enemy handlers while the platform keeps updating"
	)
	_expect(
		String(delayed.authored_state) == "entry",
		"Freeze should not halt delayed-slot activation bookkeeping"
	)

	var scoop = _new_simulation(1)
	_spawn_authored_entities(scoop)
	var player: Dictionary = scoop._players[0]
	scoop._shared.scoop_ticks = 1
	var player_top: int = scoop._trunc_fp_to_int(
		int(player.y_fp) - (Simulation.PLAYER_HEIGHT * Simulation.FP_ONE >> 1)
	)
	var field_probe: Dictionary = scoop._enemies[3]
	field_probe.x_fp = int(player.x_fp) + 47 * Simulation.FP_ONE
	field_probe.y_fp = (player_top - 89 + 16) * Simulation.FP_ONE
	_expect(
		not scoop._objects_collide(field_probe, player)
		and scoop._enemy_inside_scoop_field(field_probe, player),
		"Scoop should use its tapered 90px tractor field, not ordinary fighter overlap"
	)
	field_probe.x_fp = (int(player.x_fp) - 48 * Simulation.FP_ONE - 16 * Simulation.FP_ONE)
	_expect(
		not scoop._enemy_inside_scoop_field(field_probe, player),
		"Scoop horizontal field edges should remain strict"
	)
	field_probe.x_fp = int(player.x_fp)
	field_probe.y_fp = (player_top - 90 - 16) * Simulation.FP_ONE
	_expect(
		not scoop._enemy_inside_scoop_field(field_probe, player),
		"Scoop vertical field edges should remain strict"
	)
	for enemy_index in range(3, scoop._enemies.size()):
		(scoop._enemies[enemy_index] as Dictionary).dead = true
	for enemy_index in range(3):
		var enemy: Dictionary = scoop._enemies[enemy_index]
		enemy.authored_state = "entry"
		enemy.behavior_state_id = 1
		# At the cone apex, endpoint-inside geometry rejects a centered 32px
		# alien; offset it so its left edge lies strictly inside the narrow beam.
		enemy.x_fp = int(player.x_fp) + 15 * Simulation.FP_ONE
		enemy.y_fp = int(player.y_fp)
		enemy.collision_x_fp = int(enemy.x_fp)
		enemy.collision_y_fp = int(player.y_fp)
	var scoop_draws_before := int(scoop._rng.draw_count)
	scoop._resolve_enemy_player_collisions()
	var captives: Array = scoop._captured_enemies_for_seat(0, false)
	var overflow: Dictionary = {}
	for enemy_value in scoop._enemies:
		var candidate: Dictionary = enemy_value
		if int(candidate.get("behavior_state_id", 0)) == 5:
			overflow = candidate
			break
	_expect(
		captives.size() == 2
		and int(scoop._level_escaped_entities) == 2
		and int(scoop._level_killed_entities) == 1
		and int(scoop._shared.score) == 2500
		and not overflow.is_empty()
		and not bool(overflow.dead),
		"Scoop should capture left/right, then count and visibly eject overflow for 2,500"
	)
	_expect(
		int(scoop._rng.draw_count) == scoop_draws_before + 2
		and int(overflow.horizontal_velocity_fp) >= -4 * Simulation.FP_ONE
		and int(overflow.horizontal_velocity_fp) < 4 * Simulation.FP_ONE
		and int(overflow.vertical_velocity_fp) >= -10 * Simulation.FP_ONE
		and int(overflow.vertical_velocity_fp) < -6 * Simulation.FP_ONE,
		"Scoop overflow should draw retail vx [-4,4) then vy [-10,-6)"
	)
	overflow.horizontal_velocity_fp = 0
	overflow.vertical_velocity_fp = 0
	overflow.y_fp = 16 * Simulation.FP_ONE
	scoop._update_state_five(overflow)
	_expect(not bool(overflow.dead), "state 5 should survive equality at center y=16")
	overflow.y_fp = 16 * Simulation.FP_ONE - 1
	scoop._update_state_five(overflow)
	_expect(bool(overflow.dead), "state 5 should deactivate one fixed unit above y=16")
	var captured_timer_a := int(captives[0].behavior_timer_a)
	var captured_timer_b := int(captives[0].behavior_timer_b)
	scoop._tighten_enemy_behavior_timers(1)
	_expect(
		int(captives[0].behavior_timer_a) == captured_timer_a
		and int(captives[0].behavior_timer_b) == captured_timer_b,
		"qualifying kills should not tighten state-8 Scoop captive timers"
	)
	for captive_value in captives:
		(captive_value as Dictionary).captured_latched = true
	scoop._projectiles.clear()
	scoop._fire_player_weapon(player)
	_expect(
		scoop._projectiles.size() == 3
		and [
			int((scoop._projectiles[0] as Dictionary).prototype_id),
			int((scoop._projectiles[1] as Dictionary).prototype_id),
			int((scoop._projectiles[2] as Dictionary).prototype_id),
		] == [0, 48, 48]
		and [
			int((scoop._projectiles[0] as Dictionary).capacity_contribution),
			int((scoop._projectiles[1] as Dictionary).capacity_contribution),
			int((scoop._projectiles[2] as Dictionary).capacity_contribution),
		] == [1, 0, 0]
		and int((scoop._projectiles[1] as Dictionary).x_fp)
		== int(player.x_fp) - 36 * Simulation.FP_ONE
		and int((scoop._projectiles[2] as Dictionary).x_fp)
		== int(player.x_fp) + 36 * Simulation.FP_ONE,
		"Scoop wingmen should fire their mapped non-counting roots at ship X minus/plus 36"
	)
	scoop._projectiles = [{
		"id": 999,
		"owner_kind": "enemy",
		"owner_id": -1,
		"common_slot": -1,
		"x_fp": int(player.x_fp),
		"y_fp": int(player.y_fp),
		"velocity_x_fp": 0,
		"velocity_y_fp": 0,
		"width": 32,
		"height": 32,
		"damage_fp": Simulation.FP_ONE,
		"prototype_id": -1,
		"animation_frame": 0,
		"expired": false,
	}]
	scoop._resolve_enemy_projectile_collisions()
	_expect(
		bool(player.alive)
		and scoop._captured_enemies_for_seat(0, false).size() == 1,
		"an alien shot should sacrifice the left Scoop captive before damaging the fighter"
	)


func _test_final_kill_rockets_and_watchdogs() -> void:
	var reward = _new_simulation(1)
	_spawn_authored_entities(reward)
	reward._level_total_entities = 1
	reward._alien_projectile_processed_this_level = true
	reward._kill_enemy(reward._enemies[0], 0)
	_expect(
		int(reward._shared.rockets) == 10,
		"a qualifying final kill in every first-five LVD mode should add ten rockets"
	)

	var capped = Simulation.new()
	_expect(capped.configure({
		"mode": "solo",
		"difficulty": "normal",
		"collision_mode": "simple",
		"start_level": 1,
		"starting_rockets": 50,
		"record_replay": false,
	}), "capped-rocket fidelity simulation should configure")
	_spawn_authored_entities(capped)
	capped._level_total_entities = 1
	capped._alien_projectile_processed_this_level = true
	capped._kill_enemy(capped._enemies[0], 0)
	_expect(
		int(capped._shared.rockets) == 50
		and int(capped._shared.score) == 50050,
		"a final kill at the 50-rocket cap should award 50,000 plus the level-tail score"
	)

	var escaped = _new_simulation(1)
	_spawn_authored_entities(escaped)
	escaped._level_total_entities = 1
	escaped._escape_enemy(escaped._enemies[0])
	_expect(
		int(escaped._shared.rockets) == 0,
		"deactivation completion should not grant the final-kill rocket reward"
	)

	var watchdog = _new_simulation(1)
	watchdog._tick = Simulation.LEVEL_WATCHDOG_TICKS
	watchdog._check_level_end()
	_expect(not bool(watchdog._level_resolved), "the 45-second watchdog should survive equality")
	watchdog._tick += 1
	watchdog._check_level_end()
	_expect(
		bool(watchdog._level_resolved)
		and int(watchdog._level_resolution_tick)
		== Simulation.LEVEL_WATCHDOG_TICKS + 1 + Simulation.LEVEL_RESOLUTION_TICKS
		and int(watchdog._shared.rockets) == 0,
		"the tick beyond 45 seconds should force only the three-second resolution deadline"
	)


func _test_render_watchdog_refresh_contract() -> void:
	var simulation = _new_simulation(1)
	simulation._tick = 77
	simulation._level_watchdog_start_tick = 12
	simulation._shared.freeze_ticks = 100
	simulation._enemies = [{
		"id": 6100,
		"dead": false,
		"authored_state": "formation",
		"behavior_state_id": 2,
		"x_fp": 400 * Simulation.FP_ONE,
		"y_fp": 200 * Simulation.FP_ONE,
		"width": 32,
		"height": 32,
	}]
	simulation._refresh_enemy_watchdog_timestamp_from_render()
	_expect(
		int(simulation._level_watchdog_start_tick) == 77,
		"a frozen visible formation alien should still refresh the render-owned watchdog timestamp"
	)

	simulation._level_watchdog_start_tick = 21
	simulation._enemies = [{
		"id": 6101,
		"dead": false,
		"authored_state": "delayed",
		"behavior_state_id": 1,
		"activation_delay_sixths": 1,
		"x_fp": 400 * Simulation.FP_ONE,
		"y_fp": 200 * Simulation.FP_ONE,
		"width": 32,
		"height": 32,
	}]
	simulation._refresh_enemy_watchdog_timestamp_from_render()
	_expect(
		int(simulation._level_watchdog_start_tick) == 21,
		"a visible but delayed state-1 record should not refresh the watchdog"
	)

	simulation._enemies = [{
		"id": 6102,
		"dead": false,
		"authored_state": "captured",
		"behavior_state_id": 8,
		"x_fp": 400 * Simulation.FP_ONE,
		"y_fp": 500 * Simulation.FP_ONE,
		"width": 32,
		"height": 32,
	}]
	simulation._refresh_enemy_watchdog_timestamp_from_render()
	_expect(
		int(simulation._level_watchdog_start_tick) == 21,
		"a visible state-8 captive should remain excluded from alien render liveness"
	)

	var edge_enemy := {
		"id": 6103,
		"dead": false,
		"authored_state": "warp_malfunction",
		"behavior_state_id": 6,
		"x_fp": -32 * Simulation.FP_ONE,
		"y_fp": 200 * Simulation.FP_ONE,
		"width": 64,
		"height": 64,
	}
	simulation._enemies = [edge_enemy]
	simulation._refresh_enemy_watchdog_timestamp_from_render()
	_expect(
		int(simulation._level_watchdog_start_tick) == 21,
		"a 64-pixel alien whose right edge equals zero should fail strict viewport intersection"
	)
	edge_enemy.x_fp = -31 * Simulation.FP_ONE
	simulation._refresh_enemy_watchdog_timestamp_from_render()
	_expect(
		int(simulation._level_watchdog_start_tick) == 77,
		"one pixel of viewport overlap should refresh the watchdog"
	)


func _test_pickup_scan_owner_contract() -> void:
	var solo = _new_simulation(1, "solo")
	var solo_draws := int(solo._rng.draw_count)
	_expect(
		solo._pickup_seat_scan_order() == [0]
		and int(solo._rng.draw_count) == solo_draws,
		"single-player pickup dispatch should scan only seat zero without an owner draw"
	)


func _test_death_is_accounted_at_the_respawn_deadline() -> void:
	var simulation = _new_simulation(1)
	var player: Dictionary = simulation._players[0]
	simulation._damage_player(player, Simulation.FP_ONE)
	_expect(
		not bool(player.alive)
		and int(player.respawn_ticks) == Simulation.RESPAWN_TICKS
		and int(simulation._shared.lives) == 3,
		"fighter destruction should start the strict three-second deadline without immediately consuming a life"
	)
	for tick in range(Simulation.RESPAWN_TICKS - 1):
		simulation._update_respawns()
	_expect(
		int(player.respawn_ticks) == 1
		and int(simulation._shared.lives) == 3
		and not bool(player.alive),
		"the encoded fighter count should remain unchanged until the final deadline tick"
	)
	simulation._update_respawns()
	_expect(
		bool(player.alive)
		and int(simulation._shared.lives) == 2
		and int(player.invulnerable_ticks) == Simulation.INVULNERABLE_TICKS,
		"the deadline should consume one fighter, respawn, and start the retail solo shield"
	)


func _test_level_resolution_and_get_ready_deadlines() -> void:
	var simulation = _new_simulation(1)
	simulation._level_total_entities = 1
	simulation._level_killed_entities = 1
	simulation._try_resolve_level_counter()
	_expect(
		bool(simulation._level_resolved)
		and int(simulation._level_resolution_tick) == Simulation.LEVEL_RESOLUTION_TICKS,
		"the final entity should arm a three-second level-resolution deadline"
	)
	simulation._pickups.append({"expired": false})
	simulation._tick = Simulation.LEVEL_RESOLUTION_TICKS
	simulation._check_level_end()
	_expect(
		String(simulation._phase) == Simulation.PHASE_LEVEL,
		"level resolution should remain active at exact deadline equality"
	)
	simulation._tick = Simulation.LEVEL_RESOLUTION_TICKS + 1
	simulation._check_level_end()
	_expect(
		String(simulation._phase) == Simulation.PHASE_GET_READY
		and int(simulation._pending_level_id) == 2
		and int(simulation._get_ready_until_tick)
		== Simulation.LEVEL_RESOLUTION_TICKS + 1 + Simulation.GET_READY_TICKS
		and simulation._pickups.is_empty(),
		"the tick after resolution should clear pickups and start the two-second get-ready phase"
	)
	simulation._tick = int(simulation._get_ready_until_tick)
	simulation._step_get_ready()
	_expect(
		String(simulation._phase) == Simulation.PHASE_GET_READY,
		"get-ready should remain active at exact deadline equality"
	)
	simulation._tick = int(simulation._get_ready_until_tick) + 1
	simulation._step_get_ready()
	_expect(
		String(simulation._phase) == Simulation.PHASE_LEVEL
		and int(simulation._level_id) == 2
		and int(simulation._level_tick) == 0,
		"the tick after get-ready should initialize the next authored level"
	)


func _test_level_four_shop_warp_contract() -> void:
	var simulation = _new_simulation(4)
	simulation._shared.money = Simulation.WARP_SHOP_MINIMUM_MONEY
	simulation._warp_malfunction_interval = 0
	simulation._level_total_entities = 1
	simulation._level_killed_entities = 1
	simulation._try_resolve_level_counter()
	simulation._tick = Simulation.LEVEL_RESOLUTION_TICKS + 1
	simulation._check_level_end()
	_expect(
		String(simulation._phase) == Simulation.PHASE_WARP
		and not bool(simulation._warp_owned_skip)
		and int(simulation._warp_stage_updates_remaining)
		== Simulation.WARP_STAGE_ONE_UPDATES
		and int(simulation._shared.warp_fp) == 3 * Simulation.FP_ONE + (Simulation.FP_ONE >> 1)
		and int(simulation._shared.warp_companion) == 10,
		"level 4 completion should upgrade progression and enter the full non-owned mode-13 warp"
	)
	for update_index in range(399):
		simulation._tick += 1
		simulation._step_warp()
	_expect(
		String(simulation._phase) == Simulation.PHASE_WARP
		and int(simulation._warp_stage) == 2
		and int(simulation._warp_stage_updates_remaining) == 1,
		"the retail 100+200+100 warp should remain active through update 399"
	)
	simulation._tick += 1
	simulation._step_warp()
	_expect(
		String(simulation._phase) == Simulation.PHASE_SHOP
		and int(simulation._level_id) == 4
		and int(simulation._pending_level_id) == 5,
		"warp update 400 should enter the first shop while logical level remains 4"
	)
	simulation._shop_ready[0] = true
	simulation._try_leave_shop()
	_expect(
		String(simulation._phase) == Simulation.PHASE_SHOP,
		"the post-warp shop input guard should survive deadline equality"
	)
	simulation._tick = int(simulation._shop_warp_until_tick) + 1
	simulation._try_leave_shop()
	_expect(
		String(simulation._phase) == Simulation.PHASE_GET_READY
		and int(simulation._pending_level_id) == 5,
		"leaving the first shop after its 500-ms guard should proceed to level-5 Get Ready"
	)

	var poor = _new_simulation(4)
	poor._shared.money = Simulation.WARP_SHOP_MINIMUM_MONEY - 1
	poor._warp_malfunction_interval = 0
	poor._begin_warp(false, "test_level_four", 0)
	for update_index in range(400):
		poor._tick += 1
		poor._step_warp()
	_expect(
		String(poor._phase) == Simulation.PHASE_GET_READY
		and int(poor._pending_level_id) == 5,
		"money below 50 should bypass mode 9 and proceed directly to level-5 Get Ready"
	)


func _test_warp_bonus_and_malfunction_contracts() -> void:
	var startup = _new_simulation(1, "solo", "normal", 73)
	var startup_oracle = Rng.new(73)
	var expected_interval := 19000 + startup_oracle.next_range(8000)
	_expect(
		int(startup._shared.warp_fp) == 3 * Simulation.FP_ONE
		and int(startup._shared.warp_companion) == 8
		and int(startup._warp_malfunction_interval) == expected_interval,
		"fresh-game warp progression and the first malfunction interval should match startup disassembly"
	)

	var visual = _new_simulation(1)
	visual._begin_warp(true, "visual_test", 0)
	visual._update_warp_player_animation()
	_expect(
		absf(float(visual._warp_scale) - 7.150000095) < 0.000001
		and absf(float(visual._warp_velocity) - 0.130434796) < 0.000001
		and absf(float(visual._warp_effect) - 0.00999999978) < 0.000001
		and absf(float(visual._warp_offset) - 0.25) < 0.000001,
		"the first warp animation update should retain all promoted-float operations"
	)

	var background = _new_simulation(1)
	background._begin_warp(true, "background_cadence_test", 0)
	background._advance_background_scroll_presentation()
	background._update_warp_player_animation()
	background._advance_background_scroll_presentation()
	background._update_warp_player_animation()
	background._advance_background_scroll_presentation()
	var background_snapshot: Dictionary = background.get_snapshot().warp
	_expect(
		absf(float(background_snapshot.background_draw_offset) - 0.60750002) < 0.000001
		and absf(float(background_snapshot.background_post_draw_offset) - 1.0725001) < 0.000001,
		"authoritative background offsets accumulate each changing float32 Warp scale before sparse snapshots"
	)
	for update_index in range(53):
		visual._update_warp_player_animation()
	_expect(
		float(visual._warp_scale) > 121.10
		and float(visual._warp_scale) < 121.11,
		"the malfunction gate should first observe scale above 120 on call 55"
	)

	var moving = _new_simulation(1)
	moving._begin_warp(true, "movement_test", 0)
	moving._warp_malfunction_interval = 0
	moving._projectiles.clear()
	moving._input_masks[0] = Simulation.ACTION_RIGHT | Simulation.ACTION_FIRE
	var moving_start_x := int(moving._players[0].x_fp)
	moving._step_warp()
	_expect(
		int(moving._players[0].x_fp) > moving_start_x
		and moving._projectiles.is_empty(),
		"mode 13 should keep fighter movement/status live while suppressing player fire"
	)

	var skip = _new_simulation(1)
	skip._shared.money = Simulation.WARP_SHOP_MINIMUM_MONEY
	skip._warp_malfunction_interval = 0
	skip._pickups = [{
		"id": 600,
		"kind": "money",
		"x_fp": 100 * Simulation.FP_ONE,
		"y_fp": 100 * Simulation.FP_ONE,
		"velocity_x_fp": 0,
		"velocity_y_fp": 0,
		"width": 20,
		"height": 20,
		"animation_countdown_fp": 999 * Simulation.FP_ONE,
		"animation_period_fp": 999 * Simulation.FP_ONE,
		"animation_frame": 0,
		"expired": false,
	}]
	skip._apply_retail_bonus_type(15, skip._shared, 0)
	_expect(
		bool(skip._warp_transition_requested)
		and int(skip._shared.warp_fp) == 3 * Simulation.FP_ONE + (Simulation.FP_ONE >> 1)
		and int(skip._shared.warp_companion) == 10,
		"type 15 should upgrade progression and latch an owned warp transition"
	)
	skip._consume_warp_transition_request()
	for update_index in range(400):
		skip._tick += 1
		skip._step_warp()
	_expect(
		String(skip._phase) == Simulation.PHASE_SHOP
		and int(skip._level_id) == 4
		and int(skip._pending_level_id) == 5
		and skip._pickups.size() == 1,
		"type 15 on levels 1-3 should run four skip passes, stop at special level 4, preserve pickups, then enter shop"
	)

	var boundary = _new_simulation(5)
	boundary._warp_malfunction_interval = 0
	boundary._apply_retail_bonus_type(15, boundary._shared, 0)
	boundary._consume_warp_transition_request()
	for update_index in range(400):
		boundary._tick += 1
		boundary._step_warp()
	_expect(
		String(boundary._phase) == Simulation.PHASE_COMPLETE
		and int(boundary._level_id) == 5
		and int(boundary._result.get("level_reached", 0)) == 5,
		"type 15 on level 5 should stop at the configured boundary before loading authored level 6"
	)


	var early_gate = _new_simulation(1)
	early_gate._begin_warp(true, "gate_test", 0)
	early_gate._warp_malfunction_interval = 1
	early_gate._rng.seed(9001)
	var early_draws := int(early_gate._rng.draw_count)
	_expect(
		not early_gate._try_begin_warp_malfunction()
		and int(early_gate._rng.draw_count) == early_draws + 1,
		"an early malfunction gate should consume its interval draw before rejecting scale <= 120"
	)

	var entry_fire = _new_simulation(1)
	entry_fire._begin_warp(true, "entry_fire_test", 0)
	entry_fire._warp_scale = Rng._float32(121.0)
	entry_fire._warp_malfunction_interval = 1
	entry_fire._projectiles.clear()
	entry_fire._input_masks[0] = Simulation.ACTION_FIRE
	entry_fire._previous_input_masks[0] = 0
	entry_fire._step_warp()
	_expect(
		String(entry_fire._phase) == Simulation.PHASE_WARP_MALFUNCTION
		and not entry_fire._projectiles.is_empty(),
		"the gate-hit frame should reach the player callback as mode 16 and allow firing"
	)

	var spawned = _new_simulation(1)
	spawned._enemies = [{
		"id": 700,
		"dead": false,
		"behavior_state_id": 8,
		"captured_owner_seat": 0,
		"captured_side": 0,
		"captured_latched": true,
		"x_fp": 300 * Simulation.FP_ONE,
		"y_fp": 500 * Simulation.FP_ONE,
		"width": 32,
		"height": 32,
		"health_fp": Simulation.FP_ONE,
		"max_health_fp": Simulation.FP_ONE,
		"sprite": "alien001",
	}]
	spawned._rng.seed(4040)
	var spawn_draws := int(spawned._rng.draw_count)
	var malfunction_entry_tick := int(spawned._tick)
	spawned._begin_warp_malfunction(12345)
	_expect(
		String(spawned._phase) == Simulation.PHASE_WARP_MALFUNCTION
		and int(spawned._warp_stage_updates_remaining) == 0
		and absf(float(spawned._warp_scale)) < 0.000001
		and absf(float(spawned._warp_velocity) + 5.0) < 0.000001
		and int(spawned._warp_malfunction_total) >= 2
		and int(spawned._warp_malfunction_total) <= 3
		and spawned._enemies.size() == int(spawned._warp_malfunction_total) + 1
		and int(spawned._rng.draw_count)
		== spawn_draws + 2 + 12 * int(spawned._warp_malfunction_total),
		"malfunction selection should preserve state-8 captives and consume file, budget, then 12 draws per enemy"
	)
	_expect(
		int(spawned._warp_malfunction_message_cadence_tick)
		== malfunction_entry_tick + 18
		and int(spawned._warp_malfunction_message_cadence_remaining) == 1,
		"malfunction entry should arm the retail one-shot message cue for 300 ms"
	)
	var start_event: Dictionary = {}
	for event_value in spawned._events:
		if (
			event_value is Dictionary
			and String((event_value as Dictionary).get("type", ""))
			== "warp_malfunction_started"
		):
			start_event = event_value
			break
	_expect(
		String(start_event.get("sfx_key", "")) == "alienshoot15"
		and int(start_event.get("frequency_hz", 0)) == 12345
		and int(start_event.get("source_hz", 0)) == 32000,
		"malfunction entry should immediately play alienshoot15 at its random retail frequency"
	)
	spawned._events.clear()
	spawned._tick = malfunction_entry_tick + 18
	spawned._update_warp_malfunction_message_cadence()
	_expect(
		spawned._events.is_empty(),
		"the delayed malfunction cue should survive exact 300-ms equality"
	)
	spawned._tick += 1
	spawned._update_warp_malfunction_message_cadence()
	_expect(
		spawned._events.size() == 1
		and String((spawned._events[0] as Dictionary).type)
		== "warp_malfunction_message_cue"
		and int(spawned._warp_malfunction_message_cadence_remaining) == 0
		and int(spawned._warp_malfunction_message_cadence_tick)
		== spawned._tick + 96,
		"the tick after 300 ms should emit exactly one cue and rearm the dormant timer for 1.6 seconds"
	)

	var gem_enemy: Dictionary = spawned._enemies[1]
	spawned._pickups.clear()
	spawned._shared.score_multiplier = 2
	spawned._rng.seed(8080)
	var gem_draws := int(spawned._rng.draw_count)
	spawned._kill_enemy(gem_enemy, 0)
	_expect(
		int(spawned._warp_malfunction_killed) == 1
		and int(spawned._shared.score) == 10000
		and spawned._pickups.size() == 1
		and String((spawned._pickups[0] as Dictionary).kind) == "warp_gem"
		and int(spawned._rng.draw_count) == gem_draws + 1,
		"a mode-16 kill should award 5,000 times multiplier and consume one gem-color draw"
	)
	var gem: Dictionary = spawned._pickups[0]
	var score_before_collection := int(spawned._shared.score)
	gem.gem_color_bit = 1
	gem.variant = 0
	spawned._apply_pickup_dictionary(gem, 0)
	_expect(
		int(spawned._shared.score) == score_before_collection + 10000
		and int(spawned._shared.rank_markers) == 1
		and int(spawned._shared.gem_count) == 1
		and int(spawned._rng.draw_count) == gem_draws + 2,
		"gem collection should score again, mark its color, increment the counter, and draw one pitch"
	)
	for color_index in range(1, 6):
		spawned._apply_pickup_dictionary({
			"kind": "warp_gem",
			"effect_key": "warp_gem",
			"variant": color_index,
			"gem_color_bit": 1 << color_index,
		}, 0)
	_expect(
		int(spawned._shared.rank_markers) == 0x3f
		and bool(spawned._shared.auto_fire)
		and int(spawned._shared.auto_fire_delay_ms)
		== Simulation.SUPER_AUTO_FIRE_REPEAT_DELAY_MS
		and int(spawned._shared.upgrades.get("super_autofire", 0)) == 1,
		"all six gem colors should enable retail Super Auto Fire"
	)

	var full_pool = _new_simulation(1)
	full_pool._pickups.clear()
	for slot_index in range(Simulation.BONUS_POOL_SLOT_COUNT):
		full_pool._pickups.append({"id": 9000 + slot_index})
	full_pool._rng.seed(9090)
	var full_pool_draws := int(full_pool._rng.draw_count)
	full_pool._spawn_warp_malfunction_gem({
		"x_fp": 400 * Simulation.FP_ONE,
		"y_fp": 200 * Simulation.FP_ONE,
	})
	_expect(
		full_pool._pickups.size() == Simulation.BONUS_POOL_SLOT_COUNT
		and int(full_pool._rng.draw_count) == full_pool_draws,
		"a full shared pickup pool should reject a malfunction gem before its color draw"
	)

	var reused_pool = _new_simulation(1)
	reused_pool._pickups.clear()
	var reused_player: Dictionary = reused_pool._players[0]
	for slot_index in range(Simulation.BONUS_POOL_SLOT_COUNT):
		var pickup := _test_pickup(
			9200 + slot_index,
			int(reused_player.x_fp) if slot_index == 0 else -1000 * Simulation.FP_ONE,
			int(reused_player.y_fp)
		)
		pickup.pickup_slot = slot_index
		reused_pool._pickups.append(pickup)
	reused_pool._resolve_pickup_collisions()
	reused_pool._rng.seed(9091)
	var reused_pool_draws := int(reused_pool._rng.draw_count)
	reused_pool._spawn_warp_malfunction_gem({
		"x_fp": 400 * Simulation.FP_ONE,
		"y_fp": 200 * Simulation.FP_ONE,
	})
	_expect(
		reused_pool._pickups.size() == Simulation.BONUS_POOL_SLOT_COUNT + 1
		and bool((reused_pool._pickups[0] as Dictionary).expired)
		and int((reused_pool._pickups.back() as Dictionary).pickup_slot) == 0
		and int(reused_pool._rng.draw_count) == reused_pool_draws + 1,
		"an early collected pickup should free slot zero for a same-frame gem and its color draw"
	)

	var animated = _new_simulation(1)
	animated._players[0].active = false
	animated._pickups.clear()
	animated._rng.seed(9191)
	animated._spawn_warp_malfunction_gem({
		"x_fp": 400 * Simulation.FP_ONE,
		"y_fp": 200 * Simulation.FP_ONE,
	})
	var animated_gem: Dictionary = animated._pickups[0]
	for update_index in range(6):
		animated._update_pickups()
	_expect(
		int(animated_gem.animation_frame) == 0
		and int(animated_gem.animation_countdown_fp) == 0,
		"a marks.tga gem should retain its first cell at exact animation-countdown equality"
	)
	animated._update_pickups()
	_expect(
		int(animated_gem.animation_frame) == 1,
		"a marks.tga gem should advance only after strict animation-countdown underflow"
	)

	var deferred_collection = _new_simulation(1)
	deferred_collection._begin_warp_malfunction(12345)
	deferred_collection._pickups.clear()
	var deferred_player: Dictionary = deferred_collection._players[0]
	var deferred_enemy := {
		"id": 9800,
		"dead": false,
		"warp_malfunction": true,
		"authored_lvd": true,
		"authored_state": "warp_malfunction",
		"behavior_state_id": 6,
		"x_fp": int(deferred_player.x_fp),
		"y_fp": int(deferred_player.y_fp) + 22 * Simulation.FP_ONE,
		"width": 64,
		"height": 64,
		"health_fp": Simulation.FP_ONE,
		"max_health_fp": Simulation.FP_ONE,
		"score": 5000,
		"sprite": "malfunction1",
	}
	deferred_collection._enemies = [deferred_enemy]
	deferred_collection._warp_malfunction_total = 1
	deferred_collection._warp_malfunction_killed = 0
	deferred_collection._projectiles = [{
		"id": 9801,
		"owner_kind": "player",
		"owner_id": 0,
		"player_slot": 0,
		"spawn_tick": deferred_collection._tick,
		"x_fp": int(deferred_enemy.x_fp),
		"y_fp": int(deferred_enemy.y_fp),
		"velocity_x_fp": 0,
		"velocity_y_fp": 0,
		"width": 8,
		"height": 8,
		"damage_fp": Simulation.FP_ONE,
		"prototype_id": 0,
		"expired": false,
	}]
	deferred_collection._tick += 1
	deferred_collection._step_warp_malfunction()
	_expect(
		deferred_collection._pickups.size() == 1
		and int(deferred_collection._shared.gem_count) == 0,
		"a gem spawned by this frame's kill must miss the earlier pickup scan and remain uncollected"
	)
	deferred_collection._tick += 1
	deferred_collection._step_warp_malfunction()
	_expect(
		int(deferred_collection._shared.gem_count) == 1,
		"the overlapping malfunction gem should become collectible on the next frame's early pickup scan"
	)

	var completion = _new_simulation(1)
	completion._begin_warp_malfunction(12345)
	completion._enemies.clear()
	completion._warp_malfunction_total = 1
	completion._warp_malfunction_killed = 1
	completion._warp_malfunction_missed = 0
	completion._tick = 120
	completion._check_warp_malfunction_completion()
	var resolution_tick := int(completion._warp_malfunction_resolution_tick)
	completion._tick = resolution_tick
	completion._check_warp_malfunction_completion()
	_expect(
		not bool(completion._warp_malfunction_transition_pending),
		"mode 16 should survive exact equality at its three-second completion deadline"
	)
	completion._tick = resolution_tick + 1
	completion._check_warp_malfunction_completion()
	_expect(
		bool(completion._warp_malfunction_transition_pending)
		and String(completion._phase) == Simulation.PHASE_WARP_MALFUNCTION,
		"the tick after the mode-16 deadline should latch, but not immediately take, the return to mode 13"
	)
	completion._step_warp_malfunction()
	_expect(
		String(completion._phase) == Simulation.PHASE_WARP
		and int(completion._warp_stage) == 0
		and int(completion._warp_stage_updates_remaining)
		== Simulation.WARP_STAGE_ONE_UPDATES
		and absf(float(completion._warp_scale)) < 0.000001
		and absf(float(completion._warp_velocity) + 5.0) < 0.000001,
		"the latched return should execute one final full mode-16 update before restarting mode 13"
	)

	var late = _new_simulation(1)
	late._phase = Simulation.PHASE_WARP_MALFUNCTION
	late._level_watchdog_start_tick = 0
	late._tick = Simulation.LEVEL_WATCHDOG_TICKS
	late._warp_malfunction_total = 1
	late._warp_malfunction_killed = 0
	late._warp_malfunction_missed = 0
	late._enemies = [{
		"id": 9900,
		"dead": false,
		"warp_malfunction": true,
	}]
	late._check_warp_malfunction_completion()
	_expect(
		int(late._warp_malfunction_resolution_tick) == 0,
		"mode 16's inherited 45-second watchdog should survive exact equality"
	)
	late._tick += 1
	late._check_warp_malfunction_completion()
	_expect(
		int(late._warp_malfunction_resolution_tick)
		== late._tick + Simulation.WARP_MALFUNCTION_RESOLUTION_TICKS
		and int(late._warp_malfunction_missed) == 0
		and not bool((late._enemies[0] as Dictionary).dead),
		"mode 16's inherited 45-second watchdog should arm resolution without killing or counting live enemies"
	)

	var liveness = _new_simulation(1)
	liveness._phase = Simulation.PHASE_WARP_MALFUNCTION
	liveness._enemy_liveness_idle_updates = Simulation.LEVEL_LIVENESS_UPDATE_LIMIT
	liveness._level_total_entities = 10
	liveness._level_killed_entities = 0
	liveness._level_escaped_entities = 0
	liveness._level_resolved = false
	liveness._enemies.clear()
	liveness._update_enemies()
	_expect(
		int(liveness._enemy_liveness_idle_updates) == 0
		and int(liveness._level_killed_entities) == 0
		and not bool(liveness._level_resolved),
		"the remake-only ordinary-level liveness guard must stay disabled in mode 16"
	)


func _test_rank_promotion_runtime_contract() -> void:
	var fireworks = _new_simulation(4)
	fireworks._rng.seed(1)
	fireworks._shared.rank = 1
	fireworks._begin_rank_promotion(0)
	fireworks._tick = int(fireworks._rank_promotion_minimum_tick) - 1
	var draws_before := int(fireworks._rng.draw_count)
	fireworks._step_rank_promotion()
	var firework_event: Dictionary = {}
	var promotion_voice_events: Array[Dictionary] = []
	for event_value in fireworks._events:
		var event: Dictionary = event_value
		if String(event.get("type", "")) == "rank_promotion_firework":
			firework_event = event
		elif String(event.get("type", "")) == "rank_promotion_voice":
			promotion_voice_events.append(event)
	_expect(
		int(fireworks._rng.draw_count) == draws_before + 82
		and not firework_event.is_empty()
		and int(firework_event.get("particle_count", 0)) == 12
		and not bool(firework_event.get("secondary", true))
		and int(firework_event.get("retail_pan_index", 0)) == 81
		and String(firework_event.get("sfx_key", "")) == "explo3",
		"seed one should reproduce the bounded mode-0x14 sparkle trace and all 82 shared-generator draws"
	)
	_expect(
		promotion_voice_events.size() == 3
		and String(promotion_voice_events[0].get("voice_key", "")) == "congratulations"
		and int(promotion_voice_events[0].get("queue_padding_ms", -1)) == 100
		and String(promotion_voice_events[1].get("voice_key", "")) == "lieutenant"
		and int(promotion_voice_events[1].get("queue_padding_ms", -1)) == 50
		and String(promotion_voice_events[2].get("voice_key", "")) == "rank"
		and int(promotion_voice_events[2].get("queue_padding_ms", -1)) == 50
		and not promotion_voice_events[0].has("delay_ms")
		and not promotion_voice_events[1].has("delay_ms")
		and not promotion_voice_events[2].has("delay_ms"),
		"the default first promotion should queue the recovered congratulations-lieutenant-rank phrase"
	)

	var rank_contracts: Array = fireworks._catalog.bonus_modes.rank_promotion.ranks
	for rank_index in range(rank_contracts.size()):
		fireworks._events.clear()
		fireworks._shared.rank = rank_index + 1
		fireworks._begin_rank_promotion(0)
		var expected_queue: Array = rank_contracts[rank_index].queue
		var actual_queue: Array[Dictionary] = []
		for event_value in fireworks._events:
			var event: Dictionary = event_value
			if String(event.get("type", "")) == "rank_promotion_voice":
				actual_queue.append(event)
		_expect(
			actual_queue.size() == expected_queue.size(),
			"rank %d should emit every executable-pinned voice cue" % (rank_index + 1)
		)
		for queue_index in range(mini(actual_queue.size(), expected_queue.size())):
			var expected_cue: Dictionary = expected_queue[queue_index]
			var actual_cue: Dictionary = actual_queue[queue_index]
			_expect(
				String(actual_cue.get("voice_key", ""))
				== String(expected_cue.get("key", ""))
				and int(actual_cue.get("queue_padding_ms", -1))
				== int(expected_cue.get("padding_ms", -2))
				and int(actual_cue.get("queue_index", -1)) == queue_index
				and int(actual_cue.get("seat_id", -1)) == 0,
				"rank %d cue %d should preserve exact key, order, padding, and owner"
				% [rank_index + 1, queue_index]
			)

	var held_fire = _new_simulation(4)
	held_fire._rng.seed(2)
	held_fire._shared.rank = 1
	held_fire._begin_rank_promotion(0)
	var minimum_tick := int(held_fire._rank_promotion_minimum_tick)
	held_fire.set_input(0, Simulation.ACTION_FIRE)
	held_fire._tick = minimum_tick - 1
	held_fire._step_rank_promotion()
	_expect(
		String(held_fire._phase) == Simulation.PHASE_RANK_PROMOTION,
		"promotion fire polling should remain locked through the tick before four seconds"
	)
	held_fire._tick = minimum_tick
	var boundary_snapshot: Dictionary = held_fire.get_snapshot()
	_expect(
		bool(boundary_snapshot.rank_promotion.can_continue)
		and bool(boundary_snapshot.rank_promotion.prompt_visible)
		and String(boundary_snapshot.rank_promotion.rank_name) == "LIEUTENANT"
		and int(boundary_snapshot.rank_promotion.badge_y) == 13,
		"the exact four-second boundary should expose the held-fire gate and first prompt blink"
	)
	_expect(
		Simulation.RANK_NAMES[8] == "ADMIRAL 1 SILVER STAR"
		and int(Simulation.RANK_BADGE_Y[8]) == 52,
		"higher rank names and repeated base-badge rows should follow the recovered executable tables"
	)
	held_fire._step_rank_promotion()
	_expect(
		String(held_fire._phase) == Simulation.PHASE_GET_READY,
		"a fire button held across the minimum boundary should dismiss promotion at equality"
	)

	var timeout = _new_simulation(4)
	timeout._rng.seed(2)
	timeout._shared.rank = 1
	timeout._begin_rank_promotion(0)
	timeout._tick = int(timeout._rank_promotion_timeout_tick)
	timeout._step_rank_promotion()
	_expect(
		String(timeout._phase) == Simulation.PHASE_GET_READY,
		"the 1,200,000-ms retail safety deadline should auto-dismiss promotion at equality"
	)


func _test_first_shop_effect_contracts() -> void:
	var simulation = _new_simulation(4)
	var progression: Dictionary = simulation._shared
	progression.weapon_id = 1
	_expect(
		not simulation._can_apply_shop_effect(simulation._shop_by_id[3]),
		"the first shop should reject buying the already-equipped weapon"
	)
	progression.auto_fire = false
	progression.upgrades.super_autofire = 1
	_expect(
		not simulation._can_apply_shop_effect(simulation._shop_by_id[7]),
		"Auto Fire should reject while Super Auto Fire is active"
	)
	progression.upgrades.erase("super_autofire")

	progression.bonus_time = 43
	_expect(
		simulation._can_apply_shop_effect(simulation._shop_by_id[15]),
		"Extra Time should accept any pre-purchase value below 45"
	)
	simulation._apply_shop_effect(simulation._shop_by_id[15], 0)
	_expect(
		int(progression.bonus_time) == 48
		and not simulation._can_apply_shop_effect(simulation._shop_by_id[15]),
		"shop Extra Time should add five without a post-clamp, then reject at or above 45"
	)

	progression.rank_markers = 0
	var expected_masks := [0x20, 0x30, 0x38, 0x3c, 0x3e, 0x3f]
	for expected_mask in expected_masks:
		simulation._apply_shop_effect(simulation._shop_by_id[14], 0)
		_expect(
			int(progression.rank_markers) == expected_mask,
			"Rank Marker should add the highest missing retail mask bit"
		)
	_expect(
		int(progression.score) == 0 and not simulation._rank_full_reward_claimed,
		"completing the six-bit rank mask should not pay on the same purchase"
	)
	progression.score_multiplier = 2
	simulation._apply_shop_effect(simulation._shop_by_id[14], 0)
	_expect(
		int(progression.score) == 2000000
		and simulation._rank_full_reward_claimed
		and not simulation._can_apply_shop_effect(simulation._shop_by_id[14]),
		"a subsequent full-mask purchase should pay one multiplied million once per level"
	)
	_expect(
		simulation._cash_out_full_rank_mask_on_shop_exit(0)
		and int(progression.score) == 4000000
		and int(progression.rank_markers) == 0
		and int(progression.rank) == 1
		and int(progression.highest_rank) == 1
		and simulation._rank_full_reward_claimed,
		"shop exit should independently clear a full mask, pay another multiplied million, and promote rank"
	)
	var capped_rank = _new_simulation(4)
	capped_rank._shared.rank_markers = 0x3f
	capped_rank._shared.rank = Simulation.DEFAULT_RANK_CAP
	_expect(
		not capped_rank._cash_out_full_rank_mask_on_shop_exit(0)
		and int(capped_rank._shared.rank_markers) == 0
		and int(capped_rank._shared.rank) == Simulation.DEFAULT_RANK_CAP
		and int(capped_rank._shared.score) == Simulation.FULL_RANK_MASK_CASHOUT_SCORE,
		"a capped rank should still clear and cash the mask without incrementing beyond the retail default cap"
	)
	simulation._initialize_level_resolution_state(simulation._levels_by_id[4])
	_expect(
		simulation._can_apply_shop_effect(simulation._shop_by_id[14]),
		"level setup should reset the full-mask reward guard"
	)

	var secret = _new_simulation(4)
	progression = secret._shared
	var lives_before := int(progression.lives)
	var armour_before := int(progression.armour_fp)
	var capacity_before := int(progression.bullet_capacity)
	var speed_before := int(progression.speed_fp)
	var time_before := int(progression.bonus_time)
	var draws_before := int(secret._rng.draw_count)
	secret._apply_shop_effect(secret._shop_by_id[13], 0)
	var selected := int(progression.selected_secret_id)
	_expect(
		selected >= 0 and selected < 30
		and int(secret._rng.draw_count) == draws_before + 1
		and int(progression.secret_session_seen[selected]) == 1,
		"a normal Game Secret should select one of 30 images and mark it seen"
	)
	_expect(
		int(progression.lives) == lives_before
		and int(progression.armour_fp) == armour_before
		and int(progression.bullet_capacity) == capacity_before
		and int(progression.speed_fp) == speed_before
		and int(progression.bonus_time) == time_before,
		"Game Secret should not mutate fighter, weapon, speed, or bonus-time stats"
	)

	var exhausted = _new_simulation(4)
	progression = exhausted._shared
	progression.secret_session_earned.fill(1)
	progression.secret_session_seen.fill(1)
	draws_before = int(exhausted._rng.draw_count)
	exhausted._apply_secret(progression)
	_expect(
		int(exhausted._rng.draw_count) == draws_before + 251,
		"Game Secret should use the retail 251-attempt escape when every image is exhausted"
	)

	var fixed = Simulation.new()
	_expect(fixed.configure({
		"mode": "solo",
		"difficulty": "normal",
		"collision_mode": "simple",
		"start_level": 4,
		"profile_kind": 2,
		"seed": 91,
		"record_replay": false,
	}), "fixed-secret profile simulation should configure")
	draws_before = int(fixed._rng.draw_count)
	fixed._apply_secret(fixed._shared)
	_expect(
		int(fixed._shared.selected_secret_id) == 30
		and int(fixed._rng.draw_count) == draws_before,
		"profile kind 2 should select secret image 30 without consuming RNG"
	)


func _test_bonus_catalog_and_drop_contract() -> void:
	var catalog: Dictionary = Catalog.load_catalog()
	_expect(bool(catalog.ok), "bonus fidelity test should load authored content")
	if not bool(catalog.ok):
		return
	var bonuses: Array = catalog.bonuses
	var expected_weights := [
		45, 45, 45, 45, 45, 111, 53, 90, 90, 130, 130, 65, 80, 80, 80,
		20, 140, 20, 60, 35, 50, 25, 35, 35, 35, 5, 25, 10, 15, 300, 150,
		75, 30, 8, 10, 15, 20,
	]
	var expected_source_y := [
		60, 80, 100, 120, 140, 20, 460, 160, 180, 280, 300, 40, 340, 320,
		360, 240, 380, 400, 260, 420, 0, 500, 520, 540, 560, 660, 440, 200,
		480, 600, 580, 620, 640, 220, 700, 680, 720,
	]
	_expect(bonuses.size() == 37, "retail bonus catalog should contain exactly 37 types")
	var weight_total := 0
	for bonus_index in range(bonuses.size()):
		var bonus: Dictionary = bonuses[bonus_index]
		weight_total += int(bonus.weight)
		_expect(
			int(bonus.id) == bonus_index
			and int(bonus.weight) == expected_weights[bonus_index]
			and int(bonus.source_y) == expected_source_y[bonus_index]
			and int(bonus.width) == 20
			and int(bonus.height) == 20
			and int(bonus.frame_count) == 10,
			"bonus type %d should preserve its executable row, weight, and 20x20x10 geometry" % bonus_index
		)
	_expect(
		weight_total == 2252,
		"bonus weights should retain the 2,252 total used by the executable's 2,251-range sampler"
	)

	var denominators := {"easy": 18, "normal": 28, "hard": 38, "ace": 48}
	for difficulty_value in denominators.keys():
		var difficulty := String(difficulty_value)
		var simulation = _new_simulation(1, "solo", difficulty, 73)
		simulation._rng.seed(73)
		var oracle = Rng.new(73)
		var denominator := int(denominators[difficulty])
		var expected_pass := 1 + int(oracle.next_u32() % (denominator - 1)) < 4
		var actual_pass := bool(simulation._retail_bonus_drop_passes())
		_expect(
			actual_pass == expected_pass
			and int(simulation._rng.draw_count) == 1,
			"%s bonus drop should use one retail draw with denominator %d" % [
				difficulty,
				denominator,
			]
		)

	var spawn = _new_simulation(1)
	spawn._rng.seed(12345)
	spawn._pickups.clear()
	spawn._spawn_retail_bonus({
		"x_fp": 300 * Simulation.FP_ONE,
		"y_fp": 200 * Simulation.FP_ONE,
		"authored_state": "return",
	})
	_expect(spawn._pickups.size() == 1, "a free bonus slot should accept a retail drop")
	if spawn._pickups.size() == 1:
		var pickup: Dictionary = spawn._pickups[0]
		_expect(
			int(pickup.x_fp) == 295 * Simulation.FP_ONE
			and int(pickup.y_fp) == 194 * Simulation.FP_ONE,
			"seed 12345 should preserve jitter-first spawning at the alien top-left"
		)
		_expect(
			int(pickup.bonus_type) == 29
			and int(pickup.animation_frame) == 4
			and int(spawn._rng.draw_count) == 5,
			"bonus spawn should draw jitter, velocity, animation period, type, then phase"
		)
		_expect(
			int(pickup.velocity_y_fp) >= 78643
			and int(pickup.velocity_y_fp) <= 117965
			and int(pickup.animation_period_fp) >= 3 * Simulation.FP_ONE
			and int(pickup.animation_period_fp) <= 7 * Simulation.FP_ONE,
			"bonus fall velocity and animation period should stay in their executable float ranges"
		)

	var full_pool = _new_simulation(1)
	_spawn_authored_entities(full_pool)
	for slot in range(Simulation.BONUS_POOL_SLOT_COUNT):
		full_pool._pickups.append({})
	full_pool._rng.seed(12345)
	full_pool._kill_enemy(full_pool._enemies[0], 0)
	_expect(
		int(full_pool._rng.draw_count) == 0
		and full_pool._pickups.size() == Simulation.BONUS_POOL_SLOT_COUNT,
		"a full 150-slot bonus pool should skip the drop roll and consume no RNG"
	)

	var expiry = _new_simulation(1)
	expiry._pickups = [{
		"id": 1,
		"kind": "money",
		"x_fp": 0,
		"y_fp": 640 * Simulation.FP_ONE,
		"velocity_y_fp": 0,
		"expired": false,
	}]
	expiry._remove_expired_entities()
	_expect(expiry._pickups.size() == 1, "a bonus should survive at exact center y=640")
	expiry._pickups[0].y_fp = 640 * Simulation.FP_ONE + 1
	expiry._remove_expired_entities()
	_expect(expiry._pickups.is_empty(), "a bonus should expire one fixed unit below center y=640")


func _test_retail_bonus_effect_contracts() -> void:
	var multiplier = _new_simulation(1)
	var progression: Dictionary = multiplier._shared
	multiplier._apply_retail_bonus_type(7, progression, 0)
	_expect(
		int(progression.score_multiplier) == 2
		and int(progression.score_multiplier_ticks) == 1201,
		"x2 should use the fresh 20-second bonus-time deadline plus strict-equality tick"
	)
	for tick in range(1200):
		multiplier._update_progression_timers()
	_expect(
		int(progression.score_multiplier) == 2
		and int(progression.score_multiplier_ticks) == 1,
		"x2 should remain active through exact deadline equality"
	)
	multiplier._update_progression_timers()
	_expect(
		int(progression.score_multiplier) == 1
		and int(progression.score_multiplier_ticks) == 0,
		"x2 should clear on the tick after its equality deadline"
	)

	var letters = _new_simulation(1)
	progression = letters._shared
	for letter_id in range(5):
		letters._apply_retail_bonus_type(letter_id, progression, 0)
	_expect(
		int(progression.lives) == Simulation.MAX_FIGHTERS
		and int(progression.armour_fp) == Simulation.MAX_ARMOUR_CHARGES * Simulation.FP_ONE
		and int(progression.score) == 1000000
		and int(progression.letter_bits) == 0x1f,
		"an exact EXTRA sequence fills fighters and armour, awards the all-collected score, and keeps the flags"
	)
	# Retail keeps the five flags set, so the next collect is a duplicate that
	# scores 100 and re-fires the (now capped) all-collected score award.
	letters._apply_retail_bonus_type(0, progression, 0)
	_expect(
		int(progression.score) == 1000100 + 1000000,
		"a duplicate EXTRA letter awards 100 and re-fires the capped all-collected score"
	)

	var extra_time = _new_simulation(1)
	progression = extra_time._shared
	progression.bonus_time = 43
	extra_time._apply_retail_bonus_type(28, progression, 0)
	_expect(
		int(progression.bonus_time) == 48,
		"Extra Time should retain the retail pre-check overshoot above the 45-second maximum"
	)
	extra_time._apply_retail_bonus_type(28, progression, 0)
	_expect(
		int(progression.bonus_time) == 45
		and int(progression.score) == 25000,
		"Extra Time at or above maximum should clamp to 45 and award 25,000"
	)

	var money = _new_simulation(1)
	progression = money._shared
	progression.money = Simulation.MAX_MONEY - 5
	money._apply_retail_bonus_type(29, progression, 0)
	_expect(
		int(progression.money) == Simulation.MAX_MONEY
		and int(progression.score) == 100,
		"overflowing the +10 money bonus should cap cash and convert it to 100 score"
	)

	var suckers = _new_simulation(1)
	progression = suckers._shared
	progression.weapon_id = 3
	progression.bullet_capacity = 5
	for bonus_type in [22, 23, 24]:
		suckers._apply_retail_bonus_type(bonus_type, progression, 0)
	_expect(
		int(progression.weapon_id) == 4
		and int(progression.bullet_capacity) == 25
		and int(progression.speed_fp)
		>= int(suckers._difficulty.player_base_speed_fp)
		+ 10 * int(suckers._difficulty.player_speed_upgrade_fp)
		and int(progression.bonus_time) == 30
		and int(progression.sucker_bits) == 0,
		"collecting all three sucker types should apply the executable's restorative bundle"
	)

	var freeze = _new_simulation(1)
	progression = freeze._shared
	freeze._apply_retail_bonus_type(35, progression, 0)
	_expect(
		int(progression.freeze_ticks) == 601,
		"bonus type 35 should freeze alien motion for ten seconds through equality"
	)

	var bomb = _new_simulation(1)
	_spawn_authored_entities(bomb)
	bomb._apply_retail_bonus_type(19, bomb._shared, 0)
	var all_dead := true
	for enemy_value in bomb._enemies:
		all_dead = all_dead and bool((enemy_value as Dictionary).dead)
	_expect(
		all_dead
		and int(bomb._shared.score) == 0
		and int(bomb._level_killed_entities) == 18,
		"Gem Bomb should clear eligible level-1 aliens through kill accounting without score, group, or drops"
	)


func _test_drunk_and_bonus_mode_boundaries() -> void:
	var drunk = _new_simulation(1)
	var player: Dictionary = drunk._players[0]
	var progression: Dictionary = drunk._shared
	player.x_fp = 400 * Simulation.FP_ONE
	drunk._input_masks[0] = Simulation.ACTION_RIGHT
	drunk._apply_retail_bonus_type(34, progression, 0)
	var starting_x := int(player.x_fp)
	drunk._update_players()
	_expect(
		int(player.x_fp) < starting_x,
		"Drunk should reverse right input for its complete live deadline"
	)
	progression.drunk_ticks = 0
	starting_x = int(player.x_fp)
	drunk._update_players()
	_expect(
		int(player.x_fp) > starting_x,
		"normal horizontal direction should return immediately after Drunk expires"
	)
	progression.drunk_ticks = 100
	player.x_fp = 400 * Simulation.FP_ONE
	player.sprite_phase_half_steps = 10
	drunk._input_masks[0] = Simulation.ACTION_LEFT | Simulation.ACTION_RIGHT
	drunk._update_players()
	_expect(
		int(player.x_fp) > 400 * Simulation.FP_ONE
		and int(player.sprite_phase_half_steps) == 9,
		"both held should retain retail left-key priority, bank left, then travel right under Drunk"
	)
	progression.scoop_ticks = 100
	progression.mirror_ticks = 100
	drunk._damage_player(player, Simulation.FP_ONE)
	_expect(
		int(progression.drunk_ticks) == 0
		and int(progression.scoop_ticks) == 0
		and int(progression.mirror_ticks) == 0,
		"a lethal unarmoured hit should clear Drunk, Scoop, and Mirror immediately"
	)

	var memory = _new_simulation(1)
	_spawn_authored_entities(memory)
	player = memory._players[0]
	progression = memory._shared
	var level_tick_before := int(memory._level_tick)
	var player_x_before := int(player.x_fp)
	var enemy_x_before := int((memory._enemies[0] as Dictionary).x_fp)
	memory._apply_retail_bonus_type(6, progression, 0)
	var memory_snapshot: Dictionary = memory.get_snapshot().bonus_mode
	_expect(
		String(memory._phase) == Simulation.PHASE_BONUS_MODE
		and String(progression.special_mode) == "memory_station"
		and memory_snapshot.tiles.size() == 16
		and int(memory_snapshot.remaining_ms) == 30_000,
		"Memory Station should enter its deterministic 4x4 retail controller and deadline"
	)
	memory._input_masks[0] = Simulation.ACTION_RIGHT
	memory.step()
	_expect(
		int(memory._level_tick) == level_tick_before
		and int(player.x_fp) == player_x_before
		and int((memory._enemies[0] as Dictionary).x_fp) == enemy_x_before
		and memory._projectiles.is_empty(),
		"ordinary movement, firing, enemy updates, and level time must stop inside Memory Station"
	)
	var equality_tick := int(memory._tick) + 1
	memory._memory_station._mode_deadline_ms = (
		equality_tick * 1000 / Simulation.TICKS_PER_SECOND
	)
	memory.step()
	_expect(
		String(memory._phase) == Simulation.PHASE_BONUS_MODE,
		"Memory Station should survive exact retail deadline equality"
	)
	memory.step()
	_expect(
		String(memory._phase) == Simulation.PHASE_LEVEL
		and String(progression.special_mode).is_empty(),
		"Memory Station failure should restore the unchanged ordinary combat state"
	)

	var meteor = _new_simulation(1)
	meteor._pickups = [{"expired": false}, {"expired": false}]
	meteor._apply_retail_bonus_type(20, meteor._shared, 0)
	_expect(
		String(meteor._phase) == Simulation.PHASE_BONUS_MODE
		and String(meteor._shared.special_mode) == "meteor_storm"
		and meteor._pickups.is_empty()
		and int(meteor.get_snapshot().bonus_mode.slot_count) == 30
		and int(meteor.get_snapshot().bonus_mode.intro_remaining_ms) == 4000,
		"Meteor Storm should clear the live bonus pool and enter its 30-slot retail controller"
	)


func _test_captive_weapon_mapping_and_projectile_animation() -> void:
	var expected_graphs := [
		[48],
		[47],
		[45, 46],
		[4, 63, 65, 64],
		[42, 43, 44],
		[38],
		[58],
		[35],
		[39, 40, 41],
		[67],
	]
	var expected_damage := [65536, 65536, 65536, 163840, 262144, 196608, 196608, 327680, 327680, 196608]
	for weapon_id in range(expected_graphs.size()):
		var simulation = _new_simulation(1)
		var player: Dictionary = simulation._players[0]
		simulation._shared.weapon_id = mini(weapon_id, 8)
		simulation._shared.bullet_capacity = 50
		simulation._enemies = [{
			"dead": false,
			"behavior_state_id": 8,
			"captured_owner_seat": 0,
			"captured_side": 0,
			"captured_latched": true,
		}]
		simulation._projectiles.clear()
		var main_count := 0
		if weapon_id < 9:
			simulation._fire_player_weapon(player)
			main_count = int((simulation._weapons_by_id[weapon_id] as Dictionary).projectiles.size())
		else:
			simulation._spawn_player_side_graph(
				{"id": 9, "projectiles": [], "damage_fp": 0},
				simulation._shared,
				player,
				false,
				1
			)
		var captive_prototypes: Array = []
		var captive_fields_exact := true
		for projectile_index in range(main_count, simulation._projectiles.size()):
			var projectile: Dictionary = simulation._projectiles[projectile_index]
			captive_prototypes.append(int(projectile.prototype_id))
			captive_fields_exact = (
				captive_fields_exact
				and int(projectile.damage_fp) == int(expected_damage[weapon_id])
				and int(projectile.capacity_contribution) == 0
			)
		_expect(
			captive_prototypes == expected_graphs[weapon_id]
			and captive_fields_exact,
			"Scoop weapon %d should use the executable's mapped graph, damage, and zero contribution" % weapon_id
		)

	var animated = _new_simulation(1)
	animated._projectiles.clear()
	animated._fire_player_weapon(animated._players[0])
	var ordinary: Dictionary = animated._projectiles[0]
	animated._tick += 1
	animated._update_player_projectiles()
	_expect(
		int(ordinary.prototype_id) == 0
		and int(ordinary.animation_countdown_fp) == 0,
		"ordinary projectile animation should stay on its frame at countdown equality"
	)
	animated._tick += 1
	animated._update_player_projectiles()
	_expect(
		int(ordinary.prototype_id) == 2
		and int(ordinary.animation_countdown_fp) == Simulation.FP_ONE,
		"ordinary projectile animation should advance through the executable next-frame table after underflow"
	)

	var beam = _new_simulation(1)
	beam._shared.weapon_id = 7
	beam._shared.bullet_capacity = 50
	beam._enemies = [{
		"dead": false,
		"behavior_state_id": 8,
		"captured_owner_seat": 0,
		"captured_side": 0,
		"captured_latched": true,
	}]
	beam._projectiles.clear()
	beam._fire_player_weapon(beam._players[0])
	var mini_beam: Dictionary = beam._projectiles[1]
	for update_index in range(3):
		beam._tick += 1
		beam._update_player_projectiles()
	_expect(
		int(mini_beam.prototype_id) == 57
		and not bool(mini_beam.expired),
		"the captive Laser should advance 35 -> 36 -> 37 -> 57 once per update"
	)
	beam._tick += 1
	beam._update_player_projectiles()
	_expect(
		bool(mini_beam.expired),
		"the captive Laser should retire on the update after frame 57's collision opportunity"
	)


func _test_mirror_runtime_contract() -> void:
	var simulation = _new_simulation(1)
	var player: Dictionary = simulation._players[0]
	var progression: Dictionary = simulation._shared
	player.x_fp = 310 * Simulation.FP_ONE
	simulation._apply_retail_bonus_type(25, progression, 0)
	_expect(
		int(progression.mirror_ticks) == 1201
		and int(player.mirror_anchor_x_fp) == int(player.x_fp),
		"Mirror should set the strict-equality duration and copy the movement anchor"
	)
	player.x_fp = 500 * Simulation.FP_ONE
	player.mirror_anchor_x_fp = 310 * Simulation.FP_ONE
	simulation._input_masks[0] = Simulation.ACTION_RIGHT
	simulation._update_players()
	_expect(
		int(player.x_fp) > 310 * Simulation.FP_ONE
		and int(player.x_fp) < 400 * Simulation.FP_ONE
		and int(player.mirror_anchor_x_fp) == int(player.x_fp),
		"active Mirror movement should integrate from its retail anchor, not a temporary draw X"
	)
	var snapshot: Dictionary = simulation.get_snapshot().players[0]
	_expect(
		bool(snapshot.mirror_active)
		and int(snapshot.mirror_x_fp)
		== Simulation.FIELD_WIDTH * Simulation.FP_ONE - int(snapshot.x_fp),
		"the authoritative snapshot should expose the reflected fighter center"
	)

	simulation._projectiles.clear()
	progression.bullet_capacity = 1
	simulation._fire_player_weapon(player)
	var mirror_contributions_zero := true
	for projectile_value in simulation._projectiles:
		mirror_contributions_zero = (
			mirror_contributions_zero
			and int((projectile_value as Dictionary).capacity_contribution) == 0
		)
	_expect(
		simulation._projectiles.size() == 2
		and mirror_contributions_zero,
		"Mirror should fire both complete non-counting fighter graphs below its 100-shot gate"
	)
	var first_volley_size: int = simulation._projectiles.size()
	simulation._fire_player_weapon(player)
	_expect(
		simulation._projectiles.size() == first_volley_size * 2,
		"subsequent Mirror volleys should remain non-counting in retail accounting"
	)
	var physical_pool = _new_simulation(1)
	physical_pool._shared.mirror_ticks = 1000
	physical_pool._projectiles.clear()
	for volley_index in range(60):
		physical_pool._fire_player_weapon(physical_pool._players[0])
	physical_pool._events.clear()
	physical_pool._fire_player_weapon(physical_pool._players[0])
	_expect(
		physical_pool._projectiles.size() == Simulation.PLAYER_PROJECTILE_SLOT_COUNT
		and physical_pool._events.is_empty(),
		"a full retail player-shot pool should allocate nothing and emit no firing event"
	)
	var reuse = _new_simulation(1)
	reuse._projectiles.clear()
	for volley_index in range(3):
		reuse._fire_player_weapon(reuse._players[0])
	(reuse._projectiles[0] as Dictionary).expired = true
	reuse._remove_expired_entities()
	reuse._fire_player_weapon(reuse._players[0])
	_expect(
		int((reuse._projectiles.back() as Dictionary).player_slot) == 0,
		"the fixed player-shot pool should reuse its lowest free slot instead of appending in age order"
	)

	var ordered = _new_simulation(1)
	ordered._enemies = [{
		"id": 8100,
		"dead": false,
		"authored_lvd": false,
		"authored_state": "entry",
		"behavior_state_id": 1,
		"x_fp": 400 * Simulation.FP_ONE,
		"y_fp": 200 * Simulation.FP_ONE,
		"width": 32,
		"height": 32,
		"health_fp": 2 * Simulation.FP_ONE,
		"max_health_fp": 2 * Simulation.FP_ONE,
		"score": 0,
		"sprite": "alien001",
	}]
	var high_slot := {
		"id": 8200,
		"owner_kind": "player",
		"owner_id": 0,
		"player_slot": 8,
		"x_fp": 400 * Simulation.FP_ONE,
		"y_fp": 200 * Simulation.FP_ONE,
		"width": 8,
		"height": 8,
		"damage_fp": 2 * Simulation.FP_ONE,
		"prototype_id": 0,
		"expired": false,
	}
	var low_slot := high_slot.duplicate(true)
	low_slot.id = 8201
	low_slot.player_slot = 0
	low_slot.damage_fp = Simulation.FP_ONE
	ordered._projectiles = [high_slot, low_slot]
	ordered._resolve_player_projectile_collisions()
	_expect(
		bool(low_slot.expired)
		and bool(high_slot.expired)
		and bool((ordered._enemies[0] as Dictionary).dead),
		"player-shot collision should scan ascending retail slots even when storage age is reversed"
	)
	for projectile_index in range(100):
		simulation._projectiles.append({
			"id": 2000 + projectile_index,
			"owner_kind": "player",
			"owner_id": 0,
			"expired": false,
			"capacity_contribution": 1,
		})
	var blocked_size: int = simulation._projectiles.size()
	simulation._fire_player_weapon(player)
	_expect(
		simulation._projectiles.size() == blocked_size,
		"Mirror should block exactly when the counted live total reaches 100"
	)

	var shots = _new_simulation(1)
	player = shots._players[0]
	progression = shots._shared
	progression.mirror_ticks = 100
	progression.armour_fp = 2 * Simulation.FP_ONE
	player.x_fp = 300 * Simulation.FP_ONE
	shots._projectiles.clear()
	shots._rng.seed(404)
	var shot_oracle = Rng.new(404)
	var shot_reflected := (shot_oracle.next_u32() & 0x1ff) >= 256
	var selected_x := (
		Simulation.FIELD_WIDTH * Simulation.FP_ONE - int(player.x_fp)
		if shot_reflected
		else int(player.x_fp)
	)
	shots._projectiles.append({
		"id": 900,
		"owner_kind": "enemy",
		"owner_id": -1,
		"common_slot": -1,
		"x_fp": selected_x,
		"y_fp": int(player.y_fp),
		"velocity_x_fp": 0,
		"velocity_y_fp": 0,
		"width": 32,
		"height": 32,
		"damage_fp": Simulation.FP_ONE,
		"prototype_id": -1,
		"enemy_projectile_type": 7,
		"enemy_sheet": "alien001",
		"animation_frame": 0,
		"expired": false,
	})
	shots._resolve_enemy_projectile_collisions()
	_expect(
		int(shots._rng.draw_count) == 1
		and bool((shots._projectiles[0] as Dictionary).expired)
		and int(progression.armour_fp) == Simulation.FP_ONE,
		"alien shots should consume one raw 9-bit Mirror selector before the whole pool scan"
	)

	var pickups = _new_simulation(1)
	player = pickups._players[0]
	progression = pickups._shared
	progression.mirror_ticks = 100
	player.x_fp = 300 * Simulation.FP_ONE
	pickups._rng.seed(818)
	var pickup_oracle = Rng.new(818)
	var pickup_reflected := (pickup_oracle.next_u32() & 0x1ff) >= 256
	selected_x = (
		Simulation.FIELD_WIDTH * Simulation.FP_ONE - int(player.x_fp)
		if pickup_reflected
		else int(player.x_fp)
	)
	var rejected_x := (
		int(player.x_fp)
		if pickup_reflected
		else Simulation.FIELD_WIDTH * Simulation.FP_ONE - int(player.x_fp)
	)
	pickups._pickups = [
		_test_pickup(901, selected_x, int(player.y_fp)),
		_test_pickup(902, rejected_x, int(player.y_fp)),
	]
	pickups._update_pickups()
	_expect(
		int(pickups._rng.draw_count) == 1
		and bool((pickups._pickups[0] as Dictionary).expired)
		and not bool((pickups._pickups[1] as Dictionary).expired),
		"falling bonuses should reuse one raw 9-bit Mirror selector for all 150 slots"
	)

	var rendered = _new_simulation(1)
	player = rendered._players[0]
	progression = rendered._shared
	progression.mirror_ticks = 100
	player.x_fp = 300 * Simulation.FP_ONE + 12345
	var render_oracle = Rng.new(5150)
	var expected_render_sides := [
		(render_oracle.next_u32() & 0x7f) < 64,
		(render_oracle.next_u32() & 0x7f) < 64,
	]
	rendered._rng.seed(5150)
	rendered._enemies = []
	for side in range(2):
		var target_offset := -32 * Simulation.FP_ONE if side == 0 else 40 * Simulation.FP_ONE
		var captive := {
			"id": 950 + side,
			"dead": false,
			"authored_lvd": true,
			"authored_state": "captured",
			"behavior_state_id": 8,
			"captured_owner_seat": 0,
			"captured_side": side,
			"captured_latched": true,
			"capture_offset_fp": target_offset,
			"x_fp": int(player.x_fp) - 4 * Simulation.FP_ONE + target_offset,
			"y_fp": int(player.y_fp) + 2 * Simulation.FP_ONE,
			"width": 32,
			"height": 32,
			"health_fp": Simulation.FP_ONE,
			"max_health_fp": Simulation.FP_ONE,
			"sprite": "alien001",
			"mask_id": "alien001",
			"authored_sprite_frame": 0,
		}
		rendered._enemies.append(captive)
		rendered._update_captured_enemy(captive)
	var rendered_snapshot: Array = rendered.get_snapshot().enemies
	var render_sides_exact := true
	var render_x_exact := true
	for side in range(2):
		var captive: Dictionary = rendered._enemies[side]
		var snapshot_enemy: Dictionary = rendered_snapshot[side]
		render_sides_exact = (
			render_sides_exact
			and bool(captive.captured_render_mirrored) == bool(expected_render_sides[side])
		)
		render_x_exact = (
			render_x_exact
			and int(snapshot_enemy.render_x_fp) == rendered._captured_render_x_fp(
				captive,
				bool(expected_render_sides[side])
			)
		)
	_expect(
		int(rendered._rng.draw_count) == 2
		and render_sides_exact
		and render_x_exact,
		"each rendered Scoop captive should consume its own seven-bit Mirror side draw and export the exact quantized X"
	)


func _test_pickup(entity_id: int, x_fp: int, y_fp: int) -> Dictionary:
	return {
		"id": entity_id,
		"kind": "money",
		"effect_key": "money",
		"variant": 0,
		"animation_frame": 0,
		"animation_countdown_fp": 3 * Simulation.FP_ONE,
		"animation_period_fp": 3 * Simulation.FP_ONE,
		"x_fp": x_fp,
		"y_fp": y_fp,
		"velocity_x_fp": 0,
		"velocity_y_fp": 0,
		"width": 20,
		"height": 20,
		"expired": false,
	}


func _new_simulation(
	level_id: int,
	mode: String = "solo",
	difficulty: String = "normal",
	seed: int = 5150
):
	var simulation = Simulation.new()
	_expect(simulation.configure({
		"mode": mode,
		"difficulty": difficulty,
		"collision_mode": "simple",
		"start_level": level_id,
		"end_level": 5,
		"seed": seed,
		"record_replay": false,
	}), "level %d %s/%s fidelity simulation should configure" % [
		level_id,
		mode,
		difficulty,
	])
	return simulation


func _spawn_authored_entities(simulation) -> void:
	simulation._level_tick = 1
	simulation._spawn_due_waves()


func _find_enemy_in_state(simulation, state: String) -> Dictionary:
	for enemy_value in simulation._enemies:
		var enemy: Dictionary = enemy_value
		if String(enemy.get("authored_state", "")) == state:
			return enemy
	return {}


func _prepare_state_four_enemy(enemy: Dictionary) -> void:
	enemy.dead = false
	enemy.authored_state = "return"
	enemy.behavior_state_id = 4
	enemy.x_fp = 400 * Simulation.FP_ONE
	enemy.y_fp = 300 * Simulation.FP_ONE
	enemy.velocity_x_fp = 0
	enemy.velocity_y_fp = 0
	enemy.acceleration_x_fp = 0
	enemy.state_four_velocity_x_fp = 0
	enemy.state_four_acceleration_x_fp = 0
	enemy.state_four_turn_countdown = 100
	enemy.animation_countdown_sixths = 600
	enemy.authored_animation_frame = 0
	enemy.animation_direction = 0


func _prepare_state_six_enemy(enemy: Dictionary) -> void:
	enemy.dead = false
	enemy.authored_state = "supplemental_large"
	enemy.behavior_state_id = 6
	enemy.x_fp = 400 * Simulation.FP_ONE
	enemy.y_fp = 300 * Simulation.FP_ONE
	enemy.heading = 0
	enemy.x_scale_fp = Simulation.FP_ONE
	enemy.y_scale_fp = Simulation.FP_ONE
	enemy.speed_fp = Simulation.FP_ONE
	enemy.behavior_timer_a = 0
	enemy.steering_countdown_fp = 100 * Simulation.FP_ONE
	enemy.steering_mode = 2
	enemy.heading_step_countdown_sixths = 600
	enemy.animation_countdown_sixths = 600


func _prepare_state_ten_enemy(enemy: Dictionary) -> void:
	enemy.dead = false
	enemy.authored_state = "state_ten"
	enemy.behavior_state_id = 10
	enemy.x_fp = 400 * Simulation.FP_ONE
	enemy.y_fp = 0
	enemy.horizontal_velocity_fp = 0
	enemy.horizontal_acceleration_fp = 0
	enemy.horizontal_flip_interval_sixths = 60
	enemy.horizontal_flip_countdown_sixths = 60
	enemy.vertical_velocity_fp = 0
	enemy.vertical_acceleration_fp = 0
	enemy.animation_countdown_sixths = 600


func _event_scores(events: Array, event_type: String) -> Array:
	var scores: Array = []
	for event_value in events:
		var event: Dictionary = event_value
		if String(event.get("type", "")) == event_type:
			scores.append(int(event.get("score", 0)))
	return scores


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

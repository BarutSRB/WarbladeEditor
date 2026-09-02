extends SceneTree

const Simulation := preload("res://src/sim/game_simulation.gd")
const CampaignTest := preload("res://tests/sim/test_campaign_through_thirty.gd")

const LEVEL_RESOURCE_COUNTS := {
	36: {1: 28, 2: 20},
	37: {1: 36},
	38: {1: 36},
	39: {1: 32, 2: 8},
	40: {1: 30},
	41: {1: 40},
	42: {1: 60},
	43: {1: 40},
	44: {1: 40, 2: 12},
	45: {1: 30},
	46: {1: 90},
	47: {1: 60},
	48: {1: 90},
	49: {1: 40},
}
const LEVEL_RESOURCE_SHEETS := {
	36: {1: "alien_green_lilla_t", 2: "alien_cyan_lilla_t"},
	37: {1: "alien_green_lilla_t"},
	38: {1: "alien_raudkule"},
	39: {1: "alien_raudkule", 2: "alien_raudkule2"},
	40: {1: "alien_raudkule"},
	41: {1: "alien_raudkule"},
	42: {1: "alien_blavinger_gf"},
	43: {1: "alien_blavinger_gf"},
	44: {1: "alien_blavinger_gf", 2: "alien_blavinger_gf2"},
	45: {1: "alien_blavinger_gf2"},
	46: {1: "alien_rbille"},
	47: {1: "alien_rbille"},
	48: {1: "alien_rbille"},
	49: {1: "alien_rbille"},
}
const LEVEL_RESOURCE_SCORES := {
	36: {1: 450, 2: 550},
	37: {1: 450},
	38: {1: 500},
	39: {1: 500, 2: 550},
	40: {1: 500},
	41: {1: 500},
	42: {1: 600},
	43: {1: 600},
	44: {1: 600, 2: 750},
	45: {1: 200},
	46: {1: 800},
	47: {1: 850},
	48: {1: 850},
	49: {1: 750},
}
const NEW_HMA_SHEETS := [
	"alien_raudkule",
	"alien_raudkule2",
	"alien_blavinger_gf",
	"alien_blavinger_gf2",
	"alien_rbille",
]

var _failures: Array[String] = []


func _initialize() -> void:
	_test_authored_resource_matrix()
	_test_new_hma_resources()
	_test_level_thirty_six_supplemental_records()
	_test_mode_two_and_escape_opcodes()
	_test_recurring_shop_routes()
	_test_mode_three_levels()
	_test_level_forty_nine_organic_campaign_driver()
	_test_default_and_retained_campaign_boundaries()
	if _failures.is_empty():
		print("LEVELS 36-49 TESTS PASSED")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _test_authored_resource_matrix() -> void:
	for level_id_value in LEVEL_RESOURCE_COUNTS:
		var level_id := int(level_id_value)
		var simulation = _new_level(level_id, 49, "simple", 4900 + level_id)
		if simulation == null:
			continue
		var ordinary: Array = simulation._enemies.filter(
			func(enemy: Dictionary) -> bool:
				return int(enemy.get("group_id", -1)) >= 0
		)
		var expected_counts := LEVEL_RESOURCE_COUNTS[level_id] as Dictionary
		var expected_total := 0
		for count_value in expected_counts.values():
			expected_total += int(count_value)
		_expect(
			ordinary.size() == expected_total,
			"level %d should spawn exactly %d authored ordinary enemies"
			% [level_id, expected_total]
		)
		for slot_value in expected_counts:
			var slot_id := int(slot_value)
			var matches: Array = ordinary.filter(
				func(enemy: Dictionary) -> bool:
					return int(enemy.get("resource_slot_id", -1)) == slot_id
			)
			_expect(
				matches.size() == int(expected_counts[slot_id]),
				"level %d resource slot %d should spawn %d enemies"
				% [level_id, slot_id, int(expected_counts[slot_id])]
			)
			var bindings_match := true
			for enemy_value in matches:
				var enemy := enemy_value as Dictionary
				bindings_match = bindings_match and (
					String(enemy.get("sprite", ""))
					== String((LEVEL_RESOURCE_SHEETS[level_id] as Dictionary)[slot_id])
					and int(enemy.get("score", -1))
					== int((LEVEL_RESOURCE_SCORES[level_id] as Dictionary)[slot_id])
				)
			_expect(
				bindings_match,
				"level %d slot %d should retain its exact sheet and kill score"
				% [level_id, slot_id]
			)


func _test_new_hma_resources() -> void:
	var simulation = _new_level(44, 49, "pixel", 4944)
	if simulation == null:
		return
	for sheet_id in NEW_HMA_SHEETS:
		_expect(
			simulation._hit_masks.has(sheet_id),
			"pixel mode should load the authoritative %s HMA" % sheet_id
		)


func _test_level_thirty_six_supplemental_records() -> void:
	var simulation = _new_level(36, 49, "simple", 4936)
	if simulation == null:
		return
	var supplemental: Array = simulation._enemies.filter(
		func(enemy: Dictionary) -> bool:
			return String(enemy.get("authored_state", "")) == "supplemental_large"
	)
	_expect(supplemental.size() == 3, "level 36 should spawn all three supplemental enemies")
	var cyan: Array = supplemental.filter(
		func(enemy: Dictionary) -> bool:
			return int(enemy.get("resource_slot_id", -1)) == 2
	)
	var green: Array = supplemental.filter(
		func(enemy: Dictionary) -> bool:
			return int(enemy.get("resource_slot_id", -1)) == 1
	)
	_expect(
		cyan.size() == 2
		and cyan.all(func(enemy: Dictionary) -> bool: return (
			String(enemy.get("sprite", "")) == "alien_cyan_lilla_t"
			and int(enemy.get("max_health_fp", 0)) == 40 * Simulation.FP_ONE
			and int(enemy.get("animation_max_phase", -1)) == 3
		)),
		"level-36 record zero should produce two four-phase cyan enemies at health 40"
	)
	_expect(
		green.size() == 1
		and String(green[0].get("sprite", "")) == "alien_green_lilla_t"
		and int(green[0].get("max_health_fp", 0)) == 59 * Simulation.FP_ONE
		and int(green[0].get("animation_max_phase", -1)) == 3,
		"level-36 record one should produce one four-phase green enemy at health 59"
	)

	# The retail fixed table is indexed by supplemental record, independently of
	# the record's resource selector. Give the two records distinct metadata so a
	# resource-indexed implementation cannot pass just because the retail values
	# happen to match on level 36.
	var level := (simulation._levels_by_id[36] as Dictionary).duplicate(true)
	var fixed_records := level.authored_lvd.fixed_table_records_raw_words as Array
	fixed_records[0] = [2, 7, 0, 0]
	fixed_records[1] = [5, 9, 0, 0]
	simulation._enemies.clear()
	simulation._supplemental_spawned = false
	simulation._spawn_authored_supplemental(level)
	var respawned: Array = simulation._enemies
	var record_zero: Array = respawned.filter(
		func(enemy: Dictionary) -> bool:
			return int(enemy.get("resource_slot_id", -1)) == 2
	)
	var record_one: Array = respawned.filter(
		func(enemy: Dictionary) -> bool:
			return int(enemy.get("resource_slot_id", -1)) == 1
	)
	_expect(
		record_zero.size() == 2
		and record_zero.all(func(enemy: Dictionary) -> bool: return (
			int(enemy.get("animation_max_phase", -1)) == 1
			and int(enemy.get("animation_metadata", -1)) == 7
		))
		and record_one.size() == 1
		and int(record_one[0].get("animation_max_phase", -1)) == 4
		and int(record_one[0].get("animation_metadata", -1)) == 9,
		"level-36 supplemental animation metadata should use its same-index fixed record"
	)


func _test_mode_two_and_escape_opcodes() -> void:
	for level_id in [37, 45]:
		var simulation = _new_level(level_id, 49, "simple", 4960 + level_id)
		if simulation == null:
			continue
		var probe := _enemy_with_opcode(simulation._enemies, 6)
		_expect(not probe.is_empty(), "level %d should expose an opcode-6 path" % level_id)
		if probe.is_empty():
			continue
		var enemy := probe.enemy as Dictionary
		enemy.path_index = int(probe.point_index) - 1
		simulation._advance_authored_path(enemy)
		_expect(
			int(enemy.get("behavior_state_id", 0)) == 10
			and not bool(enemy.get("dead", false)),
			"level-%d mode-two opcode 6 should enter state ten without escaping"
			% level_id
		)

	var ordinary = _new_level(42, 49, "simple", 4942)
	if ordinary == null:
		return
	var ordinary_probe := _enemy_with_opcode(ordinary._enemies, 6)
	_expect(not ordinary_probe.is_empty(), "level 42 should expose an opcode-6 path")
	if ordinary_probe.is_empty():
		return
	var ordinary_enemy := ordinary_probe.enemy as Dictionary
	var escaped_before: int = ordinary._level_escaped_entities
	ordinary_enemy.path_index = int(ordinary_probe.point_index) - 1
	ordinary._advance_authored_path(ordinary_enemy)
	_expect(
		bool(ordinary_enemy.get("dead", false))
		and ordinary._level_escaped_entities == escaped_before + 1,
		"level-42 ordinary opcode 6 should use the authored escape counter"
	)

	var bonus = _new_level(49, 49, "simple", 4949)
	if bonus == null:
		return
	var bonus_probe := _enemy_with_opcode(bonus._enemies, 6)
	_expect(not bonus_probe.is_empty(), "level 49 should expose an opcode-6 path")
	if bonus_probe.is_empty():
		return
	var bonus_enemy := bonus_probe.enemy as Dictionary
	var bonus_group_id := int(bonus_enemy.get("group_id", -1))
	bonus_enemy.path_index = int(bonus_probe.point_index) - 1
	bonus._advance_authored_path(bonus_enemy)
	_expect(
		bool(bonus_enemy.get("dead", false))
		and int(bonus._group_totals.get(bonus_group_id, -1)) == 0,
		"level-49 mode-three opcode 6 should clear its retail group-total slot before escape"
	)


func _test_recurring_shop_routes() -> void:
	for level_id in [40, 44, 48]:
		var simulation = _new_level(level_id, 49, "simple", 4980 + level_id, 100)
		if simulation == null:
			continue
		var supplemental: Array = simulation._enemies.filter(
			func(enemy: Dictionary) -> bool:
				return String(enemy.get("authored_state", "")) == "supplemental_large"
		)
		_expect(
			supplemental.size() == 4
			and supplemental.all(func(enemy: Dictionary) -> bool: return (
				int(enemy.get("animation_max_phase", -1)) == 3
			)),
			"level %d should retain its four four-phase supplemental enemies" % level_id
		)
		_resolve_all_enemies(simulation)
		simulation._level_resolution_tick = simulation._tick
		_expect(
			_step_until_phase(simulation, Simulation.PHASE_WARP, 10),
			"level %d should enter Warp before its recurring shop" % level_id
		)
		if String(simulation.get_snapshot().phase) != Simulation.PHASE_WARP:
			continue
		simulation._finalize_warp()
		var shop: Dictionary = simulation.get_snapshot()
		_expect(
			String(shop.get("phase", "")) == Simulation.PHASE_SHOP
			and int((shop.get("level_resolution", {}) as Dictionary).get(
				"pending_level_id",
				0
			)) == level_id + 1,
			"level %d should shop with level %d pending" % [level_id, level_id + 1]
		)
		if String(shop.get("phase", "")) != Simulation.PHASE_SHOP:
			continue
		_leave_shop(simulation)
		_expect(
			String(simulation.get_snapshot().phase) == Simulation.PHASE_GET_READY,
			"leaving the level-%d shop should enter Get Ready" % level_id
		)


func _test_mode_three_levels() -> void:
	_test_mode_three_level(41, 500, 49, 42)
	_test_mode_three_level(49, 750, 49, 0)


func _test_mode_three_level(
	level_id: int,
	kill_score: int,
	end_level: int,
	expected_next_level: int
) -> void:
	var simulation = _new_level(level_id, end_level, "simple", 49000 + level_id, 100)
	if simulation == null:
		return
	var initial: Dictionary = simulation.get_snapshot()
	_expect(
		bool((initial.get("mode_three_bonus", {}) as Dictionary).get("active", false))
		and int((initial.mode_three_bonus.players[0] as Dictionary).get(
			"total_targets",
			0
		)) == 40,
		"level %d should activate mode three with forty targets" % level_id
	)
	var targets: Array = simulation._enemies.filter(
		func(enemy: Dictionary) -> bool:
			return int(enemy.get("group_id", -1)) >= 0
	)
	_expect(
		targets.size() == 40
		and targets.all(func(enemy: Dictionary) -> bool: return (
			int(enemy.get("resource_slot_id", 0)) == 1
			and int(enemy.get("score", -1)) == kill_score
		)),
		"level %d should bind all forty targets to slot one at %d points"
		% [level_id, kill_score]
	)
	if targets.is_empty():
		return
	var firing_candidate := targets[0] as Dictionary
	firing_candidate.behavior_state_id = 1
	firing_candidate.authored_state = "hold"
	firing_candidate.y_fp = 100 * Simulation.FP_ONE
	firing_candidate.behavior_timer_a = 1
	var rng_before_fire: Dictionary = simulation._rng.snapshot()
	_expect(
		not simulation._authored_enemy_should_fire(firing_candidate)
		and simulation._rng.snapshot() == rng_before_fire,
		"level %d mode three should suppress projectiles without consuming RNG"
		% level_id
	)
	var progression := simulation._progression_for_seat(0) as Dictionary
	var score_before := int(progression.score)
	simulation._kill_enemy(firing_candidate, 0)
	_expect(
		int(progression.score) - score_before == kill_score,
		"level %d should award its resource-authoritative %d-point kill"
		% [level_id, kill_score]
	)
	_resolve_all_enemies(simulation)
	_expect(
		int(simulation.get_snapshot().mode_three_bonus.players[0].actual_hits) == 40,
		"all forty level-%d deaths should retain projectile ownership" % level_id
	)
	simulation._level_resolution_tick = simulation._tick
	_expect(
		_step_until_phase(simulation, Simulation.PHASE_WARP, 700),
		"level-%d results should transition into ordinary Warp" % level_id
	)
	if String(simulation.get_snapshot().phase) != Simulation.PHASE_WARP:
		return
	simulation._finalize_warp()
	var shop: Dictionary = simulation.get_snapshot()
	_expect(
		String(shop.get("phase", "")) == Simulation.PHASE_SHOP
		and int((shop.get("level_resolution", {}) as Dictionary).get(
			"pending_level_id",
			-1
		)) == expected_next_level,
		"level %d should shop with pending level %d"
		% [level_id, expected_next_level]
	)
	if String(shop.get("phase", "")) != Simulation.PHASE_SHOP:
		return
	_leave_shop(simulation)
	if expected_next_level == 0:
		var completed: Dictionary = simulation.get_snapshot()
		_expect(
			String(completed.get("phase", "")) == Simulation.PHASE_COMPLETE
			and int((completed.get("result", {}) as Dictionary).get(
				"level_reached",
				0
			)) == level_id,
			"leaving the terminal level-%d shop should complete the campaign"
			% level_id
		)
	else:
		var routed: Dictionary = simulation.get_snapshot()
		_expect(
			String(routed.get("phase", "")) == Simulation.PHASE_GET_READY
			and int((routed.get("level_resolution", {}) as Dictionary).get(
				"pending_level_id",
				0
			)) == expected_next_level,
			"leaving the level-%d shop should route to level %d"
			% [level_id, expected_next_level]
		)


func _test_level_forty_nine_organic_campaign_driver() -> void:
	var simulation := Simulation.new()
	_expect(simulation.configure({
		"mode": "solo",
		"difficulty": "normal",
		"collision_mode": "simple",
		"seed": 49 * 10001,
		"start_level": 49,
		"end_level": 49,
		"starting_weapon": 8,
		"starting_lives": 999,
		"starting_money": 100,
		"record_replay": false,
	}), "the organic level-49 campaign-driver regression should configure")
	if not simulation._configured:
		return
	var maximum_actual_hits := 0
	var completion_step := 0
	var watchdog_resolved := false
	for step_index in range(3000):
		var snapshot: Dictionary = simulation.get_snapshot()
		var mode_three := snapshot.get("mode_three_bonus", {}) as Dictionary
		var result_players := mode_three.get("players", []) as Array
		if not result_players.is_empty():
			maximum_actual_hits = maxi(
				maximum_actual_hits,
				int((result_players[0] as Dictionary).get("actual_hits", 0))
			)
		var phase := String(snapshot.get("phase", ""))
		if phase == Simulation.PHASE_COMPLETE:
			completion_step = step_index
			break
		if phase == Simulation.PHASE_LEVEL:
			simulation.set_input(0, CampaignTest.campaign_combat_input(snapshot))
		elif phase == Simulation.PHASE_SHOP:
			var guard_until := int((snapshot.get("shop", {}) as Dictionary).get(
				"input_guard_until_tick",
				0
			))
			simulation.set_input(
				0,
				Simulation.ACTION_READY if int(snapshot.get("tick", 0)) > guard_until else 0
			)
		else:
			simulation.set_input(0, 0)
		var stepped := simulation.step()
		for event_value in stepped.get("events", []):
			var event := event_value as Dictionary
			if (
				String(event.get("kind", "")) == "level_resolved"
				and String(event.get("reason", "")) == "watchdog"
			):
				watchdog_resolved = true
	var completed: Dictionary = simulation.get_snapshot()
	var completed_resolution := completed.get("level_resolution", {}) as Dictionary
	_expect(
		String(completed.get("phase", "")) == Simulation.PHASE_COMPLETE
		and int((completed.get("result", {}) as Dictionary).get("level_reached", 0)) == 49
		and maximum_actual_hits == 19
		and int(completed_resolution.get("total", -1)) == 40
		and int(completed_resolution.get("killed", -1)) == 19
		and int(completed_resolution.get("escaped", -1)) == 21
		and not watchdog_resolved
		and completion_step > 0
		and completion_step < 3000,
		(
			"the organic driver should complete level 49 through the retail timed paths and terminal shop "
			+ "(phase=%s level=%d hits=%d step=%d resolved=%d escaped=%d)"
		) % [
			String(completed.get("phase", "")),
			int((completed.get("result", {}) as Dictionary).get("level_reached", 0)),
			maximum_actual_hits,
			completion_step,
			int(completed_resolution.get("killed", -1)),
			int(completed_resolution.get("escaped", -1)),
		]
	)


func _test_default_and_retained_campaign_boundaries() -> void:
	var default_simulation := Simulation.new()
	_expect(default_simulation.configure({
		"mode": "solo",
		"difficulty": "normal",
		"collision_mode": "simple",
		"seed": 490049,
		"start_level": 49,
		"record_replay": false,
	}), "the default level-49 simulation should configure")
	if default_simulation._configured:
		_expect(
			int(default_simulation.get_snapshot().end_level_id) == 3999,
			"omitting end_level should default to the endless retail clamp boundary"
		)
	for boundary in [10, 20, 25, 30, 35]:
		var simulation := Simulation.new()
		_expect(simulation.configure({
			"mode": "solo",
			"difficulty": "normal",
			"collision_mode": "simple",
			"seed": 490000 + boundary,
			"start_level": boundary,
			"end_level": boundary,
			"record_replay": false,
		}), "retained level-%d campaign boundary should remain accepted" % boundary)
		if simulation._configured:
			_expect(
				int(simulation.get_snapshot().end_level_id) == boundary,
				"retained level-%d campaign boundary should remain exact" % boundary
			)


func _enemy_with_opcode(enemies: Array, opcode: int) -> Dictionary:
	for enemy_value in enemies:
		var enemy := enemy_value as Dictionary
		var path_points: Array = enemy.get("path_points", [])
		for point_index in range(path_points.size()):
			if int((path_points[point_index] as Dictionary).get("opcode", -1)) == opcode:
				return {"enemy": enemy, "point_index": point_index}
	return {}


func _resolve_all_enemies(simulation) -> void:
	for enemy_value in simulation._enemies.duplicate():
		var enemy := enemy_value as Dictionary
		if not bool(enemy.get("dead", false)):
			simulation._kill_enemy(enemy, 0)


func _step_until_phase(simulation, expected_phase: String, maximum_steps: int) -> bool:
	for _step_index in range(maximum_steps):
		if String(simulation.get_snapshot().phase) == expected_phase:
			return true
		simulation.set_input(0, 0)
		simulation.step()
	return String(simulation.get_snapshot().phase) == expected_phase


func _leave_shop(simulation) -> void:
	var shop: Dictionary = simulation.get_snapshot()
	var guard_tick := int((shop.get("shop", {}) as Dictionary).get(
		"input_guard_until_tick",
		0
	))
	while int(simulation.get_snapshot().tick) <= guard_tick:
		simulation.set_input(0, 0)
		simulation.step()
	_expect(simulation.set_shop_ready(0, true), "the shop should accept readiness")


func _new_level(
	level_id: int,
	end_level: int,
	collision_mode: String,
	seed_value: int,
	starting_money: int = 100
):
	var simulation := Simulation.new()
	_expect(simulation.configure({
		"mode": "solo",
		"difficulty": "normal",
		"collision_mode": collision_mode,
		"seed": seed_value,
		"start_level": level_id,
		"end_level": end_level,
		"starting_weapon": 8,
		"starting_lives": 99,
		"starting_money": starting_money,
		"record_replay": false,
	}), "level-%d simulation should configure: %s" % [level_id, simulation.get_last_error()])
	if not simulation._configured:
		return null
	simulation.step()
	return simulation


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

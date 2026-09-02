extends SceneTree

const Simulation := preload("res://src/sim/game_simulation.gd")

const LEVEL_RESOURCE_COUNTS := {
	51: {1: 76},
	52: {1: 120},
	53: {1: 24, 2: 6},
	54: {1: 36},
	55: {1: 20, 2: 20, 3: 20},
	56: {1: 96, 2: 15, 3: 15},
	57: {3: 110},
	58: {1: 40, 2: 40},
	59: {1: 40},
	60: {1: 30, 2: 16},
	61: {1: 22},
	62: {1: 25},
}
const LEVEL_RESOURCE_SHEETS := {
	51: {1: "alien_gultop"},
	52: {1: "alien_gultop"},
	53: {1: "alien_gultop", 2: "alien_lillatop"},
	54: {1: "alien_gultop"},
	55: {1: "alien_bluekreps", 2: "alien_lbluekreps", 3: "alien_brownkreps"},
	56: {1: "alien_bluekreps", 2: "alien_lbluekreps", 3: "alien_brownkreps"},
	57: {3: "alien_brownkreps"},
	58: {1: "alien_brownkreps2", 2: "alien_gulkreps"},
	59: {1: "alien_rvinggk"},
	60: {1: "alien_rvinggk", 2: "alien_gvingbk"},
	61: {1: "alien_rvinggk"},
	62: {1: "alien_gvingbk"},
}
const LEVEL_RESOURCE_SCORES := {
	51: {1: 1000},
	52: {1: 1000},
	53: {1: 1000, 2: 1200},
	54: {1: 500},
	55: {1: 750, 2: 800, 3: 1000},
	56: {1: 750, 2: 800, 3: 1000},
	57: {3: 1000},
	58: {1: 500, 2: 500},
	59: {1: 750},
	60: {1: 750, 2: 750},
	61: {1: 750},
	62: {1: 500},
}
const NEW_HMA_SHEETS := [
	"alien_gultop",
	"alien_lillatop",
	"alien_bluekreps",
	"alien_lbluekreps",
	"alien_brownkreps",
	"alien_brownkreps2",
	"alien_gulkreps",
	"alien_rvinggk",
	"alien_gvingbk",
]

var _failures: Array[String] = []


func _initialize() -> void:
	_test_authored_resource_matrix()
	_test_new_hma_resources()
	_test_supplemental_records()
	_test_mode_two_levels()
	_test_recurring_shop_routes()
	_test_level_fifty_eight_mode_three_contract()
	_test_campaign_boundaries()
	if _failures.is_empty():
		print("LEVELS 51-62 TESTS PASSED")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _test_authored_resource_matrix() -> void:
	for level_id_value in LEVEL_RESOURCE_COUNTS:
		var level_id := int(level_id_value)
		var simulation = _new_level(level_id, 62, "simple", 6200 + level_id)
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
			_expect(
				matches.all(func(enemy: Dictionary) -> bool: return (
					String(enemy.get("sprite", ""))
					== String((LEVEL_RESOURCE_SHEETS[level_id] as Dictionary)[slot_id])
					and int(enemy.get("score", -1))
					== int((LEVEL_RESOURCE_SCORES[level_id] as Dictionary)[slot_id])
				)),
				"level %d slot %d should retain its exact sheet and kill score"
				% [level_id, slot_id]
			)


func _test_new_hma_resources() -> void:
	var simulation = _new_level(58, 62, "pixel", 6258)
	if simulation == null:
		return
	for sheet_id in NEW_HMA_SHEETS:
		_expect(
			simulation._hit_masks.has(sheet_id),
			"pixel mode should load the authoritative %s HMA" % sheet_id
		)


func _test_supplemental_records() -> void:
	var level_53 = _new_level(53, 62, "simple", 6253)
	if level_53 != null:
		var supplemental_53 := _supplemental_enemies(level_53)
		var health_59: Array = supplemental_53.filter(
			func(enemy: Dictionary) -> bool:
				return int(enemy.get("max_health_fp", 0)) == 59 * Simulation.FP_ONE
		)
		var health_79: Array = supplemental_53.filter(
			func(enemy: Dictionary) -> bool:
				return int(enemy.get("max_health_fp", 0)) == 79 * Simulation.FP_ONE
		)
		_expect(
			supplemental_53.size() == 4
			and health_59.size() == 2
			and health_79.size() == 2
			and supplemental_53.all(func(enemy: Dictionary) -> bool: return (
				int(enemy.get("resource_slot_id", 0)) == 1
				and String(enemy.get("sprite", "")) == "alien_gultop"
				and int(enemy.get("animation_max_phase", -1)) == 3
			)),
			"level 53 should preserve both two-enemy, four-phase supplemental records"
		)

	var level_57 = _new_level(57, 62, "simple", 6257)
	if level_57 != null:
		var supplemental_57 := _supplemental_enemies(level_57)
		_expect(
			supplemental_57.size() == 4
			and supplemental_57.all(func(enemy: Dictionary) -> bool: return (
				int(enemy.get("resource_slot_id", 0)) == 3
				and String(enemy.get("sprite", "")) == "alien_brownkreps"
				and int(enemy.get("max_health_fp", 0)) == 98 * Simulation.FP_ONE
				and int(enemy.get("animation_max_phase", -1)) == 3
				and int(enemy.get("animation_metadata", -1)) == 1
			)),
			"level 57 should bind its four supplemental enemies to resource selector three"
		)

	var level_61 = _new_level(61, 62, "simple", 6261)
	if level_61 != null:
		var supplemental_61 := _supplemental_enemies(level_61)
		_expect(
			supplemental_61.size() == 4
			and supplemental_61.all(func(enemy: Dictionary) -> bool: return (
				int(enemy.get("resource_slot_id", 0)) == 1
				and String(enemy.get("sprite", "")) == "alien_rvinggk"
				and int(enemy.get("max_health_fp", 0)) == 88 * Simulation.FP_ONE
				and int(enemy.get("animation_max_phase", -1)) == 3
				and int(enemy.get("animation_metadata", -1)) == 1
			)),
			"level 61 should preserve its four-enemy supplemental record"
		)


func _test_mode_two_levels() -> void:
	for level_id in [54, 62]:
		var simulation = _new_level(level_id, 62, "simple", 6270 + level_id)
		if simulation == null:
			continue
		var level := simulation._levels_by_id[level_id] as Dictionary
		_expect(
			int((level.get("authored_lvd", {}) as Dictionary).get(
				"level_mode_id",
				0
			)) == 2,
			"level %d should retain retail mode two" % level_id
		)
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
	var level_54 = _new_level(54, 62, "simple", 62540)
	if level_54 != null:
		var resources: Array = level_54._levels_by_id[54].enemy_resources
		_expect(
			resources.size() == 2
			and String((resources[1] as Dictionary).get("enemy_sheet_id", ""))
			== "alien_rakett_gronn"
			and int((resources[1] as Dictionary).get("kill_score", -1)) == 400,
			"level 54 should reuse the existing green-rocket resource in slot two"
		)


func _test_recurring_shop_routes() -> void:
	for level_id in [52, 56, 60]:
		var simulation = _new_level(level_id, 62, "simple", 6280 + level_id, 100)
		if simulation == null:
			continue
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


func _test_level_fifty_eight_mode_three_contract() -> void:
	var simulation = _new_level(58, 62, "simple", 62580, 100)
	if simulation == null:
		return
	var initial: Dictionary = simulation.get_snapshot()
	_expect(
		bool((initial.get("mode_three_bonus", {}) as Dictionary).get("active", false))
		and int((initial.mode_three_bonus.players[0] as Dictionary).get(
			"total_targets",
			0
		)) == 80,
		"level 58 should activate generic mode three with eighty targets"
	)
	var targets: Array = simulation._enemies.filter(
		func(enemy: Dictionary) -> bool:
			return int(enemy.get("group_id", -1)) >= 0
	)
	var slot_one: Array = targets.filter(
		func(enemy: Dictionary) -> bool:
			return int(enemy.get("resource_slot_id", 0)) == 1
	)
	var slot_two: Array = targets.filter(
		func(enemy: Dictionary) -> bool:
			return int(enemy.get("resource_slot_id", 0)) == 2
	)
	_expect(
		targets.size() == 80
		and slot_one.size() == 40
		and slot_two.size() == 40
		and targets.all(func(enemy: Dictionary) -> bool: return (
			int(enemy.get("score", -1)) == 500
		)),
		"level 58 should bind forty targets per resource at 500 points each"
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
		"level 58 mode three should suppress projectiles without consuming RNG"
	)
	var progression := simulation._progression_for_seat(0) as Dictionary
	var score_before := int(progression.score)
	simulation._kill_enemy(firing_candidate, 0)
	_expect(
		int(progression.score) - score_before == 500,
		"level 58 should award its resource-authoritative 500-point kill"
	)
	_resolve_all_enemies(simulation)
	_expect(
		int(simulation.get_snapshot().mode_three_bonus.players[0].actual_hits) == 80,
		"all eighty level-58 deaths should retain projectile ownership"
	)
	simulation._level_resolution_tick = simulation._tick
	_expect(
		_step_until_phase(simulation, Simulation.PHASE_WARP, 700),
		"level-58 results should transition into ordinary Warp"
	)
	if String(simulation.get_snapshot().phase) != Simulation.PHASE_WARP:
		return
	simulation._finalize_warp()
	var shop: Dictionary = simulation.get_snapshot()
	_expect(
		String(shop.get("phase", "")) == Simulation.PHASE_SHOP
		and int((shop.get("level_resolution", {}) as Dictionary).get(
			"pending_level_id",
			0
		)) == 59,
		"level 58 should enter its post-Warp shop with level 59 pending"
	)
	if String(shop.get("phase", "")) == Simulation.PHASE_SHOP:
		_leave_shop(simulation)
		var routed: Dictionary = simulation.get_snapshot()
		_expect(
			String(routed.get("phase", "")) == Simulation.PHASE_GET_READY
			and int((routed.get("level_resolution", {}) as Dictionary).get(
				"pending_level_id",
				0
			)) == 59,
			"leaving the level-58 shop should route to level 59"
		)


func _test_campaign_boundaries() -> void:
	var default_simulation := Simulation.new()
	_expect(default_simulation.configure({
		"mode": "solo",
		"difficulty": "normal",
		"collision_mode": "simple",
		"seed": 620062,
		"start_level": 62,
		"record_replay": false,
	}), "the simulation starting at level 62 should configure with the default boundary")
	if default_simulation._configured:
		_expect(
			int(default_simulation.get_snapshot().end_level_id) == 3999,
			"omitting end_level should default to the endless retail clamp boundary"
		)

	var level_sixty_three := Simulation.new()
	_expect(level_sixty_three.configure({
		"mode": "solo",
		"difficulty": "normal",
		"collision_mode": "simple",
		"seed": 630063,
		"start_level": 62,
		"end_level": 63,
		"record_replay": false,
	}), "end_level 63 should be accepted by the full campaign")
	var beyond_boundary := Simulation.new()
	_expect(not beyond_boundary.configure({
		"mode": "solo",
		"difficulty": "normal",
		"collision_mode": "simple",
		"seed": 100101,
		"start_level": 100,
		"end_level": 4000,
		"record_replay": false,
	}), "end_level beyond the retail clamp should fail closed")
	var endless_boundary := Simulation.new()
	_expect(endless_boundary.configure({
		"mode": "solo",
		"difficulty": "normal",
		"collision_mode": "simple",
		"seed": 100101,
		"start_level": 100,
		"end_level": 101,
		"record_replay": false,
	}), "end_level 101 should be accepted as endless play")

	var terminal = _new_level(62, 62, "simple", 626262)
	if terminal == null:
		return
	_resolve_all_enemies(terminal)
	terminal._level_resolution_tick = terminal._tick
	_expect(
		_step_until_phase(terminal, Simulation.PHASE_COMPLETE, 10),
		"level 62 should complete after its authored resolution hold"
	)
	var completed: Dictionary = terminal.get_snapshot()
	_expect(
		String(completed.get("phase", "")) == Simulation.PHASE_COMPLETE
		and int((completed.get("result", {}) as Dictionary).get(
			"level_reached",
			0
		)) == 62
		and int((completed.get("level_resolution", {}) as Dictionary).get(
			"pending_level_id",
			-1
		)) == 0
		and not _event_requests_level(completed, 63),
		"level 62 should be terminal and must never request level 63"
	)


func _supplemental_enemies(simulation) -> Array:
	return simulation._enemies.filter(
		func(enemy: Dictionary) -> bool:
			return String(enemy.get("authored_state", "")) == "supplemental_large"
	)


func _enemy_with_opcode(enemies: Array, opcode: int) -> Dictionary:
	for enemy_value in enemies:
		var enemy := enemy_value as Dictionary
		var path_points: Array = enemy.get("path_points", [])
		for point_index in range(path_points.size()):
			if int((path_points[point_index] as Dictionary).get("opcode", -1)) == opcode:
				return {"enemy": enemy, "point_index": point_index}
	return {}


func _event_requests_level(snapshot: Dictionary, level_id: int) -> bool:
	for event_value in snapshot.get("events", []):
		var event := event_value as Dictionary
		if int(event.get("level_id", 0)) == level_id:
			return true
		if int(event.get("next_level_id", 0)) == level_id:
			return true
	return false


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

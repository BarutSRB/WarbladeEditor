extends SceneTree

const Simulation := preload("res://src/sim/game_simulation.gd")

const LEVEL_RESOURCE_COUNTS := {
	31: {1: 16, 2: 12},
	32: {1: 12, 2: 6},
	33: {1: 15, 2: 15},
	34: {1: 20, 2: 10},
	35: {1: 24, 2: 12},
}
const LEVEL_RESOURCE_SHEETS := {
	31: {1: "alien_baller", 2: "alien_baller2"},
	32: {1: "alien_baller", 2: "alien_baller2"},
	33: {1: "alien_baller", 2: "alien_baller2"},
	34: {1: "alien_green_lilla_t", 2: "alien_cyan_lilla_t"},
	35: {1: "alien_green_lilla_t", 2: "alien_cyan_lilla_t"},
}
const LEVEL_RESOURCE_SCORES := {
	31: {1: 500, 2: 600},
	32: {1: 500, 2: 600},
	33: {1: 500, 2: 600},
	34: {1: 450, 2: 550},
	35: {1: 450, 2: 550},
}

var _failures: Array[String] = []


func _initialize() -> void:
	_test_authored_resource_matrix()
	_test_new_hma_resources()
	_test_level_thirty_two_supplemental_and_shop_routes()
	_test_level_thirty_three_mode_three_contract()
	_test_level_thirty_five_terminal_route()
	_test_default_and_legacy_campaign_boundaries()
	if _failures.is_empty():
		print("LEVELS 31-35 TESTS PASSED")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _test_authored_resource_matrix() -> void:
	for level_id_value in LEVEL_RESOURCE_COUNTS:
		var level_id := int(level_id_value)
		var simulation = _new_level(level_id, 35, "simple", 3500 + level_id)
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
	var simulation = _new_level(34, 35, "pixel", 3434)
	if simulation == null:
		return
	for sheet_id in ["alien_green_lilla_t", "alien_cyan_lilla_t"]:
		_expect(
			simulation._hit_masks.has(sheet_id),
			"pixel mode should load the authoritative %s HMA" % sheet_id
		)


func _test_level_thirty_two_supplemental_and_shop_routes() -> void:
	var continuing = _new_level(32, 35, "simple", 3235, 100)
	if continuing == null:
		return
	var supplemental: Array = continuing._enemies.filter(
		func(enemy: Dictionary) -> bool:
			return String(enemy.get("authored_state", "")) == "supplemental_large"
	)
	_expect(supplemental.size() == 3, "level 32 should spawn three supplemental enemies")
	var supplemental_contract_matches := true
	for enemy_value in supplemental:
		var enemy := enemy_value as Dictionary
		supplemental_contract_matches = supplemental_contract_matches and (
			int(enemy.get("resource_slot_id", -1)) == 1
			and String(enemy.get("sprite", "")) == "alien_baller"
			and int(enemy.get("score", -1)) == 0
			and int(enemy.get("max_health_fp", 0)) == 40 * Simulation.FP_ONE
			and int(enemy.get("animation_max_phase", -1)) == 3
		)
	_expect(
		supplemental_contract_matches,
		"level-32 supplementals should retain the traced slot, health, and four phases"
	)
	_resolve_all_enemies(continuing)
	continuing._level_resolution_tick = continuing._tick
	_expect(
		_step_until_phase(continuing, Simulation.PHASE_WARP, 10),
		"level 32 should enter Warp before its recurring shop"
	)
	if String(continuing.get_snapshot().phase) == Simulation.PHASE_WARP:
		continuing._finalize_warp()
	var shop: Dictionary = continuing.get_snapshot()
	_expect(
		String(shop.get("phase", "")) == Simulation.PHASE_SHOP
		and int((shop.get("level_resolution", {}) as Dictionary).get(
			"pending_level_id",
			0
		)) == 33,
		"nonterminal level 32 should shop with level 33 pending"
	)

	var terminal = _new_level(32, 32, "simple", 3232, 100)
	if terminal == null:
		return
	_resolve_all_enemies(terminal)
	terminal._level_resolution_tick = terminal._tick
	_expect(
		_step_until_phase(terminal, Simulation.PHASE_WARP, 10),
		"terminal level 32 should still enter Warp for its authored shop"
	)
	if String(terminal.get_snapshot().phase) != Simulation.PHASE_WARP:
		return
	terminal._finalize_warp()
	var terminal_shop: Dictionary = terminal.get_snapshot()
	_expect(
		String(terminal_shop.get("phase", "")) == Simulation.PHASE_SHOP
		and int((terminal_shop.get("level_resolution", {}) as Dictionary).get(
			"pending_level_id",
			-1
		)) == 0,
		"terminal level 32 should shop with no next level pending"
	)
	var guard_tick := int((terminal_shop.get("shop", {}) as Dictionary).get(
		"input_guard_until_tick",
		0
	))
	while int(terminal.get_snapshot().tick) <= guard_tick:
		terminal.set_input(0, 0)
		terminal.step()
	_expect(terminal.set_shop_ready(0, true), "terminal level-32 shop should accept readiness")
	var completed: Dictionary = terminal.get_snapshot()
	_expect(
		String(completed.get("phase", "")) == Simulation.PHASE_COMPLETE
		and int((completed.get("result", {}) as Dictionary).get("level_reached", 0)) == 32,
		"leaving the terminal level-32 shop should complete at level 32"
	)


func _test_level_thirty_three_mode_three_contract() -> void:
	var simulation = _new_level(33, 35, "simple", 3335)
	if simulation == null:
		return
	var initial: Dictionary = simulation.get_snapshot()
	_expect(
		bool((initial.get("mode_three_bonus", {}) as Dictionary).get("active", false))
		and int((initial.mode_three_bonus.players[0] as Dictionary).get(
			"total_targets",
			0
		)) == 30,
		"level 33 should activate mode three with thirty targets"
	)
	var slot_one: Array = simulation._enemies.filter(
		func(enemy: Dictionary) -> bool:
			return int(enemy.get("resource_slot_id", 0)) == 1
	)
	var slot_two: Array = simulation._enemies.filter(
		func(enemy: Dictionary) -> bool:
			return int(enemy.get("resource_slot_id", 0)) == 2
	)
	_expect(
		slot_one.size() == 15 and slot_two.size() == 15,
		"level 33 should preserve its retail 15/15 resource split"
	)
	_expect(
		slot_one.all(func(enemy: Dictionary) -> bool: return int(enemy.score) == 500)
		and slot_two.all(func(enemy: Dictionary) -> bool: return int(enemy.score) == 600),
		"level 33 should score slot 1 at 500 and slot 2 at 600"
	)
	if slot_one.is_empty() or slot_two.is_empty():
		return
	var firing_candidate := slot_one[0] as Dictionary
	firing_candidate.behavior_state_id = 1
	firing_candidate.authored_state = "hold"
	firing_candidate.y_fp = 100 * Simulation.FP_ONE
	firing_candidate.behavior_timer_a = 1
	var rng_before_fire: Dictionary = simulation._rng.snapshot()
	_expect(
		not simulation._authored_enemy_should_fire(firing_candidate)
		and simulation._rng.snapshot() == rng_before_fire,
		"level 33 mode three should suppress ordinary projectiles without consuming RNG"
	)
	var progression := simulation._progression_for_seat(0) as Dictionary
	var before_slot_one := int(progression.score)
	simulation._kill_enemy(slot_one[0] as Dictionary, 0)
	var after_slot_one := int(progression.score)
	simulation._kill_enemy(slot_two[0] as Dictionary, 0)
	var after_slot_two := int(progression.score)
	_expect(
		after_slot_one - before_slot_one == 500
		and after_slot_two - after_slot_one == 600,
		"level 33 kill awards should use each enemy resource score, not the 500-point alias"
	)
	for enemy_value in simulation._enemies.duplicate():
		var enemy := enemy_value as Dictionary
		if not bool(enemy.get("dead", false)):
			simulation._kill_enemy(enemy, 0)
	_expect(
		int(simulation.get_snapshot().mode_three_bonus.players[0].actual_hits) == 30,
		"all thirty level-33 target deaths should retain projectile ownership"
	)
	simulation._level_resolution_tick = simulation._tick
	_expect(
		_step_until_phase(simulation, Simulation.PHASE_WARP, 700),
		"level-33 results should transition into ordinary Warp"
	)
	if String(simulation.get_snapshot().phase) != Simulation.PHASE_WARP:
		return
	simulation._finalize_warp()
	var mode_three_shop: Dictionary = simulation.get_snapshot()
	_expect(
		String(mode_three_shop.get("phase", "")) == Simulation.PHASE_SHOP
		and int((mode_three_shop.get("level_resolution", {}) as Dictionary).get(
			"pending_level_id",
			0
		)) == 34,
		"level 33 should retain the recurring mode-three shop with level 34 pending"
	)
	if String(mode_three_shop.get("phase", "")) != Simulation.PHASE_SHOP:
		return
	var guard_tick := int((mode_three_shop.get("shop", {}) as Dictionary).get(
		"input_guard_until_tick",
		0
	))
	while int(simulation.get_snapshot().tick) <= guard_tick:
		simulation.set_input(0, 0)
		simulation.step()
	_expect(simulation.set_shop_ready(0, true), "the level-33 shop should accept readiness")
	var routed: Dictionary = simulation.get_snapshot()
	_expect(
		String(routed.get("phase", "")) == Simulation.PHASE_GET_READY
		and int((routed.get("level_resolution", {}) as Dictionary).get(
			"pending_level_id",
			0
		)) == 34,
		"leaving the level-33 shop should transition to level 34"
	)


func _test_level_thirty_five_terminal_route() -> void:
	var simulation = _new_level(35, 35, "simple", 3535)
	if simulation == null:
		return
	_resolve_all_enemies(simulation)
	simulation._level_resolution_tick = simulation._tick
	_expect(
		_step_until_phase(simulation, Simulation.PHASE_COMPLETE, 10),
		"level 35 should complete after its authored resolution hold"
	)
	var terminal: Dictionary = simulation.get_snapshot()
	_expect(
		int(terminal.get("level_id", 0)) == 35
		and int((terminal.get("result", {}) as Dictionary).get("level_reached", 0)) == 35
		and int((terminal.get("level_resolution", {}) as Dictionary).get(
			"pending_level_id",
			-1
		)) == 0,
		"level 35 should be terminal and must never request level 36"
	)


func _test_default_and_legacy_campaign_boundaries() -> void:
	var default_simulation := Simulation.new()
	_expect(default_simulation.configure({
		"mode": "solo",
		"difficulty": "normal",
		"collision_mode": "simple",
		"seed": 350035,
		"start_level": 35,
		"record_replay": false,
	}), "the default level-35 start should configure")
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
			"seed": 350000 + boundary,
			"start_level": boundary,
			"end_level": boundary,
			"record_replay": false,
		}), "legacy level-%d campaign boundary should remain accepted" % boundary)
		if simulation._configured:
			_expect(
				int(simulation.get_snapshot().end_level_id) == boundary,
				"legacy level-%d campaign boundary should remain exact" % boundary
			)


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

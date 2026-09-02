extends SceneTree

const Simulation := preload("res://src/sim/game_simulation.gd")

const LEVEL_RESOURCE_COUNTS := {
	26: {1: 25},
	27: {1: 14, 2: 8},
	28: {1: 16, 2: 8},
	29: {1: 36},
	30: {1: 24, 2: 6},
}
const LEVEL_RESOURCE_SHEETS := {
	26: {1: "alien_rakett"},
	27: {1: "alien_rakett", 2: "alien_rakett_gronn"},
	28: {1: "alien_rakett", 2: "alien_rakett_gronn"},
	29: {1: "alien_rakett"},
	30: {1: "alien_baller", 2: "alien_baller2"},
}
const LEVEL_RESOURCE_SCORES := {
	26: {1: 300},
	27: {1: 300, 2: 400},
	28: {1: 300, 2: 400},
	29: {1: 400},
	30: {1: 500, 2: 600},
}

var _failures: Array[String] = []


func _initialize() -> void:
	_test_authored_resource_matrix()
	_test_new_hma_resources_and_slot_two_scores()
	_test_level_twenty_eight_supplementals()
	_test_level_twenty_nine_mode_two()
	_test_level_twenty_eight_shop_and_accuracy_unlocks()
	_test_level_thirty_terminal_route()
	if _failures.is_empty():
		print("LEVELS 26-30 TESTS PASSED")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _test_authored_resource_matrix() -> void:
	for level_id_value in LEVEL_RESOURCE_COUNTS:
		var level_id := int(level_id_value)
		var simulation = _new_level(level_id, "simple", 2600 + level_id)
		if simulation == null:
			continue
		var ordinary: Array = simulation._enemies.filter(
			func(enemy: Dictionary) -> bool:
				return int(enemy.get("group_id", -1)) >= 0
		)
		var expected_counts: Dictionary = LEVEL_RESOURCE_COUNTS[level_id]
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


func _test_new_hma_resources_and_slot_two_scores() -> void:
	for level_id in [27, 30]:
		var simulation = _new_level(level_id, "pixel", 2700 + level_id)
		if simulation == null:
			continue
		for sheet_value in (LEVEL_RESOURCE_SHEETS[level_id] as Dictionary).values():
			_expect(
				simulation._hit_masks.has(String(sheet_value)),
				"pixel mode should dynamically load %s for level %d"
				% [String(sheet_value), level_id]
			)
		var slot_two: Dictionary = {}
		for enemy_value in simulation._enemies:
			var enemy := enemy_value as Dictionary
			if int(enemy.get("resource_slot_id", -1)) == 2:
				slot_two = enemy
				break
		_expect(not slot_two.is_empty(), "level %d should expose a slot-2 target" % level_id)
		if slot_two.is_empty():
			continue
		var before_score := int(simulation._progression_for_seat(0).score)
		_expect(
			_destroy_enemy_with_public_fire(simulation, slot_two),
			"a public projectile should destroy the level-%d slot-2 target" % level_id
		)
		_expect(
			int(simulation._progression_for_seat(0).score) - before_score
			== int((LEVEL_RESOURCE_SCORES[level_id] as Dictionary)[2]),
			"level %d slot 2 should award its own score without a slot-1 fallback"
			% level_id
		)


func _test_level_twenty_eight_supplementals() -> void:
	var simulation = _new_level(28, "simple", 2828)
	if simulation == null:
		return
	var supplemental: Array = simulation._enemies.filter(
		func(enemy: Dictionary) -> bool:
			return String(enemy.get("authored_state", "")) == "supplemental_large"
	)
	_expect(supplemental.size() == 2, "level 28 should spawn two supplemental enemies")
	if supplemental.is_empty():
		return
	var contract_matches := true
	for enemy_value in supplemental:
		var enemy := enemy_value as Dictionary
		contract_matches = contract_matches and (
			int(enemy.get("resource_slot_id", -1)) == 1
			and String(enemy.get("sprite", "")) == "alien_rakett"
			and int(enemy.get("score", -1)) == 0
			and int(enemy.get("width", 0)) == 64
			and int(enemy.get("height", 0)) == 64
			and int(enemy.get("animation_max_phase", -1)) == 3
			and int(enemy.get("animation_metadata", -1)) == 0
			and int(enemy.get("max_health_fp", 0)) == 30 * Simulation.FP_ONE
		)
	_expect(
		contract_matches,
		"level-28 supplementals should retain the traced slot, health, and four-phase contract"
	)
	var animated := supplemental[0] as Dictionary
	animated.behavior_timer_a = 0
	(simulation._players[0] as Dictionary).invulnerable_ticks = 10000
	var phases: Dictionary = {int(animated.get("authored_animation_frame", -1)): true}
	for _step_index in range(500):
		if phases.size() >= 4:
			break
		simulation.set_input(0, 0)
		simulation.step()
		phases[int(animated.get("authored_animation_frame", -1))] = true
	for phase in range(4):
		_expect(phases.has(phase), "level-28 supplemental animation should reach phase %d" % phase)


func _test_level_twenty_nine_mode_two() -> void:
	var simulation = _new_level(29, "simple", 2929)
	if simulation == null:
		return
	var groups: Dictionary = {}
	for enemy_value in simulation._enemies:
		var enemy := enemy_value as Dictionary
		if int(enemy.get("group_id", -1)) < 0:
			continue
		var group_id := int(enemy.group_id)
		if not groups.has(group_id):
			groups[group_id] = []
		(groups[group_id] as Array).append(enemy)
	_expect(
		groups.size() == 6
		and groups.values().all(func(group: Array) -> bool: return group.size() == 6),
		"level 29 should preserve six simultaneous six-enemy mode-two groups"
	)
	var enemy := simulation._enemies[0] as Dictionary
	enemy.path_index = enemy.path_points.size() - 2
	simulation._advance_authored_path(enemy)
	_expect(
		String(enemy.get("authored_state", "")) == "state_ten"
		and int(enemy.get("behavior_state_id", 0)) == 10,
		"level-29 opcode 6 should enter the existing authoritative kamikaze state"
	)


func _test_level_twenty_eight_shop_and_accuracy_unlocks() -> void:
	var simulation = _new_level(28, "simple", 2888, [{
		"best_hit_percent_above_level_25": 90,
	}], 100000)
	if simulation == null:
		return
	(simulation._players[0] as Dictionary).invulnerable_ticks = 10000
	for enemy_value in simulation._enemies.duplicate():
		_expect(
			_destroy_enemy_fully_with_public_fire(simulation, enemy_value as Dictionary),
			"every level-28 target should resolve through a public projectile collision"
		)
	var warp_reached := _step_until(
		simulation,
		func(snapshot: Dictionary) -> bool:
			return String(snapshot.get("phase", "")) == Simulation.PHASE_WARP,
		250
	)
	_expect(warp_reached, "level 28 should enter Warp after all twenty-six targets resolve")
	if not warp_reached:
		return
	simulation._warp_malfunction_interval = 0
	for _warp_update in range(400):
		simulation.set_input(0, 0)
		simulation.step()
	var shop: Dictionary = simulation.get_snapshot()
	_expect(
		String(shop.get("phase", "")) == Simulation.PHASE_SHOP
		and int((shop.get("level_resolution", {}) as Dictionary).get(
			"pending_level_id",
			0
		)) == 29,
		"level-28 Warp should enter the shop with level 29 pending"
	)
	var visible_ids: Array[int] = []
	for item_value in (shop.get("shop", {}) as Dictionary).get("items", []):
		visible_ids.append(int((item_value as Dictionary).get("id", 0)))
	for item_id in [18, 19, 20]:
		_expect(
			visible_ids.has(item_id),
			"a 90-percent active shop owner should see late item %d" % item_id
		)


func _test_level_thirty_terminal_route() -> void:
	var simulation = _new_level(30, "simple", 3030)
	if simulation == null:
		return
	(simulation._players[0] as Dictionary).invulnerable_ticks = 10000
	for enemy_value in simulation._enemies.duplicate():
		_expect(
			_destroy_enemy_fully_with_public_fire(simulation, enemy_value as Dictionary),
			"every level-30 target should resolve through a public projectile collision"
		)
	var completed := _step_until(
		simulation,
		func(snapshot: Dictionary) -> bool:
			return String(snapshot.get("phase", "")) == Simulation.PHASE_COMPLETE,
		250
	)
	var terminal: Dictionary = simulation.get_snapshot()
	_expect(completed, "level 30 should complete after its authored resolution hold")
	_expect(
		int(terminal.get("level_id", 0)) == 30
		and int((terminal.get("result", {}) as Dictionary).get("level_reached", 0)) == 30
		and int((terminal.get("level_resolution", {}) as Dictionary).get(
			"pending_level_id",
			-1
		)) == 0,
		"level 30 should be terminal and must never request level 31"
	)


func _destroy_enemy_with_public_fire(simulation, target: Dictionary) -> bool:
	if bool(target.get("dead", false)):
		return false
	var old_projectile_ids: Dictionary = {}
	for projectile_value in simulation._projectiles:
		var projectile := projectile_value as Dictionary
		if String(projectile.get("owner_kind", "")) == "player":
			old_projectile_ids[int(projectile.get("id", 0))] = true
	if not simulation.set_input(0, Simulation.ACTION_FIRE):
		return false
	simulation.step()
	simulation.set_input(0, 0)
	var spawned: Array = []
	for projectile_value in simulation._projectiles:
		var projectile := projectile_value as Dictionary
		if (
			String(projectile.get("owner_kind", "")) == "player"
			and not bool(projectile.get("expired", false))
			and not old_projectile_ids.has(int(projectile.get("id", 0)))
		):
			spawned.append(projectile)
	if spawned.is_empty():
		return false
	var colliding_shot := spawned[0] as Dictionary
	for projectile_value in spawned.slice(1):
		(projectile_value as Dictionary).expired = true
	if String(target.get("authored_state", "")) == "delayed":
		target.authored_state = "hold"
		target.behavior_state_id = 1
		target.activation_delay_ticks = 0
		target.activation_delay_sixths = 0
	target.x_fp = 100 * Simulation.FP_ONE
	target.y_fp = 500 * Simulation.FP_ONE
	colliding_shot.x_fp = int(target.x_fp)
	colliding_shot.y_fp = int(target.y_fp)
	simulation._update_enemy_mask_rect(target)
	simulation.step()
	return bool(target.get("dead", false))


func _destroy_enemy_fully_with_public_fire(simulation, target: Dictionary) -> bool:
	for _hit_index in range(16):
		if bool(target.get("dead", false)):
			return true
		_destroy_enemy_with_public_fire(simulation, target)
	return bool(target.get("dead", false))


func _step_until(simulation, predicate: Callable, maximum_steps: int) -> bool:
	for _step_index in range(maximum_steps):
		var snapshot: Dictionary = simulation.get_snapshot()
		if predicate.call(snapshot):
			return true
		simulation.set_input(0, 0)
		simulation.step()
	return predicate.call(simulation.get_snapshot())


func _new_level(
	level_id: int,
	collision_mode: String,
	seed_value: int,
	seats: Array = [],
	starting_money: int = 100
):
	var simulation := Simulation.new()
	_expect(simulation.configure({
		"mode": "solo",
		"difficulty": "normal",
		"collision_mode": collision_mode,
		"seed": seed_value,
		"start_level": level_id,
		"end_level": 30,
		"starting_weapon": 8,
		"starting_lives": 99,
		"starting_money": starting_money,
		"record_replay": false,
		"seats": seats,
	}), "level-%d simulation should configure: %s" % [level_id, simulation.get_last_error()])
	if not simulation._configured:
		return null
	simulation.step()
	return simulation


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

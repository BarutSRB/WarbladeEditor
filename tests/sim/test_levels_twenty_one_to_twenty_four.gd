extends SceneTree

const Simulation := preload("res://src/sim/game_simulation.gd")
const Catalog := preload("res://src/sim/content_catalog.gd")

const LEVEL_RESOURCE_COUNTS := {
	21: {1: 24, 2: 8},
	22: {1: 20, 2: 10},
	23: {1: 16, 2: 10},
}
const RESOURCE_SHEETS := {
	1: "alien003",
	2: "alien003_3",
}
const RESOURCE_KILL_SCORES := {
	1: 200,
	2: 300,
}

var _failures: Array[String] = []


func _initialize() -> void:
	_test_mixed_resource_spawn_matrix()
	_test_missing_resource_binding_fails_closed()
	_test_slot_two_supplemental_counts_toward_completion()
	_test_dynamic_masks_and_slot_two_collision_score()
	_test_level_twenty_three_supplemental_animation()
	_test_level_twenty_four_perfect_warp_shop_route()
	_test_level_twenty_four_miss_resets_chain()
	if _failures.is_empty():
		print("LEVELS 21-24 TESTS PASSED")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _test_mixed_resource_spawn_matrix() -> void:
	for level_id_value in LEVEL_RESOURCE_COUNTS:
		var level_id := int(level_id_value)
		var simulation = _new_level(level_id, "simple", 2100 + level_id)
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
			var binding_matches := true
			for enemy_value in matches:
				var enemy := enemy_value as Dictionary
				binding_matches = binding_matches and (
					String(enemy.get("sprite", ""))
					== String(RESOURCE_SHEETS[slot_id])
					and int(enemy.get("score", -1))
					== int(RESOURCE_KILL_SCORES[slot_id])
				)
			_expect(
				binding_matches,
				"level %d slot %d should retain its exact sheet and kill score"
				% [level_id, slot_id]
			)


func _test_missing_resource_binding_fails_closed() -> void:
	var temporary_base := "user://warblade_levels_21_24_missing_resource"
	var absolute_base := ProjectSettings.globalize_path(temporary_base)
	var make_error := DirAccess.make_dir_recursive_absolute(absolute_base)
	_expect(
		make_error == OK or make_error == ERR_ALREADY_EXISTS,
		"the missing-resource catalog fixture directory should be creatable"
	)
	if make_error != OK and make_error != ERR_ALREADY_EXISTS:
		return
	var copied := true
	for file_name in Catalog.REQUIRED_FILES:
		var source_path := "res://content".path_join(file_name)
		var destination_path := temporary_base.path_join(file_name)
		if not FileAccess.file_exists(source_path):
			_expect(false, "catalog fixture source %s should exist" % file_name)
			copied = false
			continue
		var destination := FileAccess.open(destination_path, FileAccess.WRITE)
		if destination == null:
			_expect(false, "catalog fixture %s should be writable" % file_name)
			copied = false
			continue
		destination.store_buffer(FileAccess.get_file_as_bytes(source_path))
	if not copied:
		_cleanup_catalog_fixture(temporary_base, absolute_base)
		return

	var levels_path := temporary_base.path_join("levels.json")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(levels_path))
	_expect(parsed is Dictionary, "the copied levels catalog should parse")
	if not parsed is Dictionary:
		_cleanup_catalog_fixture(temporary_base, absolute_base)
		return
	var levels_document := parsed as Dictionary
	var levels: Array = levels_document.get("levels", [])
	var level_twenty_one := levels[20] as Dictionary
	var resources: Array = level_twenty_one.get("enemy_resources", [])
	level_twenty_one.enemy_resources = [resources[0]]
	var levels_file := FileAccess.open(levels_path, FileAccess.WRITE)
	if levels_file == null:
		_expect(false, "the copied levels catalog should be mutable")
		_cleanup_catalog_fixture(temporary_base, absolute_base)
		return
	# Preserve schema field order so this fixture reaches the resource-binding
	# rejection it is intended to exercise.
	levels_file.store_string(JSON.stringify(levels_document, "\t", false) + "\n")
	levels_file.flush()

	var rejected := Catalog.load_catalog(temporary_base)
	_expect(
		not bool(rejected.get("ok", false))
		and String(rejected.get("error", "")).contains(
			"authored enemy resource slot 2 has no level binding"
		),
		"a level-21 slot-2 enemy must fail closed when its binding is absent: %s"
		% String(rejected.get("error", "missing rejection"))
	)
	_cleanup_catalog_fixture(temporary_base, absolute_base)


func _test_slot_two_supplemental_counts_toward_completion() -> void:
	var temporary_base := "user://warblade_levels_21_24_slot_two_supplemental"
	var absolute_base := ProjectSettings.globalize_path(temporary_base)
	var make_error := DirAccess.make_dir_recursive_absolute(absolute_base)
	_expect(
		make_error == OK or make_error == ERR_ALREADY_EXISTS,
		"the slot-2 supplemental catalog fixture directory should be creatable"
	)
	if make_error != OK and make_error != ERR_ALREADY_EXISTS:
		return
	for file_name in Catalog.REQUIRED_FILES:
		var source_path := "res://content".path_join(file_name)
		var destination := FileAccess.open(
			temporary_base.path_join(file_name),
			FileAccess.WRITE
		)
		if destination == null:
			_expect(false, "the slot-2 supplemental fixture should copy %s" % file_name)
			_cleanup_catalog_fixture(temporary_base, absolute_base)
			return
		destination.store_buffer(FileAccess.get_file_as_bytes(source_path))

	var levels_path := temporary_base.path_join("levels.json")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(levels_path))
	_expect(parsed is Dictionary, "the slot-2 supplemental levels catalog should parse")
	if not parsed is Dictionary:
		_cleanup_catalog_fixture(temporary_base, absolute_base)
		return
	var levels_document := parsed as Dictionary
	var level_twenty_three := (levels_document.get("levels", []) as Array)[22] as Dictionary
	var records := (
		(level_twenty_three.get("authored_lvd", {}) as Dictionary).get(
			"supplemental_spawn_records_raw_words",
			[]
		) as Array
	)
	(records[0] as Array)[1] = 2
	var levels_file := FileAccess.open(levels_path, FileAccess.WRITE)
	if levels_file == null:
		_expect(false, "the slot-2 supplemental levels catalog should be writable")
		_cleanup_catalog_fixture(temporary_base, absolute_base)
		return
	# Preserve schema field order while changing only the supplemental slot.
	levels_file.store_string(JSON.stringify(levels_document, "\t", false) + "\n")
	levels_file.flush()

	var simulation := Simulation.new()
	var configured := simulation.configure({
		"mode": "solo",
		"difficulty": "normal",
		"collision_mode": "simple",
		"seed": 2324,
		"start_level": 23,
		"end_level": 23,
		"starting_lives": 99,
		"record_replay": false,
		"content_base_path": temporary_base,
	})
	_expect(
		configured,
		"a declared slot-2 supplemental binding should configure: %s"
		% simulation.get_last_error()
	)
	if configured:
		simulation.step()
		var supplemental: Array = simulation._enemies.filter(
			func(enemy: Dictionary) -> bool:
				return String(enemy.get("authored_state", "")) == "supplemental_large"
		)
		var authored: Array = simulation._enemies.filter(
			func(enemy: Dictionary) -> bool:
				return int(enemy.get("group_id", -1)) >= 0
		)
		var supplemental_slots_match := supplemental.size() == 2
		for enemy_value in supplemental:
			supplemental_slots_match = (
				supplemental_slots_match
				and int((enemy_value as Dictionary).get("resource_slot_id", -1)) == 2
			)
		_expect(
			supplemental_slots_match,
			"the accepted fixture should spawn both supplementals from slot 2"
		)
		_expect(
			int(simulation._level_total_entities) == simulation._enemies.size(),
			"every positive supplemental record should contribute to the completion total"
		)
		for enemy_value in authored:
			simulation._kill_enemy(enemy_value as Dictionary, 0)
		_expect(
			not simulation._level_resolved
			and int(simulation._level_killed_entities) == authored.size(),
			"slot-2 supplementals should keep the level unresolved after authored groups die"
		)
		for enemy_value in supplemental:
			simulation._kill_enemy(enemy_value as Dictionary, 0)
		_expect(
			bool(simulation._level_resolved)
			and int(simulation._level_killed_entities)
			== int(simulation._level_total_entities),
			"the level should resolve only after both slot-2 supplementals also die"
		)
	_cleanup_catalog_fixture(temporary_base, absolute_base)


func _test_dynamic_masks_and_slot_two_collision_score() -> void:
	var pixel_simulation = _new_level(21, "pixel", 2121)
	if pixel_simulation != null:
		_expect(
			pixel_simulation._hit_masks.has("alien003")
			and pixel_simulation._hit_masks.has("alien003_3"),
			"pixel mode should dynamically load both level-21 HMA resources"
		)

	var simulation = _new_level(21, "simple", 2122)
	if simulation == null:
		return
	var slot_two: Dictionary = {}
	for enemy_value in simulation._enemies:
		var enemy := enemy_value as Dictionary
		if int(enemy.get("resource_slot_id", -1)) == 2:
			slot_two = enemy
			break
	_expect(not slot_two.is_empty(), "level 21 should expose a slot-2 collision target")
	if slot_two.is_empty():
		return
	var before_score := int(simulation._progression_for_seat(0).score)
	var destroyed := _destroy_enemy_with_public_fire(simulation, slot_two)
	_expect(destroyed, "a public player shot should destroy the level-21 slot-2 target")
	_expect(
		int(simulation._progression_for_seat(0).score) - before_score == 300,
		"a colliding slot-2 projectile should award 300 without a slot-1 fallback"
	)


func _test_level_twenty_three_supplemental_animation() -> void:
	var simulation = _new_level(23, "simple", 2323)
	if simulation == null:
		return
	var supplemental: Array = simulation._enemies.filter(
		func(enemy: Dictionary) -> bool:
			return String(enemy.get("authored_state", "")) == "supplemental_large"
	)
	_expect(supplemental.size() == 2, "level 23 should spawn its two supplemental enemies")
	if supplemental.is_empty():
		return
	var supplemental_contract_matches := true
	for enemy_value in supplemental:
		var enemy := enemy_value as Dictionary
		supplemental_contract_matches = supplemental_contract_matches and (
			int(enemy.get("resource_slot_id", -1)) == 1
			and String(enemy.get("sprite", "")) == "alien003"
			and int(enemy.get("score", -1)) == 0
			and int(enemy.get("width", 0)) == 64
			and int(enemy.get("height", 0)) == 64
			and int(enemy.get("animation_max_phase", -1)) == 6
			and int(enemy.get("animation_metadata", -1)) == 1
			and int(enemy.get("max_health_fp", 0)) == 60 * Simulation.FP_ONE
		)
	_expect(
		supplemental_contract_matches,
		"level-23 supplementals should retain the traced slot, atlas, health, and seven-frame contract"
	)

	var animated := supplemental[0] as Dictionary
	animated.behavior_timer_a = 0
	(simulation._players[0] as Dictionary).invulnerable_ticks = 10000
	var seen_phases: Dictionary = {
		int(animated.get("authored_animation_frame", -1)): true,
	}
	var guard := 0
	while seen_phases.size() < 7 and guard < 500:
		simulation.set_input(0, 0)
		simulation.step()
		seen_phases[int(animated.get("authored_animation_frame", -1))] = true
		guard += 1
	for phase in range(7):
		_expect(
			seen_phases.has(phase),
			"level-23 supplemental animation should reach phase %d" % phase
		)


func _test_level_twenty_four_perfect_warp_shop_route() -> void:
	var simulation = _new_level(24, "simple", 2424, [{
		"mode_three_perfect_reward_index": 1,
	}])
	if simulation == null:
		return
	var initial: Dictionary = simulation.get_snapshot()
	_expect(bool(initial.mode_three_bonus.active), "level 24 should activate recurring mode three")
	_expect(
		int(initial.mode_three_bonus.players[0].total_targets) == 30
		and simulation._enemies.size() == 30,
		"level 24 should own exactly thirty authored targets"
	)
	var target_contract_matches := true
	for enemy_value in simulation._enemies:
		var enemy := enemy_value as Dictionary
		target_contract_matches = target_contract_matches and (
			int(enemy.get("resource_slot_id", -1)) == 1
			and String(enemy.get("sprite", "")) == "alien003"
			and int(enemy.get("score", -1)) == 200
		)
	_expect(
		target_contract_matches,
		"all level-24 targets should bind slot 1 at 200 points"
	)

	(simulation._players[0] as Dictionary).invulnerable_ticks = 10000
	for enemy_value in simulation._enemies.duplicate():
		_expect(
			_destroy_enemy_with_public_fire(simulation, enemy_value as Dictionary),
			"every level-24 perfect target should resolve through a public projectile collision"
		)
	_expect(
		int(simulation._progression_for_seat(0).score) == 30 * 200,
		"thirty level-24 target collisions should award 6,000 points before results"
	)
	_expect(
		int(simulation.get_snapshot().mode_three_bonus.players[0].actual_hits) == 30,
		"level-24 projectile ownership should record all thirty perfect hits"
	)

	var perfect_reached := _step_until(
		simulation,
		func(snapshot: Dictionary) -> bool:
			return bool(snapshot.mode_three_bonus.players[0].perfect_awarded),
		700
	)
	_expect(perfect_reached, "level 24 should award the hydrated perfect chain")
	var perfect: Dictionary = simulation.get_snapshot()
	_expect(
		int(perfect.mode_three_bonus.players[0].perfect_reward) == 25000
		and int(perfect.profile_stats[0].mode_three_perfect_reward_index) == 2
		and int(perfect.profile_stats[0].level_eight_perfect_reward_index) == 2,
		"the shared mode-three chain should advance from 25,000 to 50,000"
	)

	var warp_reached := _step_until(
		simulation,
		func(snapshot: Dictionary) -> bool:
			return String(snapshot.get("phase", "")) == Simulation.PHASE_WARP,
		700
	)
	_expect(warp_reached, "level-24 perfect results should enter Warp")
	if not warp_reached:
		return
	simulation._warp_malfunction_interval = 0
	for update_index in range(399):
		simulation.step()
	_expect(
		String(simulation.get_snapshot().phase) == Simulation.PHASE_WARP,
		"level-24 Warp should remain active through update 399"
	)
	simulation.step()
	var shop: Dictionary = simulation.get_snapshot()
	_expect(
		String(shop.phase) == Simulation.PHASE_SHOP
		and int(shop.level_id) == 24
		and int(shop.level_resolution.pending_level_id) == 25,
		"Warp update 400 should enter the level-24 shop with level 25 pending"
	)
	if String(shop.phase) != Simulation.PHASE_SHOP:
		return
	var guard_tick := int(shop.shop.input_guard_until_tick)
	while int(simulation.get_snapshot().tick) <= guard_tick:
		simulation.step()
	_expect(simulation.set_shop_ready(0, true), "the level-24 shop should accept readiness after its guard")
	var routed: Dictionary = simulation.get_snapshot()
	_expect(
		String(routed.phase) == Simulation.PHASE_GET_READY
		and int(routed.level_resolution.pending_level_id) == 25,
		"leaving the level-24 shop should transition toward level 25 without requesting level 26"
	)


func _test_level_twenty_four_miss_resets_chain() -> void:
	var simulation = _new_level(24, "simple", 2425, [{
		"mode_three_perfect_reward_index": 3,
	}])
	if simulation == null:
		return
	(simulation._players[0] as Dictionary).invulnerable_ticks = 10000
	var targets: Array = simulation._enemies.duplicate()
	for index in range(targets.size() - 1):
		_expect(
			_destroy_enemy_with_public_fire(simulation, targets[index] as Dictionary),
			"level-24 miss setup target %d should resolve through collision" % index
		)
	var escaped := targets[-1] as Dictionary
	escaped.authored_state = "entry"
	escaped.behavior_state_id = 1
	escaped.activation_delay_ticks = 0
	escaped.activation_delay_sixths = 0
	escaped.path_index = escaped.path_points.size() - 2
	var penultimate := escaped.path_points[int(escaped.path_index)] as Dictionary
	escaped.path_progress_sixths = (
		int(penultimate.duration_threshold_ticks)
		* Simulation.SIMULATION_SCALE_DENOMINATOR
	)
	simulation.set_input(0, 0)
	simulation.step()
	_expect(
		bool(escaped.get("dead", false))
		and int(simulation._level_escaped_entities) == 1,
		"the final level-24 target should miss through its authored opcode-6 path"
	)
	_expect(
		int(simulation.get_snapshot().mode_three_bonus.players[0].actual_hits) == 29
		and int(simulation.get_snapshot().mode_three_bonus.players[0].misses) == 1,
		"the level-24 miss result should retain twenty-nine hits and one miss"
	)

	var warp_reached := _step_until(
		simulation,
		func(snapshot: Dictionary) -> bool:
			return String(snapshot.get("phase", "")) == Simulation.PHASE_WARP,
		700
	)
	_expect(warp_reached, "a level-24 miss should still proceed into Warp")
	var missed: Dictionary = simulation.get_snapshot()
	_expect(
		int(missed.profile_stats[0].mode_three_perfect_reward_index) == 0
		and int(missed.profile_stats[0].level_eight_perfect_reward_index) == 0
		and int(missed.players[0].progression.mode_three_next_perfect_rewards[0]) == 10000
		and int(missed.players[0].progression.level_eight_next_perfect_rewards[0]) == 10000,
		"one level-24 miss should reset both shared perfect-chain aliases to 10,000"
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
	target.authored_state = "entry"
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


func _step_until(simulation, predicate: Callable, maximum_steps: int) -> bool:
	for step_index in range(maximum_steps):
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
	seats: Array = []
):
	var simulation := Simulation.new()
	_expect(simulation.configure({
		"mode": "solo",
		"difficulty": "normal",
		"collision_mode": collision_mode,
		"seed": seed_value,
		"start_level": level_id,
		"end_level": 25,
		"starting_weapon": 8,
		"starting_lives": 99,
		"starting_money": 100,
		"record_replay": false,
		"seats": seats,
	}), "level-%d simulation should configure: %s" % [level_id, simulation.get_last_error()])
	if not simulation._configured:
		return null
	simulation.step()
	return simulation


func _cleanup_catalog_fixture(temporary_base: String, absolute_base: String) -> void:
	for file_name in Catalog.REQUIRED_FILES:
		DirAccess.remove_absolute(
			ProjectSettings.globalize_path(temporary_base.path_join(file_name))
		)
	DirAccess.remove_absolute(absolute_base)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

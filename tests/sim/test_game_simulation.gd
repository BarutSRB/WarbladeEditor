extends SceneTree

const Simulation := preload("res://src/sim/game_simulation.gd")
const Catalog := preload("res://src/sim/content_catalog.gd")
const SpriteFrameCatalog := preload("res://src/shared/sprite_frame_catalog.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_configuration_and_snapshot()
	_test_authored_lvd_catalog()
	_test_authored_entry_integrator()
	_test_delayed_enemy_collision_eligibility()
	_test_retail_projectile_phase_order()
	_test_retail_projectile_bounds_and_strict_overlap()
	_test_common_projectile_pool_and_masks()
	_test_attack_behavior_runtime_contract()
	_test_first_five_special_enemy_contracts()
	_test_player_retail_spawn_and_movement_contract()
	_test_sprite_frame_contract()
	_test_difficulty_runtime_contract()
	_test_three_fighter_depletion_contract()
	_test_coop_total_fighter_pool()
	_test_mode_scoped_progression()
	_test_deterministic_replay_hashes()
	_test_coop_balance_and_shared_state()
	_test_modes_and_rejections()
	_test_all_weapon_projectile_graphs()
	_test_accuracy_profile_and_shop_contract()
	_test_authoritative_presentation_event_contract()
	_test_pickup_presentation_phase()
	_test_weapon_runtime_contracts()
	_test_laser_runtime_contract()
	_test_first_five_route()
	if _failures.is_empty():
		print("SIM TESTS PASSED")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _test_configuration_and_snapshot() -> void:
	var simulation := Simulation.new()
	_expect(simulation.configure({
		"mode": "solo",
		"difficulty": "normal",
		"seed": 73,
		"record_replay": true,
	}), "normal solo configuration should succeed")
	var snapshot := simulation.get_snapshot()
	_expect(snapshot.version == Simulation.SNAPSHOT_VERSION, "snapshot should publish the current authoritative schema")
	_expect(snapshot.level_id == 1 and snapshot.level_tick == 0, "new runs should start at level one")
	_expect(snapshot.players.size() == 2, "snapshot should expose both stable seat records")
	_expect(snapshot.players[0].active and not snapshot.players[1].active, "solo should activate only seat zero")
	_expect(snapshot.players[0].x_fp == 400 * Simulation.FP_ONE, "solo should center the fighter at retail x=400")
	_expect(snapshot.shared.lives == 3, "new runs should start with three shared lives")
	_expect(
		int(snapshot.rng.draw_count) == 552,
		"solo startup should consume the warp interval, pool/entity initialization, and tail cutoff draws"
	)
	_expect(
		["x", "y", "z", "w", "c", "draw_count"].all(
			func(key: String) -> bool: return snapshot.rng.has(key)
		),
		"snapshots should retain every retail RNG word and the draw counter"
	)
	_expect(snapshot.content_hash.length() == 64, "content hash should be SHA-256")
	_expect(simulation.state_hash().length() == 64, "state hash should be SHA-256")
	_expect(not simulation.configure({
		"mode": "solo",
		"difficulty": "normal",
		"content_hash": "not-the-content-hash",
	}), "mismatched content hashes should be rejected")
	var missing := Catalog.load_catalog("res://content-that-does-not-exist")
	_expect(
		not bool(missing.get("ok", false)),
		"missing release content should fail instead of launching provisional fallback gameplay"
	)
	var explicit_fallback := Catalog.load_catalog(
		"res://content-that-does-not-exist",
		"",
		true
	)
	_expect(
		bool(explicit_fallback.get("ok", false))
		and bool(explicit_fallback.get("using_fallback", false)),
		"fallback content should require an explicit development-only opt-in"
	)


func _test_authored_lvd_catalog() -> void:
	var catalog := Catalog.load_catalog()
	_expect(catalog.ok, "authored LVD catalog should load")
	var expected_groups := [
		2, 2, 2, 25, 2, 2, 2, 2, 2, 4,
		4, 25, 1, 2, 4, 2, 4, 6, 4, 6,
		4, 4, 4, 1, 5, 1, 2, 4, 6, 4,
		4, 6, 2, 2, 4,
		4, 6, 2, 2, 1, 2, 4, 4, 6, 6, 6, 8, 12, 4, 5,
		8, 3, 6, 6, 6, 10, 8, 4, 2, 4, 1, 25,
		11, 9, 5, 4, 8, 10, 2, 7, 8, 6, 2, 4, 5, 4, 6, 4, 8, 10, 10,
		2, 6, 7, 4, 12, 9, 3, 12, 8, 1, 18, 8, 4, 10, 6, 2, 3, 4, 6,
	]
	var expected_enemies := [
		18, 22, 24, 25, 22, 20, 28, 20, 24, 30,
		32, 25, 24, 28, 32, 30, 32, 34, 28, 30,
		32, 30, 26, 30, 16, 25, 22, 24, 36, 30,
		28, 18, 30, 30, 36,
		48, 36, 36, 40, 30, 40, 60, 40, 52, 30, 90, 60, 90, 40, 14,
		76, 120, 30, 36, 60, 126, 110, 80, 40, 46, 22, 25,
		127, 100, 75, 60, 128, 128, 26, 35, 78, 68, 56, 84, 20, 112, 90,
		60, 50, 90, 100, 80, 90, 140, 60, 96, 54, 30, 48, 80, 20, 144,
		123, 80, 60, 116, 60, 45, 80, 12,
	]
	var expected_path_points := [
		22, 20, 24, 85, 42, 22, 22, 18, 22, 44,
		44, 75, 16, 32, 60, 30, 56, 84, 68, 18,
		44, 36, 30, 14, 50, 14, 28, 54, 18, 40,
		40, 60, 22, 24, 48,
		84, 64, 26, 32, 15, 40, 24, 44, 28, 18, 22, 28, 74, 16, 23,
		84, 24, 12, 18, 72, 43, 52, 28, 6, 14, 2, 75,
		55, 34, 24, 12, 44, 48, 4, 21, 30, 16, 16, 52, 52, 46, 18, 44,
		32, 92, 40, 4, 54, 19, 8, 96, 18, 6, 24, 56, 24, 54, 37, 52,
		20, 78, 4, 6, 17, 56,
	]
	var expected_kill_scores := [
		50, 20, 50, 500, 50, 75, 75, 200, 150, 75,
		75, 150, 50, 50, 50, 100, 150, 175, 175, 200,
		200, 200, 200, 200, 50, 300, 300, 300, 400, 500,
		500, 500, 500, 450, 450,
		450, 450, 500, 500, 500, 500, 600, 600, 600, 200, 800, 850, 850, 750, 0,
		1000, 1000, 1000, 500, 750, 750, 750, 500, 750, 750, 750, 500,
		1000, 1000, 1000, 1000, 1000, 1000, 1000, 1500, 1500, 0, 1500,
		3000, 50, 1500, 1500, 1500, 1500, 1000, 1500, 200, 2000, 3000,
		3000, 2000, 2500, 2500, 2500, 3000, 5000, 3000, 3000, 3000,
		5000, 3000, 3000, 5000, 5000, 50,
	]
	for level_index in range(catalog.levels.size()):
		var level: Dictionary = catalog.levels[level_index]
		_expect(level.has("authored_lvd"), "level %d should expose authored LVD data" % int(level.id))
		_expect(
			level.get("authored_runtime", {}) == {"ordinary_speed_fp": Simulation.FP_ONE},
			"level %d should expose the source-backed v9 ordinary speed" % int(level.id)
		)
		var authored: Dictionary = level.authored_lvd
		_expect(
			int(level.ordinary_kill_score) == expected_kill_scores[level_index],
			"level %d should preserve its LVD tail-A ordinary kill score" % int(level.id)
		)
		_expect(
			bool(authored.mirror_x) == (int(level.id) == 100),
			"only the level-100 authored boss encounter should mirror X"
		)
		_expect(
			authored.groups.size() == expected_groups[level_index],
			"level %d should preserve its active group count" % int(level.id)
		)
		var enemy_count := 0
		var path_point_count := 0
		for group in authored.groups:
			enemy_count += group.enemies.size()
			path_point_count += group.path_points.size()
		_expect(
			enemy_count == expected_enemies[level_index],
			"level %d should preserve its authored enemy count" % int(level.id)
		)
		_expect(
			path_point_count == expected_path_points[level_index],
			"level %d should preserve its active path points" % int(level.id)
		)
	_expect(
		String(catalog.levels[1].authored_lvd.source_title_cp1252).is_empty(),
		"level two should preserve its empty retail LVD title"
	)


func _test_authored_entry_integrator() -> void:
	var simulation := Simulation.new()
	_expect(simulation.configure({
		"mode": "solo",
		"difficulty": "normal",
		"collision_mode": "simple",
		"record_replay": false,
	}), "authored entry simulation should configure")
	simulation._levels_by_id[1].waves[0].speed_fp = 123456
	var snapshot := simulation.step()
	_expect(snapshot.enemies.size() == 18, "level one should instantiate all eighteen authored enemies")
	var first: Dictionary = snapshot.enemies[0]
	_expect(first.group_id == 0 and first.enemy_index == 0, "first enemy should retain authored identity")
	_expect(first.authored_state == "entry", "zero-delay enemy should begin its entry path")
	_expect(
		int(first.speed_fp) == Simulation.FP_ONE,
		"v9 authored enemies must ignore predecessor compatibility wave speed"
	)
	_expect(first.x_fp == 200 * Simulation.FP_ONE + 29360, "retail top-left entry X should convert to remake center X")
	_expect(first.y_fp == -75 * Simulation.FP_ONE + 29360, "retail top-left entry Y should convert before integration")
	_expect(first.velocity_x_fp == 29360, "zero X acceleration should preserve initial velocity")
	_expect(first.velocity_y_fp == 30212, "Y acceleration should apply after the first position step")
	_expect(first.acceleration_y_fp == 852, "path milli acceleration should convert deterministically")
	_expect(first.path_index == 0 and first.path_progress_ticks == 1, "first path progress should begin at one tick")
	_expect(first.formation_target_x_fp == 358 * Simulation.FP_ONE, "formation target X should use the 800-wide logical center")
	_expect(first.formation_target_y_fp == 85 * Simulation.FP_ONE, "formation target Y should remain authored")
	var delayed: Dictionary = snapshot.enemies[1]
	_expect(delayed.authored_state == "delayed", "staggered group members should wait")
	_expect(delayed.activation_delay_ticks == 14, "the authoritative tick should decrement a 15-tick stagger once")
	_expect(delayed.x_fp == 200 * Simulation.FP_ONE, "delayed enemies should remain at their center-converted entry origin")
	for tick in range(21):
		snapshot = simulation.step()
	first = snapshot.enemies[0]
	_expect(first.path_index == 0 and first.path_progress_ticks == 22, "strict path threshold should not advance at equality")
	snapshot = simulation.step()
	first = snapshot.enemies[0]
	_expect(first.path_index == 1 and first.path_progress_ticks == 0, "a new LVD segment should reset progress to retail float zero")
	_expect(first.acceleration_x_fp == -852, "the next authored path acceleration should become active")
	var terminal: Dictionary = simulation._enemies[0]
	terminal.x_fp = 123 * Simulation.FP_ONE + 17
	terminal.y_fp = -41 * Simulation.FP_ONE + 29
	terminal.velocity_x_fp = 34567
	terminal.velocity_y_fp = -45678
	simulation._finish_authored_entry(terminal)
	_expect(
		terminal.authored_state == "formation"
		and terminal.behavior_state_id == 2
		and terminal.x_fp == 123 * Simulation.FP_ONE + 17
		and terminal.y_fp == -41 * Simulation.FP_ONE + 29
		and terminal.velocity_x_fp == 34567
		and terminal.velocity_y_fp == -45678,
		"terminal opcode one should change only state and preserve integrated position/motion"
	)


func _test_delayed_enemy_collision_eligibility() -> void:
	var simulation := Simulation.new()
	_expect(simulation.configure({
		"mode": "solo",
		"difficulty": "normal",
		"collision_mode": "simple",
		"record_replay": false,
	}), "delayed-enemy collision simulation should configure")
	simulation.step()
	var delayed: Dictionary = simulation._enemies[1]
	_expect(
		String(delayed.authored_state) == "delayed"
		and int(delayed.activation_delay_ticks) > 0,
		"the regression target should still be waiting on its authored stagger"
	)
	var initial_health := int(delayed.health_fp)
	var projectile := {
		"id": 9001,
		"owner_kind": "player",
		"owner_id": 0,
		"x_fp": int(delayed.x_fp),
		"y_fp": int(delayed.y_fp),
		"width": int(delayed.width),
		"height": int(delayed.height),
		"damage_fp": Simulation.FP_ONE,
		"prototype_id": 0,
		"expired": false,
	}
	simulation._enemies = [delayed]
	simulation._projectiles = [projectile]
	simulation._resolve_projectile_collisions()
	_expect(
		int(simulation._enemies[0].health_fp) == initial_health
		and not bool(simulation._projectiles[0].expired),
		"authored enemies must not collide with player shots before activation"
	)
	simulation._enemies[0].authored_state = "entry"
	var broad_phase := simulation._objects_collide(
		simulation._projectiles[0],
		simulation._enemies[0]
	)
	simulation._resolve_projectile_collisions()
	_expect(
		bool(simulation._enemies[0].dead)
		and bool(simulation._projectiles[0].expired),
		"the same enemy should become collidable after entering its active state: state=%s broad=%s dead=%s expired=%s health=%d" % [
			str(simulation._enemies[0].authored_state),
			str(broad_phase),
			str(simulation._enemies[0].dead),
			str(simulation._projectiles[0].expired),
			int(simulation._enemies[0].health_fp),
		]
	)


func _test_retail_projectile_phase_order() -> void:
	var player_shot := Simulation.new()
	_expect(player_shot.configure({
		"mode": "solo",
		"difficulty": "normal",
		"collision_mode": "simple",
		"record_replay": false,
	}), "player-shot phase-order simulation should configure")
	player_shot.set_input(0, Simulation.ACTION_FIRE)
	var snapshot := player_shot.step()
	_expect(snapshot.projectiles.size() == 1, "a manual fire edge should create one player shot")
	_expect(
		int(snapshot.projectiles[0].y_fp) == 555 * Simulation.FP_ONE,
		"new player shots should remain at their retail spawn position on the birth tick"
	)
	player_shot._enemies.clear()
	player_shot._enemies.append({
		"id": 9002,
		"x_fp": int(snapshot.projectiles[0].x_fp),
		"y_fp": int(snapshot.projectiles[0].y_fp),
		"width": 32,
		"height": 32,
		"health_fp": Simulation.FP_ONE,
		"max_health_fp": Simulation.FP_ONE,
		"score": 0,
		"cash": 0,
		"sprite": "alien001",
		"dead": false,
	})
	player_shot.set_input(0, 0)
	snapshot = player_shot.step()
	_expect(
		snapshot.events.any(func(event: Dictionary) -> bool: return String(event.type) == "enemy_destroyed" and int(event.entity_id) == 9002),
		"an existing player shot should collide before its next movement phase"
	)

	var enemy_shot := Simulation.new()
	_expect(enemy_shot.configure({
		"mode": "solo",
		"difficulty": "normal",
		"collision_mode": "simple",
		"record_replay": false,
	}), "alien-shot phase-order simulation should configure")
	enemy_shot.step()
	var player: Dictionary = enemy_shot._players[0]
	enemy_shot._enemies = [{
		"id": 9003,
		"authored_lvd": true,
		"authored_state": "hold",
		"behavior_state_id": 1,
		"level_mode_id": 1,
		"behavior_timer_a": 1,
		"projectile_speed_fp": 2 * Simulation.FP_ONE,
		"x_fp": int(player.x_fp) - 13 * Simulation.FP_ONE,
		"y_fp": int(player.y_fp) - 16 * Simulation.FP_ONE,
		"width": 32,
		"height": 32,
		"health_fp": Simulation.FP_ONE,
		"max_health_fp": Simulation.FP_ONE,
		"sprite": "alien001",
		"dead": false,
	}]
	snapshot = enemy_shot.step()
	var fire_events: Array = snapshot.events.filter(func(event: Dictionary) -> bool: return String(event.type) == "enemy_fired")
	_expect(fire_events.size() == 1, "the guaranteed test alien should fire once")
	if fire_events.size() == 1:
		_expect(
			int(fire_events[0].x_fp) == int(player.x_fp)
			and int(fire_events[0].y_fp) == int(player.y_fp),
			"alien shots should spawn centered at alien + (13,16) without birth movement"
		)
	_expect(
		not bool(snapshot.players[0].alive),
		"new alien shots should be collision-eligible after player update on their birth tick"
	)

	var laser := Simulation.new()
	_expect(laser.configure({
		"mode": "solo",
		"difficulty": "normal",
		"collision_mode": "simple",
		"starting_weapon": 7,
		"record_replay": false,
	}), "laser phase-order simulation should configure")
	laser.set_input(0, Simulation.ACTION_FIRE)
	snapshot = laser.step()
	_expect(
		not snapshot.events.any(func(event: Dictionary) -> bool: return String(event.type) == "enemy_hit"),
		"laser frame 22 should not collide on its firing frame"
	)
	laser._enemies = [{
		"id": 9004,
		"authored_lvd": true,
		"authored_state": "hold",
		"behavior_state_id": 1,
		"level_mode_id": 3,
		"behavior_timer_a": 1,
		"projectile_speed_fp": 0,
		"x_fp": 400 * Simulation.FP_ONE,
		"y_fp": 100 * Simulation.FP_ONE,
		"width": 32,
		"height": 32,
		"health_fp": 100 * Simulation.FP_ONE,
		"max_health_fp": 100 * Simulation.FP_ONE,
		"score": 0,
		"cash": 0,
		"sprite": "alien001",
		"dead": false,
	}]
	laser.set_input(0, 0)
	var collision_frames: Array[int] = []
	for collision_index in range(4):
		snapshot = laser.step()
		if snapshot.events.any(func(event: Dictionary) -> bool: return String(event.type) == "enemy_hit" and int(event.entity_id) == 9004):
			collision_frames.append(Simulation.LASER_FRAME_CHAIN[collision_index])
	_expect(
		collision_frames == Simulation.LASER_FRAME_CHAIN,
		"laser should collide exactly once on frames 22, 23, 24, and 50"
	)
	_expect(laser._projectiles.is_empty(), "laser should retire immediately after frame 50's collision opportunity")


func _test_retail_projectile_bounds_and_strict_overlap() -> void:
	var simulation := Simulation.new()
	_expect(simulation.configure({
		"mode": "solo",
		"difficulty": "normal",
		"collision_mode": "simple",
		"record_replay": false,
	}), "projectile-boundary simulation should configure")
	var projectile := {
		"x_fp": -48 * Simulation.FP_ONE,
		"y_fp": -45 * Simulation.FP_ONE,
		"width": 4,
		"height": 10,
	}
	_expect(
		not simulation._player_projectile_out_of_bounds(projectile),
		"retail top/left bounds should remain live at exactly -50"
	)
	projectile.y_fp = -46 * Simulation.FP_ONE
	_expect(
		simulation._player_projectile_out_of_bounds(projectile),
		"a truncated player-shot top below -50 should retire"
	)
	projectile.y_fp = 0
	projectile.x_fp = 852 * Simulation.FP_ONE
	_expect(
		not simulation._player_projectile_out_of_bounds(projectile),
		"retail player-shot left should remain live at exactly 850"
	)
	projectile.x_fp = 853 * Simulation.FP_ONE
	_expect(
		simulation._player_projectile_out_of_bounds(projectile),
		"a truncated player-shot left above 850 should retire"
	)
	var left := {"x_fp": 0, "y_fp": 0, "width": 10, "height": 10}
	var touching := {"x_fp": 10 * Simulation.FP_ONE, "y_fp": 0, "width": 10, "height": 10}
	_expect(
		not simulation._objects_collide(left, touching),
		"strict retail AABBs should treat edge contact as a miss"
	)
	touching.x_fp -= 1
	_expect(simulation._objects_collide(left, touching), "one fixed-point unit of overlap should collide")


func _test_common_projectile_pool_and_masks() -> void:
	var simulation := Simulation.new()
	_expect(simulation.configure({
		"mode": "solo",
		"difficulty": "normal",
		"collision_mode": "pixel",
		"record_replay": false,
	}), "common-projectile pool simulation should configure")
	var enemy := {
		"id": 9005,
		"sprite": "alien_2",
		"x_fp": 100 * Simulation.FP_ONE,
		"y_fp": 100 * Simulation.FP_ONE,
		"projectile_speed_fp": 2 * Simulation.FP_ONE,
	}
	for projectile_index in range(Simulation.COMMON_PROJECTILE_SLOT_COUNT + 1):
		simulation._fire_enemy_projectile(enemy)
	_expect(
		simulation._projectiles.size() == Simulation.COMMON_PROJECTILE_SLOT_COUNT,
		"alien shots should scan the fixed retail pool of one hundred common slots"
	)
	var first: Dictionary = simulation._projectiles[0]
	var initial_phase := int(first.animation_frame)
	_expect(
		int(first.common_slot) == 0
		and int(first.velocity_x_fp) == 0
		and int(first.x_fp) == 113 * Simulation.FP_ONE
		and int(first.y_fp) == 116 * Simulation.FP_ONE
		and int(first.width) == 32
		and int(first.height) == 32,
		"first-five alien shots should use the recovered slot, motion, and centered geometry"
	)
	_expect(
		simulation._mask_source_rect(first, simulation._hit_masks.alien_2)
		== Rect2i(480, initial_phase * 32, 32, 32),
		"alien-shot collision should use its retail-seeded firing-alien HMA row"
	)
	simulation._update_common_projectiles()
	var advanced_phase := 1 - initial_phase
	_expect(
		int(first.animation_frame) == initial_phase
		and int(first.animation_countdown_fp) == 0,
		"common-slot animation should survive exact countdown equality"
	)
	simulation._update_common_projectiles()
	_expect(
		int(first.animation_frame) == advanced_phase
		and simulation._mask_source_rect(first, simulation._hit_masks.alien_2)
		== Rect2i(480, advanced_phase * 32, 32, 32),
		"common-slot animation should advance only after countdown underflow"
	)
	first.expired = true
	simulation._remove_expired_entities()
	simulation._fire_enemy_projectile(enemy)
	var reused: Dictionary = simulation._projectiles.back()
	_expect(
		int(reused.common_slot) == 0 and int(reused.animation_frame) == advanced_phase,
		"reused common slots should preserve their retail animation phase"
	)
	reused.y_fp = 614 * Simulation.FP_ONE
	simulation._update_common_projectiles()
	_expect(
		not bool(reused.expired) and int(reused.y_fp) == 616 * Simulation.FP_ONE,
		"alien shots should remain live after movement lands at centered Y 616"
	)
	reused.y_fp = 616 * Simulation.FP_ONE + 1
	reused.velocity_y_fp = 0
	simulation._update_common_projectiles()
	_expect(bool(reused.expired), "alien shots should retire only when centered Y is strictly above 616")
	var player: Dictionary = simulation._players[0]
	var missing_mask_shot := reused.duplicate(true)
	missing_mask_shot.expired = false
	missing_mask_shot.x_fp = int(player.x_fp)
	missing_mask_shot.y_fp = int(player.y_fp)
	missing_mask_shot.mask_id = "missing_first_five_mask"
	_expect(
		not simulation._enemy_projectile_hits_object(missing_mask_shot, player),
		"pixel collision should fail closed when a required first-five shot mask is unavailable"
	)


func _test_attack_behavior_runtime_contract() -> void:
	var catalog := Catalog.load_catalog()
	_expect(catalog.ok, "SWD runtime content should load")
	_expect(catalog.swd_paths.size() == 14, "the global SWD pool should retain all fourteen slots")
	_expect(
		catalog.swd_paths[0].source_sha256 == catalog.swd_paths[1].source_sha256
		and catalog.swd_paths[0].id != catalog.swd_paths[1].id,
		"byte-identical att001 and att002 should retain two selection slots"
	)
	var simulation := Simulation.new()
	_expect(simulation.configure({
		"mode": "solo",
		"difficulty": "normal",
		"collision_mode": "simple",
		"record_replay": false,
	}), "attack behavior simulation should configure")
	simulation.step()
	_expect(
		simulation._authored_slot_seeds.size() == Simulation.AUTHORED_ENTITY_SLOT_COUNT,
		"ordinary animation state should be seeded for all 150 retail entity slots"
	)
	var enemy: Dictionary = simulation._enemies[0]
	enemy.authored_state = "formation"
	enemy.behavior_state_id = 2
	enemy.x_fp = int(enemy.formation_target_x_fp)
	enemy.y_fp = int(enemy.formation_target_y_fp)
	enemy.behavior_timer_b = 2
	enemy.authored_animation_frame = 0
	enemy.animation_direction = 0
	enemy.animation_metadata = 1
	enemy.animation_countdown_sixths = simulation._simulation_scale_numerator()
	# Retail seed zero's first word is odd, so the Timer-B modulo-two branch
	# deterministically launches an SWD attack.
	simulation._rng.seed(0)
	simulation._update_state_two(enemy)
	_expect(
		enemy.authored_state == "swd_attack"
		and enemy.behavior_state_id == 3
		and enemy.swd_runtime_index >= 0
		and enemy.swd_runtime_index < 14,
		"state 2 Timer B should select one global SWD path on a half-open integer draw of one"
	)
	_expect(
		enemy.authored_animation_frame == 0 and enemy.animation_direction == 0,
		"state-2 animation should survive exact countdown equality"
	)
	var selected: Dictionary = catalog.swd_paths[int(enemy.swd_runtime_index)]
	_expect(
		enemy.velocity_x_fp == int(selected.initial_velocity_x_fixed_256) * 256
		and enemy.velocity_y_fp == int(selected.initial_velocity_y_fixed_256) * 256
		and enemy.swd_progress_sixths == simulation._simulation_scale_numerator(),
		"state 3 should initialize fixed-256 velocity and one tick-scale of progress"
	)
	var previous_x := int(enemy.x_fp)
	var previous_y := int(enemy.y_fp)
	var previous_vx := int(enemy.velocity_x_fp)
	var previous_vy := int(enemy.velocity_y_fp)
	var previous_ax := int(enemy.acceleration_x_fp)
	var previous_ay := int(enemy.acceleration_y_fp)
	simulation._update_state_three(enemy)
	_expect(
		enemy.x_fp == previous_x + previous_vx
		and enemy.y_fp == previous_y + previous_vy
		and enemy.velocity_x_fp == previous_vx + previous_ax
		and enemy.velocity_y_fp == previous_vy + previous_ay,
		"state 3 should update position before velocity with the authoritative normal scale"
	)
	enemy.x_fp = 387 * Simulation.FP_ONE
	enemy.y_fp = 100 * Simulation.FP_ONE
	simulation._rng.seed(5)
	_expect(
		simulation._proximity_adjusted_timer_a(enemy, 400) == 100,
		"the proximity gate should quarter Timer A inside ten pixels when its masked draw passes"
	)


func _test_first_five_special_enemy_contracts() -> void:
	var level_three := Simulation.new()
	_expect(level_three.configure({
		"mode": "solo",
		"difficulty": "normal",
		"collision_mode": "simple",
		"start_level": 3,
		"record_replay": false,
	}), "level-three supplemental simulation should configure")
	var snapshot := level_three.step()
	_expect(
		snapshot.enemies.size() == 25,
		"level three should spawn twenty-four ordinary enemies plus its one supplemental enemy"
	)
	var supplemental: Dictionary = {}
	for candidate in level_three._enemies:
		if String(candidate.authored_state) == "supplemental_large":
			supplemental = candidate
			break
	_expect(not supplemental.is_empty(), "level three should create its state-6 supplemental entity")
	_expect(
		supplemental.width == 64
		and supplemental.height == 64
		and supplemental.max_health_fp == 12 * Simulation.FP_ONE
		and supplemental.heading >= 18
		and supplemental.heading <= 22,
		"the supplemental enemy should preserve its 64-pixel atlas, health, and heading range"
	)
	_expect(
		supplemental.x_fp > 231 * Simulation.FP_ONE
		and supplemental.x_fp < 632 * Simulation.FP_ONE
		and supplemental.behavior_timer_a == 1400
		and supplemental.behavior_timer_b == 300
		and supplemental.steering_mode == 2
		and supplemental.heading_step_countdown_sixths == 12,
		"the supplemental enemy should use its center-converted spawn range, timers, and neutral steering"
	)

	var level_four := Simulation.new()
	_expect(level_four.configure({
		"mode": "solo",
		"difficulty": "normal",
		"collision_mode": "simple",
		"start_level": 4,
		"record_replay": false,
	}), "level-four state-10 simulation should configure")
	level_four.step()
	var state_ten: Dictionary = level_four._enemies[0]
	state_ten.y_fp = 550 * Simulation.FP_ONE
	level_four._rng.seed(5)
	level_four._begin_state_ten(state_ten)
	_expect(
		state_ten.vertical_acceleration_fp >= 13107
		and state_ten.vertical_acceleration_fp < 26214
		and state_ten.horizontal_acceleration_fp >= -6554
		and state_ten.horizontal_acceleration_fp < 6554
		and state_ten.horizontal_flip_interval_sixths >= 60
		and state_ten.horizontal_flip_interval_sixths <= 84,
		"state 10 should initialize its proven acceleration and ten-to-fourteen-tick flip ranges"
	)
	var acceleration_y := int(state_ten.vertical_acceleration_fp)
	var acceleration_x := int(state_ten.horizontal_acceleration_fp)
	level_four._update_state_ten(state_ten)
	_expect(
		not state_ten.dead
		and state_ten.horizontal_velocity_fp == acceleration_x
		and state_ten.vertical_velocity_fp == acceleration_y
		and state_ten.vertical_acceleration_fp
		== level_four._trunc_div(acceleration_y * 120, 126),
		"state 10 should preserve its motion order and scale-dependent vertical damping"
	)
	var boundary: Dictionary = state_ten.duplicate(true)
	boundary.dead = false
	boundary.y_fp = -116 * Simulation.FP_ONE
	boundary.vertical_velocity_fp = 0
	boundary.vertical_acceleration_fp = 0
	boundary.horizontal_velocity_fp = 0
	boundary.horizontal_acceleration_fp = 0
	boundary.horizontal_flip_countdown_sixths = 60
	level_four._update_state_ten(boundary)
	_expect(not boundary.dead, "state 10 should survive equality at center Y plus 16 equals -100")
	boundary.dead = false
	boundary.y_fp = -116 * Simulation.FP_ONE - 1
	level_four._update_state_ten(boundary)
	_expect(boundary.dead, "state 10 should deactivate one fixed unit beyond the strict retail top bound")


func _test_player_retail_spawn_and_movement_contract() -> void:
	var solo := Simulation.new()
	_expect(solo.configure({
		"mode": "solo",
		"difficulty": "normal",
		"collision_mode": "simple",
		"record_replay": false,
	}), "retail player contract simulation should configure")
	var snapshot := solo.get_snapshot()
	var player: Dictionary = snapshot.players[0]
	_expect(player.x_fp == 400 * Simulation.FP_ONE, "solo should convert retail top-left x=380 to center x=400")
	_expect(player.y_fp == 564 * Simulation.FP_ONE, "player should convert retail top-left y=550 to center y=564")
	_expect(player.width == 40 and player.height == 28, "player dimensions should match the retail fighter frame")
	solo.set_input(0, Simulation.ACTION_RIGHT)
	snapshot = solo.step()
	_expect(snapshot.players[0].x_fp == 404 * Simulation.FP_ONE, "normal base lateral speed should be four pixels per tick")
	for tick in range(100):
		snapshot = solo.step()
	_expect(snapshot.players[0].x_fp == 716 * Simulation.FP_ONE, "right movement should clamp at retail center x=716")
	solo.set_input(0, 0)
	solo._damage_player(solo._players[0], Simulation.FP_ONE)
	for tick in range(Simulation.RESPAWN_TICKS):
		snapshot = solo.step()
	_expect(snapshot.players[0].alive, "solo fighter should respawn after the authoritative delay")
	_expect(snapshot.players[0].x_fp == 400 * Simulation.FP_ONE, "solo respawn should return to retail center x=400")
	var coop := Simulation.new()
	_expect(coop.configure({
		"mode": "coop",
		"difficulty": "normal",
	}), "co-op split spawn simulation should configure")
	var coop_players: Array = coop.get_snapshot().players
	_expect(
		coop_players[0].x_fp == 330 * Simulation.FP_ONE
		and coop_players[1].x_fp == 470 * Simulation.FP_ONE,
		"new simultaneous co-op should retain its explicit split spawn"
	)


func _test_three_fighter_depletion_contract() -> void:
	var simulation := Simulation.new()
	_expect(simulation.configure({
		"mode": "solo",
		"difficulty": "normal",
		"collision_mode": "simple",
		"record_replay": false,
	}), "three-fighter depletion simulation should configure")
	var snapshot := simulation.get_snapshot()
	for expected_remaining in [2, 1]:
		simulation._damage_player(simulation._players[0], Simulation.FP_ONE)
		_expect(
			simulation.get_snapshot().shared.lives == expected_remaining + 1,
			"retail should retain the encoded fighter count during the death delay"
		)
		for tick in range(Simulation.RESPAWN_TICKS):
			snapshot = simulation.step()
		_expect(snapshot.shared.lives == expected_remaining, "the death deadline should consume one fighter")
		_expect(snapshot.players[0].alive, "a remaining fighter count should permit respawn")
	simulation._damage_player(simulation._players[0], Simulation.FP_ONE)
	for tick in range(Simulation.RESPAWN_TICKS):
		snapshot = simulation.step()
	_expect(snapshot.shared.lives == 0, "the third destroyed fighter should exhaust the encoded count")
	_expect(snapshot.phase == Simulation.PHASE_GAME_OVER, "three initial fighters should allow exactly three destructions")
	simulation._shared.lives = Simulation.MAX_FIGHTERS
	_expect(
		not simulation._can_apply_shop_effect({"effect": "life_up"}),
		"retail fighter count should cap at five"
	)


func _test_coop_total_fighter_pool() -> void:
	var simulation := Simulation.new()
	_expect(simulation.configure({
		"mode": "coop",
		"difficulty": "normal",
		"collision_mode": "simple",
		"record_replay": false,
	}), "co-op fighter-pool simulation should configure")
	var player_zero: Dictionary = simulation._players[0]
	var player_one: Dictionary = simulation._players[1]
	simulation._damage_player(player_zero, Simulation.FP_ONE)
	_expect(
		simulation._shared.lives == 3
		and bool(player_zero.active)
		and int(player_zero.respawn_ticks) > 0,
		"co-op should defer shared-fighter consumption until the death deadline"
	)
	player_zero.respawn_ticks = 1
	simulation._update_respawns()
	_expect(
		bool(player_zero.alive) and simulation._shared.lives == 2,
		"the first destroyed co-op seat should consume the one reserve at its deadline"
	)
	simulation._damage_player(player_zero, Simulation.FP_ONE)
	player_zero.respawn_ticks = 1
	simulation._update_respawns()
	_expect(
		simulation._shared.lives == 1
		and not bool(player_zero.active)
		and bool(player_one.alive),
		"a live partner should reserve the final fighter and block a fourth ship"
	)
	simulation._enemies.clear()
	simulation._begin_level(2)
	_expect(
		not bool(player_zero.active)
		and not bool(player_zero.alive)
		and bool(player_one.active)
		and bool(player_one.alive),
		"a new level must not resurrect a co-op seat when no shared fighter is available"
	)
	simulation._damage_player(player_one, Simulation.FP_ONE)
	player_one.respawn_ticks = 1
	simulation._update_respawns()
	_expect(
		simulation._shared.lives == 0
		and simulation.get_snapshot().phase == Simulation.PHASE_GAME_OVER,
		"three shared fighters must permit exactly three co-op destructions"
	)


func _test_mode_scoped_progression() -> void:
	var coop := Simulation.new()
	_expect(coop.configure({
		"mode": "coop",
		"difficulty": "normal",
		"collision_mode": "simple",
		"record_replay": false,
	}), "shared co-op progression simulation should configure")
	coop._apply_shop_effect({"effect": "equip_weapon", "weapon_id": 1}, 0)
	_expect(
		coop._progression_for_seat(0).weapon_id == 1
		and coop._progression_for_seat(1).weapon_id == 1,
		"simultaneous co-op should keep its explicitly shared progression"
	)


func _test_difficulty_runtime_contract() -> void:
	var expected := {
		"easy": {
			"scale": 6,
			"timer": 2800,
			"player_speed": 275251,
			"projectile_speed": 229376,
			"state_six_aimed_shot_travel_multiplier": 3.0,
		},
		"normal": {
			"scale": 6,
			"timer": 2600,
			"player_speed": 262144,
			"projectile_speed": 281805,
			"state_six_aimed_shot_travel_multiplier": 2.2,
		},
		"hard": {
			"scale": 7,
			"timer": 2350,
			"player_speed": 229376,
			"projectile_speed": 382293,
			"state_six_aimed_shot_travel_multiplier": 2.0,
		},
		"ace": {
			"scale": 8,
			"timer": 2200,
			"player_speed": 196608,
			"projectile_speed": 480597,
			"state_six_aimed_shot_travel_multiplier": 1.8,
		},
	}
	for difficulty_id in expected:
		var simulation := Simulation.new()
		_expect(simulation.configure({
			"mode": "solo",
			"difficulty": difficulty_id,
			"collision_mode": "simple",
			"record_replay": false,
		}), "%s difficulty simulation should configure" % difficulty_id)
		var snapshot := simulation.step()
		var contract: Dictionary = expected[difficulty_id]
		var enemy: Dictionary = snapshot.enemies[0]
		_expect(
			int(simulation._difficulty.simulation_scale_numerator) == int(contract.scale),
			"%s should use its recovered sixth-tick simulation scale" % difficulty_id
		)
		_expect(
			enemy.max_health_fp == Simulation.FP_ONE,
			"%s should preserve first-five authored enemy health" % difficulty_id
		)
		_expect(
			enemy.behavior_timer_a == int(contract.timer)
			and enemy.behavior_timer_b == int(contract.timer),
			"%s should apply its recovered level-one timer transform" % difficulty_id
		)
		_expect(
			snapshot.shared.speed_fp == int(contract.player_speed),
			"%s should apply its recovered player base delta" % difficulty_id
		)
		_expect(
			int(simulation._enemies[0].projectile_speed_fp) == int(contract.projectile_speed),
			"%s should apply its recovered alien projectile delta" % difficulty_id
		)
		_expect(
			PackedFloat32Array([
				simulation._state_six_aimed_shot_travel_multiplier()
			])[0]
			== PackedFloat32Array([
				float(contract.state_six_aimed_shot_travel_multiplier)
			])[0],
			"%s should apply its recovered state-6 aimed-shot travel multiplier"
			% difficulty_id
		)
	var hard := Simulation.new()
	_expect(hard.configure({
		"mode": "solo",
		"difficulty": "hard",
		"collision_mode": "simple",
		"record_replay": false,
	}), "hard path-scale simulation should configure")
	var hard_snapshot := hard.step()
	var hard_enemy: Dictionary = hard_snapshot.enemies[0]
	_expect(
		hard_enemy.x_fp == 200 * Simulation.FP_ONE + 34253,
		"hard entry position should advance by seven sixths"
	)
	_expect(
		hard_enemy.path_progress_sixths == 7,
		"hard path progress should retain exact sixth-tick units"
	)
	hard._tighten_enemy_behavior_timers(2)
	_expect(
		hard._enemies[0].behavior_timer_a == 2150
		and hard._enemies[0].behavior_timer_b == 2150,
		"level-one hard timers should tighten by two authored kill steps"
	)
	_expect(
		hard._fire_roll_passes(2147483647, 4, 6)
		and not hard._fire_roll_passes(2147483648, 4, 6),
		"deterministic fire threshold should preserve the strict retail boundary"
	)
	hard._rng.restore({
		"x": 0,
		"y": 0,
		"z": 0,
		"w": 0,
		"c": 0xff00ff00,
		"draw_count": 12,
	})
	_expect(
		hard._random_retail_float_fp(-1.5, 0.0) == 0
		and int(hard._rng.draw_count) == 13,
		"maximum U32 must preserve the rare float32 upper endpoint through fixed-point conversion"
	)


func _test_sprite_frame_contract() -> void:
	var frames := SpriteFrameCatalog.new()
	_expect(frames.load_file(), "proven sprite-frame catalog should load")
	_expect(
		frames.fighter_source_rect(5) == Rect2i(200, 0, 40, 27),
		"neutral fighter frame should use the exact retail rectangle"
	)
	_expect(
		frames.enemy_direction_frame(Simulation.FP_ONE, 0, false) == 4,
		"rightward entry velocity should select the recovered horizontal bucket"
	)
	_expect(
		frames.enemy_direction_frame(0, Simulation.FP_ONE, false) == 8,
		"vertical entry velocity should use the recovered positive sentinel bucket"
	)
	_expect(
		frames.enemy_direction_frame(0, Simulation.FP_ONE, true) == 0,
		"mirrored entry velocity should use the recovered mirror table"
	)
	_expect(
		frames.projectile_source_rect(18) == Rect2i(176, 0, 22, 41),
		"plasma should use its recovered packed-atlas rectangle"
	)
	var state_ten_rects: Array[Rect2i] = [
		Rect2i(512, 0, 32, 32),
		Rect2i(512, 32, 32, 32),
		Rect2i(512, 64, 32, 32),
		Rect2i(544, 0, 32, 32),
		Rect2i(544, 32, 32, 32),
		Rect2i(544, 64, 32, 32),
	]
	for phase in range(6):
		_expect(
			frames.enemy_source_rect({
				"authored_state": "state_ten",
				"authored_animation_frame": phase,
				"authored_sprite_frame": 15,
				"id": 999,
			}, 12345) == state_ten_rects[phase],
			"state 10 phase %d should use its proven six-cell source selector" % phase
		)
	var simulation := Simulation.new()
	_expect(simulation.configure({
		"mode": "solo",
		"difficulty": "normal",
		"collision_mode": "simple",
		"record_replay": false,
	}), "fighter banking simulation should configure")
	simulation.set_input(0, Simulation.ACTION_RIGHT)
	simulation.step()
	var snapshot := simulation.step()
	_expect(snapshot.players[0].sprite_frame == 6, "two right updates should bank from frame five to six")
	_expect(
		simulation._players[0].sprite_phase_half_steps == 12,
		"fighter banking should retain the retail half-frame phase"
	)
	simulation.set_input(0, Simulation.ACTION_LEFT | Simulation.ACTION_RIGHT)
	snapshot = simulation.step()
	_expect(
		simulation._players[0].sprite_phase_half_steps == 11
		and snapshot.players[0].sprite_frame == 5,
		"simultaneous directions should preserve the retail left-key priority"
	)
	simulation.set_input(0, 0)
	simulation.step()
	_expect(
		simulation._players[0].sprite_phase_half_steps == 10,
		"idle banking should move toward neutral by one half-frame"
	)


func _test_deterministic_replay_hashes() -> void:
	var left := Simulation.new()
	var right := Simulation.new()
	var config := {
		"mode": "coop",
		"difficulty": "hard",
		"coop_balance": "classic",
		"seed": 9191,
		"record_replay": true,
	}
	_expect(left.configure(config), "left deterministic simulation should configure")
	_expect(right.configure(config), "right deterministic simulation should configure")
	for tick in range(420):
		var p1_mask := 0
		var p2_mask := 0
		if tick % 120 < 60:
			p1_mask |= Simulation.ACTION_LEFT
			p2_mask |= Simulation.ACTION_RIGHT
		else:
			p1_mask |= Simulation.ACTION_RIGHT
			p2_mask |= Simulation.ACTION_LEFT
		if tick % 12 == 0:
			p1_mask |= Simulation.ACTION_FIRE
		if tick % 15 == 0:
			p2_mask |= Simulation.ACTION_FIRE
		left.set_input(0, p1_mask)
		left.set_input(1, p2_mask)
		right.set_input(0, p1_mask)
		right.set_input(1, p2_mask)
		left.step()
		right.step()
		_expect(left.state_hash() == right.state_hash(), "identical inputs diverged at tick %d" % tick)
		if not _failures.is_empty():
			break
	_expect(left.get_replay().frames.size() == 420, "enabled replay capture should record each authoritative tick")
	_expect(
		int(left.get_replay().version) == Simulation.REPLAY_VERSION
		and ["x", "y", "z", "w", "c", "draw_count"].all(
			func(key: String) -> bool: return left.get_replay().initial_rng.has(key)
		),
		"replays should identify the five-word RNG schema and its pre-level-load state"
	)


func _test_coop_balance_and_shared_state() -> void:
	var classic := Simulation.new()
	var balanced := Simulation.new()
	var base := {
		"mode": "coop",
		"difficulty": "normal",
		"seed": 4,
		"record_replay": false,
	}
	var classic_config := base.duplicate(true)
	classic_config["coop_balance"] = "classic"
	var balanced_config := base.duplicate(true)
	balanced_config["coop_balance"] = "balanced"
	_expect(classic.configure(classic_config), "classic co-op should configure")
	_expect(balanced.configure(balanced_config), "balanced co-op should configure")
	for tick in range(1):
		classic.step()
		balanced.step()
	var classic_snapshot := classic.get_snapshot()
	var balanced_snapshot := balanced.get_snapshot()
	_expect(classic_snapshot.players[0].active and classic_snapshot.players[1].active, "co-op should activate both seats")
	_expect(classic_snapshot.enemies.size() == 18, "level one should spawn all authored enemies on its first tick")
	_expect(
		balanced_snapshot.enemies[0].max_health_fp == classic_snapshot.enemies[0].max_health_fp * 2,
		"balanced co-op should apply exactly two times enemy health"
	)
	_expect(
		balanced_snapshot.shared == classic_snapshot.shared,
		"co-op balance should not alter shared player progression"
	)


func _test_modes_and_rejections() -> void:
	var removed := Simulation.new()
	_expect(not removed.configure({
		"mode": "alternating",
		"difficulty": "easy",
	}), "removed alternating mode should be rejected")
	_expect(not removed.configure({
		"mode": "duel",
		"difficulty": "ace",
	}), "removed duel mode should be rejected")
	var coop := Simulation.new()
	_expect(coop.configure({
		"mode": "coop",
		"difficulty": "easy",
	}), "co-op mode should configure")
	_expect(not coop.set_input(2, 0), "out-of-range seats should be rejected")
	_expect(not coop.set_input(0, 1 << 12), "unknown action bits should be rejected")
	var purchase := coop.submit_shop_purchase(0, 1, 1)
	_expect(not purchase.accepted and purchase.reason == "wrong_phase", "shop claims outside the shop should be rejected")


func _test_all_weapon_projectile_graphs() -> void:
	var catalog := Catalog.load_catalog()
	_expect(catalog.ok and catalog.weapons.size() == 9, "content should expose all nine base weapons")
	for weapon in catalog.weapons:
		var simulation := Simulation.new()
		_expect(simulation.configure({
			"mode": "solo",
			"difficulty": "normal",
			"starting_weapon": int(weapon.id),
			"record_replay": false,
		}), "weapon %d should be configurable" % int(weapon.id))
		simulation.set_input(0, Simulation.ACTION_FIRE)
		var snapshot := simulation.step()
		var expected_count := int(weapon.projectiles.size())
		if int(weapon.id) == 7:
			_expect(
				snapshot.events.any(func(event: Dictionary) -> bool: return event.type == "weapon_fired"),
				"the persistent Laser beam should emit a weapon-fired event"
			)
		_expect(
			snapshot.projectiles.size() == expected_count,
			"weapon %d should instantiate its complete projectile graph" % int(weapon.id)
		)
		_expect(
			int(snapshot.profile_stats[0].projectile_objects_fired) == expected_count,
			"weapon %d should count every allocated projectile object" % int(weapon.id)
		)
		var fire_events: Array = snapshot.events.filter(
			func(event: Dictionary) -> bool: return String(event.type) == "weapon_fired"
		)
		_expect(fire_events.size() == 1, "every weapon volley should emit one presentation event")
		if fire_events.size() == 1:
			var fire_event: Dictionary = fire_events[0]
			_expect(int(fire_event.event_id) > 0, "presentation events should have stable positive IDs")
			_expect(int(fire_event.tick) == int(snapshot.tick), "presentation events should carry the authoritative tick")
			_expect(int(fire_event.weapon_id) == int(weapon.id), "weapon events should identify the fired weapon")
			_expect(typeof(fire_event.x_fp) == TYPE_INT, "presentation event X positions should remain fixed-point integers")
			_expect(typeof(fire_event.y_fp) == TYPE_INT, "presentation event Y positions should remain fixed-point integers")


func _test_accuracy_profile_and_shop_contract() -> void:
	var accuracy := Simulation.new()
	_expect(accuracy.configure({
		"mode": "solo",
		"difficulty": "normal",
		"collision_mode": "simple",
		"record_replay": false,
		"seats": [{"best_hit_percent_above_level_25": 69}],
	}), "accuracy simulation should configure")
	_expect(
		int(accuracy.get_snapshot().profile_stats[0].best_hit_percent_above_level_25) == 69,
		"simulation profile stats should hydrate the stored accuracy best"
	)
	accuracy.set_input(0, Simulation.ACTION_FIRE)
	var snapshot := accuracy.step()
	_expect(
		int(snapshot.profile_stats[0].projectile_objects_fired) == 1,
		"public fire input should count the allocated projectile object"
	)
	var projectile: Dictionary = accuracy._projectiles[0]
	accuracy._enemies = [{
		"id": 8801,
		"authored_lvd": false,
		"authored_state": "hold",
		"behavior_state_id": 1,
		"x_fp": int(projectile.x_fp),
		"y_fp": int(projectile.y_fp),
		"width": int(projectile.width),
		"height": int(projectile.height),
		"health_fp": Simulation.FP_ONE,
		"max_health_fp": Simulation.FP_ONE,
		"score": 0,
		"cash": 0,
		"sprite": "alien001",
		"dead": false,
	}]
	accuracy.set_input(0, 0)
	snapshot = accuracy.step()
	_expect(
		snapshot.events.any(func(event: Dictionary) -> bool: return String(event.get("type", "")) == "enemy_hit"),
		"the deterministic public projectile should collide with the test enemy"
	)
	_expect(
		int(snapshot.profile_stats[0].successful_hits) == 1,
		"an actual public enemy collision should count one successful hit"
	)

	var solo_stats: Dictionary = accuracy._profile_stats_by_seat[0]
	solo_stats.projectile_objects_fired = 10
	solo_stats.successful_hits = 7
	solo_stats.best_hit_percent_above_level_25 = 69
	accuracy._commit_accuracy_sample_for_level_entry(25)
	_expect(
		int(solo_stats.best_hit_percent_above_level_25) == 69,
		"entering level twenty-five must not commit an accuracy sample"
	)
	accuracy._end_level_id = 25
	accuracy._complete_campaign()
	_expect(
		int(accuracy.get_snapshot().result.profile_stats[0].best_hit_percent_above_level_25) == 69,
		"ending the campaign at level twenty-five must not fabricate a sample"
	)
	accuracy._commit_accuracy_sample_for_level_entry(26)
	_expect(
		int(solo_stats.best_hit_percent_above_level_25) == 70,
		"entering a level above twenty-five should commit floor(100 * hits / shots)"
	)
	solo_stats.successful_hits = 5
	accuracy._commit_accuracy_sample_for_level_entry(27)
	_expect(
		int(solo_stats.best_hit_percent_above_level_25) == 70,
		"later lower accuracy samples must not reduce the stored best"
	)

	var shop_thresholds := {18: 70, 19: 80, 20: 90}
	for item_id in shop_thresholds:
		var item: Dictionary = accuracy._shop_by_id[item_id]
		_expect(
			String(item.unlock.kind) == "hit_percent_above_level_25"
			and int(item.unlock.threshold) == int(shop_thresholds[item_id]),
			"shop item %d should retain its inclusive accuracy threshold" % item_id
		)
	accuracy._phase = Simulation.PHASE_SHOP
	accuracy._turn_seat = 0
	accuracy._shared.money = 5000
	solo_stats.best_hit_percent_above_level_25 = 69
	var locked := accuracy.submit_shop_purchase(0, 18, 701)
	_expect(
		not bool(locked.accepted) and String(locked.reason) == "locked_item",
		"Rocket Pack should remain locked one point below its threshold"
	)
	solo_stats.best_hit_percent_above_level_25 = 70
	var visible_ids: Array = accuracy.get_snapshot().shop.items.map(
		func(item: Dictionary) -> int: return int(item.id)
	)
	_expect(
		visible_ids.has(18) and not visible_ids.has(19) and not visible_ids.has(20),
		"the inclusive 70 threshold should reveal only Rocket Pack"
	)
	var unlocked := accuracy.submit_shop_purchase(0, 18, 702)
	_expect(bool(unlocked.accepted), "Rocket Pack should be purchasable at exactly 70 percent")

	var floor_division := Simulation.new()
	_expect(floor_division.configure({
		"mode": "solo",
		"difficulty": "normal",
		"record_replay": false,
	}), "solo accuracy simulation should configure")
	floor_division._profile_stats_by_seat[0].projectile_objects_fired = 3
	floor_division._profile_stats_by_seat[0].successful_hits = 2
	floor_division._commit_accuracy_sample_for_level_entry(26)
	_expect(
		int(floor_division._profile_stats_by_seat[0].best_hit_percent_above_level_25) == 66,
		"solo should commit only the active seat using integer floor division"
	)
	floor_division._profile_stats_by_seat[0].projectile_objects_fired = 0
	floor_division._profile_stats_by_seat[0].successful_hits = 9
	floor_division._commit_accuracy_sample_for_level_entry(27)
	_expect(
		int(floor_division._profile_stats_by_seat[0].best_hit_percent_above_level_25) == 66,
		"a zero-shot sample should leave the existing best unchanged"
	)

	var coop := Simulation.new()
	_expect(coop.configure({
		"mode": "coop",
		"difficulty": "normal",
		"record_replay": false,
	}), "co-op accuracy simulation should configure")
	coop.set_input(0, Simulation.ACTION_FIRE)
	coop.set_input(1, Simulation.ACTION_FIRE)
	var coop_snapshot := coop.step()
	_expect(
		int(coop_snapshot.profile_stats[0].projectile_objects_fired) == 1
		and int(coop_snapshot.profile_stats[1].projectile_objects_fired) == 1,
		"co-op public fire input should count projectile objects independently per seat"
	)
	coop._profile_stats_by_seat[0].projectile_objects_fired = 8
	coop._profile_stats_by_seat[0].successful_hits = 6
	coop._profile_stats_by_seat[1].projectile_objects_fired = 5
	coop._profile_stats_by_seat[1].successful_hits = 4
	coop._commit_accuracy_sample_for_level_entry(26)
	_expect(
		int(coop._profile_stats_by_seat[0].best_hit_percent_above_level_25) == 75
		and int(coop._profile_stats_by_seat[1].best_hit_percent_above_level_25) == 80,
		"co-op level entry should commit each simultaneous owner's cumulative accuracy"
	)


func _test_authoritative_presentation_event_contract() -> void:
	var simulation := Simulation.new()
	_expect(simulation.configure({
		"mode": "solo",
		"difficulty": "normal",
		"collision_mode": "simple",
		"record_replay": false,
	}), "presentation event simulation should configure")
	var enemy := {
		"id": 41,
		"sprite": "alien001",
		"x_fp": 320 * Simulation.FP_ONE,
		"y_fp": 120 * Simulation.FP_ONE,
		"projectile_speed_fp": 2 * Simulation.FP_ONE,
	}
	simulation._common_projectile_slots[0].animation_frame = 0
	simulation._common_projectile_slots[1].animation_frame = 0
	simulation._fire_enemy_projectile(enemy)
	simulation._fire_enemy_projectile(enemy)
	var snapshot := simulation.get_snapshot()
	_expect(snapshot.projectiles.size() == 2, "enemy fire should publish its authoritative projectiles")
	_expect(snapshot.projectiles[0].animation_frame == 0, "alien shots should publish their server-owned initial atlas row")
	_expect(
		snapshot.projectiles[0].x_fp == 333 * Simulation.FP_ONE
		and snapshot.projectiles[0].y_fp == 136 * Simulation.FP_ONE
		and snapshot.projectiles[0].velocity_x_fp == 0,
		"alien-shot snapshots should expose retail center conversion and vertical-only movement"
	)
	_expect(
		snapshot.projectiles[0].pool_slot == 0
		and snapshot.projectiles[1].pool_slot == 1,
		"alien-shot snapshots should expose stable common-pool slots"
	)
	_expect(
		String(snapshot.projectiles[0].projectile_kind) == "enemy_projectile"
		and String(snapshot.projectiles[0].sprite_sheet_id) == "alien001"
		and snapshot.projectiles[0].source_rect == [480, 0, 32, 32],
		"snapshot v9 should publish canonical enemy projectile presentation metadata"
	)
	_expect(snapshot.events.size() == 2, "enemy fire should emit presentation events")
	if snapshot.events.size() == 2:
		var first: Dictionary = snapshot.events[0]
		var second: Dictionary = snapshot.events[1]
		_expect(first.type == "enemy_fired" and first.kind == first.type, "events should publish a compatible type and kind")
		_expect(int(second.event_id) == int(first.event_id) + 1, "event IDs should be monotonic within a match")
		_expect(first.projectile_id == snapshot.projectiles[0].id, "enemy-fire events should identify their projectile")
		_expect(first.enemy_sheet == "alien001", "enemy-fire events should retain the source art sheet")
		_expect(typeof(first.x_fp) == TYPE_INT and typeof(first.y_fp) == TYPE_INT, "enemy-fire positions should stay deterministic integers")
	simulation._update_projectiles()
	_expect(simulation.get_snapshot().projectiles[0].animation_frame == 0, "alien shot atlas phase should survive exact countdown equality")
	simulation._update_projectiles()
	_expect(simulation.get_snapshot().projectiles[0].animation_frame == 1, "alien shot atlas phase should advance authoritatively after underflow")


func _test_pickup_presentation_phase() -> void:
	var simulation := Simulation.new()
	_expect(simulation.configure({
		"mode": "solo",
		"difficulty": "normal",
		"collision_mode": "simple",
		"record_replay": false,
	}), "pickup presentation simulation should configure")
	simulation._pickups = [{
		"id": 91,
		"kind": "money",
		"variant": 2,
		"animation_frame": 6,
		"animation_period_fp": 3 * Simulation.FP_ONE,
		"animation_countdown_fp": Simulation.FP_ONE,
		"x_fp": 100 * Simulation.FP_ONE,
		"y_fp": 100 * Simulation.FP_ONE,
		"velocity_y_fp": 0,
		"expired": false,
	}]
	simulation._update_pickups()
	var pickup: Dictionary = simulation.get_snapshot().pickups[0]
	_expect(
		pickup.animation_frame == 6,
		"pickup animation should remain on its frame at exact countdown equality"
	)
	simulation._update_pickups()
	pickup = simulation.get_snapshot().pickups[0]
	_expect(
		pickup.animation_frame == 7,
		"pickup frames should advance once the retail countdown becomes negative"
	)
	_expect(pickup.variant == 2, "pickup snapshots should retain their recovered atlas-row variant")


func _test_weapon_runtime_contracts() -> void:
	var manual := Simulation.new()
	_expect(manual.configure({
		"mode": "solo",
		"difficulty": "normal",
		"collision_mode": "simple",
		"record_replay": false,
	}), "manual fire-latch simulation should configure")
	manual.set_input(0, Simulation.ACTION_FIRE)
	var snapshot := manual.step()
	_expect(snapshot.projectiles.size() == 1, "manual press edge should fire immediately")
	_expect(
		snapshot.projectiles[0].y_fp
		== 555 * Simulation.FP_ONE,
		"projectile centers should convert from the retail fighter sprite origin before birth-frame movement"
	)
	snapshot = manual.step()
	_expect(snapshot.projectiles.size() == 1, "held manual fire should stay disarmed")
	manual.set_input(0, 0)
	manual.step()
	manual.set_input(0, Simulation.ACTION_FIRE)
	snapshot = manual.step()
	_expect(snapshot.projectiles.size() == 2, "release should rearm the manual fire latch")

	var automatic := Simulation.new()
	_expect(automatic.configure({
		"mode": "solo",
		"difficulty": "normal",
		"collision_mode": "simple",
		"record_replay": false,
	}), "autofire deadline simulation should configure")
	automatic._shared.auto_fire = true
	automatic.set_input(0, Simulation.ACTION_FIRE)
	snapshot = automatic.step()
	_expect(
		snapshot.projectiles.size() == 2,
		"an armed edge and expired autofire deadline may produce two retail volleys"
	)
	for tick in range(6):
		snapshot = automatic.step()
	_expect(
		snapshot.projectiles.size() == 2,
		"autofire should not fire when integer milliseconds equal its strict deadline"
	)
	snapshot = automatic.step()
	_expect(snapshot.projectiles.size() == 3, "autofire should repeat after the strict 100 ms deadline")

	var capacity := Simulation.new()
	_expect(capacity.configure({
		"mode": "solo",
		"difficulty": "normal",
		"collision_mode": "simple",
		"starting_weapon": 3,
		"record_replay": false,
	}), "projectile capacity simulation should configure")
	capacity._shared.bullet_capacity = 1
	capacity.set_input(0, Simulation.ACTION_FIRE)
	snapshot = capacity.step()
	_expect(
		snapshot.projectiles.size() == 4,
		"pre-volley capacity gate should allow a recursive volley to overshoot the cap"
	)

	var war_i := Simulation.new()
	_expect(war_i.configure({
		"mode": "solo",
		"difficulty": "normal",
		"collision_mode": "simple",
		"starting_weapon": 8,
		"seed": 91,
		"record_replay": false,
	}), "War.I.Plasma spread simulation should configure")
	war_i.set_input(0, Simulation.ACTION_FIRE)
	war_i.step()
	_expect(war_i._projectiles.size() == 3, "War.I.Plasma should preserve its recursive three-object graph")
	for projectile in war_i._projectiles:
		var spread := 5 if int(projectile.prototype_id) == 19 else 3
		_expect(
			int(projectile.velocity_x_fp) >= -spread * Simulation.FP_ONE / 2
			and int(projectile.velocity_x_fp) < spread * Simulation.FP_ONE / 2,
			"War.I.Plasma special secondary should randomize horizontal velocity"
		)

	var fireballs := Simulation.new()
	_expect(fireballs.configure({
		"mode": "solo",
		"difficulty": "normal",
		"collision_mode": "simple",
		"starting_weapon": 6,
		"seed": 92,
		"record_replay": false,
	}), "fireball spread simulation should configure")
	fireballs.set_input(0, Simulation.ACTION_FIRE)
	fireballs.step()
	_expect(fireballs._projectiles.size() == 4, "Fireballs should preserve its recursive four-object graph")
	for projectile in fireballs._projectiles:
		var spread := 30 if int(projectile.prototype_id) in [25, 26] else 20
		_expect(
			int(projectile.x_fp) >= 400 * Simulation.FP_ONE - spread * Simulation.FP_ONE / 2
			and int(projectile.x_fp) < 400 * Simulation.FP_ONE + spread * Simulation.FP_ONE / 2,
			"Fireballs special secondary should randomize its one-time spawn X"
		)
		_expect(int(projectile.velocity_x_fp) == 0, "Fireballs one-time spread should leave horizontal velocity zero")

	var upgrades := Simulation.new()
	_expect(upgrades.configure({
		"mode": "solo",
		"difficulty": "normal",
		"collision_mode": "simple",
		"record_replay": false,
	}), "retail upgrade-cap simulation should configure")
	upgrades._shared.bullet_capacity = Simulation.MAX_PROJECTILE_CAPACITY
	_expect(
		not upgrades._can_apply_shop_effect({"effect": "bullet_capacity_up"}),
		"projectile capacity should cap at fifty"
	)
	upgrades._shared.armour_fp = Simulation.MAX_ARMOUR_CHARGES * Simulation.FP_ONE
	_expect(
		not upgrades._can_apply_shop_effect({"effect": "armor_up"}),
		"armour should cap at two charges"
	)
	upgrades._shared.armour_fp = Simulation.FP_ONE
	upgrades._damage_player(upgrades._players[0], Simulation.FP_ONE)
	_expect(
		upgrades._players[0].alive
		and upgrades._players[0].projectile_suppression_ticks
		== Simulation.ARMOUR_PROJECTILE_SUPPRESSION_TICKS,
		"armour should absorb one hit and start four seconds of projectile suppression"
	)
	upgrades._shared.bullet_capacity = 6
	upgrades._damage_player(upgrades._players[0], Simulation.FP_ONE)
	upgrades._players[0].respawn_ticks = 1
	upgrades._update_respawns()
	_expect(
		upgrades._shared.bullet_capacity == 5,
		"death should remove one projectile-capacity upgrade above the retail base"
	)


func _test_laser_runtime_contract() -> void:
	var laser := Simulation.new()
	_expect(laser.configure({
		"mode": "solo",
		"difficulty": "normal",
		"collision_mode": "simple",
		"starting_weapon": 7,
		"record_replay": false,
	}), "Laser runtime simulation should configure")
	laser.set_input(0, Simulation.ACTION_FIRE)
	var snapshot := laser.step()
	_expect(snapshot.projectiles.size() == 1, "Laser frame 22 should survive its spawn tick")
	_expect(
		snapshot.projectiles[0].prototype_id == 22
		and snapshot.projectiles[0].x_fp == 400 * Simulation.FP_ONE
		and snapshot.projectiles[0].y_fp == 514 * Simulation.FP_ONE,
		"Laser should convert the retail latched column and visual-top geometry"
	)
	_expect(
		String(snapshot.projectiles[0].projectile_kind) == "player_weapon"
		and String(snapshot.projectiles[0].sprite_sheet_id) == "weapons_big"
		and (snapshot.projectiles[0].source_rect as Array).size() == 4
		and int(snapshot.projectiles[0].source_rect[2]) > 0
		and int(snapshot.projectiles[0].source_rect[3]) > 0,
		"snapshot v9 should publish canonical player projectile presentation metadata"
	)
	var beam: Dictionary = laser._projectiles[0]
	_expect(
		beam.collision_x_fp == 400 * Simulation.FP_ONE
		and beam.collision_y_fp == 275 * Simulation.FP_ONE
		and beam.collision_width == 16
		and beam.collision_height == 550,
		"Laser collision should span from screen top to the live retail fighter Y"
	)
	laser.set_input(0, Simulation.ACTION_RIGHT)
	for expected_frame in [23, 24, 50]:
		snapshot = laser.step()
		_expect(
			snapshot.projectiles.size() == 1
			and snapshot.projectiles[0].prototype_id == expected_frame,
			"Laser should preserve its four proven live atlas frames"
		)
		_expect(
			snapshot.projectiles[0].x_fp == 400 * Simulation.FP_ONE,
			"Laser X should remain latched while the fighter moves"
		)
	snapshot = laser.step()
	_expect(snapshot.projectiles.is_empty(), "Laser should deactivate after frame 50 advances to -1")

	var damage := Simulation.new()
	_expect(damage.configure({
		"mode": "solo",
		"difficulty": "normal",
		"collision_mode": "simple",
		"starting_weapon": 7,
		"record_replay": false,
	}), "Laser damage simulation should configure")
	damage.set_input(0, Simulation.ACTION_FIRE)
	damage.step()
	damage._enemies.clear()
	var damage_beam: Dictionary = damage._projectiles[0]
	damage_beam.damage_fp = 10 * Simulation.FP_ONE
	for enemy_index in range(3):
		damage._enemies.append({
			"id": 1000 + enemy_index,
			"x_fp": 400 * Simulation.FP_ONE,
			"y_fp": 100 * Simulation.FP_ONE,
			"width": 32,
			"height": 32,
			"health_fp": 20 * Simulation.FP_ONE,
			"max_health_fp": 20 * Simulation.FP_ONE,
			"score": 0,
			"cash": 0,
			"dead": false,
		})
	damage._resolve_projectile_collisions()
	_expect(
		damage._enemies[0].health_fp == 10 * Simulation.FP_ONE
		and damage._enemies[1].health_fp == 15 * Simulation.FP_ONE
		and damage._enemies[2].health_fp == 35 * Simulation.FP_ONE / 2,
		"Laser should apply 10, 5, and 2.5 damage across ordinary enemies in array order"
	)
	_expect(
		not damage_beam.expired
		and damage_beam.damage_fp == 5 * Simulation.FP_ONE / 4,
		"Laser should remain live and halve stored damage after every ordinary collision"
	)


func _test_first_five_route() -> void:
	var simulation := Simulation.new()
	_expect(simulation.configure({
		"mode": "solo",
		"difficulty": "easy",
		"collision_mode": "simple",
		"seed": 5150,
		"starting_lives": 99,
		"starting_money": 5000,
		"end_level": 5,
		"record_replay": false,
	}), "first-five route simulation should configure")
	simulation._warp_malfunction_interval = 0
	var snapshot := simulation.get_snapshot()
	var bought_weapon := false
	for tick in range(30000):
		if snapshot.phase == Simulation.PHASE_LEVEL:
			var action_mask := 0
			var target: Dictionary = {}
			# The shared effect pool is the only hazard that homes at the fighter
			# and destroys it on contact. One hit clears an object, so the route
			# driver answers the closest one before it picks an authored target;
			# without this it dies faster than it can clear level one.
			var closest_effect_y_fp := -(1 << 60)
			for effect_value in snapshot.get("effect_objects", []):
				var effect: Dictionary = effect_value
				var effect_y_fp := int(effect.get("y_fp", 0))
				if (
					effect_y_fp >= int(snapshot.players[0].y_fp)
					or effect_y_fp <= closest_effect_y_fp
				):
					continue
				closest_effect_y_fp = effect_y_fp
				target = effect
			if target.is_empty():
				for enemy_value in snapshot.enemies:
					var enemy: Dictionary = enemy_value
					if String(enemy.get("authored_state", "")) != "delayed":
						target = enemy
						break
			if not target.is_empty():
				var target_x := int(target.x_fp)
				var player_x := int(snapshot.players[0].x_fp)
				if player_x < target_x - Simulation.FP_ONE:
					action_mask |= Simulation.ACTION_RIGHT
				elif player_x > target_x + Simulation.FP_ONE:
					action_mask |= Simulation.ACTION_LEFT
			if tick % 8 == 0:
				action_mask |= Simulation.ACTION_FIRE
			simulation.set_input(0, action_mask)
		elif snapshot.phase == Simulation.PHASE_SHOP:
			simulation.set_input(0, 0)
			if (
				not bought_weapon
				and int(snapshot.tick) > int(snapshot.shop.input_guard_until_tick)
			):
				# Which weapon the route reaches the first shop holding depends on
				# which bonuses dropped, and the shop refuses a sidegrade, so the
				# assertion is that the shop accepts an affordable *upgrade*
				# rather than that one hardcoded item is always buyable.
				var purchase := {"accepted": false, "reason": "no shop weapon offered"}
				var offered: Array = snapshot.shop.get("items", [])
				for offer_index in range(offered.size() - 1, -1, -1):
					var offer: Dictionary = offered[offer_index]
					if String(offer.get("category", "")) != "weapon":
						continue
					var attempt := simulation.submit_shop_purchase(
						0,
						int(offer.get("id", 0)),
						9001 + offer_index
					)
					if bool(attempt.get("accepted", false)):
						purchase = attempt
						break
					purchase = attempt
				_expect(
					purchase.accepted,
					"the authoritative first shop should accept an affordable weapon: %s"
					% str(purchase)
				)
				bought_weapon = true
			if int(snapshot.tick) > int(snapshot.shop.input_guard_until_tick):
				simulation.set_shop_ready(0, true)
		elif snapshot.phase == Simulation.PHASE_GET_READY:
			simulation.set_input(0, 0)
		elif snapshot.phase in [
			Simulation.PHASE_WARP,
			Simulation.PHASE_WARP_MALFUNCTION,
			# A hurry-up wave can push a level long enough to change which
			# bonus tiles drop, so the route has to idle through those too.
			Simulation.PHASE_BONUS_MODE,
			Simulation.PHASE_RANK_PROMOTION,
		]:
			simulation.set_input(0, 0)
		else:
			break
		snapshot = simulation.step()
	_expect(bought_weapon, "the first-five route should visit the shop after level four")
	_expect(snapshot.phase == Simulation.PHASE_COMPLETE, "an input-driven run should complete level five")
	_expect(snapshot.result.completed and snapshot.result.level_reached == 5, "completion results should identify level five")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

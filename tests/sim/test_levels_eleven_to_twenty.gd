extends SceneTree

const Simulation := preload("res://src/sim/game_simulation.gd")
const Catalog := preload("res://src/sim/content_catalog.gd")

const LEVEL_IDS := [11, 12, 13, 14, 15, 16, 17, 18, 19, 20]
const LVD_SHA256 := [
	"2c8dc69d4f373f3d0b4796c41045e645be7a5aa0e574d7db20f02744efddacfe",
	"8888909c4f7a8f4bcd024d035cfbdef3ee590d075c723f5c230773049aff3a86",
	"d8ba943e3acfe6fa21ee4177d383cbf9114de8f7b97c4de95137873afadd62b8",
	"1a654e1a3ce7caefde5517ab1b661e2387977d5abd00ab36548dfb57659744a1",
	"1debac1fbaa5e4b2c98e2aaf6519f249ca8dd2a744a5dee24ff5e7ac5da66991",
	"21fad6d67bed291923c03fe177370e0f9f2b5777258c07ce0896f30a4b80ed12",
	"b5f4e31dbce7ef30b1615768d35eb90b22b0ae39ce439ac108af851fc5f723a5",
	"f91d59b3f2464c5709c3056219208ab0735f045faffa00c2670d062ed4a7f1cf",
	"30c5e49b1486de3dd50f53a58fc0b30df0c141057e3c137fa4b1178c955079e2",
	"33dc4133c6caf4575a46c4ee56659f7eff884aa498d1ada07f81874a17e2fc62",
]
const MODES := [1, 2, 1, 1, 1, 3, 1, 1, 1, 2]
const GROUPS := [4, 25, 1, 2, 4, 2, 4, 6, 4, 6]
const ENEMIES := [32, 25, 24, 28, 32, 30, 32, 34, 28, 30]
const RESOLVED_ENTITIES := [33, 25, 24, 28, 34, 30, 32, 34, 30, 30]
const PATH_POINTS := [44, 75, 16, 32, 60, 30, 56, 84, 68, 18]
const HEALTH := [2, 2, 2, 2, 2, 2, 3, 3, 3, 3]
const KILL_SCORES := [75, 150, 50, 50, 50, 100, 150, 175, 175, 200]
const ENEMY_SHEETS := [
	"alien_3", "alien_3", "alien000", "alien000", "alien000",
	"alien000", "alien_lilla", "alien_lilla", "alien_lilla", "alien_lilla",
]

var _failures: Array[String] = []


func _initialize() -> void:
	_test_catalog_and_runtime_matrix()
	_test_fixed_table_supplemental_behavior()
	_test_level_sixteen_mode_three_contract()
	_test_level_twenty_mode_two_cohorts()
	_test_projectile_broad_phase_contract()
	_test_terminal_level_twenty_shop_routes()
	_test_public_input_progression_boundaries()
	_test_deterministic_level_one_to_twenty_campaign()
	if _failures.is_empty():
		print("LEVELS 11-20 TESTS PASSED")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _test_catalog_and_runtime_matrix() -> void:
	var catalog := Catalog.load_catalog()
	_expect(bool(catalog.get("ok", false)), "the one-hundred-level catalog should load")
	if not bool(catalog.get("ok", false)):
		return
	var raw_document: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://content/levels.json")
	)
	var raw_levels: Array = raw_document.get("levels", [])
	var shop_levels: Array[int] = []
	for level_value in catalog.levels:
		var candidate: Dictionary = level_value
		if bool(candidate.shop_after):
			shop_levels.append(int(candidate.id))
	_expect(
		shop_levels == range(4, 101, 4),
		"authored ordinary shop flags should recur every fourth level through 100"
	)
	for index in range(LEVEL_IDS.size()):
		var level_id: int = int(LEVEL_IDS[index])
		var level: Dictionary = catalog.levels[level_id - 1]
		var authored: Dictionary = level.authored_lvd
		var enemy_count := 0
		var path_count := 0
		for group_value in authored.groups:
			var group: Dictionary = group_value
			enemy_count += group.enemies.size()
			path_count += group.path_points.size()
			for enemy_value in group.enemies:
				var enemy: Dictionary = enemy_value
				_expect(
					int(enemy.base_health) == HEALTH[index],
					"level %d should retain its authored health" % level_id
				)
		var resolved := enemy_count
		for record_value in authored.supplemental_spawn_records_raw_words.slice(0, 4):
			var record: Array = record_value
			if int(record[1]) == 1:
				resolved += maxi(0, int(record[0]))
		_expect(str(raw_levels[level_id - 1].raw_lvd_sha256) == LVD_SHA256[index], "level %d should retain its pinned LVD hash" % level_id)
		_expect(int(authored.level_mode_id) == MODES[index], "level %d should retain its authored mode" % level_id)
		_expect(authored.groups.size() == GROUPS[index], "level %d should retain its group count" % level_id)
		_expect(enemy_count == ENEMIES[index], "level %d should retain its enemy count" % level_id)
		_expect(resolved == RESOLVED_ENTITIES[index], "level %d should retain its resolved entity total" % level_id)
		_expect(path_count == PATH_POINTS[index], "level %d should retain its path-point count" % level_id)
		_expect(int(level.ordinary_kill_score) == KILL_SCORES[index], "level %d should retain its kill score" % level_id)
		_expect(str(level.enemy_sprite) == ENEMY_SHEETS[index], "level %d should bind its retail enemy sheet" % level_id)
		_expect(authored.fixed_table_records_raw_words.size() == 50, "level %d should expose all fifty fixed-table records" % level_id)

		var simulation := Simulation.new()
		_expect(simulation.configure({
			"mode": "solo",
			"difficulty": "normal",
			"collision_mode": "simple",
			"seed": 1100 + index,
			"start_level": level_id,
			"end_level": 20,
			"record_replay": false,
		}), "level %d runtime should configure: %s" % [level_id, simulation.get_last_error()])
		if not simulation._configured:
			continue
		var snapshot := simulation.step()
		_expect(snapshot.enemies.size() == RESOLVED_ENTITIES[index], "level %d should spawn every resolved entity" % level_id)
		for enemy_value in snapshot.enemies:
			var enemy: Dictionary = enemy_value
			_expect(
				str(enemy.sprite) == ENEMY_SHEETS[index],
				"level %d should spawn only its authored enemy sheet" % level_id
			)


func _test_fixed_table_supplemental_behavior() -> void:
	var cases := [
		{"level": 15, "count": 2, "maximum": 6, "metadata": 0, "health": 20},
		{"level": 19, "count": 2, "maximum": 4, "metadata": 1, "health": 50},
	]
	for case_value in cases:
		var case: Dictionary = case_value
		var simulation: GameSimulation = _new_level(int(case.level), int(case.level), "solo", 1500 + int(case.level))
		if simulation == null:
			continue
		var supplemental: Array = []
		for enemy_value in simulation._enemies:
			var candidate: Dictionary = enemy_value
			if str(candidate.get("authored_state", "")) == "supplemental_large":
				supplemental.append(candidate)
		_expect(supplemental.size() == int(case.count), "level %d should spawn its supplemental count" % int(case.level))
		for enemy_value in supplemental:
			var enemy: Dictionary = enemy_value
			_expect(
				int(enemy.animation_max_phase) == int(case.maximum)
				and int(enemy.animation_metadata) == int(case.metadata),
				"level %d supplemental animation should come from fixed-table words 0-1" % int(case.level)
			)
			_expect(
				int(enemy.base_health_divisor_numerator) == int(case.health),
				"level %d supplemental health divisor should come from supplemental word 2" % int(case.level)
			)


func _test_level_sixteen_mode_three_contract() -> void:
	var simulation: GameSimulation = _new_level(16, 20, "solo", 1616, [{
		"mode_three_perfect_reward_index": 1,
	}])
	if simulation == null:
		return
	var initial: Dictionary = simulation.get_snapshot()
	_expect(initial.mode_three_bonus == initial.level_eight_bonus, "canonical and legacy mode-three snapshots should remain synchronized")
	_expect(bool(initial.mode_three_bonus.active), "level 16 should activate the recurring mode-three controller")
	_expect(int(initial.mode_three_bonus.players[0].total_targets) == 30, "level 16 should own thirty targets")
	_expect(simulation._enemies.size() == 30, "level 16 should spawn thirty authored targets")
	_expect(
		simulation._enemies.all(func(enemy: Dictionary) -> bool: return int(enemy.score) == 100),
		"level 16 targets should use the per-level 100-point mode-three score"
	)
	var progression: Dictionary = simulation._progression_for_seat(0)
	progression.money = 50
	var before_rng: Dictionary = simulation._rng.snapshot()
	for enemy_value in simulation._enemies.duplicate():
		simulation._kill_enemy(enemy_value as Dictionary, 0)
	_expect(simulation._rng.snapshot() == before_rng, "level-16 deaths should consume no bonus-drop RNG")
	_expect(simulation._pickups.is_empty(), "level 16 should suppress ordinary bonus drops")
	simulation._level_resolution_tick = simulation._tick
	simulation.step()
	var reveal_steps := 0
	while (
		int(simulation.get_snapshot().mode_three_bonus.players[0].displayed_hits) < 30
		and reveal_steps < 140
	):
		simulation.step()
		reveal_steps += 1
	_expect(reveal_steps == 120, "thirty level-16 hits should reveal over 120 controller updates")
	var gate_ms := int(simulation.get_snapshot().mode_three_bonus.reveal_deadline_ms)
	while simulation._simulation_milliseconds() < gate_ms:
		simulation.step()
	_expect(
		not bool(simulation.get_snapshot().mode_three_bonus.players[0].perfect_awarded),
		"level-16 perfect should remain strict at reveal-deadline equality"
	)
	simulation.step()
	var perfect: Dictionary = simulation.get_snapshot()
	_expect(
		bool(perfect.mode_three_bonus.players[0].perfect_awarded)
		and int(perfect.mode_three_bonus.players[0].perfect_reward) == 25000,
		"a hydrated index-one chain should award 25,000 on the level-16 perfect"
	)
	_expect(
		int(perfect.profile_stats[0].mode_three_perfects) == 1
		and int(perfect.profile_stats[0].level_eight_perfects) == 0,
		"level 16 should increment the canonical counter without rewriting level-eight history"
	)
	_expect(
		int(perfect.profile_stats[0].mode_three_perfect_reward_index) == 2
		and int(perfect.profile_stats[0].level_eight_perfect_reward_index) == 2,
		"canonical and legacy persisted chain indices should remain synchronized"
	)
	var result_deadline_ms := int(perfect.mode_three_bonus.result_deadline_ms)
	while simulation._simulation_milliseconds() < result_deadline_ms:
		simulation.step()
	simulation.step()
	_expect(simulation.get_snapshot().phase == Simulation.PHASE_WARP, "level-16 results should enter ordinary Warp")
	simulation._finalize_warp()
	var shopped: Dictionary = simulation.get_snapshot()
	_expect(
		shopped.phase == Simulation.PHASE_SHOP
		and int(shopped.level_resolution.pending_level_id) == 17,
		"level 16 should route through its recurring shop before level 17"
	)


func _test_level_twenty_mode_two_cohorts() -> void:
	var simulation: GameSimulation = _new_level(20, 20, "solo", 2020)
	if simulation == null:
		return
	var groups: Dictionary = {}
	for enemy_value in simulation._enemies:
		var enemy: Dictionary = enemy_value
		var group_id := int(enemy.group_id)
		if not groups.has(group_id):
			groups[group_id] = []
		(groups[group_id] as Array).append(enemy)
	_expect(
		groups.values().all(func(group: Array) -> bool: return group.size() == 5),
		"level 20 should preserve six simultaneous five-enemy mode-two groups"
	)
	for group_value in groups.values():
		var group: Array = group_value
		var activation_delay := int((group[0] as Dictionary).activation_delay_ticks)
		for enemy_value in group:
			var group_enemy: Dictionary = enemy_value
			_expect(
				int(group_enemy.activation_delay_ticks) == activation_delay,
				"mode-two group members should share their activation delay"
			)
	var enemy: Dictionary = simulation._enemies[0]
	enemy.path_index = enemy.path_points.size() - 2
	simulation._advance_authored_path(enemy)
	_expect(
		str(enemy.authored_state) == "state_ten" and int(enemy.behavior_state_id) == 10,
		"level-20 opcode 6 should enter the existing authoritative kamikaze state"
	)


func _test_projectile_broad_phase_contract() -> void:
	var simulation: GameSimulation = _new_level(16, 20, "solo", 1660)
	if simulation == null:
		return
	var expected := {
		7: {
			"alien001": [0, 0, 5, 13],
			"alien_2": [0, 0, 3, 11],
			"alien_3": [0, 0, 5, 12],
			"alien000": [0, 0, 7, 13],
			"alien_lilla": [0, 0, 5, 9],
		},
		6: {
			"alien001": [0, 1, 11, 12],
			"alien_2": [2, 2, 9, 9],
			"alien_3": [0, 0, 31, 12],
			"alien000": [0, 0, 13, 16],
			"alien_lilla": [0, 0, 11, 11],
		},
	}
	for projectile_type in expected:
		for sheet_id in expected[projectile_type]:
			_expect(
				simulation._enemy_projectile_broad_metadata({
					"enemy_projectile_type": projectile_type,
					"enemy_sheet": sheet_id,
				}) == expected[projectile_type][sheet_id],
				"type-%d %s projectiles should use captured retail broad metadata" % [projectile_type, sheet_id]
			)


func _test_terminal_level_twenty_shop_routes() -> void:
	var solo: GameSimulation = _new_level(20, 20, "solo", 2001)
	if solo != null:
		var progression: Dictionary = solo._progression_for_seat(0)
		var starting_speed := int(progression.speed_fp)
		progression.money = 200
		progression.rank_markers = 0x3f
		_finalize_terminal_warp(solo)
		var shop: Dictionary = solo.get_snapshot()
		_expect(
			shop.phase == Simulation.PHASE_SHOP
			and int(shop.level_resolution.pending_level_id) == 0,
			"an eligible level-20 pilot should enter a terminal-marked shop"
		)
		solo._shop_warp_until_tick = 0
		var purchase: Dictionary = solo.submit_shop_purchase(0, 1, 2001)
		_expect(bool(purchase.get("accepted", false)), "terminal shops should accept ordinary purchases")
		_expect(solo.set_shop_ready(0, true), "the terminal solo shop should accept readiness")
		_expect(solo.get_snapshot().phase == Simulation.PHASE_RANK_PROMOTION, "terminal full-rank cashout should retain promotion")
		solo._finish_rank_promotion()
		var completed: Dictionary = solo.get_snapshot()
		_expect(
			completed.phase == Simulation.PHASE_COMPLETE
			and int(completed.level_id) == 20
			and int(completed.level_resolution.pending_level_id) == 0,
			"terminal promotion should complete at level 20 without requesting level 21"
		)
		_expect(
			int(completed.result.seat_progression[0].rank) == 1
			and int(completed.result.seat_progression[0].speed_fp) > starting_speed,
			"terminal results should capture the shop purchase and promotion"
		)

	var ineligible: GameSimulation = _new_level(20, 20, "solo", 2002)
	if ineligible != null:
		ineligible._progression_for_seat(0).money = 0
		_finalize_terminal_warp(ineligible)
		_expect(
			ineligible.get_snapshot().phase == Simulation.PHASE_COMPLETE,
			"an ineligible terminal pilot should complete directly after Warp"
		)


func _test_public_input_progression_boundaries() -> void:
	var cases := [
		{"start": 11, "end": 12, "seed": 1112},
		{"start": 15, "end": 16, "seed": 1516},
		{"start": 19, "end": 20, "seed": 1920},
	]
	for case_value in cases:
		var case: Dictionary = case_value
		var result := _run_public_input_slice(
			int(case.start),
			int(case.end),
			int(case.seed)
		)
		_expect(
			bool(result.get("complete", false)),
			"public input should complete levels %d-%d: %s"
			% [int(case.start), int(case.end), str(result.get("error", "timeout"))]
		)
		_expect(
			result.get("visited", []) == range(int(case.start), int(case.end) + 1),
			"public input should visit levels %d-%d in order"
			% [int(case.start), int(case.end)]
		)
		_expect(
			int(result.get("projectile_ticks", 0)) > 0,
			"public input should resolve levels %d-%d through live projectile play"
			% [int(case.start), int(case.end)]
		)


func _run_public_input_slice(
	start_level: int,
	end_level: int,
	seed_value: int
) -> Dictionary:
	var simulation := Simulation.new()
	if not simulation.configure({
		"mode": "solo",
		"difficulty": "easy",
		"collision_mode": "simple",
		"seed": seed_value,
		"start_level": start_level,
		"end_level": end_level,
		"starting_weapon": 8,
		"starting_lives": 99,
		"starting_money": 100,
		"record_replay": false,
	}):
		return {"complete": false, "error": simulation.get_last_error()}
	var visited: Array[int] = []
	var projectile_ticks := 0
	for update_index in range(90000):
		var snapshot: Dictionary = simulation.get_snapshot()
		var phase := String(snapshot.get("phase", ""))
		if phase == Simulation.PHASE_COMPLETE:
			return {
				"complete": true,
				"visited": visited,
				"projectile_ticks": projectile_ticks,
				"ticks": int(snapshot.get("tick", 0)),
				"state_hash": simulation.state_hash(),
			}
		if phase == Simulation.PHASE_LEVEL:
			var level_id := int(snapshot.get("level_id", 0))
			if visited.is_empty() or visited[-1] != level_id:
				visited.append(level_id)
			var action := _autoplay_action(snapshot, update_index)
			if (action & Simulation.ACTION_FIRE) != 0:
				projectile_ticks += 1
			simulation.set_input(0, action)
		elif phase == Simulation.PHASE_SHOP:
			simulation.set_input(0, 0)
			simulation.set_shop_ready(0, true)
		elif phase == Simulation.PHASE_RANK_PROMOTION:
			simulation.set_input(0, Simulation.ACTION_FIRE)
		else:
			simulation.set_input(0, 0)
		simulation.step()
	return {
		"complete": false,
		"visited": visited,
		"projectile_ticks": projectile_ticks,
		"ticks": int(simulation.get_snapshot().get("tick", 0)),
		"error": "public-input guard exhausted in %s"
		% String(simulation.get_snapshot().get("phase", "unknown")),
	}


func _autoplay_action(snapshot: Dictionary, update_index: int) -> int:
	var players: Array = snapshot.get("players", [])
	if players.is_empty() or not bool((players[0] as Dictionary).get("alive", false)):
		return 0
	var player_x := int((players[0] as Dictionary).get("x_fp", 0))
	var target: Dictionary = {}
	for enemy_value in snapshot.get("enemies", []):
		var enemy: Dictionary = enemy_value
		var y_fp := int(enemy.get("y_fp", 0))
		if y_fp < 0 or y_fp >= int((players[0] as Dictionary).get("y_fp", 0)):
			continue
		if target.is_empty() or y_fp > int(target.get("y_fp", -1)):
			target = enemy
	var action := 0
	if not target.is_empty():
		var delta_x := int(target.get("x_fp", player_x)) - player_x
		if delta_x < -4 * Simulation.FP_ONE:
			action |= Simulation.ACTION_LEFT
		elif delta_x > 4 * Simulation.FP_ONE:
			action |= Simulation.ACTION_RIGHT
	if (update_index & 1) == 0:
		action |= Simulation.ACTION_FIRE
	return action


func _finalize_terminal_warp(simulation) -> void:
	simulation._level_resolved = true
	simulation._level_resolution_tick = simulation._tick
	simulation.step()
	_expect(simulation.get_snapshot().phase == Simulation.PHASE_WARP, "level 20 should enter Warp before terminal routing")
	simulation._warp_malfunction_interval = 0
	simulation._finalize_warp()


func _test_deterministic_level_one_to_twenty_campaign() -> void:
	var first := _run_campaign(202020)
	var second := _run_campaign(202020)
	_expect(bool(first.get("complete", false)), "the level 1-20 campaign should reach completion")
	_expect(first.get("visited", []) == range(1, 21), "the campaign should visit levels 1 through 20 in order")
	_expect(first.get("shops", []) == [4, 8, 12, 16, 20], "the campaign should visit all five recurring shops")
	_expect(
		String(first.get("state_hash", "")) == String(second.get("state_hash", ""))
		and int(first.get("ticks", -1)) == int(second.get("ticks", -2))
		and first.get("visited", []) == second.get("visited", [])
		and first.get("shops", []) == second.get("shops", []),
		"same-seed twenty-level campaigns should finish at an identical tick and hash"
	)


func _run_campaign(seed_value: int) -> Dictionary:
	var simulation := Simulation.new()
	if not simulation.configure({
		"mode": "solo",
		"difficulty": "normal",
		"collision_mode": "simple",
		"seed": seed_value,
		"start_level": 1,
		"end_level": 20,
		"record_replay": false,
	}):
		return {"complete": false, "error": simulation.get_last_error()}
	var visited: Array[int] = []
	var shops: Array[int] = []
	var prepared_level := 0
	var guard := 0
	while guard < 40000:
		guard += 1
		var snapshot: Dictionary = simulation.get_snapshot()
		var phase := String(snapshot.get("phase", ""))
		if phase == Simulation.PHASE_COMPLETE:
			return {
				"complete": true,
				"visited": visited,
				"shops": shops,
				"ticks": int(snapshot.get("tick", 0)),
				"state_hash": simulation.state_hash(),
			}
		match phase:
			Simulation.PHASE_LEVEL:
				var level_id := int(snapshot.get("level_id", 0))
				if prepared_level != level_id:
					if simulation._enemies.is_empty():
						simulation.step()
						continue
					visited.append(level_id)
					_fill_bonus_pool(simulation)
					if level_id in [4, 8, 12, 16, 20]:
						simulation._progression_for_seat(0).money = 100
					for enemy_value in simulation._enemies.duplicate():
						var enemy: Dictionary = enemy_value
						if not bool(enemy.get("dead", false)):
							simulation._kill_enemy(enemy, 0)
					prepared_level = level_id
			Simulation.PHASE_SHOP:
				var shop_level := int(snapshot.get("level_id", 0))
				if shops.is_empty() or shops[-1] != shop_level:
					shops.append(shop_level)
				simulation.set_shop_ready(0, true)
			Simulation.PHASE_RANK_PROMOTION:
				simulation.set_input(0, Simulation.ACTION_FIRE)
			Simulation.PHASE_WARP:
				simulation._warp_malfunction_interval = 0
				simulation.set_input(0, 0)
			_:
				simulation.set_input(0, 0)
		simulation.step()
	return {
		"complete": false,
		"visited": visited,
		"shops": shops,
		"ticks": int(simulation.get_snapshot().get("tick", 0)),
		"state_hash": simulation.state_hash(),
	}


func _fill_bonus_pool(simulation) -> void:
	simulation._pickups.clear()
	for slot_id in range(150):
		simulation._pickups.append({
			"id": -2000 - slot_id,
			"pickup_slot": slot_id,
			"kind": "campaign_pool_guard",
			"effect_key": "campaign_pool_guard",
			"expired": false,
			"x_fp": -100000 * Simulation.FP_ONE,
			"y_fp": -100000 * Simulation.FP_ONE,
			"velocity_x_fp": 0,
			"velocity_y_fp": 0,
			"width": 1,
			"height": 1,
			"animation_frame": 0,
			"animation_period_fp": 3 * Simulation.FP_ONE,
			"animation_countdown_fp": 3 * Simulation.FP_ONE,
		})


func _new_level(
	start_level: int,
	end_level: int,
	mode: String,
	seed_value: int,
	seats: Array = []
) -> GameSimulation:
	var simulation := Simulation.new()
	_expect(simulation.configure({
		"mode": mode,
		"difficulty": "normal",
		"collision_mode": "simple",
		"seed": seed_value,
		"start_level": start_level,
		"end_level": end_level,
		"record_replay": false,
		"seats": seats,
	}), "level-%d %s simulation should configure: %s" % [start_level, mode, simulation.get_last_error()])
	if not simulation._configured:
		return null
	simulation.step()
	return simulation


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

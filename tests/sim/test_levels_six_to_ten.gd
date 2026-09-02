extends SceneTree

const Simulation := preload("res://src/sim/game_simulation.gd")
const Catalog := preload("res://src/sim/content_catalog.gd")

const LEVEL_IDS := [6, 7, 8, 9, 10]
const LVD_SHA256 := [
	"455e9317c7c88949e2a01f6bbc0a7e9d2ab123c65212ca755b285cad2c748f55",
	"c8166c50a69d3b8d18a64105001b294620e7a34a9a8807aa44ab0a9c6ecb124e",
	"ec06689d53be07b5b4a276892ab00798db347382e2cb42f03d2150f87ff8d743",
	"cb74b30c90700fdbc4d99e8f0fd8f05033f33acc6d507b53a07d4e0d7c934fc7",
	"9e35777eafe10d504464ee0804ea60983abfe4b8239c0e2805a529d7312b94e0",
]
const MODES := [1, 1, 3, 1, 1]
const GROUPS := [2, 2, 2, 2, 4]
const ENEMIES := [20, 28, 20, 24, 30]
const RESOLVED_ENTITIES := [20, 29, 20, 24, 30]
const PATH_POINTS := [22, 22, 18, 22, 44]
const KILL_SCORES := [75, 75, 200, 150, 75]
const ENEMY_SHEETS := ["alien_2", "alien_2", "alien_2", "alien_3", "alien_3"]

var _failures: Array[String] = []


func _initialize() -> void:
	_test_catalog_contract()
	_test_runtime_spawns()
	_test_mode_three_escape_completion()
	_test_deterministic_level_one_to_ten_campaign()
	if _failures.is_empty():
		print("LEVELS 6-10 TESTS PASSED")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _test_catalog_contract() -> void:
	var catalog := Catalog.load_catalog()
	_expect(bool(catalog.get("ok", false)), "one-hundred-level catalog should load")
	if not bool(catalog.get("ok", false)):
		return
	var ids: Array = catalog.levels.map(func(level: Dictionary) -> int: return int(level.id))
	_expect(
		ids == range(1, 101),
		"authored classic route should be contiguous from level 1 through 100"
	)
	var raw_document: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://content/levels.json")
	)
	var raw_levels: Array = raw_document.get("levels", [])
	for index in range(LEVEL_IDS.size()):
		var level: Dictionary = catalog.levels[LEVEL_IDS[index] - 1]
		var raw_level: Dictionary = raw_levels[LEVEL_IDS[index] - 1]
		var authored: Dictionary = level.authored_lvd
		var enemy_count := 0
		var path_count := 0
		var health_values: Array[int] = []
		for group_value in authored.groups:
			var group: Dictionary = group_value
			enemy_count += group.enemies.size()
			path_count += group.path_points.size()
			for enemy_value in group.enemies:
				health_values.append(int((enemy_value as Dictionary).base_health))
		_expect(int(level.id) == LEVEL_IDS[index], "level ordering should remain stable")
		_expect(str(raw_level.raw_lvd_sha256) == LVD_SHA256[index], "level %d should retain its pinned LVD hash" % int(level.id))
		_expect(int(authored.level_mode_id) == MODES[index], "level %d should retain its authored mode" % int(level.id))
		_expect(authored.groups.size() == GROUPS[index], "level %d should retain its group count" % int(level.id))
		_expect(enemy_count == ENEMIES[index], "level %d should retain its enemy count" % int(level.id))
		_expect(path_count == PATH_POINTS[index], "level %d should retain its path-point count" % int(level.id))
		_expect(int(level.ordinary_kill_score) == KILL_SCORES[index], "level %d should retain its ordinary score" % int(level.id))
		_expect(str(level.enemy_sprite) == ENEMY_SHEETS[index], "level %d should bind its retail enemy sheet" % int(level.id))
		_expect(
			health_values.all(func(value: int) -> bool: return value == (2 if int(level.id) >= 9 else 1)),
			"levels 9-10 should use ALIEN_3 health two while levels 6-8 retain health one"
		)
		var resolved := enemy_count
		for record_value in authored.supplemental_spawn_records_raw_words.slice(0, 4):
			var record: Array = record_value
			if int(record[1]) == 1:
				resolved += maxi(0, int(record[0]))
		_expect(resolved == RESOLVED_ENTITIES[index], "level %d should retain its resolved entity total" % int(level.id))
	_expect(bool(catalog.levels[3].shop_after), "the first recurring shop should remain after level 4")
	_expect(bool(catalog.levels[7].shop_after), "the second recurring shop should occur after level 8")
	_expect(
		catalog.levels[6].authored_lvd.supplemental_spawn_records_raw_words[0] == [1, 1, 15, 861, 13],
		"level 7 should retain its exact state-6 supplemental record"
	)


func _test_runtime_spawns() -> void:
	for index in range(LEVEL_IDS.size()):
		var simulation := Simulation.new()
		_expect(simulation.configure({
			"mode": "solo",
			"difficulty": "normal",
			"collision_mode": "simple",
			"seed": 610 + index,
			"start_level": LEVEL_IDS[index],
			"end_level": 10,
			"record_replay": false,
		}), "level %d runtime should configure" % LEVEL_IDS[index])
		var before_draws := int(simulation.get_snapshot().rng.draw_count)
		var snapshot := simulation.step()
		_expect(snapshot.enemies.size() == RESOLVED_ENTITIES[index], "level %d should spawn every resolved authored entity" % LEVEL_IDS[index])
		_expect(
			snapshot.enemies.all(func(enemy: Dictionary) -> bool: return str(enemy.sprite) == ENEMY_SHEETS[index]),
			"level %d runtime enemies should use the authored sheet" % LEVEL_IDS[index]
		)
		if LEVEL_IDS[index] == 8:
			_expect(
				int(snapshot.rng.draw_count) == before_draws,
				"mode-3 enemies should consume no firing RNG on their first active update"
			)


func _test_mode_three_escape_completion() -> void:
	var simulation := Simulation.new()
	_expect(simulation.configure({
		"mode": "solo",
		"difficulty": "normal",
		"collision_mode": "simple",
		"seed": 808,
		"start_level": 8,
		"end_level": 10,
		"record_replay": true,
	}), "level-8 natural completion simulation should configure")
	var saw_counter_resolution := false
	var saw_watchdog := false
	for tick_index in range(6000):
		var snapshot := simulation.step()
		for event_value in snapshot.events:
			var event: Dictionary = event_value
			if str(event.get("type", "")) == "level_resolved":
				saw_counter_resolution = str(event.get("reason", "")) != "watchdog"
				saw_watchdog = str(event.get("reason", "")) == "watchdog"
		if str(snapshot.phase) != Simulation.PHASE_LEVEL:
			break
	_expect(saw_counter_resolution, "level 8 should resolve naturally from hit/escape accounting")
	_expect(not saw_watchdog, "level 8 should never require the liveness watchdog")
	_expect(
		simulation.get_snapshot().phase == Simulation.PHASE_WARP,
		"natural level-8 completion should enter its recurring retail Warp"
	)
	_expect(
		simulation.get_replay().frames.all(_frame_has_no_input),
		"the natural completion proof should not inject hidden firing input"
	)


func _frame_has_no_input(frame: Dictionary) -> bool:
	return int(frame.inputs[0]) == 0 and int(frame.inputs[1]) == 0


func _test_deterministic_level_one_to_ten_campaign() -> void:
	var first := _run_level_one_to_ten_campaign(1010)
	var second := _run_level_one_to_ten_campaign(1010)
	_expect(bool(first.get("complete", false)), "the bounded level 1-10 campaign should reach completion")
	_expect(
		first.get("visited", []) == range(1, 11),
		"the campaign should visit every authored level exactly once in order"
	)
	_expect(
		first.get("shops", []) == [4, 8],
		"the deterministic campaign should enter recurring shops only after levels 4 and 8; got %s" % [first.get("shops", [])]
	)
	_expect(
		String(first.get("state_hash", "")) == String(second.get("state_hash", ""))
		and int(first.get("ticks", -1)) == int(second.get("ticks", -2))
		and first.get("visited", []) == second.get("visited", [])
		and first.get("shops", []) == second.get("shops", []),
		"two level 1-10 campaigns with the same seed should end at the identical tick and state hash"
	)


func _run_level_one_to_ten_campaign(seed_value: int) -> Dictionary:
	var simulation := Simulation.new()
	if not simulation.configure({
		"mode": "solo",
		"difficulty": "normal",
		"collision_mode": "simple",
		"seed": seed_value,
		"start_level": 1,
		"end_level": 10,
		"record_replay": false,
	}):
		return {"complete": false, "error": simulation.get_last_error()}
	var visited: Array[int] = []
	var shops: Array[int] = []
	var prepared_level := 0
	var guard := 0
	while guard < 20000:
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
					_fill_bonus_pool_for_campaign(simulation)
					if level_id in [4, 8]:
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


func _fill_bonus_pool_for_campaign(simulation) -> void:
	simulation._pickups.clear()
	for slot_id in range(150):
		simulation._pickups.append({
			"id": -1000 - slot_id,
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


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

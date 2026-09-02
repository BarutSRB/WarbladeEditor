extends SceneTree

## Plays a real campaign segment across the level-100 boundary: 95 -> 126
## with the route-assist profile, asserting the credits interstitial, endless
## continuation, wrapped shop cadence, the mirrored wrapped level-125 boss with
## its traced +100-per-hundred health additive, terminal routing at the
## configured boundary, and frame-by-frame replay determinism.

const Simulation := preload("res://src/sim/game_simulation.gd")
const CampaignDriver := preload("res://tests/sim/test_campaign_through_thirty.gd")

const START_LEVEL := 95
const END_LEVEL := 126
const CAMPAIGN_SEED := 126_9500
const GUARD_STEPS := 400000
const EXPECTED_SHOPS: Array[int] = [96, 99, 104, 108, 112, 116, 120, 124]

var _failures: Array[String] = []


func _initialize() -> void:
	_test_endless_campaign_segment()
	if _failures.is_empty():
		print("LEVELS 95-126 ENDLESS CAMPAIGN TESTS PASSED")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _test_endless_campaign_segment() -> void:
	var first := _run_campaign()
	_expect(
		bool(first.get("complete", false)),
		"the 95-126 endless segment should complete: %s"
		% String(first.get("error", "guard exhausted"))
	)
	if not bool(first.get("complete", false)):
		return
	_expect(
		first.visited == range(START_LEVEL, END_LEVEL + 1),
		"the segment should visit every display level 95 through 126: %s"
		% str(first.visited)
	)
	_expect(
		first.shops == EXPECTED_SHOPS,
		"wrapped shop cadence should recur past level 100: %s" % str(first.shops)
	)
	_expect(
		int(first.credits_entries) == 1,
		"the level-100 credits interstitial should run exactly once"
	)
	_expect(
		int(first.level_101_routes) == 1,
		"dismissing the credits should begin level 101 exactly once"
	)
	_expect(
		int(first.boss_entries) == 2 and int(first.boss_music_cues) == 2,
		"the segment should enter the level-100 and wrapped level-125 encounters"
	)
	_expect(
		int(first.boss_100_maximum_health) == 500,
		"the authored level-100 boss keeps its retail 500 health at zero steps: %d"
		% int(first.boss_100_maximum_health)
	)
	_expect(
		int(first.boss_125_maximum_health) == 400,
		"the wrapped level-125 boss must carry retail 300 + the traced 100-per-hundred additive: %d"
		% int(first.boss_125_maximum_health)
	)
	_expect(
		bool(first.boss_125_entered_mirrored),
		"the wrapped level-125 encounter runs mirrored ((125 / 100) & 1)"
	)
	_expect(
		int(first.level_126_routes) == 1,
		"defeating the wrapped level-125 boss should bridge into level 126 once"
	)
	_expect(
		(first.watchdog_levels as Array).is_empty(),
		"wrapped endless levels must resolve through public gameplay, not the watchdog: %s"
		% str(first.watchdog_levels)
	)
	_expect(
		not bool(first.requested_level_after_end),
		"the configured level-126 boundary must never request level 127"
	)
	var terminal := first.get("campaign_terminal", {}) as Dictionary
	_expect(
		String(terminal.get("kind", "")) == "configured_boundary"
		and int(terminal.get("levels_beyond_authored", -1)) == 26,
		"the terminal contract should report a configured boundary 26 levels beyond the authored set"
	)
	_expect(
		int(first.replay_frame_count) > 0
		and String(first.last_replay_hash) == String(first.state_hash),
		"the recorded replay should end on the authoritative terminal hash"
	)
	var replayed := _play_replay(first.replay)
	_expect(
		bool(replayed.get("complete", false)),
		"the recorded 95-126 segment should replay to its terminal level: %s"
		% String(replayed.get("error", "replay did not complete"))
	)
	if bool(replayed.get("complete", false)):
		_expect(
			String(replayed.state_hash) == String(first.state_hash)
			and int(replayed.ticks) == int(first.ticks),
			"the replayed segment should reproduce every tick and the terminal hash"
		)


func _run_campaign() -> Dictionary:
	var simulation := Simulation.new()
	if not simulation.configure({
		"mode": "solo",
		"difficulty": "normal",
		"collision_mode": "pixel",
		"seed": CAMPAIGN_SEED,
		"start_level": START_LEVEL,
		"end_level": END_LEVEL,
		"starting_weapon": 8,
		"starting_lives": 999,
		"starting_money": 100,
		"starting_rockets": 50,
		"record_replay": true,
	}):
		return {"complete": false, "error": simulation.get_last_error()}

	var visited: Array[int] = []
	var shops: Array[int] = []
	var prepared_level := 0
	var boss_entries := 0
	var boss_music_cues := 0
	var boss_100_maximum_health := 0
	var boss_125_maximum_health := 0
	var boss_125_entered_mirrored := false
	var credits_entries := 0
	var credits_seen := false
	var level_101_routes := 0
	var level_126_routes := 0
	var watchdog_levels: Array[int] = []
	var requested_level_after_end := false
	var guard := 0
	while guard < GUARD_STEPS:
		guard += 1
		var snapshot: Dictionary = simulation.get_snapshot()
		var phase := String(snapshot.get("phase", ""))
		var tick := int(snapshot.get("tick", 0))
		var boss := snapshot.get("boss", {}) as Dictionary
		if bool(boss.get("active", false)):
			var boss_level := int(snapshot.get("level_id", 0))
			if boss_level == 100:
				boss_100_maximum_health = int(boss.get("max_health", 0))
			elif boss_level == 125:
				boss_125_maximum_health = int(boss.get("max_health", 0))
				if bool(boss.get("mirror_x", false)):
					boss_125_entered_mirrored = true
		if phase == Simulation.PHASE_CREDITS:
			if not credits_seen:
				credits_seen = true
				credits_entries += 1
		else:
			credits_seen = false
		if (
			int(snapshot.get("level_id", 0)) == END_LEVEL + 1
			or int((snapshot.get("level_resolution", {}) as Dictionary).get(
				"pending_level_id",
				0
			)) == END_LEVEL + 1
		):
			requested_level_after_end = true
		if phase == Simulation.PHASE_COMPLETE:
			var replay: Dictionary = simulation.get_replay()
			var frames := replay.get("frames", []) as Array
			return {
				"complete": true,
				"visited": visited,
				"shops": shops,
				"ticks": tick,
				"state_hash": simulation.state_hash(),
				"boss_entries": boss_entries,
				"boss_music_cues": boss_music_cues,
				"boss_100_maximum_health": boss_100_maximum_health,
				"boss_125_maximum_health": boss_125_maximum_health,
				"boss_125_entered_mirrored": boss_125_entered_mirrored,
				"credits_entries": credits_entries,
				"level_101_routes": level_101_routes,
				"level_126_routes": level_126_routes,
				"watchdog_levels": watchdog_levels,
				"requested_level_after_end": requested_level_after_end,
				"replay": replay,
				"replay_frame_count": frames.size(),
				"last_replay_hash": (
					String((frames[-1] as Dictionary).get("state_hash", ""))
					if not frames.is_empty()
					else ""
				),
				"campaign_terminal": (
					snapshot.get("result", {}) as Dictionary
				).get("campaign_terminal", {}).duplicate(true),
			}

		match phase:
			Simulation.PHASE_LEVEL:
				var level_id := int(snapshot.get("level_id", 0))
				if prepared_level != level_id:
					visited.append(level_id)
					prepared_level = level_id
					if level_id in [100, 125]:
						boss_entries += 1
				simulation.set_input(
					0,
					CampaignDriver.campaign_combat_input(snapshot, 0, true)
				)
			Simulation.PHASE_SHOP:
				var shop_level := int(snapshot.get("level_id", 0))
				if shops.is_empty() or shops[-1] != shop_level:
					shops.append(shop_level)
				var shop: Dictionary = snapshot.get("shop", {})
				var guard_until := int(shop.get("input_guard_until_tick", 0))
				simulation.set_input(0, (
					Simulation.ACTION_READY if tick > guard_until else 0
				))
			Simulation.PHASE_RANK_PROMOTION:
				simulation.set_input(0, Simulation.ACTION_FIRE)
			Simulation.PHASE_WARP_MALFUNCTION:
				simulation.set_input(
					0,
					CampaignDriver.campaign_combat_input(snapshot, 0, true)
				)
			Simulation.PHASE_CREDITS:
				# Pulse confirm so the interstitial sees a fresh press once its
				# minimum display time has elapsed.
				simulation.set_input(0, (
					Simulation.ACTION_CONFIRM if tick % 2 == 0 else 0
				))
			_:
				simulation.set_input(0, 0)

		var stepped: Dictionary = simulation.step()
		for event_value in stepped.get("events", []):
			var event := event_value as Dictionary
			var kind := String(event.get("kind", ""))
			if kind == "music_cue" and String(event.get("key", "")) == "boss":
				boss_music_cues += 1
			if kind == "get_ready_started" and int(event.get("level_id", 0)) == 101:
				level_101_routes += 1
			if kind == "get_ready_started" and int(event.get("level_id", 0)) == 126:
				level_126_routes += 1
			if (
				kind == "level_resolved"
				and String(event.get("reason", "")) == "watchdog"
				and int(event.get("level_id", 0)) not in watchdog_levels
			):
				watchdog_levels.append(int(event.get("level_id", 0)))
			if int(event.get("level_id", 0)) == END_LEVEL + 1:
				requested_level_after_end = true

	return {
		"complete": false,
		"error": "endless segment guard exhausted in %s at level %d"
		% [
			String(simulation.get_snapshot().get("phase", "unknown")),
			int(simulation.get_snapshot().get("level_id", 0)),
		],
		"visited": visited,
		"shops": shops,
		"watchdog_levels": watchdog_levels,
	}


func _play_replay(replay: Dictionary) -> Dictionary:
	var match_config := (replay.get("match_config", {}) as Dictionary).duplicate(true)
	match_config["content_hash"] = String(replay.get("content_hash", ""))
	match_config["record_replay"] = false
	var simulation := Simulation.new()
	if not simulation.configure(match_config):
		return {
			"complete": false,
			"error": "replay configure failed: %s" % simulation.get_last_error(),
		}
	var frames := replay.get("frames", []) as Array
	for frame_index in range(frames.size()):
		var frame := frames[frame_index] as Dictionary
		var inputs := frame.get("inputs", []) as Array
		if inputs.is_empty():
			return {
				"complete": false,
				"error": "replay input missing at frame %d" % frame_index,
			}
		if not simulation.set_input(0, int(inputs[0])):
			return {
				"complete": false,
				"error": "replay input rejected at frame %d" % frame_index,
			}
		simulation.step()
		if simulation.state_hash() != String(frame.get("state_hash", "")):
			return {
				"complete": false,
				"error": "replay diverged at frame %d (tick %d)"
				% [frame_index, int(frame.get("tick", -1))],
			}
	var terminal := simulation.get_snapshot()
	return {
		"complete": (
			String(terminal.get("phase", "")) == Simulation.PHASE_COMPLETE
			and int(terminal.get("level_id", 0)) == END_LEVEL
		),
		"error": "replay did not reach terminal level %d" % END_LEVEL,
		"ticks": int(terminal.get("tick", 0)),
		"state_hash": simulation.state_hash(),
	}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

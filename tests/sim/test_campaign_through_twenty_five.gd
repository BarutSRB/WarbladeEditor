extends SceneTree

const Simulation := preload("res://src/sim/game_simulation.gd")

const CAMPAIGN_SEED: int = 250025
const SHOP_LEVELS: Array[int] = [4, 8, 12, 16, 20, 24]

var _failures: Array[String] = []


func _initialize() -> void:
	_test_deterministic_campaign_through_level_twenty_five()
	if _failures.is_empty():
		print("LEVELS 1-25 CAMPAIGN TESTS PASSED")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _test_deterministic_campaign_through_level_twenty_five() -> void:
	var first := _run_campaign(CAMPAIGN_SEED)
	_expect(
		bool(first.get("complete", false)),
		"the first deterministic 1-25 campaign should complete: %s"
		% String(first.get("error", "guard exhausted"))
	)
	if not bool(first.get("complete", false)):
		return
	_expect(
		first.visited == range(1, 26),
		"the bounded campaign should visit every authored level from 1 through 25"
	)
	_expect(
		first.shops == SHOP_LEVELS,
		"the bounded campaign should retain the six recurring shop routes: %s"
		% str(first.shops)
	)
	_expect(
		int(first.level_reached) == 25
		and int(first.pending_level_id) == 0
		and not bool(first.requested_level_26),
		"level 25 should be terminal and must never request level 26"
	)
	_expect(
		int(first.boss_entries) == 1
		and int(first.boss_music_cues) == 1
		and int(first.public_boss_hits) > 0,
		"the campaign should enter state 13 once, cue boss music once, and defeat it through public fire"
	)
	_expect(
		int(first.replay_version) == 12
		and int(first.replay_frame_count) > 0
		and String(first.last_replay_hash) == String(first.state_hash),
		"the v12 replay should end on the authoritative terminal state hash"
	)
	if first.visited != range(1, 26) or first.shops != SHOP_LEVELS:
		return
	var replayed := _play_replay(first.replay)
	_expect(
		bool(replayed.get("complete", false)),
		"the recorded 1-25 campaign should replay through terminal level 25: %s"
		% String(replayed.get("error", "replay did not complete"))
	)
	if bool(replayed.get("complete", false)):
		_expect(
			String(replayed.state_hash) == String(first.state_hash)
			and int(replayed.ticks) == int(first.ticks)
			and int(replayed.verified_frames) == int(first.replay_frame_count),
			"the second 1-25 campaign should replay every public frame and terminal hash"
		)


func _run_campaign(seed_value: int) -> Dictionary:
	var simulation := Simulation.new()
	if not simulation.configure({
		"mode": "solo",
		"difficulty": "normal",
		"collision_mode": "simple",
		"seed": seed_value,
		"start_level": 1,
		"end_level": 25,
		"starting_weapon": 8,
		"starting_lives": 999,
		"starting_money": 100,
		"record_replay": true,
	}):
		return {"complete": false, "error": simulation.get_last_error()}

	var visited: Array[int] = []
	var shops: Array[int] = []
	var prepared_level := 0
	var boss_entries := 0
	var boss_music_cues := 0
	var requested_level_26 := false
	var guard := 0
	while guard < 70000:
		guard += 1
		var snapshot: Dictionary = simulation.get_snapshot()
		var phase := String(snapshot.get("phase", ""))
		if (
			int(snapshot.get("level_id", 0)) == 26
			or int((snapshot.get("level_resolution", {}) as Dictionary).get(
				"pending_level_id",
				0
			)) == 26
		):
			requested_level_26 = true
		if phase == Simulation.PHASE_COMPLETE:
			var replay: Dictionary = simulation.get_replay()
			var frames := replay.get("frames", []) as Array
			return {
				"complete": true,
				"visited": visited,
				"shops": shops,
				"ticks": int(snapshot.get("tick", 0)),
				"state_hash": simulation.state_hash(),
				"level_reached": int((snapshot.get("result", {}) as Dictionary).get(
					"level_reached",
					0
				)),
				"pending_level_id": int((
					snapshot.get("level_resolution", {}) as Dictionary
				).get("pending_level_id", -1)),
				"requested_level_26": requested_level_26,
				"boss_entries": boss_entries,
				"boss_music_cues": boss_music_cues,
				"public_boss_hits": int((
					snapshot.get("profile_stats", [{}]) as Array
				)[0].get("successful_hits", 0)),
				"replay_version": int(replay.get("version", 0)),
				"replay_frame_count": frames.size(),
				"last_replay_hash": (
					String((frames[-1] as Dictionary).get("state_hash", ""))
					if not frames.is_empty()
					else ""
				),
				"replay": replay,
			}

		match phase:
			Simulation.PHASE_LEVEL:
				var level_id := int(snapshot.get("level_id", 0))
				if prepared_level != level_id:
					visited.append(level_id)
					prepared_level = level_id
					if level_id == 25:
						boss_entries += 1
				simulation.set_input(0, _campaign_combat_input(snapshot))
			Simulation.PHASE_SHOP:
				var shop_level := int(snapshot.get("level_id", 0))
				if shops.is_empty() or shops[-1] != shop_level:
					shops.append(shop_level)
				var guard_until := int((snapshot.get("shop", {}) as Dictionary).get(
					"input_guard_until_tick",
					0
				))
				simulation.set_input(
					0,
					Simulation.ACTION_READY if int(snapshot.get("tick", 0)) > guard_until else 0
				)
			Simulation.PHASE_RANK_PROMOTION:
				simulation.set_input(0, Simulation.ACTION_FIRE)
			Simulation.PHASE_WARP_MALFUNCTION:
				simulation.set_input(0, _campaign_combat_input(snapshot))
			_:
				simulation.set_input(0, 0)

		var stepped: Dictionary = simulation.step()
		for event_value in stepped.get("events", []):
			var event := event_value as Dictionary
			if (
				String(event.get("kind", "")) == "music_cue"
				and String(event.get("key", "")) == "boss"
			):
				boss_music_cues += 1
			if int(event.get("level_id", 0)) == 26:
				requested_level_26 = true

	return {
		"complete": false,
		"error": "campaign guard exhausted in %s at level %d"
		% [
			String(simulation.get_snapshot().get("phase", "unknown")),
			int(simulation.get_snapshot().get("level_id", 0)),
		],
		"visited": visited,
		"shops": shops,
		"ticks": int(simulation.get_snapshot().get("tick", 0)),
		"state_hash": simulation.state_hash(),
	}


func _campaign_combat_input(snapshot: Dictionary) -> int:
	var players := snapshot.get("players", []) as Array
	if players.is_empty():
		return 0
	var player := players[0] as Dictionary
	if not bool(player.get("active", false)) or not bool(player.get("alive", false)):
		return 0
	var pickups := snapshot.get("pickups", []) as Array
	if not pickups.is_empty():
		var imminent := pickups[0] as Dictionary
		for pickup_value in pickups.slice(1):
			var pickup := pickup_value as Dictionary
			if int(pickup.get("y_fp", 0)) > int(imminent.get("y_fp", 0)):
				imminent = pickup
		var escape_x_fp := (
			40 * Simulation.FP_ONE
			if int(imminent.get("x_fp", 0)) >= 400 * Simulation.FP_ONE
			else 760 * Simulation.FP_ONE
		)
		var escape_delta := escape_x_fp - int(player.get("x_fp", 0))
		if escape_delta < -4 * Simulation.FP_ONE:
			return Simulation.ACTION_LEFT
		if escape_delta > 4 * Simulation.FP_ONE:
			return Simulation.ACTION_RIGHT
		return 0

	var target_x_fp: Variant = null
	if int(snapshot.get("level_id", 0)) == 25:
		var boss := snapshot.get("boss", {}) as Dictionary
		if bool(boss.get("active", false)):
			target_x_fp = int(float(boss.get("x", 0.0)) * Simulation.FP_ONE)
	else:
		for enemy_value in snapshot.get("enemies", []):
			var enemy := enemy_value as Dictionary
			if bool(enemy.get("warp_malfunction", false)):
				target_x_fp = int(enemy.get("x_fp", 0))
				break
			var enemy_y_fp := int(enemy.get("y_fp", 0))
			if (
				target_x_fp == null
				and int(enemy.get("behavior_state_id", 0)) != 8
				and enemy_y_fp >= -32 * Simulation.FP_ONE
				and enemy_y_fp < 350 * Simulation.FP_ONE
			):
				target_x_fp = int(enemy.get("x_fp", 0))
	if target_x_fp == null:
		return 0

	var delta := int(target_x_fp) - int(player.get("x_fp", 0))
	var input_mask := 0
	if delta < -4 * Simulation.FP_ONE:
		input_mask |= Simulation.ACTION_LEFT
	elif delta > 4 * Simulation.FP_ONE:
		input_mask |= Simulation.ACTION_RIGHT
	if (
		absi(delta) <= 24 * Simulation.FP_ONE
		and int(snapshot.get("tick", 0)) % 2 == 0
	):
		input_mask |= Simulation.ACTION_FIRE
	return input_mask


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
	if simulation.get_replay().initial_rng != replay.get("initial_rng", {}):
		return {"complete": false, "error": "replay initial RNG does not match"}

	var frames := replay.get("frames", []) as Array
	for frame_index in range(frames.size()):
		var frame := frames[frame_index] as Dictionary
		var inputs := frame.get("inputs", []) as Array
		if inputs.is_empty() or not simulation.set_input(0, int(inputs[0])):
			return {
				"complete": false,
				"error": "replay input rejected at frame %d" % frame_index,
			}
		for action_value in frame.get("bonus_actions", []):
			var action := action_value as Dictionary
			var accepted := simulation.submit_bonus_action(
				int(action.get("seat_id", -1)),
				int(action.get("target_tick", frame.get("tick", 0))),
				int(action.get("action_kind", 0)),
				int(action.get("tile_index", -1))
			)
			if not bool(accepted.get("accepted", false)):
				return {
					"complete": false,
					"error": "replay bonus action rejected at frame %d: %s"
					% [frame_index, String(accepted.get("reason", "unknown"))],
				}
		var stepped := simulation.step()
		if (
			int(stepped.get("tick", -1)) != int(frame.get("tick", -2))
			or simulation.state_hash() != String(frame.get("state_hash", ""))
		):
			return {
				"complete": false,
				"error": "replay diverged at frame %d (tick %d)"
				% [frame_index, int(frame.get("tick", -1))],
			}

	var terminal := simulation.get_snapshot()
	return {
		"complete": (
			String(terminal.get("phase", "")) == Simulation.PHASE_COMPLETE
			and int(terminal.get("level_id", 0)) == 25
		),
		"error": "replay did not reach terminal level 25",
		"ticks": int(terminal.get("tick", 0)),
		"state_hash": simulation.state_hash(),
		"verified_frames": frames.size(),
	}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

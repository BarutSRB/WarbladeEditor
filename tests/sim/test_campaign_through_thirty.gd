extends SceneTree

const Simulation := preload("res://src/sim/game_simulation.gd")

const DEFAULT_END_LEVEL: int = 100
const SUPPORTED_END_LEVELS: Array[int] = [30, 35, 49, 50, 62, 75, 100]
const SUPPORTED_MODES: Array[String] = ["solo", "coop"]
## Weapon 7 is the persistent Laser beam; see `boss_resists_primary_weapon`.
const LASER_WEAPON_ID: int = 7
# The hurry-up wave lengthens a slow run: once the first wave fires the
# interval drops to ten seconds for the rest of the level, and each wave can
# leave homing debris behind, so the driver spends far more ticks per level
# than it did before those hazards existed.
const CAMPAIGN_GUARD_STEPS: int = 500000
const EXTENDED_CAMPAIGN_GUARD_STEPS: int = 900000
const SHOP_LEVELS_BY_END := {
	30: [4, 8, 12, 16, 20, 24, 28],
	35: [4, 8, 12, 16, 20, 24, 28, 32, 33],
	49: [4, 8, 12, 16, 20, 24, 28, 32, 33, 36, 40, 41, 44, 48, 49],
	50: [4, 8, 12, 16, 20, 24, 28, 32, 33, 36, 40, 41, 44, 48, 49],
	62: [
		4, 8, 12, 16, 20, 24, 28, 32, 33, 36, 40, 41, 44, 48, 49,
		52, 56, 58, 60,
	],
	75: [
		4, 8, 12, 16, 20, 24, 28, 32, 33, 36, 40, 41, 44, 48, 49,
		52, 56, 58, 60, 64, 66, 68, 72, 74,
	],
	100: [
		4, 8, 12, 16, 20, 24, 28, 32, 33, 36, 40, 41, 44, 48, 49,
		52, 56, 58, 60, 64, 66, 68, 72, 74, 76, 80, 83, 84, 88,
		91, 92, 96, 99,
	],
}

var _failures: Array[String] = []


func _initialize() -> void:
	var end_level := _campaign_end_level()
	var mode := _campaign_mode()
	_test_deterministic_campaign(end_level, mode)
	if _failures.is_empty():
		print(
			"LEVELS 1-%d %s CAMPAIGN TESTS PASSED"
			% [end_level, mode.to_upper()]
		)
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _test_deterministic_campaign(
	end_level: int,
	mode: String
) -> void:
	var campaign_seed := end_level * 10001 + SUPPORTED_MODES.find(mode) * 101
	var expected_shops: Array = SHOP_LEVELS_BY_END[end_level]
	var first := _run_campaign(campaign_seed, end_level, mode)
	_expect(
		bool(first.get("complete", false)),
		"the first deterministic 1-%d campaign should complete: %s"
		% [end_level, String(first.get("error", "guard exhausted"))]
	)
	if not bool(first.get("complete", false)):
		return
	var route_error := _campaign_route_failure(
		first.visited as Array,
		end_level,
		int(first.get("warp_starts", 0))
	)
	_expect(route_error.is_empty(), route_error)
	_expect(
		first.shops == expected_shops,
		"the bounded campaign should retain the expected shop routes through level %d: %s"
		% [end_level, str(first.shops)]
	)
	_expect(
		int(first.level_reached) == end_level
		and int(first.pending_level_id) == 0
		and not bool(first.requested_level_after_end),
		"level %d should be terminal and must never request level %d"
		% [end_level, end_level + 1]
	)
	_expect(
		(first.watchdog_levels as Array).is_empty(),
		"levels 1-%d must resolve through public gameplay, not the liveness watchdog: %s"
		% [end_level, str(first.watchdog_levels)]
	)
	var expected_boss_entries := 1
	for boss_level in [50, 75, 100]:
		if end_level >= boss_level:
			expected_boss_entries += 1
	_expect(
		int(first.boss_entries) == expected_boss_entries
		and int(first.level_twenty_six_routes) == 1
		and int(first.level_fifty_routes) == (1 if end_level >= 50 else 0)
		and int(first.level_fifty_one_routes) == (1 if end_level > 50 else 0)
		and int(first.level_seventy_five_routes) == (1 if end_level >= 75 else 0)
		and int(first.level_seventy_six_routes) == (1 if end_level > 75 else 0)
		and int(first.level_one_hundred_routes) == (1 if end_level >= 100 else 0)
		and int(first.boss_music_cues) == expected_boss_entries
		and int(first.public_boss_hits) > 0,
		"the campaign should enter each configured state-13 encounter once, defeat it through public fire, and route across each boss boundary exactly once"
	)
	_expect(
		int(first.replay_version) == 12
		and int(first.replay_frame_count) > 0
		and String(first.last_replay_hash) == String(first.state_hash),
		"the v12 replay should end on the authoritative terminal state hash"
	)
	var replay_match_config := (first.replay.get("match_config", {}) as Dictionary)
	_expect(
		String(replay_match_config.get("collision_mode", "")) == "pixel"
		and int(replay_match_config.get("starting_weapon", -1)) == 8
		and int(replay_match_config.get("starting_lives", -1)) == 999
		and int(replay_match_config.get("starting_money", -1)) == 100
		and int(replay_match_config.get("starting_rockets", -1)) == 50,
		"the full-route replay must record its production-HMA route-assist profile exactly"
	)
	var terminal_contract := first.get("campaign_terminal", {}) as Dictionary
	_expect(
		bool(terminal_contract.get("credits_required", false)) == (end_level == 100)
		and String(terminal_contract.get("kind", ""))
		== ("level_100" if end_level == 100 else "configured_boundary"),
		"only a complete level-100 campaign should require the retail ending"
	)
	_expect(
		int(first.get("warp_starts", 0)) > 0
		and int(first.get("bonus_boundaries", 0)) > 0,
		"the bounded campaign should exercise Warp and authored bonus boundaries: warp=%d bonus=%d"
		% [
			int(first.get("warp_starts", 0)),
			int(first.get("bonus_boundaries", 0)),
		]
	)
	if end_level == 100:
		_expect(
			int(first.get("targeted_rocket_frames", 0)) > 0,
			"the full campaign should exercise authoritative homing targeting"
		)
	_expect(
		int(first.get("player_deaths", 0)) > 0
		and int(first.get("player_respawns", 0)) > 0,
		"the bounded campaign should exercise a death and its respawn"
	)
	if not route_error.is_empty() or first.shops != expected_shops:
		return
	var replayed := _play_replay(first.replay, end_level)
	_expect(
		bool(replayed.get("complete", false)),
		"the recorded 1-%d campaign should replay through terminal level %d: %s"
		% [end_level, end_level, String(replayed.get("error", "replay did not complete"))]
	)
	if bool(replayed.get("complete", false)):
		_expect(
			String(replayed.state_hash) == String(first.state_hash)
			and int(replayed.ticks) == int(first.ticks)
			and int(replayed.verified_frames) == int(first.replay_frame_count),
			"the second 1-%d campaign should replay every public frame and terminal hash"
			% end_level
		)


## The campaign must climb from level 1 to the declared boundary one level at a
## time. The single legitimate gap is a warp's owned skip, which advances up to
## four levels without ever entering them, so a run that took a warp may leave
## a bounded hole in the visited list. Returns an empty string when the route is
## acceptable, otherwise the failure message.
func _campaign_route_failure(
	visited: Array,
	end_level: int,
	warp_starts: int
) -> String:
	if visited == range(1, end_level + 1):
		return ""
	if visited.is_empty() or int(visited[0]) != 1 or int(visited[-1]) != end_level:
		return (
			"the bounded campaign should climb from level 1 to level %d: %s"
			% [end_level, str(visited)]
		)
	var gaps: Array[int] = []
	for index in range(1, visited.size()):
		var step := int(visited[index]) - int(visited[index - 1])
		if step <= 0:
			return (
				"the bounded campaign should never revisit or reverse a level: %s"
				% str(visited)
			)
		if step > 1:
			gaps.append(step - 1)
	if gaps.is_empty():
		return ""
	if warp_starts <= 0:
		return (
			"the bounded campaign skipped levels without taking a warp: %s"
			% str(visited)
		)
	for gap in gaps:
		if gap > 4:
			return (
				"a warp skip may cover at most four levels, saw a gap of %d: %s"
				% [gap, str(visited)]
			)
	return ""


func _run_campaign(
	seed_value: int,
	end_level: int,
	mode: String
) -> Dictionary:
	var simulation := Simulation.new()
	if not simulation.configure({
		"mode": mode,
		"difficulty": "normal",
		# Full-route campaigns retain the shipped pixel/HMA collision path. The
		# expanded combat resources below keep five frame-by-frame level-100
		# replays bounded; focused tests own the production starting economy,
		# weapon, and three-fighter depletion contracts.
		"collision_mode": "pixel",
		"seed": seed_value,
		"start_level": 1,
		"end_level": end_level,
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
	var level_twenty_six_routes := 0
	var level_fifty_routes := 0
	var level_fifty_one_routes := 0
	var level_seventy_five_routes := 0
	var level_seventy_six_routes := 0
	var level_one_hundred_routes := 0
	var watchdog_levels: Array[int] = []
	var requested_level_after_end := false
	var warp_starts := 0
	var bonus_boundaries := 0
	var authored_bonus_levels_seen: Array[int] = []
	var player_deaths := 0
	var player_respawns := 0
	var targeted_rocket_frames := 0
	var guard := 0
	var maximum_guard_steps := (
		EXTENDED_CAMPAIGN_GUARD_STEPS if end_level > 50 else CAMPAIGN_GUARD_STEPS
	)
	while guard < maximum_guard_steps:
		guard += 1
		var snapshot: Dictionary = simulation.get_snapshot()
		var phase := String(snapshot.get("phase", ""))
		if phase == Simulation.PHASE_WARP:
			warp_starts = maxi(warp_starts, 1)
		if bool((snapshot.get("mode_three_bonus", {}) as Dictionary).get("active", false)):
			var bonus_level_id := int(snapshot.get("level_id", 0))
			if bonus_level_id not in authored_bonus_levels_seen:
				authored_bonus_levels_seen.append(bonus_level_id)
				bonus_boundaries += 1
		for projectile_value in snapshot.get("projectiles", []):
			var projectile := projectile_value as Dictionary
			if (
				String(projectile.get(
					"projectile_kind",
					projectile.get("kind", "")
				)) == "rocket_missile"
				and String(projectile.get("target_kind", "")) in ["enemy", "boss"]
			):
				targeted_rocket_frames += 1
				break
		if (
			int(snapshot.get("level_id", 0)) == end_level + 1
			or int((snapshot.get("level_resolution", {}) as Dictionary).get(
				"pending_level_id",
				0
			)) == end_level + 1
		):
			requested_level_after_end = true
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
				"requested_level_after_end": requested_level_after_end,
				"boss_entries": boss_entries,
				"level_twenty_six_routes": level_twenty_six_routes,
				"level_fifty_routes": level_fifty_routes,
				"level_fifty_one_routes": level_fifty_one_routes,
				"level_seventy_five_routes": level_seventy_five_routes,
				"level_seventy_six_routes": level_seventy_six_routes,
				"level_one_hundred_routes": level_one_hundred_routes,
				"watchdog_levels": watchdog_levels,
				"boss_music_cues": boss_music_cues,
				"public_boss_hits": _total_successful_hits(snapshot),
				"replay_version": int(replay.get("version", 0)),
				"replay_frame_count": frames.size(),
				"last_replay_hash": (
					String((frames[-1] as Dictionary).get("state_hash", ""))
					if not frames.is_empty()
					else ""
				),
				"replay": replay,
				"campaign_terminal": (
					snapshot.get("result", {}) as Dictionary
				).get("campaign_terminal", {}).duplicate(true),
				"warp_starts": warp_starts,
				"bonus_boundaries": bonus_boundaries,
				"player_deaths": player_deaths,
				"player_respawns": player_respawns,
				"targeted_rocket_frames": targeted_rocket_frames,
			}

		match phase:
			Simulation.PHASE_LEVEL:
				var level_id := int(snapshot.get("level_id", 0))
				if prepared_level != level_id:
					visited.append(level_id)
					prepared_level = level_id
					if level_id in [25, 50, 75, 100]:
						boss_entries += 1
				_set_campaign_inputs(simulation, snapshot, mode)
			Simulation.PHASE_SHOP:
				var shop_level := int(snapshot.get("level_id", 0))
				if shops.is_empty() or shops[-1] != shop_level:
					shops.append(shop_level)
				var shop: Dictionary = snapshot.get("shop", {})
				var guard_until := int(shop.get(
					"input_guard_until_tick",
					0
				))
				var shop_ready_allowed := int(snapshot.get("tick", 0)) > guard_until
				for seat_id in _participating_seats(mode):
					simulation.set_input(seat_id, (
						Simulation.ACTION_READY
						if shop_ready_allowed
						else 0
					))
			Simulation.PHASE_RANK_PROMOTION:
				for seat_id in _participating_seats(mode):
					simulation.set_input(seat_id, Simulation.ACTION_FIRE)
			Simulation.PHASE_WARP_MALFUNCTION:
				_set_campaign_inputs(simulation, snapshot, mode)
			_:
				for seat_id in _participating_seats(mode):
					simulation.set_input(seat_id, 0)

		var stepped: Dictionary = simulation.step()
		for event_value in stepped.get("events", []):
			var event := event_value as Dictionary
			match String(event.get("kind", "")):
				"warp_started":
					warp_starts += 1
				"bonus_mode_boundary_started":
					bonus_boundaries += 1
				"level_eight_results_started":
					# The active snapshot already counts each authored mode-three
					# level exactly once; this event is asserted by focused tests.
					pass
				"player_destroyed":
					player_deaths += 1
				"player_respawned":
					player_respawns += 1
			if (
				String(event.get("kind", "")) == "music_cue"
				and String(event.get("key", "")) == "boss"
			):
				boss_music_cues += 1
			if (
				String(event.get("kind", "")) == "get_ready_started"
				and int(event.get("level_id", 0)) == 26
			):
				level_twenty_six_routes += 1
			if (
				String(event.get("kind", "")) == "get_ready_started"
				and int(event.get("level_id", 0)) == 50
			):
				level_fifty_routes += 1
			if (
				String(event.get("kind", "")) == "get_ready_started"
				and int(event.get("level_id", 0)) == 51
			):
				level_fifty_one_routes += 1
			if (
				String(event.get("kind", "")) == "get_ready_started"
				and int(event.get("level_id", 0)) == 75
			):
				level_seventy_five_routes += 1
			if (
				String(event.get("kind", "")) == "get_ready_started"
				and int(event.get("level_id", 0)) == 76
			):
				level_seventy_six_routes += 1
			if (
				String(event.get("kind", "")) == "get_ready_started"
				and int(event.get("level_id", 0)) == 100
			):
				level_one_hundred_routes += 1
			if (
				String(event.get("kind", "")) == "level_resolved"
				and String(event.get("reason", "")) == "watchdog"
				and int(event.get("level_id", 0)) not in watchdog_levels
			):
				watchdog_levels.append(int(event.get("level_id", 0)))
			if int(event.get("level_id", 0)) == end_level + 1:
				requested_level_after_end = true

	return {
		"complete": false,
		"error": (
			"campaign guard exhausted in %s at level %d "
			+ "(tick %d, deaths %d, killed %d of %d, effects %d)"
		)
		% [
			String(simulation.get_snapshot().get("phase", "unknown")),
			int(simulation.get_snapshot().get("level_id", 0)),
			int(simulation.get_snapshot().get("tick", 0)),
			player_deaths,
			int(simulation._level_killed_entities),
			int(simulation._level_total_entities),
			simulation._active_effect_objects().size(),
		]
		+ " boss_active=%s enemies=%d"
		% [
			str((simulation.get_snapshot().get("boss", {}) as Dictionary).get("active", false)),
			(simulation.get_snapshot().get("enemies", []) as Array).size(),
		],
		"visited": visited,
		"shops": shops,
		"watchdog_levels": watchdog_levels,
		"ticks": int(simulation.get_snapshot().get("tick", 0)),
		"state_hash": simulation.state_hash(),
	}


func _set_campaign_inputs(
	simulation: RefCounted,
	snapshot: Dictionary,
	mode: String
) -> void:
	for seat_id in _participating_seats(mode):
		simulation.set_input(
			seat_id,
			campaign_combat_input(snapshot, seat_id, true)
		)


static func _participating_seats(mode: String) -> Array[int]:
	return [0] if mode == "solo" else [0, 1]


static func _total_successful_hits(snapshot: Dictionary) -> int:
	var total := 0
	for stats_value in snapshot.get("profile_stats", []):
		var stats := stats_value as Dictionary
		total += int(stats.get("successful_hits", 0))
	return total


static func campaign_combat_input(
	snapshot: Dictionary,
	seat_id: int = 0,
	should_fire: bool = true
) -> int:
	var players := snapshot.get("players", []) as Array
	if seat_id < 0 or seat_id >= players.size():
		return 0
	var player := players[seat_id] as Dictionary
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

	# The shared effect pool is the only hazard that homes at the fighter and
	# destroys it on contact, and one hit clears an object, so the driver shoots
	# the closest one before it picks an authored target.
	var closest_effect_x_fp: Variant = null
	var closest_effect_y_fp: int = -(1 << 60)
	for effect_value in snapshot.get("effect_objects", []):
		var effect := effect_value as Dictionary
		var effect_y_fp := int(effect.get("y_fp", 0))
		if (
			effect_y_fp >= int(player.get("y_fp", 0))
			or effect_y_fp <= closest_effect_y_fp
		):
			continue
		closest_effect_x_fp = int(effect.get("x_fp", 0))
		closest_effect_y_fp = effect_y_fp
	if closest_effect_x_fp != null:
		var effect_delta := int(closest_effect_x_fp) - int(player.get("x_fp", 0))
		var effect_mask := Simulation.ACTION_FIRE if should_fire else 0
		if effect_delta < -Simulation.FP_ONE:
			effect_mask |= Simulation.ACTION_LEFT
		elif effect_delta > Simulation.FP_ONE:
			effect_mask |= Simulation.ACTION_RIGHT
		return effect_mask

	var target_x_fp: Variant = null
	var selected_target_y_fp: int = -(1 << 60)
	var target_y_limit_fp := 350 * Simulation.FP_ONE
	var mode_three_active := bool(
		(snapshot.get("mode_three_bonus", {}) as Dictionary).get("active", false)
	)
	if mode_three_active:
		if int(snapshot.get("level_id", 0)) >= 51:
			# Level 58 has bottom-entry targets whose held hitboxes overlap the
			# starting Plasma volley. Mode three suppresses alien projectiles, so the
			# extended driver can safely target every visible authored enemy.
			target_y_limit_fp = 600 * Simulation.FP_ONE
		else:
			# Preserve the established compatibility-campaign targeting inputs.
			target_y_limit_fp = int(player.get("y_fp", 0)) - 16 * Simulation.FP_ONE
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
			var candidate_y_limit_fp := target_y_limit_fp
			if (
				int(snapshot.get("level_id", 0)) >= 51
				and String(enemy.get("authored_state", "")) == "hold"
			):
				# Level 51 introduces ordinary authored holds below the historical
				# y=350 campaign-driver lane. They remain safely above the player and
				# must be targeted to avoid relying on the watchdog for progression.
				candidate_y_limit_fp = maxi(
					candidate_y_limit_fp,
					int(player.get("y_fp", 0)) - 16 * Simulation.FP_ONE
				)
			if (
				(
					target_x_fp == null
					or (
						mode_three_active
						and int(snapshot.get("level_id", 0)) >= 51
						and enemy_y_fp > selected_target_y_fp
					)
				)
				and int(enemy.get("behavior_state_id", 0)) != 8
				and enemy_y_fp >= -32 * Simulation.FP_ONE
				and enemy_y_fp < candidate_y_limit_fp
			):
				target_x_fp = int(enemy.get("x_fp", 0))
				selected_target_y_fp = enemy_y_fp
	if target_x_fp == null:
		return 0

	var reachable_target_x_fp := int(target_x_fp)
	if int(snapshot.get("level_id", 0)) >= 51:
		# Several added formations hold thirty pixels beyond the player's retail
		# movement clamp. Aim from the nearest reachable edge so the starting
		# weapon's spread can clear them instead of moving forever without firing.
		reachable_target_x_fp = clampi(
			reachable_target_x_fp,
			Simulation.PLAYER_MIN_X_FP,
			Simulation.PLAYER_MAX_X_FP
		)
	var delta := reachable_target_x_fp - int(player.get("x_fp", 0))
	var input_mask := 0
	if delta < -4 * Simulation.FP_ONE:
		input_mask |= Simulation.ACTION_LEFT
	elif delta > 4 * Simulation.FP_ONE:
		input_mask |= Simulation.ACTION_RIGHT
	if (
		should_fire
		and absi(delta) <= 24 * Simulation.FP_ONE
		and int(snapshot.get("tick", 0)) % 2 == 0
	):
		input_mask |= Simulation.ACTION_FIRE
	if (
		should_fire
		and bool(boss.get("active", false))
		and int((player.get("progression", {}) as Dictionary).get("rockets", 0)) > 0
		and int(snapshot.get("tick", 0)) % 2 == 0
		and (
			int(snapshot.get("level_id", 0)) == 100
			or boss_resists_primary_weapon(snapshot, player)
		)
	):
		# The retail final boss is intentionally a long 500-health encounter.
		# Exercise the public homing-rocket path in the bounded campaign instead
		# of letting the test driver spend hundreds of thousands of ticks waiting
		# for its straight Plasma lane to cross the mirrored off-screen loop.
		# The same secondary is the driver's only answer when the fighter reaches
		# any state-13 encounter holding a weapon the boss is immune to.
		input_mask |= Simulation.ACTION_SECONDARY
	return input_mask


## Retail's collision pass rewrites the Laser's rectangle to the column between
## the top of the field and the fighter (`0x00585945-0x00585971`), then tests a
## state-13 boss against that rectangle's *midpoint*. The only thing that brings
## the midpoint into the boss's local 16..112 band is the override at
## `0x00585af7-0x00585b6a`, which substitutes local Y 60 solely while the boss
## origin sits inside `(0.0, 600.0)` — both constants read from the retail image.
## Every big-boss path hangs above that band (the level-25 encounter peaks at
## origin Y -55.6), so a fighter holding the Laser cannot damage a boss at all.
## That is faithful retail behaviour, not a remake defect; it only matters here
## because a campaign whose pickups happen to leave the driver on the Laser would
## otherwise fire into a boss forever. The driver spends a homing rocket instead.
static func boss_resists_primary_weapon(
	snapshot: Dictionary,
	player: Dictionary
) -> bool:
	if int(
		(player.get("progression", {}) as Dictionary).get("weapon_id", -1)
	) != LASER_WEAPON_ID:
		return false
	var boss_y := float((snapshot.get("boss", {}) as Dictionary).get("y", 0.0))
	return boss_y <= 0.0 or boss_y >= float(Simulation.FIELD_HEIGHT)


func _play_replay(replay: Dictionary, end_level: int) -> Dictionary:
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
	var replay_mode := String(match_config.get("mode", "solo"))
	for frame_index in range(frames.size()):
		var frame := frames[frame_index] as Dictionary
		var inputs := frame.get("inputs", []) as Array
		if inputs.is_empty():
			return {
				"complete": false,
				"error": "replay input missing at frame %d" % frame_index,
			}
		for seat_id in _participating_seats(replay_mode):
			if seat_id >= inputs.size():
				return {
					"complete": false,
					"error": "replay input missing for seat %d at frame %d"
					% [seat_id, frame_index],
				}
			if not simulation.set_input(seat_id, int(inputs[seat_id])):
				return {
					"complete": false,
					"error": "replay input rejected for seat %d at frame %d"
					% [seat_id, frame_index],
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
			and int(terminal.get("level_id", 0)) == end_level
		),
		"error": "replay did not reach terminal level %d" % end_level,
		"ticks": int(terminal.get("tick", 0)),
		"state_hash": simulation.state_hash(),
		"verified_frames": frames.size(),
	}


func _campaign_end_level() -> int:
	var configured := OS.get_environment("CAMPAIGN_END_LEVEL")
	var end_level := DEFAULT_END_LEVEL if configured.is_empty() else int(configured)
	if end_level not in SUPPORTED_END_LEVELS:
		_failures.append(
			"CAMPAIGN_END_LEVEL must be 30, 35, 49, 50, 62, 75, or 100"
		)
		return DEFAULT_END_LEVEL
	return end_level


func _campaign_mode() -> String:
	var mode := OS.get_environment("CAMPAIGN_MODE").to_lower()
	if mode.is_empty():
		return "solo"
	if mode not in SUPPORTED_MODES:
		_failures.append("CAMPAIGN_MODE must be solo or coop")
		return "solo"
	return mode


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

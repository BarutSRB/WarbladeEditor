extends SceneTree

const Simulation := preload("res://src/sim/game_simulation.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_memory_suspends_ordinary_combat()
	_test_memory_device_normalization_and_replay_parity()
	_test_bonus_action_validation()
	_test_meteor_suspends_combat_and_holds_result_strictly()
	_test_meteor_threshold_enters_terminal_gem_drop_in_rng_order()
	_test_gem_drop_primary_fire_and_terminal_reset()
	_test_gem_drop_multiplayer_movement_ownership()
	_test_bonus_profile_statistics()
	if _failures.is_empty():
		print("BONUS MODE INTEGRATION TESTS PASSED")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _test_memory_suspends_ordinary_combat() -> void:
	var simulation = _memory_simulation(7101)
	var frozen_bytes := _ordinary_combat_bytes(simulation)
	var frozen_hash: String = simulation._combat_state_hash()
	var level_tick := int(simulation._level_tick)

	for action_mask in [
		Simulation.ACTION_RIGHT,
		Simulation.ACTION_UP,
		Simulation.ACTION_LEFT,
		Simulation.ACTION_DOWN,
	]:
		_expect(simulation.set_input(0, action_mask), "Memory owner input should be accepted")
		var snapshot: Dictionary = simulation.step()
		_expect(
			String(snapshot.phase) == Simulation.PHASE_BONUS_MODE
			and String(snapshot.bonus_mode.kind) == "memory_station"
			and bool(snapshot.bonus_mode.suspended),
			"Memory Station should remain the authoritative suspended phase"
		)
		_expect(
			_ordinary_combat_bytes(simulation) == frozen_bytes
			and simulation._combat_state_hash() == frozen_hash
			and int(simulation._level_tick) == level_tick,
			"Memory Station must preserve every ordinary-combat field byte-for-byte"
		)


func _test_memory_device_normalization_and_replay_parity() -> void:
	var mouse = _memory_simulation(7202)
	var keyboard = _memory_simulation(7202)
	var gamepad = _memory_simulation(7202)
	var target_tick := int(mouse._tick) + 1

	var submitted: Dictionary = mouse.submit_bonus_action(
		0,
		target_tick,
		Simulation.BONUS_ACTION_SELECT_TILE,
		0
	)
	_expect(bool(submitted.accepted), "mouse tile selection should queue authoritatively")
	_expect(
		keyboard.set_input(0, Simulation.ACTION_FIRE),
		"keyboard selection should use the shared Fire action"
	)
	_expect(
		gamepad.set_input(0, Simulation.ACTION_FIRE),
		"gamepad selection should use the shared Fire action"
	)

	var mouse_snapshot: Dictionary = mouse.step()
	var keyboard_snapshot: Dictionary = keyboard.step()
	var gamepad_snapshot: Dictionary = gamepad.step()
	var mouse_frame: Dictionary = mouse.get_replay().frames[-1]
	var keyboard_frame: Dictionary = keyboard.get_replay().frames[-1]
	var gamepad_frame: Dictionary = gamepad.get_replay().frames[-1]
	var expected_action := [{
		"seat_id": 0,
		"target_tick": target_tick,
		"action_kind": Simulation.BONUS_ACTION_SELECT_TILE,
		"tile_index": 0,
	}]

	_expect(
		mouse_frame.bonus_actions == expected_action
		and keyboard_frame.bonus_actions == expected_action
		and gamepad_frame.bonus_actions == expected_action,
		"mouse, keyboard, and gamepad must record one identical semantic bonus action"
	)
	_expect(
		mouse_frame.inputs == [0, 0]
		and keyboard_frame.inputs == [0, 0]
		and gamepad_frame.inputs == [0, 0],
		"raw Fire must be stripped once it is represented by the semantic replay action"
	)
	_expect(
		mouse_snapshot.bonus_mode.tiles == keyboard_snapshot.bonus_mode.tiles
		and mouse_snapshot.bonus_mode.tiles == gamepad_snapshot.bonus_mode.tiles,
		"all input devices must reveal the same authoritative Memory tile"
	)
	_expect(
		mouse.state_hash() == keyboard.state_hash()
		and mouse.state_hash() == gamepad.state_hash()
		and String(mouse_frame.state_hash) == String(keyboard_frame.state_hash)
		and String(mouse_frame.state_hash) == String(gamepad_frame.state_hash),
		"normalized device input must converge to identical live and replay state hashes"
	)


func _test_bonus_action_validation() -> void:
	var simulation = _memory_simulation(7303, Simulation.MODE_COOP)
	var current_tick := int(simulation._tick)
	_expect_rejection(
		simulation.submit_bonus_action(1, current_tick + 1, 999, -1),
		"not_bonus_mode_owner",
		"the non-owning co-op seat must not control Memory Station"
	)
	_expect_rejection(
		simulation.submit_bonus_action(0, current_tick + 1, 999, -1),
		"unsupported_bonus_action",
		"unknown semantic action kinds must be rejected"
	)
	_expect_rejection(
		simulation.submit_bonus_action(
			0,
			current_tick + 1,
			Simulation.BONUS_ACTION_SELECT_TILE,
			-1
		),
		"tile_out_of_range",
		"negative tile indices must be rejected"
	)
	_expect_rejection(
		simulation.submit_bonus_action(
			0,
			current_tick + 1,
			Simulation.BONUS_ACTION_SELECT_TILE,
			7
		),
		"tile_is_outside_active_grid",
		"fixed-stride tile indices outside the active grid must be rejected"
	)
	_expect_rejection(
		simulation.submit_bonus_action(
			0,
			current_tick + 1,
			Simulation.BONUS_ACTION_KILL_TIME,
			0
		),
		"kill_time_has_tile",
		"kill-time commands must not smuggle a tile index"
	)
	_expect_rejection(
		simulation.submit_bonus_action(
			0,
			current_tick + Simulation.BONUS_ACTION_MAX_FUTURE_TICKS + 1,
			Simulation.BONUS_ACTION_SELECT_TILE,
			0
		),
		"input_too_far_ahead",
		"far-future actions must be rejected"
	)

	for unused_tick in range(Simulation.BONUS_ACTION_MAX_OLD_TICKS + 1):
		simulation.set_input(0, 0)
		simulation.set_input(1, 0)
		simulation.step()
	current_tick = int(simulation._tick)
	_expect_rejection(
		simulation.submit_bonus_action(
			0,
			current_tick - Simulation.BONUS_ACTION_MAX_OLD_TICKS - 1,
			Simulation.BONUS_ACTION_SELECT_TILE,
			0
		),
		"input_too_old",
		"stale bonus actions must be rejected"
	)

	var accepted: Dictionary = simulation.submit_bonus_action(
		0,
		current_tick + 1,
		Simulation.BONUS_ACTION_SELECT_TILE,
		0
	)
	_expect(bool(accepted.accepted), "one valid owner action should enter the bounded queue")
	_expect_rejection(
		simulation.submit_bonus_action(
			0,
			current_tick + 1,
			Simulation.BONUS_ACTION_SELECT_TILE,
			0
		),
		"duplicate_action_tick",
		"a duplicated target tick must be rejected before execution"
	)
	_expect_rejection(
		simulation.submit_bonus_action(
			0,
			current_tick + 2,
			Simulation.BONUS_ACTION_SELECT_TILE,
			1
		),
		"bonus_action_rate_limited",
		"a second queued owner action must fail the authoritative action-rate limit"
	)

	simulation.step()
	_expect_rejection(
		simulation.submit_bonus_action(
			0,
			int(simulation._tick) + 1,
			Simulation.BONUS_ACTION_SELECT_TILE,
			0
		),
		"tile_is_already_revealed",
		"server-side tile validation must reject a repeated revealed selection"
	)


func _test_meteor_suspends_combat_and_holds_result_strictly() -> void:
	var simulation = _meteor_simulation(7404)
	var frozen_bytes := _ordinary_combat_bytes(simulation)
	var frozen_hash: String = simulation._combat_state_hash()
	var initial_snapshot: Dictionary = simulation.get_snapshot()
	_expect(
		initial_snapshot.bonus_mode.slots.size() == 30,
		"GameSimulation should expose Meteor Storm's complete 30-slot pool"
	)

	for action_mask in [
		Simulation.ACTION_LEFT,
		Simulation.ACTION_RIGHT | Simulation.ACTION_FIRE,
		0,
	]:
		simulation.set_input(0, action_mask)
		simulation.step()
		_expect(
			_ordinary_combat_bytes(simulation) == frozen_bytes
			and simulation._combat_state_hash() == frozen_hash,
			"Meteor intro/gameplay must preserve ordinary combat byte-for-byte"
		)

	# Drive the real controller across its natural success branch while keeping
	# GameSimulation responsible for rewards, profile accounting, and the hold.
	var meteor = simulation._meteor_storm
	meteor._intro_until_ms = 0
	meteor._distance = 0.01
	meteor._counted_active_slots = 20
	meteor._low_speed_updates = 0
	meteor._high_speed_updates = 1
	meteor._speed = 15.0
	meteor._accelerator_released = false
	simulation.set_input(0, Simulation.ACTION_FIRE)
	var completed: Dictionary = simulation.step()
	_expect(
		String(completed.phase) == Simulation.PHASE_BONUS_MODE
		and String(completed.bonus_mode.completion.tier) == "perfect",
		"perfect Meteor completion should enter the parent-owned result hold"
	)
	_expect(
		int(completed.profile_stats[0].bonus_rounds) == 1
		and int(completed.profile_stats[0].perfect_bonus_rounds) == 1
		and int(completed.profile_stats[0].meteor_score) >= 10000000,
		"Meteor rewards should update authoritative profile statistics exactly once"
	)
	_expect(
		_ordinary_combat_bytes(simulation) == frozen_bytes
		and simulation._combat_state_hash() == frozen_hash,
		"Meteor completion rewards must not mutate suspended ordinary combat"
	)

	var completion_tick := int(simulation._tick)
	# 180 simulation ticks are exactly 3000ms, preserving the completion-frame
	# millisecond remainder and reaching the strict retail equality boundary.
	simulation._tick = completion_tick + 179
	simulation.set_input(0, 0)
	var equality: Dictionary = simulation.step()
	_expect(
		String(equality.phase) == Simulation.PHASE_BONUS_MODE
		and not equality.bonus_mode.completion.is_empty(),
		"Meteor's result screen must remain active at exact three-second equality"
	)
	_expect(
		_ordinary_combat_bytes(simulation) == frozen_bytes
		and simulation._combat_state_hash() == frozen_hash,
		"ordinary combat must remain byte-identical throughout the result hold"
	)

	var resumed: Dictionary = simulation.step()
	_expect(
		String(resumed.phase) == Simulation.PHASE_LEVEL
		and String(resumed.bonus_mode.kind).is_empty()
		and not bool(resumed.bonus_mode.suspended),
		"Meteor Storm should resume combat only after the strict three-second boundary"
	)
	_expect(
		_ordinary_combat_bytes(simulation) == frozen_bytes,
		"resuming from Meteor Storm must restore the unchanged ordinary-combat state"
	)


func _test_bonus_profile_statistics() -> void:
	var memory = _memory_simulation(7505)
	var equality_tick := int(memory._tick) + 1
	memory._memory_station._mode_deadline_ms = equality_tick * 1000 / Simulation.TICKS_PER_SECOND
	memory.set_input(0, 0)
	var equality: Dictionary = memory.step()
	_expect(
		String(equality.phase) == Simulation.PHASE_BONUS_MODE,
		"Memory Station should remain active at exact deadline equality"
	)
	var failed: Dictionary = memory.step()
	_expect(
		String(failed.phase) == Simulation.PHASE_LEVEL
		and int(failed.profile_stats[0].bonus_rounds) == 1
		and int(failed.profile_stats[0].perfect_bonus_rounds) == 0,
		"a failed Memory round should increment only the total bonus-round statistic"
	)

	var meteor = _new_simulation(7506)
	meteor._enter_bonus_mode_boundary("meteor_storm", meteor._shared, 0)
	meteor._apply_meteor_progression_deltas(
		meteor._shared,
		0,
		{"meteor_score": 1000}
	)
	meteor._finish_bonus_mode_boundary("meteor_storm")
	meteor._enter_bonus_mode_boundary("meteor_storm", meteor._shared, 0)
	meteor._apply_meteor_progression_deltas(
		meteor._shared,
		0,
		{"meteor_score": 400}
	)
	var meteor_stats: Dictionary = meteor.get_snapshot().profile_stats[0]
	_expect(
		int(meteor_stats.meteor_score) == 1000
		and int(meteor_stats.meteor_current_score) == 400,
		"profile best Meteor score should retain the best individual round, not a cumulative run total"
	)


func _test_meteor_threshold_enters_terminal_gem_drop_in_rng_order() -> void:
	var simulation = _meteor_simulation(7454)
	var meteor = simulation._meteor_storm
	meteor._intro_until_ms = 0
	meteor._counted_active_slots = 20
	meteor._active_target = 20.0
	meteor._gem_progress = meteor._gem_progress_origin + 95 * meteor._gem_progress_step
	for slot_value in meteor._slots:
		(slot_value as Dictionary).active = false
	var slot: Dictionary = meteor._slots[0]
	slot.active = true
	slot.kind = "gem"
	slot.frame_index = 0
	slot.source_rect = [0, 0, 80, 51]
	slot.x = 360.0
	slot.y = 535.0
	slot.velocity_x = 0.0
	slot.velocity_y = 0.0
	slot.animation_ticks = 5.0
	slot.collision_mask = "diamantbig"
	slot.texture_id = "diamantbig"
	slot.spawn_serial = 999
	var draws_before := int(simulation._rng.snapshot().draw_count)
	simulation.set_input(0, 0)
	var entered: Dictionary = simulation.step()
	var draws_after := int(simulation._rng.snapshot().draw_count)
	_expect(
		String(entered.phase) == Simulation.PHASE_BONUS_MODE
		and String(entered.bonus_mode.kind) == "gem_drop"
		and String(entered.bonus_mode.source_mode) == "meteor_storm",
		"a Meteor threshold should enter the real standalone Gem Drop controller"
	)
	# With no state-8 captive, FUN_0059bb90 consumes 3*150+100 draws,
	# the ten-slot initializer consumes 30, and the collected Meteor gem draws
	# one bell frequency after state-18 initialization.
	_expect(
		draws_after - draws_before == 581,
		"Meteor threshold RNG must be reset(550), Gem init(30), then bell(1)"
	)
	var event_kinds: Array[String] = []
	for event_value in entered.events:
		event_kinds.append(String((event_value as Dictionary).type))
	var started_index := event_kinds.find("meteor_gem_drop_started")
	var entered_index := event_kinds.find("gem_drop_entered")
	var collected_index := event_kinds.find("meteor_gem_collected")
	var bell_index := -1
	for event_index in range(entered.events.size()):
		var event: Dictionary = entered.events[event_index]
		if String(event.get("type", "")) == "sound_cue" and String(event.get("key", "")) == "bell1":
			bell_index = event_index
	_expect(
		started_index >= 0
		and entered_index > started_index
		and collected_index > entered_index
		and bell_index > collected_index,
		"state-18 initialization must occur inside Meteor's collision scan before deactivation/bell"
	)
	_expect(
		simulation._enemies.is_empty()
		and simulation._projectiles.is_empty()
		and simulation._pickups.is_empty(),
		"Gem Drop entry should destructively reset non-captive combat pools"
	)


func _test_gem_drop_primary_fire_and_terminal_reset() -> void:
	var simulation = _meteor_simulation(7464)
	var entered: Dictionary = simulation._prepare_gem_drop(
		"meteor_storm",
		false,
		0,
		{}
	)
	_expect(bool(entered.ok), "Gem Drop integration setup should initialize state 18")
	simulation._activate_pending_gem_drop_transition()
	var intro_deadline := int(simulation._gem_drop._intro_until_ms)
	# Primary fire is allowed during the four-second intro; ordinary projectile
	# updates remain absent from the state-18 dispatcher.
	simulation.set_input(0, Simulation.ACTION_FIRE)
	var before_x := int(simulation._players[0].x_fp)
	var intro: Dictionary = simulation.step()
	_expect(
		String(intro.bonus_mode.kind) == "gem_drop"
		and int(simulation._gem_drop._now_ms) < intro_deadline
		and not simulation._projectiles.is_empty()
		and int(simulation._players[0].x_fp) == before_x,
		"Gem Drop intro should run primary fire/player control without advancing shots"
	)
	var projectile_y := int((simulation._projectiles[0] as Dictionary).y_fp)
	simulation.set_input(0, 0)
	simulation.step()
	_expect(
		int((simulation._projectiles[0] as Dictionary).y_fp) == projectile_y,
		"ordinary player shots allocated in state 18 must remain stationary"
	)

	# Equality is an active Gem update. Starting at exactly zero therefore
	# decrements below zero, invokes the second variable-RNG pool reset, and
	# returns directly to ordinary state 2 in this same simulation step.
	simulation._gem_drop._intro_until_ms = 0
	simulation._gem_drop._remaining = 0.0
	var reset_draws_before := int(simulation._rng.snapshot().draw_count)
	var completed: Dictionary = simulation.step()
	var reset_draws_after := int(simulation._rng.snapshot().draw_count)
	_expect(
		String(completed.phase) == Simulation.PHASE_LEVEL
		and String(completed.bonus_mode.kind).is_empty()
		and reset_draws_after - reset_draws_before == 550,
		"Gem Drop terminal should reset pools again and return directly to state 2"
	)
	var boundary_event: Dictionary = {}
	for event_value in completed.events:
		var event: Dictionary = event_value
		if String(event.get("type", "")) == "bonus_mode_boundary_ended":
			boundary_event = event
	_expect(
		bool(boundary_event.get("music_unchanged", false))
		and not boundary_event.has("music_key")
		and simulation._projectiles.is_empty(),
		"Gem Drop completion must leave gems music untouched and discard state-18 shots"
	)


func _test_gem_drop_multiplayer_movement_ownership() -> void:
	var coop = _new_simulation(7474, Simulation.MODE_COOP)
	coop._enter_bonus_mode_boundary("meteor_storm", coop._shared, 0)
	coop._prepare_gem_drop("meteor_storm", false, 0, {})
	coop._activate_pending_gem_drop_transition()
	var coop_p0_x := int(coop._players[0].x_fp)
	var coop_p1_x := int(coop._players[1].x_fp)
	coop.set_input(0, Simulation.ACTION_LEFT)
	coop.set_input(1, Simulation.ACTION_RIGHT)
	coop.step()
	_expect(
		int(coop._players[0].x_fp) < coop_p0_x
		and int(coop._players[1].x_fp) > coop_p1_x,
		"remake co-op should move both Gem Drop fighters under owner-first authority"
	)


func _new_simulation(seed_value: int, mode: String = Simulation.MODE_SOLO):
	var simulation = Simulation.new()
	_expect(simulation.configure({
		"mode": mode,
		"difficulty": "normal",
		"collision_mode": "simple",
		"start_level": 1,
		"end_level": 10,
		"seed": seed_value,
		"record_replay": true,
	}), "bonus integration simulation should configure: %s" % simulation.get_last_error())
	# Populate and advance ordinary combat once, so suspension checks cover live
	# authored enemies and counters instead of only pristine empty collections.
	simulation.step()
	simulation.set_input(0, 0)
	if mode == Simulation.MODE_COOP:
		simulation.set_input(1, 0)
	return simulation


func _memory_simulation(seed_value: int, mode: String = Simulation.MODE_SOLO):
	var simulation = _new_simulation(seed_value, mode)
	simulation._enter_bonus_mode_boundary("memory_station", simulation._shared, 0)
	_expect(
		String(simulation._phase) == Simulation.PHASE_BONUS_MODE
		and String(simulation._active_bonus_mode_kind()) == "memory_station",
		"Memory Station integration fixture should enter through GameSimulation"
	)
	return simulation


func _meteor_simulation(seed_value: int):
	var simulation = _new_simulation(seed_value)
	simulation._enter_bonus_mode_boundary("meteor_storm", simulation._shared, 0)
	_expect(
		String(simulation._phase) == Simulation.PHASE_BONUS_MODE
		and String(simulation._active_bonus_mode_kind()) == "meteor_storm",
		"Meteor Storm integration fixture should enter through GameSimulation"
	)
	return simulation


func _ordinary_combat_bytes(simulation) -> String:
	# Mirrors GameSimulation._combat_state_hash(), but compares the actual
	# canonical serialized bytes as well as the production SHA-256 tripwire.
	return JSON.stringify({
		"level_tick": simulation._level_tick,
		"players": simulation._players,
		"enemies": simulation._enemies,
		"projectiles": simulation._projectiles,
		"common_projectile_slots": simulation._common_projectile_slots,
		"pickups": simulation._pickups,
		"spawned_waves": simulation._spawned_waves,
		"authored_spawn_slot": simulation._authored_spawn_slot,
		"supplemental_spawned": simulation._supplemental_spawned,
		"platform_x_fp": simulation._platform_x_fp,
		"platform_y_fp": simulation._platform_y_fp,
		"platform_velocity_x_fp": simulation._platform_velocity_x_fp,
		"platform_acceleration_x_fp": simulation._platform_acceleration_x_fp,
		"level_total_entities": simulation._level_total_entities,
		"level_killed_entities": simulation._level_killed_entities,
		"level_escaped_entities": simulation._level_escaped_entities,
		"level_resolved": simulation._level_resolved,
		"level_resolution_tick": simulation._level_resolution_tick,
		"group_kill_counts": simulation._group_kill_counts,
		"cohort_kill_counts": simulation._cohort_kill_counts,
	})


func _expect_rejection(result: Dictionary, reason: String, message: String) -> void:
	_expect(
		not bool(result.get("accepted", false))
		and String(result.get("reason", "")) == reason,
		"%s (expected %s, got %s)" % [
			message,
			reason,
			String(result.get("reason", "<missing>")),
		]
	)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

extends SceneTree

const Simulation := preload("res://src/sim/game_simulation.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_mode_three_hit_ownership_and_rng_suppression()
	_test_perfect_reveal_deadlines_warp_and_shop()
	_test_miss_resets_perfect_chain()
	_test_multiplayer_perfect_candidate_ownership()
	_test_alien_three_projectile_audio()
	if _failures.is_empty():
		print("LEVEL 8 BONUS TESTS PASSED")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _test_mode_three_hit_ownership_and_rng_suppression() -> void:
	var simulation := _new_level_eight("coop", 801)
	if simulation == null:
		return
	var initial := simulation.get_snapshot()
	_expect(initial.level_eight_bonus.active, "level 8 should publish its mode-3 controller")
	_expect(
		int(initial.level_eight_bonus.players[0].total_targets) == 20
		and int(initial.level_eight_bonus.players[1].total_targets) == 20,
		"each participating session should own the authored target total"
	)
	var before_rng: Dictionary = simulation._rng.snapshot()
	var enemy: Dictionary = simulation._enemies[0]
	simulation._kill_enemy(enemy, 1)
	var after := simulation.get_snapshot()
	_expect(
		int(after.level_eight_bonus.players[0].actual_hits) == 0
		and int(after.level_eight_bonus.players[1].actual_hits) == 1,
		"a mode-3 death should credit only the killing projectile owner"
	)
	_expect(
		int(simulation._progression_for_seat(1).score) == 200,
		"the P2-owned mode-3 target should retain its authored 200-point kill score (got %d)" % int(simulation._progression_for_seat(1).score)
	)
	_expect(simulation._pickups.is_empty(), "mode 3 should never create an ordinary bonus drop")
	_expect(
		simulation._rng.snapshot() == before_rng,
		"mode-3 death should consume neither firing nor bonus-drop RNG"
	)


func _test_perfect_reveal_deadlines_warp_and_shop() -> void:
	var simulation := _new_level_eight("solo", 802)
	if simulation == null:
		return
	var progression: Dictionary = simulation._progression_for_seat(0)
	progression.score_multiplier = 2
	progression.score_multiplier_ticks = 10000
	progression.money = 50
	for enemy_value in simulation._enemies.duplicate():
		simulation._kill_enemy(enemy_value as Dictionary, 0)
	_expect(
		simulation._level_resolution_tick - simulation._tick == 180,
		"mode 3 should retain the executable-pinned 3000-ms completion hold"
	)
	simulation._level_resolution_tick = simulation._tick
	var started := simulation.step()
	_expect(
		started.level_eight_bonus.result_initialized
		and str(started.level_eight_bonus.header)
		== "B O N U S   L E V E L   R E S U L T S",
		"result entry should publish the exact header after the strict hold"
	)
	var reveal_steps := 0
	while (
		int(simulation.get_snapshot().level_eight_bonus.players[0].displayed_hits) < 20
		and reveal_steps < 100
	):
		simulation.step()
		reveal_steps += 1
	_expect(reveal_steps == 80, "the post-decrement 3-to-0 counter should reveal every fourth update")
	_expect(
		int(progression.score) == 28000,
		"twenty kills and twenty reveals should each honor the 2x score multiplier (got %d)" % int(progression.score)
	)
	var gate_ms := int(simulation.get_snapshot().level_eight_bonus.reveal_deadline_ms)
	while simulation._simulation_milliseconds() < gate_ms:
		simulation.step()
	_expect(
		not bool(simulation.get_snapshot().level_eight_bonus.players[0].perfect_awarded),
		"the perfect reward must not fire at deadline equality"
	)
	simulation.step()
	var perfect := simulation.get_snapshot()
	_expect(
		perfect.level_eight_bonus.players[0].perfect_awarded
		and int(perfect.level_eight_bonus.players[0].perfect_reward) == 20000
		and int(progression.score) == 48000,
		"the first perfect should award 10,000 times the current multiplier exactly once (reward %d score %d)" % [int(perfect.level_eight_bonus.players[0].perfect_reward), int(progression.score)]
	)
	_expect(
		int(perfect.profile_stats[0].bonus_rounds) == 1
		and int(perfect.profile_stats[0].perfect_bonus_rounds) == 1
		and int(perfect.profile_stats[0].level_eight_perfects) == 1,
		"result entry and a perfect should emit exactly one total/perfect profile delta"
	)
	_expect(
		int(progression.level_eight_perfect_reward_indices[0]) == 1
		and int(progression.level_eight_next_perfect_rewards[0]) == 25000,
		"a perfect should advance the next reward from 10,000 to 25,000"
	)
	var result_deadline_ms := int(perfect.level_eight_bonus.result_deadline_ms)
	while simulation._simulation_milliseconds() < result_deadline_ms:
		simulation.step()
	_expect(
		simulation.get_snapshot().phase == Simulation.PHASE_LEVEL,
		"the 4000-ms result extension should survive deadline equality"
	)
	simulation.step()
	_expect(
		simulation.get_snapshot().phase == Simulation.PHASE_WARP,
		"the first strict post-result update should enter ordinary Warp"
	)
	simulation._warp_malfunction_interval = 0
	for update_index in range(399):
		simulation.step()
	_expect(
		simulation.get_snapshot().phase == Simulation.PHASE_WARP,
		"the retail Warp should remain active through update 399"
	)
	simulation.step()
	var shopped := simulation.get_snapshot()
	_expect(
		shopped.phase == Simulation.PHASE_SHOP
		and int(shopped.shop.active_seat_id) == 0
		and int(shopped.level_id) == 8,
		"Warp update 400 should enter the money-and-fighter-eligible second shop"
	)


func _test_miss_resets_perfect_chain() -> void:
	var simulation := _new_level_eight("solo", 803, [{
		"level_eight_perfect_reward_index": 3,
	}])
	if simulation == null:
		return
	var enemies := simulation._enemies.duplicate()
	for index in range(enemies.size()):
		if index == enemies.size() - 1:
			simulation._escape_enemy(enemies[index] as Dictionary)
		else:
			simulation._kill_enemy(enemies[index] as Dictionary, 0)
	simulation._level_resolution_tick = simulation._tick
	simulation.step()
	var guard := 0
	while simulation.get_snapshot().phase == Simulation.PHASE_LEVEL and guard < 500:
		simulation.step()
		guard += 1
	var snapshot := simulation.get_snapshot()
	_expect(snapshot.phase == Simulation.PHASE_WARP, "a miss result should still continue into Warp")
	_expect(
		int(snapshot.level_eight_bonus.players[0].actual_hits) == 19
		and int(snapshot.level_eight_bonus.players[0].misses) == 1,
		"opcode-6 deactivation should resolve as total minus owner hits"
	)
	_expect(
		int(simulation._level_eight_perfect_indices[0]) == 0
		and int(simulation._progression_for_seat(0).level_eight_next_perfect_rewards[0]) == 10000,
		"any miss should reset the next-perfect chain to 10,000"
	)
	_expect(
		int(snapshot.profile_stats[0].bonus_rounds) == 1
		and int(snapshot.profile_stats[0].level_eight_perfects) == 0,
		"a miss should increment total rounds without mutating the perfect counter"
	)


func _test_multiplayer_perfect_candidate_ownership() -> void:
	var simulation := _new_level_eight("coop", 804)
	if simulation == null:
		return
	for enemy_value in simulation._enemies.duplicate():
		simulation._kill_enemy(enemy_value as Dictionary, 1)
	simulation._level_resolution_tick = simulation._tick
	simulation.step()
	var guard := 0
	while (
		not bool(simulation.get_snapshot().level_eight_bonus.players[1].perfect_awarded)
		and guard < 200
	):
		simulation.step()
		guard += 1
	var p2_perfect := simulation.get_snapshot()
	_expect(
		int(p2_perfect.level_eight_bonus.players[0].actual_hits) == 0
		and int(p2_perfect.level_eight_bonus.players[1].actual_hits) == 20
		and p2_perfect.level_eight_bonus.players[1].perfect_awarded,
		"co-op should preserve P2 projectile ownership through its perfect award"
	)
	_expect(
		int(p2_perfect.profile_stats[0].level_eight_perfects) == 0
		and int(p2_perfect.profile_stats[1].level_eight_perfects) == 1,
		"co-op profile deltas should belong to the perfect projectile owner"
	)

	# Exercise the executable's otherwise physically rare same-update tie: its
	# scan visits P0 then P1 and retains P1 as the current candidate.
	var tied := _new_level_eight("coop", 805)
	if tied == null:
		return
	for counters_value in tied._level_eight_result_players:
		var counters: Dictionary = counters_value
		counters.actual_hits = 20
		counters.displayed_hits = 20
		counters.perfect_awarded = false
	tied._level_eight_result_initialized = true
	tied._level_eight_reveal_deadline_ms = -1
	tied._level_eight_result_deadline_ms = 100000
	tied._step_level_eight_results()
	_expect(
		not bool(tied._level_eight_result_players[0].perfect_awarded)
		and bool(tied._level_eight_result_players[1].perfect_awarded),
		"when both sessions are eligible, the current update should select P1"
	)
	tied._step_level_eight_results()
	_expect(
		bool(tied._level_eight_result_players[0].perfect_awarded),
		"P0's independent one-shot should remain eligible on the following update"
	)


func _test_alien_three_projectile_audio() -> void:
	var simulation := Simulation.new()
	_expect(simulation.configure({
		"mode": "solo",
		"difficulty": "normal",
		"collision_mode": "simple",
		"seed": 901,
		"start_level": 9,
		"end_level": 10,
		"record_replay": false,
	}), "level-9 audio simulation should configure")
	if not simulation._configured:
		return
	simulation.step()
	simulation._events.clear()
	simulation._fire_enemy_projectile(simulation._enemies[0])
	_expect(
		not simulation._events.is_empty()
		and str(simulation._events[-1].get("sfx_key", "")) == "alienshoot10",
		"ALIEN_3 ordinary projectiles should emit the traced alienshoot10 cue"
	)


func _new_level_eight(
	mode: String,
	seed: int,
	seats: Array = []
) -> GameSimulation:
	var simulation := Simulation.new()
	_expect(simulation.configure({
		"mode": mode,
		"difficulty": "normal",
		"collision_mode": "simple",
		"seed": seed,
		"start_level": 8,
		"end_level": 10,
		"record_replay": true,
		"seats": seats,
	}), "level-8 %s simulation should configure: %s" % [mode, simulation.get_last_error()])
	if not simulation._configured:
		return null
	simulation.step()
	return simulation


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

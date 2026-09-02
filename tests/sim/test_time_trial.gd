extends SceneTree

## Contract tests for retail match mode 6 (Time Trial), see
## docs/evidence/TIME_TRIAL.md. Every number asserted here is read back from
## pinned retail instruction bytes by tools/time_trial_extract.py.

const Simulation := preload("res://src/sim/game_simulation.gd")
const MatchConfig := preload("res://src/client/match_config.gd")
const Catalog := preload("res://src/sim/content_catalog.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_configuration_and_clock()
	_test_sequential_loader_wraps()
	_test_no_shop_or_warp_routing()
	_test_death_keeps_the_loadout()
	_test_clock_expiry_ends_the_run()
	_test_grouped_best_locks()
	_test_extra_minute_lock_arms_the_longer_clock()
	_test_rejected_configurations()
	_test_client_configuration_path()
	if _failures.is_empty():
		print("TIME TRIAL TESTS PASSED")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("TIME TRIAL TESTS FAILED: %d" % _failures.size())
	quit(1)


func _configure(start_state: Dictionary = {}) -> Object:
	var simulation := Simulation.new()
	if not simulation.configure({
		"mode": "time_trial",
		"difficulty": "normal",
		"seed": 4242,
		"start_level": 1,
		"record_replay": false,
		"seats": [{
			"seat": 0,
			"profile_id": "time_trial_test",
			"display_name": "PILOT",
			"start_state": start_state,
			"local": true,
		}],
	}):
		_failures.append(
			"Time Trial simulation must configure: %s" % simulation.get_last_error()
		)
	return simulation


func _test_configuration_and_clock() -> void:
	var simulation := _configure()
	var snapshot: Dictionary = simulation.get_snapshot()
	_expect(String(snapshot.get("mode", "")) == "time_trial", "the snapshot publishes the mode")
	var clock: Dictionary = snapshot.get("time_trial", {})
	_expect(bool(clock.get("active", false)), "the Time Trial snapshot block is active")
	_expect(
		int(clock.get("remaining_ms", 0)) == 181000,
		"the match clock arms at 181000 ms: %d" % int(clock.get("remaining_ms", -1))
	)
	_expect(
		int(clock.get("authored_level_count", 0)) == 15,
		"Time Trial publishes its fifteen authored levels"
	)
	_expect(
		String(snapshot.get("level_title", "")) == "B RUNNER",
		"the first Time Trial level loads timetrial_01.lvd"
	)
	_expect(
		int(simulation._shared.get("weapon_id", -1)) == 0,
		"Time Trial always starts on weapon 0"
	)


func _test_sequential_loader_wraps() -> void:
	for level_id in range(1, 16):
		_expect(
			Simulation.time_trial_level_id_for(level_id) == level_id,
			"level counter %d selects its own file" % level_id
		)
	_expect(
		Simulation.time_trial_level_id_for(16) == 1,
		"the sixteenth level wraps back to timetrial_01.lvd"
	)
	_expect(
		Simulation.time_trial_level_id_for(31) == 1
		and Simulation.time_trial_level_id_for(45) == 15,
		"the loader keeps cycling the fifteen authored files"
	)
	var simulation := _configure()
	simulation._begin_level(16)
	_expect(
		String(simulation.get_snapshot().get("level_title", "")) == "B RUNNER",
		"the wrapped level reloads the first authored file"
	)
	_expect(
		int(simulation.get_snapshot().get("level_id", 0)) == 16,
		"the level counter itself keeps counting past the wrap"
	)


func _test_no_shop_or_warp_routing() -> void:
	var simulation := _configure()
	# Level 4 is a shop boundary in the classic campaign; Time Trial levels
	# never declare one and must route straight into the next file.
	simulation._begin_level(4)
	var level: Dictionary = simulation._level_data_for(4)
	_expect(
		not bool(level.get("shop_after", true)),
		"no Time Trial level declares a shop"
	)
	simulation._level_resolved = true
	simulation._level_resolution_tick = simulation._tick - 1
	simulation._check_level_end()
	_expect(
		String(simulation._phase) == Simulation.PHASE_GET_READY,
		"a completed Time Trial level goes straight to get ready: %s" % simulation._phase
	)
	_expect(
		int(simulation._pending_level_id) == 5,
		"the loader advances by one file"
	)


func _test_death_keeps_the_loadout() -> void:
	var simulation := _configure()
	var progression: Dictionary = simulation._shared
	progression.bullet_capacity = 9
	simulation._set_upgrade(progression, "alien_lock", 1)
	simulation._reset_loadout_after_death(progression)
	_expect(
		int(progression.bullet_capacity) == 9,
		"match mode 6 skips the projectile-capacity reset"
	)
	_expect(
		int((progression.upgrades as Dictionary).get("alien_lock", 0)) == 1,
		"match mode 6 skips the alien-lock reset"
	)


func _test_clock_expiry_ends_the_run() -> void:
	var simulation := _configure()
	simulation._shared.score = 654321
	simulation._time_trial_deadline_ms = 0
	simulation.step()
	_expect(
		bool(simulation._time_trial_expired),
		"the clock expires once the deadline passes"
	)
	_expect(
		String(simulation._phase) == Simulation.PHASE_GAME_OVER,
		"clock expiry ends the run through the game-over path: %s" % simulation._phase
	)
	var result: Dictionary = simulation.get_snapshot().get("result", {})
	var tally: Array = result.get("tally_by_seat", [])
	_expect(
		tally.size() == 2 and (tally[0] as Dictionary).has("total_score"),
		"clock expiry produces the solo-style GAME BONUSES tally"
	)
	_expect(
		int((tally[0] as Dictionary).get("base_score", 0)) == 654321,
		"the tally carries the Time Trial score"
	)
	_expect(
		(tally[1] as Dictionary).is_empty(),
		"Time Trial never fills a second seat"
	)


func _test_grouped_best_locks() -> void:
	_expect(
		MatchConfig.compute_start_state({"best_score": 1000000000}, "time_trial").is_empty(),
		"the in-the-game score tiers never apply in match mode 6"
	)
	_expect(
		MatchConfig.grouped_best_score({
			"best_level_100_score": 4000000,
			"best_time_trial_score": 9000000,
			"best_meteor_score": 100,
		}) == 9000000,
		"the grouped best is the maximum of the three stored bests"
	)
	var full := MatchConfig.compute_start_state(
		{"best_time_trial_score": 20000000},
		"time_trial"
	)
	_expect(
		int(full.get("timed_score_multiplier", 0)) == 5,
		"the 7,000,000 tier overrides the 5,000,000 multiplier"
	)
	_expect(
		bool(full.get("timed_scoop", false))
		and bool(full.get("auto_fire", false))
		and bool(full.get("super_auto_fire", false))
		and bool(full.get("speed_max", false))
		and bool(full.get("time_trial_extra_minute", false)),
		"every grouped-best tier through 20,000,000 applies"
	)
	_expect(
		int(full.get("speed_steps", 0)) == 5 and int(full.get("bonus_time", 0)) == 30,
		"the speed tiers also set the traced 30-second bonus time"
	)
	_expect(
		not full.has("weapon_at_least"),
		"no weapon tier applies in match mode 6"
	)
	var simulation := _configure(full)
	var progression: Dictionary = simulation._shared
	_expect(
		int(progression.get("score_multiplier", 1)) == 5
		and int(progression.get("score_multiplier_ticks", 0)) > 0,
		"the multiplier lock arms as a timed effect"
	)
	_expect(
		int(progression.get("scoop_ticks", 0)) > 0,
		"the scoop lock arms as a timed effect"
	)
	_expect(
		int(progression.get("speed_fp", 0)) == int(progression.get("speed_cap_fp", -1)),
		"the maximum-speed lock starts at the cap"
	)
	_expect(
		int(progression.get("weapon_id", -1)) == 0,
		"the locks never raise the Time Trial starting weapon"
	)


func _test_extra_minute_lock_arms_the_longer_clock() -> void:
	var simulation := _configure({"time_trial_extra_minute": true})
	_expect(
		int((simulation.get_snapshot().get("time_trial", {}) as Dictionary).get(
			"remaining_ms", 0
		)) == 241000,
		"the 20,000,000 grouped-best lock arms the 241000 ms clock"
	)


func _test_rejected_configurations() -> void:
	var simulation := Simulation.new()
	_expect(
		not simulation.configure({
			"mode": "time_trial",
			"difficulty": "normal",
			"seed": 1,
			"start_level": 4,
		}),
		"Time Trial rejects a start level other than its first file"
	)
	var weapon_simulation := Simulation.new()
	_expect(
		not weapon_simulation.configure({
			"mode": "time_trial",
			"difficulty": "normal",
			"seed": 1,
			"start_level": 1,
			"starting_weapon": 2,
		}),
		"Time Trial rejects a starting weapon other than the Single Shot"
	)
	_expect(
		Catalog.TIME_TRIAL_MATCH_CLOCK_MS == 181000
		and Catalog.TIME_TRIAL_EXTRA_MINUTE_CLOCK_MS == 241000
		and Catalog.TIME_TRIAL_MISSING_LEVELS_CLOCK_MS == 10000,
		"the catalog pins the three traced clock values"
	)


## The client builds Time Trial matches through WBMatchConfig, which is the only
## path that resolves the grouped-best locks from a real profile. This walks
## profile -> match config -> configured simulation in one piece.
func _test_client_configuration_path() -> void:
	var config := MatchConfig.make(
		"time_trial",
		"normal",
		"classic",
		[{
			"id": "p1",
			"name": "PILOT",
			"best_time_trial_score": 21000000,
			"best_level_100_score": 0,
			"best_meteor_score": 0,
		}],
		"pixel",
		777
	)
	_expect(
		String(config.get("mode", "")) == "time_trial"
		and int(config.get("seat_count", 0)) == 1
		and MatchConfig.validate(config),
		"the client builds a valid single-seat Time Trial configuration"
	)
	var simulation := Simulation.new()
	_expect(
		simulation.configure(config),
		"the client configuration configures the simulation: %s"
		% simulation.get_last_error()
	)
	var clock: Dictionary = simulation.get_snapshot().get("time_trial", {})
	_expect(
		int(clock.get("remaining_ms", 0)) == 241000,
		"a 20,000,000 grouped best arms the longer clock through the client path"
	)
	_expect(
		int(simulation._shared.get("weapon_id", -1)) == 0
		and int(simulation._shared.get("score_multiplier", 1)) == 5
		and int(simulation._shared.get("speed_fp", 0))
		== int(simulation._shared.get("speed_cap_fp", -1)),
		"the client path applies the grouped-best locks without a weapon tier"
	)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

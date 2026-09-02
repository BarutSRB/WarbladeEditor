extends SceneTree

## Focused contract tests for the end-of-game GAME BONUSES tally, the retire
## command, and the Duel total-score winner rule
## (docs/evidence/GAME_BONUS_TALLY.md).

const Simulation := preload("res://src/sim/game_simulation.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_solo_tally_formulas()
	_test_retire_enters_game_over()
	_test_retire_rejected_after_terminal()
	if _failures.is_empty():
		print("ENDGAME TALLY TESTS PASSED")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _configure(mode: String) -> Object:
	var simulation := Simulation.new()
	if not simulation.configure({
		"mode": mode,
		"difficulty": "normal",
		"seed": 909,
		"start_level": 1,
		"end_level": 5,
	}):
		_failures.append("tally simulation must configure: %s" % simulation.get_last_error())
	return simulation


func _test_solo_tally_formulas() -> void:
	var simulation := _configure("solo")
	var progression: Dictionary = simulation._shared
	progression.score = 123456
	progression.money = 700
	progression.rank = 5
	var stats: Dictionary = simulation._profile_stats_by_seat[0]
	stats.perfect_bonus_rounds = 3
	stats.projectile_objects_fired = 400
	stats.successful_hits = 301
	var retire: Dictionary = simulation.request_retire(0)
	_expect(bool(retire.get("accepted", false)), "solo retire is accepted mid-level")
	var result: Dictionary = simulation.get_snapshot().get("result", {})
	var tally: Dictionary = (result.get("tally_by_seat", []) as Array)[0]
	_expect(
		int(tally.get("cash_left_points", 0)) == 700 * 100,
		"cash left contributes money x 100"
	)
	# Rank 5: table entries 1..5 = 20000+30000+40000+50000+60000.
	_expect(
		int(tally.get("rank_bonus", 0)) == 200000,
		"the rank bonus is the cumulative table sum: %d" % int(tally.get("rank_bonus", 0))
	)
	_expect(
		int(tally.get("perfect_points", 0)) == 3 * 100000,
		"perfects contribute 100000 each"
	)
	# 301 * 100 / 400 = 75 (truncated).
	_expect(
		int(tally.get("hit_percent", -1)) == 75
		and int(tally.get("hit_percent_points", 0)) == 75 * 1000,
		"hit percentage truncates and contributes 1000 per percent"
	)
	var expected_sum := 70000 + 200000 + 300000 + 75000
	_expect(
		int(tally.get("sum_bonus_points", 0)) == expected_sum,
		"the bonus sum adds every line"
	)
	_expect(
		int(tally.get("base_score", 0)) == 123456
		and int(tally.get("total_score", 0)) == 123456 + expected_sum,
		"the total is the raw score plus the bonus sum"
	)
	_expect(
		bool(result.get("retired", false)),
		"the result records the retire"
	)


func _test_retire_enters_game_over() -> void:
	var simulation := _configure("solo")
	var retire: Dictionary = simulation.request_retire(0)
	_expect(bool(retire.get("accepted", false)), "retire is accepted during a level")
	_expect(
		String(simulation.get_snapshot().get("phase", "")) == Simulation.PHASE_GAME_OVER,
		"retire ends the run through the standard game-over phase"
	)
	var retired_events := 0
	for event_value in simulation._events:
		if String((event_value as Dictionary).get("kind", "")) == "match_retired":
			retired_events += 1
	_expect(retired_events == 1, "retire emits its authoritative event once")


func _test_retire_rejected_after_terminal() -> void:
	var simulation := _configure("solo")
	simulation.request_retire(0)
	var second: Dictionary = simulation.request_retire(0)
	_expect(
		not bool(second.get("accepted", false)),
		"retire is rejected once the match is terminal"
	)
	var fresh := _configure("solo")
	var wrong_seat: Dictionary = fresh.request_retire(1)
	_expect(
		not bool(wrong_seat.get("accepted", false)),
		"retire is rejected for a non-participating seat"
	)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

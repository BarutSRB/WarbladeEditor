extends SceneTree

## Focused contract tests for the retail letter awards
## (docs/evidence/LETTER_AWARDS.md): per-collect scoring, the strict
## consecutive EXTRA / ARTXE chains, SUPER variants, and the repeating
## all-collected award.

const Simulation := preload("res://src/sim/game_simulation.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_per_collect_scoring()
	_test_forward_sequence_award()
	_test_reverse_sequence_award()
	_test_broken_sequence_gives_no_award()
	_test_super_awards_when_capped()
	_test_all_collected_award_repeats()
	if _failures.is_empty():
		print("LETTER AWARD TESTS PASSED")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _make_simulation() -> Object:
	var simulation := Simulation.new()
	if not simulation.configure({
		"mode": "solo",
		"difficulty": "normal",
		"seed": 777,
		"start_level": 1,
		"end_level": 5,
	}):
		_failures.append("letter test simulation must configure: %s" % simulation.get_last_error())
	return simulation


func _shared(simulation: Object) -> Dictionary:
	return simulation._shared


func _collect(simulation: Object, letter_id: int) -> void:
	simulation._apply_letter_bonus(letter_id, _shared(simulation), 0)


func _test_per_collect_scoring() -> void:
	var simulation := _make_simulation()
	var progression := _shared(simulation)
	var base := int(progression.score)
	_collect(simulation, 0)
	_expect(
		int(progression.score) == base,
		"a fresh letter collect scores nothing, only sets its flag"
	)
	_collect(simulation, 0)
	_expect(
		int(progression.score) == base + 100,
		"a duplicate letter awards the traced 100 points"
	)
	progression.score_multiplier = 5
	_collect(simulation, 0)
	_expect(
		int(progression.score) == base + 100 + 500,
		"the active score multiplier applies to the duplicate letter score"
	)
	progression.score_multiplier = 1


func _test_forward_sequence_award() -> void:
	var simulation := _make_simulation()
	var progression := _shared(simulation)
	progression.lives = 1
	progression.armour_fp = 0
	for letter_id in [0, 1, 2, 3, 4]:
		_collect(simulation, letter_id)
	_expect(
		int(progression.lives) == Simulation.MAX_FIGHTERS
		and int(progression.armour_fp) == Simulation.MAX_ARMOUR_CHARGES * Simulation.FP_ONE,
		"the strict forward E-X-T-R-A chain fills fighters and armour to their caps"
	)
	var award_events := _events_of_kind(simulation, "letter_sequence_completed")
	_expect(
		award_events.size() == 1
		and String((award_events[0] as Dictionary).get("award", "")) == "extra",
		"forward completion emits the extra award event"
	)


func _test_reverse_sequence_award() -> void:
	var simulation := _make_simulation()
	var progression := _shared(simulation)
	progression.lives = 1
	progression.armour_fp = 0
	for letter_id in [4, 3, 2, 1, 0]:
		_collect(simulation, letter_id)
	_expect(
		int(progression.lives) == Simulation.MAX_FIGHTERS,
		"the strict reverse A-R-T-X-E chain fills fighters to the cap"
	)
	var award_events := _events_of_kind(simulation, "letter_sequence_completed")
	_expect(
		award_events.size() == 1
		and String((award_events[0] as Dictionary).get("award", "")) == "artxe",
		"reverse completion emits the artxe award event"
	)


func _test_broken_sequence_gives_no_award() -> void:
	var simulation := _make_simulation()
	var progression := _shared(simulation)
	progression.lives = 1
	progression.armour_fp = 0
	# E, X, R, T, A: the forward chain breaks at R (needs T first).
	for letter_id in [0, 1, 3, 2, 4]:
		_collect(simulation, letter_id)
	var award_events := _events_of_kind(simulation, "letter_sequence_completed")
	_expect(
		award_events.is_empty(),
		"a broken consecutive order completes no chain"
	)
	# The all-collected award still fires for the five flags.
	_expect(
		int(progression.lives) == 2,
		"all five letters in any order still grant the fighter award"
	)


func _test_super_awards_when_capped() -> void:
	var simulation := _make_simulation()
	var progression := _shared(simulation)
	progression.lives = Simulation.MAX_FIGHTERS
	progression.armour_fp = Simulation.MAX_ARMOUR_CHARGES * Simulation.FP_ONE
	var base := int(progression.score)
	for letter_id in [0, 1, 2, 3, 4]:
		_collect(simulation, letter_id)
	# All five are fresh collects (no per-letter score); the capped sequence
	# awards the SUPER score and the capped all-collected awards its score.
	var expected := base + 5000000 + 1000000
	_expect(
		int(progression.score) == expected,
		"capped fighters and armour route the sequence and all-collected awards to scores: %d != %d"
		% [int(progression.score), expected]
	)
	var award_events := _events_of_kind(simulation, "letter_sequence_completed")
	_expect(
		award_events.size() == 1
		and String((award_events[0] as Dictionary).get("award", "")) == "super_extra",
		"the capped forward completion is the SUPER EXTRA variant"
	)


func _test_all_collected_award_repeats() -> void:
	var simulation := _make_simulation()
	var progression := _shared(simulation)
	progression.lives = 1
	progression.armour_fp = 0
	# Unordered so no chain completes; the fifth letter grants a fighter.
	for letter_id in [0, 2, 4, 1, 3]:
		_collect(simulation, letter_id)
	_expect(int(progression.lives) == 2, "the all-collected award grants one fighter")
	var bonus_time_before := int(progression.bonus_time)
	# Retail keeps the five flags set, so one more letter re-fires the award.
	_collect(simulation, 2)
	_expect(
		int(progression.lives) == 3,
		"letters collected after completion re-trigger the award"
	)
	_expect(
		int(progression.bonus_time) >= bonus_time_before,
		"the fighter branch feeds the clamped bonus-time grant"
	)
	var all_events := _events_of_kind(simulation, "letters_all_collected")
	_expect(
		all_events.size() == 2,
		"every completion pass emits its award event: %d" % all_events.size()
	)


func _events_of_kind(simulation: Object, kind: String) -> Array:
	var matched: Array = []
	for event_value in simulation._events:
		var event := event_value as Dictionary
		if String(event.get("kind", "")) == kind:
			matched.append(event)
	return matched


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

extends SceneTree

## Focused contract tests for the profile lock start-state
## (docs/evidence/PROFILE_LOCKS.md): the evaluator output applied at
## configure, drop-table exclusions, and the shop-exit Auto Fire rule.

const Simulation := preload("res://src/sim/game_simulation.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_start_state_application()
	_test_drop_exclusions()
	_test_shop_exit_auto_fire_reset()
	_test_evaluator_output()
	if _failures.is_empty():
		print("PROFILE LOCK TESTS PASSED")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _configure_with_start_state(start_state: Dictionary) -> Object:
	var simulation := Simulation.new()
	if not simulation.configure({
		"mode": "solo",
		"difficulty": "normal",
		"seed": 606,
		"start_level": 1,
		"end_level": 5,
		"seats": [{
			"seat": 0,
			"profile_id": "locked",
			"start_state": start_state,
		}],
	}):
		_failures.append(
			"lock simulation must configure: %s" % simulation.get_last_error()
		)
	return simulation


func _test_start_state_application() -> void:
	var simulation := _configure_with_start_state({
		"bullet_capacity": 10,
		"speed_steps": 3,
		"auto_fire": true,
		"weapon_at_least": 2,
		"armour_charges": 1,
		"money": 1000,
		"bullet_speed_up": true,
		"gem_counter": true,
		"autofire_through_shop": true,
	})
	var progression: Dictionary = simulation._shared
	_expect(int(progression.bullet_capacity) == 10, "lock bullets apply")
	_expect(
		int(progression.speed_fp)
		== int(simulation._difficulty.player_base_speed_fp)
		+ 3 * int(progression.speed_step_fp),
		"lock speed steps apply from the difficulty base"
	)
	_expect(bool(progression.auto_fire), "lock auto fire applies")
	_expect(int(progression.weapon_id) == 2, "lock weapon floor applies")
	_expect(
		int(progression.armour_fp) == Simulation.FP_ONE,
		"lock armour charge applies"
	)
	_expect(int(progression.money) == 1000, "lock money applies")
	_expect(
		int(progression.bullet_speed_fp)
		== Simulation.FP_ONE + (Simulation.FP_ONE >> 2),
		"lock bullet speed is the traced 1.25x"
	)
	_expect(
		int(progression.upgrades.get("gem_counter", 0)) == 1
		and int(progression.upgrades.get("autofire_through_shop", 0)) == 1,
		"lock display and shop flags become upgrades"
	)
	_expect(
		not progression.has("start_state_pending"),
		"the pending start state is consumed at configure"
	)


func _test_drop_exclusions() -> void:
	var simulation := _configure_with_start_state({
		"excluded_bonus_types": [12, 13, 14],
	})
	for draw in range(200):
		var selected: Dictionary = simulation._select_retail_bonus()
		var bonus_type := int(selected.get("id", -1))
		if bonus_type in [12, 13, 14]:
			_failures.append(
				"excluded bonus type %d must never be selected" % bonus_type
			)
			return


func _test_shop_exit_auto_fire_reset() -> void:
	var plain := _configure_with_start_state({})
	var progression: Dictionary = plain._shared
	progression.auto_fire = true
	plain._apply_shop_exit_auto_fire_reset()
	_expect(
		not bool(progression.auto_fire),
		"auto fire does not survive the shop by default"
	)
	var locked := _configure_with_start_state({"autofire_through_shop": true})
	var locked_progression: Dictionary = locked._shared
	locked_progression.auto_fire = true
	locked._apply_shop_exit_auto_fire_reset()
	_expect(
		bool(locked_progression.auto_fire),
		"the 1,000-games lock keeps auto fire through the shop"
	)
	var super_fire := _configure_with_start_state({"super_auto_fire": true})
	var super_progression: Dictionary = super_fire._shared
	super_fire._apply_shop_exit_auto_fire_reset()
	_expect(
		bool(super_progression.auto_fire),
		"purchased Super Auto Fire always persists through the shop"
	)


func _test_evaluator_output() -> void:
	var profile := {
		"id": "p1",
		"name": "P1",
		"best_score": 260000000,
		"games_played": 26000,
		"secrets_seen": (1 << 30) - 1,
		"highest_rank": 5,
		"fastest_meteor_ms": 0,
	}
	var start_state: Dictionary = WBMatchConfig.compute_start_state(profile, "solo")
	_expect(int(start_state.get("money", 0)) == 1000, "250M tier overrides the 100M money")
	_expect(bool(start_state.get("auto_fire", false)), "10M auto fire fires")
	_expect(
		int(start_state.get("armour_charges", 0)) == 2,
		"find-all-secrets grants full armour"
	)
	_expect(
		int(start_state.get("weapon_at_least", 0)) == 4,
		"find-all-secrets grants Super Triple over the score-tier weapons"
	)
	_expect(
		bool(start_state.get("only_blue_coins", false)),
		"the 20,000-games lock arms blue-only coins"
	)
	_expect(
		(start_state.get("excluded_bonus_types", []) as Array) == [12, 13, 14],
		"the shot-off locks exclude single, double, and triple drops"
	)
	_expect(
		bool(start_state.get("secret_counter", false)),
		"above 200M the secret counter starts on"
	)
	var guest: Dictionary = WBMatchConfig.compute_start_state({}, "solo")
	_expect(guest.is_empty(), "guests have no lock state")
	var coop: Dictionary = WBMatchConfig.compute_start_state(profile, "coop")
	_expect(coop.is_empty(), "locks apply only to solo matches")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

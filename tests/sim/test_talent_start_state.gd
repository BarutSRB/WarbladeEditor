extends SceneTree

## Content v12 talent wiring: catalog validation, the grant merge rules, the
## talent-gated shop items, start-state application (alien_lock, rockets), and
## the two fidelity canaries — the 552-draw solo startup contract and twin-run
## replay-hash equality with a talent-laden configuration.

const Simulation := preload("res://src/sim/game_simulation.gd")
const Catalog := preload("res://src/sim/content_catalog.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_catalog_accepts_shipped_talents()
	_test_merge_talent_grants()
	_test_contract_normalizes_talent_fields()
	_test_shop_gating_disabled_matches_retail()
	_test_shop_gating_enabled_requires_license()
	_test_start_state_grants_apply()
	_test_startup_draw_count_unchanged()
	_test_twin_run_hash_equality_with_talents()
	if _failures.is_empty():
		print("TALENT START STATE TESTS PASSED")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failures.append("%s (expected %s, got %s)" % [message, str(expected), str(actual)])


func _base_config(talents_enabled: bool, unlocks: Array = [], grants: Dictionary = {}) -> Dictionary:
	var start_state := grants.duplicate(true)
	return {
		"mode": "solo",
		"difficulty": "normal",
		"seed": 424_242,
		"start_level": 1,
		"end_level": 8,
		"record_replay": true,
		"talents_enabled": talents_enabled,
		"seats": [{
			"seat": 0,
			"profile_id": "talent-test",
			"start_state": start_state,
			"shop_unlocks": unlocks,
		}],
	}


func _test_catalog_accepts_shipped_talents() -> void:
	var loaded: Dictionary = Catalog.load_catalog("res://content", "", false)
	_expect(bool(loaded.get("ok", false)), "content catalog loads with talents.json")
	_expect_equal(int(loaded.get("talents_version", 0)), 1, "catalog reports talents v1")
	var talents: Dictionary = loaded.get("talents", {})
	_expect_equal(
		(talents.get("shop_migration", {}) as Dictionary).get("talent_gated_effects", []),
		["enable_autofire", "enable_super_autofire", "rocket_pack", "enable_alien_lock"],
		"gated effects survive catalog validation"
	)


func _test_merge_talent_grants() -> void:
	# Profile lock dominance: the 25-bullet lock beats an 18-bullet talent.
	var merged := WBMatchConfig.merge_talent_grants(
		{"bullet_capacity": 25, "money": 500},
		{"bullet_capacity": 18.0, "money": 1000.0, "auto_fire": true, "alien_lock": true}
	)
	_expect_equal(int(merged["bullet_capacity"]), 25, "int keys take the MAX")
	_expect_equal(int(merged["money"]), 1000, "talent int wins when larger (and floats cast)")
	_expect_equal(merged.get("auto_fire"), true, "bool keys OR in")
	_expect_equal(merged.get("alien_lock"), true, "alien_lock rides the bool vocabulary")
	var untouched := WBMatchConfig.merge_talent_grants(
		{"excluded_bonus_types": [12]},
		{"excluded_bonus_types": [13], "made_up": 5}
	)
	_expect_equal(
		untouched["excluded_bonus_types"], [12],
		"talents never write excluded_bonus_types"
	)
	_expect(not untouched.has("made_up"), "unknown grant keys are dropped")


func _test_contract_normalizes_talent_fields() -> void:
	var contract := WBMatchContract.network_contract({
		"mode": "solo",
		"talents_enabled": true,
		"starting_rockets": 99,
		"seats": [{
			"shop_unlocks": ["rocket_pack", "rocket_pack", "equip_weapon", "enable_autofire"],
		}],
	})
	_expect_equal(contract.get("talents_enabled"), true, "talents_enabled rides the contract")
	_expect_equal(int(contract.get("starting_rockets", 0)), 50, "rockets clamp to the retail cap")
	_expect_equal(
		(contract.get("seats", [])[0] as Dictionary).get("shop_unlocks"),
		["enable_autofire", "rocket_pack"],
		"shop unlocks dedupe, drop ungated effects, and sort"
	)
	var time_trial_contract := WBMatchContract.network_contract({
		"mode": "time_trial",
		"talents_enabled": true,
	})
	_expect_equal(
		time_trial_contract.get("talents_enabled"), false,
		"time trial never runs talent-enabled"
	)


func _shop_effect_visible(simulation: Simulation, effect: String) -> bool:
	for item_value in simulation._shop_by_id.values():
		if String((item_value as Dictionary).get("effect", "")) == effect:
			return simulation._shop_item_is_unlocked(item_value, 0)
	return false


func _test_shop_gating_disabled_matches_retail() -> void:
	var simulation := Simulation.new()
	_expect(simulation.configure(_base_config(false)), "talent-free config configures")
	_expect(
		_shop_effect_visible(simulation, "enable_autofire"),
		"talents off: Auto Fire keeps its retail always-unlocked rule"
	)
	_expect(
		not _shop_effect_visible(simulation, "rocket_pack"),
		"talents off: Rocket Pack keeps its retail hit-percent gate"
	)


func _test_shop_gating_enabled_requires_license() -> void:
	var unlicensed := Simulation.new()
	_expect(unlicensed.configure(_base_config(true)), "talent-enabled config configures")
	_expect(
		not _shop_effect_visible(unlicensed, "enable_autofire"),
		"talents on without the license: Auto Fire is locked"
	)
	var licensed := Simulation.new()
	_expect(
		licensed.configure(_base_config(true, ["enable_autofire", "rocket_pack"])),
		"licensed config configures"
	)
	_expect(
		_shop_effect_visible(licensed, "enable_autofire"),
		"the Auto Fire license unlocks the shop item"
	)
	_expect(
		_shop_effect_visible(licensed, "rocket_pack"),
		"the Rocket Pack license replaces the retail hit-percent gate"
	)
	_expect(
		not _shop_effect_visible(licensed, "enable_super_autofire"),
		"unlicensed gated items stay locked"
	)


func _test_start_state_grants_apply() -> void:
	var simulation := Simulation.new()
	var config := _base_config(true, [], {
		"bullet_capacity": 12,
		"auto_fire": true,
		"alien_lock": true,
	})
	config["starting_rockets"] = 20
	_expect(simulation.configure(config), "grant-laden config configures")
	var shared: Dictionary = simulation.get_snapshot().get("shared", {})
	_expect_equal(int(shared.get("bullet_capacity", 0)), 12, "bullet capacity grant applies")
	_expect_equal(shared.get("auto_fire"), true, "auto fire grant applies")
	_expect_equal(int(shared.get("rockets", 0)), 20, "starting rockets grant applies")
	_expect_equal(
		int((shared.get("upgrades", {}) as Dictionary).get("alien_lock", 0)), 1,
		"the alien lock grant mirrors the shop effect"
	)


func _test_startup_draw_count_unchanged() -> void:
	var simulation := Simulation.new()
	_expect(simulation.configure(_base_config(true, ["enable_autofire"])), "canary configures")
	_expect_equal(
		int((simulation.get_snapshot().get("rng", {}) as Dictionary).get("draw_count", -1)),
		552,
		"solo startup keeps the exact 552-draw retail contract with talents on"
	)


func _test_twin_run_hash_equality_with_talents() -> void:
	var config := _base_config(true, ["enable_autofire"], {"bullet_capacity": 12})
	config["starting_rockets"] = 10
	var first := Simulation.new()
	var second := Simulation.new()
	_expect(first.configure(config.duplicate(true)), "twin one configures")
	_expect(second.configure(config.duplicate(true)), "twin two configures")
	for tick in range(600):
		first.set_input(0, Simulation.ACTION_FIRE if tick % 5 == 0 else 0)
		second.set_input(0, Simulation.ACTION_FIRE if tick % 5 == 0 else 0)
		first.step()
		second.step()
	_expect_equal(
		first.state_hash(), second.state_hash(),
		"talent-laden twin runs stay hash-identical"
	)

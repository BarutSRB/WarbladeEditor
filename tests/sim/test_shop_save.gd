extends SceneTree

## Contract tests for the retail in-shop saved game (writer `FUN_00537c80`,
## loader `FUN_005384f0`). Retail serializes a raw image of its own state block,
## so these tests pin the behavioral contract: shop-only writes, an exactly
## restored shop boundary, and a resumed run that stays bit-identical to the
## run that was never saved.

const Simulation := preload("res://src/sim/game_simulation.gd")
const SaveStore := preload("res://src/client/save_game_store.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_save_is_rejected_outside_the_shop()
	_test_restore_reproduces_the_shop_boundary()
	_test_resumed_run_matches_an_unsaved_run()
	_test_restore_rejects_foreign_saves()
	_test_slot_store_round_trip()
	if _failures.is_empty():
		print("SHOP SAVE TESTS PASSED")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("SHOP SAVE TESTS FAILED: %d" % _failures.size())
	quit(1)


func _configure(mode: String = "solo") -> Object:
	var simulation := Simulation.new()
	if not simulation.configure({
		"mode": mode,
		"difficulty": "normal",
		"collision_mode": "simple",
		"seed": 20260809,
		"start_level": 1,
		"end_level": 12,
		"starting_weapon": 8,
		"starting_lives": 999,
		"starting_money": 100,
		"record_replay": false,
	}):
		_failures.append("save simulation must configure: %s" % simulation.get_last_error())
	return simulation


## Drives the run until the first shop opens after level 4.
func _run_to_shop(simulation: Object, limit: int = 200000) -> bool:
	for _tick in range(limit):
		var snapshot: Dictionary = simulation.get_snapshot()
		var phase := String(snapshot.get("phase", ""))
		if phase == Simulation.PHASE_SHOP:
			return true
		if phase in [Simulation.PHASE_GAME_OVER, Simulation.PHASE_COMPLETE]:
			return false
		simulation.set_input(
			0,
			_combat_input(snapshot) if phase == Simulation.PHASE_LEVEL else 0
		)
		simulation.step()
	return false


## A compact aim-and-fire pilot: chase the lowest live alien and pulse fire on
## even ticks, which is enough to clear the opening levels deterministically.
func _combat_input(snapshot: Dictionary) -> int:
	var players := snapshot.get("players", []) as Array
	if players.is_empty():
		return 0
	var player := players[0] as Dictionary
	if not bool(player.get("active", false)) or not bool(player.get("alive", false)):
		return 0
	var target_x_fp: Variant = null
	for enemy_value in snapshot.get("enemies", []):
		var enemy := enemy_value as Dictionary
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


func _test_save_is_rejected_outside_the_shop() -> void:
	var simulation := _configure()
	_expect(
		simulation.export_shop_save().is_empty(),
		"a run cannot be saved during a level"
	)
	_expect(
		String(simulation.get_last_error()) == "a run can only be saved from the shop",
		"the rejection names the shop-only rule: %s" % simulation.get_last_error()
	)


func _test_restore_reproduces_the_shop_boundary() -> void:
	var simulation := _configure()
	if not _run_to_shop(simulation):
		_failures.append("the solo run must reach its first shop")
		return
	simulation._shared.money = 4321
	simulation._shared.score = 987654
	simulation._shared.bullet_capacity = 8
	var save: Dictionary = simulation.export_shop_save()
	_expect(not save.is_empty(), "the shop boundary produces a save: %s" % simulation.get_last_error())
	_expect(
		int(save.get("version", 0)) == Simulation.SHOP_SAVE_VERSION
		and String(save.get("schema", "")) == Simulation.SHOP_SAVE_SCHEMA,
		"the save publishes its version and schema"
	)
	var restored := Simulation.new()
	_expect(
		restored.restore_shop_save(save),
		"the save restores: %s" % restored.get_last_error()
	)
	_expect(
		String(restored._phase) == Simulation.PHASE_SHOP,
		"a restored run resumes in the shop: %s" % restored._phase
	)
	_expect(
		int(restored._level_id) == int(simulation._level_id)
		and int(restored._tick) == int(simulation._tick),
		"the restored run keeps its level and tick"
	)
	_expect(
		int(restored._shared.money) == 4321
		and int(restored._shared.score) == 987654
		and int(restored._shared.bullet_capacity) == 8,
		"the restored run keeps its progression"
	)
	_expect(
		restored._rng.snapshot() == simulation._rng.snapshot(),
		"the restored run keeps its RNG position"
	)
	_expect(
		restored._progression_for_seat(0) == restored._shared
		and restored._progression_for_seat(1) == restored._shared,
		"solo seats share one restored progression object"
	)
	var visible: Array = (restored.get_snapshot().get("shop", {}) as Dictionary).get("items", [])
	_expect(not visible.is_empty(), "the restored shop still offers its items")
	# Saving a resumed run must not nest the previous save inside the new one.
	var resaved: Dictionary = restored.export_shop_save()
	_expect(
		not resaved.is_empty()
		and not (resaved.get("match_config", {}) as Dictionary).has("resume_save")
		and not (resaved.get("match_config", {}) as Dictionary).has("resume_slot"),
		"re-saving a restored run does not nest the previous save"
	)


func _test_resumed_run_matches_an_unsaved_run() -> void:
	var simulation := _configure()
	if not _run_to_shop(simulation):
		_failures.append("the reference run must reach its first shop")
		return
	var save: Dictionary = simulation.export_shop_save()
	var restored := Simulation.new()
	if not restored.restore_shop_save(save):
		_failures.append("the reference save must restore: %s" % restored.get_last_error())
		return
	# Both runs leave the shop and play on with identical inputs; a saved run
	# that resumes correctly stays bit-identical to one that never stopped.
	for _tick in range(6000):
		var snapshot: Dictionary = simulation.get_snapshot()
		var mask := 0
		match String(snapshot.get("phase", "")):
			Simulation.PHASE_SHOP:
				var guard_until := int((snapshot.get("shop", {}) as Dictionary).get(
					"input_guard_until_tick",
					0
				))
				if int(snapshot.get("tick", 0)) > guard_until:
					mask = Simulation.ACTION_READY
			Simulation.PHASE_LEVEL, Simulation.PHASE_WARP_MALFUNCTION:
				mask = _combat_input(snapshot)
			Simulation.PHASE_RANK_PROMOTION:
				mask = Simulation.ACTION_FIRE
		simulation.set_input(0, mask)
		restored.set_input(0, mask)
		simulation.step()
		restored.step()
	_expect(
		String(simulation.state_hash()) == String(restored.state_hash()),
		"a resumed run stays bit-identical to the unsaved run"
	)
	_expect(
		int(simulation._level_id) == int(restored._level_id)
		and int(simulation._level_id) > 4,
		"both runs advanced past the shop"
	)


func _test_restore_rejects_foreign_saves() -> void:
	var simulation := _configure()
	if not _run_to_shop(simulation):
		_failures.append("the rejection run must reach its first shop")
		return
	var save: Dictionary = simulation.export_shop_save()
	var stale_version: Dictionary = save.duplicate(true)
	stale_version["content_version"] = int(save.get("content_version", 0)) - 1
	var stale := Simulation.new()
	_expect(
		not stale.restore_shop_save(stale_version),
		"a save written for other content is rejected"
	)
	var stale_schema: Dictionary = save.duplicate(true)
	stale_schema["schema"] = "warblade.shop-save.v0"
	var schema_simulation := Simulation.new()
	_expect(
		not schema_simulation.restore_shop_save(stale_schema),
		"a save with an unsupported schema is rejected"
	)
	var missing_state: Dictionary = save.duplicate(true)
	missing_state.erase("state")
	var missing := Simulation.new()
	_expect(
		not missing.restore_shop_save(missing_state),
		"a save without state is rejected"
	)


func _test_slot_store_round_trip() -> void:
	var simulation := _configure()
	if not _run_to_shop(simulation):
		_failures.append("the slot-store run must reach its first shop")
		return
	var save: Dictionary = simulation.export_shop_save()
	var store := SaveStore.new()
	store.configure_directory("user://test-savegames")
	_expect(not store.has_slot(3), "an unused slot starts empty")
	_expect(store.save_slot(3, save), "a slot accepts a save: %s" % store.last_error)
	_expect(store.has_slot(3), "a written slot reports as occupied")
	var loaded: Dictionary = store.load_slot(3)
	_expect(
		int(loaded.get("slot", -1)) == 3
		and String(loaded.get("schema", "")) == Simulation.SHOP_SAVE_SCHEMA,
		"a loaded slot keeps its identity"
	)
	var summaries := store.slot_summaries()
	_expect(
		summaries.size() == SaveStore.SLOT_COUNT,
		"the slot list covers every save slot"
	)
	_expect(
		bool(summaries[3].get("occupied", false))
		and String(summaries[3].get("mode", "")) == "solo"
		and int(summaries[3].get("level_id", 0)) == int(simulation._level_id),
		"the occupied slot summarizes its run"
	)
	_expect(
		not bool(summaries[0].get("occupied", true)),
		"unused slots summarize as empty"
	)
	var restored := Simulation.new()
	_expect(
		restored.restore_shop_save(loaded),
		"a slot round trip restores: %s" % restored.get_last_error()
	)
	_expect(not store.save_slot(SaveStore.SLOT_COUNT, save), "out-of-range slots are rejected")
	_expect(store.clear_slot(3), "a slot can be cleared")
	_expect(not store.has_slot(3), "a cleared slot reports as empty")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

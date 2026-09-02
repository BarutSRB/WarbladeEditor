extends SceneTree

const Simulation := preload("res://src/sim/game_simulation.gd")
const CampaignDriver := preload("res://tests/sim/test_campaign_through_thirty.gd")

const LEVEL_ID: int = 74
const GUARD_STEPS: int = 30000

var _failures: Array[String] = []


func _initialize() -> void:
	_test_level_seventy_four_public_completion()
	if _failures.is_empty():
		print("LEVEL 74 PUBLIC COMPLETION TESTS PASSED")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _test_level_seventy_four_public_completion() -> void:
	var simulation := Simulation.new()
	_expect(simulation.configure({
		"mode": "solo",
		"difficulty": "normal",
		"collision_mode": "simple",
		"seed": 740074,
		"start_level": LEVEL_ID,
		"end_level": LEVEL_ID,
		"starting_weapon": 8,
		"starting_lives": 999,
		"starting_money": 100,
		"record_replay": false,
	}), "level 74 public completion fixture should configure")
	if not simulation._configured:
		return

	for guard in range(GUARD_STEPS):
		var before: Dictionary = simulation.get_snapshot()
		var phase := String(before.get("phase", ""))
		if phase == Simulation.PHASE_COMPLETE:
			_expect(
				int((before.get("result", {}) as Dictionary).get(
					"level_reached",
					0
				)) == LEVEL_ID,
				"level 74 should complete at its configured boundary"
			)
			return
		match phase:
			Simulation.PHASE_LEVEL, Simulation.PHASE_WARP_MALFUNCTION:
				simulation.set_input(
					0,
					CampaignDriver.campaign_combat_input(before)
				)
			Simulation.PHASE_SHOP:
				var guard_until := int((before.get("shop", {}) as Dictionary).get(
					"input_guard_until_tick",
					0
				))
				simulation.set_input(
					0,
					Simulation.ACTION_READY
					if int(before.get("tick", 0)) > guard_until
					else 0
				)
			Simulation.PHASE_RANK_PROMOTION:
				simulation.set_input(0, Simulation.ACTION_FIRE)
			_:
				simulation.set_input(0, 0)

		var stepped := simulation.step()
		for event_value in stepped.get("events", []):
			var event := event_value as Dictionary
			if (
				String(event.get("kind", "")) == "level_resolved"
				and String(event.get("reason", "")) == "watchdog"
			):
				_expect(false, _watchdog_diagnostic(before))
				return

	_expect(false, "level 74 public completion exhausted its deterministic guard")


func _watchdog_diagnostic(snapshot: Dictionary) -> String:
	var remaining: Array = []
	for enemy_value in snapshot.get("enemies", []):
		var enemy := enemy_value as Dictionary
		remaining.append({
			"id": int(enemy.get("id", -1)),
			"group_id": int(enemy.get("group_id", -1)),
			"authored_state": String(enemy.get("authored_state", "")),
			"behavior_state_id": int(enemy.get("behavior_state_id", 0)),
			"dead": bool(enemy.get("dead", false)),
			"x_fp": int(enemy.get("x_fp", 0)),
			"y_fp": int(enemy.get("y_fp", 0)),
		})
	return (
		"level 74 reached the retail watchdog; resolution=%s mode_three=%s remaining=%s selected_target=%s"
		% [
			str(snapshot.get("level_resolution", {})),
			str(snapshot.get("mode_three_bonus", {})),
			str(remaining),
			str(_campaign_selected_target(snapshot)),
		]
	)


func _campaign_selected_target(snapshot: Dictionary) -> Dictionary:
	var players := snapshot.get("players", []) as Array
	if players.is_empty():
		return {}
	var player := players[0] as Dictionary
	var selected: Dictionary = {}
	var selected_y_fp := -(1 << 60)
	var target_y_limit_fp := 600 * Simulation.FP_ONE
	for enemy_value in snapshot.get("enemies", []):
		var enemy := enemy_value as Dictionary
		var enemy_y_fp := int(enemy.get("y_fp", 0))
		var candidate_limit_fp := target_y_limit_fp
		if String(enemy.get("authored_state", "")) == "hold":
			candidate_limit_fp = maxi(
				candidate_limit_fp,
				int(player.get("y_fp", 0)) - 16 * Simulation.FP_ONE
			)
		if (
			int(enemy.get("behavior_state_id", 0)) != 8
			and enemy_y_fp >= -32 * Simulation.FP_ONE
			and enemy_y_fp < candidate_limit_fp
			and (selected.is_empty() or enemy_y_fp > selected_y_fp)
		):
			selected = {
				"id": int(enemy.get("id", -1)),
				"group_id": int(enemy.get("group_id", -1)),
				"authored_state": String(enemy.get("authored_state", "")),
				"behavior_state_id": int(enemy.get("behavior_state_id", 0)),
				"x_fp": int(enemy.get("x_fp", 0)),
				"y_fp": enemy_y_fp,
			}
			selected_y_fp = enemy_y_fp
	return selected


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

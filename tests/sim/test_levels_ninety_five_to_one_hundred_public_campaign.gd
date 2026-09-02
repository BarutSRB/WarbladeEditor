extends SceneTree

const Simulation := preload("res://src/sim/game_simulation.gd")
const CampaignDriver := preload("res://tests/sim/test_campaign_through_thirty.gd")

const START_LEVEL: int = 95
const END_LEVEL: int = 100
const GUARD_STEPS: int = 100000

var _failures: Array[String] = []


func _initialize() -> void:
	_test_public_late_campaign()
	if _failures.is_empty():
		print("LEVELS 95-100 PUBLIC CAMPAIGN TESTS PASSED")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _test_public_late_campaign() -> void:
	var simulation := Simulation.new()
	_expect(simulation.configure({
		"mode": "solo",
		"difficulty": "normal",
		"collision_mode": "simple",
		"seed": 95100,
		"start_level": START_LEVEL,
		"end_level": END_LEVEL,
		"starting_weapon": 8,
		"starting_lives": 999,
		"starting_money": 100,
		"starting_rockets": 50,
		"record_replay": false,
	}), "the public levels 95-100 campaign should configure")
	if not simulation._configured:
		return

	var visited: Array[int] = []
	var prepared_level := 0
	var watchdog_levels: Array[int] = []
	for guard in range(GUARD_STEPS):
		var snapshot: Dictionary = simulation.get_snapshot()
		var phase := String(snapshot.get("phase", ""))
		if phase == Simulation.PHASE_COMPLETE:
			var result := snapshot.get("result", {}) as Dictionary
			var terminal := result.get("campaign_terminal", {}) as Dictionary
			_expect(
				visited == range(START_LEVEL, END_LEVEL + 1),
				"the public driver must visit every level from %d through 100: %s"
				% [START_LEVEL, str(visited)]
			)
			_expect(
				watchdog_levels.is_empty(),
				"levels 95-100 must resolve through gameplay, not a watchdog: %s"
				% str(watchdog_levels)
			)
			_expect(
				int(result.get("level_reached", 0)) == END_LEVEL
				and String(terminal.get("kind", "")) == "level_100"
				and bool(terminal.get("credits_required", false))
				and int((snapshot.get("level_resolution", {}) as Dictionary).get(
					"pending_level_id",
					-1
				)) == 0,
				"level 100 must terminate directly into the retail ending contract"
			)
			return

		match phase:
			Simulation.PHASE_LEVEL:
				var level_id := int(snapshot.get("level_id", 0))
				if prepared_level != level_id:
					visited.append(level_id)
					prepared_level = level_id
				simulation.set_input(
					0,
					CampaignDriver.campaign_combat_input(snapshot)
				)
			Simulation.PHASE_SHOP:
				var guard_until := int((snapshot.get("shop", {}) as Dictionary).get(
					"input_guard_until_tick",
					0
				))
				simulation.set_input(
					0,
					Simulation.ACTION_READY
					if int(snapshot.get("tick", 0)) > guard_until
					else 0
				)
			Simulation.PHASE_RANK_PROMOTION:
				simulation.set_input(0, Simulation.ACTION_FIRE)
			Simulation.PHASE_WARP_MALFUNCTION:
				simulation.set_input(
					0,
					CampaignDriver.campaign_combat_input(snapshot)
				)
			_:
				simulation.set_input(0, 0)

		var stepped := simulation.step()
		for event_value in stepped.get("events", []):
			var event := event_value as Dictionary
			if (
				String(event.get("kind", "")) == "level_resolved"
				and String(event.get("reason", "")) == "watchdog"
			):
				watchdog_levels.append(int(event.get("level_id", 0)))

	var terminal_snapshot := simulation.get_snapshot()
	var boss := terminal_snapshot.get("boss", {}) as Dictionary
	var alive_states: Dictionary = {}
	for enemy_value in terminal_snapshot.get("enemies", []):
		var enemy := enemy_value as Dictionary
		if bool(enemy.get("dead", false)):
			continue
		var state := String(enemy.get("authored_state", "unknown"))
		alive_states[state] = int(alive_states.get(state, 0)) + 1
	_expect(false, (
		"levels %d-100 exhausted %d public steps at level %d in %s; alive=%s boss=%s player=%s projectiles=%d counters=%s"
		% [
			START_LEVEL,
			GUARD_STEPS,
			int(terminal_snapshot.get("level_id", 0)),
			String(terminal_snapshot.get("phase", "unknown")),
			str(alive_states),
			str(boss),
			str((terminal_snapshot.get("players", []) as Array)[0]),
			(terminal_snapshot.get("projectiles", []) as Array).size(),
			str(terminal_snapshot.get("level_counters", {})),
		]
	))


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

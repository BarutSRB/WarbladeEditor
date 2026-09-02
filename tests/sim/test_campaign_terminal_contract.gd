extends SceneTree

const Simulation := preload("res://src/sim/game_simulation.gd")
const Protocol := preload("res://src/net/protocol_codec.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_configured_boundary_contract()
	_test_level_one_hundred_solo_contract()
	if _failures.is_empty():
		print("CAMPAIGN TERMINAL CONTRACT TESTS PASSED")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _test_configured_boundary_contract() -> void:
	var simulation: Variant = _fallback_simulation(Simulation.MODE_SOLO)
	if simulation == null:
		return
	simulation._level_id = 5
	simulation._end_level_id = 5
	simulation._pending_level_id = 6
	simulation._complete_campaign()
	var snapshot: Dictionary = simulation.get_snapshot()
	var terminal := snapshot.result.get("campaign_terminal", {}) as Dictionary
	_expect(
		int(snapshot.version) == Protocol.SNAPSHOT_VERSION
		and String(terminal.get("kind", "")) == "configured_boundary"
		and not bool(terminal.get("full_campaign_completed", true))
		and not bool(terminal.get("credits_required", true))
		and int(terminal.get("ending_mode_id", -1)) == 0
		and int(terminal.get("winner_seat_id", 0)) == -1
		and int(terminal.get("level_100_score", -1)) == 0
		and int(snapshot.level_resolution.pending_level_id) == 0,
		"configured boundaries must complete without credits or a pending level"
	)


func _test_level_one_hundred_solo_contract() -> void:
	var simulation: Variant = _fallback_simulation(Simulation.MODE_SOLO)
	if simulation == null:
		return
	simulation._level_id = 100
	simulation._end_level_id = 100
	simulation._shared.score = 12345678
	simulation._pending_level_id = 101
	simulation._complete_campaign()
	var snapshot: Dictionary = simulation.get_snapshot()
	var terminal := snapshot.result.get("campaign_terminal", {}) as Dictionary
	_expect(
		String(terminal.get("kind", "")) == "level_100"
		and bool(terminal.get("full_campaign_completed", false))
		and bool(terminal.get("credits_required", false))
		and int(terminal.get("ending_mode_id", -1)) == 0
		and int(terminal.get("winner_seat_id", 0)) == -1
		and int(terminal.get("level_100_score", 0)) == 12345678
		and int(snapshot.level_resolution.pending_level_id) == 0,
		"level 100 must publish the authoritative solo ending contract and suppress 101"
	)


func _fallback_simulation(mode: String) -> Variant:
	var simulation := Simulation.new()
	var configured := simulation.configure({
		"mode": mode,
		"difficulty": "normal",
		"coop_balance": "classic",
		"collision_mode": "simple",
		"start_level": 1,
		"end_level": 5,
		"seed": 100001,
		"content_base_path": "res://missing-terminal-contract-content",
		"allow_fallback_content": true,
	})
	_expect(
		configured,
		"terminal fixture should configure: %s" % simulation.get_last_error()
	)
	return simulation if configured else null


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

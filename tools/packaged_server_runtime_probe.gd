extends SceneTree

const NetworkSessionAdapter := preload("res://src/client/network_session_adapter.gd")
const MatchConfig := preload("res://src/client/match_config.gd")
const InputRouter := preload("res://src/client/input_router.gd")

const SCHEMA := "warblade.packaged_server_probe.v1"
const POLL_INTERVAL_SECONDS := 0.01
const STARTUP_TIMEOUT_MSEC := 12_000
const INPUT_TIMEOUT_MSEC := 5_000

var _adapter: WBNetworkSessionAdapter


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var result := _base_result()
	var arguments := _arguments()
	var host := String(arguments.get("host", ""))
	var port := int(arguments.get("port", 0))
	var token := String(arguments.get("token", ""))
	var expected_content_hash := String(arguments.get("content-hash", ""))
	var expected_end_level := int(arguments.get("end-level", 0))
	if (
		host != "127.0.0.1"
		or port < 1024
		or port > 65535
		or token.is_empty()
		or expected_content_hash.length() != 64
		or expected_end_level < 1
		or expected_end_level > MatchConfig.MAX_END_LEVEL
	):
		result.error = "The packaged server probe received an invalid endpoint contract."
		_finish(result)
		return

	_adapter = NetworkSessionAdapter.new()
	var config := MatchConfig.make(
		"solo",
		"normal",
		"classic",
		[],
		"pixel",
		1
	)
	config.end_level = expected_end_level
	if not _adapter.configure(config, {
		"host": host,
		"port": port,
		"token": token,
		"requested_seat": 0,
	}):
		result.error = _adapter.last_error()
		_finish(result)
		return
	result.configured = true
	result.content_hash_matches = _adapter.content_hash() == expected_content_hash
	if not bool(result.content_hash_matches):
		result.error = "The probe and packaged server loaded different content."
		_finish(result)
		return

	var startup_deadline := Time.get_ticks_msec() + STARTUP_TIMEOUT_MSEC
	while Time.get_ticks_msec() < startup_deadline:
		_adapter.poll()
		var snapshot := _adapter.get_snapshot()
		if _adapter.is_ready() and not snapshot.is_empty():
			result.authenticated = true
			result.authoritative_end_level = int(snapshot.get("end_level_id", 0))
			result.match_contract_valid = (
				int(result.authoritative_end_level) == expected_end_level
			)
			result.initial_tick = int(snapshot.get("tick", -1))
			result.initial_x_fp = _player_x(snapshot, 0)
			result.state_hash_valid = String(snapshot.get("state_hash", "")).length() == 64
			result.seat_claimed = (
				not bool(snapshot.get("waiting_for_seats", true))
				and int(snapshot.get("required_seats", 0)) == 1
				and int(result.initial_x_fp) >= 0
			)
			break
		if not _adapter.last_error().is_empty():
			break
		await create_timer(POLL_INTERVAL_SECONDS).timeout
	if not bool(result.authenticated):
		result.error = (
			_adapter.last_error()
			if not _adapter.last_error().is_empty()
			else "The packaged server did not authenticate the probe before timeout."
		)
		_finish(result)
		return
	if not bool(result.seat_claimed):
		result.error = "The packaged server did not grant authoritative seat zero."
		_finish(result)
		return
	if not bool(result.match_contract_valid):
		result.error = "The packaged server did not honor the requested campaign boundary."
		_finish(result)
		return
	if not bool(result.state_hash_valid):
		result.error = "The packaged server snapshot omitted its authoritative state hash."
		_finish(result)
		return

	result.input_submitted = _adapter.submit_input(0, InputRouter.INPUT_RIGHT)
	if not bool(result.input_submitted):
		result.error = "The packaged server probe could not submit input."
		_finish(result)
		return
	var input_deadline := Time.get_ticks_msec() + INPUT_TIMEOUT_MSEC
	while Time.get_ticks_msec() < input_deadline:
		_adapter.poll()
		_adapter.submit_input(0, InputRouter.INPUT_RIGHT)
		var snapshot := _adapter.get_snapshot()
		var tick := int(snapshot.get("tick", -1))
		var x_fp := _player_x(snapshot, 0)
		if tick > int(result.initial_tick):
			result.authoritative_tick_advanced = true
			result.final_tick = tick
		if x_fp > int(result.initial_x_fp):
			result.authoritative_input_applied = true
			result.final_x_fp = x_fp
		if (
			bool(result.authoritative_tick_advanced)
			and bool(result.authoritative_input_applied)
		):
			break
		if not _adapter.last_error().is_empty():
			break
		await create_timer(POLL_INTERVAL_SECONDS).timeout
	_adapter.submit_input(0, 0)
	if not _adapter.last_error().is_empty():
		result.error = _adapter.last_error()
	elif not bool(result.authoritative_tick_advanced):
		result.error = "The packaged server did not publish an advancing snapshot."
	elif not bool(result.authoritative_input_applied):
		result.error = "The packaged server did not apply authenticated input."
	result.ok = String(result.error).is_empty()
	_finish(result)


func _arguments() -> Dictionary:
	var result := {}
	for argument in OS.get_cmdline_user_args():
		if not argument.begins_with("--") or not argument.contains("="):
			continue
		var separator := argument.find("=")
		result[argument.substr(2, separator - 2)] = argument.substr(separator + 1)
	return result


func _player_x(snapshot: Dictionary, seat_id: int) -> int:
	for value in snapshot.get("players", []):
		if value is Dictionary and int(value.get("seat_id", -1)) == seat_id:
			return int(value.get("x_fp", -1))
	return -1


func _finish(result: Dictionary) -> void:
	if _adapter != null:
		_adapter.close()
	print(JSON.stringify(result))
	quit(0 if bool(result.get("ok", false)) else 2)


func _base_result() -> Dictionary:
	return {
		"schema": SCHEMA,
		"ok": false,
		"error": "",
		"configured": false,
		"content_hash_matches": false,
		"match_contract_valid": false,
		"authenticated": false,
		"seat_claimed": false,
		"state_hash_valid": false,
		"input_submitted": false,
		"authoritative_tick_advanced": false,
		"authoritative_input_applied": false,
		"initial_tick": -1,
		"final_tick": -1,
		"initial_x_fp": -1,
		"authoritative_end_level": 0,
		"final_x_fp": -1,
	}

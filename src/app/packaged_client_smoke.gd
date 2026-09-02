extends Node

const SCHEMA := "warblade.packaged_runtime_smoke.v1"
const STARTUP_TIMEOUT_MSEC := 15_000
const ADVANCE_TIMEOUT_MSEC := 5_000
const SHUTDOWN_TIMEOUT_MSEC := 8_000
const FORCE_KILL_TIMEOUT_MSEC := 2_000

var _session: WBClientSession
var _sidecar_pid := 0
var _heartbeat_path := ""


func _ready() -> void:
	_run.call_deferred()


func _exit_tree() -> void:
	if _session != null:
		_session.close()
	if _sidecar_pid > 0 and OS.is_process_running(_sidecar_pid):
		OS.kill(_sidecar_pid)


func _run() -> void:
	var result := _base_result()
	_session = WBClientSession.new()
	add_child(_session)
	var failure_messages: Array[String] = []
	_session.session_failed.connect(func(message: String) -> void:
		failure_messages.append(message)
	)
	var config := WBMatchConfig.make(
		"solo",
		"normal",
		"classic",
		[],
		"simple",
		424_203
	)
	var boundary_argument := parse_end_level_arguments(OS.get_cmdline_user_args())
	if not bool(boundary_argument.get("valid", false)):
		result.requested_end_level = int(boundary_argument.get("value", 0))
		result.error = str(boundary_argument.get(
			"error",
			"The packaged client received an invalid end-level boundary."
		))
		await _finish(result)
		return
	if bool(boundary_argument.get("provided", false)):
		config.end_level = int(boundary_argument.get("value", 0))
	result.requested_end_level = int(config.get("end_level", 0))
	if not _session.begin(config):
		result.error = _failure_message(failure_messages, "The packaged client session did not start.")
		await _finish(result)
		return
	_sidecar_pid = int(_session._network._sidecar_pid)
	_heartbeat_path = str(_session._network._sidecar_heartbeat_path)
	result.sidecar_started = _sidecar_pid > 0 and OS.is_process_running(_sidecar_pid)
	if not bool(result.sidecar_started):
		result.error = "The packaged client did not launch its authoritative sidecar."
		await _finish(result)
		return

	var startup_deadline := Time.get_ticks_msec() + STARTUP_TIMEOUT_MSEC
	while Time.get_ticks_msec() < startup_deadline:
		await get_tree().process_frame
		var snapshot := _session.snapshot()
		if _session._network.is_ready() and not snapshot.is_empty():
			result.authenticated = true
			result.initial_tick = int(snapshot.get("tick", -1))
			result.initial_x_fp = _player_x(snapshot, 0)
			result.authoritative_end_level = int(snapshot.get("end_level_id", 0))
			result.match_contract_valid = (
				int(result.authoritative_end_level) == int(result.requested_end_level)
			)
			result.state_hash_valid = str(snapshot.get("state_hash", "")).length() == 64
			break
		if not failure_messages.is_empty() or not _session._network.last_error().is_empty():
			break
	if not bool(result.authenticated):
		result.error = _failure_message(
			failure_messages,
			_session._network.last_error() if not _session._network.last_error().is_empty()
			else "The packaged sidecar did not authenticate before the timeout."
		)
		await _finish(result)
		return
	if not bool(result.state_hash_valid):
		result.error = "The authenticated snapshot did not contain an authoritative state hash."
		await _finish(result)
		return
	if not bool(result.match_contract_valid) or int(result.initial_x_fp) < 0:
		result.error = "The authenticated snapshot did not match the requested client match."
		await _finish(result)
		return

	var advance_deadline := Time.get_ticks_msec() + ADVANCE_TIMEOUT_MSEC
	while Time.get_ticks_msec() < advance_deadline:
		_session.submit_input(0, WBInputRouter.INPUT_RIGHT)
		await get_tree().process_frame
		var snapshot := _session.snapshot()
		var tick := int(snapshot.get("tick", -1))
		var x_fp := _player_x(snapshot, 0)
		if tick > int(result.initial_tick):
			result.authoritative_tick_advanced = true
			result.final_tick = tick
		if x_fp > int(result.initial_x_fp):
			result.authoritative_input_applied = true
			result.final_x_fp = x_fp
		if bool(result.authoritative_tick_advanced) and bool(result.authoritative_input_applied):
			break
	_session.submit_input(0, 0)
	if not bool(result.authoritative_tick_advanced):
		result.error = "The packaged authoritative simulation did not advance."
	elif not bool(result.authoritative_input_applied):
		result.error = "The packaged authoritative simulation did not apply client input."
	await _finish(result)


func _finish(result: Dictionary) -> void:
	if _session != null:
		_session.close()
	result.clean_shutdown = await _wait_for_sidecar_exit(SHUTDOWN_TIMEOUT_MSEC)
	result.heartbeat_removed = (
		_heartbeat_path.is_empty() or not FileAccess.file_exists(_heartbeat_path)
	)
	if not bool(result.clean_shutdown):
		if _sidecar_pid > 0 and OS.is_process_running(_sidecar_pid):
			OS.kill(_sidecar_pid)
		await _wait_for_sidecar_exit(FORCE_KILL_TIMEOUT_MSEC)
		if str(result.error).is_empty():
			result.error = "The packaged sidecar did not stop through its heartbeat channel."
	elif not bool(result.heartbeat_removed) and str(result.error).is_empty():
		result.error = "The packaged sidecar stopped without removing its heartbeat file."
	result.ok = (
		str(result.error).is_empty()
		and bool(result.sidecar_started)
		and bool(result.authenticated)
		and bool(result.match_contract_valid)
		and bool(result.state_hash_valid)
		and bool(result.authoritative_tick_advanced)
		and bool(result.authoritative_input_applied)
		and bool(result.clean_shutdown)
		and bool(result.heartbeat_removed)
	)
	print(JSON.stringify(result))
	if _session != null:
		_session.queue_free()
		_session = null
	get_tree().quit(0 if bool(result.ok) else 2)


func _wait_for_sidecar_exit(timeout_msec: int) -> bool:
	if _sidecar_pid <= 0:
		return false
	var deadline := Time.get_ticks_msec() + timeout_msec
	while Time.get_ticks_msec() < deadline:
		if not OS.is_process_running(_sidecar_pid):
			return true
		await get_tree().process_frame
	return not OS.is_process_running(_sidecar_pid)


func _player_x(snapshot: Dictionary, seat_id: int) -> int:
	for value in snapshot.get("players", []):
		if value is Dictionary and int(value.get("seat_id", -1)) == seat_id:
			return int(value.get("x_fp", 0))
	return -1


func _failure_message(messages: Array[String], fallback: String) -> String:
	if not messages.is_empty():
		return messages.back()
	return fallback


static func parse_end_level_arguments(arguments: Variant) -> Dictionary:
	var supplied: Array[String] = []
	for value: Variant in arguments:
		var argument := str(value)
		if argument.begins_with("--end-level="):
			supplied.append(argument.trim_prefix("--end-level="))
	if supplied.is_empty():
		return {
			"provided": false,
			"valid": true,
			"value": 0,
			"error": "",
		}
	if supplied.size() != 1:
		return {
			"provided": true,
			"valid": false,
			"value": 0,
			"error": "The packaged client accepts exactly one --end-level boundary.",
		}
	var raw_value := supplied[0]
	if not raw_value.is_valid_int():
		return {
			"provided": true,
			"valid": false,
			"value": 0,
			"error": "The packaged client end-level boundary must be an integer from 1 through %d." % WBMatchConfig.MAX_END_LEVEL,
		}
	var parsed_value := int(raw_value)
	if parsed_value < 1 or parsed_value > WBMatchConfig.MAX_END_LEVEL:
		return {
			"provided": true,
			"valid": false,
			"value": parsed_value,
			"error": "The packaged client end-level boundary must be from 1 through %d; received %d." % [
				WBMatchConfig.MAX_END_LEVEL,
				parsed_value,
			],
		}
	return {
		"provided": true,
		"valid": true,
		"value": parsed_value,
		"error": "",
	}


func _base_result() -> Dictionary:
	return {
		"schema": SCHEMA,
		"kind": "client_self_sidecar",
		"ok": false,
		"error": "",
		"sidecar_started": false,
		"authenticated": false,
		"match_contract_valid": false,
		"state_hash_valid": false,
		"authoritative_tick_advanced": false,
		"authoritative_input_applied": false,
		"clean_shutdown": false,
		"heartbeat_removed": false,
		"initial_tick": -1,
		"final_tick": -1,
		"initial_x_fp": -1,
		"final_x_fp": -1,
		"requested_end_level": 0,
		"authoritative_end_level": 0,
	}

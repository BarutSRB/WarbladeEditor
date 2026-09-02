class_name WBLocalTwoClientHarness
extends Node

var _process_ids: Array[int] = []
var _port := 0
var _token := ""
var _ready_path := ""
var _heartbeat_path := ""
var _started_at_usec := 0
var _last_heartbeat_usec := 0
var _clients_started := false


func _ready() -> void:
	_token = Crypto.new().generate_random_bytes(16).hex_encode()
	_ready_path = ProjectSettings.globalize_path(
		"user://two_client_server_%d_%d.json" % [OS.get_process_id(), Time.get_ticks_usec()]
	)
	_heartbeat_path = _ready_path.trim_suffix(".json") + ".heartbeat"
	if FileAccess.file_exists(_ready_path):
		DirAccess.remove_absolute(_ready_path)
	if FileAccess.file_exists(_heartbeat_path):
		DirAccess.remove_absolute(_heartbeat_path)
	if not _write_heartbeat():
		push_error("The local two-client harness could not create its heartbeat.")
		get_tree().quit(2)
		return
	_started_at_usec = Time.get_ticks_usec()
	var executable := OS.get_executable_path()
	# The server is an idle lobby; the seat-0 client's HELLO configures the
	# match and the seat-1 client joins it.
	_process_ids.append(OS.create_process(executable, _engine_arguments(true) + PackedStringArray([
		"--server",
		"--host=127.0.0.1",
		"--port=0",
		"--token=%s" % _token,
		"--ready-file=%s" % _ready_path,
		"--parent-heartbeat=%s" % _heartbeat_path,
	])))
	if _process_ids[0] <= 0:
		push_error("The local two-client harness could not start its server.")
		_stop_processes()
		get_tree().quit(2)
		return
	set_process(true)


func _process(_delta: float) -> void:
	if Time.get_ticks_usec() - _last_heartbeat_usec >= 1_000_000:
		_write_heartbeat()
	if _clients_started:
		return
	if Time.get_ticks_usec() - _started_at_usec > 12_000_000:
		push_error("The local two-client server did not become ready.")
		_stop_processes()
		get_tree().quit(2)
		return
	if not FileAccess.file_exists(_ready_path):
		return
	var file := FileAccess.open(_ready_path, FileAccess.READ)
	if file == null:
		return
	var json := JSON.new()
	var parsed := json.parse(file.get_as_text())
	file.close()
	if parsed != OK or typeof(json.data) != TYPE_DICTIONARY:
		push_error("The local two-client server returned invalid startup data.")
		_stop_processes()
		get_tree().quit(2)
		return
	var result: Dictionary = json.data
	DirAccess.remove_absolute(_ready_path)
	if not bool(result.get("ok", false)):
		push_error(str(result.get("error", "The local two-client server failed.")))
		_stop_processes()
		get_tree().quit(2)
		return
	_port = int(result.get("port", 0))
	_launch_clients()


func _exit_tree() -> void:
	_stop_processes()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_stop_processes()
		get_tree().quit()


func _stop_processes() -> void:
	for pid in _process_ids:
		if pid > 0 and OS.is_process_running(pid):
			OS.kill(pid)
	_process_ids.clear()
	if not _ready_path.is_empty() and FileAccess.file_exists(_ready_path):
		DirAccess.remove_absolute(_ready_path)
	if not _heartbeat_path.is_empty() and FileAccess.file_exists(_heartbeat_path):
		DirAccess.remove_absolute(_heartbeat_path)


func _launch_clients() -> void:
	var executable := OS.get_executable_path()
	for seat in range(2):
		var arguments := _engine_arguments(false)
		arguments.append_array([
			"--connect=127.0.0.1",
			"--port=%d" % _port,
			"--token=%s" % _token,
			"--client-seat=%d" % seat,
			"--window-title=Warblade Player %d" % (seat + 1),
		])
		# Presentation flags given to the harness (e.g. --sprite-pack=<name>)
		# ride along to both clients.
		for argument in OS.get_cmdline_user_args():
			if argument != "--local-two-client-harness":
				arguments.append(argument)
		_process_ids.append(OS.create_process(executable, arguments))
	_clients_started = true
	if _process_ids.any(func(pid: int) -> bool: return pid <= 0):
		push_error("The local two-client harness could not start every process.")
		_stop_processes()
		get_tree().quit(2)
		return
	print("Warblade local harness listening on 127.0.0.1:%d" % _port)


func _engine_arguments(headless: bool) -> PackedStringArray:
	var arguments := PackedStringArray()
	if headless:
		arguments.append("--headless")
	if OS.has_feature("editor"):
		arguments.append_array([
			"--path",
			ProjectSettings.globalize_path("res://"),
		])
	arguments.append("--")
	return arguments


func _write_heartbeat() -> bool:
	var file := FileAccess.open(_heartbeat_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(str(Time.get_unix_time_from_system()))
	file.close()
	_last_heartbeat_usec = Time.get_ticks_usec()
	return true

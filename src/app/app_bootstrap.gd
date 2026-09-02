extends Node

const SERVER_PATH := "res://src/server/authoritative_server.gd"
const PACKAGED_CLIENT_SMOKE_PATH := "res://src/app/packaged_client_smoke.gd"

var _args: WBCliArgs


func _ready() -> void:
	_args = WBCliArgs.new()
	if _args.has_flag("server") or OS.has_feature("server"):
		_start_server()
		return
	if _args.has_flag("local-two-client-harness"):
		add_child(WBLocalTwoClientHarness.new())
		return
	if _args.has_flag("packaged-client-smoke"):
		_start_packaged_client_smoke()
		return
	var pack_name := _args.value(
		"sprite-pack",
		str(WBSettingsStore.read_raw().get("sprite_pack", ""))
	)
	var pack_active := true
	if not pack_name.is_empty():
		# A missing or broken pack warns and plays with retail art; it never
		# blocks boot.
		pack_active = WBAssetLibrary.set_active_pack(pack_name)
	if _args.has_flag("pack-smoke"):
		var pack_result := WBAssetLibrary.new().validate_pack()
		if not pack_active:
			pack_result = {
				"ok": false,
				"pack": pack_name,
				"overridden": 0,
				"errors": ["sprite pack did not activate: %s" % pack_name],
			}
		print(JSON.stringify(pack_result))
		get_tree().quit(0 if bool(pack_result.get("ok", false)) else 2)
		return
	var presentation := WBAssetLibrary.new()
	var presentation_result := presentation.validate_required(
		true,
		_args.has_flag("presentation-smoke")
	)
	if _args.has_flag("presentation-smoke"):
		print(JSON.stringify(presentation_result))
		get_tree().quit(0 if bool(presentation_result.get("ok", false)) else 2)
		return
	if (
		not bool(presentation_result.get("ok", false))
		and not _args.has_flag("allow-placeholder-presentation")
	):
		_show_presentation_failure(presentation_result)
		return
	var title := _args.value("window-title")
	if not title.is_empty() and DisplayServer.get_name() != "headless":
		DisplayServer.window_set_title(title)
	var shell := WBAppShell.new()
	add_child(shell)


func _start_packaged_client_smoke() -> void:
	if not ResourceLoader.exists(PACKAGED_CLIENT_SMOKE_PATH):
		push_error("Packaged client smoke script is missing: %s" % PACKAGED_CLIENT_SMOKE_PATH)
		get_tree().quit(2)
		return
	var script: Script = load(PACKAGED_CLIENT_SMOKE_PATH)
	if script == null or not script.can_instantiate():
		push_error("Packaged client smoke script cannot be instantiated.")
		get_tree().quit(2)
		return
	var smoke: Object = script.new()
	if not smoke is Node:
		push_error("Packaged client smoke must extend Node.")
		get_tree().quit(2)
		return
	add_child(smoke as Node)


func _show_presentation_failure(result: Dictionary) -> void:
	var errors: Array = result.get("errors", [])
	var message := "The original Warblade presentation assets failed validation."
	if not errors.is_empty():
		message += "\n\n" + "\n".join(errors)
	push_error(message)
	if DisplayServer.get_name() == "headless":
		get_tree().quit(2)
		return
	var background := ColorRect.new()
	background.color = Color("#060912")
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	var label := Label.new()
	label.text = message
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.set_anchors_preset(Control.PRESET_CENTER)
	label.position = Vector2(-300.0, -120.0)
	label.size = Vector2(600.0, 240.0)
	label.add_theme_color_override("font_color", Color("#ff8f8f"))
	label.add_theme_font_size_override("font_size", 20)
	add_child(label)


## Every `--server` process is a lobby game server: it binds, authenticates,
## and lets the first authenticated HELLO configure the match. The client's
## sidecar launches it on 127.0.0.1; the same binary with --host/--port/--token
## is the online deployment.
func _start_server() -> void:
	if not ResourceLoader.exists(SERVER_PATH):
		push_error("Authoritative server script is missing: %s" % SERVER_PATH)
		get_tree().quit(2)
		return
	var script: Script = load(SERVER_PATH)
	if script == null or not script.can_instantiate():
		push_error("Authoritative server script cannot be instantiated.")
		get_tree().quit(2)
		return
	var server: Object = script.new()
	if not server is Node:
		push_error("Authoritative server must extend Node.")
		get_tree().quit(2)
		return
	add_child(server as Node)
	if not server.has_method("start_lobby"):
		_finish_server_start({
			"ok": false,
			"error": "Authoritative server does not expose start_lobby.",
		})
		return
	var result: Dictionary = server.call(
		"start_lobby",
		_args.value("host", "127.0.0.1"),
		_args.integer("port", 0),
		_args.value("token")
	)
	# A launching client pins its compiled-content hash; refuse to stand in for
	# it with different content on disk.
	var expected_hash := _args.value("content-hash")
	if (
		bool(result.get("ok", false))
		and not expected_hash.is_empty()
		and str(result.get("content_hash", "")) != expected_hash
	):
		if server.has_method("stop"):
			server.call("stop")
		result = {
			"ok": false,
			"error": "The server's game content differs from the launching client.",
		}
	# A hosting sidecar keeps the lobby server's rendezvous socket informed of
	# its public endpoint; the host client passes the address and nonce it
	# registered over WebSocket.
	var rendezvous := _args.value("rendezvous").strip_edges()
	if bool(result.get("ok", false)) and not rendezvous.is_empty():
		var separator := rendezvous.rfind(":")
		var rendezvous_host := rendezvous.substr(0, separator) if separator > 0 else ""
		var rendezvous_port := int(rendezvous.substr(separator + 1)) if separator > 0 else 0
		var configured: Dictionary = server.call(
			"configure_rendezvous", rendezvous_host, rendezvous_port, _args.value("rendezvous-nonce")
		)
		if not bool(configured.get("ok", false)):
			if server.has_method("stop"):
				server.call("stop")
			result = {
				"ok": false,
				"error": str(configured.get("error", "rendezvous configuration failed")),
			}
	_finish_server_start(result)
	if bool(result.get("ok", false)):
		_monitor_parent_heartbeat(_args.value("parent-heartbeat"), server)


func _finish_server_start(result: Dictionary) -> void:
	var response := {
		"ok": bool(result.get("ok", false)),
		"error": str(result.get("error", "")),
		"port": int(result.get("port", 0)),
		"token": str(result.get("token", "")),
		"content_hash": str(result.get("content_hash", "")),
	}
	var ready_path := _args.value("ready-file")
	if not ready_path.is_empty():
		var temporary_path := ready_path + ".tmp"
		var file := FileAccess.open(temporary_path, FileAccess.WRITE)
		if file == null:
			push_error("Unable to write the local server startup response.")
			get_tree().quit(2)
			return
		file.store_string(JSON.stringify(response))
		file.close()
		if FileAccess.file_exists(ready_path):
			DirAccess.remove_absolute(ready_path)
		if DirAccess.rename_absolute(temporary_path, ready_path) != OK:
			push_error("Unable to publish the local server startup response.")
			get_tree().quit(2)
			return
	print(JSON.stringify(response))
	if not bool(response.ok):
		push_error(str(response.error))
		get_tree().quit(2)


func _monitor_parent_heartbeat(path: String, server: Object) -> void:
	if path.is_empty():
		return
	var now_msec := Time.get_ticks_msec()
	var last_seen_msec := [now_msec]
	var last_monitor_msec := [now_msec]
	var last_payload := [""]
	var monitor := Timer.new()
	monitor.wait_time = 1.0
	monitor.timeout.connect(func() -> void:
		var current_msec := Time.get_ticks_msec()
		if heartbeat_callback_needs_grace(last_monitor_msec[0], current_msec):
			last_seen_msec[0] = current_msec
		last_monitor_msec[0] = current_msec
		if FileAccess.file_exists(path):
			var file := FileAccess.open(path, FileAccess.READ)
			if file != null:
				var raw := file.get_as_text()
				file.close()
				if raw == "shutdown":
					DirAccess.remove_absolute(path)
					if server.has_method("stop"):
						server.call("stop")
					get_tree().quit()
					return
				if not raw.is_empty() and raw != last_payload[0]:
					last_payload[0] = raw
					last_seen_msec[0] = current_msec
		if current_msec - last_seen_msec[0] > 5000:
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(path)
			if server.has_method("stop"):
				server.call("stop")
			get_tree().quit()
	)
	add_child(monitor)
	monitor.start()


static func heartbeat_callback_needs_grace(
	previous_callback_msec: int,
	current_callback_msec: int
) -> bool:
	return current_callback_msec - previous_callback_msec > 2000

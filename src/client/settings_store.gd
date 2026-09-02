class_name WBSettingsStore
extends RefCounted

const DEFAULT_PATH := "user://settings.json"
const SETTINGS_VERSION := 2
## The live lobby server; SETTINGS → LOBBY SERVER overrides it per profile.
const DEFAULT_LOBBY_HOST := "68.183.194.133"
## Version 1 settings files were written with the loopback development default.
const LEGACY_LOBBY_HOST := "127.0.0.1"
const RENDER_CAPS := [0, 60, 120, 144, 165, 240, 360, 480]
const REMAPPABLE_ACTIONS := [
	"p1_left", "p1_right", "p1_up", "p1_down", "p1_fire", "p1_secondary",
	"p2_left", "p2_right", "p2_up", "p2_down", "p2_fire", "p2_secondary",
	"pause",
]
const MAX_EVENTS_PER_ACTION := 4

var _path := DEFAULT_PATH
var _settings: Dictionary = {}


func configure_path(path: String) -> void:
	_path = path


func load_settings() -> Dictionary:
	_settings = defaults()
	if FileAccess.file_exists(_path):
		var file := FileAccess.open(_path, FileAccess.READ)
		if file != null:
			var parsed: Variant = JSON.parse_string(file.get_as_text())
			if parsed is Dictionary:
				_merge_file(parsed as Dictionary, _settings)
	_settings = sanitize(_settings)
	apply()
	return values()


func values() -> Dictionary:
	return _settings.duplicate(true)


func set_value(key: String, value: Variant) -> void:
	if not defaults().has(key):
		return
	_settings[key] = value
	_settings = sanitize(_settings)


func save_and_apply() -> bool:
	apply()
	var file := FileAccess.open(_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify({"version": SETTINGS_VERSION}.merged(_settings), "\t"))
	return true


func apply() -> void:
	Engine.max_fps = int(_settings.get("render_cap", 0))
	if DisplayServer.get_name() == "headless":
		return
	var vsync := bool(_settings.get("vsync", true))
	DisplayServer.window_set_vsync_mode(
		DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED
	)
	var display_mode := str(_settings.get("display_mode", "windowed"))
	match display_mode:
		"fullscreen":
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		"borderless":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
		_:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			DisplayServer.window_set_size(Vector2i(
				int(_settings.get("window_width", 1280)),
				int(_settings.get("window_height", 960))
			))
	AudioServer.set_bus_volume_db(
		AudioServer.get_bus_index("Master"),
		linear_to_db(float(_settings.get("master_volume", 0.8)))
	)
	apply_input_bindings(_settings.get("input_bindings", {}))


static func apply_input_bindings(bindings_value: Variant) -> void:
	# Restore project defaults first so cleared or invalid bindings revert
	# instead of leaving stale events behind.
	InputMap.load_from_project_settings()
	if not bindings_value is Dictionary:
		return
	var bindings := bindings_value as Dictionary
	for action_value: Variant in bindings:
		var action := str(action_value)
		if action not in REMAPPABLE_ACTIONS or not InputMap.has_action(action):
			continue
		var events_value: Variant = bindings[action_value]
		if not events_value is Array:
			continue
		var events: Array[InputEvent] = []
		for event_value: Variant in (events_value as Array):
			if not event_value is Dictionary:
				continue
			var event := make_input_event(event_value as Dictionary)
			if event != null:
				events.append(event)
		if events.is_empty():
			continue
		InputMap.action_erase_events(action)
		for event in events:
			InputMap.action_add_event(action, event)


static func make_input_event(data: Dictionary) -> InputEvent:
	match str(data.get("type", "")):
		"key":
			var keycode := int(data.get("physical_keycode", 0))
			if keycode <= 0:
				return null
			var key_event := InputEventKey.new()
			key_event.physical_keycode = keycode as Key
			return key_event
		"joy_button":
			var button := int(data.get("button_index", -1))
			if button < 0:
				return null
			var button_event := InputEventJoypadButton.new()
			button_event.button_index = button as JoyButton
			button_event.device = int(data.get("device", -1))
			return button_event
		"joy_axis":
			var axis := int(data.get("axis", -1))
			if axis < 0:
				return null
			var axis_event := InputEventJoypadMotion.new()
			axis_event.axis = axis as JoyAxis
			axis_event.axis_value = signf(float(data.get("axis_value", 1.0)))
			axis_event.device = int(data.get("device", -1))
			return axis_event
	return null


static func describe_input_event(data: Dictionary) -> String:
	var event := make_input_event(data)
	if event == null:
		return ""
	if event is InputEventKey:
		var key_event := event as InputEventKey
		var keycode: Key = key_event.physical_keycode
		if DisplayServer.get_name() != "headless":
			var mapped := DisplayServer.keyboard_get_keycode_from_physical(
				key_event.physical_keycode
			)
			if mapped != KEY_NONE:
				keycode = mapped
		return OS.get_keycode_string(keycode)
	return event.as_text()


static func defaults() -> Dictionary:
	return {
		"display_mode": "windowed",
		"window_width": 1280,
		"window_height": 960,
		"render_cap": 0,
		"vsync": true,
		"collision_mode": "pixel",
		"effects_mode": "enhanced",
		"texture_filter": "smooth",
		"sprite_pack": "",
		"master_volume": 0.8,
		"music_volume": 0.75,
		"sfx_volume": 0.9,
		"voice_volume": 0.9,
		"voice_pack": 1,
		"background_brightness": 1.0,
		# The lobby server (identity, lobby list, global chat, talents). An
		# empty address keeps the game offline; solo and couch play never need it.
		"lobby_host": DEFAULT_LOBBY_HOST,
		"lobby_port": 7400,
		"lobby_udp_port": 7401,
		# The UDP port this Mac listens on when hosting an online co-op game.
		"host_port": 42000,
		"upnp_enabled": true,
		"input_bindings": {},
		"jukebox": WBJukeboxStore.sanitize({}),
	}


## The lobby-server endpoint the lobby client connects to.
static func lobby_config(settings: Dictionary) -> Dictionary:
	return {
		"host": str(settings.get("lobby_host", "")),
		"port": int(settings.get("lobby_port", 7400)),
		"udp_port": int(settings.get("lobby_udp_port", 7401)),
	}


static func describe_lobby(settings: Dictionary) -> String:
	var host := str(settings.get("lobby_host", "")).strip_edges()
	if host.is_empty():
		return "LOBBY SERVER NOT CONFIGURED"
	return "LOBBY SERVER %s:%d" % [host, int(settings.get("lobby_port", 7400))]


static func sanitize_port(value: Variant, fallback: int) -> int:
	var port := int(value)
	return port if port >= 1024 and port <= 65535 else fallback


static func sanitize(source: Dictionary) -> Dictionary:
	var result := defaults()
	var display_mode := str(source.get("display_mode", result["display_mode"]))
	result["display_mode"] = display_mode if display_mode in ["windowed", "borderless", "fullscreen"] else "windowed"
	result["window_width"] = clampi(int(source.get("window_width", 1280)), 800, 7680)
	result["window_height"] = clampi(int(source.get("window_height", 960)), 600, 4320)
	var render_cap := int(source.get("render_cap", 0))
	result["render_cap"] = render_cap if render_cap in RENDER_CAPS else 0
	result["vsync"] = bool(source.get("vsync", true))
	var collision := str(source.get("collision_mode", "pixel"))
	result["collision_mode"] = collision if collision in ["pixel", "simple"] else "pixel"
	var effects_mode := str(source.get("effects_mode", "enhanced"))
	result["effects_mode"] = effects_mode if effects_mode in ["original", "enhanced"] else "enhanced"
	var texture_filter := str(source.get("texture_filter", "smooth"))
	result["texture_filter"] = texture_filter if texture_filter in ["smooth", "sharp"] else "smooth"
	result["sprite_pack"] = sanitize_pack_name(str(source.get("sprite_pack", "")))
	result["master_volume"] = clampf(float(source.get("master_volume", 0.8)), 0.0, 1.0)
	result["music_volume"] = clampf(float(source.get("music_volume", 0.75)), 0.0, 1.0)
	result["sfx_volume"] = clampf(float(source.get("sfx_volume", 0.9)), 0.0, 1.0)
	result["voice_volume"] = clampf(float(source.get("voice_volume", 0.9)), 0.0, 1.0)
	result["voice_pack"] = 2 if int(source.get("voice_pack", 1)) == 2 else 1
	result["background_brightness"] = clampf(
		float(source.get("background_brightness", 1.0)), 0.25, 1.0
	)
	var lobby_host := str(source.get("lobby_host", DEFAULT_LOBBY_HOST)).strip_edges()
	if lobby_host.length() > 253 or lobby_host.contains(" "):
		lobby_host = ""
	result["lobby_host"] = lobby_host
	result["lobby_port"] = sanitize_port(source.get("lobby_port", 7400), 7400)
	result["lobby_udp_port"] = sanitize_port(source.get("lobby_udp_port", 7401), 7401)
	result["host_port"] = sanitize_port(source.get("host_port", 42000), 42000)
	result["upnp_enabled"] = bool(source.get("upnp_enabled", true))
	result["input_bindings"] = sanitize_input_bindings(source.get("input_bindings", {}))
	result["jukebox"] = WBJukeboxStore.sanitize(source.get("jukebox", {}))
	return result


static func sanitize_input_bindings(value: Variant) -> Dictionary:
	var result := {}
	if not value is Dictionary:
		return result
	for action_value: Variant in (value as Dictionary):
		var action := str(action_value)
		if action not in REMAPPABLE_ACTIONS:
			continue
		var events_value: Variant = (value as Dictionary)[action_value]
		if not events_value is Array:
			continue
		var events: Array = []
		for event_value: Variant in (events_value as Array):
			if events.size() >= MAX_EVENTS_PER_ACTION:
				break
			if not event_value is Dictionary:
				continue
			var event := event_value as Dictionary
			match str(event.get("type", "")):
				"key":
					var keycode := int(event.get("physical_keycode", 0))
					if keycode > 0:
						events.append({"type": "key", "physical_keycode": keycode})
				"joy_button":
					var button := int(event.get("button_index", -1))
					if button >= 0:
						events.append({
							"type": "joy_button",
							"button_index": button,
							"device": int(event.get("device", -1)),
						})
				"joy_axis":
					var axis := int(event.get("axis", -1))
					if axis >= 0:
						events.append({
							"type": "joy_axis",
							"axis": axis,
							"axis_value": signf(float(event.get("axis_value", 1.0))),
							"device": int(event.get("device", -1)),
						})
		if not events.is_empty():
			result[action] = events
	return result


## Sprite pack folder names: 1-32 characters of lowercase [a-z0-9_].
## Availability is checked at boot, not here, so a missing pack degrades to
## retail art instead of being erased from settings.
static func sanitize_pack_name(value: String) -> String:
	var pack_name := value.strip_edges().to_lower()
	if pack_name.is_empty() or pack_name.length() > 32:
		return ""
	for character in pack_name:
		if not "abcdefghijklmnopqrstuvwxyz0123456789_".contains(character):
			return ""
	return pack_name


## Parses and sanitizes settings WITHOUT apply(): bootstrap consults settings
## before the shell exists and must not touch the window or audio bus.
static func read_raw(path: String = DEFAULT_PATH) -> Dictionary:
	var settings := defaults()
	if FileAccess.file_exists(path):
		var file := FileAccess.open(path, FileAccess.READ)
		if file != null:
			var parsed: Variant = JSON.parse_string(file.get_as_text())
			if parsed is Dictionary:
				_merge_file(parsed as Dictionary, settings)
	return sanitize(settings)


## Copies the known keys of a settings document over `target`. Version 1
## files were saved with the loopback development lobby address; those adopt
## the live server, while a deliberately configured host survives.
static func _merge_file(parsed: Dictionary, target: Dictionary) -> void:
	var legacy := int(parsed.get("version", 1)) < 2
	for key: Variant in target.keys():
		if not parsed.has(key):
			continue
		if legacy and key == "lobby_host" and str(parsed[key]).strip_edges() == LEGACY_LOBBY_HOST:
			continue
		target[key] = parsed[key]

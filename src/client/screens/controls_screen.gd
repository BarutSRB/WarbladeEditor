class_name WBControlsScreen
extends Control

## Press-to-rebind controls screen. Bindings persist through
## WBSettingsStore ("input_bindings") and apply via InputMap so
## WBInputRouter and every gameplay consumer see them transparently.
## p1_confirm / p1_cancel / p2_confirm double as UI navigation and stay fixed.

signal closed

const ACTION_LABELS := [
	["p1_left", "P1  MOVE LEFT"],
	["p1_right", "P1  MOVE RIGHT"],
	["p1_up", "P1  MOVE UP"],
	["p1_down", "P1  MOVE DOWN"],
	["p1_fire", "P1  FIRE"],
	["p1_secondary", "P1  ROCKET"],
	["p2_left", "P2  MOVE LEFT"],
	["p2_right", "P2  MOVE RIGHT"],
	["p2_up", "P2  MOVE UP"],
	["p2_down", "P2  MOVE DOWN"],
	["p2_fire", "P2  FIRE"],
	["p2_secondary", "P2  ROCKET"],
	["pause", "PAUSE"],
]

var _settings_store: WBSettingsStore
var _bindings: Dictionary = {}
var _binding_labels: Dictionary = {}
var _rebind_action := ""
var _status: Label
var _rows: VBoxContainer


func _init(settings_store: WBSettingsStore) -> void:
	_settings_store = settings_store
	_bindings = WBSettingsStore.sanitize_input_bindings(
		settings_store.values().get("input_bindings", {})
	)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL


func _ready() -> void:
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 8)
	add_child(column)

	var heading := Label.new()
	heading.text = "CONTROLS"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 24)
	column.add_child(heading)

	_status = Label.new()
	_status.text = "Select REBIND, then press a key or controller input. ESC cancels."
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 13)
	_status.add_theme_color_override("font_color", Color("#809bb4"))
	column.add_child(_status)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)

	_rows = VBoxContainer.new()
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", 6)
	scroll.add_child(_rows)

	for pair in ACTION_LABELS:
		_rows.add_child(_make_row(str(pair[0]), str(pair[1])))

	var footer := HBoxContainer.new()
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	footer.add_theme_constant_override("separation", 16)
	column.add_child(footer)

	var reset := Button.new()
	reset.text = "RESET DEFAULTS"
	reset.pressed.connect(_on_reset_defaults)
	footer.add_child(reset)

	var back := Button.new()
	back.text = "BACK"
	back.pressed.connect(func() -> void: closed.emit())
	footer.add_child(back)

	_refresh_labels()


func _make_row(action: String, label_text: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var name_label := Label.new()
	name_label.text = label_text
	name_label.custom_minimum_size = Vector2(220, 0)
	row.add_child(name_label)
	var binding_label := Label.new()
	binding_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	binding_label.add_theme_color_override("font_color", Color("#c8b878"))
	row.add_child(binding_label)
	_binding_labels[action] = binding_label
	var rebind := Button.new()
	rebind.text = "REBIND"
	rebind.pressed.connect(func() -> void: _begin_rebind(action))
	row.add_child(rebind)
	return row


func _begin_rebind(action: String) -> void:
	_rebind_action = action
	_status.text = "Press a key or controller input for %s ... (ESC cancels)" % _display_name(action)
	_refresh_labels()


func _unhandled_input(event: InputEvent) -> void:
	if _rebind_action.is_empty():
		return
	var captured := _capture_event(event)
	if captured.is_empty():
		return
	get_viewport().set_input_as_handled()
	if str(captured.get("cancel", "")) == "cancel":
		_rebind_action = ""
		_status.text = "Rebind cancelled."
		_refresh_labels()
		return
	_bindings[_rebind_action] = [captured]
	_rebind_action = ""
	_persist()
	_refresh_labels()


func _capture_event(event: InputEvent) -> Dictionary:
	if event is InputEventKey and event.is_pressed() and not event.is_echo():
		var key_event := event as InputEventKey
		if key_event.physical_keycode == KEY_ESCAPE:
			return {"cancel": "cancel"}
		if key_event.physical_keycode == KEY_NONE:
			return {}
		return {"type": "key", "physical_keycode": int(key_event.physical_keycode)}
	if event is InputEventJoypadButton and event.is_pressed():
		var button_event := event as InputEventJoypadButton
		return {
			"type": "joy_button",
			"button_index": int(button_event.button_index),
			"device": -1,
		}
	if event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		if absf(motion.axis_value) >= 0.6:
			return {
				"type": "joy_axis",
				"axis": int(motion.axis),
				"axis_value": signf(motion.axis_value),
				"device": -1,
			}
	return {}


func _persist() -> void:
	_bindings = WBSettingsStore.sanitize_input_bindings(_bindings)
	_settings_store.set_value("input_bindings", _bindings)
	_settings_store.save_and_apply()
	_status.text = "Saved."


func _on_reset_defaults() -> void:
	_bindings = {}
	_rebind_action = ""
	_persist()
	_status.text = "Defaults restored."
	_refresh_labels()


func _refresh_labels() -> void:
	var signatures := {}
	for pair in ACTION_LABELS:
		var action := str(pair[0])
		for event_value: Variant in _events_for(action):
			var signature := JSON.stringify(event_value)
			signatures[signature] = int(signatures.get(signature, 0)) + 1
	for pair in ACTION_LABELS:
		var action := str(pair[0])
		var label := _binding_labels.get(action) as Label
		if label == null:
			continue
		var descriptions: Array[String] = []
		var conflict := false
		for event_value: Variant in _events_for(action):
			var description := WBSettingsStore.describe_input_event(event_value as Dictionary)
			if not description.is_empty():
				descriptions.append(description)
			if int(signatures.get(JSON.stringify(event_value), 0)) > 1:
				conflict = true
		if action == _rebind_action:
			label.text = "PRESS INPUT..."
			label.add_theme_color_override("font_color", Color("#e0d090"))
		else:
			label.text = " / ".join(descriptions) if not descriptions.is_empty() else "(default)"
			label.add_theme_color_override(
				"font_color",
				Color("#e06060") if conflict else Color("#c8b878")
			)
		if conflict and action != _rebind_action:
			label.text += "   [CONFLICT]"


## Events shown for an action: the custom binding if present, otherwise the
## live InputMap events (project defaults) serialized for display.
func _events_for(action: String) -> Array:
	if _bindings.has(action):
		return _bindings[action] as Array
	var events: Array = []
	if not InputMap.has_action(action):
		return events
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			events.append({
				"type": "key",
				"physical_keycode": int((event as InputEventKey).physical_keycode),
			})
		elif event is InputEventJoypadButton:
			events.append({
				"type": "joy_button",
				"button_index": int((event as InputEventJoypadButton).button_index),
				"device": int(event.device),
			})
		elif event is InputEventJoypadMotion:
			events.append({
				"type": "joy_axis",
				"axis": int((event as InputEventJoypadMotion).axis),
				"axis_value": signf((event as InputEventJoypadMotion).axis_value),
				"device": int(event.device),
			})
	return events


func _display_name(action: String) -> String:
	for pair in ACTION_LABELS:
		if str(pair[0]) == action:
			return str(pair[1])
	return action

class_name WBChatPanel
extends VBoxContainer

## One reusable chat widget: a scrolling log above a line edit. The global
## chat screen, the hosted-game waiting room, and the in-game chat dock all
## use it; the owner decides where submitted lines go.

signal message_submitted(text: String)
signal closed()

const MAX_LINES := 200

var _lines: Array[String] = []
var _log := RichTextLabel.new()
var _status := Label.new()
var _input := LineEdit.new()
var _send := Button.new()


func _ready() -> void:
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", 6)
	_log.name = "ChatLog"
	_log.bbcode_enabled = false
	_log.scroll_following = true
	_log.selection_enabled = true
	_log.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log.custom_minimum_size = Vector2(0.0, 120.0)
	_log.add_theme_font_size_override("normal_font_size", 13)
	_log.add_theme_color_override("default_color", Color("#c8d8eb"))
	add_child(_log)
	_status.name = "ChatStatus"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_font_size_override("font_size", 12)
	_status.add_theme_color_override("font_color", Color("#ff7b6b"))
	_status.visible = false
	add_child(_status)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_input.name = "ChatInput"
	_input.placeholder_text = "TYPE A MESSAGE"
	_input.max_length = WBLobbyContract.CHAT_MAX_CHARS
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.text_submitted.connect(func(_text: String) -> void: _submit())
	_input.gui_input.connect(_on_input_gui_input)
	row.add_child(_input)
	_send.name = "ChatSend"
	_send.text = "SEND"
	_send.pressed.connect(_submit)
	row.add_child(_send)
	add_child(row)


func append_line(nickname: String, text: String) -> void:
	_lines.append("%s: %s" % [nickname.to_upper(), text])
	while _lines.size() > MAX_LINES:
		_lines.pop_front()
	_log.text = "\n".join(_lines)


## Replaces the log with stored history: an Array of {nickname, body} rows.
func set_lines(messages: Array) -> void:
	_lines.clear()
	for message_value: Variant in messages:
		if not message_value is Dictionary:
			continue
		var message := message_value as Dictionary
		_lines.append("%s: %s" % [
			str(message.get("nickname", "?")).to_upper(),
			str(message.get("body", message.get("text", ""))),
		])
	while _lines.size() > MAX_LINES:
		_lines.pop_front()
	_log.text = "\n".join(_lines)


func line_count() -> int:
	return _lines.size()


func set_status(text: String) -> void:
	_status.text = text
	_status.visible = not text.is_empty()


func focus_input() -> void:
	_input.grab_focus()


func is_input_focused() -> bool:
	return _input.has_focus()


func release_input() -> void:
	_input.release_focus()


func clear_input() -> void:
	_input.text = ""


## The in-game dock trims the log so it does not cover the play field.
func set_compact(compact: bool) -> void:
	_log.custom_minimum_size = Vector2(0.0, 72.0 if compact else 120.0)
	_log.add_theme_font_size_override("normal_font_size", 12 if compact else 13)


func submit_for_test(text: String) -> void:
	_input.text = text
	_submit()


func _submit() -> void:
	var text := _input.text.strip_edges()
	if text.is_empty():
		return
	_input.text = ""
	message_submitted.emit(text)


func _on_input_gui_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		if (event as InputEventKey).keycode == KEY_ESCAPE:
			_input.release_focus()
			closed.emit()
			get_viewport().set_input_as_handled()

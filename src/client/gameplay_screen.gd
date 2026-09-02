class_name WBGameplayScreen
extends Control

const Protocol := preload("res://src/net/protocol_codec.gd")

signal exit_requested(result: Dictionary)
signal shop_save_requested()
## The run reached its terminal state: the result summary the shell records
## locally and, when online, reports to the lobby server. Emitted once.
signal match_finished(result: Dictionary)
## Online co-op: flips whenever the match stops or resumes because a seat
## is empty (the host reports the match once the joiner fills it).
signal party_waiting(waiting: bool)
signal authoritative_result_ready(result: Dictionary)
signal sound_requested(key: String)
signal audio_requested(request: Dictionary)

var _renderer := WBGameplayRenderer.new()
var _hud := WBHudOverlay.new()
var _session := WBClientSession.new()
var _input := WBInputRouter.new()
var _assets := WBAssetLibrary.new()
var _config: Dictionary = {}
var _snapshot: Dictionary = {}
var _pause_overlay: Control
var _shop_overlay: Control
var _shop_grid := GridContainer.new()
var _shop_status := Label.new()
var _shop_info := Label.new()
var _ready_box := HBoxContainer.new()
var _rank_promotion_overlay: Control
var _rank_promotion_title := Label.new()
var _rank_promotion_status := Label.new()
var _rank_promotion_player := Label.new()
var _rank_promotion_rank := Label.new()
var _rank_promotion_badge := TextureRect.new()
var _rank_promotion_badge_texture := AtlasTexture.new()
var _rank_promotion_prompt := Label.new()
var _result_overlay: Control
var _result_summary := Label.new()
var _result_heading: Label
var _result_done_button: Button
var _result_retry_button: Button
var _result_persistence_status := Label.new()
var _gameover_art := TextureRect.new()
var _ending_presentation: WBEndingPresentation
var _level_banner := Label.new()
var _level_banner_timer := Timer.new()
var _hurry_up_banner := Label.new()
var _hurry_up_banner_timer := Timer.new()
var _seen_hurry_up_events: Dictionary = {}
var _current_level := 0
var _current_phase := ""
var _shop_signature := ""
## Signature of the leave/save row; snapshots arrive twenty times a second
## and rebuilding controls that often swallows clicks and steals focus.
var _ready_signature := ""
## A transient shop message (purchase or save outcome) shown over the cash
## line until it expires; the cash line alone would overwrite it at once.
var _shop_notice := ""
var _shop_notice_until_msec := 0
const SHOP_NOTICE_MSEC := 3000
var _finished := false
var _match_finished_emitted := false
var _demo := false
var _secret_overlay: Control
var _secret_image := TextureRect.new()
var _secret_background := TextureRect.new()
var _secret_label := Label.new()
var _secret_active := false
var _seen_secret_events: Dictionary = {}
var _get_ready_overlay: Control
var _get_ready_label := Label.new()
var _get_ready_level := Label.new()
var _ending_started := false
var _ending_finished := false
var _credits_interstitial_active := false
var _credits_continue_armed := false
var _profile_result_persist_requested := false
var _profile_result_persisted := false
var _profile_result_persist_in_flight := false
var _profile_result_persist_error := ""
var _pending_authoritative_result: Dictionary = {}
var _party: Dictionary = {}
var _party_active := false
var _party_overlay: Control
var _party_heading: Label
var _party_status := Label.new()
var _party_status_text := ""
var _party_start_button: Button
var _party_retire_button: Button
var _party_chat: WBChatPanel
var _chat_dock: Control
var _chat_dock_panel: WBChatPanel
var _party_waiting := false
var _party_started := false
var _party_pause_requested := false


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	set_process_unhandled_input(true)

	_renderer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_renderer)
	_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_hud)
	_create_chat_dock()

	add_child(_session)
	_session.snapshot_received.connect(_on_snapshot)
	_session.session_failed.connect(_on_session_failed)
	_session.sound_requested.connect(func(key: String) -> void: sound_requested.emit(key))
	_session.audio_requested.connect(
		func(request: Dictionary) -> void: audio_requested.emit(request)
	)
	_session.pause_changed.connect(_on_pause_changed)
	_session.purchase_completed.connect(_on_purchase_completed)
	_session.save_completed.connect(_on_save_completed)
	_session.chat_received.connect(_on_chat_received)

	_create_level_banner()
	_create_get_ready_overlay()
	_create_pause_overlay()
	_create_shop_overlay()
	_create_secret_overlay()
	_create_rank_promotion_overlay()
	_create_party_overlay()
	_create_result_overlay()
	_create_ending_presentation()


func begin(match_config: Dictionary) -> bool:
	_config = match_config.duplicate(true)
	_demo = bool(_config.get("demo", false))
	var party_value: Variant = _config.get("party", {})
	_party = (party_value as Dictionary).duplicate(true) if party_value is Dictionary else {}
	_party_active = not _party.is_empty() and not _demo
	_party_started = false
	_party_waiting = false
	_party_pause_requested = false
	_party_chat.set_lines([])
	_chat_dock_panel.set_lines([])
	_chat_dock.visible = false
	_party_overlay.visible = false
	_renderer.configure(_config)
	_hud.set_hiscore(int(_config.get("hiscore", 0)))
	_finished = false
	_match_finished_emitted = false
	_ending_started = false
	_ending_finished = false
	_credits_interstitial_active = false
	_credits_continue_armed = false
	_profile_result_persist_requested = false
	_profile_result_persisted = false
	_profile_result_persist_in_flight = false
	_profile_result_persist_error = ""
	_pending_authoritative_result.clear()
	_clear_profile_persistence_gate_ui()
	_secret_active = false
	_seen_secret_events.clear()
	_seen_hurry_up_events.clear()
	if _ending_presentation != null:
		_ending_presentation.reset()
	_current_level = 0
	_current_phase = ""
	if not _session.begin(_config):
		return false
	_hud.show_placeholder_notice(_session.is_placeholder())
	return true


## Resumes a saved run. The match configuration travels inside the save so the
## session rebuilds exactly the run that was written, and the slot number lets a
## networked session tell the authoritative server which slot to load.
func resume(save: Dictionary) -> bool:
	var match_config: Dictionary = (
		save.get("match_config", {}) as Dictionary
	).duplicate(true)
	match_config["content_hash"] = str(save.get("content_hash", ""))
	match_config["resume_slot"] = int(save.get("slot", -1))
	# The transport version is a wire property of this session, not saved run
	# state; a save written under an older transport still resumes. The save
	# payload itself stays gated by its own schema version and content hash.
	match_config["protocol_version"] = ProtocolCodec.VERSION
	# Server-written slots carry the authoritative config, which never included
	# the client-side seat_count; derive it from the mode so the saved match
	# validates.
	match_config["seat_count"] = WBMatchContract.seat_count_for_mode(
		str(match_config.get("mode", "solo"))
	)
	var state: Dictionary = save.get("state", {})
	var progression: Dictionary = state.get("shared_progression", {})
	match_config["hiscore"] = int(progression.get("score", 0))
	return begin(match_config)


func _exit_tree() -> void:
	_assets.clear()


func _physics_process(_delta: float) -> void:
	if not _session.is_active() or _session.is_paused() or _finished:
		return
	if _secret_active:
		if (_input.mask_for_seat(0) & WBInputRouter.INPUT_FIRE) != 0:
			_dismiss_secret_screen()
		return
	var seat_count := int(_config.get("seat_count", 1))
	for seat in range(seat_count):
		var mask := (
			WBDemoPilot.input_for(_snapshot)
			if _demo and seat == 0
			else filtered_input_mask(_input.mask_for_seat(seat))
		)
		if _credits_continue_armed and seat == 0:
			mask |= WBInputRouter.INPUT_CONFIRM
		_session.submit_input(seat, mask)
	if _credits_continue_armed:
		# The credits interstitial exits on a single confirm edge.
		_credits_continue_armed = false
	_session.advance_tick()


func filtered_input_mask(mask: int) -> int:
	if _current_phase == "shop":
		return 0
	if _party_active and _chat_input_focused():
		return 0
	var normalized := WBInputRouter.normalize_mask(mask)
	if _secret_active:
		return normalized & WBInputRouter.INPUT_FIRE
	if _current_phase == "rank_promotion":
		return normalized & WBInputRouter.INPUT_FIRE
	if _current_phase == "credits":
		return normalized & (
			WBInputRouter.INPUT_CONFIRM | WBInputRouter.INPUT_FIRE
		)
	if _current_phase == "bonus_mode":
		match str(_snapshot.get("bonus_mode", {}).get("kind", "")):
			"memory_station":
				return normalized & (
					WBInputRouter.INPUT_LEFT
					| WBInputRouter.INPUT_RIGHT
					| WBInputRouter.INPUT_UP
					| WBInputRouter.INPUT_DOWN
					| WBInputRouter.INPUT_FIRE
					| WBInputRouter.INPUT_SECONDARY
				)
			"meteor_storm":
				return normalized & (
					WBInputRouter.INPUT_LEFT
					| WBInputRouter.INPUT_RIGHT
					| WBInputRouter.INPUT_FIRE
				)
			"gem_drop":
				# Retail state 18 runs horizontal movement and primary fire, while
				# its later secondary-weapon path is explicitly suppressed.
				return normalized & (
					WBInputRouter.INPUT_LEFT
					| WBInputRouter.INPUT_RIGHT
					| WBInputRouter.INPUT_FIRE
				)
		return 0
	return normalized


func _unhandled_input(event: InputEvent) -> void:
	if _demo:
		# Retail attract play ends on any human input.
		var pressed := (
			(event is InputEventKey and event.is_pressed() and not event.is_echo())
			or (event is InputEventMouseButton and event.is_pressed())
			or (event is InputEventJoypadButton and event.is_pressed())
		)
		if pressed:
			get_viewport().set_input_as_handled()
			_session.close()
			exit_requested.emit({"demo": true})
		return
	if _secret_active and event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and not mb.is_echo():
			_dismiss_secret_screen()
			get_viewport().set_input_as_handled()
		return
	if (
		_ending_presentation != null
		and _ending_presentation.is_active()
		and _ending_presentation.handle_input(event)
	):
		get_viewport().set_input_as_handled()
		return
	if _party_active and _current_phase == "level" and not _finished and event is InputEventKey:
		var key := event as InputEventKey
		if (
			key.pressed
			and not key.echo
			and key.keycode in [KEY_ENTER, KEY_KP_ENTER]
			and not _chat_input_focused()
		):
			_chat_dock.visible = true
			_chat_dock_panel.focus_input()
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("pause") and _current_phase == "level" and not _finished:
		_toggle_pause()
		get_viewport().set_input_as_handled()
		return
	if (
		_current_phase != "bonus_mode"
		or str(_snapshot.get("bonus_mode", {}).get("kind", "")) != "memory_station"
		or not event is InputEventMouseButton
	):
		return
	var mouse_button := event as InputEventMouseButton
	if not mouse_button.pressed or mouse_button.is_echo():
		return
	var bonus: Dictionary = _snapshot.get("bonus_mode", {})
	var owner_seat_id := int(bonus.get("owner_seat_id", 0))
	var local_owner_seat_id := _session.local_seat_for_authoritative(owner_seat_id)
	if local_owner_seat_id < 0:
		return
	var result: Dictionary = {}
	if mouse_button.button_index == MOUSE_BUTTON_LEFT:
		var logical_position := WBAspectFit.output_to_logical(
			mouse_button.position,
			_renderer.output_rect()
		)
		var tile_index := memory_tile_index_from_logical(logical_position, bonus)
		if tile_index < 0:
			return
		result = _session.submit_bonus_action(
			local_owner_seat_id,
			Protocol.BONUS_ACTION_SELECT_TILE,
			tile_index
		)
	elif mouse_button.button_index == MOUSE_BUTTON_RIGHT:
		result = _session.submit_bonus_action(
			local_owner_seat_id,
			Protocol.BONUS_ACTION_KILL_TIME,
			-1
		)
	else:
		return
	if bool(result.get("accepted", false)) or bool(result.get("pending", false)):
		get_viewport().set_input_as_handled()


static func memory_tile_index_from_logical(
	logical_position: Vector2,
	bonus_mode: Dictionary
) -> int:
	var tiles: Array = bonus_mode.get("tiles", [])
	var declared_tile_size := maxf(
		1.0,
		float(bonus_mode.get("tile_size", bonus_mode.get("tile_size_px", 64)))
	)
	for tile_value in tiles:
		if not tile_value is Dictionary:
			continue
		var tile := tile_value as Dictionary
		var tile_rect := Rect2(
			Vector2(float(tile.get("x", 0)), float(tile.get("y", 0))),
			Vector2(declared_tile_size, declared_tile_size)
		)
		if tile_rect.has_point(logical_position):
			return int(tile.get("tile_index", -1))
	var columns := maxi(
		1,
		int(bonus_mode.get("grid_columns", bonus_mode.get("columns", 0)))
	)
	var rows := maxi(
		1,
		int(bonus_mode.get("grid_rows", bonus_mode.get("rows", columns)))
	)
	var tile_size := declared_tile_size
	var origin := Vector2(
		float(bonus_mode.get("grid_origin_x", (800.0 - columns * tile_size) * 0.5)),
		float(bonus_mode.get("grid_origin_y", (600.0 - rows * tile_size) * 0.5))
	)
	var relative := logical_position - origin
	if (
		relative.x < 0.0
		or relative.y < 0.0
		or relative.x >= float(columns) * tile_size
		or relative.y >= float(rows) * tile_size
	):
		return -1
	var column := int(floor(relative.x / tile_size))
	var row := int(floor(relative.y / tile_size))
	# Retail stores its cursor target in an 8-row fixed-stride, column-major
	# array even while the visible grid is smaller than 8x8.
	return column * 8 + row


func _on_snapshot(snapshot: Dictionary) -> void:
	_snapshot = snapshot
	_renderer.set_snapshot(snapshot)
	_hud.update_snapshot(snapshot)
	var level_id := int(snapshot.get("level_id", 1))
	if level_id != _current_level:
		_current_level = level_id
		_show_level_banner(level_id, str(snapshot.get("level_title", "")))
	var phase := str(snapshot.get("phase", "level"))
	if phase != _current_phase:
		_current_phase = phase
		_apply_phase(phase)
	if phase == "shop":
		_refresh_shop(snapshot)
	elif phase == "rank_promotion":
		_refresh_rank_promotion(snapshot)
	elif phase == "get_ready":
		_refresh_get_ready(snapshot)
	for hurry_up_value: Variant in snapshot.get("events", []):
		if not hurry_up_value is Dictionary:
			continue
		var hurry_up_event: Dictionary = hurry_up_value
		if str(hurry_up_event.get("type", "")) != "hurry_up_banner":
			continue
		var hurry_up_event_id := int(hurry_up_event.get("event_id", -1))
		if hurry_up_event_id >= 0:
			if _seen_hurry_up_events.has(hurry_up_event_id):
				continue
			_seen_hurry_up_events[hurry_up_event_id] = true
		_show_hurry_up_banner(
			str(hurry_up_event.get("text", "H U R R Y   U P")),
			int(hurry_up_event.get("duration_ms", 1000))
		)
	if not _secret_active:
		for event_value: Variant in snapshot.get("events", []):
			if not event_value is Dictionary:
				continue
			var event: Dictionary = event_value
			if str(event.get("type", "")) != "shop_secret_selected":
				continue
			var event_id := int(event.get("event_id", -1))
			if event_id >= 0 and _seen_secret_events.has(event_id):
				continue
			if event_id >= 0:
				_seen_secret_events[event_id] = true
			var secret_id := int(event.get("secret_id", 0))
			var asset_key := str(event.get("asset_key", "secret_%02d" % (secret_id + 1)))
			_show_secret_screen(secret_id, asset_key)
			break
	if _party_active:
		_refresh_party_overlay()


func _apply_phase(phase: String) -> void:
	_pause_overlay.visible = false
	_shop_overlay.visible = phase == "shop"
	_rank_promotion_overlay.visible = phase == "rank_promotion"
	_result_overlay.visible = false
	if _secret_active and phase != "shop":
		_dismiss_secret_screen()
	_get_ready_overlay.visible = phase == "get_ready"
	_hud.visible = phase == "level"
	if _party_active:
		_chat_dock.visible = phase == "level"
	if phase in ["complete", "game_over"]:
		_emit_match_finished(phase)
	if phase == "complete" and _should_present_ending() and not _ending_finished:
		_finished = true
		_begin_ending()
	elif phase in ["complete", "game_over", "results"]:
		_clear_profile_persistence_gate_ui()
		_result_overlay.visible = true
		_finished = true
		_show_results(phase)
	elif phase == "credits":
		_begin_credits_interstitial()
	elif phase == "shop":
		_ready_signature = ""
		_shop_notice = ""
		_focus_shop_control.call_deferred()


## Terminal phases publish the run summary exactly once so the shell can
## record it (and, when online, report it to the lobby server).
func _emit_match_finished(phase: String) -> void:
	if _match_finished_emitted or _demo:
		return
	_match_finished_emitted = true
	var result := _build_result()
	result["phase"] = phase
	result["duration_ticks"] = int(_snapshot.get("tick", 0))
	match_finished.emit(result)


func _toggle_pause() -> void:
	var paused := not _session.is_paused()
	_session.set_paused(paused)


func _retire_run() -> void:
	# Retail retire needs no confirmation: the run ends as if the last
	# fighter was lost and the game-over tally follows.
	if _session.request_retire():
		_pause_overlay.visible = false


func _on_pause_changed(paused: bool) -> void:
	if _party_active:
		# Online co-op shows the party room (chat, START/RESUME) instead of
		# the retail pause art, for the host and the joiner alike.
		_refresh_party_overlay()
		return
	_pause_overlay.visible = paused
	if paused:
		_focus_first_enabled_button.call_deferred(_pause_overlay)


func _create_level_banner() -> void:
	_level_banner.set_anchors_preset(Control.PRESET_CENTER)
	_level_banner.position = Vector2(-300.0, -60.0)
	_level_banner.size = Vector2(600.0, 120.0)
	_level_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_level_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_level_banner.add_theme_font_size_override("font_size", 34)
	_level_banner.add_theme_color_override("font_color", Color("#ffe898"))
	_level_banner.add_theme_color_override("font_shadow_color", Color("#00000080"))
	_level_banner.add_theme_constant_override("shadow_offset_x", 2)
	_level_banner.add_theme_constant_override("shadow_offset_y", 2)
	_level_banner.visible = false
	add_child(_level_banner)
	_level_banner_timer.one_shot = true
	_level_banner_timer.wait_time = 2.2
	_level_banner_timer.timeout.connect(func() -> void: _level_banner.visible = false)
	add_child(_level_banner_timer)
	# Retail writes "H U R R Y   U P" into its shared message slot with a
	# one-second deadline (docs/evidence/HURRY_UP_SECRET_SHIPS.md).
	_hurry_up_banner.set_anchors_preset(Control.PRESET_CENTER)
	_hurry_up_banner.position = Vector2(-300.0, -140.0)
	_hurry_up_banner.size = Vector2(600.0, 60.0)
	_hurry_up_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hurry_up_banner.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hurry_up_banner.add_theme_font_size_override("font_size", 30)
	_hurry_up_banner.add_theme_color_override("font_color", Color("#ff7a4b"))
	_hurry_up_banner.add_theme_color_override("font_shadow_color", Color("#00000080"))
	_hurry_up_banner.add_theme_constant_override("shadow_offset_x", 2)
	_hurry_up_banner.add_theme_constant_override("shadow_offset_y", 2)
	_hurry_up_banner.visible = false
	_hurry_up_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hurry_up_banner)
	_hurry_up_banner_timer.one_shot = true
	_hurry_up_banner_timer.wait_time = 1.0
	_hurry_up_banner_timer.timeout.connect(
		func() -> void: _hurry_up_banner.visible = false
	)
	add_child(_hurry_up_banner_timer)


func _show_hurry_up_banner(text: String, duration_ms: int) -> void:
	_hurry_up_banner.text = text
	_hurry_up_banner.visible = true
	_hurry_up_banner_timer.wait_time = maxf(0.1, float(duration_ms) / 1000.0)
	_hurry_up_banner_timer.start()


func level_banner_text(level_id: int, level_title: String) -> String:
	var title := level_title.strip_edges()
	if title.is_empty():
		return "LEVEL %d" % level_id
	return "LEVEL %d\n%s" % [level_id, title]


func _show_level_banner(level_id: int, level_title: String) -> void:
	_level_banner.text = level_banner_text(level_id, level_title)
	_level_banner.visible = true
	_level_banner_timer.start()


func _create_get_ready_overlay() -> void:
	_get_ready_overlay = _overlay(Color(0.01, 0.02, 0.06, 0.82))
	_get_ready_overlay.name = "GetReadyOverlay"
	_get_ready_overlay.visible = false
	add_child(_get_ready_overlay)

	_get_ready_label.text = "GET READY"
	_get_ready_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_get_ready_label.add_theme_font_size_override("font_size", 36)
	_get_ready_label.add_theme_color_override("font_color", Color("#ffe898"))
	_get_ready_label.add_theme_color_override("font_shadow_color", Color("#00000080"))
	_get_ready_label.add_theme_constant_override("shadow_offset_x", 2)
	_get_ready_label.add_theme_constant_override("shadow_offset_y", 2)
	_get_ready_label.set_anchors_preset(Control.PRESET_CENTER)
	_get_ready_label.position = Vector2(-200.0, -54.0)
	_get_ready_label.size = Vector2(400.0, 48.0)
	_get_ready_overlay.add_child(_get_ready_label)

	_get_ready_level.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_get_ready_level.add_theme_font_size_override("font_size", 28)
	_get_ready_level.add_theme_color_override("font_color", Color("#ffe17a"))
	_get_ready_level.set_anchors_preset(Control.PRESET_CENTER)
	_get_ready_level.position = Vector2(-200.0, 8.0)
	_get_ready_level.size = Vector2(400.0, 40.0)
	_get_ready_overlay.add_child(_get_ready_level)


func _refresh_get_ready(snapshot: Dictionary) -> void:
	var next_level := int(snapshot.get("get_ready", {}).get("next_level_id", snapshot.get("level_id", 1)))
	var level_title := str(snapshot.get("get_ready", {}).get("next_level_title", "")).strip_edges()
	if level_title.is_empty():
		_get_ready_level.text = "LEVEL %d" % next_level
	else:
		_get_ready_level.text = "%s\nLEVEL %d" % [level_title, next_level]


func _create_pause_overlay() -> void:
	# Retail pause dims nothing: the big magenta PAUSE art rotates ninety
	# degrees onto the playfield center while the game stays visible.
	_pause_overlay = _overlay(Color(0.01, 0.02, 0.06, 0.0))
	_pause_overlay.visible = false
	add_child(_pause_overlay)

	var pause_texture := _assets.texture("pause3")
	if pause_texture != null:
		var pause_art := TextureRect.new()
		pause_art.texture = pause_texture
		pause_art.set_anchors_preset(Control.PRESET_CENTER)
		# 90° clockwise around its center: the horizontal 252x128 art becomes
		# the retail vertical 128x252 banner (reads top-to-bottom).
		pause_art.position = Vector2(-126.0, -64.0)
		pause_art.size = Vector2(252.0, 128.0)
		pause_art.pivot_offset = Vector2(126.0, 64.0)
		pause_art.rotation = PI * 0.5
		pause_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pause_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
		pause_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_pause_overlay.add_child(pause_art)
	else:
		var paused_heading := _heading("PAUSE ART ASSET ERROR")
		paused_heading.set_anchors_preset(Control.PRESET_CENTER)
		paused_heading.position = Vector2(-180.0, -60.0)
		paused_heading.size = Vector2(360.0, 120.0)
		_pause_overlay.add_child(paused_heading)

	var actions := HBoxContainer.new()
	actions.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	actions.position = Vector2(-260.0, -52.0)
	actions.size = Vector2(520.0, 44.0)
	actions.add_theme_constant_override("separation", 10)
	_pause_overlay.add_child(actions)
	var resume := _button("RESUME")
	resume.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	resume.pressed.connect(_toggle_pause)
	actions.add_child(resume)
	var retire := _button("RETIRE")
	retire.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	retire.pressed.connect(_retire_run)
	actions.add_child(retire)
	var restart := _button("RESTART RUN")
	restart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	restart.pressed.connect(_restart)
	actions.add_child(restart)
	var leave := _button("RETURN TO MENU")
	leave.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	leave.pressed.connect(_leave_run)
	actions.add_child(leave)


func _create_shop_overlay() -> void:
	_shop_overlay = _overlay(Color(0.015, 0.025, 0.07, 0.25))
	_shop_overlay.visible = false
	add_child(_shop_overlay)
	var shop_texture := _assets.texture("butikk3")
	if shop_texture != null:
		var shop_art := TextureRect.new()
		shop_art.texture = shop_texture
		shop_art.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		shop_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		shop_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		shop_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_shop_overlay.add_child(shop_art)
		_shop_overlay.move_child(shop_art, 0)
	# Controls sit inside the native butikk3 panel regions: the top-left
	# monitor shows the focused item, the top-right display shows cash, the
	# big right panel lists items, and the bottom-left bar holds the exits.
	_shop_info.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_shop_info.position = Vector2(66.0, 34.0)
	_shop_info.size = Vector2(282.0, 210.0)
	_shop_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_shop_info.add_theme_font_size_override("font_size", 15)
	_shop_info.add_theme_color_override("font_color", Color("#d8f7ff"))
	_shop_overlay.add_child(_shop_info)
	_shop_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_shop_status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_shop_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_shop_status.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_shop_status.position = Vector2(505.0, 30.0)
	_shop_status.size = Vector2(220.0, 58.0)
	_shop_status.add_theme_font_size_override("font_size", 14)
	_shop_status.add_theme_color_override("font_color", Color("#ffd66b"))
	_shop_overlay.add_child(_shop_status)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_preset(Control.PRESET_TOP_LEFT)
	scroll.position = Vector2(460.0, 122.0)
	scroll.size = Vector2(268.0, 376.0)
	_shop_overlay.add_child(scroll)
	_shop_grid.columns = 1
	_shop_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_shop_grid.add_theme_constant_override("h_separation", 6)
	_shop_grid.add_theme_constant_override("v_separation", 6)
	scroll.add_child(_shop_grid)
	_ready_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_ready_box.add_theme_constant_override("separation", 12)
	_ready_box.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_ready_box.position = Vector2(100.0, 462.0)
	_ready_box.size = Vector2(320.0, 52.0)
	_shop_overlay.add_child(_ready_box)


func _refresh_shop(snapshot: Dictionary) -> void:
	var shop: Dictionary = snapshot.get("shop", {})
	var items: Array = shop.get("items", [])
	var signature := JSON.stringify(items)
	var shared: Dictionary = snapshot.get("shared", {})
	if not _shop_notice.is_empty() and Time.get_ticks_msec() >= _shop_notice_until_msec:
		_shop_notice = ""
	if not _shop_notice.is_empty():
		_shop_status.text = _shop_notice
	elif items.is_empty():
		_shop_status.text = "SHOP DATA ERROR: AUTHORITATIVE ITEM LIST IS EMPTY"
	else:
		_shop_status.text = "AVAILABLE CASH: $ %d" % int(shared.get("money", 0))
	if signature != _shop_signature:
		_shop_signature = signature
		for child in _shop_grid.get_children():
			child.queue_free()
		for entry: Variant in items:
			if entry is Dictionary:
				_add_shop_item(entry)
	_rebuild_ready_buttons(shop)
	_focus_shop_control.call_deferred()


func _add_shop_item(item: Dictionary) -> void:
	var item_id := int(item.get("id", item.get("item_id", 0)))
	var item_name := str(item.get("name", "ITEM %d" % item_id))
	var price := int(item.get("price", 0))
	var available := bool(item.get("available", true)) and not bool(item.get("purchased", false))
	var button := _button("%02d  %s\n$ %d" % [item_id, item_name, price])
	button.custom_minimum_size = Vector2(248.0, 54.0)
	button.disabled = not available
	var icon := _assets.texture(shop_icon_key(item_id))
	if icon != null:
		button.icon = icon
		button.expand_icon = true
	button.pressed.connect(func() -> void: _purchase(item_id))
	button.focus_entered.connect(func() -> void:
		_shop_info.text = "%02d  %s\n$ %d" % [item_id, item_name, price]
	)
	_shop_grid.add_child(button)


func _purchase(item_id: int) -> void:
	var seat := _shop_request_seat_id()
	var local_seat := _local_seat_for(seat)
	if local_seat < 0:
		_show_shop_notice("P%d IS SHOPPING" % (seat + 1))
		return
	var result := _session.request_purchase(local_seat, item_id)
	if not bool(result.get("accepted", false)):
		_show_shop_notice("PURCHASE REJECTED: %s" % str(result.get("reason", "UNAVAILABLE")).to_upper())
	elif bool(result.get("pending", false)):
		_show_shop_notice("PURCHASE PENDING SERVER CONFIRMATION")


func _on_purchase_completed(result: Dictionary) -> void:
	if bool(result.get("accepted", false)):
		_show_shop_notice("PURCHASE ACCEPTED")
	else:
		_show_shop_notice("PURCHASE REJECTED: %s" % str(
			result.get("reason", "UNAVAILABLE")
		).replace("_", " ").to_upper())


func _rebuild_ready_buttons(shop: Dictionary) -> void:
	var ready: Array = shop.get("ready", [])
	var seat_count := int(_config.get("seat_count", 1))
	var rows: Array = []
	for seat in range(seat_count):
		rows.append({
			"seat": seat,
			"ready": bool(ready[seat]) if seat < ready.size() else false,
			"local_seat": _local_seat_for(seat),
		})
	var can_save := _can_save_here()
	var signature := JSON.stringify([rows, can_save])
	if signature == _ready_signature:
		return
	_ready_signature = signature
	for child in _ready_box.get_children():
		_ready_box.remove_child(child)
		child.queue_free()
	for row_value: Variant in rows:
		var row: Dictionary = row_value
		var seat := int(row["seat"])
		var is_ready := bool(row["ready"])
		var local_seat := int(row["local_seat"])
		if local_seat < 0:
			# The other party member's seat: its state, never a control here.
			var state := _button("P%d %s" % [seat + 1, "READY" if is_ready else "SHOPPING"])
			state.disabled = true
			_ready_box.add_child(state)
			continue
		var button := _button("P%d %s" % [seat + 1, "READY" if is_ready else "LEAVE SHOP"])
		button.disabled = is_ready
		button.pressed.connect(func() -> void: _session.set_ready(local_seat, true))
		_ready_box.add_child(button)
	if can_save:
		var save_button := _button("SAVE GAME")
		save_button.pressed.connect(_request_shop_save)
		_ready_box.add_child(save_button)


## Shop controls address authoritative seats while the session speaks in
## local seats (a joiner's only seat is local 0 but authoritative 1). A seat
## with no local counterpart belongs to the other party member.
func _local_seat_for(authoritative_seat: int) -> int:
	if not _party_active:
		return authoritative_seat
	return _session.local_seat_for_authoritative(authoritative_seat)


## The game server writes save slots on the machine that runs it, so only a
## local session or the party host can save a run it will be able to load.
func _can_save_here() -> bool:
	if not _session.can_save_run():
		return false
	return not _party_active or party_role() == "host"


func _show_shop_notice(text: String) -> void:
	_shop_notice = text
	_shop_notice_until_msec = Time.get_ticks_msec() + SHOP_NOTICE_MSEC
	_shop_status.text = text


func _on_save_completed(accepted: bool, details: Dictionary) -> void:
	var slot := int(details.get("slot", 0))
	if accepted:
		_show_shop_notice("SAVED TO SLOT %d" % (slot + 1))
	else:
		_show_shop_notice("SAVE FAILED: %s" % str(
			details.get("reason", "UNKNOWN")
		).replace("_", " ").to_upper())


func _request_shop_save() -> void:
	shop_save_requested.emit()


## The shell owns slot selection; the authoritative game server owns the run
## state and writes the slot itself.
func request_shop_save(slot: int) -> bool:
	return _session.request_save(slot)


func report_shop_save(message: String) -> void:
	_show_shop_notice(message)


func _shop_request_seat_id() -> int:
	var shop: Dictionary = _snapshot.get("shop", {})
	return maxi(0, int(shop.get("active_seat_id", 0)))


func shop_icon_key(item_id: int) -> String:
	return str({
		1: "shop_speed", 2: "shop_bullet", 3: "shop_doubleshot",
		4: "shop_lessspeed", 5: "shop_tripleshot", 6: "shop_quad",
		7: "shop_autofire", 8: "shop_supertriple", 9: "shop_armour",
		10: "shop_plasma", 11: "shop_extralife", 12: "shop_fireballs",
		13: "shop_secret", 14: "shop_rank", 15: "shop_extratime",
		16: "shop_laser", 17: "shop_wariplasma", 18: "shop_rocketpack",
		19: "shop_alienlock", 20: "shop_autofire_super",
	}.get(item_id, ""))


func _focus_shop_control() -> void:
	var focus := get_viewport().gui_get_focus_owner()
	if focus != null and _shop_overlay.is_ancestor_of(focus):
		return
	_focus_first_enabled_button(_shop_overlay)


func _focus_first_enabled_button(root: Node) -> void:
	for candidate in root.find_children("*", "Button", true, false):
		var button := candidate as Button
		if button != null and button.visible and not button.disabled:
			button.grab_focus()
			return


func _create_secret_overlay() -> void:
	_secret_overlay = _overlay(Color(0.01, 0.02, 0.06, 0.94))
	_secret_overlay.name = "SecretOverlay"
	_secret_overlay.visible = false
	add_child(_secret_overlay)

	_secret_background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_secret_background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_secret_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_secret_overlay.add_child(_secret_background)

	_secret_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_secret_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_secret_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_secret_overlay.add_child(_secret_image)

	_secret_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_secret_label.add_theme_font_size_override("font_size", 22)
	_secret_label.add_theme_color_override("font_color", Color("#ffe898"))
	_secret_label.text = "SECRET FOUND"
	_secret_overlay.add_child(_secret_label)

	var prompt := Label.new()
	prompt.name = "SecretPrompt"
	prompt.text = "PRESS FIRE OR CLICK TO CONTINUE"
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.add_theme_font_size_override("font_size", 16)
	prompt.add_theme_color_override("font_color", Color("#ffffff"))
	_secret_overlay.add_child(prompt)


func _show_secret_screen(secret_id: int, asset_key: String) -> void:
	if _secret_active:
		return
	_secret_active = true
	var background_texture := _assets.texture("secretscreen_new")
	var secret_texture := _assets.texture(asset_key)
	var logical_width := 800.0
	var logical_height := 600.0

	_secret_background.texture = background_texture
	if background_texture != null:
		var bg_width := maxf(1.0, float(background_texture.get_width()))
		var bg_height := maxf(1.0, float(background_texture.get_height()))
		_secret_background.set_anchors_preset(Control.PRESET_CENTER)
		_secret_background.position = Vector2(-bg_width * 0.5, -bg_height * 0.5)
		_secret_background.size = Vector2(bg_width, bg_height)

	_secret_image.texture = secret_texture
	if secret_texture != null:
		var img_width := maxf(1.0, float(secret_texture.get_width()))
		var img_height := maxf(1.0, float(secret_texture.get_height()))
		_secret_image.set_anchors_preset(Control.PRESET_CENTER)
		_secret_image.position = Vector2(-img_width * 0.5, -img_height * 0.5 - 20.0)
		_secret_image.size = Vector2(img_width, img_height)

	_secret_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_secret_label.position = Vector2(-200.0, 42.0)
	_secret_label.size = Vector2(400.0, 40.0)

	var prompt := _secret_overlay.get_node_or_null(NodePath("SecretPrompt")) as Label
	if prompt != null:
		prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		prompt.position = Vector2(-300.0, -38.0)
		prompt.size = Vector2(600.0, 36.0)

	_secret_overlay.visible = true
	_shop_overlay.visible = false
	audio_requested.emit({
		"category": "voice",
		"key": "secretfound",
		"priority": 95,
		"max_voices": 1,
		"event_id": "secret_reveal_%d_%d" % [secret_id, get_instance_id()],
	})


func _dismiss_secret_screen() -> void:
	if not _secret_active:
		return
	_secret_active = false
	_secret_overlay.visible = false
	if _current_phase == "shop":
		_shop_overlay.visible = true
		_focus_shop_control.call_deferred()


func _create_rank_promotion_overlay() -> void:
	_rank_promotion_overlay = _overlay(Color(0.01, 0.02, 0.06, 0.86))
	_rank_promotion_overlay.name = "RankPromotionOverlay"
	_rank_promotion_overlay.visible = false
	add_child(_rank_promotion_overlay)

	var panel := _center_panel(_rank_promotion_overlay, Vector2(620.0, 330.0))
	var column := _column(panel)
	_rank_promotion_title.text = "C O N G R A T U L A T I O N S"
	_rank_promotion_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rank_promotion_title.add_theme_font_size_override("font_size", 28)
	_rank_promotion_title.add_theme_color_override("font_color", Color("#ffd66b"))
	column.add_child(_rank_promotion_title)

	_rank_promotion_status.text = "YOU ARE HEREBY PROMOTED TO"
	_rank_promotion_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rank_promotion_status.add_theme_font_size_override("font_size", 20)
	column.add_child(_rank_promotion_status)

	_rank_promotion_player.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rank_promotion_player.add_theme_color_override("font_color", Color("#9ab6cf"))
	column.add_child(_rank_promotion_player)

	var rank_row := HBoxContainer.new()
	rank_row.alignment = BoxContainer.ALIGNMENT_CENTER
	rank_row.add_theme_constant_override("separation", 18)
	column.add_child(rank_row)
	_rank_promotion_rank.add_theme_font_size_override("font_size", 24)
	_rank_promotion_rank.add_theme_color_override("font_color", Color("#ffe898"))
	rank_row.add_child(_rank_promotion_rank)
	var badge_atlas := _assets.texture("ranks2")
	if badge_atlas != null:
		_rank_promotion_badge_texture.atlas = badge_atlas
		_rank_promotion_badge.texture = _rank_promotion_badge_texture
	_rank_promotion_badge.custom_minimum_size = Vector2(128.0, 26.0)
	_rank_promotion_badge.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_rank_promotion_badge.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_rank_promotion_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rank_row.add_child(_rank_promotion_badge)

	_rank_promotion_prompt.text = "PRESS FIRE TO CONTINUE"
	_rank_promotion_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rank_promotion_prompt.add_theme_font_size_override("font_size", 20)
	_rank_promotion_prompt.add_theme_color_override("font_color", Color("#ffffff"))
	column.add_child(_rank_promotion_prompt)


func _refresh_rank_promotion(snapshot: Dictionary) -> void:
	var promotion: Dictionary = snapshot.get("rank_promotion", {})
	var shared: Dictionary = snapshot.get("shared", {})
	var seat_id := int(promotion.get("seat_id", snapshot.get("turn_seat", 0)))
	var rank := int(promotion.get("rank", shared.get("rank", 0)))
	var rank_cap := maxi(0, int(promotion.get("rank_cap", shared.get("rank_cap", rank))))
	var rank_name := str(promotion.get("rank_name", "")).strip_edges()
	var badge_y := maxi(0, int(promotion.get("badge_y", rank * 13)))
	_rank_promotion_player.text = "PLAYER %d" % (seat_id + 1)
	_rank_promotion_rank.text = (
		rank_name if not rank_name.is_empty() else "RANK %d / %d" % [rank, rank_cap]
	)
	_rank_promotion_badge.visible = _rank_promotion_badge_texture.atlas != null
	_rank_promotion_badge_texture.region = Rect2(0.0, float(badge_y), 64.0, 13.0)
	_rank_promotion_prompt.visible = bool(promotion.get("prompt_visible", false))


func _create_result_overlay() -> void:
	_result_overlay = _overlay(Color(0.01, 0.02, 0.06, 0.94))
	_result_overlay.visible = false
	add_child(_result_overlay)
	var gameover_texture := _assets.texture("gameover")
	if gameover_texture != null:
		_gameover_art.texture = gameover_texture
		_gameover_art.set_anchors_preset(Control.PRESET_CENTER)
		_gameover_art.position = Vector2(-256.0, -180.0)
		_gameover_art.size = Vector2(512.0, 128.0)
		_gameover_art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_gameover_art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_gameover_art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_result_overlay.add_child(_gameover_art)
	var column := VBoxContainer.new()
	column.set_anchors_preset(Control.PRESET_CENTER)
	column.position = Vector2(-235.0, -20.0)
	column.size = Vector2(470.0, 300.0)
	column.add_theme_constant_override("separation", 18)
	_result_overlay.add_child(column)
	_result_heading = _heading("RUN COMPLETE")
	_result_heading.add_theme_color_override("font_color", Color("#ffe17a"))
	column.add_child(_result_heading)
	_result_summary.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_summary.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_result_summary.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_result_summary.add_theme_font_size_override("font_size", 22)
	_result_summary.add_theme_color_override("font_color", Color("#ffe898"))
	column.add_child(_result_summary)
	_result_persistence_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_persistence_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_result_persistence_status.add_theme_color_override("font_color", Color("#ffb4a2"))
	_result_persistence_status.visible = false
	column.add_child(_result_persistence_status)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	column.add_child(actions)
	_result_retry_button = _button("RETRY SAVE")
	_result_retry_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_result_retry_button.visible = false
	_result_retry_button.disabled = true
	_result_retry_button.pressed.connect(retry_authoritative_result_persist)
	actions.add_child(_result_retry_button)
	_result_done_button = _button("RETURN TO MENU")
	_result_done_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_result_done_button.pressed.connect(_leave_run)
	actions.add_child(_result_done_button)


func _create_ending_presentation() -> void:
	_ending_presentation = WBEndingPresentation.new()
	_ending_presentation.name = "EndingPresentation"
	_ending_presentation.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_ending_presentation.dismissed.connect(_on_ending_dismissed)
	_ending_presentation.audio_requested.connect(
		func(request: Dictionary) -> void: audio_requested.emit(request)
	)
	add_child(_ending_presentation)


func _should_present_ending() -> bool:
	var terminal := _campaign_terminal()
	return (
		str(terminal.get("kind", "")) == "level_100"
		and bool(terminal.get("full_campaign_completed", false))
		and bool(terminal.get("credits_required", false))
	)


func _begin_ending() -> void:
	if _demo:
		# Demo attract runs record nothing: skip the persistence gate and
		# return straight to the title.
		_session.close()
		exit_requested.emit({"demo": true})
		return
	if _profile_result_persisted:
		_start_ending_after_persist()
		return
	if _profile_result_persist_requested:
		_show_profile_persistence_gate()
		return
	_pending_authoritative_result = _build_result()
	_profile_result_persist_requested = true
	_profile_result_persist_in_flight = true
	_profile_result_persist_error = ""
	_show_profile_persistence_gate()
	authoritative_result_ready.emit(_pending_authoritative_result.duplicate(true))


func retry_authoritative_result_persist() -> void:
	if (
		not _profile_result_persist_requested
		or _profile_result_persisted
		or _profile_result_persist_in_flight
		or _pending_authoritative_result.is_empty()
	):
		return
	_profile_result_persist_in_flight = true
	_profile_result_persist_error = ""
	_show_profile_persistence_gate()
	authoritative_result_ready.emit(_pending_authoritative_result.duplicate(true))


func mark_authoritative_result_persisted() -> void:
	if not _profile_result_persist_requested or _profile_result_persisted:
		return
	_profile_result_persisted = true
	_profile_result_persist_in_flight = false
	_profile_result_persist_error = ""
	_pending_authoritative_result["profile_result_persisted"] = true
	_clear_profile_persistence_gate_ui()
	_start_ending_after_persist()


func mark_authoritative_result_persist_failed(message := "") -> void:
	if not _profile_result_persist_requested or _profile_result_persisted:
		return
	_profile_result_persist_in_flight = false
	_profile_result_persist_error = message.strip_edges()
	if _profile_result_persist_error.is_empty():
		_profile_result_persist_error = (
			"THE CAMPAIGN RESULT COULD NOT BE SAVED. "
			+ "CHECK AVAILABLE STORAGE AND TRY AGAIN."
		)
	_show_profile_persistence_gate()


func _start_ending_after_persist() -> void:
	if _ending_started or not _profile_result_persisted:
		return
	_ending_started = true
	var ending_contract := _assets.section("ending")
	var presentation_terminal := _campaign_terminal()
	presentation_terminal["presentation_tick"] = int(_snapshot.get("tick", 0))
	var rng_value: Variant = _snapshot.get("rng", {})
	if rng_value is Dictionary:
		presentation_terminal["presentation_rng"] = (rng_value as Dictionary).duplicate(true)
	if not _ending_presentation.configure(
		_assets,
		ending_contract,
		presentation_terminal
	):
		_result_overlay.visible = true
		_show_results("complete")
		_result_summary.text += "\nCREDITS PRESENTATION ERROR\n%s" % (
			_ending_presentation.last_error.to_upper()
		)
		return
	_clear_profile_persistence_gate_ui()
	_result_overlay.visible = false
	_ending_presentation.start()
	audio_requested.emit({
		"category": "music",
		"key": _ending_presentation.music_key(),
		"action": "play",
		"event_id": "campaign_credits_music_%s" % get_instance_id(),
	})


func _begin_credits_interstitial() -> void:
	# Endless campaigns cross level 100 through the retail credits roll and
	# then continue; no result screen or profile gate appears mid-run.
	if _credits_interstitial_active:
		return
	_credits_interstitial_active = true
	var credits_value: Variant = _snapshot.get("credits", {})
	var credits := credits_value as Dictionary if credits_value is Dictionary else {}
	var presentation_terminal := {
		"kind": "level_100",
		"full_campaign_completed": false,
		"credits_required": true,
		"ending_mode_id": 0,
		"winner_seat_id": -1,
		"level_100_score": int(credits.get("score", 0)),
		"presentation_tick": int(_snapshot.get("tick", 0)),
	}
	var rng_value: Variant = _snapshot.get("rng", {})
	if rng_value is Dictionary:
		presentation_terminal["presentation_rng"] = (rng_value as Dictionary).duplicate(true)
	if not _ending_presentation.configure(
		_assets,
		_assets.section("ending"),
		presentation_terminal
	):
		# A presentation failure must never stall the campaign.
		_credits_interstitial_active = false
		_credits_continue_armed = true
		return
	_ending_presentation.visible = true
	_ending_presentation.start()
	audio_requested.emit({
		"category": "music",
		"key": _ending_presentation.music_key(),
		"action": "play",
		"event_id": "credits_interstitial_music_%s" % get_instance_id(),
	})


func _on_ending_dismissed() -> void:
	if _credits_interstitial_active:
		_credits_interstitial_active = false
		_credits_continue_armed = true
		_ending_presentation.visible = false
		return
	if _ending_finished:
		return
	_ending_finished = true
	_ending_presentation.visible = false
	_clear_profile_persistence_gate_ui()
	_result_overlay.visible = true
	_show_results("complete")


func _show_profile_persistence_gate() -> void:
	_result_overlay.visible = true
	_show_results("complete")
	_result_done_button.disabled = true
	_result_persistence_status.visible = true
	if _profile_result_persist_in_flight:
		_result_persistence_status.text = "SAVING CAMPAIGN RESULT…"
		_result_retry_button.visible = false
		_result_retry_button.disabled = true
		return
	_result_persistence_status.text = "PROFILE SAVE FAILED\n%s" % (
		_profile_result_persist_error.to_upper()
	)
	_result_retry_button.visible = true
	_result_retry_button.disabled = false
	_result_retry_button.grab_focus.call_deferred()


func _clear_profile_persistence_gate_ui() -> void:
	if _result_persistence_status == null:
		return
	_result_persistence_status.visible = false
	_result_persistence_status.text = ""
	if _result_retry_button != null:
		_result_retry_button.visible = false
		_result_retry_button.disabled = true
	if _result_done_button != null:
		_result_done_button.disabled = false


func _show_results(phase: String) -> void:
	var shared: Dictionary = _snapshot.get("shared", {})
	var result: Dictionary = _snapshot.get("result", {})
	var completed := phase == "complete" or bool(result.get("completed", false))
	_gameover_art.visible = not completed and _gameover_art.texture != null
	_result_heading.text = (
		completion_heading(int(result.get("level_reached", _snapshot.get("level_id", 1))))
		if completed
		else "RUN ENDED"
	)
	_result_summary.text = "LEVEL %d\nSCORE %09d\nCASH $ %d\nSTATE %s" % [
		int(_snapshot.get("level_id", 1)),
		int(shared.get("score", result.get("score", 0))),
		int(shared.get("money", result.get("money", 0))),
		_session.state_hash().substr(0, 12).to_upper(),
	]


func completion_heading(level_reached: int) -> String:
	if level_reached >= 3999:
		return "LEVEL 3999 REACHED — CAMPAIGN COMPLETE"
	if level_reached > 100:
		return "LEVEL %d REACHED" % level_reached
	if level_reached == 100:
		return "ALL 100 LEVELS CLEARED"
	if level_reached > 62:
		return "LEVEL %d CLEARED" % level_reached
	if level_reached >= 62:
		return "FIRST SIXTY-TWO LEVELS CLEARED"
	if level_reached >= 50:
		return "FIRST FIFTY LEVELS CLEARED"
	if level_reached >= 49:
		return "FIRST FORTY-NINE LEVELS CLEARED"
	if level_reached >= 35:
		return "FIRST THIRTY-FIVE LEVELS CLEARED"
	if level_reached >= 30:
		return "FIRST THIRTY LEVELS CLEARED"
	if level_reached >= 25:
		return "FIRST TWENTY-FIVE LEVELS CLEARED"
	if level_reached >= 20:
		return "FIRST TWENTY LEVELS CLEARED"
	if level_reached >= 10:
		return "FIRST TEN LEVELS CLEARED"
	return "LEVEL %d CLEARED" % maxi(1, level_reached)


func _restart() -> void:
	_session.close()
	_pause_overlay.visible = false
	_finished = false
	begin(_config)


func _leave_run() -> void:
	if _profile_result_persist_requested and not _profile_result_persisted:
		_show_profile_persistence_gate()
		return
	var result := _build_result()
	_session.close()
	exit_requested.emit(result)


func _build_result() -> Dictionary:
	var shared: Dictionary = _snapshot.get("shared", {})
	var result: Dictionary = _snapshot.get("result", {}).duplicate(true)
	result["completed"] = _current_phase == "complete" or bool(result.get("completed", false))
	result["level_id"] = int(_snapshot.get("level_id", 1))
	result["score"] = int(shared.get("score", result.get("score", 0)))
	result["money"] = int(shared.get("money", result.get("money", 0)))
	if not result.has("campaign_terminal"):
		result["campaign_terminal"] = _campaign_terminal()
	if not result.has("profile_stats"):
		result["profile_stats"] = _snapshot.get("profile_stats", []).duplicate(true)
	if not result.has("seat_progression"):
		result["seat_progression"] = _snapshot.get("seat_progression", []).duplicate(true)
	result["mode"] = str(_config.get("mode", "solo"))
	result["difficulty"] = str(_config.get("difficulty", "normal"))
	result["profile_result_persisted"] = _profile_result_persisted
	return result


func _campaign_terminal() -> Dictionary:
	var result_value: Variant = _snapshot.get("result", {})
	if result_value is Dictionary:
		var terminal_value: Variant = (result_value as Dictionary).get(
			"campaign_terminal",
			{}
		)
		if terminal_value is Dictionary:
			return (terminal_value as Dictionary).duplicate(true)
	var snapshot_value: Variant = _snapshot.get("campaign_terminal", {})
	return (
		(snapshot_value as Dictionary).duplicate(true)
		if snapshot_value is Dictionary
		else {}
	)


func _on_session_failed(message: String) -> void:
	_finished = true
	_current_phase = "game_over"
	if _party_active:
		_party_overlay.visible = false
		_chat_dock.visible = false
	_result_overlay.visible = true
	if _party_active and str(_party.get("role", "")) == "joiner":
		_result_summary.text = "THE HOST LEFT THE GAME\n\n%s" % message
	else:
		_result_summary.text = "GAME SERVER ERROR\n\n%s" % message


## --- Online co-op party room and chat -----------------------------------

func is_party() -> bool:
	return _party_active


func party_role() -> String:
	return str(_party.get("role", ""))


## The UDP port the hosting sidecar bound (0 when not hosting).
func listen_port() -> int:
	return _session.listen_port()


func punch_request(address: String, port: int) -> bool:
	return _session.punch_request(address, port)


## The shell describes the lobby state (LAN address, token, joiner name) and
## the room shows it under the heading.
func set_party_status(text: String) -> void:
	_party_status_text = text
	if _party_active:
		_refresh_party_overlay()


func set_party_joiner(nickname: String) -> void:
	_party["joiner_nickname"] = nickname
	if _party_active:
		_refresh_party_overlay()


func append_party_line(nickname: String, text: String) -> void:
	_party_chat.append_line(nickname, text)
	_chat_dock_panel.append_line(nickname, text)


func send_party_chat(text: String) -> void:
	_send_party_chat(text)


func party_chat_line_count() -> int:
	return _party_chat.line_count()


func party_overlay_visible() -> bool:
	return _party_overlay.visible


func party_heading_text() -> String:
	return _party_heading.text


func _chat_input_focused() -> bool:
	return (
		(_chat_dock_panel != null and _chat_dock_panel.is_input_focused())
		or (_party_chat != null and _party_chat.is_input_focused())
	)


func _on_chat_received(_seat_id: int, nickname: String, text: String) -> void:
	append_party_line(nickname, text)


func _send_party_chat(text: String) -> void:
	if not _session.send_chat(text, str(_party.get("nickname", ""))):
		_party_chat.set_status("CHAT IS NOT CONNECTED")
		_chat_dock_panel.set_status("CHAT IS NOT CONNECTED")


func _create_party_overlay() -> void:
	_party_overlay = _overlay(Color(0.01, 0.02, 0.06, 0.82))
	_party_overlay.name = "PartyOverlay"
	_party_overlay.visible = false
	add_child(_party_overlay)
	var panel := _center_panel(_party_overlay, Vector2(560.0, 470.0))
	var column := _column(panel)
	_party_heading = _heading("WAITING FOR A PLAYER")
	_party_heading.name = "PartyHeading"
	column.add_child(_party_heading)
	_party_status.name = "PartyStatus"
	_party_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_party_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_party_status.add_theme_font_size_override("font_size", 13)
	_party_status.add_theme_color_override("font_color", Color("#809bb4"))
	column.add_child(_party_status)
	_party_chat = WBChatPanel.new()
	_party_chat.name = "PartyChat"
	_party_chat.message_submitted.connect(_send_party_chat)
	column.add_child(_party_chat)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	column.add_child(actions)
	_party_start_button = _button("START")
	_party_start_button.name = "PartyStart"
	_party_start_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_party_start_button.pressed.connect(func() -> void: _session.set_paused(false))
	actions.add_child(_party_start_button)
	_party_retire_button = _button("RETIRE")
	_party_retire_button.name = "PartyRetire"
	_party_retire_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_party_retire_button.pressed.connect(_retire_run)
	actions.add_child(_party_retire_button)
	var leave := _button("RETURN TO MENU")
	leave.name = "PartyLeave"
	leave.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	leave.pressed.connect(_leave_run)
	actions.add_child(leave)


## The in-game chat dock: a compact log in the bottom-left corner; Enter
## focuses its line, Escape releases it, and gameplay input is muted while
## it has focus.
func _create_chat_dock() -> void:
	_chat_dock = Control.new()
	_chat_dock.name = "ChatDock"
	_chat_dock.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_chat_dock.position = Vector2(8.0, -136.0)
	_chat_dock.size = Vector2(340.0, 128.0)
	_chat_dock.visible = false
	_chat_dock.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_chat_dock)
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.0, 0.0, 0.0, 0.45)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chat_dock.add_child(backdrop)
	_chat_dock_panel = WBChatPanel.new()
	_chat_dock_panel.name = "ChatDockPanel"
	_chat_dock_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_chat_dock_panel.set_compact(true)
	_chat_dock_panel.message_submitted.connect(_send_party_chat)
	_chat_dock.add_child(_chat_dock_panel)


## The room gate: the host holds the match paused until START, so the
## joiner's arrival never launches the first wave unannounced. Afterwards the
## same overlay is the pause menu for both roles, and it reappears while a
## seat is empty.
func _refresh_party_overlay() -> void:
	if not _party_active:
		_party_overlay.visible = false
		return
	var role := str(_party.get("role", ""))
	if role == "host" and not _party_pause_requested and _session.is_active():
		_party_pause_requested = true
		_session.set_paused(true)
	var waiting := bool(_snapshot.get("waiting_for_seats", false))
	var paused := _session.is_paused()
	if waiting != _party_waiting:
		_party_waiting = waiting
		party_waiting.emit(waiting)
	if not _snapshot.is_empty() and not waiting and not paused:
		_party_started = true
	var show := (waiting or paused) and not _finished
	_party_overlay.visible = show
	_pause_overlay.visible = false
	if not show:
		return
	var heading := ""
	var status := _party_status_text
	var joiner := str(_party.get("joiner_nickname", "A PLAYER"))
	if role == "host":
		if waiting:
			heading = "PLAYER LEFT — WAITING FOR A NEW PLAYER" if _party_started else "WAITING FOR A PLAYER"
		elif not _party_started:
			heading = "%s JOINED" % joiner.to_upper()
			status = "PRESS START WHEN YOU ARE BOTH READY"
		else:
			heading = "PAUSED"
			status = "PRESS RESUME TO CONTINUE"
		_party_start_button.visible = true
		_party_start_button.disabled = waiting
		_party_start_button.text = "RESUME" if _party_started else "START"
		_party_retire_button.visible = true
	else:
		if waiting:
			heading = "WAITING FOR THE HOST"
		elif not _party_started:
			heading = "WAITING FOR THE HOST TO START"
			status = "SAY HELLO WHILE YOU WAIT"
		else:
			heading = "PAUSED BY THE HOST"
			status = "THE HOST CAN RESUME THE GAME"
		_party_start_button.visible = false
		_party_retire_button.visible = false
	_party_heading.text = heading
	_party_status.text = status


func _overlay(color: Color) -> Control:
	var overlay := Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = color
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(background)
	return overlay


func _center_panel(parent: Control, panel_size: Vector2) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = -panel_size * 0.5
	panel.size = panel_size
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.01, 0.02, 0.05, 0.94)
	style.border_color = Color("#3a2a10")
	style.set_border_width_all(1)
	style.corner_radius_top_left = 0
	style.corner_radius_top_right = 0
	style.corner_radius_bottom_left = 0
	style.corner_radius_bottom_right = 0
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	return panel


func _column(panel: PanelContainer) -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 26)
	margin.add_theme_constant_override("margin_right", 26)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_bottom", 22)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	return column


func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 26)
	label.add_theme_color_override("font_color", Color("#ffd66b"))
	return label


func _button(text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0.0, 40.0)
	button.add_theme_font_size_override("font_size", 15)
	return button

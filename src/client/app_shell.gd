class_name WBAppShell
extends Control

var _profiles := WBProfileStore.new()
var _hiscores := WBHiscoreStore.new()
var _saved_games := WBSaveGameStore.new()
var _identity := WBIdentityStore.new()
var _talent_cache := WBTalentCache.new()
## Tests may inject a WBFakeLobbyClient before adding the shell to the tree.
var _lobby: WBLobbyClient = null
var _talent_catalog := WBTalentCatalog.new()
var _settings_store := WBSettingsStore.new()
var _settings: Dictionary = {}
var _profile_entries: Array[Dictionary] = []
var _selected_profiles: Array[Dictionary] = []
var _assets := WBAssetLibrary.new()
var _mode := "solo"
var _difficulty := "normal"
var _coop_balance := "classic"
var _page := Control.new()
var _audio := WBAudioDirector.new()
var _gameplay: WBGameplayScreen
var _active_result_persisted := false
var _demo_active := false
var _attract_timer: Timer
var _lobby_status_label: Label
var _lobby_notice := ""
var _content_hash := ""
## Online co-op bookkeeping: role, lobby id, port, token, match id.
var _party: Dictionary = {}
var _rendezvous := WBRendezvous.new()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = _create_theme()
	_apply_profile_suffix()
	_settings = _settings_store.load_settings()
	_apply_texture_filter()
	_profile_entries = _profiles.load_profiles()
	_hiscores.load_tables()
	_selected_profiles = [_profile_entries[0]]
	_create_backdrop()
	add_child(_audio)
	_audio.configure(_settings)
	_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_page)
	_audio.play_music("title")
	_identity.load_identity()
	_talent_catalog.load_catalog()
	var catalog := ContentCatalog.load_catalog("res://content", "")
	_content_hash = str(catalog.get("content_hash", "")) if bool(catalog.get("ok", false)) else ""
	if _lobby == null:
		_lobby = _make_lobby_client()
	_configure_lobby_client()
	_lobby.seed_profile_state(_talent_cache.load_state())
	add_child(_lobby)
	add_child(_rendezvous)
	_rendezvous.probe_finished.connect(_on_probe_finished)
	_rendezvous.upnp_finished.connect(_on_upnp_finished)
	_lobby.state_changed.connect(_on_lobby_state_changed)
	_lobby.kicked.connect(_on_lobby_kicked)
	_lobby.notice.connect(_on_lobby_notice)
	_lobby.lobby_join_offer.connect(_on_lobby_join_offer)
	_lobby.lobby_joiner_left.connect(_on_lobby_joiner_left)
	_lobby.lobby_join_ready.connect(_on_lobby_join_ready)
	_lobby.lobby_join_rejected.connect(_on_lobby_join_rejected)
	_lobby.lobby_closed.connect(_on_lobby_closed)
	_lobby.points_credited.connect(func(amount: int, _reason: String) -> void:
		_announce_credit(amount)
	)
	_lobby.connect_now()
	_present_splash_overlay()
	show_title()


## --profile-suffix=<tag> keeps a second instance's identity, talent cache,
## and settings apart so two clients can run on one Mac for online smoke
## tests. Profiles, hiscores, and saves stay shared.
func _apply_profile_suffix() -> void:
	var suffix := WBCliArgs.new().value("profile-suffix").strip_edges()
	if suffix.is_empty():
		return
	_identity.configure_path("user://identity_%s.json" % suffix)
	_talent_cache.configure_path("user://talent_cache_%s.json" % suffix)
	_settings_store.configure_path("user://settings_%s.json" % suffix)


func _make_lobby_client() -> WBLobbyClient:
	if WBCliArgs.new().has_flag("fake-lobby"):
		return WBFakeLobbyClient.new()
	return WBLobbyClient.new()


func _configure_lobby_client() -> void:
	var lobby_config := WBSettingsStore.lobby_config(_settings)
	_lobby.configure(
		_identity,
		str(lobby_config.get("host", "")),
		int(lobby_config.get("port", WBLobbyContract.DEFAULT_WS_PORT)),
		int(lobby_config.get("udp_port", WBLobbyContract.DEFAULT_UDP_PORT)),
		_talent_cache
	)
	_lobby.set_content_hash(_content_hash)
	_lobby.set_client_version(str(ProjectSettings.get_setting("application/config/version", "dev")))


func _on_lobby_state_changed(state: String) -> void:
	if state == WBLobbyClient.STATE_ONLINE:
		_lobby_notice = ""
	if is_instance_valid(_lobby_status_label):
		_lobby_status_label.text = _lobby_status_text()


func _on_lobby_kicked(_reason: String) -> void:
	_lobby_notice = "SIGNED IN ON ANOTHER DEVICE — SAVE SETTINGS TO RECONNECT"
	_on_lobby_state_changed(_lobby.state())


func _on_lobby_notice(message: Dictionary) -> void:
	if str(message.get("kind", "")) == "protocol":
		_lobby_notice = "GAME UPDATE REQUIRED FOR THE LOBBY SERVER"
	else:
		_lobby_notice = str(message.get("message", "")).to_upper()
	_on_lobby_state_changed(_lobby.state())


func _lobby_status_text() -> String:
	var endpoint := WBSettingsStore.describe_lobby(_settings)
	if _lobby == null:
		return endpoint
	match _lobby.state():
		WBLobbyClient.STATE_ONLINE:
			if _lobby.is_registered():
				return "%s — ONLINE AS %s" % [endpoint, _lobby.nickname().to_upper()]
			return "%s — ONLINE, NO NICKNAME YET" % endpoint
		WBLobbyClient.STATE_CONNECTING:
			return "%s — CONNECTING..." % endpoint
	if not _lobby_notice.is_empty():
		return "%s — %s" % [endpoint, _lobby_notice]
	return "%s — OFFLINE (SOLO AND COUCH PLAY AVAILABLE)" % endpoint


func _present_splash_overlay() -> void:
	var splash_texture := _assets.texture("splashscreen")
	if splash_texture == null:
		return
	var splash := TextureRect.new()
	splash.name = "SplashScreen"
	splash.texture = splash_texture
	splash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	splash.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	splash.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	splash.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(splash)
	var dismiss := func() -> void:
		if is_instance_valid(splash):
			splash.queue_free()
		# Disarm the early-keypress hook from every dismiss path (click, timer,
		# or key) so no later menu input is swallowed.
		set_process_unhandled_input(false)
		_unhandled_splash_dismiss = Callable()
	splash.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
			dismiss.call()
	)
	var timer := Timer.new()
	timer.one_shot = true
	timer.wait_time = 3.0
	timer.timeout.connect(dismiss)
	add_child(timer)
	timer.start()
	# Accept any key press to dismiss the splash early.
	set_process_unhandled_input(true)
	_unhandled_splash_dismiss = func(event: InputEvent) -> void:
		if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
			dismiss.call()


var _unhandled_splash_dismiss: Callable


func _unhandled_input(event: InputEvent) -> void:
	if _attract_timer != null and not _attract_timer.is_stopped():
		_attract_timer.start()
	if _unhandled_splash_dismiss.is_valid():
		_unhandled_splash_dismiss.call(event)
		get_viewport().set_input_as_handled()


## Online features (hosting, joining, chat, spending talent points) need a
## registered nickname. The prompt appears on first use, never at boot.
func _require_nickname(then: Callable) -> void:
	var registered_or_offline := (
		_lobby == null or not _lobby.is_online() or _lobby.is_registered()
	)
	if _identity.has_nickname() and registered_or_offline:
		then.call()
		return
	_show_nickname_prompt(then)


func _show_nickname_prompt(then: Callable) -> void:
	_clear_page()
	_stop_attract_timer()
	var column := _screen_column(
		"CHOOSE A NICKNAME",
		"Your nickname is shown in the lobby list and global chat. 3-16 letters, digits, or underscores."
	)
	var name_input := LineEdit.new()
	name_input.name = "NicknameInput"
	name_input.placeholder_text = "NICKNAME"
	name_input.max_length = WBLobbyContract.NICKNAME_MAX_CHARS
	name_input.text = _identity.nickname()
	column.add_child(name_input)
	var status := Label.new()
	status.name = "NicknameStatus"
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.add_theme_color_override("font_color", Color("#ff7b6b"))
	column.add_child(status)
	var submit := func() -> void:
		var name := name_input.text.strip_edges().to_upper()
		if not WBLobbyContract.is_valid_nickname(name):
			status.text = "NICKNAME MUST BE 3-16 LETTERS, DIGITS, OR _"
			return
		if not _lobby.is_online():
			status.text = "LOBBY SERVER OFFLINE — CHECK SETTINGS"
			return
		status.text = "REGISTERING..."
		var outcome: Dictionary = (
			await _lobby.set_nickname(name)
			if _lobby.is_registered()
			else await _lobby.register_nickname(name)
		)
		if not bool(outcome.get("ok", false)):
			status.text = _lobby_error_text(outcome.get("error", {}))
			return
		_bind_pilot_profile()
		if then.is_valid():
			then.call()
		else:
			show_title()
	name_input.text_submitted.connect(func(_text: String) -> void: submit.call())
	column.add_child(_menu_button("CONFIRM", submit))
	column.add_child(_back_button(show_title))
	name_input.grab_focus()


func _lobby_error_text(error: Dictionary) -> String:
	match str(error.get("code", "")):
		WBLobbyContract.ERR_OFFLINE:
			return "LOBBY SERVER OFFLINE — CHECK SETTINGS"
		WBLobbyContract.ERR_UNREACHABLE, WBLobbyContract.ERR_TIMEOUT:
			return "LOBBY SERVER UNREACHABLE — CHECK SETTINGS AND TRY AGAIN"
		WBLobbyContract.ERR_RATE_LIMITED:
			return "TOO MANY ATTEMPTS — WAIT A MOMENT"
		WBLobbyContract.ERR_NICKNAME_TAKEN:
			return "NICKNAME TAKEN — CHOOSE ANOTHER"
		WBLobbyContract.ERR_INVALID_NICKNAME:
			return "NICKNAME MUST BE 3-16 LETTERS, DIGITS, OR _"
		WBLobbyContract.ERR_NOT_REGISTERED, WBLobbyContract.ERR_NOT_AUTHENTICATED:
			return "SET A NICKNAME FIRST"
		WBLobbyContract.ERR_INSUFFICIENT_POINTS:
			return "NOT ENOUGH TALENT POINTS"
		WBLobbyContract.ERR_RESPEC_COOLDOWN:
			return "RESPEC IS ON COOLDOWN — TRY AGAIN LATER"
		_:
			return str(error.get("message", "REQUEST FAILED")).to_upper()


## The pilot in seat 0: the profile bound to this identity once a nickname
## exists (created on demand, renamed when the nickname changes), otherwise
## the first local profile.
func _pilot_profile() -> Dictionary:
	if not _identity.has_nickname():
		return _profile_entries[0]
	return _bind_pilot_profile()


func _bind_pilot_profile() -> Dictionary:
	var profile_id := _identity.profile_id()
	var nickname := _identity.nickname()
	if profile_id.is_empty() or nickname.is_empty():
		return _profile_entries[0]
	var bound := _profiles.ensure_profile(profile_id, nickname)
	if bound.is_empty():
		return _profile_entries[0]
	if str(bound.get("name", "")) != nickname.to_upper().substr(0, 16):
		if _profiles.rename_profile(profile_id, nickname):
			bound = _profiles.ensure_profile(profile_id, nickname)
	_profile_entries = _profiles.profiles()
	if _selected_profiles.is_empty():
		_selected_profiles = [bound]
	else:
		_selected_profiles[0] = bound
	return bound


func _show_account() -> void:
	_clear_page()
	var nickname := _identity.nickname()
	var column := _screen_column(
		"ACCOUNT",
		"Your nickname and device key identify you on the lobby server. No password is needed."
	)
	var rows: Array = [
		["PILOT", nickname.to_upper() if not nickname.is_empty() else "NOT SET"],
		["DEVICE ID", _identity.profile_id().trim_prefix(WBIdentityStore.PROFILE_ID_PREFIX).to_upper()],
		["TALENT POINTS", str(_lobby.current_points())],
		["LOBBY SERVER", _lobby_status_text()],
	]
	for row_value in rows:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var key_label := Label.new()
		key_label.text = str(row_value[0])
		key_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(key_label)
		var value_label := Label.new()
		value_label.text = str(row_value[1])
		value_label.add_theme_font_size_override("font_size", 12)
		value_label.add_theme_color_override("font_color", Color("#ffd66b"))
		row.add_child(value_label)
		column.add_child(row)
	column.add_child(_menu_button(
		"CHANGE NICKNAME" if not nickname.is_empty() else "SET NICKNAME",
		func() -> void: _show_nickname_prompt(_show_account)
	))
	column.add_child(_menu_button("LOCAL PILOT DATA", _show_profiles))
	column.add_child(_back_button(show_title))
	_focus_first_button(column)


## The persistent talent tree: four branches, tiers top to bottom. Purchases
## are server-validated round trips — the screen rebuilds from the refreshed
## profile state and never grants optimistically.
func _show_talent_tree() -> void:
	_clear_page()
	var column := _center_column(Vector2(760.0, 560.0))
	var heading_row := HBoxContainer.new()
	var heading := Label.new()
	heading.text = "TALENTS"
	heading.add_theme_font_size_override("font_size", 24)
	heading.add_theme_color_override("font_color", Color("#ffd66b"))
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading_row.add_child(heading)
	var points_label := Label.new()
	points_label.name = "TalentPoints"
	points_label.text = "POINTS ★%d" % _lobby.current_points()
	points_label.add_theme_font_size_override("font_size", 18)
	points_label.add_theme_color_override("font_color", Color("#ffd66b"))
	heading_row.add_child(points_label)
	column.add_child(heading_row)
	var can_spend := _lobby.is_registered()
	if not can_spend:
		var banner := Label.new()
		banner.name = "TalentBanner"
		banner.text = (
			"SET A NICKNAME TO SPEND POINTS"
			if _lobby.is_online()
			else "OFFLINE — SHOWING CACHED TALENTS"
		)
		banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		banner.add_theme_font_size_override("font_size", 12)
		banner.add_theme_color_override("font_color", Color("#809bb4"))
		column.add_child(banner)
	if not _talent_catalog.is_loaded():
		var missing := Label.new()
		missing.text = "TALENT CATALOG UNAVAILABLE"
		column.add_child(missing)
		column.add_child(_back_button(show_title))
		return
	var owned := _lobby.owned_talents()
	var info := Label.new()
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.follow_focus = true
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var branches_row := HBoxContainer.new()
	branches_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	branches_row.add_theme_constant_override("separation", 12)
	scroll.add_child(branches_row)
	for branch_value in _talent_catalog.branches():
		var branch := branch_value as Dictionary
		var branch_column := VBoxContainer.new()
		branch_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		branch_column.add_theme_constant_override("separation", 6)
		var branch_label := Label.new()
		branch_label.text = str(branch.get("name", ""))
		branch_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		branch_label.add_theme_font_size_override("font_size", 15)
		branch_label.add_theme_color_override("font_color", Color("#809bb4"))
		branch_column.add_child(branch_label)
		for node_value in (branch.get("nodes", []) as Array):
			var node := node_value as Dictionary
			var node_id := str(node.get("id", ""))
			var button := Button.new()
			button.name = "Talent_" + node_id
			button.custom_minimum_size = Vector2(0.0, 40.0)
			button.add_theme_font_size_override("font_size", 12)
			var is_owned := int(owned.get(node_id, 0)) > 0
			var purchasable := (
				can_spend
				and bool(_talent_catalog.validate_spend(owned, node_id).get("ok", false))
			)
			if is_owned:
				button.text = "★ " + str(node.get("name", node_id))
				button.disabled = true
				button.add_theme_color_override("font_disabled_color", Color("#ffd66b"))
			elif purchasable:
				button.text = str(node.get("name", node_id))
			else:
				button.text = str(node.get("name", node_id))
				button.disabled = true
			button.focus_entered.connect(func() -> void:
				info.text = _talent_info_text(node, is_owned, purchasable)
			)
			button.mouse_entered.connect(func() -> void:
				info.text = _talent_info_text(node, is_owned, purchasable)
			)
			if purchasable:
				button.pressed.connect(func() -> void:
					button.disabled = true
					button.text = "..."
					var outcome: Dictionary = await _lobby.spend_talent(node_id)
					if not bool(outcome.get("ok", false)):
						info.text = _lobby_error_text(outcome.get("error", {}))
					_show_talent_tree()
				)
			branch_column.add_child(button)
		branches_row.add_child(branch_column)
	info.name = "TalentInfo"
	info.text = "Select a talent."
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.custom_minimum_size = Vector2(0.0, 64.0)
	info.add_theme_font_size_override("font_size", 13)
	column.add_child(info)
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	var respec := Button.new()
	respec.text = "RESPEC (FULL REFUND)"
	respec.custom_minimum_size = Vector2(0.0, 44.0)
	respec.disabled = not can_spend
	respec.pressed.connect(func() -> void:
		if respec.text != "SURE?":
			respec.text = "SURE?"
			return
		respec.disabled = true
		var outcome: Dictionary = await _lobby.respec()
		if not bool(outcome.get("ok", false)):
			info.text = _lobby_error_text(outcome.get("error", {}))
		_show_talent_tree()
	)
	respec.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(respec)
	var back := _back_button(show_title)
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	actions.add_child(back)
	column.add_child(actions)
	_focus_first_enabled_talent(branches_row, back)


func _talent_info_text(node: Dictionary, is_owned: bool, purchasable: bool) -> String:
	var pieces: Array[String] = [
		"%s — %d POINTS" % [str(node.get("name", "")), int(node.get("cost", 0))],
		str(node.get("text", "")),
	]
	var requires: Array = node.get("requires", []) as Array
	if not requires.is_empty():
		var names: Array[String] = []
		for requirement_value in requires:
			var requirement := _talent_catalog.node(str(requirement_value))
			names.append(str(requirement.get("name", str(requirement_value))))
		pieces.append("REQUIRES: " + ", ".join(names))
	if is_owned:
		pieces.append("LEARNED")
	elif purchasable:
		pieces.append("PRESS TO LEARN")
	return "\n".join(pieces)


func _focus_first_enabled_talent(branches_row: Node, fallback: Button) -> void:
	for branch_column in branches_row.get_children():
		for child in branch_column.get_children():
			if child is Button and not (child as Button).disabled:
				(child as Button).grab_focus.call_deferred()
				return
	fallback.grab_focus.call_deferred()


func show_title() -> void:
	_clear_page()
	_start_attract_timer()
	# The newscreen.png backdrop (in _create_backdrop) provides the original
	# dark menu panel; the logo is the separate original newlogo3 art drawn
	# above the menu column, as on the retail title screen.
	var logo_texture := _assets.texture("newlogo3")
	if logo_texture != null:
		var logo := TextureRect.new()
		logo.name = "TitleLogo"
		logo.texture = logo_texture
		logo.set_anchors_preset(Control.PRESET_CENTER)
		logo.position = Vector2(-325.0, -230.0)
		logo.size = Vector2(693.0, 110.0)
		logo.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		logo.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_page.add_child(logo)
	# Retail activates a menu line at the bottom of the title screen
	# (manual: "move the mouse to activate the menu line at the bottom of the
	# screen"); the bar below keeps the retail item set and order.
	var bar := HBoxContainer.new()
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	bar.position = Vector2(-396.0, -46.0)
	bar.size = Vector2(792.0, 42.0)
	bar.add_theme_constant_override("separation", 2)
	_page.add_child(bar)
	var start_button := Button.new()
	start_button.text = "START"
	start_button.custom_minimum_size = Vector2(0.0, 36.0)
	var start_menu := PopupMenu.new()
	start_menu.add_item("START 1 PLAYER GAME", 1)
	start_menu.add_item("START 2 PLAYER CO-OP (REMAKE)", 4)
	start_menu.add_item("HOST 2 PLAYER CO-OP (ONLINE)", 9)
	start_menu.add_item("JOIN ONLINE GAME", 10)
	start_menu.add_item("START TIME TRIAL", 6)
	start_menu.add_item("DEMO GAME", 7)
	start_menu.add_item("LOAD SAVED GAME", 8)
	start_menu.id_pressed.connect(_on_start_menu_id)
	bar.add_child(start_menu)
	start_button.pressed.connect(func() -> void:
		# Embedded subwindows (the default) are positioned in the main viewport's
		# canvas coordinates, so the button's global rect is the right space.
		start_menu.reset_size()
		var button_rect := Rect2i(start_button.get_global_rect())
		start_menu.position = button_rect.position + Vector2i(0, -start_menu.size.y)
		start_menu.popup()
	)
	bar.add_child(start_button)
	bar.add_child(_bar_button("ABOUT", _show_about))
	bar.add_child(_bar_button("STORY", _show_story))
	bar.add_child(_bar_button("SETTINGS", _show_settings))
	bar.add_child(_bar_button("BONUSES", _show_bonuses))
	bar.add_child(_bar_button("HISCORE", _show_hiscore))
	bar.add_child(_bar_button("CHAT", _show_global_chat))
	bar.add_child(_bar_button("TALENTS ★%d" % _lobby.current_points(), _show_talent_tree))
	bar.add_child(_bar_button("ACCOUNT", _show_account))
	bar.add_child(_bar_button("USER MANUAL", _show_user_manual))
	bar.add_child(_bar_button("QUIT", _quit))
	# The footer names the lobby server and the player's online status, so an
	# offline session is never mistaken for a connected one.
	_lobby_status_label = Label.new()
	_lobby_status_label.name = "LobbyStatus"
	_lobby_status_label.text = _lobby_status_text()
	_lobby_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lobby_status_label.add_theme_font_size_override("font_size", 12)
	_lobby_status_label.add_theme_color_override("font_color", Color("#809bb4"))
	_lobby_status_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_lobby_status_label.position = Vector2(-300.0, -66.0)
	_lobby_status_label.size = Vector2(600.0, 18.0)
	_lobby_status_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_page.add_child(_lobby_status_label)
	_focus_first_button(bar)


func _show_global_chat() -> void:
	_require_nickname(_show_global_chat_screen)


## One global room on the lobby server: stored history first, then live
## lines for as long as the screen is open.
func _show_global_chat_screen() -> void:
	_clear_page()
	_stop_attract_timer()
	var column := _center_column(Vector2(720.0, 560.0))
	var heading_row := HBoxContainer.new()
	var heading := Label.new()
	heading.text = "GLOBAL CHAT"
	heading.add_theme_font_size_override("font_size", 24)
	heading.add_theme_color_override("font_color", Color("#ffd66b"))
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading_row.add_child(heading)
	var status := Label.new()
	status.name = "GlobalChatStatus"
	status.text = _lobby_status_text()
	status.add_theme_font_size_override("font_size", 12)
	status.add_theme_color_override("font_color", Color("#809bb4"))
	heading_row.add_child(status)
	column.add_child(heading_row)
	var panel := WBChatPanel.new()
	panel.name = "GlobalChatPanel"
	column.add_child(panel)
	panel.message_submitted.connect(func(text: String) -> void:
		var outcome: Dictionary = await _lobby.send_chat(text)
		if is_instance_valid(panel):
			panel.set_status(
				"" if bool(outcome.get("ok", false)) else _lobby_error_text(outcome.get("error", {}))
			)
	)
	panel.closed.connect(show_title)
	var on_message := func(message: Dictionary) -> void:
		if is_instance_valid(panel):
			panel.append_line(str(message.get("nickname", "?")), str(message.get("body", "")))
	var on_state := func(_state: String) -> void:
		if is_instance_valid(status):
			status.text = _lobby_status_text()
	_lobby.chat_message.connect(on_message)
	_lobby.state_changed.connect(on_state)
	panel.tree_exited.connect(func() -> void:
		if _lobby.chat_message.is_connected(on_message):
			_lobby.chat_message.disconnect(on_message)
		if _lobby.state_changed.is_connected(on_state):
			_lobby.state_changed.disconnect(on_state)
	)
	column.add_child(_back_button(show_title))
	if _lobby.is_online():
		var history: Dictionary = await _lobby.chat_history()
		if is_instance_valid(panel) and bool(history.get("ok", false)):
			panel.set_lines(history.get("messages", []) as Array)
	elif is_instance_valid(panel):
		panel.set_status("LOBBY SERVER OFFLINE — CHAT IS UNAVAILABLE")
	if is_instance_valid(panel):
		panel.focus_input()


func _bar_button(text: String, callback: Callable) -> Button:
	var button := _menu_button(text, callback)
	button.custom_minimum_size = Vector2(0.0, 36.0)
	button.add_theme_font_size_override("font_size", 13)
	return button


func _on_start_menu_id(id: int) -> void:
	# Seat 0 is always the identity pilot, so only co-op needs a pilot screen
	# (for the second seat); solo goes straight to difficulty and Time Trial
	# starts immediately, as retail does.
	match id:
		1:
			_mode = "solo"
			_selected_profiles = [_pilot_profile()]
			_show_difficulty_select()
		4:
			_mode = "coop"
			_show_match_profiles()
		6:
			_mode = "time_trial"
			_selected_profiles = [_pilot_profile()]
			_start_match()
		7:
			_start_demo()
		8:
			_show_saved_games()
		9:
			_require_nickname(_start_host_setup)
		10:
			_require_nickname(_show_lobby_browser)


## Retail idle attract: after a quiet spell on the title screen the game
## starts playing itself; any input during the demo returns to the title.
func _start_attract_timer() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if _attract_timer == null:
		_attract_timer = Timer.new()
		_attract_timer.one_shot = true
		_attract_timer.wait_time = 45.0
		_attract_timer.timeout.connect(func() -> void:
			if _gameplay == null and not _demo_active:
				_start_demo()
		)
		add_child(_attract_timer)
	_attract_timer.start()


func _stop_attract_timer() -> void:
	if _attract_timer != null:
		_attract_timer.stop()


## Retail DEMO GAME: the computer plays an early random level; any human
## input returns to the title, and nothing is recorded.
func _start_demo() -> void:
	_mode = "solo"
	_demo_active = true
	var config := WBMatchConfig.make(
		"solo",
		"normal",
		"classic",
		[],
		str(_settings.get("collision_mode", "pixel"))
	)
	config["demo"] = true
	config["start_level"] = 1 + (randi() % 10)
	config["effects_mode"] = str(_settings.get("effects_mode", "enhanced"))
	config["texture_filter"] = str(_settings.get("texture_filter", "smooth"))
	_clear_page()
	_gameplay = WBGameplayScreen.new()
	_active_result_persisted = false
	_gameplay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_gameplay.exit_requested.connect(_on_gameplay_exit)
	_gameplay.sound_requested.connect(_on_gameplay_sound)
	_gameplay.audio_requested.connect(_on_gameplay_audio_requested)
	_page.add_child(_gameplay)
	_audio.play_music("warblade")
	if not _gameplay.begin(config):
		_demo_active = false
		_gameplay = null
		_audio.play_music("title")
		show_title()
		return
	var banner := Label.new()
	banner.text = "D E M O   —   PRESS ANY KEY"
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.add_theme_font_size_override("font_size", 16)
	banner.add_theme_color_override("font_color", Color("#ffd66b"))
	banner.set_anchors_preset(Control.PRESET_CENTER_TOP)
	banner.position = Vector2(-260, 12)
	banner.size = Vector2(520, 28)
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_gameplay.add_child(banner)


func _show_about() -> void:
	_clear_page()
	var column := _screen_column("ABOUT", "Warblade by EMV Software — the original team.")
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	column.add_child(row)
	for portrait in ["edgar", "hitman", "wayne", "wade", "bell", "olsen"]:
		var texture := _assets.texture(portrait)
		if texture == null:
			continue
		var image := TextureRect.new()
		image.texture = texture
		image.custom_minimum_size = Vector2(72.0, 72.0)
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(image)
	var credits := Label.new()
	credits.text = str(_assets.section("ending").get("credits_text", "")).strip_edges()
	credits.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	credits.add_theme_font_size_override("font_size", 12)
	column.add_child(credits)
	column.add_child(_back_button(show_title))
	_focus_first_button(column)


func _show_story() -> void:
	_clear_page()
	var column := _screen_column("STORY", "The original mission briefing.")
	var story := Label.new()
	story.text = str(_assets.section("ending").get("story_text", "")).strip_edges()
	story.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	story.add_theme_font_size_override("font_size", 14)
	story.add_theme_color_override("font_color", Color("#c8d8eb"))
	column.add_child(story)
	column.add_child(_back_button(show_title))
	_focus_first_button(column)


func _show_bonuses() -> void:
	_clear_page()
	var column := _screen_column(
		"BONUSES AND WEAPONS",
		"The original bonus, weapon, and rank systems."
	)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	scroll.add_child(body)
	var bonuses_sheet := _assets.texture("bonuses")
	if bonuses_sheet != null:
		var sheet := TextureRect.new()
		sheet.texture = bonuses_sheet
		sheet.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		sheet.custom_minimum_size = Vector2(0, 96)
		body.add_child(sheet)
	var sections := [
		["WEAPONS", "Single, Double, Triple, Quad, Super Triple, Plasma, Fireballs, Laser, and War.I.Plasma. Catching the weapon you already carry adds a bullet instead."],
		["ALIEN SCOOP", "A tractor field that captures two alien wingmen to fight beside you."],
		["SMART BOMBS", "Gem and money bombs convert the wave into collectables."],
		["MULTIPLY SCORE", "Timed x2 and x5 multipliers apply to every award while they run."],
		["METEOR STORM", "Steer through the rocks; full throttle earns the big bonus."],
		["RANDOM BONUS", "The mystery drop resolves into another bonus when caught."],
		["DECREASE STRENGTH", "Weakens your rank progress — some drops hurt."],
		["EXTRA BONUS TIME", "Extends the T bar; the shop's Extra Time can overshoot the cap."],
		["THE LETTERS", "E X T R A grants fighters; strict order or strict reverse order fills fighters and armour, or scores millions when full."],
	]
	for section in sections:
		var heading := Label.new()
		heading.text = str(section[0])
		heading.add_theme_font_size_override("font_size", 15)
		heading.add_theme_color_override("font_color", Color("#ffd66b"))
		body.add_child(heading)
		var text := Label.new()
		text.text = str(section[1])
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.add_theme_font_size_override("font_size", 12)
		text.add_theme_color_override("font_color", Color("#c8d8eb"))
		body.add_child(text)
	var rank_heading := Label.new()
	rank_heading.text = "NEW RANK"
	rank_heading.add_theme_font_size_override("font_size", 15)
	rank_heading.add_theme_color_override("font_color", Color("#ffd66b"))
	body.add_child(rank_heading)
	var rank_text := Label.new()
	rank_text.text = "Big aliens drop rank marks in six colours; collect all six and visit the shop to be promoted. There may be more bonuses and ranks out there..."
	rank_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rank_text.add_theme_font_size_override("font_size", 12)
	rank_text.add_theme_color_override("font_color", Color("#c8d8eb"))
	body.add_child(rank_text)
	var rank_row := HBoxContainer.new()
	rank_row.alignment = BoxContainer.ALIGNMENT_CENTER
	rank_row.add_theme_constant_override("separation", 10)
	body.add_child(rank_row)
	for art_key in ["marks", "medaljer", "star_1", "star_2", "star_3", "planeter"]:
		var art := _assets.texture(art_key)
		if art == null:
			continue
		var icon := TextureRect.new()
		icon.texture = art
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.custom_minimum_size = Vector2(48, 48)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rank_row.add_child(icon)
	var gallery := _menu_button("SECRET GALLERY", _show_secret_gallery)
	column.add_child(gallery)
	column.add_child(_back_button(show_title))
	_focus_first_button(column)


func _show_secret_gallery() -> void:
	_clear_page()
	var profile: Dictionary = (
		_selected_profiles[0] if not _selected_profiles.is_empty() else {}
	)
	for entry in _profile_entries:
		if str(entry.get("id", "")) == str(profile.get("id", "")):
			profile = entry
			break
	var seen_mask := int(profile.get("secrets_seen", 0))
	var found := 0
	for secret_id in range(30):
		if (seen_mask & (1 << secret_id)) != 0:
			found += 1
	var column := _screen_column(
		"GAME SECRETS",
		"%s has uncovered %d of 30 shop secrets." % [
			str(profile.get("name", "PILOT")),
			found,
		]
	)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	scroll.add_child(grid)
	for secret_id in range(30):
		var unlocked := (seen_mask & (1 << secret_id)) != 0
		if unlocked:
			var panel := TextureRect.new()
			panel.texture = _assets.texture("secret_%02d" % (secret_id + 1))
			panel.custom_minimum_size = Vector2(168.0, 82.0)
			panel.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			panel.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			grid.add_child(panel)
		else:
			var locked := Label.new()
			locked.text = "SECRET %02d\nLOCKED" % (secret_id + 1)
			locked.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			locked.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			locked.custom_minimum_size = Vector2(168.0, 82.0)
			locked.add_theme_font_size_override("font_size", 11)
			locked.add_theme_color_override("font_color", Color("#5a6a7d"))
			grid.add_child(locked)
	column.add_child(_back_button(_show_bonuses))
	_focus_first_button(column)


func _show_hiscore(table_kind: String = "normal") -> void:
	_clear_page()
	_audio.play_music("hiscore")
	var column := _center_column(Vector2(640.0, 560.0))
	var heading := Label.new()
	heading.text = "HALL OF FAME"
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 24)
	heading.add_theme_color_override("font_color", Color("#ffd66b"))
	column.add_child(heading)
	var tabs := HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 6)
	column.add_child(tabs)
	var tab_labels := {
		"easy": "EASY", "normal": "NORMAL", "hard": "HARD", "ace": "ACE",
		"meteorstorm": "METEOR", "timetrial": "TIME TRIAL",
	}
	for kind in WBHiscoreStore.TABLE_KINDS:
		var tab := Button.new()
		tab.text = str(tab_labels.get(kind, kind.to_upper()))
		tab.disabled = kind == table_kind
		tab.pressed.connect(_show_hiscore.bind(kind))
		tabs.add_child(tab)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)
	var entries := _hiscores.table(table_kind)
	if entries.is_empty():
		var empty := Label.new()
		empty.text = "NO SCORES RECORDED YET"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty.add_theme_color_override("font_color", Color("#809bb4"))
		list.add_child(empty)
	var placement := 0
	for entry_value in entries:
		var entry := entry_value as Dictionary
		placement += 1
		var line := Label.new()
		line.text = "%2d  %-16s %11d  L%d" % [
			placement,
			str(entry.get("name", "PILOT")),
			int(entry.get("score", 0)),
			int(entry.get("level", 1)),
		]
		line.add_theme_font_size_override("font_size", 15)
		line.add_theme_color_override(
			"font_color",
			Color("#ffe8a0") if placement == 1 else Color("#c8d8eb")
		)
		line.tooltip_text = _hiscore_entry_details(entry)
		list.add_child(line)
		var details := Label.new()
		details.text = "      %s" % _hiscore_entry_details(entry)
		details.add_theme_font_size_override("font_size", 11)
		details.add_theme_color_override("font_color", Color("#7d92a8"))
		list.add_child(details)
	column.add_child(_back_button(func() -> void:
		_audio.play_music("title")
		show_title()
	))
	_focus_first_button(column)


func _hiscore_entry_details(entry: Dictionary) -> String:
	var rank_index := clampi(
		int(entry.get("rank_index", 0)),
		0,
		GameSimulation.RANK_NAMES.size() - 1
	)
	var seconds := int(entry.get("duration_ticks", 0)) / 60
	var recorded := ""
	if int(entry.get("at", 0)) > 0:
		recorded = " — " + Time.get_date_string_from_unix_time(int(entry.get("at", 0)))
	return "%s — %d:%02d:%02d — %d SHOTS, %d HITS (%d%%)%s" % [
		String(GameSimulation.RANK_NAMES[rank_index]),
		seconds / 3600,
		(seconds / 60) % 60,
		seconds % 60,
		int(entry.get("shots", 0)),
		int(entry.get("hits", 0)),
		int(entry.get("hit_percent", 0)),
		recorded,
	]


func _show_user_manual() -> void:
	_clear_page()
	var column := _screen_column("USER MANUAL", "The complete retail manual (v1.34).")
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(scroll)
	var text := Label.new()
	text.text = _load_manual_text()
	text.autowrap_mode = TextServer.AUTOWRAP_OFF
	text.add_theme_font_size_override("font_size", 11)
	text.add_theme_color_override("font_color", Color("#c8d8eb"))
	scroll.add_child(text)
	column.add_child(_back_button(show_title))
	_focus_first_button(column)


static func _load_manual_text() -> String:
	var manual_path := "res://assets/original/manual/Warblade_Manual_V1.34_Eng.txt"
	if not FileAccess.file_exists(manual_path):
		return "The extracted manual file is missing."
	var file := FileAccess.open(manual_path, FileAccess.READ)
	if file == null:
		return "The extracted manual file cannot be read."
	var buffer := file.get_buffer(file.get_length())
	file.close()
	# The retail manual is ISO-8859-1 with CRLF line endings;
	# get_string_from_ascii performs the byte-to-codepoint Latin-1 decode.
	return buffer.get_string_from_ascii().replace("\r", "")


func _exit_tree() -> void:
	_audio.stop_music()
	_assets.clear()
	theme = null


func _show_match_profiles() -> void:
	_clear_page()
	var column := _screen_column(
		"SELECT SECOND PILOT",
		"Player 1 is your pilot. The second seat rides along as a guest or a local pilot."
	)
	var pilot := _pilot_profile()
	var p1_row := HBoxContainer.new()
	p1_row.add_theme_constant_override("separation", 8)
	var p1_label := Label.new()
	p1_label.text = "PLAYER 1"
	p1_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p1_row.add_child(p1_label)
	var p1_name := Label.new()
	p1_name.text = str(pilot.get("name", "PILOT"))
	p1_name.add_theme_color_override("font_color", Color("#ffd66b"))
	p1_row.add_child(p1_name)
	column.add_child(p1_row)
	var p2_row := _option_row("PLAYER 2")
	var p2_option := p2_row[1] as OptionButton
	p2_option.add_item("GUEST")
	for profile in _profile_entries:
		p2_option.add_item(str(profile.get("name", "PILOT")))
	column.add_child(p2_row[0])
	var continue_button := _menu_button("CONTINUE", func() -> void:
		_selected_profiles = [pilot]
		if p2_option.selected == 0:
			_selected_profiles.append({"id": "guest", "name": "GUEST"})
		else:
			_selected_profiles.append(_profile_entries[p2_option.selected - 1])
		_show_difficulty_select()
	)
	column.add_child(continue_button)
	column.add_child(_back_button(show_title))
	_focus_first_button(column)


func _show_difficulty_select() -> void:
	_clear_page()
	var column := _screen_column("SELECT DIFFICULTY", "Difficulty is fixed for the entire run.")
	var difficulties: Array[Dictionary] = [
		{"id": "easy", "name": "EASY", "description": "A gentler route through the original waves."},
		{"id": "normal", "name": "NORMAL", "description": "The standard Warblade balance."},
		{"id": "hard", "name": "HARD", "description": "Faster and less forgiving."},
		{"id": "ace", "name": "ACE", "description": "The highest original challenge."},
	]
	for entry in difficulties:
		var difficulty_id := str(entry["id"])
		var button := _menu_button("%s\n%s" % [entry["name"], entry["description"]], func() -> void:
			_difficulty = difficulty_id
			if _mode == "coop":
				_show_coop_balance()
			else:
				_start_match()
		)
		button.custom_minimum_size.y = 64.0
		column.add_child(button)
	column.add_child(_back_button(
		_show_match_profiles if _mode == "coop" and _party.is_empty() else Callable(self, "show_title")
	))
	_focus_first_button(column)


func _show_coop_balance() -> void:
	_clear_page()
	var column := _screen_column("CO-OP BALANCE", "Both presets keep the original waves, attacks, drops, and rewards.")
	var classic := _menu_button("CLASSIC\nOriginal enemy health and behavior.", func() -> void:
		_coop_balance = "classic"
		_start_match()
	)
	classic.custom_minimum_size.y = 72.0
	column.add_child(classic)
	var balanced := _menu_button("BALANCED\nTwo-player enemies use exactly 2× health.", func() -> void:
		_coop_balance = "balanced"
		_start_match()
	)
	balanced.custom_minimum_size.y = 72.0
	column.add_child(balanced)
	column.add_child(_back_button(_show_difficulty_select))
	_focus_first_button(column)


func _show_profiles() -> void:
	_clear_page()
	var column := _screen_column(
		"LOCAL PROFILES",
		"Up to ten local pilots. Statistics feed the profile locks."
	)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 8)
	scroll.add_child(list)
	for profile in _profile_entries:
		var profile_id := str(profile.get("id", ""))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var name := Label.new()
		name.text = str(profile.get("name", "PILOT"))
		name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name)
		var score := Label.new()
		score.text = "BEST %d" % int(profile.get("best_score", 0))
		score.add_theme_font_size_override("font_size", 12)
		score.add_theme_color_override("font_color", Color("#809bb4"))
		row.add_child(score)
		var stats := Button.new()
		stats.text = "STATS"
		stats.pressed.connect(_show_statistics.bind(profile_id))
		row.add_child(stats)
		var rename := Button.new()
		rename.text = "RENAME"
		rename.pressed.connect(_show_profile_rename.bind(profile_id))
		row.add_child(rename)
		var reset := Button.new()
		reset.text = "RESET"
		reset.pressed.connect(func() -> void:
			if reset.text == "RESET":
				reset.text = "SURE?"
				return
			_profiles.reset_profile_statistics(profile_id)
			_profile_entries = _profiles.profiles()
			_show_profiles()
		)
		row.add_child(reset)
		var remove := Button.new()
		remove.text = "DELETE"
		remove.disabled = _profile_entries.size() <= 1
		remove.pressed.connect(func() -> void:
			if remove.text == "DELETE":
				remove.text = "SURE?"
				return
			_profiles.remove_profile(profile_id)
			_profile_entries = _profiles.profiles()
			for selected_index in range(_selected_profiles.size()):
				if str(_selected_profiles[selected_index].get("id", "")) == profile_id:
					_selected_profiles[selected_index] = _profile_entries[0]
			_show_profiles()
		)
		row.add_child(remove)
		list.add_child(row)
	if _profile_entries.size() < WBProfileStore.MAX_PROFILES:
		var creation := HBoxContainer.new()
		creation.add_theme_constant_override("separation", 10)
		var name_input := LineEdit.new()
		name_input.placeholder_text = "NEW PILOT NAME"
		name_input.max_length = 16
		name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		creation.add_child(name_input)
		var create := _menu_button("CREATE", func() -> void:
			var profile := _profiles.add_profile(name_input.text)
			if not profile.is_empty():
				_profile_entries = _profiles.profiles()
				_show_profiles()
		)
		create.custom_minimum_size.x = 150.0
		creation.add_child(create)
		column.add_child(creation)
	column.add_child(_back_button(show_title))
	_focus_first_button(column)


func _show_profile_rename(profile_id: String) -> void:
	_clear_page()
	var column := _screen_column("RENAME PILOT", "Local hall-of-fame entries keep their recorded names.")
	var name_input := LineEdit.new()
	name_input.max_length = 16
	for profile in _profile_entries:
		if str(profile.get("id", "")) == profile_id:
			name_input.text = str(profile.get("name", ""))
	column.add_child(name_input)
	column.add_child(_menu_button("SAVE NAME", func() -> void:
		if _profiles.rename_profile(profile_id, name_input.text):
			_profile_entries = _profiles.profiles()
		_show_profiles()
	))
	column.add_child(_back_button(_show_profiles))
	_focus_first_button(column)


func _show_statistics(profile_id: String) -> void:
	_clear_page()
	var profile: Dictionary = {}
	for entry in _profile_entries:
		if str(entry.get("id", "")) == profile_id:
			profile = entry
			break
	var column := _screen_column(
		"STATISTICS",
		str(profile.get("name", "PILOT"))
	)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	scroll.add_child(list)
	var total_shots := int(profile.get("total_shots", 0))
	var total_hits := int(profile.get("total_hits", 0))
	var total_percent := (
		clampi(total_hits * 100 / total_shots, 0, 100) if total_shots > 0 else 0
	)
	var game_seconds := int(profile.get("total_game_time_ticks", 0)) / 60
	var rank_index := clampi(
		int(profile.get("highest_rank", 0)),
		0,
		GameSimulation.RANK_NAMES.size() - 1
	)
	var fastest_clear := int(profile.get("fastest_level_clear_ticks", 0))
	var bonus_rounds := int(profile.get("bonus_rounds_total", 0))
	var perfect_rounds := int(profile.get("perfect_bonus_rounds", 0))
	var rows := [
		["HIGHEST RANK REACHED", String(GameSimulation.RANK_NAMES[rank_index])],
		["HIGHEST AMOUNT OF MONEY", str(int(profile.get("highest_money", 0)))],
		["TOTAL HIT PERCENTAGE", "%d%%" % total_percent],
		["HIGHEST HIT %% ABOVE LEVEL 25", "%d%%" % int(profile.get("best_hit_percent_above_level_25", 0))],
		["TOTAL GAMES PLAYED", str(int(profile.get("games_played", 0)))],
		["TOTAL LEVELS PLAYED", str(int(profile.get("levels_played_total", 0)))],
		["HIGHEST LEVEL REACHED", str(int(profile.get("highest_level", 0)))],
		["SECRETS FOUND", "%d / 30" % _count_secret_bits(int(profile.get("secrets_seen", 0)))],
		["SECRETS FOUND IN ONE GAME", str(int(profile.get("secrets_one_game_best", 0)))],
		["FASTEST METEORSTORM", "—"],
		[
			"FASTEST CLEARING OF LEVEL",
			"%d.%02d SEC" % [fastest_clear / 60, (fastest_clear % 60) * 100 / 60]
			if fastest_clear > 0 else "—",
		],
		[
			"TOTAL GAME TIME",
			"%d HOURS, %d MINUTES, %d SECONDS" % [
				game_seconds / 3600,
				(game_seconds / 60) % 60,
				game_seconds % 60,
			],
		],
		[
			"PERFECT BONUS LEVELS",
			"%d OF %d" % [perfect_rounds, bonus_rounds],
		],
		["HIGHEST POINTS IN THE GAME", str(int(profile.get("best_score", 0)))],
		["HIGHEST POINTS IN METEORSTORM", str(int(profile.get("best_meteor_score", 0)))],
		["HIGHEST POINTS IN TIME TRIAL", str(int(profile.get("best_time_trial_score", 0)))],
		["HIGHEST POINTS AT LEVEL 100", str(int(profile.get("best_level_100_score", 0)))],
	]
	for row_data in rows:
		var row := HBoxContainer.new()
		var label := Label.new()
		label.text = str(row_data[0])
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_font_size_override("font_size", 13)
		row.add_child(label)
		var value := Label.new()
		value.text = str(row_data[1])
		value.add_theme_font_size_override("font_size", 13)
		value.add_theme_color_override("font_color", Color("#ffe8a0"))
		row.add_child(value)
		list.add_child(row)
	column.add_child(_back_button(_show_profiles))
	_focus_first_button(column)


static func _count_secret_bits(mask: int) -> int:
	var count := 0
	for secret_id in range(30):
		if (mask & (1 << secret_id)) != 0:
			count += 1
	return count


func _show_settings() -> void:
	_clear_page()
	var frame := _screen_column("SETTINGS", "Rendering can exceed 60 Hz; gameplay remains fixed and deterministic.")
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	frame.add_child(scroll)
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 10)
	scroll.add_child(column)

	var display_row := _option_row("DISPLAY")
	var display := display_row[1] as OptionButton
	for label in ["WINDOWED", "BORDERLESS", "FULLSCREEN"]:
		display.add_item(label)
	display.select(["windowed", "borderless", "fullscreen"].find(str(_settings.get("display_mode", "windowed"))))
	column.add_child(display_row[0])

	var resolution_row := _option_row("WINDOW SIZE")
	var resolution := resolution_row[1] as OptionButton
	var resolutions := [
		Vector2i(1280, 720),
		Vector2i(1280, 960),
		Vector2i(1600, 900),
		Vector2i(1920, 1080),
		Vector2i(1920, 1440),
		Vector2i(2560, 1440),
		Vector2i(2560, 1920),
		Vector2i(3840, 2160),
		Vector2i(5120, 2880),
		Vector2i(6016, 3384),
		Vector2i(7680, 4320),
	]
	for value in resolutions:
		resolution.add_item("%d × %d" % [value.x, value.y])
	var current_size := Vector2i(int(_settings.get("window_width", 1280)), int(_settings.get("window_height", 960)))
	var resolution_index := resolutions.find(current_size)
	resolution.select(0 if resolution_index < 0 else resolution_index)
	column.add_child(resolution_row[0])

	var cap_row := _option_row("RENDER RATE")
	var cap := cap_row[1] as OptionButton
	var render_caps := [0, 60, 120, 144, 165, 240, 360, 480]
	for value in render_caps:
		cap.add_item("UNLIMITED" if value == 0 else "%d FPS" % value)
	cap.select(maxi(0, render_caps.find(int(_settings.get("render_cap", 0)))))
	column.add_child(cap_row[0])

	var collision_row := _option_row("COLLISION")
	var collision := collision_row[1] as OptionButton
	collision.add_item("PIXEL MASK")
	collision.add_item("SIMPLE")
	collision.select(0 if str(_settings.get("collision_mode", "pixel")) == "pixel" else 1)
	column.add_child(collision_row[0])

	var effects_row := _option_row("EFFECTS")
	var effects := effects_row[1] as OptionButton
	effects.add_item("ENHANCED ORIGINAL ART")
	effects.add_item("RECOVERED CORE ONLY")
	effects.select(1 if str(_settings.get("effects_mode", "enhanced")) == "original" else 0)
	column.add_child(effects_row[0])

	var filter_row := _option_row("TEXTURE SCALING")
	var filter := filter_row[1] as OptionButton
	filter.add_item("SMOOTH")
	filter.add_item("SHARP PIXELS")
	filter.select(1 if str(_settings.get("texture_filter", "smooth")) == "sharp" else 0)
	column.add_child(filter_row[0])

	var sprite_pack_row := _option_row("SPRITE PACK")
	var sprite_pack := sprite_pack_row[1] as OptionButton
	var sprite_pack_names := WBAssetLibrary.available_packs()
	sprite_pack.add_item("RETAIL ORIGINAL")
	for sprite_pack_name in sprite_pack_names:
		sprite_pack.add_item(sprite_pack_name.to_upper())
	# find() returns -1 for retail/unknown, so +1 lands on RETAIL ORIGINAL.
	sprite_pack.select(sprite_pack_names.find(str(_settings.get("sprite_pack", ""))) + 1)
	column.add_child(sprite_pack_row[0])
	if not sprite_pack_names.is_empty():
		var sprite_pack_note := Label.new()
		sprite_pack_note.text = "Sprite packs apply at the next launch."
		sprite_pack_note.add_theme_font_size_override("font_size", 12)
		sprite_pack_note.add_theme_color_override("font_color", Color("#809bb4"))
		column.add_child(sprite_pack_note)

	var vsync := CheckButton.new()
	vsync.text = "VSync / display refresh"
	vsync.button_pressed = bool(_settings.get("vsync", true))
	column.add_child(vsync)

	var master_row := _slider_row("MASTER VOLUME", float(_settings.get("master_volume", 0.8)))
	column.add_child(master_row[0])
	var music_row := _slider_row("MUSIC", float(_settings.get("music_volume", 0.75)))
	column.add_child(music_row[0])
	var sfx_row := _slider_row("SFX", float(_settings.get("sfx_volume", 0.9)))
	column.add_child(sfx_row[0])
	var voice_row := _slider_row("VOICE", float(_settings.get("voice_volume", 0.9)))
	column.add_child(voice_row[0])

	var voice_pack_row := _option_row("VOICE PACK")
	var voice_pack := voice_pack_row[1] as OptionButton
	voice_pack.add_item("PACK 1 — CLASSIC")
	voice_pack.add_item("PACK 2 — ROBOT (PARTIAL)")
	voice_pack.select(1 if int(_settings.get("voice_pack", 1)) == 2 else 0)
	column.add_child(voice_pack_row[0])

	var brightness_row := _slider_row(
		"BACKGROUND BRIGHTNESS",
		float(_settings.get("background_brightness", 1.0))
	)
	(brightness_row[1] as HSlider).min_value = 0.25
	column.add_child(brightness_row[0])

	# The lobby server provides nicknames, the lobby list, global chat, and
	# talent storage. Solo and couch play never need it.
	var lobby_heading := Label.new()
	lobby_heading.text = "LOBBY SERVER"
	lobby_heading.add_theme_font_size_override("font_size", 15)
	lobby_heading.add_theme_color_override("font_color", Color("#ffd66b"))
	column.add_child(lobby_heading)
	var lobby_host_row := _text_row(
		"LOBBY ADDRESS", str(_settings.get("lobby_host", "")), "host or IP", false
	)
	column.add_child(lobby_host_row[0])
	var lobby_port_row := _text_row(
		"LOBBY PORT", str(int(_settings.get("lobby_port", 7400))), "1024-65535", false
	)
	column.add_child(lobby_port_row[0])
	var lobby_udp_row := _text_row(
		"RENDEZVOUS UDP PORT", str(int(_settings.get("lobby_udp_port", 7401))), "1024-65535", false
	)
	column.add_child(lobby_udp_row[0])
	var host_port_row := _text_row(
		"HOST PORT", str(int(_settings.get("host_port", 42000))), "1024-65535", false
	)
	column.add_child(host_port_row[0])
	var upnp := CheckButton.new()
	upnp.text = "UPnP port mapping when hosting"
	upnp.button_pressed = bool(_settings.get("upnp_enabled", true))
	column.add_child(upnp)
	var lobby_note := Label.new()
	lobby_note.text = "HOST PORT is the UDP port your Mac listens on when hosting an online co-op game."
	lobby_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lobby_note.add_theme_font_size_override("font_size", 12)
	lobby_note.add_theme_color_override("font_color", Color("#809bb4"))
	column.add_child(lobby_note)

	var controls := Label.new()
	controls.text = "P1  A / D + SPACE     P2  ← / → + ENTER     PAUSE  P / ESC"
	controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	controls.add_theme_font_size_override("font_size", 13)
	controls.add_theme_color_override("font_color", Color("#809bb4"))
	column.add_child(controls)

	var remap := _menu_button("CONTROLS", _show_controls)
	column.add_child(remap)

	var jukebox := _menu_button("JUKEBOX", _show_jukebox)
	column.add_child(jukebox)

	var save := _menu_button("SAVE SETTINGS", func() -> void:
		_settings_store.set_value("display_mode", ["windowed", "borderless", "fullscreen"][display.selected])
		var selected_size: Vector2i = resolutions[resolution.selected]
		_settings_store.set_value("window_width", selected_size.x)
		_settings_store.set_value("window_height", selected_size.y)
		_settings_store.set_value("render_cap", render_caps[cap.selected])
		_settings_store.set_value("collision_mode", "pixel" if collision.selected == 0 else "simple")
		_settings_store.set_value("effects_mode", "original" if effects.selected == 1 else "enhanced")
		_settings_store.set_value("texture_filter", "sharp" if filter.selected == 1 else "smooth")
		_settings_store.set_value(
			"sprite_pack",
			"" if sprite_pack.selected <= 0 else sprite_pack_names[sprite_pack.selected - 1]
		)
		_settings_store.set_value("vsync", vsync.button_pressed)
		_settings_store.set_value("master_volume", (master_row[1] as HSlider).value)
		_settings_store.set_value("music_volume", (music_row[1] as HSlider).value)
		_settings_store.set_value("sfx_volume", (sfx_row[1] as HSlider).value)
		_settings_store.set_value("voice_volume", (voice_row[1] as HSlider).value)
		_settings_store.set_value("voice_pack", 2 if voice_pack.selected == 1 else 1)
		_settings_store.set_value(
			"background_brightness", (brightness_row[1] as HSlider).value
		)
		_settings_store.set_value(
			"lobby_host", (lobby_host_row[1] as LineEdit).text.strip_edges()
		)
		_settings_store.set_value(
			"lobby_port", int((lobby_port_row[1] as LineEdit).text.strip_edges())
		)
		_settings_store.set_value(
			"lobby_udp_port", int((lobby_udp_row[1] as LineEdit).text.strip_edges())
		)
		_settings_store.set_value(
			"host_port", int((host_port_row[1] as LineEdit).text.strip_edges())
		)
		_settings_store.set_value("upnp_enabled", upnp.button_pressed)
		_settings_store.save_and_apply()
		_settings = _settings_store.values()
		_apply_texture_filter()
		_apply_background_brightness()
		_audio.configure(_settings)
		_lobby.disconnect_now()
		_configure_lobby_client()
		_lobby.connect_now()
		show_title()
	)
	column.add_child(save)
	column.add_child(_back_button(show_title))
	_focus_first_button(column)


func _show_controls() -> void:
	_clear_page()
	var column := _center_column(Vector2(640.0, 560.0))
	var screen := WBControlsScreen.new(_settings_store)
	screen.closed.connect(func() -> void:
		_settings = _settings_store.values()
		_show_settings()
	)
	column.add_child(screen)


func _show_jukebox() -> void:
	_clear_page()
	var column := _screen_column(
		"JUKEBOX",
		"Override any music slot with a built-in track or your own MP3/OGG file."
	)
	var jukebox_config: Dictionary = WBJukeboxStore.sanitize(
		_settings.get("jukebox", {})
	)
	var built_in := [
		"title", "warblade", "shop", "boss", "memory", "meteor", "gems",
		"hiscore", "promoted", "timetrial", "end", "endgame",
	]
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	var file_dialog := FileDialog.new()
	file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	file_dialog.use_native_dialog = true
	file_dialog.filters = ["*.mp3, *.ogg ; Music files"]
	add_child(file_dialog)
	var slots: Dictionary = jukebox_config.get("slots", {})
	for slot_id_value in WBJukeboxStore.SLOTS:
		var slot_id := str(slot_id_value)
		var default_key := str(WBJukeboxStore.SLOTS[slot_id])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var label := Label.new()
		label.text = str(WBJukeboxStore.SLOT_LABELS.get(slot_id, slot_id.to_upper()))
		label.custom_minimum_size = Vector2(200, 0)
		label.add_theme_font_size_override("font_size", 13)
		row.add_child(label)
		var selector := OptionButton.new()
		selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		selector.add_item("DEFAULT (%s)" % default_key.to_upper())
		for track in built_in:
			selector.add_item("TRACK: %s" % str(track).to_upper())
		var slot_config: Dictionary = (
			slots.get(slot_id, {}) if slots.get(slot_id, {}) is Dictionary else {}
		)
		var current_source := str(slot_config.get("source", ""))
		if current_source == "builtin":
			var track_index := built_in.find(str(slot_config.get("key", "")))
			if track_index >= 0:
				selector.select(track_index + 1)
		elif current_source == "user":
			selector.add_item("FILE: %s" % str(slot_config.get("path", "")).get_file())
			selector.select(selector.item_count - 1)
		selector.item_selected.connect(func(item_index: int) -> void:
			if item_index == 0:
				(jukebox_config.get("slots", {}) as Dictionary).erase(slot_id)
			elif item_index <= built_in.size():
				(jukebox_config.get("slots", {}) as Dictionary)[slot_id] = {
					"source": "builtin",
					"key": str(built_in[item_index - 1]),
				}
			_persist_jukebox(jukebox_config)
		)
		row.add_child(selector)
		var browse := Button.new()
		browse.text = "FILE..."
		browse.pressed.connect(func() -> void:
			var handler := func(path: String) -> void:
				(jukebox_config.get("slots", {}) as Dictionary)[slot_id] = {
					"source": "user",
					"path": path,
				}
				_persist_jukebox(jukebox_config)
				_show_jukebox()
			for connection in file_dialog.file_selected.get_connections():
				file_dialog.file_selected.disconnect(connection.callable)
			file_dialog.file_selected.connect(handler, CONNECT_ONE_SHOT)
			file_dialog.popup_centered_ratio(0.7)
		)
		row.add_child(browse)
		list.add_child(row)
	var note := Label.new()
	note.text = "Missing or moved files silently fall back to the built-in track."
	note.add_theme_font_size_override("font_size", 11)
	note.add_theme_color_override("font_color", Color("#809bb4"))
	column.add_child(note)
	column.add_child(_back_button(_show_settings))
	_focus_first_button(column)


func _persist_jukebox(jukebox_config: Dictionary) -> void:
	_settings_store.set_value("jukebox", jukebox_config)
	_settings_store.save_and_apply()
	_settings = _settings_store.values()
	_audio.configure(_settings)


## Builds and launches the selected match. The seed is drawn locally and the
## talent grants come from the cached lobby state, so a match starts the
## same way online and offline.
func _start_match() -> void:
	if str(_party.get("role", "")) == "host":
		_start_hosted_match()
		return
	_launch_match(_build_match_config())


func _build_match_config() -> Dictionary:
	return WBMatchConfig.make(
		_mode,
		_difficulty,
		_coop_balance,
		_selected_profiles,
		str(_settings.get("collision_mode", "pixel")),
		WBMatchConfig.random_seed(),
		_talent_grants()
	)


## The composed talent grants for seat 0 (the pilot bound to this identity).
## Empty grants still run talent-enabled so the shop keeps its license rules.
func _talent_grants() -> Dictionary:
	return {"enabled": true}.merged(_lobby.current_grants())


## A finished run reports itself to the lobby server when registered so
## talent points can be credited; offline runs simply record locally.
func _on_match_finished(result: Dictionary) -> void:
	if _demo_active or _lobby == null or not _lobby.is_registered():
		return
	var role := str(_party.get("role", ""))
	if role == "joiner":
		# The host reports a hosted match for both seats.
		return
	var outcome := "completed" if bool(result.get("completed", false)) else "game_over"
	if bool(result.get("retired", false)):
		outcome = "retired"
	var terminal_value: Variant = result.get("campaign_terminal", {})
	var terminal: Dictionary = terminal_value if terminal_value is Dictionary else {}
	var report := {
		"kind": "hosted" if role == "host" else ("couch" if _mode == "coop" else "solo"),
		"mode": _mode,
		"difficulty": _difficulty,
		"coop_balance": _coop_balance,
		"result": outcome,
		"score": int(result.get("score", 0)),
		"level_reached": int(result.get("level_id", 1)),
		"duration_ticks": int(result.get("duration_ticks", 0)),
		"campaign_completed": bool(terminal.get("full_campaign_completed", false)),
	}
	if role == "host":
		if int(_party.get("match_id", 0)) <= 0:
			return
		report["match_id"] = int(_party.get("match_id", 0))
	await _lobby.report_match_end(report)


func _announce_credit(points: int) -> void:
	var toast := Label.new()
	toast.name = "CreditToast"
	toast.text = "RUN RECORDED: +%d TALENT POINTS" % points
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.add_theme_font_size_override("font_size", 16)
	toast.add_theme_color_override("font_color", Color("#ffd66b"))
	toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toast.position = Vector2(-260.0, 40.0)
	toast.size = Vector2(520.0, 24.0)
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(toast)
	var timer := get_tree().create_timer(6.0)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(toast):
			toast.queue_free()
	)


func _launch_match(config: Dictionary) -> void:
	config["effects_mode"] = str(_settings.get("effects_mode", "enhanced"))
	config["texture_filter"] = str(_settings.get("texture_filter", "smooth"))
	# The HUD hiscore row mirrors the retail top line; seed it from the best
	# profile score so the live run overtakes it exactly like retail.
	var best_score := 0
	var best_key := (
		"best_time_trial_score" if _mode == "time_trial" else "best_score"
	)
	for profile in _profile_entries:
		best_score = maxi(best_score, int(profile.get(best_key, 0)))
	config["hiscore"] = best_score
	_clear_page()
	_gameplay = WBGameplayScreen.new()
	_active_result_persisted = false
	_gameplay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_gameplay.exit_requested.connect(_on_gameplay_exit)
	_gameplay.shop_save_requested.connect(_on_shop_save_requested)
	_gameplay.authoritative_result_ready.connect(_on_authoritative_result_ready)
	_gameplay.match_finished.connect(_on_match_finished)
	_gameplay.party_waiting.connect(_on_party_waiting)
	_gameplay.sound_requested.connect(_on_gameplay_sound)
	_gameplay.audio_requested.connect(_on_gameplay_audio_requested)
	_page.add_child(_gameplay)
	_audio.play_music("timetrial" if _mode == "time_trial" else "warblade")
	if not _gameplay.begin(config):
		_audio.play_music("title")
		show_title()
		var error_label := Label.new()
		error_label.text = "GAME SERVER UNAVAILABLE"
		error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		error_label.add_theme_color_override("font_color", Color("#ff7b6b"))
		error_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		error_label.position = Vector2(-260, -40)
		error_label.size = Vector2(520, 36)
		_page.add_child(error_label)


func _on_gameplay_sound(key: String) -> void:
	var music_key := gameplay_music_key(key)
	if not music_key.is_empty():
		_audio.play_music(music_key)
		return
	_audio.play_sfx(key)


static func gameplay_music_key(key: String) -> String:
	return str({
		"music_shop": "shop",
		"music_warblade": "warblade",
		"music_promoted": "promoted",
		"music_memory": "memory",
		"music_meteor": "meteor",
		"music_endgame": "endgame",
	}.get(key, ""))


func _on_gameplay_audio_requested(request: Dictionary) -> void:
	_audio.play_request(request)


## Retail writes an in-shop save into a numbered slot. The remake keeps the
## slot contract and stores its own authoritative shop-boundary state.
func _on_shop_save_requested() -> void:
	if _gameplay == null:
		return
	var slot := WBSaveGameStore.SLOT_COUNT - 1
	for candidate in range(WBSaveGameStore.SLOT_COUNT):
		if not _saved_games.has_slot(candidate):
			slot = candidate
			break
	# The authoritative game server owns the run state and writes the slot
	# itself; the acknowledgement arrives on the control channel.
	if _gameplay.request_shop_save(slot):
		_gameplay.report_shop_save("SAVING TO SLOT %d..." % (slot + 1))
	else:
		_gameplay.report_shop_save("SAVE FAILED: THE RUN CANNOT BE SAVED HERE")


## Retail lists its numbered save slots; an empty slot cannot be resumed.
func _show_saved_games() -> void:
	_clear_page()
	var column := _screen_column(
		"LOAD SAVED GAME",
		"Runs are saved from the shop and resume exactly where they stopped."
	)
	var occupied := 0
	for summary in _saved_games.slot_summaries():
		var slot := int(summary.get("slot", 0))
		if not bool(summary.get("occupied", false)):
			continue
		occupied += 1
		var label := "SLOT %d\n%s %s - LEVEL %d - %d POINTS" % [
			slot + 1,
			str(summary.get("mode", "")).to_upper(),
			str(summary.get("difficulty", "")).to_upper(),
			int(summary.get("level_id", 0)),
			int(summary.get("score", 0)),
		]
		var button := _menu_button(label, func() -> void: _resume_saved_game(slot))
		button.custom_minimum_size.y = 64.0
		column.add_child(button)
	if occupied == 0:
		var empty := Label.new()
		empty.text = "NO SAVED GAMES"
		empty.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(empty)
	column.add_child(_back_button(show_title))
	_focus_first_button(column)


## Resumes a saved run straight into the gameplay screen. The authoritative
## game server restores the numbered slot itself; the session only routes the
## request to the configured server.
func _resume_saved_game(slot: int) -> void:
	var save := _saved_games.load_slot(slot)
	if save.is_empty():
		return
	var match_config: Dictionary = (save.get("match_config", {}) as Dictionary).duplicate(true)
	_mode = str(match_config.get("mode", "solo"))
	_difficulty = str(match_config.get("difficulty", "normal"))
	_coop_balance = str(match_config.get("coop_balance", "classic"))
	_clear_page()
	_gameplay = WBGameplayScreen.new()
	_active_result_persisted = false
	_gameplay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_gameplay.exit_requested.connect(_on_gameplay_exit)
	_gameplay.shop_save_requested.connect(_on_shop_save_requested)
	_gameplay.authoritative_result_ready.connect(_on_authoritative_result_ready)
	_gameplay.match_finished.connect(_on_match_finished)
	_gameplay.sound_requested.connect(_on_gameplay_sound)
	_gameplay.audio_requested.connect(_on_gameplay_audio_requested)
	_page.add_child(_gameplay)
	_audio.play_music("timetrial" if _mode == "time_trial" else "warblade")
	if not _gameplay.resume(save):
		_audio.play_music("title")
		show_title()


func _on_gameplay_exit(result: Dictionary) -> void:
	if _demo_active:
		# Demo attract runs record nothing, matching retail self-play.
		_demo_active = false
		_gameplay = null
		_audio.play_music("title")
		show_title()
		return
	_end_party_session()
	if not _active_result_persisted and not bool(
		result.get("profile_result_persisted", false)
	):
		_profiles.record_result(_selected_profile_ids(), result)
	if result.has("tally_by_seat"):
		var names_by_seat: Array = []
		for seat in range(WBInputRouter.seats_for_mode(_mode)):
			names_by_seat.append(
				str(_selected_profiles[seat].get("name", "PILOT"))
				if seat < _selected_profiles.size()
				else "GUEST %d" % (seat + 1)
			)
		_hiscores.record_result(result, _mode, _difficulty, names_by_seat)
	_profile_entries = _profiles.profiles()
	_active_result_persisted = false
	_gameplay = null
	_audio.play_music("title")
	show_title()


## --- Online co-op: hosting ----------------------------------------------

func _start_host_setup() -> void:
	_mode = "coop"
	_party = {"role": "host"}
	_selected_profiles = [_pilot_profile(), {"id": "guest", "name": "GUEST"}]
	_show_difficulty_select()


## The host spawns its own game server bound publicly and plays seat 0; the
## joiner arrives through the lobby server (or CONNECT TO HOST) as seat 1.
func _build_hosted_config() -> Dictionary:
	var port := int(_settings.get("host_port", WBLobbyContract.DEFAULT_HOST_PORT))
	var token := Crypto.new().generate_random_bytes(8).hex_encode()
	var config := _build_match_config()
	config["server"] = {"kind": "host", "port": port, "token": token, "seat": 0}
	config["party"] = {"role": "host", "nickname": _identity.nickname()}
	_party = {
		"role": "host",
		"port": port,
		"token": token,
		"lobby_id": "",
		"match_id": 0,
		"registered": false,
		"started": false,
		"seed": str(config.get("seed", 0)),
	}
	# With the lobby server reachable the sidecar keeps its rendezvous socket
	# informed, so joiners on the internet learn where to punch.
	var rendezvous_ip := _lobby_ipv4()
	if _lobby.is_registered() and not rendezvous_ip.is_empty() and _lobby.udp_port() > 0:
		var nonce := WBRendezvous.make_nonce_hex()
		(config["server"] as Dictionary)["rendezvous"] = "%s:%d" % [rendezvous_ip, _lobby.udp_port()]
		(config["server"] as Dictionary)["nonce"] = nonce
		_party["nonce"] = nonce
	return config


func _lobby_ipv4() -> String:
	return WBRendezvous.resolve_ipv4(_lobby.host()) if _lobby != null else ""


func _start_hosted_match() -> void:
	var config := _build_hosted_config()
	var nonce := str(_party.get("nonce", ""))
	if not nonce.is_empty():
		# The lobby server must know the nonce before the sidecar's first
		# keepalive arrives, or that datagram is dropped as unregistered.
		await _lobby.register_rendezvous(nonce)
	_launch_match(config)


func _on_party_waiting(waiting: bool) -> void:
	if str(_party.get("role", "")) != "host" or _gameplay == null:
		return
	if waiting:
		if not bool(_party.get("registered", false)):
			_register_hosted_lobby()
		elif not str(_party.get("lobby_id", "")).is_empty() and _lobby.is_online():
			# The joiner left: reopen the seat in the lobby list.
			_lobby.update_lobby(str(_party["lobby_id"]), {"open": true})
		return
	if not bool(_party.get("started", false)):
		_party["started"] = true
		_report_hosted_match_start()


func _party_manual_line() -> String:
	var lan := WBRendezvous.local_lan_ipv4()
	return "CONNECT TO HOST: %s PORT %d TOKEN %s" % [
		lan if not lan.is_empty() else "THIS MAC'S IP",
		int(_party.get("port", 0)),
		str(_party.get("token", "")).to_upper(),
	]


func _register_hosted_lobby() -> void:
	_party["registered"] = true
	var port := _gameplay.listen_port()
	if port <= 0:
		port = int(_party.get("port", 0))
	_party["port"] = port
	if not _lobby.is_registered():
		_gameplay.set_party_status("LOBBY SERVER OFFLINE — " + _party_manual_line())
		return
	var fields := {
		"name": "%s'S GAME" % _identity.nickname().to_upper(),
		"mode": _mode,
		"difficulty": _difficulty,
		"coop_balance": _coop_balance,
		"game_token": str(_party.get("token", "")),
		"port": port,
		"upnp_mapped": false,
	}
	var lan := WBRendezvous.local_lan_ipv4()
	if not lan.is_empty():
		fields["lan"] = {"ip": lan, "port": port}
	_gameplay.set_party_status("LISTING YOUR GAME...")
	var outcome: Dictionary = await _lobby.create_lobby(fields)
	if _gameplay == null or str(_party.get("role", "")) != "host":
		return
	if not bool(outcome.get("ok", false)):
		_gameplay.set_party_status(
			"LOBBY LISTING FAILED: %s — %s" % [
				_lobby_error_text(outcome.get("error", {})), _party_manual_line()
			]
		)
		return
	var lobby_value: Variant = outcome.get("lobby", {})
	var lobby: Dictionary = lobby_value if lobby_value is Dictionary else {}
	_party["lobby_id"] = str(lobby.get("lobby_id", ""))
	_gameplay.set_party_status("LISTED IN THE LOBBY — " + _party_manual_line())
	if bool(_settings.get("upnp_enabled", true)) and _rendezvous.map_port_async(port):
		_party["upnp_pending"] = true


func _on_upnp_finished(result: Dictionary) -> void:
	if str(result.get("action", "")) != "map":
		return
	if str(_party.get("role", "")) != "host" or _gameplay == null:
		return
	_party["upnp_pending"] = false
	var port := int(result.get("port", 0))
	if bool(result.get("ok", false)):
		_party["upnp_mapped"] = true
		if not str(_party.get("lobby_id", "")).is_empty() and _lobby.is_online():
			_lobby.update_lobby(
				str(_party["lobby_id"]), {"upnp_mapped": true, "upnp_external_port": port}
			)
		_gameplay.set_party_status(
			"LISTED IN THE LOBBY — ROUTER PORT %d MAPPED — %s" % [port, _party_manual_line()]
		)
	else:
		_gameplay.set_party_status(
			"LISTED IN THE LOBBY — NO UPNP (%s) — %s" % [
				str(result.get("error", "")).to_upper(), _party_manual_line()
			]
		)


func _report_hosted_match_start() -> void:
	if not _lobby.is_registered() or str(_party.get("lobby_id", "")).is_empty():
		return
	var outcome: Dictionary = await _lobby.report_match_start({
		"kind": "hosted",
		"mode": _mode,
		"difficulty": _difficulty,
		"coop_balance": _coop_balance,
		"seed": str(_party.get("seed", "")),
		"start_level": 1,
		"end_level": WBMatchConfig.MAX_END_LEVEL,
		"content_hash": _content_hash,
	})
	if bool(outcome.get("ok", false)) and str(_party.get("role", "")) == "host":
		_party["match_id"] = int(outcome.get("match_id", 0))


func _on_lobby_join_offer(offer: Dictionary) -> void:
	var join_id := int(offer.get("join_id", 0))
	if str(_party.get("role", "")) != "host" or _gameplay == null:
		_lobby.answer_join(join_id, false, "not_hosting")
		return
	var joiner_value: Variant = offer.get("joiner", {})
	var joiner: Dictionary = joiner_value if joiner_value is Dictionary else {}
	var nickname := str(joiner.get("nickname", "PLAYER"))
	# Open the router toward the joiner before telling them to connect.
	for key in ["public", "lan"]:
		var endpoint_value: Variant = joiner.get(key)
		if endpoint_value is Dictionary:
			var endpoint := endpoint_value as Dictionary
			_gameplay.punch_request(str(endpoint.get("ip", "")), int(endpoint.get("port", 0)))
	_party["joiner_nickname"] = nickname
	_gameplay.set_party_joiner(nickname)
	_gameplay.append_party_line("LOBBY", "%s is connecting..." % nickname)
	_lobby.answer_join(join_id, true)


func _on_lobby_joiner_left(info: Dictionary) -> void:
	if str(_party.get("role", "")) != "host" or _gameplay == null:
		return
	_gameplay.append_party_line("LOBBY", "%s left" % str(info.get("nickname", "the player")))


func _end_party_session() -> void:
	var role := str(_party.get("role", ""))
	var lobby_id := str(_party.get("lobby_id", ""))
	if role == "host" and not lobby_id.is_empty() and _lobby.is_online():
		_lobby.close_lobby(lobby_id)
	elif role == "joiner" and _lobby.is_online():
		_lobby.leave_lobby()
	if role == "host" and bool(_party.get("upnp_mapped", false)):
		_rendezvous.unmap_port_async(int(_party.get("port", 0)))
	_rendezvous.close_probe()
	_party = {}


## --- Online co-op: joining ----------------------------------------------

func _show_lobby_browser() -> void:
	_clear_page()
	_stop_attract_timer()
	_party = {}
	var column := _screen_column(
		"JOIN ONLINE GAME",
		"Games other players are hosting right now. Your game content must match the host's."
	)
	var status := Label.new()
	status.name = "LobbyBrowserStatus"
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.add_theme_font_size_override("font_size", 12)
	status.add_theme_color_override("font_color", Color("#809bb4"))
	column.add_child(status)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	var list := VBoxContainer.new()
	list.name = "LobbyList"
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	column.add_child(_menu_button("REFRESH", func() -> void: _refresh_lobby_list(list, status)))
	column.add_child(_menu_button("CONNECT TO HOST", _show_manual_connect))
	column.add_child(_back_button(show_title))
	var timer := Timer.new()
	timer.wait_time = 5.0
	timer.autostart = true
	timer.timeout.connect(func() -> void:
		if is_instance_valid(list):
			_refresh_lobby_list(list, status)
	)
	column.add_child(timer)
	var on_changed := func() -> void:
		if is_instance_valid(list):
			_refresh_lobby_list(list, status)
	_lobby.lobby_list_changed.connect(on_changed)
	list.tree_exited.connect(func() -> void:
		if _lobby.lobby_list_changed.is_connected(on_changed):
			_lobby.lobby_list_changed.disconnect(on_changed)
	)
	_refresh_lobby_list(list, status)
	_focus_first_button(column)


func _refresh_lobby_list(list: VBoxContainer, status: Label) -> void:
	if not _lobby.is_registered():
		status.text = "LOBBY SERVER OFFLINE — USE CONNECT TO HOST"
		return
	var outcome: Dictionary = await _lobby.list_lobbies()
	if not is_instance_valid(list) or not is_instance_valid(status):
		return
	for child in list.get_children():
		list.remove_child(child)
		child.queue_free()
	if not bool(outcome.get("ok", false)):
		status.text = _lobby_error_text(outcome.get("error", {}))
		return
	var lobbies_value: Variant = outcome.get("lobbies", [])
	var lobbies: Array = lobbies_value if lobbies_value is Array else []
	status.text = (
		"%d GAME%s LISTED" % [lobbies.size(), "" if lobbies.size() == 1 else "S"]
		if not lobbies.is_empty()
		else "NO GAMES LISTED — HOST ONE OR WAIT"
	)
	for lobby_value: Variant in lobbies:
		if not lobby_value is Dictionary:
			continue
		var lobby := lobby_value as Dictionary
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var label := Label.new()
		label.text = "%s — %s %s — %s" % [
			str(lobby.get("host_nickname", "?")).to_upper(),
			str(lobby.get("difficulty", "")).to_upper(),
			str(lobby.get("coop_balance", "")).to_upper(),
			str(lobby.get("state", "")).to_upper(),
		]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_font_size_override("font_size", 13)
		row.add_child(label)
		var join := Button.new()
		join.name = "Join_" + str(lobby.get("lobby_id", ""))
		join.text = "JOIN"
		join.disabled = (
			str(lobby.get("state", "")) != "open"
			or not bool(lobby.get("content_matches", true))
			or not bool(lobby.get("host_fresh", true))
		)
		join.pressed.connect(func() -> void: _begin_join(lobby))
		row.add_child(join)
		list.add_child(row)


## Asks the lobby server to introduce us to the host; the endpoints and the
## game token arrive through a lobby_join_ready push once the host accepts.
func _begin_join(lobby: Dictionary) -> void:
	_clear_page()
	var host_nickname := str(lobby.get("host_nickname", "HOST"))
	var column := _screen_column(
		"JOINING %s" % host_nickname.to_upper(),
		"Contacting the host through the lobby server..."
	)
	var status := Label.new()
	status.name = "JoinStatus"
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.add_theme_color_override("font_color", Color("#ffd66b"))
	column.add_child(status)
	column.add_child(_back_button(func() -> void:
		if _lobby.is_online():
			_lobby.leave_lobby()
		_show_lobby_browser()
	))
	_party = {
		"role": "joiner",
		"lobby_id": str(lobby.get("lobby_id", "")),
		"host_nickname": host_nickname,
		"join_id": 0,
	}
	# Learn our public endpoint from the rendezvous socket first, from the
	# very local port ENet will use, so the host can punch toward it.
	var rendezvous_ip := _lobby_ipv4()
	if not rendezvous_ip.is_empty() and _lobby.udp_port() > 0:
		var nonce := WBRendezvous.make_nonce_hex()
		_party["nonce"] = nonce
		await _lobby.register_rendezvous(nonce)
		if not is_instance_valid(status) or str(_party.get("role", "")) != "joiner":
			return
		if _rendezvous.begin_probe(rendezvous_ip, _lobby.udp_port(), nonce):
			status.text = "FINDING YOUR PUBLIC ADDRESS..."
			return
	_continue_join({})


func _on_probe_finished(result: Dictionary) -> void:
	if str(_party.get("role", "")) != "joiner" or _gameplay != null:
		return
	var fields := {}
	var local_port := int(result.get("local_port", 0))
	_party["local_port"] = local_port
	var lan := WBRendezvous.local_lan_ipv4()
	if local_port > 0 and not lan.is_empty():
		fields["lan"] = {"ip": lan, "port": local_port}
	if bool(result.get("ok", false)):
		_party["public"] = {"ip": str(result.get("ip", "")), "port": int(result.get("port", 0))}
	else:
		var status := find_child("JoinStatus", true, false) as Label
		if status != null:
			status.text = "NO ANSWER FROM THE RENDEZVOUS SOCKET — TRYING ANYWAY"
	_continue_join(fields)


func _continue_join(fields: Dictionary) -> void:
	var outcome: Dictionary = await _lobby.request_join(str(_party.get("lobby_id", "")), fields)
	var status := find_child("JoinStatus", true, false) as Label
	if status == null or str(_party.get("role", "")) != "joiner":
		return
	if not bool(outcome.get("ok", false)):
		status.text = _lobby_error_text(outcome.get("error", {}))
		return
	_party["join_id"] = int(outcome.get("join_id", 0))
	status.text = "WAITING FOR THE HOST TO ACCEPT..."


func _on_lobby_join_ready(info: Dictionary) -> void:
	if str(_party.get("role", "")) != "joiner" or _gameplay != null:
		return
	if int(info.get("join_id", -1)) != int(_party.get("join_id", 0)):
		return
	var lan_value: Variant = info.get("host_lan")
	var public_value: Variant = info.get("host_public")
	var lan_candidate := {}
	if lan_value is Dictionary:
		lan_candidate = {
			"host": str((lan_value as Dictionary).get("ip", "")),
			"port": int((lan_value as Dictionary).get("port", 0)),
			"lan": true,
		}
	var public_candidate := {}
	if public_value is Dictionary:
		public_candidate = {
			"host": str((public_value as Dictionary).get("ip", "")),
			"port": int((public_value as Dictionary).get("port", 0)),
		}
	# Behind one router the LAN address is the sure path; otherwise the public
	# endpoint comes first and the LAN one stays as a long shot.
	var ordered: Array = (
		[lan_candidate, public_candidate]
		if bool(info.get("same_public_ip", false))
		else [public_candidate, lan_candidate]
	)
	var candidates: Array = []
	for candidate: Variant in ordered:
		if not (candidate as Dictionary).is_empty():
			candidates.append(candidate)
	if candidates.is_empty():
		var status := find_child("JoinStatus", true, false) as Label
		if status != null:
			status.text = "THE HOST HAS NO REACHABLE ADDRESS — USE CONNECT TO HOST"
		return
	_launch_joined_match(
		candidates,
		str(info.get("game_token", "")),
		str(info.get("host_nickname", _party.get("host_nickname", "HOST")))
	)


func _on_lobby_join_rejected(info: Dictionary) -> void:
	if str(_party.get("role", "")) != "joiner" or _gameplay != null:
		return
	var status := find_child("JoinStatus", true, false) as Label
	if status != null:
		status.text = "THE HOST DID NOT ACCEPT (%s)" % str(info.get("reason", "")).to_upper()


func _on_lobby_closed(info: Dictionary) -> void:
	if str(_party.get("role", "")) != "joiner" or _gameplay != null:
		return
	var status := find_child("JoinStatus", true, false) as Label
	if status != null:
		status.text = "THE HOST CLOSED THE GAME (%s)" % str(info.get("reason", "")).to_upper()


## The joiner plays whatever match the host authored: its HELLO carries no
## request and the contract is adopted from the first snapshot.
func _launch_joined_match(candidates: Array, token: String, host_nickname: String) -> void:
	_mode = "coop"
	_selected_profiles = [{"id": "guest", "name": host_nickname}, _pilot_profile()]
	var config := WBMatchConfig.make(
		"coop",
		"normal",
		"classic",
		_selected_profiles,
		str(_settings.get("collision_mode", "pixel")),
		WBMatchConfig.random_seed()
	)
	config["server"] = {
		"kind": "join",
		"candidates": candidates,
		"token": token,
		"local_port": int(_party.get("local_port", 0)),
		"seat": 1,
	}
	config["party"] = {
		"role": "joiner",
		"nickname": _identity.nickname(),
		"host_nickname": host_nickname,
	}
	_party["role"] = "joiner"
	_party["host_nickname"] = host_nickname
	_launch_match(config)


func _show_manual_connect() -> void:
	_clear_page()
	var column := _screen_column(
		"CONNECT TO HOST",
		"Enter the address, port, and token the host sees in their waiting room."
	)
	var host_row := _text_row("HOST ADDRESS", "", "ip or hostname", false)
	(host_row[1] as LineEdit).name = "HostAddressInput"
	column.add_child(host_row[0])
	var port_row := _text_row("PORT", str(WBLobbyContract.DEFAULT_HOST_PORT), "1024-65535", false)
	(port_row[1] as LineEdit).name = "HostPortInput"
	column.add_child(port_row[0])
	var token_row := _text_row("TOKEN", "", "game token", false)
	(token_row[1] as LineEdit).name = "HostTokenInput"
	column.add_child(token_row[0])
	var status := Label.new()
	status.name = "ManualConnectStatus"
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.add_theme_color_override("font_color", Color("#ff7b6b"))
	column.add_child(status)
	column.add_child(_menu_button("CONNECT", func() -> void:
		var host := (host_row[1] as LineEdit).text.strip_edges()
		var port := int((port_row[1] as LineEdit).text.strip_edges())
		var token := (token_row[1] as LineEdit).text.strip_edges().to_lower()
		if host.is_empty() or port < 1024 or port > 65535 or token.is_empty():
			status.text = "ENTER THE HOST ADDRESS, A PORT FROM 1024 TO 65535, AND THE TOKEN"
			return
		_party = {"role": "joiner", "lobby_id": "", "host_nickname": "HOST", "join_id": 0}
		_launch_joined_match([{"host": host, "port": port}], token, "HOST")
	))
	column.add_child(_back_button(_show_lobby_browser))
	_focus_first_button(column)


func _on_authoritative_result_ready(result: Dictionary) -> void:
	if _active_result_persisted or _demo_active:
		return
	if not _profiles.record_result(_selected_profile_ids(), result):
		if _gameplay != null:
			_gameplay.mark_authoritative_result_persist_failed(
				_profiles.last_save_error
			)
		return
	_active_result_persisted = true
	_profile_entries = _profiles.profiles()
	if _gameplay != null:
		_gameplay.mark_authoritative_result_persisted()


func _selected_profile_ids() -> Array:
	var ids: Array = []
	for profile in _selected_profiles:
		ids.append(str(profile.get("id", "")))
	return ids


func _create_backdrop() -> void:
	var star_texture := _assets.texture("stars1")
	if star_texture != null:
		var starfield := TextureRect.new()
		starfield.name = "OriginalStarBackdrop"
		starfield.texture = star_texture
		starfield.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		starfield.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		starfield.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		starfield.modulate = Color(0.42, 0.52, 0.7, 0.48)
		starfield.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(starfield)
		_apply_background_brightness()
	var background := ColorRect.new()
	background.color = Color(0.01, 0.025, 0.06, 0.55)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	var screen_texture := _assets.texture("newscreen")
	if screen_texture != null:
		var title_frame := TextureRect.new()
		title_frame.name = "OriginalTitleScreen"
		title_frame.texture = screen_texture
		title_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		title_frame.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		title_frame.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		title_frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(title_frame)


func _apply_texture_filter() -> void:
	texture_filter = (
		CanvasItem.TEXTURE_FILTER_NEAREST
		if str(_settings.get("texture_filter", "smooth")) == "sharp"
		else CanvasItem.TEXTURE_FILTER_LINEAR
	)


func _apply_background_brightness() -> void:
	var brightness := clampf(float(_settings.get("background_brightness", 1.0)), 0.25, 1.0)
	var starfield := get_node_or_null("OriginalStarBackdrop")
	if starfield is CanvasItem:
		(starfield as CanvasItem).modulate = Color(
			0.42 * brightness, 0.52 * brightness, 0.7 * brightness, 0.48
		)


func _clear_page() -> void:
	_stop_attract_timer()
	for child in _page.get_children():
		_page.remove_child(child)
		child.queue_free()


func _center_column(panel_size: Vector2) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.position = -panel_size * 0.5
	panel.size = panel_size
	_page.add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	return column


func _screen_column(title: String, description: String) -> VBoxContainer:
	var column := _center_column(Vector2(560.0, 520.0))
	var heading := Label.new()
	heading.text = title
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	heading.add_theme_font_size_override("font_size", 24)
	heading.add_theme_color_override("font_color", Color("#ffd66b"))
	column.add_child(heading)
	var subtitle := Label.new()
	subtitle.text = description
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	subtitle.add_theme_font_size_override("font_size", 13)
	subtitle.add_theme_color_override("font_color", Color("#809bb4"))
	column.add_child(subtitle)
	var divider := HSeparator.new()
	column.add_child(divider)
	return column


func _menu_button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0.0, 44.0)
	button.pressed.connect(callback)
	return button


func _back_button(callback: Callable) -> Button:
	return _menu_button("BACK", callback)


func _option_row(label_text: String) -> Array:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 180.0
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var option := OptionButton.new()
	option.custom_minimum_size = Vector2(260.0, 42.0)
	row.add_child(option)
	return [row, option]


func _text_row(label_text: String, value: String, placeholder: String, secret: bool) -> Array:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 180.0
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var edit := LineEdit.new()
	edit.text = value
	edit.placeholder_text = placeholder
	edit.secret = secret
	edit.custom_minimum_size = Vector2(260.0, 42.0)
	row.add_child(edit)
	return [row, edit]


func _slider_row(label_text: String, value: float) -> Array:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 180.0
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = value
	slider.custom_minimum_size = Vector2(260.0, 36.0)
	row.add_child(slider)
	return [row, slider]


func _focus_first_button(root: Node) -> void:
	for child in root.get_children():
		if child is Button and not child.disabled:
			child.grab_focus.call_deferred()
			return


func _quit() -> void:
	get_tree().quit()


func _create_theme() -> Theme:
	var result := Theme.new()
	result.default_font_size = 16
	var panel := StyleBoxFlat.new()
	panel.bg_color = Color(0.01, 0.02, 0.05, 0.94)
	panel.border_color = Color("#3a2a10")
	panel.set_border_width_all(1)
	panel.corner_radius_top_left = 0
	panel.corner_radius_top_right = 0
	panel.corner_radius_bottom_left = 0
	panel.corner_radius_bottom_right = 0
	result.set_stylebox("panel", "PanelContainer", panel)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.02, 0.03, 0.08, 0.88)
	normal.border_color = Color("#2a2008")
	normal.set_border_width_all(1)
	normal.corner_radius_top_left = 0
	normal.corner_radius_top_right = 0
	normal.corner_radius_bottom_left = 0
	normal.corner_radius_bottom_right = 0
	normal.content_margin_left = 10.0
	normal.content_margin_right = 10.0
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.05, 0.08, 0.15, 0.92)
	hover.border_color = Color("#8a6a20")
	var pressed_style := normal.duplicate() as StyleBoxFlat
	pressed_style.bg_color = Color(0.01, 0.02, 0.04, 0.95)
	result.set_stylebox("normal", "Button", normal)
	result.set_stylebox("hover", "Button", hover)
	result.set_stylebox("focus", "Button", hover)
	result.set_stylebox("pressed", "Button", pressed_style)
	result.set_color("font_color", "Button", Color("#c8b878"))
	result.set_color("font_hover_color", "Button", Color("#ffe8a0"))
	result.set_color("font_focus_color", "Button", Color("#ffe8a0"))
	result.set_color("font_color", "Label", Color("#b8c8d8"))
	return result

extends SceneTree

const AppBootstrap := preload("res://src/app/app_bootstrap.gd")
const RejectingProfileStore := preload("res://tests/client/rejecting_profile_store.gd")
const BitmapTextLayout := preload("res://src/client/bitmap_text_layout.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_aspect_fit()
	_test_input_normalization()
	_test_bitmap_font_layout()
	_test_no_placeholder_renderer_source()
	_test_match_config()
	_test_settings_sanitization()
	_test_settings_file_migration()
	_test_sprite_pack_override()
	_test_jukebox_store()
	_test_input_remap()
	_test_hiscore_store()
	_test_manual_decode()
	_test_profile_management()
	_test_sidecar_suspend_grace()
	_test_network_match_contract()
	_test_profile_persistence()
	await _test_ending_presentation()
	await _test_campaign_ending_gate()
	await _test_renderer_layout()
	await _test_boss_renderer()
	await _test_hud_original_assets()
	await _test_gameplay_screen_original_ui()
	await _test_shell_boot()
	await _test_nickname_prompt_path()
	await _test_talent_tree_screen()
	await _test_local_seed_and_grants()
	await _test_match_end_report_credits()
	await _test_global_chat_screen()
	await _test_lobby_browser_and_manual_connect()
	await _test_host_lobby_registration()
	await _test_gameplay_party_room()
	await _test_shop_party_seat_controls()
	if _failures.is_empty():
		print("CLIENT TESTS PASSED")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("CLIENT TESTS FAILED: %d" % _failures.size())
	quit(1)


func _test_aspect_fit() -> void:
	var widescreen := WBAspectFit.calculate(Vector2(1920.0, 1080.0))
	_expect_vector(widescreen.position, Vector2(240.0, 0.0), "16:9 centers the 4:3 arena")
	_expect_vector(widescreen.size, Vector2(1440.0, 1080.0), "16:9 preserves all 800x600 gameplay")
	var portrait := WBAspectFit.calculate(Vector2(900.0, 1200.0))
	_expect_vector(portrait.position, Vector2(0.0, 262.5), "portrait centers the arena vertically")
	_expect_vector(portrait.size, Vector2(900.0, 675.0), "portrait preserves the arena aspect")
	var logical := Vector2(123.0, 456.0)
	var output := WBAspectFit.logical_to_output(logical, widescreen)
	_expect_vector(WBAspectFit.output_to_logical(output, widescreen), logical, "aspect mapping round trips")


func _test_bitmap_font_layout() -> void:
	var assets := WBAssetLibrary.new()
	_expect_equal(assets.manifest_version(), 2, "the client loads the finite-product presentation v2 manifest")
	var fonts := assets.section("bitmap_fonts")
	var primary_value: Variant = fonts.get("abcd_2", {})
	_expect(primary_value is Dictionary, "presentation v2 publishes the primary bitmap-font contract")
	var layout := BitmapTextLayout.new()
	if not primary_value is Dictionary:
		assets.clear()
		return
	_expect(layout.configure(primary_value as Dictionary), "the executable-proven fixed font contract is consumable")
	_expect_equal(layout.cell_size(), Vector2i(8, 8), "primary bitmap glyphs use exact 8x8 cells")
	_expect_equal(layout.line_width("A 1"), 24, "space and glyph advances remain fixed at eight pixels")
	_expect_equal(layout.text_size("AB\n1"), Vector2i(16, 16), "bitmap layout applies exact newline height")
	var placements := layout.glyph_placements("A 1", Vector2(10.0, 20.0), 1)
	_expect_equal(placements.size(), 2, "spaces advance without drawing a bitmap cell")
	if placements.size() == 2:
		_expect_equal(placements[0].source, Rect2i(0, 13, 8, 8), "A selects executable glyph index zero and style row one")
		_expect_equal(placements[1].source, Rect2i(27 * 8, 13, 8, 8), "digit one selects executable glyph index twenty-seven")
		_expect_equal(placements[1].destination.position, Vector2(26.0, 20.0), "glyph placement preserves both fixed advances")
	var legacy_path := "user://presentation_v1_compat_%d.json" % Time.get_ticks_usec()
	var legacy_file := FileAccess.open(legacy_path, FileAccess.WRITE)
	legacy_file.store_string(JSON.stringify({
		"version": 1,
		"schema": "warblade.presentation.v1",
		"textures": {},
		"music": {},
		"sfx": {},
		"voices": {},
	}))
	legacy_file = null
	var legacy_assets := WBAssetLibrary.new()
	_expect(legacy_assets.configure(legacy_path), "the presentation v2 reader retains predecessor v1 compatibility")
	_expect_equal(legacy_assets.manifest_version(), 1, "a predecessor manifest retains its declared version")
	legacy_assets.clear()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(legacy_path))
	assets.clear()


func _test_input_normalization() -> void:
	var contradictory := WBInputRouter.INPUT_LEFT | WBInputRouter.INPUT_RIGHT | WBInputRouter.INPUT_FIRE
	_expect_equal(
		WBInputRouter.normalize_mask(contradictory),
		WBInputRouter.INPUT_FIRE,
		"contradictory horizontal input resolves to neutral"
	)
	var vertical := (
		WBInputRouter.INPUT_UP
		| WBInputRouter.INPUT_DOWN
		| WBInputRouter.INPUT_SECONDARY
	)
	_expect_equal(
		WBInputRouter.normalize_mask(vertical),
		WBInputRouter.INPUT_SECONDARY,
		"contradictory vertical input resolves to neutral without dropping secondary"
	)
	_expect_equal(WBInputRouter.INPUT_UP, 64, "UP retains its protocol bit")
	_expect_equal(WBInputRouter.INPUT_DOWN, 128, "DOWN retains its protocol bit")
	_expect_equal(WBInputRouter.INPUT_SECONDARY, 256, "SECONDARY retains its protocol bit")
	var network_adapter := WBNetworkSessionAdapter.new()
	network_adapter._connections = [{"requested_seat": 1}]
	_expect_equal(
		network_adapter.local_seat_for_authoritative(1),
		0,
		"a remote client maps its authoritative player-two owner to local input seat zero"
	)
	_expect_equal(
		network_adapter.local_seat_for_authoritative(0),
		-1,
		"a remote client cannot submit pointer actions for an unowned authoritative seat"
	)
	var sequence_state := {"control_sequence": 1, "input_sequence": 1}
	_expect_equal(
		network_adapter._next_input_sequence(sequence_state),
		1,
		"unreliable input begins its own sequence stream"
	)
	_expect_equal(
		network_adapter._next_control_sequence(sequence_state),
		1,
		"reliable bonus commands are not skipped by input stream traffic"
	)


func _test_no_placeholder_renderer_source() -> void:
	var source := FileAccess.get_file_as_string("res://src/client/gameplay_renderer.gd")
	for forbidden in ["draw_circle(", "draw_colored_polygon(", "smiley", "smile face", "triangle ship"]:
		_expect(not source.to_lower().contains(forbidden), "gameplay renderer must not regain placeholder primitive: %s" % forbidden)
	_expect(
		source.contains(
			"_draw_enemies(arena, alpha)\n\t_draw_boss(arena, alpha)\n\t_draw_projectiles(arena, alpha)"
		),
		"boss parts render after ordinary enemies and before projectiles"
	)
	_expect_equal(WBInputRouter.seats_for_mode("solo"), 1, "solo owns one seat")
	_expect_equal(WBInputRouter.seats_for_mode("coop"), 2, "co-op owns two seats")
	var pause_has_p := false
	for event in InputMap.action_get_events("pause"):
		if event is InputEventKey and event.physical_keycode == KEY_P:
			pause_has_p = true
	_expect(pause_has_p, "original P pause key remains supported")
	var p1_uses_first_controller := false
	var p2_uses_second_controller := false
	for event in InputMap.action_get_events("p1_fire"):
		if event is InputEventJoypadButton and event.device == 0:
			p1_uses_first_controller = true
	for event in InputMap.action_get_events("p2_fire"):
		if event is InputEventJoypadButton and event.device == 1:
			p2_uses_second_controller = true
	_expect(
		p1_uses_first_controller and p2_uses_second_controller,
		"couch seats should use distinct controller devices"
	)


func _test_match_config() -> void:
	var profiles: Array = [
		{
			"id": "one",
			"name": "ONE",
			"mode_three_perfect_reward_index": 4,
			"best_hit_percent_above_level_25": 84,
			"best_score": 20000,
		},
		{"id": "two", "name": "TWO", "best_hit_percent_above_level_25": 150},
	]
	var config := WBMatchConfig.make("coop", "ace", "balanced", profiles, "pixel", 42)
	_expect(WBMatchConfig.validate(config), "valid co-op configuration is accepted")
	_expect_equal(int(config["seat_count"]), 2, "co-op config includes both seats")
	_expect_equal(str(config["difficulty"]), "ace", "difficulty is preserved")
	_expect_equal(int(config["seed"]), 42, "explicit deterministic seed is preserved")
	_expect_equal(int(config.content_version), 12, "new matches publish content contract version twelve")
	_expect_equal(
		int(config.seats[0].mode_three_perfect_reward_index),
		4,
		"profile mode-three progression is hydrated into its authoritative seat"
	)
	_expect_equal(
		int(config.seats[0].level_eight_perfect_reward_index),
		4,
		"the legacy level-eight seat alias remains synchronized"
	)
	_expect_equal(
		int(config.seats[0].best_hit_percent_above_level_25),
		84,
		"profile accuracy history is hydrated into its authoritative seat"
	)
	_expect_equal(
		int(config.seats[1].best_hit_percent_above_level_25),
		100,
		"match hydration clamps profile accuracy history to a percentage"
	)
	_expect(
		not bool(config.seats[0].only_blue_coins_active)
		and not bool(config.seats[1].only_blue_coins_active)
		and not bool(config.seats[0].rank_ready),
		"profile locks apply only to solo starts, so co-op seats stay unlocked"
	)
	var solo_lock_config := WBMatchConfig.make(
		"solo",
		"normal",
		"classic",
		[{"id": "one", "name": "ONE", "games_played": 20000}],
		"pixel",
		42
	)
	_expect(
		bool(solo_lock_config.seats[0].only_blue_coins_active),
		"the 20,000-games profile lock arms blue-only coins on solo starts"
	)
	_expect_equal(int(config.end_level), 3999, "new client matches default to the endless retail clamp")
	var invalid := config.duplicate(true)
	invalid["seat_count"] = 1
	_expect(not WBMatchConfig.validate(invalid), "mismatched seat ownership is rejected")
	invalid = config.duplicate(true)
	invalid["protocol_version"] = 2
	_expect(not WBMatchConfig.validate(invalid), "stale protocol configurations are rejected")
	invalid = config.duplicate(true)
	invalid["content_version"] = 5
	_expect(not WBMatchConfig.validate(invalid), "stale content configurations are rejected")
	invalid = config.duplicate(true)
	invalid["end_level"] = 4000
	_expect(not WBMatchConfig.validate(invalid), "client routes remain bounded to the retail level clamp")
	invalid = config.duplicate(true)
	invalid["end_level"] = 101
	_expect(WBMatchConfig.validate(invalid), "endless routes past level one hundred are valid")
	var explicit_ninety_nine := config.duplicate(true)
	explicit_ninety_nine.end_level = 99
	_expect(WBMatchConfig.validate(explicit_ninety_nine), "explicit level-ninety-nine boundaries remain valid")
	var explicit_seventy_five := config.duplicate(true)
	explicit_seventy_five.end_level = 75
	_expect(WBMatchConfig.validate(explicit_seventy_five), "explicit level-seventy-five boundaries remain valid")
	var explicit_fifty := config.duplicate(true)
	explicit_fifty.end_level = 50
	_expect(WBMatchConfig.validate(explicit_fifty), "explicit fifty-level compatibility matches remain valid")
	var explicit_forty_nine := config.duplicate(true)
	explicit_forty_nine.end_level = 49
	_expect(WBMatchConfig.validate(explicit_forty_nine), "explicit forty-nine-level compatibility matches remain valid")
	var explicit_thirty_five := config.duplicate(true)
	explicit_thirty_five.end_level = 35
	_expect(WBMatchConfig.validate(explicit_thirty_five), "explicit thirty-five-level compatibility matches remain valid")
	var explicit_thirty := config.duplicate(true)
	explicit_thirty.end_level = 30
	_expect(WBMatchConfig.validate(explicit_thirty), "explicit thirty-level compatibility matches remain valid")
	var explicit_twenty_five := config.duplicate(true)
	explicit_twenty_five.end_level = 25
	_expect(WBMatchConfig.validate(explicit_twenty_five), "explicit twenty-five-level compatibility matches remain valid")
	var explicit_twenty := config.duplicate(true)
	explicit_twenty.end_level = 20
	_expect(WBMatchConfig.validate(explicit_twenty), "explicit twenty-level compatibility matches remain valid")
	var explicit_ten := config.duplicate(true)
	explicit_ten.end_level = 10
	_expect(WBMatchConfig.validate(explicit_ten), "explicit ten-level compatibility matches remain valid")


func _test_settings_sanitization() -> void:
	var sanitized := WBSettingsStore.sanitize({
		"display_mode": "unsupported",
		"window_width": 20,
		"window_height": 99999,
		"render_cap": 73,
		"collision_mode": "forged",
		"master_volume": 4.0,
		"voice_volume": -2.0,
	})
	_expect_equal(str(sanitized["display_mode"]), "windowed", "unknown display mode falls back")
	_expect_equal(int(sanitized["window_width"]), 800, "window width is bounded")
	_expect_equal(int(sanitized["window_height"]), 4320, "window height is bounded")
	_expect_equal(int(sanitized["render_cap"]), 0, "unknown render cap falls back to unlimited")
	_expect_equal(str(sanitized["collision_mode"]), "pixel", "unknown collision mode falls back")
	_expect_equal(str(sanitized["effects_mode"]), "enhanced", "unknown effects mode falls back")
	_expect_equal(str(sanitized["texture_filter"]), "smooth", "unknown texture filter falls back")
	_expect(is_equal_approx(float(sanitized["master_volume"]), 1.0), "volume is clamped")
	_expect(is_equal_approx(float(sanitized["voice_volume"]), 0.0), "voice volume is clamped")
	_expect(
		is_equal_approx(float(WBSettingsStore.defaults()["voice_volume"]), 0.9),
		"voice volume has an explicit default"
	)
	var pack_sanitized := WBSettingsStore.sanitize({"voice_pack": 7, "background_brightness": 0.05})
	_expect_equal(int(pack_sanitized["voice_pack"]), 1, "unknown voice packs sanitize to pack 1")
	_expect(
		is_equal_approx(float(pack_sanitized["background_brightness"]), 0.25),
		"background brightness has a readability floor"
	)
	_expect_equal(
		int(WBSettingsStore.sanitize({"voice_pack": 2})["voice_pack"]),
		2,
		"pack 2 is a valid selection"
	)
	var lobby_defaults := WBSettingsStore.defaults()
	_expect_equal(str(lobby_defaults["lobby_host"]), WBSettingsStore.DEFAULT_LOBBY_HOST, "the lobby server defaults to the live droplet")
	_expect_equal(WBSettingsStore.DEFAULT_LOBBY_HOST, "68.183.194.133", "the live droplet address is baked in")
	_expect_equal(int(lobby_defaults["lobby_port"]), 7400, "the lobby server defaults to port 7400")
	_expect_equal(int(lobby_defaults["lobby_udp_port"]), 7401, "the rendezvous socket defaults to UDP 7401")
	_expect_equal(int(lobby_defaults["host_port"]), 42000, "hosting defaults to UDP 42000")
	_expect(bool(lobby_defaults["upnp_enabled"]), "UPnP is on by default")
	var lobby_sanitized := WBSettingsStore.sanitize({
		"lobby_host": "lobby example com",
		"lobby_port": 80,
		"lobby_udp_port": 70000,
		"host_port": "abc",
		"upnp_enabled": 0,
	})
	_expect_equal(str(lobby_sanitized["lobby_host"]), "", "hosts with whitespace are rejected")
	_expect_equal(int(lobby_sanitized["lobby_port"]), 7400, "privileged lobby ports fall back")
	_expect_equal(int(lobby_sanitized["lobby_udp_port"]), 7401, "out-of-range UDP ports fall back")
	_expect_equal(int(lobby_sanitized["host_port"]), 42000, "non-numeric host ports fall back")
	_expect(not bool(lobby_sanitized["upnp_enabled"]), "UPnP can be switched off")
	var configured := WBSettingsStore.sanitize({"lobby_host": "lobby.example.com", "lobby_port": 7500})
	var lobby_config := WBSettingsStore.lobby_config(configured)
	_expect_equal(str(lobby_config["host"]), "lobby.example.com", "the lobby config carries the host")
	_expect_equal(int(lobby_config["port"]), 7500, "the lobby config carries the port")
	_expect_equal(int(lobby_config["udp_port"]), 7401, "the lobby config carries the rendezvous port")
	_expect_equal(
		WBSettingsStore.describe_lobby(configured),
		"LOBBY SERVER lobby.example.com:7500",
		"the title footer names the lobby server"
	)
	_expect_equal(
		WBSettingsStore.describe_lobby(WBSettingsStore.sanitize({"lobby_host": ""})),
		"LOBBY SERVER NOT CONFIGURED",
		"an empty lobby address is called out instead of silently failing"
	)


func _test_settings_file_migration() -> void:
	var path := "user://test_settings_%d.json" % Time.get_ticks_usec()
	var legacy := FileAccess.open(path, FileAccess.WRITE)
	legacy.store_string(JSON.stringify({"version": 1, "lobby_host": "127.0.0.1", "lobby_port": 7500}))
	legacy = null
	var store := WBSettingsStore.new()
	store.configure_path(path)
	var loaded := store.load_settings()
	_expect_equal(str(loaded["lobby_host"]), WBSettingsStore.DEFAULT_LOBBY_HOST, "a version 1 file drops the loopback dev default")
	_expect_equal(int(loaded["lobby_port"]), 7500, "a version 1 file keeps its other lobby keys")
	_expect_equal(
		str(WBSettingsStore.read_raw(path)["lobby_host"]),
		WBSettingsStore.DEFAULT_LOBBY_HOST,
		"the raw reader applies the same migration"
	)
	_expect(store.save_and_apply(), "the migrated settings save")
	var saved := FileAccess.open(path, FileAccess.READ)
	var document: Variant = JSON.parse_string(saved.get_as_text())
	saved = null
	_expect(
		document is Dictionary and int((document as Dictionary).get("version", 0)) == WBSettingsStore.SETTINGS_VERSION,
		"saved settings carry the current schema version"
	)
	_expect_equal(
		str((document as Dictionary).get("lobby_host", "")),
		WBSettingsStore.DEFAULT_LOBBY_HOST,
		"the saved file stores the live address"
	)
	var current := FileAccess.open(path, FileAccess.WRITE)
	current.store_string(JSON.stringify({"version": 2, "lobby_host": "127.0.0.1"}))
	current = null
	var reloaded := WBSettingsStore.new()
	reloaded.configure_path(path)
	_expect_equal(
		str(reloaded.load_settings()["lobby_host"]),
		"127.0.0.1",
		"a current file keeps a deliberately configured loopback host"
	)
	var custom := FileAccess.open(path, FileAccess.WRITE)
	custom.store_string(JSON.stringify({"version": 1, "lobby_host": "lobby.example.com"}))
	custom = null
	_expect_equal(
		str(WBSettingsStore.read_raw(path)["lobby_host"]),
		"lobby.example.com",
		"a version 1 file keeps a custom host"
	)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _test_sprite_pack_override() -> void:
	var pack_name := "test_pack_%d" % Time.get_ticks_usec()
	var pack_dir := "user://packs/%s" % pack_name
	var textures_dir := "%s/textures" % pack_dir
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(textures_dir))
	var override_image := Image.create_empty(576, 96, false, Image.FORMAT_RGBA8)
	override_image.fill(Color(1.0, 0.0, 1.0, 1.0))
	_expect_equal(
		override_image.save_png(ProjectSettings.globalize_path("%s/alien001.png" % textures_dir)),
		OK,
		"the test pack override image saves"
	)
	var wrong_size := Image.create_empty(10, 10, false, Image.FORMAT_RGBA8)
	wrong_size.fill(Color(0.0, 1.0, 0.0, 1.0))
	wrong_size.save_png(ProjectSettings.globalize_path("%s/fighter1.png" % textures_dir))
	var manifest_file := FileAccess.open("%s/pack.json" % pack_dir, FileAccess.WRITE)
	manifest_file.store_string(JSON.stringify({
		"version": 1,
		"schema": "warblade.sprite-pack.v1",
		"name": pack_name,
		"textures": {
			"alien001": {"path": "textures/alien001.png", "width": 576, "height": 96},
			"fighter1": {"path": "textures/fighter1.png", "width": 440, "height": 28},
			"not_a_retail_key": {"path": "textures/alien001.png", "width": 576, "height": 96},
		},
	}))
	manifest_file = null
	_expect(
		not WBAssetLibrary.set_active_pack("missing_pack_%d" % Time.get_ticks_usec()),
		"selecting a missing sprite pack fails and clears the active pack"
	)
	_expect(WBAssetLibrary.set_active_pack(pack_name), "the test sprite pack activates")
	_expect_equal(WBAssetLibrary.active_pack_name(), pack_name, "the active pack reports its name")
	_expect(
		WBAssetLibrary.available_packs().has(pack_name),
		"pack discovery lists user://packs entries"
	)
	var assets := WBAssetLibrary.new()
	var overridden := assets.texture("alien001")
	_expect(overridden != null, "the pack override resolves through texture()")
	if overridden != null:
		_expect_equal(overridden.get_width(), 576, "the override keeps the retail sheet width")
		_expect(
			overridden.get_image().get_pixel(0, 0).is_equal_approx(Color(1.0, 0.0, 1.0, 1.0)),
			"the resolved texture carries the pack's pixels"
		)
	var fallback := assets.texture("fighter1")
	_expect(fallback != null, "a wrong-size pack entry falls back to retail art")
	if fallback != null:
		_expect_equal(fallback.get_width(), 440, "the fallback texture is the retail sheet")
	var report := assets.validate_pack()
	_expect(not bool(report.get("ok", true)), "pack validation reports broken entries")
	_expect_equal(int(report.get("overridden", 0)), 1, "pack validation counts working overrides")
	_expect_equal(
		(report.get("errors", []) as Array).size(),
		2,
		"pack validation names each broken entry exactly once"
	)
	_expect_equal(
		str(WBSettingsStore.sanitize({"sprite_pack": "Bad Name!"})["sprite_pack"]),
		"",
		"invalid sprite pack names sanitize to retail"
	)
	_expect_equal(
		str(WBSettingsStore.sanitize({"sprite_pack": "Solstice"})["sprite_pack"]),
		"solstice",
		"sprite pack names sanitize to lower case"
	)
	assets.clear()
	WBAssetLibrary.set_active_pack("")
	_expect_equal(WBAssetLibrary.active_pack_name(), "", "clearing the pack resets static state")
	for file_name in ["textures/alien001.png", "textures/fighter1.png", "pack.json"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path("%s/%s" % [pack_dir, file_name]))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(textures_dir))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(pack_dir))


func _test_jukebox_store() -> void:
	var sanitized := WBJukeboxStore.sanitize({
		"slots": {
			"shop": {"source": "builtin", "key": "BOSS"},
			"boss": {"source": "user", "path": "/tmp/custom.mp3"},
			"bogus": {"source": "builtin", "key": "gems"},
			"title": {"source": "user", "path": "/tmp/evil.exe"},
		},
		"main_playlist": [
			{"source": "builtin", "key": "gems"},
			{"source": "user", "path": "/tmp/song.ogg"},
			{"source": "user", "path": "not-audio.txt"},
		],
		"main_playlist_enabled": true,
	})
	var slots: Dictionary = sanitized["slots"]
	_expect_equal(slots.size(), 2, "unknown slots and non-audio user paths are dropped")
	_expect_equal(
		str((slots["shop"] as Dictionary).get("key", "")),
		"boss",
		"builtin slot keys normalize to lower case"
	)
	_expect_equal(
		str((slots["boss"] as Dictionary).get("path", "")),
		"/tmp/custom.mp3",
		"user slot paths are preserved"
	)
	_expect_equal((sanitized["main_playlist"] as Array).size(), 2, "invalid playlist entries are dropped")
	_expect(bool(sanitized["main_playlist_enabled"]), "playlist stays enabled with valid entries")
	_expect(
		not bool(WBJukeboxStore.sanitize({"main_playlist_enabled": true})["main_playlist_enabled"]),
		"an empty playlist cannot be enabled"
	)
	var store := WBJukeboxStore.new()
	store.configure(sanitized)
	var shop_override := store.override_for_music_key("shop")
	_expect_equal(str(shop_override.get("kind", "")), "builtin", "shop slot resolves its override")
	_expect(store.override_for_music_key("memory").is_empty(), "unconfigured slots resolve empty")
	_expect_equal(
		WBJukeboxStore.slot_for_music_key("warblade"),
		"main",
		"the gameplay music key belongs to the Main slot"
	)
	_expect_equal(
		str(store.override_for_music_key("warblade").get("kind", "")),
		"playlist",
		"the Main slot resolves the enabled playlist"
	)


func _test_input_remap() -> void:
	var sanitized := WBSettingsStore.sanitize_input_bindings({
		"p1_left": [{"type": "key", "physical_keycode": KEY_J}],
		"p1_fire": [
			{"type": "joy_button", "button_index": 0, "device": -1},
			{"type": "key", "physical_keycode": 0},
		],
		"ui_accept": [{"type": "key", "physical_keycode": KEY_K}],
		"p2_fire": "garbage",
	})
	_expect_equal(sanitized.size(), 2, "unknown actions and invalid payloads are dropped")
	_expect_equal(
		(sanitized["p1_fire"] as Array).size(),
		1,
		"invalid events inside an action are dropped"
	)
	WBSettingsStore.apply_input_bindings(sanitized)
	var remapped := InputMap.action_get_events("p1_left")
	_expect_equal(remapped.size(), 1, "remapped action carries exactly the custom event")
	_expect(
		remapped[0] is InputEventKey
		and (remapped[0] as InputEventKey).physical_keycode == KEY_J,
		"remapped p1_left uses the custom key"
	)
	var default_up := InputMap.action_get_events("p1_up")
	_expect(not default_up.is_empty(), "untouched actions keep their project defaults")
	WBSettingsStore.apply_input_bindings({})
	var restored := InputMap.action_get_events("p1_left")
	_expect(
		not restored.is_empty()
		and not (
			restored[0] is InputEventKey
			and (restored[0] as InputEventKey).physical_keycode == KEY_J
		),
		"clearing bindings restores project defaults"
	)
	_expect(
		WBSettingsStore.make_input_event({"type": "key", "physical_keycode": 0}) == null,
		"zero keycodes produce no event"
	)
	_expect_equal(
		WBSettingsStore.describe_input_event({"type": "joy_button", "button_index": 0, "device": -1}),
		WBSettingsStore.make_input_event(
			{"type": "joy_button", "button_index": 0, "device": -1}
		).as_text(),
		"joypad bindings describe through as_text"
	)


func _test_hiscore_store() -> void:
	var store := WBHiscoreStore.new()
	var path := "user://test_hiscores_%d.json" % Time.get_ticks_usec()
	store.configure_path(path)
	store.load_tables()
	var result := {
		"tick": 7200,
		"level_reached": 12,
		"tally_by_seat": [
			{"total_score": 50000, "rank_index": 2, "hit_percent": 66},
			{},
		],
		"profile_stats": [
			{
				"projectile_objects_fired": 300,
				"successful_hits": 200,
				"meteor_score": 4200,
			},
			{},
		],
	}
	_expect(
		store.record_result(result, "solo", "hard", ["ONE"]),
		"hiscore recording persists"
	)
	var hard_table := store.table("hard")
	_expect_equal(hard_table.size(), 1, "the difficulty table receives the total")
	_expect_equal(
		int((hard_table[0] as Dictionary).get("score", 0)),
		50000,
		"the hall of fame stores the end-of-game total"
	)
	_expect_equal(
		store.table("meteorstorm").size(),
		1,
		"non-zero meteor scores enter the Meteor Storm table"
	)
	for extra in range(25):
		store.record_result({
			"tick": 100,
			"level_reached": 2,
			"tally_by_seat": [{"total_score": 100 + extra, "rank_index": 0, "hit_percent": 1}],
			"profile_stats": [{}],
		}, "solo", "hard", ["FILLER"])
	_expect_equal(
		store.table("hard").size(),
		WBHiscoreStore.MAX_ENTRIES,
		"tables trim to the retail twenty entries"
	)
	var reloaded := WBHiscoreStore.new()
	reloaded.configure_path(path)
	reloaded.load_tables()
	_expect_equal(
		int((reloaded.table("hard")[0] as Dictionary).get("score", 0)),
		50000,
		"hiscores survive a reload sorted"
	)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _test_manual_decode() -> void:
	var text := WBAppShell._load_manual_text()
	_expect(text.length() > 10000, "the extracted manual decodes to full length")
	_expect(not text.contains("\r"), "the viewer strips carriage returns")
	_expect(
		text.containsn("warblade"),
		"the manual mentions the game by name"
	)


func _test_profile_management() -> void:
	var store := WBProfileStore.new()
	var path := "user://test_profiles_%d.json" % Time.get_ticks_usec()
	store.configure_path(path)
	store.load_profiles()
	var created := store.add_profile("SECOND")
	_expect(not created.is_empty(), "a second profile is created")
	var created_id := str(created.get("id", ""))
	_expect(store.rename_profile(created_id, "renamed"), "profiles rename")
	var renamed_name := ""
	for profile in store.profiles():
		if str(profile.get("id", "")) == created_id:
			renamed_name = str(profile.get("name", ""))
	_expect_equal(renamed_name, "RENAMED", "rename uppercases and persists")
	_expect(
		store.record_result([created_id], {
			"completed": false,
			"level_id": 9,
			"level_reached": 9,
			"score": 1234,
			"money": 555,
			"tick": 3600,
			"profile_stats": [{
				"projectile_objects_fired": 50,
				"successful_hits": 25,
				"fastest_level_clear_ticks": 400,
			}],
			"seat_progression": [{
				"highest_rank": 3,
				"secret_session_seen": [1, 0, 1],
			}],
		}),
		"results accumulate the retail statistics"
	)
	var recorded: Dictionary = {}
	for profile in store.profiles():
		if str(profile.get("id", "")) == created_id:
			recorded = profile
	_expect_equal(int(recorded.get("games_played", 0)), 1, "games played increments")
	_expect_equal(int(recorded.get("levels_played_total", 0)), 9, "levels accumulate")
	_expect_equal(int(recorded.get("highest_money", 0)), 555, "highest money records")
	_expect_equal(int(recorded.get("total_shots", 0)), 50, "shots accumulate")
	_expect_equal(int(recorded.get("highest_rank", 0)), 3, "highest rank persists")
	_expect_equal(
		int(recorded.get("secrets_seen", 0)),
		0b101,
		"secrets seen union the session flags"
	)
	_expect_equal(
		int(recorded.get("fastest_level_clear_ticks", 0)),
		400,
		"the fastest clear records"
	)
	_expect(store.reset_profile_statistics(created_id), "statistics reset")
	for profile in store.profiles():
		if str(profile.get("id", "")) == created_id:
			_expect_equal(
				int(profile.get("games_played", 0)),
				0,
				"reset clears cumulative statistics"
			)
	_expect(store.remove_profile(created_id), "profiles delete")
	_expect_equal(store.profiles().size(), 1, "deletion removes the profile")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _test_sidecar_suspend_grace() -> void:
	_expect(
		not AppBootstrap.heartbeat_callback_needs_grace(1000, 2000),
		"normal heartbeat timer cadence should not be treated as a suspend"
	)
	_expect(
		AppBootstrap.heartbeat_callback_needs_grace(1000, 11_000),
		"a sleep-sized callback gap should grant the parent time to refresh its heartbeat"
	)


## The match no longer rides process arguments: every game server, local test
## sidecar or online, is configured through the canonical HELLO match request.
func _test_network_match_contract() -> void:
	var default_contract := WBMatchContract.network_contract({})
	_expect_equal(
		int(default_contract.end_level),
		3999,
		"the network contract defaults to the endless retail clamp boundary"
	)
	_expect_equal(default_contract.seats.size(), 1, "a default contract is a one-seat solo match")
	var config := {
		"mode": "coop",
		"difficulty": "hard",
		"coop_balance": "balanced",
		"collision_mode": "pixel",
		"seed": 3_000_000_000_000_000_001,
		"start_level": 16,
		"end_level": 20,
		"starting_rockets": 99,
		"seats": [
			{
				"seat": 0,
				"profile_id": "pilot_one",
				"display_name": "PILOT ONE",
				"mode_three_perfect_reward_index": 7,
				"best_hit_percent_above_level_25": 84,
				"rank_ready": true,
				"only_blue_coins_active": true,
				"start_state": {
					"money": 500,
					"weapon_at_least": 2,
					"auto_fire": true,
					"excluded_bonus_types": [13, 12],
					"forged_field": 99,
				},
				"secret_session_earned": [1, 0, 1],
			},
			{
				"seat": 1,
				"mode_three_perfect_reward_index": 99,
				"best_hit_percent_above_level_25": 999,
			},
		],
	}
	var contract := WBMatchContract.network_contract(config)
	_expect_equal(int(contract.end_level), 20, "the contract keeps the level-twenty boundary")
	_expect_equal(int(contract.starting_rockets), 50, "the contract clamps the starting Rocket Pack inventory")
	_expect_equal(contract.seats.size(), 2, "a co-op contract carries both seats")
	_expect_equal(int(contract.seats[0].mode_three_perfect_reward_index), 7, "P1's mode-three chain rides the contract")
	_expect_equal(int(contract.seats[1].mode_three_perfect_reward_index), 9, "P2's mode-three chain is bounded")
	_expect_equal(int(contract.seats[1].level_eight_perfect_reward_index), 9, "the legacy chain alias stays synchronized")
	_expect_equal(int(contract.seats[0].best_hit_percent_above_level_25), 84, "P1's profile accuracy rides the contract")
	_expect_equal(int(contract.seats[1].best_hit_percent_above_level_25), 100, "P2's profile accuracy is clamped")
	_expect(
		bool(contract.seats[0].rank_ready) and bool(contract.seats[0].only_blue_coins_active),
		"both bounded state-13 progression inputs ride the contract"
	)
	_expect(
		not (contract.seats[0] as Dictionary).has("display_name"),
		"presentation-only seat fields never reach the wire"
	)
	var start_state: Dictionary = contract.seats[0].start_state
	_expect_equal(int(start_state.get("money", 0)), 500, "profile-lock start money rides the contract")
	_expect_equal(int(start_state.get("weapon_at_least", 0)), 2, "profile-lock weapons ride the contract")
	_expect(bool(start_state.get("auto_fire", false)), "profile-lock auto fire rides the contract")
	_expect_equal(
		start_state.get("excluded_bonus_types", []),
		[12, 13],
		"excluded bonus types are normalized in sorted order"
	)
	_expect(
		not start_state.has("forged_field"),
		"unknown start-state fields are dropped before they can reach the simulation"
	)
	var expected_secrets: Array = [1, 0, 1]
	while expected_secrets.size() < 30:
		expected_secrets.append(0)
	_expect_equal(
		contract.seats[0].secret_session_earned,
		expected_secrets,
		"the 30-entry secret flags are padded exactly"
	)
	_expect_equal(str(contract.seed), "3000000000000000001", "64-bit seeds ride as lossless strings")

	# The request must survive its JSON wire trip bit-identically, including
	# float64 coercion of every small integer, or join-equality would fail.
	var request := WBMatchContract.network_match_request(config)
	var parsed: Dictionary = JSON.parse_string(JSON.stringify(request))
	var normalized := WBMatchContract.network_contract(parsed.get("contract", {}))
	_expect(
		normalized == contract,
		"the contract normalizer is idempotent across the JSON wire boundary"
	)
	_expect_equal(int(request.resume_slot), -1, "a fresh match requests no resume slot")
	_expect_equal(
		int(WBMatchContract.network_match_request({"resume_slot": 2}).resume_slot),
		2,
		"a resumed match carries its numbered slot beside the contract"
	)
	var expanded := WBMatchContract.config_from_network_contract(contract)
	_expect_equal(int(expanded.protocol_version), 8, "the server expands its own protocol version")
	_expect_equal(int(expanded.content_version), 12, "the server expands its own content version")
	_expect_equal(int(expanded.seed), 3_000_000_000_000_000_001, "the seed expands back to its integer")
	_expect_equal(int(expanded.seat_count), 2, "the seat count derives from the mode")
	_expect_equal(
		WBMatchContract.seat_count_for_mode("time_trial"),
		1,
		"Time Trial is single seat like solo"
	)


func _test_profile_persistence() -> void:
	var path := "user://warblade_client_test_%d.json" % Time.get_ticks_usec()
	var store := WBProfileStore.new()
	store.configure_path(path)
	var initial := store.load_profiles()
	_expect_equal(initial.size(), 1, "profile store creates one initial pilot")
	var created := store.add_profile("test pilot")
	_expect_equal(str(created.get("name", "")), "TEST PILOT", "profile names are normalized")
	_expect_equal(int(created.get("best_meteor_score", -1)), 0, "new v4 profiles initialize Meteor history")
	_expect_equal(int(created.get("bonus_rounds_total", -1)), 0, "new v4 profiles initialize bonus-round totals")
	_expect_equal(int(created.get("perfect_bonus_rounds", -1)), 0, "new v4 profiles initialize perfect totals")
	_expect_equal(int(created.get("mode_three_perfect_reward_index", -1)), 0, "new v4 profiles initialize the mode-three perfect chain")
	_expect_equal(int(created.get("level_eight_perfect_reward_index", -1)), 0, "new v4 profiles initialize the level-8 perfect chain")
	_expect_equal(int(created.get("best_hit_percent_above_level_25", -1)), 0, "new v4 profiles initialize level-25 accuracy history")
	_expect_equal(int(created.get("best_level_100_score", -1)), 0, "new v4 profiles initialize the level-100 score best")
	store.record_result([str(created.id)], {
		"completed": true,
		"level_id": 10,
		"score": 1234,
		"mode": "solo",
		"difficulty": "normal",
		"profile_stats": [{
			"meteor_score": 875,
			"bonus_rounds": 2,
			"perfect_bonus_rounds": 1,
			"mode_three_perfect_reward_index": 3,
			"best_hit_percent_above_level_25": 72,
		}],
	})
	var stored_document: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	_expect_equal(int(stored_document.get("version", 0)), 5, "profile persistence writes schema version five")
	var loaded := WBProfileStore.new()
	loaded.configure_path(path)
	var loaded_profiles := loaded.load_profiles()
	_expect_equal(loaded_profiles.size(), 2, "profiles persist locally")
	var loaded_created: Dictionary = loaded_profiles.filter(
		func(profile: Dictionary) -> bool: return str(profile.id) == str(created.id)
	)[0]
	_expect_equal(int(loaded_created.best_meteor_score), 875, "Meteor best score persists")
	_expect_equal(int(loaded_created.bonus_rounds_total), 2, "bonus-round totals persist")
	_expect_equal(int(loaded_created.perfect_bonus_rounds), 1, "perfect totals persist")
	_expect_equal(int(loaded_created.mode_three_perfect_reward_index), 3, "mode-three perfect reward chain persists")
	_expect_equal(int(loaded_created.level_eight_perfect_reward_index), 3, "level-8 perfect reward chain persists")
	_expect_equal(int(loaded_created.best_hit_percent_above_level_25), 72, "level-25 accuracy history persists")
	loaded.record_result([str(created.id), str(created.id)], {
		"completed": false,
		"level_id": 8,
		"score": 500,
		"mode": "coop",
		"difficulty": "normal",
		"profile_stats": [
			{"meteor_score": 125, "bonus_rounds": 1, "perfect_bonus_rounds": 0, "level_eight_perfect_reward_index": 2, "best_hit_percent_above_level_25": 65},
			{"meteor_score": 250, "bonus_rounds": 2, "perfect_bonus_rounds": 1, "mode_three_perfect_reward_index": 5, "best_hit_percent_above_level_25": 89},
		],
	})
	var aggregated_profile: Dictionary = loaded.profiles().filter(
		func(profile: Dictionary) -> bool: return str(profile.id) == str(created.id)
	)[0]
	_expect_equal(int(aggregated_profile.best_meteor_score), 875, "duplicate-seat ownership preserves the best per-seat Meteor round")
	_expect_equal(int(aggregated_profile.bonus_rounds_total), 5, "duplicate profile seats aggregate all owned bonus rounds")
	_expect_equal(int(aggregated_profile.perfect_bonus_rounds), 2, "duplicate profile seats aggregate all perfect rounds")
	_expect_equal(int(aggregated_profile.mode_three_perfect_reward_index), 5, "duplicate profile seats preserve the furthest canonical perfect chain")
	_expect_equal(int(aggregated_profile.level_eight_perfect_reward_index), 5, "duplicate profile seats preserve the furthest perfect chain")
	_expect_equal(int(aggregated_profile.best_hit_percent_above_level_25), 89, "duplicate profile seats preserve the best accuracy")
	loaded.record_result([str(created.id)], {
		"completed": false,
		"level_id": 16,
		"score": 0,
		"mode": "solo",
		"difficulty": "normal",
		"profile_stats": [{
			"mode_three_perfect_reward_index": 0,
			"level_eight_perfect_reward_index": 0,
			"best_hit_percent_above_level_25": 20,
		}],
	})
	var reset_profile: Dictionary = loaded.profiles().filter(
		func(profile: Dictionary) -> bool: return str(profile.id) == str(created.id)
	)[0]
	_expect_equal(
		int(reset_profile.mode_three_perfect_reward_index),
		0,
		"an authoritative mode-three miss persists a canonical chain reset"
	)
	_expect_equal(
		int(reset_profile.level_eight_perfect_reward_index),
		0,
		"an authoritative mode-three miss keeps the legacy chain alias reset"
	)
	_expect_equal(
		int(reset_profile.best_hit_percent_above_level_25),
		89,
		"later results cannot lower the persisted best accuracy"
	)
	_expect_equal(int(reset_profile.best_level_100_score), 0, "short runs cannot populate the level-100 score best")
	loaded.record_result([str(created.id)], {
		"completed": true,
		"level_id": 100,
		"score": 11111,
		"mode": "solo",
		"difficulty": "normal",
		"campaign_terminal": {
			"kind": "level_100",
			"full_campaign_completed": true,
			"credits_required": true,
			"ending_mode_id": 0,
			"winner_seat_id": -1,
			"level_100_score": 54321,
		},
	})
	var level_100_profile: Dictionary = loaded.profiles().filter(
		func(profile: Dictionary) -> bool: return str(profile.id) == str(created.id)
	)[0]
	_expect_equal(
		int(level_100_profile.best_level_100_score),
		54321,
		"full-campaign completion records the authoritative level-100 score"
	)
	loaded.record_result([str(created.id)], {
		"completed": true,
		"level_id": 100,
		"score": 9000,
		"campaign_terminal": {
			"kind": "level_100",
			"full_campaign_completed": true,
			"credits_required": true,
			"level_100_score": 12345,
		},
	})
	level_100_profile = loaded.profiles().filter(
		func(profile: Dictionary) -> bool: return str(profile.id) == str(created.id)
	)[0]
	_expect_equal(
		int(level_100_profile.best_level_100_score),
		54321,
		"later completions cannot lower the authoritative level-100 score best"
	)

	var canonical_before_failed_publication := FileAccess.get_file_as_string(path)
	var rejecting_store := RejectingProfileStore.new()
	rejecting_store.configure_path(path)
	var rejecting_profiles: Array[Dictionary] = rejecting_store.load_profiles()
	var rejecting_created: Dictionary = rejecting_profiles.filter(
		func(profile: Dictionary) -> bool: return str(profile.id) == str(created.id)
	)[0]
	var history_before_retry := int((rejecting_created.get("history", []) as Array).size())
	var retry_result := {
		"completed": true,
		"level_id": 100,
		"score": 99999,
		"mode": "solo",
		"difficulty": "normal",
	}
	_expect(
		not rejecting_store.record_result([str(created.id)], retry_result),
		"a failed atomic publication reports persistence failure"
	)
	_expect_equal(
		FileAccess.get_file_as_string(path),
		canonical_before_failed_publication,
		"failed publication leaves the prior canonical profile byte-for-byte intact"
	)
	var canonical_absolute_path := ProjectSettings.globalize_path(path)
	var profile_directory := DirAccess.open(canonical_absolute_path.get_base_dir())
	var temporary_prefix := ".%s." % canonical_absolute_path.get_file()
	var leftover_temporaries: Array[String] = []
	if profile_directory != null:
		for file_name in profile_directory.get_files():
			if file_name.begins_with(temporary_prefix) and file_name.ends_with(".tmp"):
				leftover_temporaries.append(file_name)
	_expect(
		leftover_temporaries.is_empty(),
		"failed publication cleans up its sibling temporary file"
	)
	var rejected_created: Dictionary = rejecting_store.profiles().filter(
		func(profile: Dictionary) -> bool: return str(profile.id) == str(created.id)
	)[0]
	_expect_equal(
		int((rejected_created.get("history", []) as Array).size()),
		history_before_retry,
		"failed publication rolls in-memory history back for a safe retry"
	)
	_expect(
		rejecting_store.last_save_error.contains("publish"),
		"profile publication failures retain a useful persistence error"
	)
	var retry_store := WBProfileStore.new()
	retry_store.configure_path(path)
	retry_store.load_profiles()
	_expect(
		retry_store.record_result([str(created.id)], retry_result),
		"the same authoritative result can be retried successfully"
	)
	var retried_created: Dictionary = retry_store.profiles().filter(
		func(profile: Dictionary) -> bool: return str(profile.id) == str(created.id)
	)[0]
	_expect_equal(
		int((retried_created.get("history", []) as Array).size()),
		history_before_retry + 1,
		"a failed attempt followed by a successful retry appends history exactly once"
	)
	_expect_equal(
		int(retried_created.get("best_score", 0)),
		99999,
		"successful atomic publication updates the canonical profile"
	)

	var legacy_path := "user://warblade_client_legacy_test_%d.json" % Time.get_ticks_usec()
	var legacy_file := FileAccess.open(legacy_path, FileAccess.WRITE)
	legacy_file.store_string(JSON.stringify({
		"version": 1,
		"profiles": [{
			"id": "legacy-pilot",
			"name": "LEGACY",
			"best_score": 77,
			"history": [],
		}, {
			"id": "legacy-chain",
			"name": "LEGACY CHAIN",
			"level_eight_perfect_reward_index": 6,
			"history": [],
		}, {
			"id": "legacy-accuracy",
			"name": "LEGACY ACCURACY",
			"best_hit_percent_above_level_25": 999,
			"history": [],
		}, {
			"id": "legacy-negative-accuracy",
			"name": "LEGACY NEGATIVE",
			"best_hit_percent_above_level_25": -9,
			"history": [],
		}],
	}))
	legacy_file = null
	var migrated := WBProfileStore.new()
	migrated.configure_path(legacy_path)
	var migrated_profile: Dictionary = migrated.load_profiles()[0]
	_expect_equal(int(migrated_profile.best_score), 77, "v1 profile score survives additive migration")
	_expect_equal(int(migrated_profile.best_meteor_score), 0, "v1 profile gains a zero Meteor best")
	_expect_equal(int(migrated_profile.bonus_rounds_total), 0, "v1 profile gains a zero bonus total")
	_expect_equal(int(migrated_profile.perfect_bonus_rounds), 0, "v1 profile gains a zero perfect total")
	_expect_equal(int(migrated_profile.mode_three_perfect_reward_index), 0, "v1 profile gains a zero mode-three chain")
	_expect_equal(int(migrated_profile.level_eight_perfect_reward_index), 0, "v1 profile gains a zero level-8 chain")
	_expect_equal(int(migrated_profile.best_hit_percent_above_level_25), 0, "v1 profile gains a zero level-25 accuracy best")
	_expect_equal(int(migrated_profile.best_level_100_score), 0, "v1 profile gains a zero level-100 score best")
	var migrated_legacy_chain: Dictionary = migrated.profiles().filter(
		func(profile: Dictionary) -> bool: return str(profile.id) == "legacy-chain"
	)[0]
	_expect_equal(int(migrated_legacy_chain.mode_three_perfect_reward_index), 6, "legacy-only chains hydrate the canonical profile field")
	_expect_equal(int(migrated_legacy_chain.level_eight_perfect_reward_index), 6, "legacy-only chains retain their compatibility field")
	var migrated_legacy_accuracy: Dictionary = migrated.profiles().filter(
		func(profile: Dictionary) -> bool: return str(profile.id) == "legacy-accuracy"
	)[0]
	_expect_equal(int(migrated_legacy_accuracy.best_hit_percent_above_level_25), 100, "migrated profile accuracy is clamped to one hundred")
	var migrated_negative_accuracy: Dictionary = migrated.profiles().filter(
		func(profile: Dictionary) -> bool: return str(profile.id) == "legacy-negative-accuracy"
	)[0]
	_expect_equal(int(migrated_negative_accuracy.best_hit_percent_above_level_25), 0, "migrated profile accuracy is clamped to zero")
	var migrated_document: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string(legacy_path)
	)
	_expect_equal(
		int(migrated_document.get("version", 0)),
		WBProfileStore.PROFILE_VERSION,
		"loading a legacy profile persists the additive schema-v4 migration"
	)
	var migrated_profiles: Array = migrated_document.get("profiles", [])
	var persisted_legacy_accuracy: Array = migrated_profiles.filter(
		func(profile: Dictionary) -> bool:
			return str(profile.get("id", "")) == "legacy-accuracy"
	)
	_expect(
		persisted_legacy_accuracy.size() == 1
		and int(persisted_legacy_accuracy[0].get(
			"best_hit_percent_above_level_25",
			-1
		)) == 100,
		"the persisted v4 migration includes the clamped accuracy field"
	)
	var v3_path := "user://warblade_client_v3_test_%d.json" % Time.get_ticks_usec()
	var v3_file := FileAccess.open(v3_path, FileAccess.WRITE)
	v3_file.store_string(JSON.stringify({
		"version": 3,
		"profiles": [{
			"id": "v3-pilot",
			"name": "V3 PILOT",
			"best_score": 8765,
			"best_meteor_score": 400,
			"bonus_rounds_total": 7,
			"perfect_bonus_rounds": 3,
			"mode_three_perfect_reward_index": 5,
			"level_eight_perfect_reward_index": 5,
			"best_hit_percent_above_level_25": 88,
			"history": [],
		}],
	}))
	v3_file = null
	var migrated_v3 := WBProfileStore.new()
	migrated_v3.configure_path(v3_path)
	var migrated_v3_profile: Dictionary = migrated_v3.load_profiles()[0]
	_expect_equal(int(migrated_v3_profile.best_score), 8765, "v3 migration preserves existing best score")
	_expect_equal(int(migrated_v3_profile.best_level_100_score), 0, "v3 migration adds a zero level-100 best")
	var migrated_v3_document: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string(v3_path)
	)
	_expect_equal(int(migrated_v3_document.get("version", 0)), 5, "v3 profiles are rewritten at the current schema")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(legacy_path))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(v3_path))


func _test_ending_presentation() -> void:
	var assets := WBAssetLibrary.new()
	var slides: Array[Dictionary] = []
	for index in range(WBEndingPresentation.REQUIRED_SLIDE_COUNT):
		slides.append({"texture": "stars1", "duration_seconds": 0.1})
	var contract := {
		"slides": slides,
		"story_text": "EXACT STORY",
		"credits_text": "EXACT CREDITS",
		"scroll_pixels_per_second": 30.0,
		"accelerated_multiplier": 8.0,
		"loop": false,
		"music": "endgame",
		"controls": {
			"left_mouse": "LEFT MOUSEBUTTON TO PAUSE",
			"right_mouse": "RIGHT MOUSEBUTTON TO SPEED UP",
			"continue": "ESC, SPACE OR FIRE TO CONTINUE",
		},
		"modes": {
			"0": {
				"title": "MISSION COMPLETE",
				"text": "NORMAL ENDING",
				"fireworks": true,
			},
		},
		"evidence": {
			"text_loop": true,
			"instruction_overlay_duration_ms": 8000,
		},
	}
	var ending := WBEndingPresentation.new()
	ending.size = Vector2(800.0, 600.0)
	root.add_child(ending)
	await process_frame
	_expect(
		ending.configure(
			assets,
			contract,
			{"ending_mode_id": 0, "winner_seat_id": -1}
		),
		"the ending presenter accepts the exact thirteen-slide contract"
	)
	_expect_equal(ending.music_key(), "endgame", "credits select the recovered endgame track")
	_expect_equal(
		ending._scroll_label.text,
		"EXACT STORYEXACT CREDITS",
		"mode metadata never rewrites the authored story and credits scroll"
	)
	ending.start()
	var initial_scroll := ending.scroll_position()
	ending.advance_for_test(0.25)
	_expect_equal(ending.current_slide_index(), 2, "credits advance through timed slides in authored order")
	_expect(
		is_equal_approx(ending.scroll_position(), initial_scroll - 7.5),
		"credits scroll at the executable-backed nominal rate"
	)
	var left_press := InputEventMouseButton.new()
	left_press.button_index = MOUSE_BUTTON_LEFT
	left_press.pressed = true
	_expect(ending.handle_input(left_press), "left-click is consumed by active credits")
	_expect(ending.is_paused(), "left-click pauses credits")
	var paused_scroll := ending.scroll_position()
	ending.advance_for_test(1.0)
	_expect(
		is_equal_approx(ending.scroll_position(), paused_scroll),
		"holding left mouse pauses the credits text"
	)
	_expect_equal(
		ending.current_slide_index(),
		12,
		"the retail slide clock continues while the text is paused"
	)
	var left_release := InputEventMouseButton.new()
	left_release.button_index = MOUSE_BUTTON_LEFT
	left_release.pressed = false
	ending.handle_input(left_release)
	_expect(not ending.is_paused(), "releasing left mouse resumes the credits text")
	var right_press := InputEventMouseButton.new()
	right_press.button_index = MOUSE_BUTTON_RIGHT
	right_press.pressed = true
	ending.handle_input(right_press)
	_expect(ending.is_accelerated(), "holding right mouse enables retail acceleration")
	var accelerated_scroll := ending.scroll_position()
	ending.advance_for_test(0.25)
	_expect(
		is_equal_approx(ending.scroll_position(), accelerated_scroll - 60.0),
		"right mouse applies the executable-backed eight-times multiplier"
	)
	var right_release := InputEventMouseButton.new()
	right_release.button_index = MOUSE_BUTTON_RIGHT
	right_release.pressed = false
	ending.handle_input(right_release)
	_expect(not ending.is_accelerated(), "releasing right mouse restores nominal credits speed")
	ending.advance_for_test(20.0)
	_expect_equal(
		ending.current_slide_index(),
		12,
		"non-looping retail slides hold the thirteenth image pending continue"
	)
	_expect(not ending._instruction.visible, "ending control help clears after the traced eight seconds")
	var dismiss_count := [0]
	ending.dismissed.connect(func() -> void: dismiss_count[0] += 1)
	var space := InputEventKey.new()
	space.keycode = KEY_SPACE
	space.pressed = true
	ending.handle_input(space)
	ending.handle_input(space)
	_expect_equal(dismiss_count[0], 1, "Space dismisses credits exactly once")

	var firework_rng := DeterministicRng.new(12345)
	var firework_terminal := {
		"ending_mode_id": 0,
		"winner_seat_id": -1,
		"presentation_tick": 700,
		"presentation_rng": firework_rng.snapshot(),
	}
	_expect(
		ending.configure(assets, contract, firework_terminal),
		"credits accept a firework-enabled terminal"
	)
	_expect(ending.fireworks_enabled(), "the ending mode firework flag enables ending fireworks")
	ending.start()
	var first_firework_signature := ending.firework_signature()
	ending.configure(assets, contract, firework_terminal)
	ending.start()
	_expect_equal(
		ending.firework_signature(),
		first_firework_signature,
		"winner fireworks clone terminal RNG and replay identically"
	)
	ending.advance_for_test(1.0)
	var one_second_firework_signature := ending.firework_signature()
	_expect_equal(ending.firework_update_count(), 60, "one elapsed second advances exactly sixty firework updates")
	for refresh_rate in [100, 144, 165]:
		ending.configure(assets, contract, firework_terminal)
		ending.start()
		for _frame in range(refresh_rate):
			ending.advance_for_test(1.0 / float(refresh_rate))
		_expect_equal(
			ending.firework_update_count(),
			60,
			"%d Hz partitioning advances exactly sixty firework updates" % refresh_rate
		)
		_expect_equal(
			ending.firework_signature(),
			one_second_firework_signature,
			"%d Hz partitioning preserves the deterministic firework signature" % refresh_rate
		)
	ending.configure(assets, contract, firework_terminal)
	ending.start()
	var initial_sub_tick_progress := float(ending.firework_render_progresses()[0])
	ending.advance_for_test((1.0 / 60.0) - 0.000001)
	_expect_equal(ending.firework_update_count(), 0, "a genuine sub-tick interval is never rounded up")
	_expect(
		float(ending.firework_render_progresses()[0]) > initial_sub_tick_progress,
		"a genuine sub-tick interval still advances high-refresh firework rendering"
	)
	ending.configure(assets, contract, firework_terminal)
	ending.start()
	ending.advance_for_test(1.3)
	var coarse_firework_signature := ending.firework_signature()
	_expect_equal(ending.firework_update_count(), 78, "coarse elapsed time advances the exact fixed-update count")
	ending.configure(assets, contract, firework_terminal)
	ending.start()
	for _frame in range(156):
		ending.advance_for_test(1.0 / 120.0)
	_expect_equal(
		ending.firework_signature(),
		coarse_firework_signature,
		"fixed-update winner fireworks are invariant to high-refresh frame partitioning"
	)
	firework_rng.next_u32()
	firework_terminal.presentation_rng = firework_rng.snapshot()
	ending.configure(assets, contract, firework_terminal)
	ending.start()
	_expect(
		ending.firework_signature() != first_firework_signature,
		"a distinct terminal RNG state produces a distinct deterministic winner burst"
	)

	var authored := assets.section("ending")
	var authored_slides: Array = authored.get("slides", [])
	_expect_equal(authored_slides.size(), 13, "presentation content publishes all thirteen ending slides")
	if authored_slides.size() == 13:
		var authored_order: Array[String] = []
		for slide_value in authored_slides:
			authored_order.append(str((slide_value as Dictionary).get("texture", "")))
		_expect_equal(
			authored_order,
			[
				"ending_5", "ending_4", "ending_6", "ending_3", "ending_0",
				"ending_1", "ending_9", "ending_7", "ending_8", "ending_2",
				"ending_10", "ending_11", "ending_12",
			],
			"ending slides retain the executable-backed load order"
		)
		_expect(
			authored_slides.all(
				func(slide: Dictionary) -> bool: return is_equal_approx(float(slide.get("duration_seconds", 0.0)), 15.0)
			),
			"every ending image retains its fifteen-second retail duration"
		)
	_expect_equal(float(authored.get("scroll_pixels_per_second", 0.0)), 30.0, "ending content pins the 0.5-pixel-per-update scroll rate")
	_expect_equal(float(authored.get("accelerated_multiplier", 0.0)), 8.0, "ending content pins right-click acceleration")
	_expect_equal(str(authored.get("music", "")), "endgame", "ending content names the recovered music asset")
	_expect(
		not str(authored.get("story_text", "")).begins_with("|"),
		"ending display text strips the executable's leading format control"
	)
	_expect(
		ending.configure(
			assets,
			authored,
			{"ending_mode_id": 0, "winner_seat_id": -1}
		),
		"the client accepts the authored ending contract without fallback data"
	)
	_expect_equal(
		ending._scroll_label.text,
		str(authored.get("story_text", "")) + str(authored.get("credits_text", "")),
		"the client presents the exact recovered story/credits byte order"
	)
	_expect(ending.fireworks_enabled(), "the authored normal ending enables fireworks")
	ending.free()
	assets.clear()
	await process_frame


func _test_campaign_ending_gate() -> void:
	var screen := WBGameplayScreen.new()
	root.add_child(screen)
	await process_frame
	var persist_requests: Array[Dictionary] = []
	var audio_requests: Array[Dictionary] = []
	var exit_requests: Array[Dictionary] = []
	var fail_persistence := [true]
	screen.authoritative_result_ready.connect(
		func(result: Dictionary) -> void:
			persist_requests.append(result.duplicate(true))
			if fail_persistence[0]:
				screen.mark_authoritative_result_persist_failed(
					"SIMULATED STORAGE FAILURE. TRY AGAIN."
				)
			else:
				screen.mark_authoritative_result_persisted()
	)
	screen.audio_requested.connect(
		func(request: Dictionary) -> void: audio_requests.append(request.duplicate(true))
	)
	screen.exit_requested.connect(
		func(result: Dictionary) -> void: exit_requests.append(result.duplicate(true))
	)
	screen._config = {"mode": "solo", "difficulty": "normal"}
	screen._current_phase = "complete"
	screen._snapshot = {
		"tick": 4000,
		"rng": DeterministicRng.new(9876).snapshot(),
		"phase": "complete",
		"level_id": 100,
		"shared": {"score": 7654321, "money": 987},
		"result": {
			"completed": true,
			"level_reached": 100,
			"campaign_terminal": {
				"kind": "level_100",
				"full_campaign_completed": true,
				"credits_required": true,
				"ending_mode_id": 0,
				"winner_seat_id": -1,
				"level_100_score": 7654321,
			},
		},
	}
	screen._apply_phase("complete")
	_expect_equal(persist_requests.size(), 1, "full completion requests immediate profile persistence once")
	_expect(
		not screen._ending_presentation.is_active(),
		"credits remain gated until profile persistence is explicitly acknowledged"
	)
	_expect(screen._result_overlay.visible, "failed persistence retains the authoritative result screen")
	_expect(screen._result_retry_button.visible, "failed persistence exposes a clear retry action")
	_expect(not screen._result_retry_button.disabled, "the failed-persistence retry action is enabled")
	_expect(screen._result_done_button.disabled, "failed persistence prevents discarding the completed run")
	_expect(
		screen._result_persistence_status.text.contains("SIMULATED STORAGE FAILURE"),
		"failed persistence explains why credits have not started"
	)
	_expect(
		not audio_requests.any(
			func(request: Dictionary) -> bool: return str(request.get("key", "")) == "endgame"
		),
		"credits music cannot start before successful persistence"
	)
	screen._leave_run()
	_expect_equal(exit_requests.size(), 0, "failed persistence cannot discard the retained campaign result")
	screen._apply_phase("complete")
	_expect_equal(persist_requests.size(), 1, "replayed completion snapshots do not double-save profiles")
	fail_persistence[0] = false
	screen.retry_authoritative_result_persist()
	_expect_equal(persist_requests.size(), 2, "the retry action resubmits the retained authoritative result once")
	if persist_requests.size() == 2:
		_expect_equal(
			persist_requests[1],
			persist_requests[0],
			"persistence retry uses the exact retained result instead of rebuilding it"
		)
	_expect(
		screen._ending_presentation.is_active(),
		"successful persistence acknowledgement begins credits"
	)
	_expect_equal(
		screen._ending_presentation._terminal.get("presentation_rng", {}),
		screen._snapshot.get("rng", {}),
		"credits receive a client-local clone of the terminal authoritative RNG"
	)
	_expect(not screen._result_overlay.visible, "acknowledged credits defer the normal results overlay")
	_expect(
		audio_requests.any(
			func(request: Dictionary) -> bool: return str(request.get("key", "")) == "endgame"
		),
		"acknowledged credits request the recovered endgame music"
	)
	screen.retry_authoritative_result_persist()
	_expect_equal(persist_requests.size(), 2, "acknowledged persistence cannot be retried or duplicated")
	screen._ending_presentation.dismiss()
	_expect(screen._result_overlay.visible, "dismissing credits reveals the existing results overlay")
	_expect(
		bool(screen._build_result().get("profile_result_persisted", false)),
		"the eventual menu exit carries the immediate-persistence acknowledgement"
	)
	_expect_equal(screen.completion_heading(100), "ALL 100 LEVELS CLEARED", "full completion has a final campaign heading")
	screen.free()
	await process_frame

	var short_screen := WBGameplayScreen.new()
	root.add_child(short_screen)
	await process_frame
	var short_persist_count := [0]
	short_screen.authoritative_result_ready.connect(func(_result: Dictionary) -> void: short_persist_count[0] += 1)
	short_screen._current_phase = "complete"
	short_screen._snapshot = {
		"phase": "complete",
		"level_id": 99,
		"result": {
			"completed": true,
			"campaign_terminal": {
				"kind": "configured_boundary",
				"full_campaign_completed": false,
				"credits_required": false,
				"ending_mode_id": 0,
				"winner_seat_id": -1,
				"level_100_score": 0,
			},
		},
	}
	short_screen._apply_phase("complete")
	_expect(not short_screen._ending_presentation.is_active(), "explicit earlier boundaries skip credits")
	_expect(short_screen._result_overlay.visible, "explicit earlier boundaries retain normal results")
	_expect_equal(short_persist_count[0], 0, "earlier boundaries retain save-on-exit behavior")
	_expect_equal(short_screen.completion_heading(99), "LEVEL 99 CLEARED", "late explicit boundaries use generic result copy")
	short_screen.free()
	await process_frame


func _test_renderer_layout() -> void:
	var renderer := WBGameplayRenderer.new()
	renderer.size = Vector2(2560.0, 1440.0)
	root.add_child(renderer)
	await process_frame
	var arena := renderer.output_rect()
	_expect_vector(arena.position, Vector2(320.0, 0.0), "renderer letterboxes ultrawide output")
	_expect_vector(arena.size, Vector2(1920.0, 1440.0), "renderer scales the full arena")
	var playfield := renderer.playfield_rect()
	_expect_vector(playfield.position, Vector2(473.6, 0.0), "original left HUD rail remains inside the arena")
	_expect_vector(playfield.size, Vector2(1612.8, 1440.0), "original 672-pixel playfield scales without expanding")
	var background_quads := WBGameplayRenderer.background_destination_quads(125.0)
	_expect_equal(
		background_quads,
		[Rect2(64.0, -475.0, 672.0, 600.0), Rect2(64.0, 125.0, 672.0, 600.0)],
		"retail background mapping uses two whole-source quads separated by exactly 600 pixels"
	)
	_expect(
		is_equal_approx(WBGameplayRenderer.advance_background_scroll(0.0, 5.0, "level"), 0.0),
		"ordinary level snapshots do not manufacture background motion"
	)
	_expect(
		is_equal_approx(WBGameplayRenderer.advance_background_scroll(0.0, 5.0, "warp"), 0.25),
		"Warp advances the background by active warp scale divided by twenty"
	)
	_expect(
		is_equal_approx(WBGameplayRenderer.advance_background_scroll(599.9, 5.0, "warp"), 0.15),
		"positive Warp scrolling wraps at the exact 600-pixel boundary"
	)
	_expect(
		is_equal_approx(WBGameplayRenderer.advance_background_scroll(0.0, -5.0, "warp"), 599.75),
		"negative Warp scrolling wraps at the exact zero boundary"
	)
	renderer.set_snapshot({"tick": 10, "phase": "level", "level_id": 1, "warp": {"scale": 7.15}})
	renderer.set_snapshot({"tick": 11, "phase": "level", "level_id": 1, "warp": {"scale": 7.15}})
	_expect(is_zero_approx(renderer.background_scroll_offset()), "renderer state remains still outside Warp")
	renderer.set_snapshot({"tick": 12, "phase": "warp", "level_id": 1, "warp": {"scale": 5.0}})
	_expect(is_zero_approx(renderer.background_draw_offset()), "Warp draws the existing offset before its post-draw update")
	_expect(is_equal_approx(renderer.background_scroll_offset(), 0.25), "renderer advances once per new authoritative Warp tick")
	renderer.set_snapshot({"tick": 12, "phase": "warp", "level_id": 1, "warp": {"scale": 99.0}})
	_expect(is_zero_approx(renderer.background_draw_offset()), "redrawing a snapshot preserves its pre-update draw offset")
	_expect(is_equal_approx(renderer.background_scroll_offset(), 0.25), "redrawing one authoritative snapshot cannot advance background state")
	renderer.set_snapshot({"tick": 13, "phase": "warp", "level_id": 1, "warp": {"scale": 5.0}})
	_expect(is_equal_approx(renderer.background_draw_offset(), 0.25), "the next Warp tick draws the preceding post-update offset")
	_expect(is_equal_approx(renderer.background_scroll_offset(), 0.5), "the next Warp tick performs one more post-draw update")
	renderer.configure({})
	renderer.set_snapshot({
		"tick": 12,
		"phase": "warp",
		"level_id": 1,
		"warp": {
			"scale": 5.0,
			"background_draw_offset": 0.0,
			"background_post_draw_offset": 0.25,
		},
	})
	renderer.set_snapshot({
		"tick": 15,
		"phase": "warp",
		"level_id": 1,
		"warp": {
			"scale": 11.45,
			"background_draw_offset": 1.0725,
			"background_post_draw_offset": 1.645,
		},
	})
	_expect(
		is_equal_approx(renderer.background_draw_offset(), 1.0725)
		and is_equal_approx(renderer.background_scroll_offset(), 1.645),
		"20 Hz snapshots consume the authoritative sum of each changing Warp scale"
	)
	_expect(
		is_equal_approx(renderer.interpolated_background_draw_offset(0.5), 0.53625),
		"high-refresh rendering interpolates between authoritative three-tick offsets"
	)
	renderer.set_snapshot({
		"tick": 18,
		"phase": "warp",
		"level_id": 1,
		"warp": {
			"scale": 5.0,
			"background_draw_offset": 0.25,
			"background_post_draw_offset": 0.5,
		},
	})
	renderer._background_previous_draw_offset = 599.75
	_expect(
		is_zero_approx(renderer.interpolated_background_draw_offset(0.5)),
		"high-refresh background interpolation follows the short path across the 600 wrap"
	)
	for required_key in [
		"fighter1",
		"fighter2",
		"figterfire2",
		"alien001",
		"alien_2",
		"weapons_big",
		"bonuses",
		"stars1",
		"border",
		"expl_small",
		"flare1",
	]:
		_expect(renderer.required_asset_keys().has(required_key), "renderer declares original asset %s" % required_key)
	_expect(
		not renderer.has_presentation_error(),
		"required original renderer assets resolve: %s" % [renderer.presentation_errors()]
	)
	_expect_equal(renderer.pickup_texture_key(), "bonuses", "pickups use the original bonuses atlas")
	for pickup_kind in ["money", "armour", "letter", "bonus_time"]:
		var pickup_rect := renderer.pickup_source_rect(pickup_kind)
		_expect(
			pickup_rect.size == Vector2i(20, 20),
			"%s pickup maps to an original bonuses frame" % pickup_kind
		)
	_expect_equal(renderer.pickup_source_rect("money").position.y, 600, "money uses the first recovered money row")
	_expect_equal(renderer.pickup_source_rect("armour").position.y, 500, "armour uses recovered type-21 row")
	_expect_equal(renderer.pickup_source_rect("bonus_time").position.y, 480, "extra time uses recovered type-28 row")
	_expect_equal(renderer.pickup_source_rect("letter", 0, 4).position.y, 140, "EXTRA letter variants select their recovered rows")
	_expect_equal(renderer.pickup_source_rect("money", 9).position.x, 180, "bonus rows expose all ten animation frames")
	_expect_equal(renderer.thrust_frame_size(), Vector2i(16, 25), "fighter thrust uses recovered frame geometry")
	_expect_equal(renderer.thrust_frame_count(), 10, "fighter thrust uses all ten retail frames")
	_expect_equal(renderer.thrust_center_offset(), Vector2(0.0, 19.5), "fighter thrust retains the retail top-left draw offset in centered coordinates")
	_expect_equal(renderer.enemy_projectile_source_rect(0), Rect2i(480, 0, 32, 32), "alien shots use the recovered first atlas row")
	_expect_equal(renderer.enemy_projectile_source_rect(1), Rect2i(480, 32, 32, 32), "alien shots use the recovered second atlas row")
	_expect_equal(renderer.enemy_projectile_source_rect(2), Rect2i(480, 0, 32, 32), "alien shot animation wraps over two rows")
	_expect_equal(renderer.enemy_projectile_source_rect(1, 6), Rect2i(448, 32, 32, 32), "state-6 aimed shots use their recovered type-6 atlas column")
	renderer.set_snapshot({"tick": 1, "phase": "level", "level_id": 25})
	_expect_equal(
		renderer.projectile_snapshot_source_rect({
			"owner_kind": "boss",
			"enemy_sheet": "alien_big1_1",
			"enemy_projectile_type": 14,
			"animation_frame": 3,
			"source_rect": [544, 0, 32, 32],
		}),
		Rect2i(544, 0, 32, 32),
		"type-14 boss shots render the authoritative six-frame snapshot atlas region"
	)
	_expect_equal(
		renderer.projectile_snapshot_source_rect({
			"owner_kind": "boss",
			"enemy_sheet": "alien_big1_1",
			"enemy_projectile_type": 15,
			"animation_frame": 5,
			"source_rect": [160, 64, 32, 32],
		}),
		Rect2i(160, 64, 32, 32),
		"type-15 boss shots preserve retained raw animation frames without two-frame wrapping"
	)
	_expect_equal(
		renderer.projectile_snapshot_source_rect({
			"owner_kind": "boss",
			"enemy_sheet": "alien_big1_1",
			"enemy_projectile_type": 15,
			"animation_frame": 5,
			"source_rect": [480, 32, 32, 32],
		}),
		Rect2i(),
		"boss projectile rendering rejects a generic-frame substitution"
	)
	_expect_equal(
		renderer.projectile_snapshot_source_rect({
			"owner_kind": "boss",
			"enemy_sheet": "alien_big1_1",
			"enemy_projectile_type": 14,
			"animation_frame": 6,
			"source_rect": [192, 64, 32, 32],
		}),
		Rect2i(),
		"type-14 boss projectiles reject frames outside the traced six-frame domain"
	)
	renderer.set_snapshot({"tick": 2, "phase": "level", "level_id": 50})
	_expect_equal(
		renderer.projectile_snapshot_source_rect({
			"owner_kind": "boss",
			"enemy_sheet": "alien_big2_1",
			"enemy_projectile_type": 14,
			"animation_frame": 0,
			"source_rect": [512, 0, 32, 32],
		}),
		Rect2i(512, 0, 32, 32),
		"level-50 boss projectiles validate against authored resource slot one"
	)
	_expect_equal(
		renderer.projectile_snapshot_source_rect({
			"owner_kind": "boss",
			"enemy_sheet": "alien_big1_1",
			"enemy_projectile_type": 14,
			"animation_frame": 0,
			"source_rect": [512, 0, 32, 32],
		}),
		Rect2i(),
		"boss projectiles cannot borrow another level's resource-slot-one sheet"
	)
	_expect_equal(renderer.enemy_projectile_texture_key({"enemy_sheet": "alien_2"}), "alien_2", "alien shots retain their firing enemy atlas")
	_expect_equal(renderer.explosion_frame_count(), 13, "small explosions use recovered frames zero through twelve")
	var meteor_ship := {
		"frame_index": 5,
		"width": 40,
		"height": 28,
		"collision_height": 27,
		"render_source_rect": [200, 0, 40, 28],
		"source_rect": [200, 0, 40, 27],
	}
	_expect_equal(
		renderer.meteor_ship_render_source_rect(meteor_ship),
		Rect2(200.0, 0.0, 40.0, 28.0),
		"Meteor fighter draws the full 40x28 authored frame instead of its 40x27 collision slice"
	)
	_expect_equal(
		renderer.meteor_ship_render_destination(meteor_ship, Vector2(400.0, 564.0)),
		Rect2(380.0, 550.0, 40.0, 28.0),
		"Meteor fighter render geometry remains centered without a half-pixel vertical offset"
	)
	var slot_generation_one := {"slot_id": 3, "spawn_serial": 41}
	var slot_generation_two := {"slot_id": 3, "spawn_serial": 42}
	_expect(
		renderer.meteor_slot_interpolation_key(slot_generation_one)
		!= renderer.meteor_slot_interpolation_key(slot_generation_two),
		"Meteor slot interpolation identity includes spawn_serial so respawns cannot teleport through old positions"
	)
	var level_eight_live := renderer.level_eight_presentation_state({
		"active": true,
		"result_initialized": false,
		"players": [{
			"seat_id": 0,
			"participating": true,
			"hud_hits": 7,
			"hud_misses": 13,
			"total_targets": 20,
		}],
	})
	_expect_equal(str(level_eight_live.get("kind", "")), "hud", "level-eight live counters select the HUD presentation")
	_expect_equal(int(level_eight_live.players[0].hits), 7, "level-eight HUD consumes authoritative hit counters")
	var level_eight_results := renderer.level_eight_presentation_state({
		"active": true,
		"result_initialized": true,
		"header": "B O N U S   L E V E L   R E S U L T S",
		"reveal_countdown": 2,
		"players": [{
			"seat_id": 0,
			"participating": true,
			"hud_hits": 20,
			"hud_misses": 0,
			"total_targets": 20,
			"perfect_awarded": true,
			"perfect_reward": 10000,
			"next_perfect_reward": 25000,
		}],
	})
	_expect_equal(str(level_eight_results.get("kind", "")), "results", "level-eight result hold selects the full result presentation")
	_expect_equal(int(level_eight_results.players[0].perfect_reward), 10000, "level-eight results consume the authoritative perfect reward")
	var memory_gem_drop := renderer.memory_station_presentation_state({
		"stage": "success_hold",
		"now_ms": 12000,
		"gem_drop_active": true,
		"gem_drop_until_ms": 15000,
		"super_gem_drop": true,
	})
	_expect_equal(str(memory_gem_drop.get("kind", "")), "super_gem_drop", "Gem Drop presentation owns the frozen Memory Station boundary")
	_expect_equal(int(memory_gem_drop.get("remaining_ms", -1)), 3000, "Gem Drop countdown uses authoritative simulation milliseconds")
	var memory_success := renderer.memory_station_presentation_state({
		"stage": "success_hold",
		"now_ms": 12000,
		"success_deadline_ms": 15000,
		"matches": 8,
		"mismatches": 1,
		"tries": 9,
	})
	_expect_equal(str(memory_success.get("kind", "")), "success", "Memory Station success hold has an explicit presentation state")
	_expect_equal(int(memory_success.get("matches", -1)), 8, "Memory success presentation consumes authoritative counters")
	var meteor_result := renderer.meteor_storm_result_presentation_state({
		"now_ms": 20000,
		"transition_until_ms": 23000,
		"completion": {
			"success": true,
			"tier": "perfect",
			"speed_percentage": 100.0,
			"score_reward": 20000000,
			"cash_reward": 50000,
			"meteor_score_delta_total": 20100000,
			"meteor_streak": 4,
		},
	})
	_expect_equal(str(meteor_result.get("kind", "")), "success", "Meteor completion payload selects the terminal result presentation")
	_expect_equal(int(meteor_result.get("remaining_ms", -1)), 3000, "Meteor result countdown covers the full authoritative retail hold")
	var gem_intro := renderer.gem_drop_presentation_state({
		"super_gem_drop": true,
		"now_ms": 12999,
		"intro_until_ms": 13000,
		"stage": "intro",
	})
	_expect_equal(
		str(gem_intro.get("title", "")),
		"S U P E R   G E M   D R O P",
		"Super Gem Drop uses the executable's exact spaced title"
	)
	_expect(bool(gem_intro.get("show_get_ready", false)), "Gem Drop shows GET READY strictly before its intro deadline")
	var gem_at_equality := renderer.gem_drop_presentation_state({
		"super_gem_drop": false,
		"now_ms": 13000,
		"intro_until_ms": 13000,
		"stage": "active",
	})
	_expect_equal(
		str(gem_at_equality.get("title", "")),
		"G E M   D R O P",
		"normal Gem Drop uses the executable's exact spaced title"
	)
	_expect(not bool(gem_at_equality.get("show_get_ready", true)), "Gem Drop removes GET READY at exact deadline equality")
	var gem_key_context := {"entry_tick": 700, "owner_seat_id": 0}
	var gem_slot_generation_one := {
		"slot_id": 2,
		"x_fp": 200 * 65536,
		"fall_speed_fp": 8 * 65536,
		"source_x": 80,
	}
	var gem_slot_generation_two := gem_slot_generation_one.duplicate()
	gem_slot_generation_two.x_fp = 600 * 65536
	_expect(
		renderer.gem_drop_slot_interpolation_key(gem_key_context, gem_slot_generation_one)
		!= renderer.gem_drop_slot_interpolation_key(gem_key_context, gem_slot_generation_two),
		"recycled Gem Drop slots cannot interpolate across a new authored fall"
	)
	renderer.configure({"effects_mode": "original"})
	_expect_equal(renderer.effects_mode(), "original", "original effects mode disables enhanced additive layer")
	renderer.set_snapshot({
		"tick": 1,
		"level_id": 1,
		"phase": "level",
		"players": [],
		"events": [
			{
				"event_id": 68,
				"type": "player_destroyed",
				"tick": 1,
				"x_fp": 400 * 65536,
				"y_fp": 220 * 65536,
			},
			{
				"event_id": 69,
				"type": "enemy_destroyed",
				"tick": 1,
				"x_fp": 400 * 65536,
				"y_fp": 220 * 65536,
			},
		],
	})
	_expect_equal(renderer.active_effect_count(), 0, "original mode never maps generic enemy/player destruction to retail type 10")
	renderer.set_snapshot({
		"tick": 2,
		"level_id": 1,
		"phase": "level",
		"players": [],
		"events": [{
			"event_id": 70,
				"type": "boss_retail_effect",
				"call": "FUN_005dfee0",
				"allocated_count": 1,
				"frame_period": 0,
				"payload": {
				"kind": "boss_hit",
				"x": 400.0,
				"y": 220.0,
			},
			"tick": 2,
		}],
	})
	_expect_equal(renderer.active_effect_count(), 1, "the real state-13 effect call selects the thirteen-frame atlas")
	_expect_equal(renderer._effects.active_effect_kinds(), ["type_10_impact"], "type-10 events keep their narrow impact semantic")
	_expect_equal(renderer._effects.active_effect_frame_indices(), [0], "period-zero type 10 starts on frame zero")
	renderer._effects.set_render_tick(3.0)
	_expect_equal(renderer._effects.active_effect_frame_indices(), [1], "period-zero type 10 advances every update")
	renderer._effects.set_render_tick(14.0)
	_expect_equal(renderer._effects.active_effect_frame_indices(), [12], "period-zero type 10 retains its thirteenth frame through update twelve")
	renderer._effects.set_render_tick(15.0)
	_expect_equal(renderer.active_effect_count(), 0, "period-zero type 10 expires on update thirteen")
	renderer.set_snapshot({
		"tick": 20,
		"level_id": 1,
		"phase": "level",
		"players": [],
		"events": [{
			"event_id": 171,
			"type": "boss_retail_effect",
			"call": "FUN_005dfee0",
			"allocated_count": 1,
			"frame_period": 1,
			"payload": {
				"kind": "boss_hit",
				"x": 400.0,
				"y": 220.0,
			},
			"tick": 20,
		}],
	})
	_expect_equal(renderer._effects.active_effect_frame_indices(), [0], "period-one type 10 starts on frame zero")
	renderer._effects.set_render_tick(21.0)
	_expect_equal(renderer._effects.active_effect_frame_indices(), [0], "period-one type 10 holds each frame for the first update")
	renderer._effects.set_render_tick(22.0)
	_expect_equal(renderer._effects.active_effect_frame_indices(), [1], "period-one type 10 advances on the second update")
	renderer._effects.set_render_tick(45.0)
	_expect_equal(renderer._effects.active_effect_frame_indices(), [12], "period-one type 10 retains frame twelve through update 25")
	renderer._effects.set_render_tick(46.0)
	_expect_equal(renderer.active_effect_count(), 0, "period-one type 10 expires on update 26")
	renderer.set_snapshot({
		"tick": 47,
		"level_id": 1,
		"phase": "level",
		"players": [],
		"events": [{
			"event_id": 170,
			"type": "boss_retail_effect",
			"call": "FUN_005dfee0",
			"allocated_count": 0,
			"payload": {
				"kind": "boss_hit",
				"x": 400.0,
				"y": 220.0,
			},
			"tick": 47,
		}],
	})
	_expect_equal(renderer.active_effect_count(), 0, "a pool-full state-13 call cannot create an unallocated type-10 visual")
	renderer.configure({"effects_mode": "enhanced", "texture_filter": "sharp"})
	_expect_equal(renderer.effects_mode(), "enhanced", "enhanced mode retains original core effects")
	_expect_equal(renderer.texture_filter_mode(), "sharp", "sharp texture scaling uses nearest filtering")
	var destruction_event := {
		"event_id": 71,
		"type": "enemy_destroyed",
		"tick": 3,
		"x_fp": 400 * 65536,
		"y_fp": 220 * 65536,
	}
	renderer.set_snapshot({
		"tick": 3,
		"level_id": 1,
		"phase": "level",
		"players": [],
		"events": [destruction_event],
	})
	_expect_equal(renderer.active_effect_count(), 1, "authoritative event creates one pooled original effect")
	_expect(renderer.has_seen_effect_event(71), "effect pool records authoritative event identity")
	renderer.set_snapshot({
		"tick": 6,
		"level_id": 1,
		"phase": "level",
		"players": [],
		"events": [destruction_event],
	})
	_expect_equal(renderer.active_effect_count(), 1, "repeated snapshots do not duplicate an effect event")
	var one_tick_later := Time.get_ticks_usec() + 16667
	var alpha := renderer.interpolation_alpha(one_tick_later)
	_expect(alpha > 0.25 and alpha < 0.5, "20 Hz snapshots interpolate across their full three-tick window")
	var previous_meteor_slot := {
		"slot_id": 3,
		"spawn_serial": 41,
		"active": true,
		"x_fp": 100 * 65536,
		"y_fp": 200 * 65536,
	}
	var previous_meteor_ship := {
		"x_fp": 300 * 65536,
		"y_fp": 560 * 65536,
	}
	renderer.set_snapshot({
		"tick": 9,
		"level_id": 3,
		"phase": "bonus_mode",
		"bonus_mode": {
			"kind": "meteor_storm",
			"owner_seat_id": 0,
			"entry_tick": 7,
			"ship": previous_meteor_ship,
			"slots": [previous_meteor_slot],
		},
	})
	var current_meteor_slot := {
		"slot_id": 3,
		"spawn_serial": 41,
		"active": true,
		"x_fp": 160 * 65536,
		"y_fp": 260 * 65536,
	}
	var current_meteor_ship := {
		"x_fp": 340 * 65536,
		"y_fp": 564 * 65536,
	}
	var current_bonus := {
		"kind": "meteor_storm",
		"owner_seat_id": 0,
		"entry_tick": 7,
		"now_ms": 200,
		"transition_until_ms": 3200,
		"ship": current_meteor_ship,
		"slots": [current_meteor_slot],
		"completion": {
			"success": true,
			"tier": "perfect",
			"speed_percentage": 100.0,
			"score_reward": 20000000,
			"cash_reward": 50000,
			"meteor_score_delta_total": 20100000,
			"meteor_streak": 4,
		},
	}
	renderer.set_snapshot({
		"tick": 12,
		"level_id": 3,
		"phase": "bonus_mode",
		"bonus_mode": current_bonus,
	})
	_expect_vector(
		renderer._interpolated_position(
			renderer.meteor_slot_interpolation_key(current_meteor_slot),
			current_meteor_slot,
			0.5
		),
		Vector2(130.0, 230.0),
		"same-generation Meteor slots interpolate between authoritative snapshots"
	)
	_expect_vector(
		renderer._interpolated_position(
			renderer.meteor_ship_interpolation_key(current_bonus),
			current_meteor_ship,
			0.5
		),
		Vector2(320.0, 562.0),
		"Meteor fighter interpolates between authoritative snapshots"
	)
	var respawned_meteor_slot := {
		"slot_id": 3,
		"spawn_serial": 42,
		"active": true,
		"x_fp": 700 * 65536,
		"y_fp": -60 * 65536,
	}
	_expect_vector(
		renderer._interpolated_position(
			renderer.meteor_slot_interpolation_key(respawned_meteor_slot),
			respawned_meteor_slot,
			0.5
		),
		Vector2(700.0, -60.0),
		"respawned Meteor slots start at their new authored position without cross-generation lerp"
	)
	await process_frame
	renderer.set_snapshot({
		"tick": 600,
		"level_id": 8,
		"phase": "level",
		"players": [],
		"level_eight_bonus": {
			"active": true,
			"result_initialized": true,
			"header": "B O N U S   L E V E L   R E S U L T S",
			"reveal_countdown": 2,
			"players": [{
				"seat_id": 0,
				"participating": true,
				"hud_hits": 20,
				"hud_misses": 0,
				"total_targets": 20,
				"perfect_awarded": true,
				"perfect_reward": 10000,
				"next_perfect_reward": 25000,
			}],
		},
	})
	await process_frame
	renderer.set_snapshot({
		"tick": 603,
		"level_id": 3,
		"phase": "bonus_mode",
		"bonus_mode": {
			"kind": "memory_station",
			"stage": "success_hold",
			"tiles": [],
			"matches": 8,
			"mismatches": 0,
			"tries": 8,
			"gem_drop_active": true,
			"gem_drop_until_ms": 13050,
			"super_gem_drop": true,
		},
	})
	await process_frame
	renderer.set_snapshot({
		"tick": 606,
		"level_id": 3,
		"phase": "bonus_mode",
		"bonus_mode": {
			"kind": "memory_station",
			"stage": "success_hold",
			"tiles": [],
			"matches": 8,
			"mismatches": 0,
			"tries": 8,
			"success_deadline_ms": 13100,
		},
	})
	await process_frame
	renderer.set_snapshot({
		"tick": 609,
		"level_id": 3,
		"phase": "bonus_mode",
		"bonus_mode": {
			"kind": "gem_drop",
			"entry_tick": 609,
			"owner_seat_id": 0,
			"super_gem_drop": false,
			"stage": "intro",
			"now_ms": 10150,
			"intro_until_ms": 14000,
			"players": [{
				"seat_id": 0,
				"active": true,
				"alive": true,
				"fighter_id": "fighter1",
				"mask_frame": 5,
				"x_fp": 400 * 65536,
				"y_fp": 564 * 65536,
			}],
			"slots": [{
				"slot_id": 0,
				"active": true,
				"source_x": 80,
				"source_rect": [80, 102, 80, 51],
				"x_fp": 300 * 65536,
				"y_fp": 120 * 65536,
				"fall_speed_fp": 8 * 65536,
			}],
		},
	})
	await process_frame
	renderer.free()
	await process_frame


func _test_boss_renderer() -> void:
	var renderer := WBGameplayRenderer.new()
	renderer.size = Vector2(800.0, 600.0)
	root.add_child(renderer)
	await process_frame
	for family in ["alien_big1", "alien_big2"]:
		for sheet_index in range(1, 7):
			_expect(
				renderer.required_asset_keys().has("%s_%d" % [family, sheet_index]),
				"boss renderer discovers %s_%d through the sprite catalog"
				% [family, sheet_index]
			)
			_expect(
				renderer.required_asset_keys().has("%s_%d_mask" % [family, sheet_index]),
				"boss renderer requires %s_%d_mask for exact hit flashes"
				% [family, sheet_index]
			)
	var inactive_error_count := renderer.presentation_errors().size()
	var inactive_commands := renderer.boss_render_commands({
		"active": false,
		"parts": [{"part_id": "ignored", "source_rect": [0, 0, 1, 1]}],
	})
	_expect_equal(inactive_commands.size(), 0, "inactive boss snapshots draw no parts")
	_expect_equal(
		renderer.presentation_errors().size(),
		inactive_error_count,
		"inactive boss snapshots do not validate or report dormant part data"
	)
	renderer.set_snapshot({"tick": 1, "phase": "level", "level_id": 25})
	var part_zero := {
		"part_id": 0,
		"source_rect": [0, 0, 256, 64],
		"destination_rect": [288, 140, 256, 64],
	}
	var part_one := {
		"part_id": 1,
		"source_rect": [256, 0, 256, 64],
		"x_fp": 416 * 65536,
		"y_fp": 236 * 65536,
	}
	_expect_equal(
		renderer.boss_part_interpolation_key(part_zero),
		"boss_part:0",
		"state-13 part zero has a stable interpolation identity"
	)
	_expect_equal(
		renderer.boss_part_source_rect(part_zero),
		Rect2(0, 0, 256, 64),
		"state-13 part zero uses the exact left 256x64 source slice"
	)
	_expect_equal(
		renderer.boss_part_source_rect(part_one),
		Rect2(256, 0, 256, 64),
		"state-13 part one uses the exact right 256x64 source slice"
	)
	for stage in range(6):
		var stage_commands := renderer.boss_render_commands({
			"active": true,
			"stage": stage,
			"sheet": "alien_big1_%d" % (stage + 1),
			"parts": [part_one, part_zero],
		})
		_expect_equal(
			stage_commands.size(),
			2,
			"boss stage %d resolves its one exact dynamic sheet and two parts" % stage
		)
	renderer.set_snapshot({"tick": 2, "phase": "level", "level_id": 50})
	for stage in range(6):
		var stage_commands := renderer.boss_render_commands({
			"active": true,
			"stage": stage,
			"sheet": "alien_big2_%d" % (stage + 1),
			"parts": [part_one, part_zero],
		})
		_expect_equal(
			stage_commands.size(),
			2,
			"level-50 boss stage %d resolves its authored ordered sheet" % stage
		)
	var cross_level_error_count := renderer.presentation_errors().size()
	_expect_equal(
		renderer.boss_render_commands({
			"active": true,
			"stage": 0,
			"sheet": "alien_big1_1",
			"parts": [part_one, part_zero],
		}).size(),
		0,
		"boss rendering rejects a stage sheet borrowed from another level"
	)
	_expect(
		renderer.presentation_errors().size() > cross_level_error_count,
		"cross-level boss sheets raise a visible presentation error"
	)
	renderer.set_snapshot({"tick": 3, "phase": "level", "level_id": 25})
	var commands := renderer.boss_render_commands({
		"active": true,
		"stage": 0,
		"sheet": "alien_big1_1",
		"parts": [part_one, part_zero],
	})
	_expect_equal(commands.size(), 2, "an active state-13 boss produces exactly two draw commands")
	if commands.size() == 2:
		_expect_equal(
			commands[0].source_rect,
			Rect2(0, 0, 256, 64),
			"boss draw order begins with the exact state-13 part-zero source"
		)
		_expect_equal(
			commands[0].logical_destination,
			Rect2(288, 140, 256, 64),
			"controller-authored part-zero top-left destination is preserved exactly"
		)
		_expect_equal(
			commands[1].source_rect,
			Rect2(256, 0, 256, 64),
			"boss draw order ends with the exact state-13 part-one source"
		)
		_expect_equal(
			commands[1].logical_destination,
			Rect2(288, 204, 256, 64),
			"centered fixed-point part-one fields resolve to the exact second destination"
		)
	var flash_part_zero := part_zero.duplicate(true)
	flash_part_zero.render_handle = "alien_big1_1_mask"
	var flash_commands := renderer.boss_render_commands({
		"active": true,
		"stage": 0,
		"sheet": "alien_big1_1",
		"parts": [flash_part_zero, part_one],
	})
	_expect_equal(flash_commands.size(), 2, "hit-flash snapshots retain both boss parts")
	if flash_commands.size() == 2:
		_expect_equal(
			flash_commands[0].sheet,
			"alien_big1_1_mask",
			"each boss part may select the traced white-silhouette hit-flash handle"
		)
		_expect_equal(
			flash_commands[1].sheet,
			"alien_big1_1",
			"hit-flash selection remains independently authoritative per boss part"
		)
	var previous_part_zero := part_zero.duplicate(true)
	previous_part_zero.destination_rect = [100, 200, 256, 64]
	var previous_part_one := part_one.duplicate(true)
	previous_part_one.destination_rect = [100, 264, 256, 64]
	previous_part_one.erase("x_fp")
	previous_part_one.erase("y_fp")
	var current_part_zero := part_zero.duplicate(true)
	current_part_zero.destination_rect = [300, 400, 256, 64]
	var current_part_one := previous_part_one.duplicate(true)
	current_part_one.destination_rect = [300, 464, 256, 64]
	renderer.set_snapshot({
		"tick": 100,
		"level_id": 25,
		"phase": "level",
		"boss": {
			"active": true,
			"stage": 0,
			"sheet": "alien_big1_1",
			"parts": [previous_part_zero, previous_part_one],
		},
		"events": [],
	})
	renderer.set_snapshot({
		"tick": 103,
		"level_id": 25,
		"phase": "level",
		"boss": {
			"active": true,
			"stage": 1,
			"sheet": "alien_big1_2",
			"parts": [current_part_zero, current_part_one],
		},
		"events": [],
	})
	var interpolated_commands := renderer.boss_render_commands(
		{
			"active": true,
			"stage": 1,
			"sheet": "alien_big1_2",
			"parts": [current_part_zero, current_part_one],
		},
		0.25
	)
	_expect_equal(interpolated_commands.size(), 2, "both stable boss parts interpolate across snapshots")
	if interpolated_commands.size() == 2:
		_expect_equal(
			interpolated_commands[0].logical_destination,
			Rect2(150, 250, 256, 64),
			"part-zero destination interpolates by boss_part identity across sheet stages"
		)
		_expect_equal(
			interpolated_commands[1].logical_destination,
			Rect2(150, 314, 256, 64),
			"part-one destination interpolates independently across sheet stages"
		)
	var invalid_source_count := renderer.presentation_errors().size()
	var bad_part_zero := part_zero.duplicate(true)
	bad_part_zero.source_rect = [0, 0, 255, 64]
	var invalid_source_commands := renderer.boss_render_commands({
		"active": true,
		"stage": 0,
		"sheet": "alien_big1_1",
		"parts": [bad_part_zero, part_one],
	})
	_expect_equal(invalid_source_commands.size(), 0, "incorrect state-13 source geometry draws neither part")
	_expect(
		renderer.presentation_errors().size() > invalid_source_count,
		"incorrect state-13 source geometry raises a visible presentation error"
	)
	var unknown_sheet_count := renderer.presentation_errors().size()
	var unknown_sheet_commands := renderer.boss_render_commands({
		"active": true,
		"stage": 0,
		"sheet": "not_a_retail_enemy_sheet",
		"parts": [part_zero, part_one],
	})
	_expect_equal(unknown_sheet_commands.size(), 0, "unknown boss sheets are not drawn")
	_expect(
		renderer.presentation_errors().size() > unknown_sheet_count,
		"unknown boss sheets raise a visible presentation error"
	)
	var invalid_handle_count := renderer.presentation_errors().size()
	var bad_handle_part := part_zero.duplicate(true)
	bad_handle_part.render_handle = "alien_big1_2_mask"
	_expect_equal(
		renderer.boss_render_commands({
			"active": true,
			"stage": 0,
			"sheet": "alien_big1_1",
			"parts": [bad_handle_part, part_one],
		}).size(),
		0,
		"boss parts cannot borrow another animation stage's mask"
	)
	_expect(
		renderer.presentation_errors().size() > invalid_handle_count,
		"mismatched boss hit-flash handles fail visibly"
	)
	var wrong_part_count := renderer.presentation_errors().size()
	_expect_equal(
		renderer.boss_render_commands({
			"active": true,
			"stage": 0,
			"sheet": "alien_big1_1",
			"parts": [part_zero],
		}).size(),
		0,
		"state-13 snapshots with anything other than two parts are rejected"
	)
	_expect(
		renderer.presentation_errors().size() > wrong_part_count,
		"incorrect state-13 part counts raise a visible presentation error"
	)
	var known_texture: Texture2D = renderer._textures.get("alien_big1_2")
	renderer._textures.erase("alien_big1_2")
	var missing_sheet_count := renderer.presentation_errors().size()
	renderer._draw_boss(
		renderer.output_rect(),
		1.0
	)
	_expect(
		renderer.presentation_errors().size() > missing_sheet_count,
		"a catalog-known boss sheet with no texture raises a visible presentation error"
	)
	if known_texture != null:
		renderer._textures["alien_big1_2"] = known_texture
	renderer.free()
	await process_frame


func _test_hud_original_assets() -> void:
	var hud := WBHudOverlay.new()
	hud.size = Vector2(800.0, 600.0)
	root.add_child(hud)
	await process_frame
	_expect(hud.uses_original_hud_art(), "HUD resolves original numbers and both fighter sheets")
	_expect_equal(hud.digit_source_rect(0).position.x, 0, "original HUD atlas starts with digit zero")
	_expect_equal(hud.digit_source_rect(1).position.x, 8, "original HUD atlas stores digit one in the second cell")
	_expect_equal(hud.digit_source_rect(9).position.x, 72, "original HUD atlas stores digit nine in the tenth cell")
	_expect_equal(hud.digit_source_rect(0, 168).position.x, 168, "green HUD digits use the recovered third atlas bank")
	_expect_equal(hud.digit_source_rect(0, 336).position.x, 336, "orange HUD digits use the recovered fifth atlas bank")
	_expect(hud.required_asset_keys().has("numbers"), "HUD declares original digit atlas")
	hud.update_snapshot({
		"level_id": 1,
		"mode": "coop",
		"difficulty": "normal",
		"shared": {"score": 1234, "lives": 3, "money": 50, "weapon_id": 0},
		"players": [
			{"seat_id": 0, "progression": {"lives": 3, "money": 50}},
			{"seat_id": 1, "progression": {"lives": 2, "money": 50}},
		],
	})
	hud.free()
	await process_frame


## A shell with the fake lobby client on isolated identity/cache files.
func _fake_shell(nickname: String = "", taken: Array[String] = []) -> Dictionary:
	var shell := WBAppShell.new()
	var fake := WBFakeLobbyClient.new()
	fake.taken_nicknames = taken
	shell._lobby = fake
	shell._identity.configure_path("user://test_identity.json")
	shell._identity.clear()
	shell._identity.load_identity()
	if not nickname.is_empty():
		shell._identity.set_nickname(nickname)
	shell._talent_cache.configure_path("user://test_talent_cache.json")
	shell._talent_cache.clear()
	return {"shell": shell, "fake": fake}


func _find_button(shell: Node, text: String) -> Button:
	for button in shell.find_children("*", "Button", true, false):
		if (button as Button).text == text:
			return button as Button
	return null


func _test_shell_boot() -> void:
	# Boot lands on the original title screen with no login wall; the lobby
	# client connects in the background and the footer names its state.
	var made := _fake_shell()
	var shell: WBAppShell = made["shell"]
	root.add_child(shell)
	await process_frame
	_expect(shell.get_child_count() >= 3, "app shell creates backdrop, audio, and page")
	_expect(shell.find_child("EmailInput", true, false) == null, "there is no login wall")
	_expect(_find_button(shell, "START") != null, "boot lands on the title screen")
	_expect(shell.find_children("*", "Button", true, false).size() >= 4, "title menu exposes its actions")
	_expect(
		shell.find_child("OriginalTitleScreen", true, false) is TextureRect,
		"title shell binds the contracted original 800x600 title screen"
	)
	var title_screen := shell.find_child("OriginalTitleScreen", true, false) as TextureRect
	_expect(title_screen != null and title_screen.texture.resource_path.ends_with("newscreen.png"), "title shell uses newscreen rather than a gameplay-only backdrop")
	_expect(_find_button(shell, "ACCOUNT") != null, "title bar exposes the account screen")
	var status := shell.find_child("LobbyStatus", true, false) as Label
	_expect(
		status != null and status.text.contains("ONLINE, NO NICKNAME YET"),
		"the footer reports the lobby as online without a nickname"
	)
	var team_found := false
	for menu in shell.find_children("*", "PopupMenu", true, false):
		for index in range((menu as PopupMenu).item_count):
			if (menu as PopupMenu).get_item_text(index).contains("TEAM"):
				team_found = true
	_expect(not team_found, "the unimplemented retail TEAM entry is gone")
	var bound_found := false
	for profile in shell._profile_entries:
		if str(profile.get("id", "")) == shell._identity.profile_id():
			bound_found = true
	_expect(not bound_found, "no identity profile is bound before a nickname exists")
	_expect(not shell.has_method("_show_mode_select"), "the dead SELECT MODE screen is gone")
	shell.free()
	await process_frame


func _test_nickname_prompt_path() -> void:
	var made := _fake_shell("", ["ace"] as Array[String])
	var shell: WBAppShell = made["shell"]
	var fake: WBFakeLobbyClient = made["fake"]
	root.add_child(shell)
	await process_frame
	var reached := [false]
	shell._require_nickname(func() -> void: reached[0] = true)
	await process_frame
	var name_input := shell.find_child("NicknameInput", true, false) as LineEdit
	var status := shell.find_child("NicknameStatus", true, false) as Label
	_expect(name_input != null and status != null, "an online action without a nickname opens the prompt")
	_expect(not reached[0], "the action waits for a nickname")
	var confirm := _find_button(shell, "CONFIRM")
	_expect(confirm != null, "the prompt offers CONFIRM")
	name_input.text = "no"
	confirm.pressed.emit()
	await process_frame
	_expect(status.text.contains("3-16"), "a short nickname is rejected locally")
	name_input.text = "ace"
	confirm.pressed.emit()
	await process_frame
	await process_frame
	_expect(status.text.contains("TAKEN"), "a taken nickname reports the server's refusal")
	_expect(not reached[0], "a refused nickname does not run the action")
	name_input.text = "bravo"
	confirm.pressed.emit()
	await process_frame
	await process_frame
	_expect(reached[0], "a registered nickname runs the pending action")
	_expect_equal(shell._identity.nickname(), "BRAVO", "the identity stores the registered nickname")
	_expect(fake.is_registered() and fake.nickname() == "BRAVO", "the lobby client is registered under the new nickname")
	var bound_found := false
	for profile in shell._profile_entries:
		if str(profile.get("id", "")) == shell._identity.profile_id():
			bound_found = true
	_expect(bound_found, "registration binds the identity profile in the local store")
	_expect_equal(
		str(shell._selected_profiles[0].get("id", "")),
		shell._identity.profile_id(),
		"seat 0 is pinned to the identity pilot"
	)
	shell.free()
	await process_frame


func _test_talent_tree_screen() -> void:
	var made := _fake_shell("PILOT")
	var shell: WBAppShell = made["shell"]
	var fake: WBFakeLobbyClient = made["fake"]
	root.add_child(shell)
	await process_frame
	_expect(fake.is_registered(), "an identity with a nickname registers on connect")
	fake.grant_points(35)
	shell._show_talent_tree()
	await process_frame
	var points := shell.find_child("TalentPoints", true, false) as Label
	_expect(points != null and points.text == "POINTS ★35", "talent screen shows the balance")
	_expect(shell.find_child("TalentBanner", true, false) == null, "a registered pilot sees no offline banner")
	var root_button := shell.find_child("Talent_gunnery_capacity_1", true, false) as Button
	var gated_button := shell.find_child("Talent_gunnery_capacity_2", true, false) as Button
	_expect(root_button != null and not root_button.disabled, "affordable root node is purchasable")
	_expect(gated_button != null and gated_button.disabled, "locked node is disabled")
	root_button.pressed.emit()
	await process_frame
	await process_frame
	_expect_equal(fake.owned_talents(), {"gunnery_capacity_1": 1}, "buying a talent spends server-side")
	root_button = shell.find_child("Talent_gunnery_capacity_1", true, false) as Button
	_expect(
		root_button != null and root_button.disabled and root_button.text.begins_with("★"),
		"owned node re-renders starred and disabled"
	)
	gated_button = shell.find_child("Talent_gunnery_capacity_2", true, false) as Button
	_expect(gated_button != null and not gated_button.disabled, "prerequisite chain unlocks the next tier")
	points = shell.find_child("TalentPoints", true, false) as Label
	_expect(points != null and points.text == "POINTS ★25", "balance refreshes after the spend")
	var respec_button: Button = null
	for button in shell.find_children("*", "Button", true, false):
		if (button as Button).text.begins_with("RESPEC"):
			respec_button = button as Button
			break
	_expect(respec_button != null, "talent screen offers respec")
	respec_button.pressed.emit()
	await process_frame
	_expect_equal(respec_button.text, "SURE?", "respec asks for confirmation first")
	respec_button.pressed.emit()
	await process_frame
	await process_frame
	_expect(fake.owned_talents().is_empty(), "confirmed respec clears the tree")
	_expect_equal(fake.points, 35, "respec refunds every point")
	# Offline, the tree still renders from the cached state but nothing sells.
	fake.disconnect_now()
	shell._show_talent_tree()
	await process_frame
	var banner := shell.find_child("TalentBanner", true, false) as Label
	_expect(banner != null and banner.text.contains("OFFLINE"), "offline talent screen says it shows cached talents")
	root_button = shell.find_child("Talent_gunnery_capacity_1", true, false) as Button
	_expect(root_button != null and root_button.disabled, "offline talents cannot be bought")
	points = shell.find_child("TalentPoints", true, false) as Label
	_expect(points != null and points.text == "POINTS ★35", "the cached balance still shows offline")
	shell.free()
	await process_frame


func _test_local_seed_and_grants() -> void:
	# Matches seed locally and carry the cached talent grants on seat 0; Time
	# Trial stays talent-free and solo play never names a server target.
	var made := _fake_shell("PILOT")
	var shell: WBAppShell = made["shell"]
	var fake: WBFakeLobbyClient = made["fake"]
	root.add_child(shell)
	await process_frame
	fake.grant_points(50)
	await fake.spend_talent("gunnery_capacity_1")
	await fake.spend_talent("ordnance_rocket_license")
	shell._mode = "solo"
	shell._difficulty = "hard"
	shell._selected_profiles = [shell._pilot_profile()]
	var config := shell._build_match_config()
	_expect(int(config.seed) != 0, "a match draws a local seed")
	_expect(WBMatchConfig.validate(config), "the built configuration validates")
	_expect_equal(str(config.mode), "solo", "the configuration carries the selected mode")
	_expect_equal(str(config.difficulty), "hard", "the configuration carries the selected difficulty")
	_expect_equal(config.talents_enabled, true, "solo runs talent-enabled")
	var seat: Dictionary = (config.seats as Array)[0]
	_expect_equal(
		int((seat.start_state as Dictionary).get("bullet_capacity", 0)), 8,
		"talent grants ride seat 0"
	)
	_expect_equal(seat.shop_unlocks, ["rocket_pack"] as Array[String], "licenses ride seat 0")
	_expect(not config.has("server"), "solo play never carries a server target")
	_expect(int(shell._build_match_config().seed) != int(config.seed), "every match draws a fresh seed")
	shell._mode = "time_trial"
	var trial := shell._build_match_config()
	_expect_equal(trial.talents_enabled, false, "Time Trial stays talent-free")
	fake.disconnect_now()
	shell._mode = "solo"
	var offline := shell._build_match_config()
	var offline_seat: Dictionary = (offline.seats as Array)[0]
	_expect_equal(
		int((offline_seat.start_state as Dictionary).get("bullet_capacity", 0)), 8,
		"cached grants still apply offline"
	)
	shell.free()
	await process_frame


func _test_match_end_report_credits() -> void:
	var made := _fake_shell("PILOT")
	var shell: WBAppShell = made["shell"]
	var fake: WBFakeLobbyClient = made["fake"]
	root.add_child(shell)
	await process_frame
	var points_before := fake.points
	shell._mode = "solo"
	shell._difficulty = "normal"
	shell._on_match_finished({
		"completed": false,
		"score": 250000,
		"level_id": 12,
		"duration_ticks": 3600,
		"phase": "game_over",
	})
	await process_frame
	await process_frame
	_expect_equal(fake.points, points_before + fake.credit_points_per_match,
		"a finished run is credited by the lobby server")
	var report: Dictionary = fake.matches.back()
	_expect_equal(str(report.get("kind", "")), "solo", "the report names the match kind")
	_expect_equal(int(report.get("score", 0)), 250000, "the report carries the score")
	_expect_equal(str(report.get("result", "")), "game_over", "the report names the outcome")
	_expect(
		shell.find_child("CreditToast", true, false) is Label,
		"a credit announces itself on the shell"
	)
	_expect_equal(
		shell._lobby.current_points(), points_before + fake.credit_points_per_match,
		"the cached state refreshes with the credit"
	)
	fake.disconnect_now()
	var reports_before := fake.matches.size()
	shell._on_match_finished({"completed": true, "score": 1, "level_id": 2})
	await process_frame
	_expect_equal(fake.matches.size(), reports_before, "offline runs are not reported")
	shell.free()
	await process_frame


func _test_global_chat_screen() -> void:
	var made := _fake_shell("PILOT")
	var shell: WBAppShell = made["shell"]
	var fake: WBFakeLobbyClient = made["fake"]
	root.add_child(shell)
	await process_frame
	fake.chat_log = [{"t": "chat_message", "id": 1, "nickname": "ACE", "body": "hi there", "sent_at": 0}]
	shell._show_global_chat()
	await process_frame
	await process_frame
	var panel := shell.find_child("GlobalChatPanel", true, false) as WBChatPanel
	_expect(panel != null, "the chat screen shows the panel")
	_expect_equal(panel.line_count(), 1, "stored history renders")
	panel.submit_for_test("hello world")
	await process_frame
	await process_frame
	_expect_equal(fake.chat_log.size(), 2, "submitting a line sends it to the lobby server")
	_expect_equal(panel.line_count(), 2, "the echoed line appears in the log")
	var status := shell.find_child("GlobalChatStatus", true, false) as Label
	_expect(status != null and status.text.contains("ONLINE AS PILOT"), "the chat header names the online pilot")
	fake.disconnect_now()
	shell._show_global_chat()
	await process_frame
	await process_frame
	panel = shell.find_child("GlobalChatPanel", true, false) as WBChatPanel
	var chat_status := panel.find_child("ChatStatus", true, false) as Label
	_expect(chat_status != null and chat_status.text.contains("OFFLINE"), "offline chat says it is unavailable")
	var sent_before := fake.chat_log.size()
	panel.submit_for_test("nobody hears this")
	await process_frame
	_expect_equal(fake.chat_log.size(), sent_before, "offline lines are not sent")
	shell.free()
	await process_frame


func _test_lobby_browser_and_manual_connect() -> void:
	var made := _fake_shell("PILOT")
	var shell: WBAppShell = made["shell"]
	var fake: WBFakeLobbyClient = made["fake"]
	root.add_child(shell)
	await process_frame
	fake.lobbies = [{
		"lobby_id": "lobby-1", "name": "ACE'S GAME", "host_nickname": "ACE", "mode": "coop",
		"difficulty": "hard", "coop_balance": "classic", "state": "open", "content_matches": true,
		"host_fresh": true, "player_count": 1, "created_at": 0,
	}]
	shell._show_lobby_browser()
	await process_frame
	await process_frame
	var join := shell.find_child("Join_lobby-1", true, false) as Button
	_expect(join != null and not join.disabled, "an open lobby renders an enabled JOIN button")
	var status := shell.find_child("LobbyBrowserStatus", true, false) as Label
	_expect(status != null and status.text.contains("1 GAME"), "the browser counts listed games")
	join.pressed.emit()
	await process_frame
	await process_frame
	var join_status := shell.find_child("JoinStatus", true, false) as Label
	_expect(
		join_status != null and join_status.text.contains("FINDING YOUR PUBLIC ADDRESS"),
		"a join first probes the rendezvous socket"
	)
	_expect(shell._rendezvous.is_probing(), "the probe is live while the status says so")
	shell._rendezvous.close_probe()
	shell._on_probe_finished({"ok": true, "ip": "127.0.0.1", "port": 50000, "local_port": 50000})
	await process_frame
	await process_frame
	join_status = shell.find_child("JoinStatus", true, false) as Label
	_expect(join_status != null and join_status.text.contains("WAITING FOR THE HOST"), "a join request waits for the host")
	fake.push_server_message({
		"t": WBLobbyContract.PUSH_LOBBY_JOIN_READY,
		"join_id": int(shell._party.get("join_id", 0)),
		"lobby_id": "lobby-1",
		"game_token": "tok",
		"content_hash": "",
		"host_public": null,
		"host_lan": {"ip": "127.0.0.1", "port": 42000},
		"port": 42000,
		"upnp_mapped": false,
		"same_public_ip": true,
		"host_nickname": "ACE",
		"lobby": {},
	})
	await process_frame
	_expect(shell._gameplay != null, "a ready push launches the joined match")
	var server: Dictionary = shell._gameplay._config.get("server", {}) if shell._gameplay != null else {}
	_expect_equal(str(server.get("kind", "")), "join", "the joined match dials as a joiner")
	_expect_equal(int(server.get("seat", -1)), 1, "the joiner takes seat 1")
	var candidates: Array = server.get("candidates", [])
	_expect(
		candidates.size() == 1 and str((candidates[0] as Dictionary).get("host", "")) == "127.0.0.1",
		"the LAN endpoint is the dial candidate"
	)
	_expect_equal(str(server.get("token", "")), "tok", "the game token rides the connection")
	_expect_equal(int(server.get("local_port", -1)), 50000, "the joiner dials from the probed local port")
	_expect(
		shell._gameplay != null and shell._gameplay.is_party() and shell._gameplay.party_role() == "joiner",
		"the gameplay screen runs in joiner party mode"
	)
	shell.free()
	await process_frame

	made = _fake_shell("PILOT")
	shell = made["shell"]
	root.add_child(shell)
	await process_frame
	shell._show_manual_connect()
	await process_frame
	var address := shell.find_child("HostAddressInput", true, false) as LineEdit
	var port_input := shell.find_child("HostPortInput", true, false) as LineEdit
	var token_input := shell.find_child("HostTokenInput", true, false) as LineEdit
	_expect(address != null and port_input != null and token_input != null, "the manual form has address, port, and token")
	var connect_button := _find_button(shell, "CONNECT")
	_expect(connect_button != null, "the manual form offers CONNECT")
	connect_button.pressed.emit()
	await process_frame
	var manual_status := shell.find_child("ManualConnectStatus", true, false) as Label
	_expect(manual_status != null and manual_status.text.contains("ENTER"), "an empty form is rejected")
	_expect(shell._gameplay == null, "an empty form launches nothing")
	address.text = "192.168.1.9"
	port_input.text = "42000"
	token_input.text = "ABCDEF"
	connect_button.pressed.emit()
	await process_frame
	_expect(shell._gameplay != null, "a complete form launches the join")
	server = shell._gameplay._config.get("server", {}) if shell._gameplay != null else {}
	_expect_equal(str(server.get("token", "")), "abcdef", "the typed token is normalized to lower case")
	var manual_candidates: Array = server.get("candidates", [])
	_expect(
		manual_candidates.size() == 1
		and str((manual_candidates[0] as Dictionary).get("host", "")) == "192.168.1.9",
		"the typed address is dialed"
	)
	shell.free()
	await process_frame


func _test_host_lobby_registration() -> void:
	# The host flow without spawning a sidecar: the hosted configuration, the
	# lobby listing when the room first waits, the join offer, and the match
	# reports the host sends on the joiner's arrival and at the end.
	var made := _fake_shell("ALPHA")
	var shell: WBAppShell = made["shell"]
	var fake: WBFakeLobbyClient = made["fake"]
	root.add_child(shell)
	await process_frame
	shell._start_host_setup()
	await process_frame
	_expect(_find_button(shell, "BACK") != null, "hosting starts on the difficulty screen")
	_expect_equal(str(shell._party.get("role", "")), "host", "hosting marks the party role")
	shell._difficulty = "hard"
	shell._coop_balance = "balanced"
	var config := shell._build_hosted_config()
	var server: Dictionary = config.get("server", {})
	_expect_equal(str(server.get("kind", "")), "host", "the hosted match binds the sidecar publicly")
	_expect_equal(int(server.get("port", 0)), 42000, "the hosted match uses the settings host port")
	_expect(str(server.get("token", "")).length() == 16, "the hosted match draws a 16-character token")
	_expect_equal(str(config.get("mode", "")), "coop", "a hosted match is co-op")
	_expect_equal(int(config.get("seat_count", 0)), 2, "a hosted match has two seats")
	_expect_equal(str((config.get("party", {}) as Dictionary).get("role", "")), "host", "the gameplay screen learns the host role")
	_expect(
		str(server.get("rendezvous", "")) == "%s:7401" % WBSettingsStore.DEFAULT_LOBBY_HOST,
		"a registered host passes the rendezvous socket to its sidecar"
	)
	_expect(WBRendezvousCodec.is_valid_nonce_hex(str(server.get("nonce", ""))), "a registered host passes a nonce to its sidecar")
	shell._settings["upnp_enabled"] = false
	var screen := WBGameplayScreen.new()
	shell._gameplay = screen
	shell._page.add_child(screen)
	await process_frame
	shell._on_party_waiting(true)
	await process_frame
	await process_frame
	_expect_equal(fake.lobbies.size(), 1, "the first waiting snapshot lists the game")
	var listed: Dictionary = fake.lobbies[0] if not fake.lobbies.is_empty() else {}
	_expect_equal(str(listed.get("difficulty", "")), "hard", "the listing carries the difficulty")
	_expect_equal(str(listed.get("game_token", "")), str(shell._party.get("token", "")), "the listing carries the game token")
	_expect(str(shell._party.get("lobby_id", "")).begins_with("fake-lobby"), "the shell remembers its lobby id")
	var party_status := screen.find_child("PartyStatus", true, false) as Label
	_expect(screen._party_status_text.contains("LISTED"), "the room status says the game is listed")
	shell._on_lobby_join_offer({"join_id": 5, "lobby_id": str(shell._party.get("lobby_id", "")), "joiner": {"nickname": "BRAVO", "public": null, "lan": {"ip": "192.168.1.5", "port": 40000}}})
	await process_frame
	_expect_equal(str(shell._party.get("joiner_nickname", "")), "BRAVO", "the join offer names the joiner")
	_expect_equal(screen.party_chat_line_count(), 1, "the room log announces the joiner")
	shell._on_party_waiting(false)
	await process_frame
	await process_frame
	_expect_equal(fake.matches.size(), 1, "the filled seat reports the hosted match start")
	var started: Dictionary = fake.matches[0] if not fake.matches.is_empty() else {}
	_expect_equal(str(started.get("kind", "")), "hosted", "the start report names the hosted kind")
	_expect(int(shell._party.get("match_id", 0)) > 0, "the shell remembers the match id")
	var points_before := fake.points
	shell._on_match_finished({"completed": false, "score": 90000, "level_id": 4, "duration_ticks": 600})
	await process_frame
	await process_frame
	_expect_equal(fake.matches.size(), 2, "the finished hosted match is reported")
	var ended: Dictionary = fake.matches[1] if fake.matches.size() > 1 else {}
	_expect_equal(int(ended.get("match_id", 0)), int(shell._party.get("match_id", 0)), "the end report carries the match id")
	_expect_equal(str(ended.get("kind", "")), "hosted", "the end report names the hosted kind")
	_expect_equal(fake.points, points_before + fake.credit_points_per_match, "the host is credited")
	shell._party["role"] = "joiner"
	var reports_before := fake.matches.size()
	shell._on_match_finished({"completed": false, "score": 1, "level_id": 1})
	await process_frame
	_expect_equal(fake.matches.size(), reports_before, "a joiner never reports the match")
	_expect(party_status != null, "the party status label exists")
	shell._gameplay = null
	shell.free()
	await process_frame


func _test_gameplay_party_room() -> void:
	var screen := WBGameplayScreen.new()
	root.add_child(screen)
	await process_frame
	screen._party = {"role": "host", "nickname": "ALPHA"}
	screen._party_active = true
	screen._snapshot = {"waiting_for_seats": true, "tick": 0}
	var waits: Array = []
	screen.party_waiting.connect(func(waiting: bool) -> void: waits.append(waiting))
	screen.set_party_status("LISTED IN THE LOBBY")
	_expect(screen.party_overlay_visible(), "an empty seat shows the party room")
	_expect(screen.party_heading_text().begins_with("WAITING FOR A PLAYER"), "the host room says it is waiting")
	_expect_equal(waits, [true], "the waiting transition is announced")
	var party_status := screen.find_child("PartyStatus", true, false) as Label
	_expect(party_status != null and party_status.text.contains("LISTED"), "the room shows the shell's status line")
	var start := screen.find_child("PartyStart", true, false) as Button
	_expect(start != null and start.disabled and start.visible, "START waits for a joiner")
	screen._on_chat_received(1, "BRAVO", "hello")
	_expect_equal(screen.party_chat_line_count(), 1, "chat lines land in the room log")
	var dock_panel := screen.find_child("ChatDockPanel", true, false) as WBChatPanel
	_expect(dock_panel != null and dock_panel.line_count() == 1, "chat lines mirror into the in-game dock")
	screen.set_party_joiner("BRAVO")
	screen._snapshot = {"waiting_for_seats": false, "tick": 0}
	screen._refresh_party_overlay()
	_expect_equal(waits, [true, false], "the filled seat is announced")
	_expect(not screen.party_overlay_visible(), "a running match hides the room")
	screen._current_phase = "level"
	screen._apply_phase("level")
	var dock := screen.find_child("ChatDock", true, false) as Control
	_expect(dock != null and dock.visible, "the chat dock shows during play")
	dock_panel.focus_input()
	_expect_equal(screen.filtered_input_mask(WBInputRouter.INPUT_FIRE), 0, "gameplay input is muted while typing")
	dock_panel.release_input()
	_expect_equal(
		screen.filtered_input_mask(WBInputRouter.INPUT_FIRE), WBInputRouter.INPUT_FIRE,
		"input returns when the chat line is released"
	)
	screen._party = {"role": "joiner", "nickname": "BRAVO"}
	screen._party_started = false
	screen._snapshot = {"waiting_for_seats": true, "tick": 0}
	screen._refresh_party_overlay()
	_expect(screen.party_heading_text().contains("HOST"), "the joiner room refers to the host")
	_expect(start != null and not start.visible, "the joiner has no START button")
	screen.free()
	await process_frame



class PartySessionStub extends WBClientSession:
	var requested_seat := 1
	var ready_calls: Array = []
	var purchases: Array = []
	var saves: Array = []

	func local_seat_for_authoritative(authoritative_seat: int) -> int:
		return 0 if authoritative_seat == requested_seat else -1

	func set_ready(seat: int, ready: bool) -> bool:
		ready_calls.append([seat, ready])
		return true

	func request_purchase(seat: int, item_id: int) -> Dictionary:
		purchases.append([seat, item_id])
		return {"accepted": true, "pending": true}

	func can_save_run() -> bool:
		return true

	func request_save(slot: int) -> bool:
		saves.append(slot)
		return true


## The shop addresses authoritative seats, the session speaks in local seats
## (a joiner's only seat is local 0 but authoritative 1), and the leave/save
## row must survive the twenty-per-second snapshot refresh.
func _test_shop_party_seat_controls() -> void:
	var screen := WBGameplayScreen.new()
	root.add_child(screen)
	await process_frame
	var stub := PartySessionStub.new()
	screen._session = stub
	screen._config = {"mode": "coop", "seat_count": 2}
	screen._party = {"role": "joiner", "nickname": "BRAVO"}
	screen._party_active = true
	screen._current_phase = "shop"
	var snapshot := {
		"shared": {"money": 120},
		"shop": {
			"items": [{"id": 1, "name": "Extra Speed", "price": 50}],
			"ready": [false, false],
			"active_seat_id": 1,
		},
	}
	screen._snapshot = snapshot
	screen._refresh_shop(snapshot)
	await process_frame
	var buttons := screen._ready_box.get_children()
	_expect_equal(buttons.size(), 2, "a joiner sees both seats and no save control")
	_expect(
		buttons.size() == 2 and (buttons[0] as Button).text == "P1 SHOPPING" and (buttons[0] as Button).disabled,
		"the host's seat shows as state only"
	)
	_expect(
		buttons.size() == 2 and (buttons[1] as Button).text == "P2 LEAVE SHOP" and not (buttons[1] as Button).disabled,
		"the joiner's own seat is the live control"
	)
	if buttons.size() == 2:
		(buttons[1] as Button).pressed.emit()
	_expect_equal(stub.ready_calls, [[0, true]], "leaving the shop addresses the joiner's local seat")
	screen._purchase(1)
	_expect_equal(stub.purchases, [[0, 1]], "purchases for the active seat use the local seat")
	var same_row := screen._ready_box.get_child(1)
	screen._refresh_shop(snapshot)
	_expect(screen._ready_box.get_child(1) == same_row, "an unchanged snapshot keeps the same buttons")
	(snapshot["shop"] as Dictionary)["ready"] = [true, false]
	screen._refresh_shop(snapshot)
	_expect((screen._ready_box.get_child(0) as Button).text == "P1 READY", "the host's readiness is reflected")
	stub.requested_seat = 0
	screen._party["role"] = "host"
	screen._apply_phase("shop")
	(snapshot["shop"] as Dictionary)["ready"] = [false, false]
	screen._refresh_shop(snapshot)
	await process_frame
	buttons = screen._ready_box.get_children()
	_expect_equal(buttons.size(), 3, "the host sees both seats and the save control")
	_expect(
		buttons.size() == 3 and (buttons[0] as Button).text == "P1 LEAVE SHOP" and (buttons[2] as Button).text == "SAVE GAME",
		"the host owns seat one and the save"
	)
	_expect(
		buttons.size() == 3 and (buttons[1] as Button).text == "P2 SHOPPING" and (buttons[1] as Button).disabled,
		"the joiner's seat shows as state only"
	)
	screen._purchase(1)
	_expect_equal(stub.purchases.size(), 1, "the host cannot buy during the joiner's turn")
	_expect(screen._shop_status.text.contains("P2 IS SHOPPING"), "the host is told whose turn it is")
	screen._on_save_completed(true, {"slot": 2})
	_expect(screen._shop_status.text.contains("SAVED TO SLOT 3"), "a save acknowledgement names the slot")
	screen._refresh_shop(snapshot)
	_expect(screen._shop_status.text.contains("SAVED TO SLOT 3"), "the notice survives the next snapshot")
	screen._on_save_completed(false, {"slot": 2, "reason": "disk_full"})
	_expect(screen._shop_status.text.contains("SAVE FAILED: DISK FULL"), "a rejected save explains itself")
	screen.free()
	stub.free()
	await process_frame


func _test_gameplay_screen_original_ui() -> void:
	var screen := WBGameplayScreen.new()
	root.add_child(screen)
	await process_frame
	_expect(screen.has_signal("audio_requested"), "gameplay screen forwards positional audio metadata")
	_expect(
		screen.find_children("*", "TextureRect", true, false).size() >= 3,
		"gameplay overlays include original pause, shop, and game-over art"
	)
	var overlay_paths: Array[String] = []
	for node in screen.find_children("*", "TextureRect", true, false):
		var texture_rect := node as TextureRect
		if texture_rect != null and texture_rect.texture != null:
			overlay_paths.append(texture_rect.texture.resource_path)
	_expect(overlay_paths.any(func(path: String) -> bool: return path.ends_with("pause3.tga")), "pause overlay binds the original pause3 art")
	_expect(overlay_paths.any(func(path: String) -> bool: return path.ends_with("butikk3.png")), "shop overlay binds the original butikk3 art")
	_expect(overlay_paths.any(func(path: String) -> bool: return path.ends_with("gameover.tga")), "result overlay binds the original game-over art")
	screen._current_phase = "shop"
	_expect_equal(
		screen.filtered_input_mask(WBInputRouter.INPUT_CONFIRM | WBInputRouter.INPUT_FIRE),
		0,
		"focused shop controls do not also send leave-shop gameplay commands"
	)
	screen._current_phase = "rank_promotion"
	_expect_equal(
		screen.filtered_input_mask(
			WBInputRouter.INPUT_LEFT
			| WBInputRouter.INPUT_FIRE
			| WBInputRouter.INPUT_CONFIRM
		),
		WBInputRouter.INPUT_FIRE,
		"rank promotion accepts fire while suppressing movement and UI actions"
	)
	screen._current_phase = "bonus_mode"
	screen._snapshot = {
		"bonus_mode": {
			"kind": "memory_station",
			"owner_seat_id": 0,
			"grid_columns": 4,
			"grid_rows": 4,
			"tile_size": 64,
			"grid_origin_x": 272,
			"grid_origin_y": 172,
			"tile_count": 16,
		},
	}
	_expect_equal(
		screen.filtered_input_mask(
			WBInputRouter.INPUT_LEFT
			| WBInputRouter.INPUT_UP
			| WBInputRouter.INPUT_FIRE
			| WBInputRouter.INPUT_SECONDARY
			| WBInputRouter.INPUT_CONFIRM
		),
		WBInputRouter.INPUT_LEFT
		| WBInputRouter.INPUT_UP
		| WBInputRouter.INPUT_FIRE
		| WBInputRouter.INPUT_SECONDARY,
		"Memory Station exposes only its normalized navigation and action bits"
	)
	screen._snapshot.bonus_mode = {"kind": "gem_drop", "owner_seat_id": 0}
	_expect_equal(
		screen.filtered_input_mask(
			WBInputRouter.INPUT_LEFT
			| WBInputRouter.INPUT_FIRE
			| WBInputRouter.INPUT_SECONDARY
			| WBInputRouter.INPUT_UP
		),
		WBInputRouter.INPUT_LEFT | WBInputRouter.INPUT_FIRE,
		"Gem Drop forwards horizontal movement and retail primary fire only"
	)
	screen._snapshot.bonus_mode = {
		"kind": "memory_station",
		"owner_seat_id": 0,
		"grid_columns": 4,
		"grid_rows": 4,
		"tile_size": 64,
		"grid_origin_x": 272,
		"grid_origin_y": 172,
		"tile_count": 16,
	}
	_expect_equal(
		WBGameplayScreen.memory_tile_index_from_logical(Vector2(368.0, 268.0), screen._snapshot.bonus_mode),
		9,
		"mouse coordinates normalize to the same fixed-stride tile index as keyboard selection"
	)
	_expect_equal(
		WBGameplayScreen.memory_tile_index_from_logical(Vector2(271.99, 172.0), screen._snapshot.bonus_mode),
		-1,
		"mouse positions outside the authoritative grid do not create bonus commands"
	)
	var promotion_snapshot := {
		"phase": "rank_promotion",
		"turn_seat": 1,
		"shared": {"rank": 4, "rank_cap": 20},
		"rank_promotion": {
			"seat_id": 1,
			"rank": 4,
			"rank_name": "ADMIRAL",
			"badge_y": 52,
			"highest_rank": 4,
			"rank_cap": 20,
			"minimum_tick": 100,
			"timeout_tick": 300,
			"can_continue": true,
			"prompt_visible": true,
		},
	}
	screen._snapshot = promotion_snapshot
	screen._apply_phase("rank_promotion")
	screen._refresh_rank_promotion(promotion_snapshot)
	_expect(screen._rank_promotion_overlay.visible, "rank-promotion phase displays its gameplay overlay")
	_expect_equal(
		screen._rank_promotion_title.text,
		"C O N G R A T U L A T I O N S",
		"rank-promotion overlay preserves the retail congratulations line"
	)
	_expect_equal(
		screen._rank_promotion_status.text,
		"YOU ARE HEREBY PROMOTED TO",
		"rank-promotion overlay preserves the retail promotion line"
	)
	_expect_equal(screen._rank_promotion_player.text, "PLAYER 2", "promotion overlay shows the authoritative turn")
	_expect_equal(screen._rank_promotion_rank.text, "ADMIRAL", "promotion overlay shows the recovered authoritative rank name")
	_expect_equal(
		int(screen._rank_promotion_badge_texture.region.position.y),
		52,
		"rank four uses the fourth 13-pixel ranks2 badge row"
	)
	_expect(
		screen._rank_promotion_prompt.visible
		and screen._rank_promotion_prompt.text == "PRESS FIRE TO CONTINUE",
		"authoritative prompt visibility controls the retail fire instruction"
	)
	screen._current_phase = "shop"
	screen._apply_phase("shop")
	_expect_equal(screen.shop_icon_key(18), "shop_rocketpack", "late original shop cards retain their icon bindings")
	_expect_equal(screen.shop_icon_key(20), "shop_autofire_super", "super autofire retains its original shop card")
	screen._shop_overlay.visible = true
	var ordinary_shop_snapshot := {
		"shared": {"money": 500},
		"shop": {
			"items": [{"id": 1, "name": "Extra Speed", "price": 50}],
			"ready": [false, false],
		},
	}
	screen._snapshot = ordinary_shop_snapshot
	screen._refresh_shop(ordinary_shop_snapshot)
	await process_frame
	await process_frame
	var focus := screen.get_viewport().gui_get_focus_owner()
	_expect(focus is Button and screen._shop_overlay.is_ancestor_of(focus), "controller shop flow assigns focus to an enabled authoritative control")
	var coop_shop_snapshot := {
		"shared": {"money": 75},
		"shop": {
			"items": [{"id": 1, "name": "Extra Speed", "price": 50}],
			"ready": [false, false],
			"active_seat_id": 0,
		},
	}
	screen._config = {"mode": "coop", "seat_count": 2}
	screen._snapshot = coop_shop_snapshot
	screen._refresh_shop(coop_shop_snapshot)
	await process_frame
	await process_frame
	_expect_equal(screen._shop_request_seat_id(), 0, "co-op purchases target the party leader seat")
	_expect_equal(screen._ready_box.get_child_count(), 2, "the shared co-op shop exposes both leave controls")
	if screen._ready_box.get_child_count() == 2:
		_expect(
			(screen._ready_box.get_child(0) as Button).text.begins_with("P1 ")
			and (screen._ready_box.get_child(1) as Button).text.begins_with("P2 "),
			"the co-op shop renders per-seat leave-shop controls"
		)
	screen._session._on_command_acknowledged(4, false, {"reason": "insufficient_funds"})
	_expect(screen._shop_status.text.contains("INSUFFICIENT FUNDS"), "authoritative shop rejection details reach the visible shop status")
	var leave_results: Array[Dictionary] = []
	screen.exit_requested.connect(
		func(result: Dictionary) -> void: leave_results.append(result.duplicate(true))
	)
	screen._config = {"mode": "solo", "difficulty": "ace"}
	screen._current_phase = "bonus_mode"
	screen._snapshot = {
		"level_id": 4,
		"shared": {"score": 4321, "money": 87},
		"profile_stats": [{
			"meteor_score": 975,
			"bonus_rounds": 3,
			"perfect_bonus_rounds": 2,
			"level_eight_perfect_reward_index": 4,
		}],
		"seat_progression": [{"score": 4321, "money": 87}],
		"result": {},
		"bonus_mode": {"kind": "meteor_storm", "owner_seat_id": 0},
	}
	screen._on_session_failed("peer disconnected")
	screen._leave_run()
	_expect_equal(leave_results.size(), 1, "Return to Menu still emits the last result after a disconnect")
	if leave_results.size() == 1:
		var leave_result: Dictionary = leave_results[0]
		var leave_stats: Array = leave_result.get("profile_stats", [])
		_expect_equal(leave_stats.size(), 1, "disconnect preserves active authoritative bonus statistics")
		if leave_stats.size() == 1:
			_expect_equal(int(leave_stats[0].meteor_score), 975, "Return to Menu preserves the active Meteor best")
			_expect_equal(int(leave_stats[0].bonus_rounds), 3, "Return to Menu preserves active bonus-round totals")
			_expect_equal(int(leave_stats[0].perfect_bonus_rounds), 2, "Return to Menu preserves active perfect totals")
			_expect_equal(int(leave_stats[0].level_eight_perfect_reward_index), 4, "Return to Menu preserves active level-8 progression")
		_expect_equal(str(leave_result.get("mode", "")), "solo", "disconnect results retain the configured mode")
		_expect_equal(str(leave_result.get("difficulty", "")), "ace", "disconnect results retain the configured difficulty")
	screen.free()
	await process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failures.append("%s (expected %s, got %s)" % [message, expected, actual])


func _expect_vector(actual: Vector2, expected: Vector2, message: String) -> void:
	if not actual.is_equal_approx(expected):
		_failures.append("%s (expected %s, got %s)" % [message, expected, actual])

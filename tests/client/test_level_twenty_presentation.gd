extends SceneTree

const SpriteFrameCatalog := preload("res://src/shared/sprite_frame_catalog.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_enemy_projectile_broad_bounds()

	var renderer := WBGameplayRenderer.new()
	renderer.size = Vector2(800.0, 600.0)
	root.add_child(renderer)
	await process_frame
	for sheet_id in [
		"alien001",
		"alien_2",
		"alien_3",
		"alien000",
		"alien_lilla",
		"alien003",
		"alien003_3",
		"alien_big1_1",
		"alien_big1_2",
		"alien_big1_3",
		"alien_big1_4",
		"alien_big1_5",
		"alien_big1_6",
		"alien_rakett",
		"alien_rakett_gronn",
		"alien_baller",
		"alien_baller2",
		"alien_green_lilla_t",
		"alien_cyan_lilla_t",
		"alien_raudkule",
		"alien_raudkule2",
		"alien_blavinger_gf",
		"alien_blavinger_gf2",
		"alien_rbille",
		"alien_big2_1",
		"alien_big2_2",
		"alien_big2_3",
		"alien_big2_4",
		"alien_big2_5",
		"alien_big2_6",
		"alien_gultop",
		"alien_lillatop",
		"alien_bluekreps",
		"alien_lbluekreps",
		"alien_brownkreps",
		"alien_brownkreps2",
		"alien_gulkreps",
		"alien_rvinggk",
		"alien_gvingbk",
	]:
		_expect(
			renderer.required_asset_keys().has(sheet_id),
			"renderer requires authored enemy sheet %s" % sheet_id
		)
	_expect_equal(
		renderer._sprite_frames.enemy_sheet_ids().size(),
		98,
		"renderer loads the complete campaign and Time Trial sheet catalog"
	)
	for late_sheet_id in [
		"alien_lila_royr",
		"alien_big3_1",
		"alien_n2_bla",
		"alien_big4_6",
	]:
		_expect(
			renderer.required_asset_keys().has(late_sheet_id),
			"renderer requires late-campaign enemy sheet %s" % late_sheet_id
		)
	_expect(
		renderer.required_asset_keys().has("rocket")
		and renderer.required_asset_keys().has("flare4"),
		"renderer requires the traced rocket atlas and expiry flare"
	)
	_expect(
		renderer.resolved_asset_keys().has("rocket")
		and renderer._effects._textures.has("flare4"),
		"renderer resolves both traced rocket presentation textures"
	)
	_expect(
		not renderer.has_presentation_error(),
		"all one-hundred-level presentation assets resolve: %s"
		% [renderer.presentation_errors()]
	)
	renderer.set_snapshot({"tick": 1, "phase": "level", "level_id": 13})
	_expect_equal(
		renderer.enemy_projectile_texture_key({}),
		"alien000",
		"level 13 projectile fallback resolves the authored sheet"
	)
	renderer.set_snapshot({"tick": 2, "phase": "level", "level_id": 17})
	_expect_equal(
		renderer.enemy_projectile_texture_key({}),
		"alien_lilla",
		"level 17 projectile fallback resolves the authored sheet"
	)
	renderer.set_snapshot({"tick": 3, "phase": "level", "level_id": 49})
	_expect_equal(
		renderer.enemy_projectile_texture_key({}),
		"alien_rbille",
		"level 49 projectile fallback resolves the authored sheet"
	)
	renderer.set_snapshot({"tick": 4, "phase": "level", "level_id": 50})
	_expect_equal(
		renderer.enemy_projectile_texture_key({}),
		"alien_big2_1",
		"level 50 projectile fallback resolves authored resource slot one"
	)
	renderer.set_snapshot({"tick": 5, "phase": "level", "level_id": 62})
	_expect_equal(
		renderer.enemy_projectile_texture_key({}),
		"alien_gvingbk",
		"level 62 projectile fallback resolves authored resource slot one"
	)
	renderer.set_snapshot({"tick": 6, "phase": "level", "level_id": 63})
	_expect_equal(
		renderer.enemy_projectile_texture_key({}),
		"alien_lila_royr",
		"level 63 projectile fallback resolves its authored mode-six sheet"
	)
	renderer.set_snapshot({"tick": 7, "phase": "level", "level_id": 100})
	_expect_equal(
		renderer.enemy_projectile_texture_key({}),
		"alien_big4_1",
		"level 100 projectile fallback resolves the final boss resource slot"
	)
	for level_id in range(1, 26):
		_expect_equal(
			renderer._background_texture_key(level_id),
			"stars1",
			"level %d resolves its declared background" % level_id
		)
	for level_id in range(26, 51):
		_expect_equal(
			renderer._background_texture_key(level_id),
			"stars2",
			"level %d resolves its declared late-campaign background" % level_id
		)
	for level_id in range(51, 76):
		_expect_equal(
			renderer._background_texture_key(level_id),
			"stars3",
			"level %d resolves its declared third campaign background" % level_id
		)
	for level_id in range(76, 100):
		_expect_equal(
			renderer._background_texture_key(level_id),
			"stars4",
			"level %d resolves its declared fourth campaign background" % level_id
		)
	_expect_equal(
		renderer._background_texture_key(100),
		"stars1",
		"level 100 wraps to the retail first background"
	)
	_expect_equal(
		renderer._background_texture_key(101),
		"",
		"levels beyond the full campaign do not silently reuse a background"
	)
	_expect_equal(
		renderer.projectile_snapshot_source_rect({
			"owner_kind": "player",
			"projectile_kind": "rocket_missile",
			"sprite_sheet_id": "rocket",
			"heading": 32,
			"animation_row": 2,
			"source_rect": [744, 48, 24, 24],
		}),
		Rect2i(744, 48, 24, 24),
		"canonical rocket snapshots retain their aligned atlas source rectangle"
	)
	var rocket_expired_event := {
		"event_id": 3030,
		"type": "rocket_expired",
		"tick": 3,
		"effect_key": "flare4",
		"red": 144,
		"green": 160,
		"angle": 45.0,
		"speed": 3.0,
		"x_fp": 400 * 65536,
		"y_fp": 240 * 65536,
	}
	renderer.set_snapshot({
		"tick": 3,
		"phase": "level",
		"level_id": 30,
		"events": [rocket_expired_event],
	})
	_expect(
		renderer.active_effect_count() == 1
		and renderer.has_seen_effect_event(3030),
		"rocket expiry events enter the bounded presentation-effect pool"
	)
	renderer.set_snapshot({
		"tick": 4,
		"phase": "level",
		"level_id": 30,
		"events": [rocket_expired_event],
	})
	_expect_equal(
		renderer.active_effect_count(),
		1,
		"repeated rocket expiry snapshots do not duplicate the effect"
	)
	renderer.free()

	var screen := WBGameplayScreen.new()
	root.add_child(screen)
	await process_frame
	_expect_equal(
		screen.level_banner_text(11, ""),
		"LEVEL 11",
		"untitled levels do not render a stale subtitle"
	)
	_expect_equal(
		screen.level_banner_text(13, "DEJA VU....."),
		"LEVEL 13\nDEJA VU.....",
		"level banners consume the authoritative snapshot title"
	)
	_expect_equal(
		screen.level_banner_text(16, "* * *  B O N U S   L E V E L  * * *"),
		"LEVEL 16\n* * *  B O N U S   L E V E L  * * *",
		"the recurring bonus level preserves its authored title"
	)
	_expect_equal(
		screen.completion_heading(10),
		"FIRST TEN LEVELS CLEARED",
		"the terminal campaign result preserves the ten-level milestone"
	)
	_expect_equal(
		screen.completion_heading(20),
		"FIRST TWENTY LEVELS CLEARED",
		"the terminal campaign result names the twenty-level milestone"
	)
	_expect_equal(
		screen.completion_heading(25),
		"FIRST TWENTY-FIVE LEVELS CLEARED",
		"the terminal campaign result names the twenty-five-level milestone"
	)
	_expect_equal(
		screen.completion_heading(30),
		"FIRST THIRTY LEVELS CLEARED",
		"the terminal campaign result names the thirty-level milestone"
	)
	_expect_equal(
		screen.completion_heading(35),
		"FIRST THIRTY-FIVE LEVELS CLEARED",
		"the terminal campaign result names the thirty-five-level milestone"
	)
	_expect_equal(
		screen.completion_heading(49),
		"FIRST FORTY-NINE LEVELS CLEARED",
		"the terminal campaign result names the forty-nine-level milestone"
	)
	_expect_equal(
		screen.completion_heading(50),
		"FIRST FIFTY LEVELS CLEARED",
		"the compatibility campaign result retains the fifty-level milestone"
	)
	_expect_equal(
		screen.completion_heading(62),
		"FIRST SIXTY-TWO LEVELS CLEARED",
		"the explicit compatibility result retains the sixty-two-level milestone"
	)
	_expect_equal(
		screen.completion_heading(99),
		"LEVEL 99 CLEARED",
		"late explicit compatibility boundaries use generic completion copy"
	)
	_expect_equal(
		screen.completion_heading(100),
		"ALL 100 LEVELS CLEARED",
		"the default terminal result names the complete campaign"
	)
	screen.free()

	if _failures.is_empty():
		print("LEVEL-TWENTY PRESENTATION TESTS PASSED")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("LEVEL-TWENTY PRESENTATION TESTS FAILED: %d" % _failures.size())
	quit(1)


func _test_enemy_projectile_broad_bounds() -> void:
	var expected := {
		7: {
			"alien001": [0, 0, 5, 13],
			"alien_2": [0, 0, 3, 11],
			"alien_3": [0, 0, 5, 12],
			"alien000": [0, 0, 7, 13],
			"alien_lilla": [0, 0, 5, 9],
		},
		6: {
			"alien001": [0, 1, 11, 12],
			"alien_2": [2, 2, 9, 9],
			"alien_3": [0, 0, 31, 12],
			"alien000": [0, 0, 13, 16],
			"alien_lilla": [0, 0, 11, 11],
		},
	}
	var catalog := SpriteFrameCatalog.new()
	_expect(catalog.load_file(), "sprite catalog should load broad-phase contracts")
	for type_id in expected:
		for sheet_id in expected[type_id]:
			_expect_equal(
				catalog.enemy_projectile_broad_bounds(type_id, sheet_id),
				expected[type_id][sheet_id],
				"type-%d %s broad bounds match retail metadata" % [type_id, sheet_id]
			)
	_expect(
		catalog.enemy_projectile_broad_bounds(5, "alien001").is_empty()
		and catalog.last_error.contains("unknown enemy projectile type"),
		"unknown projectile types return an explicit catalog error"
	)
	_expect(
		catalog.enemy_projectile_broad_bounds(7, "missing").is_empty()
		and catalog.last_error.contains("unknown enemy projectile sheet"),
		"unknown projectile sheets return an explicit catalog error"
	)

	var file := FileAccess.open("res://content/sprite_frames.json", FileAccess.READ)
	var parser := JSON.new()
	_expect(file != null and parser.parse(file.get_as_text()) == OK, "sprite catalog fixture parses")
	if file == null or typeof(parser.data) != TYPE_DICTIONARY:
		return
	var missing_sheet: Dictionary = (parser.data as Dictionary).duplicate(true)
	missing_sheet.enemy_projectile_contracts.ordinary_type_7.sheet_masks.erase("alien_lilla")
	var invalid := SpriteFrameCatalog.new()
	_expect(
		not invalid.configure(missing_sheet)
		and invalid.last_error.contains("cover all enemy sheets"),
		"catalog validation rejects incomplete broad-phase sheet coverage"
	)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failures.append("%s (expected %s, got %s)" % [message, expected, actual])

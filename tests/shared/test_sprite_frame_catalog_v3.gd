extends SceneTree

const SpriteFrameCatalog := preload("res://src/shared/sprite_frame_catalog.gd")

const LEGACY_SHEETS := [
	"alien001",
	"alien_2",
	"alien_3",
	"alien000",
	"alien_lilla",
]
const V3_SHEETS := [
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
]
const V4_SHEETS := [
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
]
const V5_SHEETS := [
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
]
const V6_SHEETS := [
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
]
const V7_SHEETS := [
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
]

var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var catalog := SpriteFrameCatalog.new()
	_expect(catalog.load_file(), "v11 sprite catalog loads: %s" % catalog.last_error)
	_expect_equal(catalog.enemy_sheet_for_level(21), "alien003", "legacy lookup aliases slot 1")
	_expect_equal(
		catalog.enemy_sheet_for_resource(21, 2),
		"alien003_3",
		"level 21 slot 2 resolves independently"
	)
	_expect_equal(
		catalog.enemy_sheets_for_level(23),
		["alien003", "alien003_3"],
		"level 23 preserves ordered resource bindings"
	)
	_expect_equal(
		catalog.enemy_sheets_for_level(25),
		[
			"alien_big1_1",
			"alien_big1_2",
			"alien_big1_3",
			"alien_big1_4",
			"alien_big1_5",
			"alien_big1_6",
		],
		"level 25 exposes all six authored boss sheets"
	)
	_expect_equal(catalog.enemy_sheet_for_resource(21, 3), "", "missing slots fail closed")
	_expect_equal(
		catalog.enemy_sheets_for_level(28),
		["alien_rakett", "alien_rakett_gronn"],
		"level 28 preserves both rocket resource bindings"
	)
	_expect_equal(
		catalog.enemy_sheets_for_level(30),
		["alien_baller", "alien_baller2"],
		"level 30 preserves both baller resource bindings"
	)
	_expect_equal(
		catalog.enemy_sheets_for_level(35),
		["alien_green_lilla_t", "alien_cyan_lilla_t"],
		"level 35 preserves both green/cyan resource bindings"
	)
	_expect_equal(
		catalog.enemy_sheets_for_level(36),
		["alien_green_lilla_t", "alien_cyan_lilla_t"],
		"level 36 reuses both green/cyan resource bindings"
	)
	_expect_equal(
		catalog.enemy_sheets_for_level(39),
		["alien_raudkule", "alien_raudkule2"],
		"level 39 preserves both RaudKule resource bindings"
	)
	_expect_equal(
		catalog.enemy_sheets_for_level(44),
		["alien_blavinger_gf", "alien_blavinger_gf2"],
		"level 44 preserves both Blavinger resource bindings"
	)
	_expect_equal(
		catalog.enemy_sheets_for_level(49),
		["alien_rbille"],
		"level 49 preserves its RBille resource binding"
	)
	_expect_equal(
		catalog.enemy_sheets_for_level(50),
		[
			"alien_big2_1",
			"alien_big2_2",
			"alien_big2_3",
			"alien_big2_4",
			"alien_big2_5",
			"alien_big2_6",
		],
		"level 50 exposes all six authored big2 boss sheets"
	)
	_expect_equal(
		catalog.enemy_sheets_for_level(53),
		["alien_gultop", "alien_lillatop"],
		"level 53 preserves both top-family resource bindings"
	)
	_expect_equal(
		catalog.enemy_sheets_for_level(54),
		["alien_gultop", "alien_rakett_gronn"],
		"level 54 reuses the authored green-rocket resource"
	)
	_expect_equal(
		catalog.enemy_sheets_for_level(57),
		["alien_bluekreps", "alien_lbluekreps", "alien_brownkreps"],
		"level 57 exposes the resource-selector-three brown Kreps sheet"
	)
	_expect_equal(
		catalog.enemy_sheets_for_level(58),
		["alien_brownkreps2", "alien_gulkreps"],
		"level 58 preserves both mode-three Kreps resource bindings"
	)
	_expect_equal(
		catalog.enemy_sheets_for_level(60),
		["alien_rvinggk", "alien_gvingbk"],
		"level 60 preserves both wing-family resource bindings"
	)
	_expect_equal(
		catalog.enemy_sheets_for_level(62),
		["alien_gvingbk"],
		"level 62 exposes its authored green-wing resource binding"
	)
	_expect_equal(
		catalog.enemy_sheets_for_level(75),
		[
			"alien_big3_1", "alien_big3_2", "alien_big3_3",
			"alien_big3_4", "alien_big3_5", "alien_big3_6",
		],
		"level 75 exposes all six authored Big3 boss sheets"
	)
	_expect_equal(
		catalog.enemy_sheets_for_level(98),
		["alien_kuler", "alien_kuleo", "alien_mkuler", "alien_kulel"],
		"level 98 preserves its four ordered late-campaign resources"
	)
	_expect_equal(
		catalog.enemy_sheets_for_level(100),
		[
			"alien_big4_1", "alien_big4_2", "alien_big4_3",
			"alien_big4_4", "alien_big4_5", "alien_big4_6",
		],
		"level 100 exposes all six authored Big4 boss sheets"
	)
	_expect_equal(
		catalog.enemy_projectile_broad_bounds(6, "alien_raudkule2"),
		[0, 0, 17, 17],
		"RaudKule2 supplemental broad bounds stay anchored to its occupied phase zero"
	)
	_expect_equal(
		catalog.enemy_projectile_broad_bounds(7, "alien_rbille"),
		[0, 0, 7, 7],
		"RBille ordinary projectile bounds retain their exact HMA extent"
	)
	_expect_equal(
		catalog.enemy_projectile_broad_bounds(7, "alien_mkuler"),
		[],
		"MKuler's two SHA-pinned ordinary projectile cells remain exactly empty"
	)
	var big_sheet := catalog.enemy_sheet_definition("alien_big2_6")
	_expect_equal(big_sheet.get("sheet_width"), 576, "sheet lookup exposes image width")
	_expect_equal(big_sheet.get("sheet_height"), 96, "sheet lookup exposes image height")
	var mask_definitions := catalog.hit_mask_definitions()
	_expect_equal(mask_definitions.size(), 98, "all enemy sheets expose HMA definitions")
	for definition in mask_definitions:
		_expect_equal(definition.get("image_width"), 576, "HMA image width is validated")
		_expect_equal(definition.get("image_height"), 96, "HMA image height is validated")
		_expect_equal(definition.get("frame_width"), 576, "HMA frame width is validated")
		_expect_equal(definition.get("frame_height"), 96, "HMA frame height is validated")
		_expect(not String(definition.get("path", "")).is_empty(), "HMA path is declared")
		_expect_equal(
			String(definition.get("sha256", "")).length(),
			64,
			"HMA definitions retain their pinned collision digest"
		)

	var document := _load_document()
	if not document.is_empty():
		_test_v2_compatibility(document)
		_test_v3_compatibility(document)
		_test_v4_compatibility(document)
		_test_v5_compatibility(document)
		_test_v6_compatibility(document)
		_test_v7_compatibility(document)
		_test_v8_compatibility(document)
		_test_v10_resource_validation(document)

	if _failures.is_empty():
		print("SPRITE FRAME CATALOG V11 TESTS PASSED")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("SPRITE FRAME CATALOG V11 TESTS FAILED: %d" % _failures.size())
	quit(1)


func _load_document() -> Dictionary:
	var file := FileAccess.open("res://content/sprite_frames.json", FileAccess.READ)
	if file == null:
		_failures.append("sprite catalog fixture is readable")
		return {}
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK or typeof(parser.data) != TYPE_DICTIONARY:
		_failures.append("sprite catalog fixture parses")
		return {}
	return (parser.data as Dictionary).duplicate(true)


func _test_v2_compatibility(source: Dictionary) -> void:
	var legacy := source.duplicate(true)
	legacy.version = 2
	legacy.schema = "warblade.sprite-frames.v2"
	legacy.enemy_sheets = (legacy.enemy_sheets as Array).slice(0, 5)
	legacy.level_usage = (legacy.level_usage as Array).slice(0, 20)
	for usage_value in legacy.level_usage:
		(usage_value as Dictionary).erase("enemy_resources")
	for contract_id in legacy.enemy_projectile_contracts:
		var sheet_masks: Dictionary = legacy.enemy_projectile_contracts[contract_id].sheet_masks
		for sheet_id in sheet_masks.keys():
			if not LEGACY_SHEETS.has(sheet_id):
				sheet_masks.erase(sheet_id)
	var catalog := SpriteFrameCatalog.new()
	_expect(catalog.configure(legacy), "legacy v2 sprite catalog remains readable: %s" % catalog.last_error)
	_expect_equal(catalog.enemy_sheet_ids(), LEGACY_SHEETS, "v2 retains its five sheets")
	_expect_equal(catalog.enemy_sheet_for_level(13), "alien000", "v2 level alias is unchanged")
	_expect_equal(
		catalog.enemy_sheet_for_resource(13, 1),
		"alien000",
		"v2 synthesizes the slot-1 resource lookup"
	)


func _test_v3_compatibility(source: Dictionary) -> void:
	var v3 := source.duplicate(true)
	v3.version = 3
	v3.schema = "warblade.sprite-frames.v3"
	v3.enemy_sheets = (v3.enemy_sheets as Array).slice(0, 13)
	v3.level_usage = (v3.level_usage as Array).slice(0, 25)
	for contract_id in v3.enemy_projectile_contracts:
		var sheet_masks: Dictionary = v3.enemy_projectile_contracts[contract_id].sheet_masks
		for sheet_id in sheet_masks.keys():
			if not V3_SHEETS.has(sheet_id):
				sheet_masks.erase(sheet_id)
	var catalog := SpriteFrameCatalog.new()
	_expect(catalog.configure(v3), "v3 sprite catalog remains readable: %s" % catalog.last_error)
	_expect_equal(catalog.enemy_sheet_ids(), V3_SHEETS, "v3 retains its thirteen sheets")
	_expect_equal(
		catalog.enemy_sheets_for_level(25),
		[
			"alien_big1_1",
			"alien_big1_2",
			"alien_big1_3",
			"alien_big1_4",
			"alien_big1_5",
			"alien_big1_6",
		],
		"v3 preserves the level-25 resource set"
	)


func _test_v4_compatibility(source: Dictionary) -> void:
	var v4 := source.duplicate(true)
	v4.version = 4
	v4.schema = "warblade.sprite-frames.v4"
	v4.enemy_sheets = (v4.enemy_sheets as Array).slice(0, 17)
	v4.level_usage = (v4.level_usage as Array).slice(0, 30)
	v4.supplemental_spawn_linkages = (
		v4.supplemental_spawn_linkages as Array
	).slice(0, 7)
	for contract_id in v4.enemy_projectile_contracts:
		var sheet_masks: Dictionary = v4.enemy_projectile_contracts[contract_id].sheet_masks
		for sheet_id in sheet_masks.keys():
			if not V4_SHEETS.has(sheet_id):
				sheet_masks.erase(sheet_id)
	var catalog := SpriteFrameCatalog.new()
	_expect(catalog.configure(v4), "v4 sprite catalog remains readable: %s" % catalog.last_error)
	_expect_equal(catalog.enemy_sheet_ids(), V4_SHEETS, "v4 retains its seventeen sheets")
	_expect_equal(
		catalog.enemy_sheets_for_level(30),
		["alien_baller", "alien_baller2"],
		"v4 preserves the level-30 resource set"
	)


func _test_v5_compatibility(source: Dictionary) -> void:
	var v5 := source.duplicate(true)
	v5.version = 5
	v5.schema = "warblade.sprite-frames.v5"
	v5.enemy_sheets = (v5.enemy_sheets as Array).slice(0, 19)
	v5.level_usage = (v5.level_usage as Array).slice(0, 35)
	v5.supplemental_spawn_linkages = (
		v5.supplemental_spawn_linkages as Array
	).slice(0, 8)
	for contract_id in v5.enemy_projectile_contracts:
		var sheet_masks: Dictionary = v5.enemy_projectile_contracts[contract_id].sheet_masks
		for sheet_id in sheet_masks.keys():
			if not V5_SHEETS.has(sheet_id):
				sheet_masks.erase(sheet_id)
	var catalog := SpriteFrameCatalog.new()
	_expect(catalog.configure(v5), "v5 sprite catalog remains readable: %s" % catalog.last_error)
	_expect_equal(catalog.enemy_sheet_ids(), V5_SHEETS, "v5 retains its nineteen sheets")
	_expect_equal(
		catalog.enemy_sheets_for_level(35),
		["alien_green_lilla_t", "alien_cyan_lilla_t"],
		"v5 preserves the level-35 resource set"
	)


func _test_v6_compatibility(source: Dictionary) -> void:
	var v6 := source.duplicate(true)
	v6.version = 6
	v6.schema = "warblade.sprite-frames.v6"
	v6.enemy_sheets = (v6.enemy_sheets as Array).slice(0, 24)
	v6.level_usage = (v6.level_usage as Array).slice(0, 49)
	for contract_id in v6.enemy_projectile_contracts:
		var sheet_masks: Dictionary = v6.enemy_projectile_contracts[contract_id].sheet_masks
		for sheet_id in sheet_masks.keys():
			if not V6_SHEETS.has(sheet_id):
				sheet_masks.erase(sheet_id)
	var catalog := SpriteFrameCatalog.new()
	_expect(catalog.configure(v6), "v6 sprite catalog remains readable: %s" % catalog.last_error)
	_expect_equal(catalog.enemy_sheet_ids(), V6_SHEETS, "v6 retains its twenty-four sheets")
	_expect_equal(
		catalog.enemy_sheets_for_level(49),
		["alien_rbille"],
		"v6 preserves the level-49 resource set"
	)


func _test_v7_compatibility(source: Dictionary) -> void:
	var v7 := source.duplicate(true)
	v7.version = 7
	v7.schema = "warblade.sprite-frames.v7"
	v7.enemy_sheets = (v7.enemy_sheets as Array).slice(0, 30)
	v7.level_usage = (v7.level_usage as Array).slice(0, 50)
	v7.supplemental_spawn_linkages = (
		v7.supplemental_spawn_linkages as Array
	).slice(0, 13)
	for contract_id in v7.enemy_projectile_contracts:
		var sheet_masks: Dictionary = v7.enemy_projectile_contracts[contract_id].sheet_masks
		for sheet_id in sheet_masks.keys():
			if not V7_SHEETS.has(sheet_id):
				sheet_masks.erase(sheet_id)
	var catalog := SpriteFrameCatalog.new()
	_expect(catalog.configure(v7), "v7 sprite catalog remains readable: %s" % catalog.last_error)
	_expect_equal(catalog.enemy_sheet_ids(), V7_SHEETS, "v7 retains its thirty sheets")
	_expect_equal(
		catalog.enemy_sheets_for_level(50),
		[
			"alien_big2_1",
			"alien_big2_2",
			"alien_big2_3",
			"alien_big2_4",
			"alien_big2_5",
			"alien_big2_6",
		],
		"v7 preserves the level-50 resource set"
	)


func _test_v8_compatibility(source: Dictionary) -> void:
	var v8 := source.duplicate(true)
	v8.version = 8
	v8.schema = "warblade.sprite-frames.v8"
	v8.enemy_sheets = (v8.enemy_sheets as Array).slice(0, 39)
	v8.level_usage = (v8.level_usage as Array).slice(0, 62)
	v8.supplemental_spawn_linkages = (
		v8.supplemental_spawn_linkages as Array
	).slice(0, 17)
	for contract_id in v8.enemy_projectile_contracts:
		var sheet_masks: Dictionary = v8.enemy_projectile_contracts[contract_id].sheet_masks
		for sheet_id in sheet_masks.keys():
			if not SpriteFrameCatalog.V8_ENEMY_SHEET_IDS.has(String(sheet_id)):
				sheet_masks.erase(sheet_id)
	var catalog := SpriteFrameCatalog.new()
	_expect(catalog.configure(v8), "v8 sprite catalog remains readable: %s" % catalog.last_error)
	_expect_equal(
		catalog.enemy_sheet_ids(),
		SpriteFrameCatalog.V8_ENEMY_SHEET_IDS,
		"v8 retains its thirty-nine sheets"
	)


func _test_v10_resource_validation(source: Dictionary) -> void:
	var invalid := source.duplicate(true)
	(invalid.level_usage[20].enemy_resources as Array).remove_at(0)
	var catalog := SpriteFrameCatalog.new()
	_expect(
		not catalog.configure(invalid)
		and catalog.last_error.contains("ordered contiguous slots"),
		"v10 rejects a missing leading resource binding"
	)
	var changed_hma_pin := source.duplicate(true)
	for asset_value in changed_hma_pin.hit_mask_format.assets:
		var asset := asset_value as Dictionary
		if String(asset.get("id", "")) == "alien_green_lilla_t":
			asset.hit_mask_sha256 = "0".repeat(64)
	var changed_hma_catalog := SpriteFrameCatalog.new()
	_expect(
		changed_hma_catalog.configure(changed_hma_pin),
		"a structurally valid replacement digest remains loadable until its bytes are checked"
	)
	if changed_hma_catalog.last_error.is_empty():
		var definitions := changed_hma_catalog.hit_mask_definitions().filter(
			func(definition: Dictionary) -> bool:
				return String(definition.get("id", "")) == "alien_green_lilla_t"
		)
		_expect_equal(definitions.size(), 1, "the changed HMA definition remains addressable")
		if definitions.is_empty():
			return
		_expect_equal(
			definitions[0].get("sha256"),
			"0".repeat(64),
			"the runtime definition carries the declared digest into HMA loading"
		)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failures.append("%s (expected %s, got %s)" % [message, expected, actual])

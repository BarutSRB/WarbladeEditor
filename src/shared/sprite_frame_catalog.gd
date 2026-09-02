class_name WBSpriteFrameCatalog
extends RefCounted

const DEFAULT_PATH := "res://content/sprite_frames.json"
const LEGACY_ENEMY_SHEET_IDS: Array[String] = [
	"alien001",
	"alien_2",
	"alien_3",
	"alien000",
	"alien_lilla",
]
const V3_ENEMY_SHEET_IDS: Array[String] = [
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
const V4_ENEMY_SHEET_IDS: Array[String] = [
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
const V5_ENEMY_SHEET_IDS: Array[String] = [
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
const V6_ENEMY_SHEET_IDS: Array[String] = [
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
const V7_ENEMY_SHEET_IDS: Array[String] = [
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
const V8_ENEMY_SHEET_IDS: Array[String] = [
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
]
const V10_ENEMY_SHEET_IDS: Array[String] = V8_ENEMY_SHEET_IDS + [
	"alien_lila_royr",
	"alien_lblaa_royr",
	"alien_lilla_makk",
	"alien_lblaa_makk",
	"alien_rocktalien",
	"alien_rocktalieng",
	"alien_big3_1",
	"alien_big3_2",
	"alien_big3_3",
	"alien_big3_4",
	"alien_big3_5",
	"alien_big3_6",
	"alien_gspis",
	"alien_rspis",
	"alien001_gul",
	"alien001_raud",
	"alien001_blue",
	"alien002",
	"alien_lysper2",
	"alien_lysper",
	"alien_n1_bla",
	"alien_n1_gron",
	"alien_n1_lilla",
	"alien_n2_bla",
	"alien_n2_red",
	"alien_n2_green",
	"alien_metaballs",
	"alien_metaball2",
	"alien_metaball3",
	"alien_kuler",
	"alien_kuleg",
	"alien_kuleb",
	"alien_kuleo",
	"alien_kulel",
	"alien_mkuler",
	"alien_big4_1",
	"alien_big4_2",
	"alien_big4_3",
	"alien_big4_4",
	"alien_big4_5",
	"alien_big4_6",
]
# The v11 catalog adds the eighteen sheets that only retail match mode 6 binds,
# in the first-appearance order of timetrial_01 through timetrial_15.
const TIME_TRIAL_ENEMY_SHEET_IDS: Array[String] = [
	"alien_timetrial_1",
	"alien_timetrial_3k",
	"alien_timetrial_2",
	"alien3",
	"alien_timetrial_3",
	"alien_timetrial_3b",
	"alien_timetrial_3c",
	"alien_10_green",
	"alien_10",
	"alien_10_lilla",
	"alien_12",
	"alien_12_blue",
	"alien_12_red",
	"alien_11",
	"alien_11_gul",
	"alien_13",
	"alien_13_orange",
	"alien002_cyan",
]
const EXPECTED_ENEMY_SHEET_IDS: Array[String] = (
	V10_ENEMY_SHEET_IDS + TIME_TRIAL_ENEMY_SHEET_IDS
)
const TIME_TRIAL_EMPTY_SUPPLEMENTAL_SHEET_IDS: Array[String] = [
	"alien_10",
	"alien_10_green",
	"alien_10_lilla",
	"alien_11",
	"alien_11_gul",
	"alien_12",
	"alien_12_blue",
	"alien_12_red",
	"alien_13",
	"alien_13_orange",
]
const TIME_TRIAL_LEVEL_COUNT: int = 15
const LEVEL_NAMESPACE_TIME_TRIAL: String = "time_trial"
const CATALOG_LEVEL_COUNTS := {
	2: 20,
	3: 25,
	4: 30,
	5: 35,
	6: 49,
	7: 50,
	8: 62,
	9: 100,
	10: 100,
	11: 100,
}

var last_error := ""

var _direction_ranges: Array = []
var _direction_mirror: Array = []
var _enemy_families: Dictionary = {}
var _projectile_rects: Dictionary = {}
var _projectile_next: Dictionary = {}
var _projectile_persistent: Dictionary = {}
var _level_enemy_sheets: Dictionary = {}
var _level_enemy_resources: Dictionary = {}
var _time_trial_level_enemy_sheets: Dictionary = {}
var _time_trial_level_enemy_resources: Dictionary = {}
var _enemy_sheet_ids: Array[String] = []
var _enemy_sheet_definitions: Dictionary = {}
var _hit_mask_definitions: Array[Dictionary] = []
var _enemy_projectile_broad_bounds: Dictionary = {}
var _fighter_frame_width := 40
var _fighter_frame_height := 27
var _fighter_frame_count := 11


func load_file(path: String = DEFAULT_PATH) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _fail("cannot read sprite-frame catalog")
	var json := JSON.new()
	var parse_error := json.parse(file.get_as_text())
	if parse_error != OK:
		return _fail(
			"sprite-frame catalog line %d: %s"
			% [json.get_error_line(), json.get_error_message()]
		)
	if typeof(json.data) != TYPE_DICTIONARY:
		return _fail("sprite-frame catalog must be an object")
	return configure(json.data)


func configure(document: Dictionary) -> bool:
	last_error = ""
	_direction_ranges.clear()
	_direction_mirror.clear()
	_enemy_families.clear()
	_projectile_rects.clear()
	_projectile_next.clear()
	_projectile_persistent.clear()
	_level_enemy_sheets.clear()
	_level_enemy_resources.clear()
	_time_trial_level_enemy_sheets.clear()
	_time_trial_level_enemy_resources.clear()
	_enemy_sheet_ids.clear()
	_enemy_sheet_definitions.clear()
	_hit_mask_definitions.clear()
	_enemy_projectile_broad_bounds.clear()
	var catalog_version := int(document.get("version", 0))
	var catalog_schema := String(document.get("schema", ""))
	if not CATALOG_LEVEL_COUNTS.has(catalog_version):
		return _fail("unsupported sprite-frame catalog version")
	if catalog_schema != "warblade.sprite-frames.v%d" % catalog_version:
		return _fail("unsupported sprite-frame catalog schema")
	if catalog_version >= 10 and not _state_ten_contract_is_exact(document):
		return _fail("sprite-frame catalog state-10 frame producer is invalid")
	var enemy_layout: Variant = document.get("enemy_frame_layout")
	if typeof(enemy_layout) != TYPE_DICTIONARY:
		return _fail("sprite-frame catalog is missing enemy layout")
	_direction_ranges = (enemy_layout as Dictionary).get("direction_slope_ranges", [])
	_direction_mirror = (enemy_layout as Dictionary).get("mirror_index_table", [])
	var families: Variant = (enemy_layout as Dictionary).get("families")
	if typeof(families) != TYPE_DICTIONARY:
		return _fail("sprite-frame catalog is missing enemy frame families")
	for family_id in (families as Dictionary):
		var family: Variant = (families as Dictionary)[family_id]
		if typeof(family) != TYPE_DICTIONARY:
			return _fail("enemy frame family must be an object")
		var frames: Variant = (family as Dictionary).get("frames")
		if typeof(frames) != TYPE_ARRAY or (frames as Array).is_empty():
			return _fail("enemy frame family must contain frames")
		var rects: Array[Rect2i] = []
		for frame_value in frames:
			if typeof(frame_value) != TYPE_DICTIONARY:
				return _fail("enemy frame entry must be an object")
			var rect_result := _parse_rect((frame_value as Dictionary).get("source_rect"))
			if not bool(rect_result.ok):
				return _fail(String(rect_result.error))
			rects.append(rect_result.value)
		_enemy_families[String(family_id)] = rects
	var expected_family_sizes := {
		"directional_32": 16,
		"formation_animation_32": 6,
		"supplemental_large_animation_64": 7,
	}
	for family_id in expected_family_sizes:
		if (
			not _enemy_families.has(family_id)
			or (_enemy_families[family_id] as Array).size() != int(expected_family_sizes[family_id])
		):
			return _fail("enemy frame family %s has an unexpected size" % family_id)
	if _direction_ranges.size() != 9 or _direction_mirror.size() != 16:
		return _fail("enemy direction tables have unexpected sizes")
	var projectile_sheet: Variant = document.get("projectile_sheet")
	if typeof(projectile_sheet) != TYPE_DICTIONARY:
		return _fail("sprite-frame catalog is missing projectile sheet")
	var projectile_frames: Variant = (projectile_sheet as Dictionary).get("frames")
	if typeof(projectile_frames) != TYPE_ARRAY:
		return _fail("sprite-frame catalog is missing projectile frames")
	for frame_value in projectile_frames:
		if typeof(frame_value) != TYPE_DICTIONARY:
			return _fail("projectile frame entry must be an object")
		var frame := frame_value as Dictionary
		var rect_result := _parse_rect(frame.get("source_rect"))
		if not bool(rect_result.ok):
			return _fail(String(rect_result.error))
		var prototype_id := int(frame.get("prototype_id", -1))
		_projectile_rects[prototype_id] = rect_result.value
		_projectile_next[prototype_id] = int(frame.get("next_prototype_id", prototype_id))
		_projectile_persistent[prototype_id] = bool(frame.get("persistent", false))
	var fighter_sheets: Variant = document.get("fighter_sheets")
	if typeof(fighter_sheets) != TYPE_ARRAY or (fighter_sheets as Array).size() != 2:
		return _fail("sprite-frame catalog must contain two fighter sheets")
	var first_fighter: Dictionary = (fighter_sheets as Array)[0]
	_fighter_frame_width = int(first_fighter.get("frames", [])[0].source_rect.width)
	_fighter_frame_height = int(first_fighter.get("effective_frame_height", 0))
	_fighter_frame_count = int(first_fighter.get("frames", []).size())
	if _fighter_frame_width != 40 or _fighter_frame_height != 27 or _fighter_frame_count != 11:
		return _fail("fighter frame layout does not match the proven retail layout")
	var enemy_sheets: Variant = document.get("enemy_sheets")
	if typeof(enemy_sheets) != TYPE_ARRAY:
		return _fail("sprite-frame catalog is missing enemy sheets")
	var hit_mask_format: Variant = document.get("hit_mask_format")
	if not hit_mask_format is Dictionary:
		return _fail("sprite-frame catalog is missing hit-mask provenance")
	var hit_mask_assets: Variant = (hit_mask_format as Dictionary).get("assets")
	if not hit_mask_assets is Array:
		return _fail("sprite-frame catalog is missing hit-mask asset pins")
	var hit_mask_assets_by_id: Dictionary = {}
	for asset_value in hit_mask_assets as Array:
		if not asset_value is Dictionary:
			return _fail("hit-mask asset pin must be an object")
		var asset := asset_value as Dictionary
		var asset_id := String(asset.get("id", ""))
		if (
			asset_id.is_empty()
			or hit_mask_assets_by_id.has(asset_id)
			or not _is_lower_hex_sha256(String(asset.get("hit_mask_sha256", "")))
		):
			return _fail("hit-mask asset IDs and SHA-256 pins must be unique and complete")
		hit_mask_assets_by_id[asset_id] = asset.duplicate(true)
	for sheet_value in enemy_sheets as Array:
		if typeof(sheet_value) != TYPE_DICTIONARY:
			return _fail("enemy sheet entry must be an object")
		var sheet := sheet_value as Dictionary
		var sheet_id := String(sheet.get("id", ""))
		if sheet_id.is_empty() or _enemy_sheet_ids.has(sheet_id):
			return _fail("enemy sheet IDs must be nonempty and unique")
		if int(sheet.get("sheet_width", 0)) != 576 or int(sheet.get("sheet_height", 0)) != 96:
			return _fail("enemy sheet geometry must be 576x96")
		if String(sheet.get("texture", "")).is_empty() or String(sheet.get("hit_mask", "")).is_empty():
			return _fail("enemy sheet resources must be declared")
		if not hit_mask_assets_by_id.has(sheet_id):
			return _fail("enemy sheet hit-mask SHA-256 must be pinned")
		var hit_mask_asset := hit_mask_assets_by_id[sheet_id] as Dictionary
		var hit_mask_sha256 := String(hit_mask_asset.hit_mask_sha256)
		if String(hit_mask_asset.get("hit_mask", "")) != String(sheet.hit_mask):
			return _fail("enemy sheet hit-mask path differs from its pinned asset")
		var frame_width := int(sheet.get("frame_width", sheet.get("sheet_width", 0)))
		var frame_height := int(sheet.get("frame_height", sheet.get("sheet_height", 0)))
		if frame_width != 576 or frame_height != 96:
			return _fail("enemy HMA frame geometry must be 576x96")
		_enemy_sheet_ids.append(sheet_id)
		_enemy_sheet_definitions[sheet_id] = sheet.duplicate(true)
		_hit_mask_definitions.append(
			{
				"id": sheet_id,
				"path": String(sheet.hit_mask),
				"sha256": hit_mask_sha256,
				"image_width": int(sheet.sheet_width),
				"image_height": int(sheet.sheet_height),
				"frame_width": frame_width,
				"frame_height": frame_height,
			}
		)
	if catalog_version == 2:
		if _enemy_sheet_ids != LEGACY_ENEMY_SHEET_IDS:
			return _fail("legacy sprite-frame catalog enemy sheet order is unsupported")
	elif catalog_version == 3:
		if _enemy_sheet_ids != V3_ENEMY_SHEET_IDS:
			return _fail("v3 sprite-frame catalog enemy sheet order is unsupported")
	elif catalog_version == 4:
		if _enemy_sheet_ids != V4_ENEMY_SHEET_IDS:
			return _fail("v4 sprite-frame catalog enemy sheet order is unsupported")
	elif catalog_version == 5:
		if _enemy_sheet_ids != V5_ENEMY_SHEET_IDS:
			return _fail("v5 sprite-frame catalog enemy sheet order is unsupported")
	elif catalog_version == 6:
		if _enemy_sheet_ids != V6_ENEMY_SHEET_IDS:
			return _fail("v6 sprite-frame catalog enemy sheet order is unsupported")
	elif catalog_version == 7:
		if _enemy_sheet_ids != V7_ENEMY_SHEET_IDS:
			return _fail("v7 sprite-frame catalog enemy sheet order is unsupported")
	elif catalog_version == 8:
		if _enemy_sheet_ids != V8_ENEMY_SHEET_IDS:
			return _fail("v8 sprite-frame catalog enemy sheet order is unsupported")
	elif catalog_version <= 10:
		if _enemy_sheet_ids != V10_ENEMY_SHEET_IDS:
			return _fail("v%d sprite-frame catalog enemy sheet order is unsupported" % catalog_version)
	elif _enemy_sheet_ids != EXPECTED_ENEMY_SHEET_IDS:
		return _fail("sprite-frame catalog enemy sheet order is unsupported")
	var level_usage: Variant = document.get("level_usage")
	if typeof(level_usage) != TYPE_ARRAY:
		return _fail("sprite-frame catalog is missing level usage")
	var expected_level_count := int(CATALOG_LEVEL_COUNTS[catalog_version])
	if (level_usage as Array).size() != expected_level_count:
		return _fail(
			"sprite-frame catalog must contain %d level usage records"
			% expected_level_count
		)
	for usage_value in level_usage:
		if typeof(usage_value) != TYPE_DICTIONARY:
			return _fail("level sprite usage must be an object")
		var usage := usage_value as Dictionary
		var level_id := int(usage.get("level_id", 0))
		var sheet_id := String(usage.get("enemy_sheet_id", ""))
		if level_id != _level_enemy_sheets.size() + 1:
			return _fail(
				"sprite-frame level usage must be ordered from 1 through %d"
				% expected_level_count
			)
		if not _enemy_sheet_ids.has(sheet_id):
			return _fail("level sprite usage references an unknown enemy sheet")
		_level_enemy_sheets[level_id] = sheet_id
		var resource_sheets: Dictionary = {}
		if catalog_version == 2:
			resource_sheets[1] = sheet_id
		else:
			var resources_value: Variant = usage.get("enemy_resources")
			if typeof(resources_value) != TYPE_ARRAY or (resources_value as Array).is_empty():
				return _fail("level sprite usage must contain enemy resources")
			for resource_value in resources_value as Array:
				if typeof(resource_value) != TYPE_DICTIONARY:
					return _fail("level enemy resource must be an object")
				var resource := resource_value as Dictionary
				var resource_slot_id := int(resource.get("resource_slot_id", 0))
				var resource_sheet_id := String(resource.get("enemy_sheet_id", ""))
				if resource_slot_id != resource_sheets.size() + 1:
					return _fail("level enemy resources must use ordered contiguous slots")
				if String(resource.get("raw_name", "")).is_empty():
					return _fail("level enemy resource raw name must be declared")
				if not resource.has("kill_score"):
					return _fail("level enemy resource kill score must be declared")
				if not _enemy_sheet_ids.has(resource_sheet_id):
					return _fail("level enemy resource references an unknown sheet")
				resource_sheets[resource_slot_id] = resource_sheet_id
			if String(resource_sheets.get(1, "")) != sheet_id:
				return _fail("level enemy sheet alias must match resource slot 1")
		_level_enemy_resources[level_id] = resource_sheets
	if catalog_version >= 11 and not _configure_time_trial_usage(document):
		return false
	var enemy_projectile_contracts: Variant = document.get("enemy_projectile_contracts")
	if typeof(enemy_projectile_contracts) != TYPE_DICTIONARY:
		return _fail("sprite-frame catalog is missing enemy projectile contracts")
	var expected_projectile_contracts := {
		"ordinary_type_7": 7,
		"supplemental_state_6_type_6": 6,
	}
	for contract_id in expected_projectile_contracts:
		var contract_value: Variant = (enemy_projectile_contracts as Dictionary).get(contract_id)
		if typeof(contract_value) != TYPE_DICTIONARY:
			return _fail("enemy projectile contract %s must be an object" % contract_id)
		var contract := contract_value as Dictionary
		var type_id := int(expected_projectile_contracts[contract_id])
		if int(contract.get("type_id", -1)) != type_id:
			return _fail("enemy projectile contract %s has an unexpected type" % contract_id)
		var sheet_masks_value: Variant = contract.get("sheet_masks")
		if typeof(sheet_masks_value) != TYPE_DICTIONARY:
			return _fail("enemy projectile contract %s is missing sheet masks" % contract_id)
		var sheet_masks := sheet_masks_value as Dictionary
		if sheet_masks.size() != _enemy_sheet_ids.size():
			return _fail(
				"enemy projectile contract %s must cover all enemy sheets"
				% contract_id
			)
		var bounds_by_sheet: Dictionary = {}
		for sheet_id in _enemy_sheet_ids:
			var sheet_value: Variant = sheet_masks.get(sheet_id)
			if typeof(sheet_value) != TYPE_DICTIONARY:
				return _fail(
					"enemy projectile contract %s is missing sheet %s"
					% [contract_id, sheet_id]
				)
			var sheet := sheet_value as Dictionary
			var exact_empty_ordinary_cells: bool = (
				catalog_version >= 9
				and contract_id == "ordinary_type_7"
				and sheet_id == "alien_mkuler"
			)
			if exact_empty_ordinary_cells:
				var empty_phases: Variant = sheet.get("phases")
				if (
					not sheet.has("retail_broad_phase_bounds")
					or sheet.get("retail_broad_phase_bounds") != null
					or not empty_phases is Array
					or (empty_phases as Array).size() != 2
				):
					return _fail("alien_mkuler ordinary projectile cells must remain exactly empty")
				for phase_value in empty_phases as Array:
					if (
						not phase_value is Dictionary
						or not (phase_value as Dictionary).has("local_inclusive_bounds")
						or not (phase_value as Dictionary).has("occupied_pixel_count")
						or (phase_value as Dictionary).get("local_inclusive_bounds") != null
						or int((phase_value as Dictionary).get("occupied_pixel_count", -1)) != 0
					):
						return _fail("alien_mkuler ordinary projectile phases must remain exactly empty")
				bounds_by_sheet[sheet_id] = []
				continue
			# Sheets that only Time Trial binds leave the supplemental state-6
			# projectile cell blank, because no Time Trial level carries a
			# supplemental spawn record. An exactly empty phase-zero cell has no
			# broad phase rather than an invalid one.
			if (
				catalog_version >= 11
				and contract_id == "supplemental_state_6_type_6"
				and TIME_TRIAL_EMPTY_SUPPLEMENTAL_SHEET_IDS.has(sheet_id)
			):
				if (
					not sheet.has("retail_broad_phase_bounds")
					or sheet.get("retail_broad_phase_bounds") != null
				):
					return _fail(
						"Time Trial sheet %s supplemental broad phase must be exactly empty"
						% sheet_id
					)
				var mode_six_phases: Variant = sheet.get("phases")
				if not mode_six_phases is Array or (mode_six_phases as Array).is_empty():
					return _fail(
						"Time Trial sheet %s must publish its projectile phases" % sheet_id
					)
				var mode_six_phase_zero: Variant = (mode_six_phases as Array)[0]
				if (
					not mode_six_phase_zero is Dictionary
					or (mode_six_phase_zero as Dictionary).get("local_inclusive_bounds") != null
					or int(
						(mode_six_phase_zero as Dictionary).get("occupied_pixel_count", -1)
					) != 0
				):
					return _fail(
						"Time Trial sheet %s projectile phase zero must be exactly empty"
						% sheet_id
					)
				bounds_by_sheet[sheet_id] = []
				continue
			var bounds_result := _parse_inclusive_bounds(sheet.get("retail_broad_phase_bounds"))
			if not bool(bounds_result.ok):
				return _fail(
					"enemy projectile contract %s sheet %s: %s"
					% [contract_id, sheet_id, String(bounds_result.error)]
				)
			var phases_value: Variant = sheet.get("phases")
			if typeof(phases_value) != TYPE_ARRAY or (phases_value as Array).is_empty():
				return _fail("enemy projectile contract sheet must contain phase data")
			var phase_zero_value: Variant = (phases_value as Array)[0]
			if typeof(phase_zero_value) != TYPE_DICTIONARY:
				return _fail("enemy projectile phase zero must be an object")
			var phase_zero_result := _parse_inclusive_bounds(
				(phase_zero_value as Dictionary).get("local_inclusive_bounds")
			)
			if not bool(phase_zero_result.ok):
				return _fail("enemy projectile phase-zero bounds are invalid")
			if bounds_result.value != phase_zero_result.value:
				return _fail("retail broad-phase bounds must equal phase-zero HMA bounds")
			bounds_by_sheet[sheet_id] = bounds_result.value
		_enemy_projectile_broad_bounds[type_id] = bounds_by_sheet
	return true


func _configure_time_trial_usage(document: Dictionary) -> bool:
	# Retail match mode 6 owns a separate fifteen-level namespace whose IDs
	# deliberately overlap the classic campaign, so it never shares the classic
	# usage table.
	var usage_value: Variant = document.get("time_trial_level_usage")
	if typeof(usage_value) != TYPE_ARRAY:
		return _fail("sprite-frame catalog is missing Time Trial level usage")
	var usage := usage_value as Array
	if usage.size() != TIME_TRIAL_LEVEL_COUNT:
		return _fail(
			"sprite-frame catalog must contain %d Time Trial level usage records"
			% TIME_TRIAL_LEVEL_COUNT
		)
	for usage_entry_value in usage:
		if typeof(usage_entry_value) != TYPE_DICTIONARY:
			return _fail("Time Trial sprite usage must be an object")
		var entry := usage_entry_value as Dictionary
		var level_id := int(entry.get("level_id", 0))
		var sheet_id := String(entry.get("enemy_sheet_id", ""))
		if level_id != _time_trial_level_enemy_sheets.size() + 1:
			return _fail(
				"Time Trial sprite usage must be ordered from 1 through %d"
				% TIME_TRIAL_LEVEL_COUNT
			)
		if not _enemy_sheet_ids.has(sheet_id):
			return _fail("Time Trial sprite usage references an unknown enemy sheet")
		_time_trial_level_enemy_sheets[level_id] = sheet_id
		var resource_sheets: Dictionary = {}
		var resources_value: Variant = entry.get("enemy_resources")
		if typeof(resources_value) != TYPE_ARRAY or (resources_value as Array).is_empty():
			return _fail("Time Trial sprite usage must contain enemy resources")
		for resource_value in resources_value as Array:
			if typeof(resource_value) != TYPE_DICTIONARY:
				return _fail("Time Trial enemy resource must be an object")
			var resource := resource_value as Dictionary
			var resource_slot_id := int(resource.get("resource_slot_id", 0))
			var resource_sheet_id := String(resource.get("enemy_sheet_id", ""))
			if resource_slot_id != resource_sheets.size() + 1:
				return _fail("Time Trial enemy resources must use ordered contiguous slots")
			if String(resource.get("raw_name", "")).is_empty():
				return _fail("Time Trial enemy resource raw name must be declared")
			if not resource.has("kill_score"):
				return _fail("Time Trial enemy resource kill score must be declared")
			if not _enemy_sheet_ids.has(resource_sheet_id):
				return _fail("Time Trial enemy resource references an unknown sheet")
			resource_sheets[resource_slot_id] = resource_sheet_id
		if String(resource_sheets.get(1, "")) != sheet_id:
			return _fail("Time Trial enemy sheet alias must match resource slot 1")
		_time_trial_level_enemy_resources[level_id] = resource_sheets
	return true


func _resources_for(level_id: int, level_namespace: String) -> Dictionary:
	var source := (
		_time_trial_level_enemy_resources
		if level_namespace == LEVEL_NAMESPACE_TIME_TRIAL
		else _level_enemy_resources
	)
	var resources_value: Variant = source.get(level_id)
	if typeof(resources_value) != TYPE_DICTIONARY:
		return {}
	return resources_value as Dictionary


func enemy_sheet_for_level(level_id: int, level_namespace: String = "") -> String:
	return enemy_sheet_for_resource(level_id, 1, level_namespace)


func enemy_sheet_for_resource(
	level_id: int,
	resource_slot_id: int,
	level_namespace: String = ""
) -> String:
	return String(_resources_for(level_id, level_namespace).get(resource_slot_id, ""))


func enemy_sheets_for_level(
	level_id: int,
	level_namespace: String = ""
) -> Array[String]:
	var result: Array[String] = []
	var resources := _resources_for(level_id, level_namespace)
	for resource_slot_id in range(1, resources.size() + 1):
		result.append(String(resources.get(resource_slot_id, "")))
	return result


func enemy_sheet_definition(id: String) -> Dictionary:
	if not _enemy_sheet_definitions.has(id):
		return {}
	return (_enemy_sheet_definitions[id] as Dictionary).duplicate(true)


func hit_mask_definitions() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for definition in _hit_mask_definitions:
		result.append(definition.duplicate(true))
	return result


func enemy_sheet_ids() -> Array[String]:
	return _enemy_sheet_ids.duplicate()


func enemy_projectile_broad_bounds(type_id: int, sheet_id: String) -> Array[int]:
	var result: Array[int] = []
	if not _enemy_projectile_broad_bounds.has(type_id):
		last_error = "unknown enemy projectile type %d" % type_id
		return result
	var bounds_by_sheet := _enemy_projectile_broad_bounds[type_id] as Dictionary
	if not bounds_by_sheet.has(sheet_id):
		last_error = "unknown enemy projectile sheet %s" % sheet_id
		return result
	for coordinate in bounds_by_sheet[sheet_id] as Array:
		result.append(int(coordinate))
	last_error = ""
	return result


func fighter_source_rect(frame_index: int) -> Rect2i:
	var frame := clampi(frame_index, 0, _fighter_frame_count - 1)
	return Rect2i(frame * _fighter_frame_width, 0, _fighter_frame_width, _fighter_frame_height)


func projectile_source_rect(prototype_id: int) -> Rect2i:
	return _projectile_rects.get(prototype_id, Rect2i())


func projectile_next_prototype_id(prototype_id: int) -> int:
	return int(_projectile_next.get(prototype_id, prototype_id))


func projectile_is_persistent(prototype_id: int) -> bool:
	return bool(_projectile_persistent.get(prototype_id, false))


func enemy_source_rect(enemy: Dictionary, simulation_tick: int) -> Rect2i:
	var state := String(enemy.get("authored_state", "entry"))
	var family_id := "directional_32"
	var frame_index := int(enemy.get("authored_sprite_frame", 0))
	match state:
		"formation", "return", "state_ten":
			family_id = "formation_animation_32"
			frame_index = int(
				enemy.get(
					"authored_animation_frame",
					(simulation_tick / 6 + int(enemy.get("id", 0))) % 6
				)
			)
		"supplemental_large", "warp_malfunction":
			family_id = "supplemental_large_animation_64"
			frame_index = int(enemy.get("authored_animation_frame", 0))
		"entry", "delayed":
			frame_index = enemy_direction_frame(
				int(enemy.get("velocity_x_fp", 0)),
				int(enemy.get("velocity_y_fp", 0)),
				bool(enemy.get("mirror_x", false))
			)
	if not _enemy_families.has(family_id):
		return Rect2i()
	var frames: Array = _enemy_families[family_id]
	if frames.is_empty():
		return Rect2i()
	return frames[posmod(frame_index, frames.size())]


func enemy_direction_frame(velocity_x_fp: int, velocity_y_fp: int, mirror_x: bool) -> int:
	var slope: float
	if velocity_x_fp == 0:
		slope = 5000.0 if velocity_y_fp > 0 else -5000.0
	else:
		slope = PackedFloat32Array([float(velocity_y_fp) / float(velocity_x_fp)])[0]
	var base_index := 0 if velocity_x_fp >= 0 else 8
	var frame_index := base_index
	for entry_value in _direction_ranges:
		var entry: Dictionary = entry_value
		var minimum := float(String(entry.get("minimum_float32", "0")))
		var maximum := float(String(entry.get("maximum_float32", "0")))
		if slope > minimum and slope < maximum:
			frame_index = posmod(base_index + int(entry.get("bucket", 0)), 16)
			break
	if mirror_x:
		frame_index = int(_direction_mirror[frame_index])
	return frame_index


func _state_ten_contract_is_exact(document: Dictionary) -> bool:
	var contracts_value: Variant = document.get("renderer_state_contracts")
	if not contracts_value is Array:
		return false
	var matches: Array = []
	for contract_value in contracts_value as Array:
		if not contract_value is Dictionary:
			return false
		var contract := contract_value as Dictionary
		var match_value: Variant = contract.get("snapshot_match")
		if (
			match_value is Dictionary
			and String((match_value as Dictionary).get("authored_state", ""))
			== "state_ten"
		):
			matches.append(contract)
	if matches.size() != 1:
		return false
	var contract := matches[0] as Dictionary
	var selection_value: Variant = contract.get("frame_selection")
	if not selection_value is Dictionary:
		return false
	var selection := selection_value as Dictionary
	var update_value: Variant = selection.get("phase_update")
	var selection_region_value: Variant = selection.get("selection_instruction_region")
	if not update_value is Dictionary or not selection_region_value is Dictionary:
		return false
	var update := update_value as Dictionary
	var update_region_value: Variant = update.get("instruction_region")
	if not update_region_value is Dictionary:
		return false
	var selection_region := selection_region_value as Dictionary
	var update_region := update_region_value as Dictionary
	return (
		int(contract.get("original_runtime_state_id", 0)) == 10
		and String(contract.get("frame_family", "")) == "formation_animation_32"
		and String(contract.get("confidence", "")) == "proven"
		and String(selection.get("snapshot_field", "")) == "authored_animation_frame"
		and String(selection.get("formula", ""))
		== "trunc_toward_zero(original animation phase)"
		and _json_integer_array_matches(selection.get("valid_indices"), [0, 1, 2, 3, 4, 5])
		and String(selection.get("source_y_table_va", "")) == "0x007d02a8"
		and String(selection.get("source_x_table_va", "")) == "0x007d0300"
		and String(selection_region.get("virtual_address", "")) == "0x0060e5e9"
		and int(selection_region.get("size", 0)) == 114
		and String(selection_region.get("sha256", ""))
		== "2f84aa1f998b3af3688dc383fc80de79bfc1687bd3ffef7fa04fbd41abdca260"
		and String(update_region.get("virtual_address", "")) == "0x0060e65b"
		and int(update_region.get("size", 0)) == 464
		and String(update_region.get("sha256", ""))
		== "a31a962b37f247fe76840345231e70d1f41d19251e2a625af0693bebb0327701"
		and String(update.get("advance_when", ""))
		== "countdown is strictly below zero"
		and String(update.get("countdown_subtract", "")) == "retail tick scale"
		and String(update.get("countdown_reset", "")) == "4.0"
		and String(update.get("direction_nonzero", ""))
		== "decrement and wrap below zero to 5"
		and String(update.get("direction_zero", ""))
		== "increment and wrap above 5 to zero"
	)


func _parse_rect(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return {"ok": false, "error": "sprite source rectangle must be an object"}
	var rect := value as Dictionary
	for key in ["x", "y", "width", "height"]:
		var coordinate: Variant = rect.get(key)
		if typeof(coordinate) != TYPE_INT and typeof(coordinate) != TYPE_FLOAT:
			return {"ok": false, "error": "sprite source rectangle fields must be integers"}
	var parsed := Rect2i(
		int(rect.x),
		int(rect.y),
		int(rect.width),
		int(rect.height)
	)
	if parsed.size.x <= 0 or parsed.size.y <= 0:
		return {"ok": false, "error": "sprite source rectangle must be positive"}
	return {"ok": true, "error": "", "value": parsed}


func _json_integer_array_matches(value: Variant, expected: Array) -> bool:
	if not value is Array or (value as Array).size() != expected.size():
		return false
	for index in range(expected.size()):
		var item: Variant = (value as Array)[index]
		if (
			typeof(item) != TYPE_INT
			and (typeof(item) != TYPE_FLOAT or not is_finite(float(item)) or float(item) != floor(float(item)))
		):
			return false
		if int(item) != int(expected[index]):
			return false
	return true


func _is_lower_hex_sha256(value: String) -> bool:
	if value.length() != 64:
		return false
	for index in range(value.length()):
		var character := value.substr(index, 1)
		if not "0123456789abcdef".contains(character):
			return false
	return true


func _parse_inclusive_bounds(value: Variant) -> Dictionary:
	if typeof(value) != TYPE_ARRAY or (value as Array).size() != 4:
		return {"ok": false, "error": "retail broad-phase bounds must contain four integers"}
	var parsed: Array[int] = []
	for coordinate in value as Array:
		if typeof(coordinate) != TYPE_INT and typeof(coordinate) != TYPE_FLOAT:
			return {"ok": false, "error": "retail broad-phase bounds must be integers"}
		var normalized := int(coordinate)
		if float(normalized) != float(coordinate):
			return {"ok": false, "error": "retail broad-phase bounds must be integers"}
		parsed.append(normalized)
	if (
		parsed[0] < 0
		or parsed[1] < 0
		or parsed[2] < parsed[0]
		or parsed[3] < parsed[1]
		or parsed[2] >= 32
		or parsed[3] >= 32
	):
		return {"ok": false, "error": "retail broad-phase bounds must fit a 32x32 cell"}
	return {"ok": true, "error": "", "value": parsed}


func _fail(message: String) -> bool:
	last_error = message
	return false

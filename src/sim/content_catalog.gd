class_name ContentCatalog
extends RefCounted

const FP_ONE: int = 65536
const LEGACY_REQUIRED_FILES: Array[String] = [
	"weapons.json",
	"bonuses.json",
	"levels.json",
	"shop.json",
	"difficulties.json",
	"sprite_frames.json",
	"swd_paths.json",
	"bonus_modes.json",
]
const REQUIRED_FILES: Array[String] = [
	"weapons.json",
	"bonuses.json",
	"levels.json",
	"shop.json",
	"difficulties.json",
	"sprite_frames.json",
	"swd_paths.json",
	"bonus_modes.json",
	"bosses.json",
	"ordnance.json",
	"time_trial.json",
	"talents.json",
]
const SUPPORTED_PATHS: Array[String] = [
	"sine_entry",
	"formation",
	"sweep_left",
	"sweep_right",
	"kamikaze",
]
const AUTHORED_LVD_SCHEMA: String = "warblade.lvd.authored.v2"
const BONUS_SCHEMA: String = "warblade.bonuses.v1"
const MODE_SIX_LEVEL_IDS: Array[int] = [
	63, 64, 65, 67, 68, 69, 71, 72, 73, 76, 77, 88, 89, 90, 92, 93,
]
const RETAIL_EXECUTABLE_SHA256: String = "ddf1778c307af1087ff9dcb512786111e665d972298aeaac3f1b4b2996d079ef"
const ORDNANCE_FILE_SHA256: String = "b9b424d17fff3cfb85b7d012f7ec353cb03a5cf24a363e86832456b9cf8a6467"
const ORDNANCE_CANONICAL_JSON_SHA256: String = "892bc0035c8a8216d1661225eea31b82848fdecf4bb8bc1b4b5efe73f360a646"
const BONUS_WEIGHTS: Array[int] = [
	45, 45, 45, 45, 45, 111, 53, 90, 90, 130, 130, 65, 80, 80, 80, 20, 140, 20, 60,
	35, 50, 25, 35, 35, 35, 5, 25, 10, 15, 300, 150, 75, 30, 8, 10, 15, 20,
]
const BONUS_SOURCE_Y: Array[int] = [
	60, 80, 100, 120, 140, 20, 460, 160, 180, 280, 300, 40, 340, 320, 360, 240, 380,
	400, 260, 420, 0, 500, 520, 540, 560, 660, 440, 200, 480, 600, 580, 620, 640, 220,
	700, 680, 720,
]
const BONUS_EFFECT_KEYS: Array[String] = [
	"letter_e", "letter_x", "letter_t", "letter_r", "letter_a",
	"mystery", "memory_station", "score_x2", "score_x5", "extra_bullet", "extra_speed",
	"shield", "single", "double", "triple", "warp", "scoop", "quad", "auto_fire",
	"gem_bomb", "meteor_storm", "armour", "sucker_blue_money", "sucker_gem_counter",
	"sucker_meteor_multiplier", "mirror", "money_bomb", "extra_life", "extra_time", "money_10",
	"money_50", "money_100", "money_200", "money_doubler", "drunk_mode",
	"freeze", "extra_bullet_speed",
]
const SUPPORTED_AUTHORED_PATH_OPCODES: Array[int] = [0, 1, 6]
const SUPPORTED_EFFECTS: Array[String] = [
	"speed_up",
	"bullet_capacity_up",
	"equip_weapon",
	"speed_down",
	"enable_autofire",
	"armor_up",
	"life_up",
	"buy_secret",
	"rank_marker_up",
	"bonus_time_up",
	"rocket_pack",
	"enable_alien_lock",
	"enable_super_autofire",
	"clear_profile_shields",
]
const LEVEL_CATALOG_COMPATIBILITY := {
	1: {
		"bosses_version": 0,
		"ordnance_version": 0,
		"sprite_frames_version": 2,
		"level_count": 20,
	},
	2: {
		"bosses_version": 1,
		"ordnance_version": 0,
		"sprite_frames_version": 3,
		"level_count": 25,
	},
	3: {
		"bosses_version": 2,
		"ordnance_version": 1,
		"sprite_frames_version": 4,
		"level_count": 30,
	},
	4: {
		"bosses_version": 2,
		"ordnance_version": 1,
		"sprite_frames_version": 5,
		"level_count": 35,
	},
	5: {
		"bosses_version": 2,
		"ordnance_version": 1,
		"sprite_frames_version": 6,
		"level_count": 49,
	},
	6: {
		"bosses_version": 3,
		"ordnance_version": 1,
		"sprite_frames_version": 7,
		"level_count": 50,
	},
	7: {
		"bosses_version": 3,
		"ordnance_version": 1,
		"sprite_frames_version": 8,
		"level_count": 62,
	},
	8: {
		"bosses_version": 4,
		"ordnance_version": 1,
		"sprite_frames_version": 9,
		"level_count": 100,
	},
	9: {
		"bosses_version": 5,
		"ordnance_version": 1,
		"sprite_frames_version": 10,
		"level_count": 100,
		"time_trial_version": 0,
	},
	10: {
		"bosses_version": 5,
		"ordnance_version": 1,
		"sprite_frames_version": 11,
		"level_count": 100,
		"time_trial_version": 1,
		"talents_version": 1,
	},
}
const TALENTS_SCHEMA: String = "warblade.talents.v1"
const TALENTS_VERSION: int = 1
const TIME_TRIAL_SCHEMA: String = "warblade.time-trial.v1"
const TIME_TRIAL_LEVEL_COUNT: int = 15
const TIME_TRIAL_MATCH_CLOCK_MS: int = 181000
const TIME_TRIAL_EXTRA_MINUTE_CLOCK_MS: int = 241000
const TIME_TRIAL_MISSING_LEVELS_CLOCK_MS: int = 10000
const TIME_TRIAL_RETAIL_MATCH_MODE_ID: int = 6
const TIME_TRIAL_SUPPORTED_LEVEL_MODE_IDS: Array[int] = [1, 2]
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
const SPRITE_CATALOG_LEVEL_COUNTS := {
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


static func load_catalog(
	base_path: String = "res://content",
	expected_hash: String = "",
	allow_fallback: bool = false
) -> Dictionary:
	var present_count := 0
	for file_name in LEGACY_REQUIRED_FILES:
		if FileAccess.file_exists(base_path.path_join(file_name)):
			present_count += 1
	if present_count == 0:
		if not allow_fallback:
			return _failure("required content catalog is missing")
		var fallback := _fallback_catalog()
		var fallback_hash := _hash_text(JSON.stringify(fallback))
		if not expected_hash.is_empty() and expected_hash != fallback_hash:
			return _failure("fallback content hash does not match expected hash")
		fallback["ok"] = true
		fallback["error"] = ""
		fallback["content_hash"] = fallback_hash
		fallback["using_fallback"] = true
		return fallback
	if present_count != LEGACY_REQUIRED_FILES.size():
		return _failure("content catalog is incomplete")

	var raw_files: Dictionary = {}
	var documents: Dictionary = {}
	for file_name in LEGACY_REQUIRED_FILES:
		var path := base_path.path_join(file_name)
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			return _failure("cannot read %s" % path)
		var raw := file.get_buffer(file.get_length())
		raw_files[file_name] = raw
		var json := JSON.new()
		var parse_error := json.parse(raw.get_string_from_utf8())
		if parse_error != OK:
			return _failure("%s:%d: %s" % [path, json.get_error_line(), json.get_error_message()])
		if typeof(json.data) != TYPE_DICTIONARY:
			return _failure("%s must contain a JSON object" % path)
		documents[file_name] = json.data
	var levels_document := documents.get("levels.json", {}) as Dictionary
	var levels_version := int(levels_document.get("version", 0))
	var compatibility_value: Variant = LEVEL_CATALOG_COMPATIBILITY.get(levels_version)
	if not compatibility_value is Dictionary:
		return _failure("levels.json has an unsupported version")
	var compatibility := compatibility_value as Dictionary
	var hash_file_names := LEGACY_REQUIRED_FILES.duplicate()
	if int(compatibility.bosses_version) > 0:
		var bosses_path := base_path.path_join("bosses.json")
		if not FileAccess.file_exists(bosses_path):
			return _failure("levels.json v%d requires bosses.json" % levels_version)
		var bosses_file := FileAccess.open(bosses_path, FileAccess.READ)
		if bosses_file == null:
			return _failure("cannot read %s" % bosses_path)
		var bosses_raw := bosses_file.get_buffer(bosses_file.get_length())
		raw_files["bosses.json"] = bosses_raw
		var bosses_json := JSON.new()
		var bosses_parse_error := bosses_json.parse(bosses_raw.get_string_from_utf8())
		if bosses_parse_error != OK:
			return _failure(
				"%s:%d: %s"
				% [bosses_path, bosses_json.get_error_line(), bosses_json.get_error_message()]
			)
		if typeof(bosses_json.data) != TYPE_DICTIONARY:
			return _failure("%s must contain a JSON object" % bosses_path)
		documents["bosses.json"] = bosses_json.data
		hash_file_names.append("bosses.json")
	if int(compatibility.ordnance_version) > 0:
		var ordnance_path := base_path.path_join("ordnance.json")
		if not FileAccess.file_exists(ordnance_path):
			return _failure("levels.json v%d requires ordnance.json" % levels_version)
		var ordnance_file := FileAccess.open(ordnance_path, FileAccess.READ)
		if ordnance_file == null:
			return _failure("cannot read %s" % ordnance_path)
		var ordnance_raw := ordnance_file.get_buffer(ordnance_file.get_length())
		if _hash_bytes(ordnance_raw) != ORDNANCE_FILE_SHA256:
			return _failure("ordnance.json differs from the byte-pinned retail contract")
		raw_files["ordnance.json"] = ordnance_raw
		var ordnance_json := JSON.new()
		var ordnance_parse_error := ordnance_json.parse(
			ordnance_raw.get_string_from_utf8()
		)
		if ordnance_parse_error != OK:
			return _failure(
				"%s:%d: %s"
				% [
					ordnance_path,
					ordnance_json.get_error_line(),
					ordnance_json.get_error_message(),
				]
			)
		if typeof(ordnance_json.data) != TYPE_DICTIONARY:
			return _failure("%s must contain a JSON object" % ordnance_path)
		documents["ordnance.json"] = ordnance_json.data
		hash_file_names.append("ordnance.json")
	if int(compatibility.get("time_trial_version", 0)) > 0:
		var time_trial_path := base_path.path_join("time_trial.json")
		if not FileAccess.file_exists(time_trial_path):
			return _failure("levels.json v%d requires time_trial.json" % levels_version)
		var time_trial_file := FileAccess.open(time_trial_path, FileAccess.READ)
		if time_trial_file == null:
			return _failure("cannot read %s" % time_trial_path)
		var time_trial_raw := time_trial_file.get_buffer(time_trial_file.get_length())
		raw_files["time_trial.json"] = time_trial_raw
		var time_trial_json := JSON.new()
		var time_trial_parse_error := time_trial_json.parse(
			time_trial_raw.get_string_from_utf8()
		)
		if time_trial_parse_error != OK:
			return _failure(
				"%s:%d: %s"
				% [
					time_trial_path,
					time_trial_json.get_error_line(),
					time_trial_json.get_error_message(),
				]
			)
		if typeof(time_trial_json.data) != TYPE_DICTIONARY:
			return _failure("%s must contain a JSON object" % time_trial_path)
		documents["time_trial.json"] = time_trial_json.data
		hash_file_names.append("time_trial.json")
	# Content v12: the current catalog generation carries the remake-original
	# talent document; historical fixture catalogs stay loadable without it.
	if int(compatibility.get("talents_version", 0)) > 0:
		var talents_path := base_path.path_join("talents.json")
		if not FileAccess.file_exists(talents_path):
			return _failure("levels.json v%d requires talents.json" % levels_version)
		var talents_file := FileAccess.open(talents_path, FileAccess.READ)
		if talents_file == null:
			return _failure("cannot read %s" % talents_path)
		var talents_raw := talents_file.get_buffer(talents_file.get_length())
		raw_files["talents.json"] = talents_raw
		var talents_json := JSON.new()
		var talents_parse_error := talents_json.parse(talents_raw.get_string_from_utf8())
		if talents_parse_error != OK:
			return _failure(
				"%s:%d: %s"
				% [talents_path, talents_json.get_error_line(), talents_json.get_error_message()]
			)
		if typeof(talents_json.data) != TYPE_DICTIONARY:
			return _failure("%s must contain a JSON object" % talents_path)
		documents["talents.json"] = talents_json.data
		hash_file_names.append("talents.json")

	var content_hash := _hash_files(raw_files, hash_file_names)
	if not expected_hash.is_empty() and expected_hash != content_hash:
		return _failure("content hash does not match expected hash")

	var weapon_result := _validate_weapons(documents["weapons.json"])
	if not weapon_result.ok:
		return weapon_result
	var bonus_result := _validate_bonuses(documents["bonuses.json"])
	if not bonus_result.ok:
		return bonus_result
	var bosses_result := _success({})
	var expected_bosses_version := int(compatibility.bosses_version)
	if expected_bosses_version > 0:
		if int((documents["bosses.json"] as Dictionary).get("version", 0)) != expected_bosses_version:
			return _failure(
				"levels.json v%d requires bosses.json v%d"
				% [levels_version, expected_bosses_version]
			)
		bosses_result = _validate_bosses(documents["bosses.json"])
		if not bosses_result.ok:
			return bosses_result
	var ordnance_result := _success({})
	var expected_ordnance_version := int(compatibility.ordnance_version)
	if expected_ordnance_version > 0:
		if int((documents["ordnance.json"] as Dictionary).get("version", 0)) != expected_ordnance_version:
			return _failure(
				"levels.json v%d requires ordnance.json v%d"
				% [levels_version, expected_ordnance_version]
			)
		ordnance_result = _validate_ordnance(documents["ordnance.json"])
		if not ordnance_result.ok:
			return ordnance_result
	var level_result := _validate_levels(
		documents["levels.json"],
		bosses_result.value
	)
	if not level_result.ok:
		return level_result
	var shop_result := _validate_shop(documents["shop.json"])
	if not shop_result.ok:
		return shop_result
	var difficulty_result := _validate_difficulties(documents["difficulties.json"])
	if not difficulty_result.ok:
		return difficulty_result
	var sprite_result := _validate_sprite_frames(documents["sprite_frames.json"])
	if not sprite_result.ok:
		return sprite_result
	var expected_sprite_version := int(compatibility.sprite_frames_version)
	if int((sprite_result.value as Dictionary).get("version", 0)) != expected_sprite_version:
		return _failure(
			"levels.json v%d requires sprite_frames.json v%d"
			% [levels_version, expected_sprite_version]
		)
	var binding_result := _validate_level_sprite_bindings(
		level_result.value,
		sprite_result.value
	)
	if not binding_result.ok:
		return binding_result
	var time_trial_result := _success({})
	var expected_time_trial_version := int(compatibility.get("time_trial_version", 0))
	if expected_time_trial_version > 0:
		if (
			int((documents["time_trial.json"] as Dictionary).get("version", 0))
			!= expected_time_trial_version
		):
			return _failure(
				"levels.json v%d requires time_trial.json v%d"
				% [levels_version, expected_time_trial_version]
			)
		time_trial_result = _validate_time_trial(documents["time_trial.json"])
		if not time_trial_result.ok:
			return time_trial_result
		var time_trial_binding_result := _validate_time_trial_sprite_bindings(
			(time_trial_result.value as Dictionary).get("levels", []),
			sprite_result.value
		)
		if not time_trial_binding_result.ok:
			return time_trial_binding_result
	var swd_result := _validate_swd_paths(documents["swd_paths.json"])
	if not swd_result.ok:
		return swd_result
	var bonus_modes_result := _validate_bonus_modes(
		documents["bonus_modes.json"],
		levels_version,
		level_result.value
	)
	if not bonus_modes_result.ok:
		return bonus_modes_result
	var talents_result := _success({})
	var expected_talents_version := int(compatibility.get("talents_version", 0))
	if expected_talents_version > 0:
		if int((documents["talents.json"] as Dictionary).get("version", 0)) != expected_talents_version:
			return _failure(
				"levels.json v%d requires talents.json v%d"
				% [levels_version, expected_talents_version]
			)
		talents_result = _validate_talents(documents["talents.json"], shop_result.value)
		if not talents_result.ok:
			return talents_result

	return {
		"ok": true,
		"error": "",
		"content_hash": content_hash,
		"using_fallback": false,
		"weapons": weapon_result.value,
		"bonuses": bonus_result.value,
		"levels": level_result.value,
		"shop": shop_result.value,
		"difficulties": difficulty_result.value,
		"sprites": sprite_result.value,
		"swd_paths": swd_result.value,
		"bonus_modes": bonus_modes_result.value,
		"bosses": bosses_result.value,
		"bosses_version": expected_bosses_version,
		"ordnance": ordnance_result.value,
		"time_trial": time_trial_result.value,
		"time_trial_version": expected_time_trial_version,
		"talents": talents_result.value,
		"talents_version": expected_talents_version,
	}


## The talent catalog is remake-original content (deterministic
## modernization): validation pins the schema, the closed grant vocabulary,
## the gated-effect mirror in the match contract, and prerequisite acyclicity.
static func _validate_talents(document: Dictionary, shop_items: Array) -> Dictionary:
	if int(document.get("version", 0)) != TALENTS_VERSION:
		return _failure("talents.json must publish version %d" % TALENTS_VERSION)
	if str(document.get("schema", "")) != TALENTS_SCHEMA:
		return _failure("talents.json must publish schema %s" % TALENTS_SCHEMA)
	var modes_value: Variant = document.get("applies_to_modes", [])
	if not modes_value is Array or (modes_value as Array) != ["solo", "coop"]:
		return _failure("talents.json applies_to_modes must be exactly solo and coop")
	var migration_value: Variant = document.get("shop_migration", {})
	if not migration_value is Dictionary:
		return _failure("talents.json requires a shop_migration object")
	var gated_value: Variant = (migration_value as Dictionary).get("talent_gated_effects", [])
	var gated: Array = gated_value if gated_value is Array else []
	var gated_sorted := gated.duplicate()
	gated_sorted.sort()
	if gated_sorted != WBMatchContract.TALENT_GATED_EFFECTS:
		return _failure(
			"talents.json talent_gated_effects must equal the match contract mirror"
		)
	var shop_effects: Array = []
	for item_value in shop_items:
		shop_effects.append(str((item_value as Dictionary).get("effect", "")))
	for effect_value in gated:
		if str(effect_value) not in shop_effects:
			return _failure("talent-gated effect %s is not a shop effect" % str(effect_value))
	var grant_keys_value: Variant = document.get("grant_keys", {})
	if not grant_keys_value is Dictionary:
		return _failure("talents.json requires a grant_keys vocabulary")
	var int_keys: Array = (grant_keys_value as Dictionary).get("int", [])
	var bool_keys: Array = (grant_keys_value as Dictionary).get("bool", [])
	for key_value in int_keys:
		var key := str(key_value)
		if key != "starting_rockets" and key not in WBMatchContract.START_STATE_INT_KEYS:
			return _failure("talents.json int grant key %s is outside the contract" % key)
	for key_value in bool_keys:
		if str(key_value) not in WBMatchContract.START_STATE_BOOL_KEYS:
			return _failure(
				"talents.json bool grant key %s is outside the contract" % str(key_value)
			)
	var branches_value: Variant = document.get("branches", [])
	if not branches_value is Array or (branches_value as Array).is_empty():
		return _failure("talents.json requires at least one branch")
	var nodes_by_id: Dictionary = {}
	for branch_value in (branches_value as Array):
		if not branch_value is Dictionary:
			return _failure("talents.json branches must be objects")
		for node_value in ((branch_value as Dictionary).get("nodes", []) as Array):
			if not node_value is Dictionary:
				return _failure("talents.json nodes must be objects")
			var node := node_value as Dictionary
			var node_id := str(node.get("id", ""))
			if node_id.is_empty() or nodes_by_id.has(node_id):
				return _failure("talents.json node ids must be unique and non-empty")
			var kind := str(node.get("kind", ""))
			if kind not in ["grant", "shop_unlock"]:
				return _failure("talent %s has unknown kind %s" % [node_id, kind])
			if int(node.get("cost", 0)) < 1:
				return _failure("talent %s must cost at least one point" % node_id)
			if kind == "shop_unlock" and str(node.get("shop_effect", "")) not in gated:
				return _failure("talent %s unlocks an ungated shop effect" % node_id)
			if kind == "grant":
				for grant_key_value in (node.get("grants", {}) as Dictionary).keys():
					var grant_key := str(grant_key_value)
					var grant_value: Variant = (node.get("grants", {}) as Dictionary)[grant_key_value]
					var pool: Array = bool_keys if grant_value is bool else int_keys
					if grant_key not in pool:
						return _failure(
							"talent %s grants %s outside the declared vocabulary"
							% [node_id, grant_key]
						)
			nodes_by_id[node_id] = node
	for node_id_value in nodes_by_id.keys():
		for requirement_value in (
			(nodes_by_id[node_id_value] as Dictionary).get("requires", []) as Array
		):
			if not nodes_by_id.has(str(requirement_value)):
				return _failure(
					"talent %s requires unknown node %s"
					% [str(node_id_value), str(requirement_value)]
				)
	# Prerequisite acyclicity: peel nodes whose requirements are all peeled.
	var peeled: Dictionary = {}
	var remaining := nodes_by_id.size()
	var progressed := true
	while progressed and remaining > 0:
		progressed = false
		for node_id_value in nodes_by_id.keys():
			if peeled.has(node_id_value):
				continue
			var ready := true
			for requirement_value in (
				(nodes_by_id[node_id_value] as Dictionary).get("requires", []) as Array
			):
				if not peeled.has(str(requirement_value)):
					ready = false
					break
			if ready:
				peeled[node_id_value] = true
				remaining -= 1
				progressed = true
	if remaining > 0:
		return _failure("talents.json contains a prerequisite cycle")
	return _success(document.duplicate(true))


static func _validate_ordnance(document: Dictionary) -> Dictionary:
	if not ordnance_contract_matches(document):
		return _failure("ordnance.json differs from the exact generated retail contract")
	if int(document.get("version", 0)) != 1:
		return _failure("ordnance.json has an unsupported version")
	if String(document.get("schema", "")) != "warblade.ordnance.v1":
		return _failure("ordnance.json has an unsupported schema")
	for section_name in [
		"source",
		"rocket_pack",
		"alien_lock",
		"missile_runtime",
		"integration",
	]:
		if not document.get(section_name) is Dictionary:
			return _failure("ordnance.json is missing %s" % section_name)
	return _success(document.duplicate(true))


static func ordnance_contract_matches(document: Dictionary) -> bool:
	return (
		_hash_text(JSON.stringify(document))
		== ORDNANCE_CANONICAL_JSON_SHA256
	)


static func _validate_bosses(document: Dictionary) -> Dictionary:
	var catalog_version := int(document.get("version", 0))
	if catalog_version not in [1, 2, 3, 4, 5]:
		return _failure("bosses.json has an unsupported version")
	if String(document.get("schema", "")) != "warblade.bosses.v%d" % catalog_version:
		return _failure("bosses.json has an unsupported schema")
	var bosses_value: Variant = document.get("bosses")
	if not bosses_value is Dictionary:
		return _failure("bosses.json is missing bosses")
	var expected_contract_ids: Array[String] = ["retail_big_boss_v1"]
	if catalog_version >= 3:
		expected_contract_ids.append("retail_big_boss_level_50_v1")
	if catalog_version >= 4:
		expected_contract_ids.append("retail_big_boss_level_75_v1")
		expected_contract_ids.append("retail_big_boss_level_100_v1")
	if (bosses_value as Dictionary).keys() != expected_contract_ids:
		return _failure("bosses.json contains unsupported or misordered boss contracts")
	var normalized: Dictionary = {}
	for contract_id in expected_contract_ids:
		var expected_level_id := int({
			"retail_big_boss_v1": 25,
			"retail_big_boss_level_50_v1": 50,
			"retail_big_boss_level_75_v1": 75,
			"retail_big_boss_level_100_v1": 100,
		}.get(contract_id, 0))
		var contract_result := _validate_boss_contract(
			(bosses_value as Dictionary).get(contract_id),
			contract_id,
			expected_level_id
		)
		if not contract_result.ok:
			return contract_result
		normalized[contract_id] = contract_result.value
	return _success(normalized)


static func _validate_boss_contract(
	contract_value: Variant,
	contract_id: String,
	expected_level_id: int
) -> Dictionary:
	if not contract_value is Dictionary:
		return _failure("bosses.json is missing %s" % contract_id)
	var contract := contract_value as Dictionary
	if (
		String(contract.get("id", "")) != contract_id
		or String(contract.get("executable_sha256", ""))
		!= RETAIL_EXECUTABLE_SHA256
		or int(contract.get("level_id", 0)) != expected_level_id
		or int(contract.get("level_mode_id", 0)) != 4
		or int(contract.get("retail_state_id", 0)) != 13
	):
		return _failure("%s identity or encounter binding is invalid" % contract_id)
	if contract.get("exact_trace_complete") != true:
		return _failure("%s exact trace is incomplete" % contract_id)
	for section_name in [
		"authored_level_payload",
		"resources",
		"initialization",
		"animation",
		"rendering",
		"health",
		"collision",
		"projectile_allocation",
		"aimed_fire",
		"opcode_2",
		"path",
		"death",
		"reward",
		"routing",
		"effects",
		"sounds",
		"effect_runtime",
		"evidence",
	]:
		if not contract.get(section_name) is Dictionary:
			return _failure(
				"%s is missing exact %s behavior" % [contract_id, section_name]
			)
	var authored_payload := contract.authored_level_payload as Dictionary
	var authored_payload_sha256 := String(authored_payload.get("sha256", ""))
	if (
		String(authored_payload.get("canonicalization", ""))
		!= "warblade_canonical_payload_v1"
		or not _is_lower_hex_sha256(authored_payload_sha256)
	):
		return _failure(
			"%s authored level payload binding is invalid" % contract_id
		)
	var path_contract := contract.path as Dictionary
	var expected_opcode_allowlist: Array[int] = [0, 1, 2, 7]
	if expected_level_id in [50, 75]:
		expected_opcode_allowlist = [0, 1, 2, 3, 7]
	elif expected_level_id == 100:
		expected_opcode_allowlist = [0, 1, 2, 6, 7]
	var opcode_allowlist_value: Variant = path_contract.get("opcode_allowlist")
	if (
		not opcode_allowlist_value is Array
		or (opcode_allowlist_value as Array).size()
		!= expected_opcode_allowlist.size()
	):
		return _failure("%s authored path opcode allowlist is invalid" % contract_id)
	for opcode_index in range(expected_opcode_allowlist.size()):
		if (
			not _is_json_integer((opcode_allowlist_value as Array)[opcode_index])
			or int((opcode_allowlist_value as Array)[opcode_index])
			!= int(expected_opcode_allowlist[opcode_index])
		):
			return _failure(
				"%s authored path opcode allowlist is invalid" % contract_id
			)
	var effect_runtime := contract.effect_runtime as Dictionary
	var effect_preset := effect_runtime.get("preset", {}) as Dictionary
	if (
		String(effect_runtime.get("id", "")) != "retail_big_boss_effects_v1"
		or String(effect_runtime.get("executable_sha256", ""))
		!= RETAIL_EXECUTABLE_SHA256
		or effect_runtime.get("exact_trace_complete") != true
		or String(effect_preset.get("id", "")) != "retail_high"
		or effect_preset.get("high_effects") != true
		or int(effect_preset.get("particle_density", 0)) != 100
		or String(effect_preset.get("evidence", "")) != "0x005bab12/0x005bab3a"
	):
		return _failure("%s effect runtime is not exact and pinned" % contract_id)
	var effect_pools := effect_runtime.get("pools", {}) as Dictionary
	for expected_pool in {
		"flash": 50,
		"debris": 150,
		"smoke": 500,
		"particle": 1000,
		"screen": 4,
	}:
		if (
			not effect_pools.get(expected_pool) is Dictionary
			or int((effect_pools[expected_pool] as Dictionary).get("capacity", 0))
			!= int({
				"flash": 50,
				"debris": 150,
				"smoke": 500,
				"particle": 1000,
				"screen": 4,
			}[expected_pool])
		):
			return _failure(
				"%s effect pool %s has the wrong capacity"
				% [contract_id, expected_pool]
			)
	if _contains_unresolved_contract_value(contract):
		return _failure("%s contains unresolved gameplay behavior" % contract_id)
	return _success(contract.duplicate(true))


static func _contains_unresolved_contract_value(value: Variant) -> bool:
	if value is String:
		return String(value).strip_edges().to_lower() == "unresolved"
	if value is Array:
		for item in value as Array:
			if _contains_unresolved_contract_value(item):
				return true
		return false
	if value is Dictionary:
		for key in value as Dictionary:
			if _contains_unresolved_contract_value((value as Dictionary)[key]):
				return true
	return false


static func _mode_three_aliases_from_levels(levels: Array) -> Dictionary:
	var expected_level_ids: Array[int] = [8, 16, 24, 33, 41, 49]
	if levels.size() == 62:
		expected_level_ids.append(58)
	elif levels.size() == 100:
		expected_level_ids.append_array([58, 66, 74, 83, 91, 99])
	elif levels.size() not in [49, 50]:
		return _failure("mode-three aliases require a complete late-campaign catalog")
	var actual_level_ids: Array[int] = []
	for level_index in range(levels.size()):
		var level_value: Variant = levels[level_index]
		if not level_value is Dictionary:
			return _failure("mode-three aliases require validated level objects")
		var level := level_value as Dictionary
		if int(level.get("id", 0)) != level_index + 1:
			return _failure("mode-three aliases require ordered level IDs")
		var authored_value: Variant = level.get("authored_lvd")
		if (
			authored_value is Dictionary
			and int((authored_value as Dictionary).get("level_mode_id", 0)) == 3
		):
			actual_level_ids.append(level_index + 1)
	if actual_level_ids != expected_level_ids:
		return _failure("late-campaign mode-three membership diverges from retail evidence")

	var aliases: Array = []
	for level_id in expected_level_ids:
		var level := levels[level_id - 1] as Dictionary
		var authored := level.authored_lvd as Dictionary
		var target_count := 0
		for group_value in authored.get("groups", []) as Array:
			if not group_value is Dictionary or not (group_value as Dictionary).get("enemies") is Array:
				return _failure("mode-three authored groups are malformed")
			target_count += ((group_value as Dictionary).enemies as Array).size()
		var slot_one_score: Variant = null
		for resource_value in level.get("enemy_resources", []) as Array:
			if (
				resource_value is Dictionary
				and int((resource_value as Dictionary).get("resource_slot_id", 0)) == 1
			):
				if slot_one_score != null:
					return _failure("mode-three levels must declare exactly one slot-1 resource")
				slot_one_score = int((resource_value as Dictionary).get("kill_score", -1))
		if target_count <= 0 or slot_one_score == null or int(slot_one_score) < 0:
			return _failure("mode-three target count or slot-1 score is invalid")
		aliases.append({
			"level_id": level_id,
			"authored_target_count": target_count,
			"authored_enemy_score": int(slot_one_score),
		})
	return _success(aliases)


static func _validate_bonus_modes(
	document: Dictionary,
	levels_catalog_version: int = 5,
	levels: Array = []
) -> Dictionary:
	if int(document.get("version", 0)) != 1:
		return _failure("bonus_modes.json has an unsupported version")
	if String(document.get("schema", "")) != "warblade.bonus-modes.v1":
		return _failure("bonus_modes.json has an unsupported schema")
	var source: Variant = document.get("source")
	if (
		not source is Dictionary
		or String((source as Dictionary).get("executable_sha256", ""))
		!= RETAIL_EXECUTABLE_SHA256
	):
		return _failure("bonus_modes.json executable provenance is missing or unsupported")
	for section_name in [
		"assets",
		"mode_three_bonus",
		"level_8_bonus",
		"memory_station",
		"meteor_storm",
		"rank_promotion",
	]:
		if not document.get(section_name) is Dictionary:
			return _failure("bonus_modes.json is missing %s" % section_name)
	var level_eight := document.level_8_bonus as Dictionary
	if (
		int(level_eight.get("level_id", 0)) != 8
		or int(level_eight.get("level_mode_id", 0)) != 3
		or int(level_eight.get("authored_target_count", 0)) != 20
		or not bool(level_eight.get("ordinary_enemy_projectiles_suppressed", false))
	):
		return _failure("bonus_modes.json level-8 gate diverges from executable evidence")
	var mode_three := document.mode_three_bonus as Dictionary
	if (
		int(mode_three.get("level_mode_id", 0)) != 3
		or not bool(mode_three.get("ordinary_enemy_projectiles_suppressed", false))
		or not mode_three.get("levels") is Array
		or mode_three.has("level_id")
		or mode_three.has("authored_target_count")
		or mode_three.has("background_texture")
	):
		return _failure("bonus_modes.json mode-three contract is malformed")
	var mode_three_levels: Array = mode_three.levels
	var expected_mode_three_levels := [
		{"level_id": 8, "authored_target_count": 20, "authored_enemy_score": 200},
		{"level_id": 16, "authored_target_count": 30, "authored_enemy_score": 100},
		{"level_id": 24, "authored_target_count": 30, "authored_enemy_score": 200},
	]
	if levels_catalog_version >= 4:
		expected_mode_three_levels.append(
			{"level_id": 33, "authored_target_count": 30, "authored_enemy_score": 500}
		)
	if levels_catalog_version >= 5:
		var aliases_result := _mode_three_aliases_from_levels(levels)
		if not aliases_result.ok:
			return aliases_result
		expected_mode_three_levels = aliases_result.value
	if mode_three_levels.size() != expected_mode_three_levels.size():
		var expected_level_ids: Array[int] = []
		for expected_value in expected_mode_three_levels:
			expected_level_ids.append(int((expected_value as Dictionary).level_id))
		return _failure(
			"bonus_modes.json must bind exactly levels %s to mode three"
			% str(expected_level_ids)
		)
	for index in range(expected_mode_three_levels.size()):
		var actual_value: Variant = mode_three_levels[index]
		var expected: Dictionary = expected_mode_three_levels[index]
		if not actual_value is Dictionary:
			return _failure("bonus_modes.json mode-three level entries must be objects")
		var actual := actual_value as Dictionary
		for field in ["level_id", "authored_target_count", "authored_enemy_score"]:
			if (
				not _is_json_integer(actual.get(field))
				or int(actual.get(field)) != int(expected[field])
			):
				return _failure("bonus_modes.json mode-three level facts diverge from retail evidence")
	var canonical_rewards: Variant = mode_three.get("rewards")
	var legacy_rewards: Variant = level_eight.get("rewards")
	var canonical_timing: Variant = mode_three.get("timing_and_flow")
	var legacy_timing: Variant = level_eight.get("timing_and_flow")
	if (
		not canonical_rewards is Dictionary
		or not legacy_rewards is Dictionary
		or not canonical_timing is Dictionary
		or not legacy_timing is Dictionary
	):
		return _failure("bonus_modes.json mode-three shared contracts must be objects")
	var expected_rewards := (legacy_rewards as Dictionary).duplicate(true)
	expected_rewards.erase("authored_enemy_score")
	var expected_timing := (legacy_timing as Dictionary).duplicate(true)
	expected_timing.erase("shop_rule")
	if (
		int(level_eight.get("level_id", 0)) != int(mode_three_levels[0].level_id)
		or int(level_eight.get("authored_target_count", 0))
		!= int(mode_three_levels[0].authored_target_count)
		or int((legacy_rewards as Dictionary).get("authored_enemy_score", 0))
		!= int(mode_three_levels[0].authored_enemy_score)
		or (canonical_rewards as Dictionary) != expected_rewards
		or (canonical_timing as Dictionary) != expected_timing
	):
		return _failure("bonus_modes.json legacy level-8 projection is not synchronized")
	var rank_contract := document.rank_promotion as Dictionary
	var rank_range: Variant = rank_contract.get("rank_range")
	var ranks: Variant = rank_contract.get("ranks")
	if (
		not rank_range is Array
		or (rank_range as Array).size() != 2
		or int((rank_range as Array)[0]) != 1
		or int((rank_range as Array)[1]) != 20
		or not ranks is Array
		or (ranks as Array).size() != 20
	):
		return _failure("bonus_modes.json rank voice contract must cover ranks 1 through 20")
	for rank_index in range(20):
		var rank_value: Variant = (ranks as Array)[rank_index]
		if (
			not rank_value is Dictionary
			or int((rank_value as Dictionary).get("rank", 0)) != rank_index + 1
			or not (rank_value as Dictionary).get("queue") is Array
			or ((rank_value as Dictionary).get("queue") as Array).is_empty()
		):
			return _failure("bonus_modes.json rank voice entries are not contiguous")
	return _success(document.duplicate(true))


static func _validate_weapons(document: Dictionary) -> Dictionary:
	if not _version_is_supported(document):
		return _failure("weapons.json has an unsupported version")
	var fire_control: Variant = document.get("fire_control")
	if typeof(fire_control) != TYPE_DICTIONARY:
		return _failure("weapons.json is missing fire_control")
	var fire_rules := fire_control as Dictionary
	if (
		String(fire_rules.get("manual_fire", "")) != "edge_latched"
		or int(fire_rules.get("auto_fire_repeat_delay_ms", 0)) != 100
		or int(fire_rules.get("super_auto_fire_repeat_delay_ms", 0)) != 25
		or String(fire_rules.get("deadline_comparison", "")) != "strict_greater_than"
	):
		return _failure("weapons.json fire control does not match the retail contract")
	if typeof(document.get("weapons")) != TYPE_ARRAY:
		return _failure("weapons.json is missing weapons")
	var normalized: Array = []
	var ids: Dictionary = {}
	for value in document.weapons:
		if typeof(value) != TYPE_DICTIONARY:
			return _failure("weapon entries must be objects")
		var weapon: Dictionary = value
		for key in ["id", "damage_fp"]:
			if not _is_json_integer(weapon.get(key)):
				return _failure("weapon %s must be an integer" % key)
		if typeof(weapon.get("name")) != TYPE_STRING or typeof(weapon.get("sound")) != TYPE_STRING:
			return _failure("weapon names and sounds must be strings")
		if typeof(weapon.get("projectiles")) != TYPE_ARRAY or weapon.projectiles.is_empty():
			return _failure("weapons must contain at least one projectile")
		var weapon_id := int(weapon.id)
		if ids.has(weapon_id):
			return _failure("duplicate weapon id %d" % weapon_id)
		ids[weapon_id] = true
		var projectiles: Array = []
		for projectile_value in weapon.projectiles:
			if typeof(projectile_value) != TYPE_DICTIONARY:
				return _failure("projectile entries must be objects")
			var projectile: Dictionary = projectile_value
			for key in [
				"prototype_id",
				"offset_x_fp",
				"offset_y_fp",
				"velocity_x_fp",
				"velocity_y_fp",
				"width",
				"height",
			]:
				if not _is_json_integer(projectile.get(key)):
					return _failure("projectile %s must be an integer" % key)
			if int(projectile.width) <= 0 or int(projectile.height) <= 0:
				return _failure("projectile dimensions must be positive")
			var normalized_projectile := {
				"prototype_id": int(projectile.prototype_id),
				"offset_x_fp": int(projectile.offset_x_fp),
				"offset_y_fp": int(projectile.offset_y_fp),
				"velocity_x_fp": int(projectile.velocity_x_fp),
				"velocity_y_fp": int(projectile.velocity_y_fp),
				"width": int(projectile.width),
				"height": int(projectile.height),
			}
			if projectile.has("special_secondary_raw"):
				if not _is_json_integer(projectile.special_secondary_raw):
					return _failure("projectile special_secondary_raw must be an integer")
				normalized_projectile["special_secondary_raw"] = int(
					projectile.special_secondary_raw
				)
			projectiles.append(normalized_projectile)
		normalized.append({
			"id": weapon_id,
			"name": String(weapon.name),
			"damage_fp": int(weapon.damage_fp),
			"sound": String(weapon.sound),
			"projectiles": projectiles,
		})
	if normalized.is_empty():
		return _failure("weapons.json contains no weapons")
	return _success(normalized)


static func _validate_bonuses(document: Dictionary) -> Dictionary:
	if not _version_is_supported(document):
		return _failure("bonuses.json has an unsupported version")
	if String(document.get("schema", "")) != BONUS_SCHEMA:
		return _failure("bonuses.json has an unsupported schema")
	if String(document.get("source_executable_sha256", "")) != RETAIL_EXECUTABLE_SHA256:
		return _failure("bonuses.json executable provenance is missing or unsupported")
	var expected_source := {
		"spawn_function_va": "0x0056ff10",
		"collection_switch_va": "0x00571c60",
		"selection_weight_table_va": "0x007d0700",
		"source_x_table_va": "0x00e11910",
		"source_y_table_va": "0x007d07b0",
		"height_table_va": "0x007d0860",
		"width_table_va": "0x007d0910",
		"frame_count_table_va": "0x007d09a8",
		"logical_type_table_va": "0x007d0a40",
	}
	if document.get("source") != expected_source:
		return _failure("bonuses.json source-table provenance diverges from executable evidence")
	var expected_spawn_contract := {
		"pool_slots": 150,
		"selection_total_weight": 2252,
		"weighted_roll_min_argument": 0,
		"weighted_roll_max_adjustment": -1,
		"x_jitter_min_argument": 0,
		"x_jitter_max_argument": 6,
		"x_jitter_offset": -3,
		"animation_period_min": 3,
		"animation_period_max": 7,
		"initial_phase_min_argument": 0,
		"initial_phase_max_argument": 5,
		"initial_phase_offset": 2,
	}
	var spawn_value: Variant = document.get("spawn_contract")
	if typeof(spawn_value) != TYPE_DICTIONARY:
		return _failure("bonuses.json spawn contract diverges from executable evidence")
	var spawn_contract := spawn_value as Dictionary
	if spawn_contract.size() != expected_spawn_contract.size():
		return _failure("bonuses.json spawn contract diverges from executable evidence")
	for key in expected_spawn_contract:
		if (
			not _is_json_integer(spawn_contract.get(key))
			or int(spawn_contract.get(key)) != int(expected_spawn_contract[key])
		):
			return _failure("bonuses.json spawn contract diverges from executable evidence")
	var values: Variant = document.get("bonuses")
	if typeof(values) != TYPE_ARRAY or (values as Array).size() != BONUS_WEIGHTS.size():
		return _failure("bonuses.json must contain 37 logical types")
	var normalized: Array = []
	var total_weight := 0
	for bonus_index in range((values as Array).size()):
		var value: Variant = (values as Array)[bonus_index]
		if typeof(value) != TYPE_DICTIONARY:
			return _failure("bonus entries must be objects")
		var bonus := value as Dictionary
		for key in ["id", "effect_id", "weight", "source_x", "source_y", "width", "height", "frame_count"]:
			if not _is_json_integer(bonus.get(key)):
				return _failure("bonus %s must be an integer" % key)
		if typeof(bonus.get("effect_key")) != TYPE_STRING:
			return _failure("bonus effect_key must be a string")
		if int(bonus.id) != bonus_index or int(bonus.effect_id) != bonus_index:
			return _failure("bonus logical and effect IDs must be contiguous")
		if String(bonus.effect_key) != BONUS_EFFECT_KEYS[bonus_index]:
			return _failure("bonus %d effect key is unsupported" % bonus_index)
		if int(bonus.weight) != BONUS_WEIGHTS[bonus_index]:
			return _failure("bonus %d weight diverges from executable evidence" % bonus_index)
		if int(bonus.source_x) != 0 or int(bonus.source_y) != BONUS_SOURCE_Y[bonus_index]:
			return _failure("bonus %d source position diverges from executable evidence" % bonus_index)
		if int(bonus.width) != 20 or int(bonus.height) != 20 or int(bonus.frame_count) != 10:
			return _failure("bonus %d frame geometry diverges from executable evidence" % bonus_index)
		var normalized_bonus := {
			"id": bonus_index,
			"effect_id": bonus_index,
			"effect_key": String(bonus.effect_key),
			"weight": int(bonus.weight),
			"source_x": 0,
			"source_y": int(bonus.source_y),
			"width": 20,
			"height": 20,
			"frame_count": 10,
		}
		if bonus_index >= 12 and bonus_index <= 14:
			var gate_max: int = [50, 150, 300][bonus_index - 12]
			if not _bonus_reroll_gate_matches(bonus.get("reroll_gate"), gate_max):
				return _failure("bonus %d reroll gate diverges from executable evidence" % bonus_index)
			normalized_bonus["reroll_gate"] = _bonus_reroll_gate(gate_max)
		elif bonus.has("reroll_gate"):
			return _failure("bonus %d has an unsupported reroll gate" % bonus_index)
		total_weight += int(bonus.weight)
		normalized.append(normalized_bonus)
	if total_weight != int(expected_spawn_contract.selection_total_weight):
		return _failure("bonus selection weights do not match their executable total")
	return _success(normalized)


static func _validate_levels(
	document: Dictionary,
	bosses: Dictionary = {}
) -> Dictionary:
	if (
		not _is_json_integer(document.get("version"))
		or not LEVEL_CATALOG_COMPATIBILITY.has(int(document.version))
	):
		return _failure("levels.json has an unsupported version")
	var catalog_version := int(document.version)
	if (
		catalog_version >= 2
		and String(document.get("schema", "")) != "warblade.levels.v%d" % catalog_version
	):
		return _failure("levels.json has an unsupported schema")
	if typeof(document.get("levels")) != TYPE_ARRAY:
		return _failure("levels.json is missing levels")
	var runtime_result := _validate_level_mode_runtime(document, catalog_version)
	if not runtime_result.ok:
		return runtime_result
	var level_mode_runtime := runtime_result.value as Dictionary
	var normalized: Array = []
	var ids: Dictionary = {}
	for value in document.levels:
		if typeof(value) != TYPE_DICTIONARY:
			return _failure("level entries must be objects")
		var level: Dictionary = value
		if not _is_json_integer(level.get("id")):
			return _failure("level id must be an integer")
		for key in ["title", "author", "enemy_sprite"]:
			if typeof(level.get(key)) != TYPE_STRING:
				return _failure("level %s must be a string" % key)
		if typeof(level.get("shop_after")) != TYPE_BOOL:
			return _failure("level shop_after must be a boolean")
		if not _is_json_integer(level.get("ordinary_kill_score")):
			return _failure("level ordinary_kill_score must be an integer")
		if int(level.ordinary_kill_score) < 0:
			return _failure("level ordinary_kill_score must be nonnegative")
		var resources_result := _validate_enemy_resources(level, catalog_version)
		if not resources_result.ok:
			return resources_result
		var enemy_resources: Array = resources_result.value
		var authored_runtime: Dictionary = {}
		var authored_runtime_value: Variant = level.get("authored_runtime")
		if catalog_version >= 9:
			if (
				not authored_runtime_value is Dictionary
				or (authored_runtime_value as Dictionary).size() != 1
				or not (authored_runtime_value as Dictionary).has("ordinary_speed_fp")
				or not _is_json_integer(
					(authored_runtime_value as Dictionary).get("ordinary_speed_fp")
				)
				or int((authored_runtime_value as Dictionary).ordinary_speed_fp) != FP_ONE
			):
				return _failure(
					"levels.json v9 authored runtime must declare the source-backed ordinary speed"
				)
			authored_runtime = {
				"ordinary_speed_fp": int(
					(authored_runtime_value as Dictionary).ordinary_speed_fp
				),
			}
		elif authored_runtime_value != null:
			return _failure(
				"legacy levels catalogs cannot declare authored runtime defaults"
			)
		if typeof(level.get("waves")) != TYPE_ARRAY or level.waves.is_empty():
			return _failure("levels must contain waves")
		var level_id := int(level.id)
		if ids.has(level_id):
			return _failure("duplicate level id %d" % level_id)
		ids[level_id] = true
		var mode_four_contract_id := ""
		var mode_four_contract: Dictionary = {}
		for boss_key in bosses:
			var candidate_value: Variant = bosses[boss_key]
			if (
				candidate_value is Dictionary
				and int((candidate_value as Dictionary).get("level_id", 0))
				== level_id
			):
				if not mode_four_contract_id.is_empty():
					return _failure(
						"level %d is bound to more than one boss contract" % level_id
					)
				mode_four_contract_id = String(boss_key)
				mode_four_contract = candidate_value as Dictionary
		var allow_mode_four := (
			not mode_four_contract_id.is_empty()
			and not mode_four_contract.is_empty()
		)
		var mode_four_opcode_allowlist: Array = []
		if allow_mode_four:
			var resource_contract_value: Variant = mode_four_contract.get("resources")
			if not resource_contract_value is Dictionary:
				return _failure(
					"level %d boss contract is missing its resources" % level_id
				)
			var expected_slots_value: Variant = (
				resource_contract_value as Dictionary
			).get("slots")
			var expected_sheets_value: Variant = (
				resource_contract_value as Dictionary
			).get("sheet_ids")
			if (
				not expected_slots_value is Array
				or not expected_sheets_value is Array
				or (expected_slots_value as Array).size() != enemy_resources.size()
				or (expected_sheets_value as Array).size() != enemy_resources.size()
			):
				return _failure(
					"level %d enemy resources differ from its exact boss contract"
					% level_id
				)
			for resource_index in range(enemy_resources.size()):
				var level_resource := enemy_resources[resource_index] as Dictionary
				if (
					not _is_json_integer(
						(expected_slots_value as Array)[resource_index]
					)
					or int(level_resource.resource_slot_id)
					!= int((expected_slots_value as Array)[resource_index])
					or String(level_resource.enemy_sheet_id)
					!= String((expected_sheets_value as Array)[resource_index])
				):
					return _failure(
						"level %d enemy resources differ from its exact boss contract"
						% level_id
					)
			var path_contract_value: Variant = mode_four_contract.get("path")
			if not path_contract_value is Dictionary:
				return _failure(
					"level %d boss contract is missing its path contract" % level_id
				)
			var opcode_allowlist_value: Variant = (
				path_contract_value as Dictionary
			).get("opcode_allowlist")
			if not opcode_allowlist_value is Array:
				return _failure(
					"level %d boss contract is missing its opcode allowlist" % level_id
				)
			for opcode_value in opcode_allowlist_value as Array:
				if not _is_json_integer(opcode_value):
					return _failure(
						"level %d boss contract opcode allowlist is malformed"
						% level_id
					)
				mode_four_opcode_allowlist.append(int(opcode_value))
		var authored_result := _validate_authored_lvd(
			level.get("authored_lvd"),
			level_id,
			allow_mode_four,
			mode_four_opcode_allowlist
		)
		if not authored_result.ok:
			return authored_result
		var resource_reference_result := _validate_level_resource_references(
			authored_result.value,
			enemy_resources,
			allow_mode_four
		)
		if not resource_reference_result.ok:
			return resource_reference_result
		if allow_mode_four:
			var payload_binding := mode_four_contract.authored_level_payload as Dictionary
			var actual_payload_sha256 := canonical_payload_sha256(
				authored_result.value
			)
			if (
				actual_payload_sha256.is_empty()
				or actual_payload_sha256
				!= String(payload_binding.get("sha256", ""))
			):
				return _failure(
					"level %d authored payload does not match its exact boss contract"
					% level_id
				)
		var waves: Array = []
		for wave_value in level.waves:
			if typeof(wave_value) != TYPE_DICTIONARY:
				return _failure("wave entries must be objects")
			var wave: Dictionary = wave_value
			for key in [
				"start_tick",
				"count",
				"columns",
				"spawn_x",
				"spawn_y",
				"spacing_x",
				"spacing_y",
				"health_fp",
				"speed_fp",
				"fire_interval_ticks",
				"projectile_speed_fp",
				"score",
				"cash",
			]:
				if not _is_json_integer(wave.get(key)):
					return _failure("wave %s must be an integer" % key)
			if typeof(wave.get("path")) != TYPE_STRING or not SUPPORTED_PATHS.has(String(wave.path)):
				return _failure("wave path is unsupported")
			if int(wave.count) <= 0 or int(wave.columns) <= 0:
				return _failure("wave count and columns must be positive")
			waves.append({
				"start_tick": max(0, int(wave.start_tick)),
				"count": int(wave.count),
				"columns": int(wave.columns),
				"spawn_x": int(wave.spawn_x),
				"spawn_y": int(wave.spawn_y),
				"spacing_x": int(wave.spacing_x),
				"spacing_y": int(wave.spacing_y),
				"health_fp": max(1, int(wave.health_fp)),
				"speed_fp": max(1, int(wave.speed_fp)),
				"path": String(wave.path),
				"fire_interval_ticks": max(1, int(wave.fire_interval_ticks)),
				"projectile_speed_fp": max(1, int(wave.projectile_speed_fp)),
				"score": max(0, int(wave.score)),
				"cash": max(0, int(wave.cash)),
			})
		var normalized_level := {
			"id": level_id,
			"title": String(level.title),
			"author": String(level.author),
			"enemy_sprite": String(level.enemy_sprite),
			"ordinary_kill_score": int(level.ordinary_kill_score),
			"enemy_resources": enemy_resources,
			"shop_after": bool(level.shop_after),
			"waves": waves,
		}
		if not authored_runtime.is_empty():
			normalized_level["authored_runtime"] = authored_runtime
		if not authored_result.value.is_empty():
			normalized_level["authored_lvd"] = authored_result.value
			var level_mode_key := str(int(
				(authored_result.value as Dictionary).get("level_mode_id", 0)
			))
			if level_mode_runtime.has(level_mode_key):
				normalized_level["level_mode_runtime"] = (
					level_mode_runtime[level_mode_key] as Dictionary
				).duplicate(true)
		normalized.append(normalized_level)
	var expected_level_count := int((
		LEVEL_CATALOG_COMPATIBILITY[catalog_version] as Dictionary
	).level_count)
	if ids.size() != expected_level_count:
		return _failure(
			"levels.json must contain exactly the supported first %d levels"
			% expected_level_count
		)
	for required_level in range(1, expected_level_count + 1):
		if not ids.has(required_level):
			return _failure("levels.json is missing level %d" % required_level)
	return _success(normalized)


static func _validate_level_mode_runtime(
	document: Dictionary,
	catalog_version: int
) -> Dictionary:
	var value: Variant = document.get("level_mode_runtime")
	if catalog_version < 8:
		if value != null:
			return _failure(
				"legacy levels catalogs cannot declare level mode runtime contracts"
			)
		return _success({})
	if not value is Dictionary or (value as Dictionary).keys() != ["6"]:
		return _failure(
			"levels.json v%d must declare only the exact mode-6 runtime"
			% catalog_version
		)
	var mode_six_value: Variant = (value as Dictionary).get("6")
	if not mode_six_value is Dictionary:
		return _failure("levels.json mode-6 runtime must be an object")
	var mode_six := mode_six_value as Dictionary
	if mode_six.keys() != [
		"entry_state_id",
		"special_mode_classifier",
		"ordinary_projectile_aim",
		"ordinary_projectile_vertical_speed",
		"terminal_opcode_6",
		"setup_flags",
		"evidence",
	]:
		return _failure("levels.json mode-6 runtime fields are missing or reordered")
	var aim_value: Variant = mode_six.get("ordinary_projectile_aim")
	var vertical_value: Variant = mode_six.get("ordinary_projectile_vertical_speed")
	var flags_value: Variant = mode_six.get("setup_flags")
	var evidence_value: Variant = mode_six.get("evidence")
	if (
		int(mode_six.get("entry_state_id", 0)) != 2
		or mode_six.get("special_mode_classifier") != false
		or String(mode_six.get("terminal_opcode_6", "")) != "deactivate"
		or not aim_value is Dictionary
		or not vertical_value is Dictionary
		or not flags_value is Dictionary
		or not evidence_value is Dictionary
		or (evidence_value as Dictionary).is_empty()
	):
		return _failure("levels.json mode-6 setup contract diverges from retail evidence")
	var aim := aim_value as Dictionary
	var magnitude_rng: Variant = aim.get("horizontal_speed_magnitude_rng_fp")
	if (
		aim.keys() != [
			"enabled",
			"horizontal_speed_magnitude_rng_fp",
			"direction",
			"tick_scale_applied",
		]
		or
		aim.get("enabled") != true
		or not _json_integer_array_matches(magnitude_rng, [0, 98304])
		or String(aim.get("direction", "")) != "toward_active_player_x_side"
		or aim.get("tick_scale_applied") != true
	):
		return _failure("levels.json mode-6 projectile aim contract is invalid")
	var vertical := vertical_value as Dictionary
	if (
		vertical.keys() != [
			"base_multiplier_fp",
			"accelerated_multiplier_fp",
			"accelerated_when_level_strictly_above",
		]
		or not _is_json_integer(vertical.get("base_multiplier_fp"))
		or int(vertical.get("base_multiplier_fp", 0)) != 65536
		or not _is_json_integer(vertical.get("accelerated_multiplier_fp"))
		or int(vertical.get("accelerated_multiplier_fp", 0)) != 81920
		or not _is_json_integer(vertical.get("accelerated_when_level_strictly_above"))
		or int(vertical.get("accelerated_when_level_strictly_above", 0)) != 500
	):
		return _failure("levels.json mode-6 projectile speed contract is invalid")
	var flags := flags_value as Dictionary
	if (
		flags.keys() != ["aimed_shots", "accelerated_shots"]
		or String(flags.get("aimed_shots", "")) != "0x008f201d"
		or String(flags.get("accelerated_shots", "")) != "0x008f201e"
	):
		return _failure("levels.json mode-6 setup flag provenance is invalid")
	var evidence := evidence_value as Dictionary
	if (
		evidence.keys() != [
			"level_mode_global_va",
			"setup_dispatch_region",
			"setup_jump_table_region",
			"terminal_dispatch_region",
			"terminal_jump_table_region",
			"aim_and_speed_consumer_region",
		]
		or String(evidence.get("level_mode_global_va", "")) != "0x00a95c20"
		or String(evidence.get("setup_dispatch_region", ""))
		!= "level_mode_setup_dispatch"
		or String(evidence.get("setup_jump_table_region", ""))
		!= "level_mode_setup_jump_table"
		or String(evidence.get("terminal_dispatch_region", ""))
		!= "path_terminal_dispatch"
		or String(evidence.get("terminal_jump_table_region", ""))
		!= "path_terminal_jump_table"
		or String(evidence.get("aim_and_speed_consumer_region", ""))
		!= "ordinary_projectile_aim_and_speed"
	):
		return _failure("levels.json mode-6 evidence block is invalid")
	return _success({"6": mode_six.duplicate(true)})


static func _validate_enemy_resources(
	level: Dictionary,
	catalog_version: int
) -> Dictionary:
	if catalog_version == 1:
		return _success([{
			"resource_slot_id": 1,
			"raw_name": String(level.get("enemy_sprite", "")),
			"enemy_sheet_id": String(level.get("enemy_sprite", "")),
			"kill_score": int(level.get("ordinary_kill_score", 0)),
		}])
	var resources_value: Variant = level.get("enemy_resources")
	if not resources_value is Array or (resources_value as Array).is_empty():
		return _failure("level enemy_resources must be a nonempty array")
	var normalized: Array = []
	for resource_index in range((resources_value as Array).size()):
		var resource_value: Variant = (resources_value as Array)[resource_index]
		if not resource_value is Dictionary:
			return _failure("level enemy resource entries must be objects")
		var resource := resource_value as Dictionary
		if resource.keys().size() != 4:
			return _failure("level enemy resources must contain the exact fields")
		for required_key in [
			"resource_slot_id",
			"raw_name",
			"enemy_sheet_id",
			"kill_score",
		]:
			if not resource.has(required_key):
				return _failure(
					"level enemy resources must contain the exact fields"
				)
		if (
			not _is_json_integer(resource.get("resource_slot_id"))
			or int(resource.resource_slot_id) != resource_index + 1
		):
			return _failure("level enemy resources must be ordered by contiguous slot ID")
		for key in ["raw_name", "enemy_sheet_id"]:
			if (
				typeof(resource.get(key)) != TYPE_STRING
				or String(resource.get(key)).is_empty()
			):
				return _failure("level enemy resource %s must be a nonempty string" % key)
		if (
			not _is_json_integer(resource.get("kill_score"))
			or int(resource.kill_score) < 0
		):
			return _failure("level enemy resource kill_score must be nonnegative")
		normalized.append({
			"resource_slot_id": int(resource.resource_slot_id),
			"raw_name": String(resource.raw_name),
			"enemy_sheet_id": String(resource.enemy_sheet_id),
			"kill_score": int(resource.kill_score),
		})
	var slot_one := normalized[0] as Dictionary
	if (
		String(level.get("enemy_sprite", "")) != String(slot_one.enemy_sheet_id)
		or int(level.get("ordinary_kill_score", -1)) != int(slot_one.kill_score)
	):
		return _failure("level scalar enemy aliases must equal enemy resource slot 1")
	return _success(normalized)


static func _validate_level_resource_references(
	authored: Dictionary,
	enemy_resources: Array,
	allow_mode_four: bool
) -> Dictionary:
	if authored.is_empty():
		return _success(true)
	var declared_slots: Dictionary = {}
	for resource_value in enemy_resources:
		var resource := resource_value as Dictionary
		declared_slots[int(resource.resource_slot_id)] = true
	for group_value in authored.get("groups", []):
		var group := group_value as Dictionary
		for enemy_value in group.get("enemies", []):
			var enemy := enemy_value as Dictionary
			var slot_id := int(enemy.get("resource_slot_id", -1))
			if allow_mode_four and slot_id == 0:
				continue
			if not declared_slots.has(slot_id):
				return _failure(
					"authored enemy resource slot %d has no level binding" % slot_id
				)
	var supplemental: Array = authored.get(
		"supplemental_spawn_records_raw_words",
		[]
	)
	for record_index in range(mini(4, supplemental.size())):
		var record := supplemental[record_index] as Array
		if int(record[0]) > 0 and not declared_slots.has(int(record[1])):
			return _failure(
				"authored supplemental resource slot %d has no level binding"
				% int(record[1])
			)
	return _success(true)


static func _validate_authored_lvd(
	value: Variant,
	level_id: int,
	allow_mode_four: bool = false,
	mode_four_opcode_allowlist: Array = []
) -> Dictionary:
	# Preserve the original three-argument mode-4 API. Exact encounter callers
	# pass their contract-specific allowlist, while legacy callers historically
	# received the Level-25 superset (including the unused opcode 6).
	var effective_mode_four_opcode_allowlist := mode_four_opcode_allowlist
	if allow_mode_four and effective_mode_four_opcode_allowlist.is_empty():
		effective_mode_four_opcode_allowlist = [0, 1, 2, 6, 7]
	if value == null:
		return _success({})
	if typeof(value) != TYPE_DICTIONARY:
		return _failure("level authored_lvd must be an object")
	var authored: Dictionary = value
	if String(authored.get("schema", "")) != AUTHORED_LVD_SCHEMA:
		return _failure("level authored_lvd schema is unsupported")
	if typeof(authored.get("source_title_cp1252")) != TYPE_STRING:
		return _failure("level authored_lvd source title must be a string")
	for key in ["level_mode_id", "logical_width"]:
		if not _is_json_integer(authored.get(key)):
			return _failure("level authored_lvd %s must be an integer" % key)
	if int(authored.logical_width) != 800:
		return _failure("level authored_lvd logical_width must be 800")
	var level_mode_id := int(authored.level_mode_id)
	if allow_mode_four:
		if level_mode_id != 4:
			return _failure("the validated boss encounter must use mode 4")
	elif level_mode_id == 6:
		if not MODE_SIX_LEVEL_IDS.has(level_id):
			return _failure("authored mode 6 is bound to an unsupported level")
	elif level_mode_id not in [1, 2, 3]:
		return _failure("ordinary authored levels use only modes 1, 2, 3, or 6")
	elif MODE_SIX_LEVEL_IDS.has(level_id):
		return _failure("the authored mode-6 level membership diverges from retail")
	if typeof(authored.get("mirror_x")) != TYPE_BOOL:
		return _failure("level authored_lvd mirror_x must be a boolean")
	var expected_mirror := (int(level_id / 100) & 1) == 1
	if bool(authored.mirror_x) != expected_mirror:
		return _failure("level authored_lvd mirror_x does not match its level number")
	if typeof(authored.get("supplemental_spawn_records_raw_words")) != TYPE_ARRAY:
		return _failure("level authored_lvd supplemental records must be an array")
	var supplemental_records: Array = authored.supplemental_spawn_records_raw_words
	if supplemental_records.size() != 5:
		return _failure("level authored_lvd must contain five supplemental records")
	var normalized_supplemental: Array = []
	for record_value in supplemental_records:
		if typeof(record_value) != TYPE_ARRAY:
			return _failure("level authored_lvd supplemental records must be arrays")
		var record: Array = record_value
		if record.size() != 5:
			return _failure("level authored_lvd supplemental records must contain five words")
		var normalized_record: Array[int] = []
		for word in record:
			if not _is_json_integer(word):
				return _failure("level authored_lvd supplemental words must be integers")
			normalized_record.append(int(word))
		normalized_supplemental.append(normalized_record)
	if typeof(authored.get("fixed_table_records_raw_words")) != TYPE_ARRAY:
		return _failure("level authored_lvd fixed-table records must be an array")
	var fixed_records: Array = authored.fixed_table_records_raw_words
	if fixed_records.size() != 50:
		return _failure("level authored_lvd must contain fifty fixed-table records")
	var normalized_fixed: Array = []
	for record_value in fixed_records:
		if typeof(record_value) != TYPE_ARRAY:
			return _failure("level authored_lvd fixed-table records must be arrays")
		var record: Array = record_value
		if record.size() != 4:
			return _failure("level authored_lvd fixed-table records must contain four words")
		var normalized_record: Array[int] = []
		for word in record:
			if not _is_json_integer(word):
				return _failure("level authored_lvd fixed-table words must be integers")
			normalized_record.append(int(word))
		normalized_fixed.append(normalized_record)
	if typeof(authored.get("groups")) != TYPE_ARRAY:
		return _failure("level authored_lvd groups must be an array")
	var groups_value: Array = authored.groups
	if groups_value.is_empty() or groups_value.size() > 25:
		return _failure("level authored_lvd group count must be between 1 and 25")
	var groups: Array = []
	for group_index in range(groups_value.size()):
		var group_value: Variant = groups_value[group_index]
		if typeof(group_value) != TYPE_DICTIONARY:
			return _failure("level authored_lvd group entries must be objects")
		var group: Dictionary = group_value
		for key in [
			"id",
			"entry_origin_x",
			"entry_origin_y",
			"first_activation_delay_ticks",
			"activation_stagger_ticks",
			"initial_velocity_x_milli",
			"initial_velocity_y_milli",
			"kill_cohort_id",
			"group_mode_id",
		]:
			if not _is_json_integer(group.get(key)):
				return _failure("authored group %s must be an integer" % key)
		if int(group.id) != group_index:
			return _failure("authored group IDs must be contiguous")
		if int(group.first_activation_delay_ticks) < 0 or int(group.activation_stagger_ticks) < 0:
			return _failure("authored group activation delays must be nonnegative")
		if int(group.kill_cohort_id) < 0:
			return _failure("authored group kill_cohort_id must be nonnegative")
		var group_mode_id := int(group.group_mode_id)
		var valid_group_mode := false
		if allow_mode_four:
			valid_group_mode = group_mode_id in [4, 5, 6, 7]
		elif level_id == 80:
			valid_group_mode = (
				(group_index in [0, 1] and group_mode_id == 3)
				or (group_index not in [0, 1] and group_mode_id == 1)
			)
		else:
			valid_group_mode = group_mode_id == 1
		if not valid_group_mode:
			return _failure("authored group mode is invalid for this encounter")
		var enemies_result := _validate_authored_enemies(
			group.get("enemies"),
			allow_mode_four
		)
		if not enemies_result.ok:
			return enemies_result
		var path_opcode_allowlist := effective_mode_four_opcode_allowlist
		if not allow_mode_four and level_id == 94:
			path_opcode_allowlist = [0, 1, 2, 6]
		var path_result := _validate_authored_path(
			group.get("path_points"),
			path_opcode_allowlist
		)
		if not path_result.ok:
			return path_result
		groups.append({
			"id": group_index,
			"entry_origin_x": int(group.entry_origin_x),
			"entry_origin_y": int(group.entry_origin_y),
			"first_activation_delay_ticks": int(group.first_activation_delay_ticks),
			"activation_stagger_ticks": int(group.activation_stagger_ticks),
			"initial_velocity_x_milli": int(group.initial_velocity_x_milli),
			"initial_velocity_y_milli": int(group.initial_velocity_y_milli),
			"kill_cohort_id": int(group.kill_cohort_id),
			"group_mode_id": int(group.group_mode_id),
			"enemies": enemies_result.value,
			"path_points": path_result.value,
		})
	if level_id == 80:
		if groups.size() != 10:
			return _failure("level 80 must contain its exact ten authored groups")
	if level_id == 94:
		if groups.size() != 4:
			return _failure("level 94 must contain its exact four authored groups")
		var opcode_two_count := 0
		for group_value in groups:
			var path_points := (group_value as Dictionary).path_points as Array
			for point_index in range(path_points.size()):
				if int((path_points[point_index] as Dictionary).opcode) != 2:
					continue
				opcode_two_count += 1
				if point_index != 1:
					return _failure("level 94 opcode 2 must remain at authored path index 1")
		if opcode_two_count != 4:
			return _failure("level 94 must contain exactly four opcode-2 no-op scans")
	return _success({
		"schema": AUTHORED_LVD_SCHEMA,
		"source_title_cp1252": String(authored.source_title_cp1252),
		"level_mode_id": level_mode_id,
		"logical_width": 800,
		"mirror_x": bool(authored.mirror_x),
		"supplemental_spawn_records_raw_words": normalized_supplemental,
		"fixed_table_records_raw_words": normalized_fixed,
		"groups": groups,
	})


static func _validate_authored_enemies(
	value: Variant,
	allow_resource_slot_zero: bool = false
) -> Dictionary:
	if typeof(value) != TYPE_ARRAY:
		return _failure("authored group enemies must be an array")
	var enemy_values: Array = value
	if enemy_values.is_empty() or enemy_values.size() > 50:
		return _failure("authored enemy count must be between 1 and 50")
	var enemies: Array = []
	for enemy_index in range(enemy_values.size()):
		var enemy_value: Variant = enemy_values[enemy_index]
		if typeof(enemy_value) != TYPE_DICTIONARY:
			return _failure("authored enemy entries must be objects")
		var enemy: Dictionary = enemy_value
		for key in [
			"id",
			"formation_target_x",
			"formation_target_y",
			"resource_slot_id",
			"base_health",
			"behavior_timer_a_initial",
			"behavior_timer_a_step",
			"behavior_timer_b_initial",
			"behavior_timer_b_step",
		]:
			if not _is_json_integer(enemy.get(key)):
				return _failure("authored enemy %s must be an integer" % key)
		if int(enemy.id) != enemy_index:
			return _failure("authored enemy IDs must be contiguous")
		var minimum_resource_slot := 0 if allow_resource_slot_zero else 1
		if (
			int(enemy.resource_slot_id) < minimum_resource_slot
			or int(enemy.resource_slot_id) > 6
		):
			return _failure(
				"authored enemy resource_slot_id is invalid for this encounter"
			)
		if int(enemy.base_health) <= 0:
			return _failure("authored enemy base_health must be positive")
		enemies.append({
			"id": enemy_index,
			"formation_target_x": int(enemy.formation_target_x),
			"formation_target_y": int(enemy.formation_target_y),
			"resource_slot_id": int(enemy.resource_slot_id),
			"base_health": int(enemy.base_health),
			"behavior_timer_a_initial": int(enemy.behavior_timer_a_initial),
			"behavior_timer_a_step": int(enemy.behavior_timer_a_step),
			"behavior_timer_b_initial": int(enemy.behavior_timer_b_initial),
			"behavior_timer_b_step": int(enemy.behavior_timer_b_step),
		})
	return _success(enemies)


static func _validate_authored_path(
	value: Variant,
	mode_four_opcode_allowlist: Array = []
) -> Dictionary:
	if typeof(value) != TYPE_ARRAY:
		return _failure("authored group path_points must be an array")
	var point_values: Array = value
	if (
		point_values.size() > 150
		or (point_values.is_empty() and mode_four_opcode_allowlist.is_empty())
	):
		return _failure("authored path point count is invalid for this encounter")
	var points: Array = []
	for point_index in range(point_values.size()):
		var point_value: Variant = point_values[point_index]
		if typeof(point_value) != TYPE_DICTIONARY:
			return _failure("authored path points must be objects")
		var point: Dictionary = point_value
		for key in [
			"id",
			"acceleration_x_milli",
			"acceleration_y_milli",
			"opcode",
			"unknown_0c",
			"duration_threshold_ticks",
		]:
			if not _is_json_integer(point.get(key)):
				return _failure("authored path point %s must be an integer" % key)
		if int(point.id) != point_index:
			return _failure("authored path point IDs must be contiguous")
		var supported_opcodes: Array[int] = []
		var source_opcodes := (
			mode_four_opcode_allowlist
			if not mode_four_opcode_allowlist.is_empty()
			else SUPPORTED_AUTHORED_PATH_OPCODES
		)
		for opcode_value in source_opcodes:
			if not _is_json_integer(opcode_value):
				return _failure("authored path opcode allowlist is malformed")
			supported_opcodes.append(int(opcode_value))
		if not supported_opcodes.has(int(point.opcode)):
			return _failure("authored path opcode is unsupported by the simulation")
		if int(point.duration_threshold_ticks) < 0:
			return _failure("authored path duration must be nonnegative")
		points.append({
			"id": point_index,
			"acceleration_x_milli": int(point.acceleration_x_milli),
			"acceleration_y_milli": int(point.acceleration_y_milli),
			"opcode": int(point.opcode),
			"unknown_0c": int(point.unknown_0c),
			"duration_threshold_ticks": int(point.duration_threshold_ticks),
		})
	return _success(points)


static func _validate_shop(document: Dictionary) -> Dictionary:
	if not _version_is_supported(document):
		return _failure("shop.json has an unsupported version")
	if typeof(document.get("items")) != TYPE_ARRAY:
		return _failure("shop.json is missing items")
	var normalized: Array = []
	var ids: Dictionary = {}
	for value in document.items:
		if typeof(value) != TYPE_DICTIONARY:
			return _failure("shop entries must be objects")
		var item: Dictionary = value
		for key in ["id", "price"]:
			if not _is_json_integer(item.get(key)):
				return _failure("shop item %s must be an integer" % key)
		for key in ["name", "category", "effect"]:
			if typeof(item.get(key)) != TYPE_STRING:
				return _failure("shop item %s must be a string" % key)
		if not SUPPORTED_EFFECTS.has(String(item.effect)):
			return _failure("shop item effect is unsupported")
		var item_id := int(item.id)
		if ids.has(item_id):
			return _failure("duplicate shop item id %d" % item_id)
		ids[item_id] = true
		var normalized_item := {
			"id": item_id,
			"name": String(item.name),
			"price": max(0, int(item.price)),
			"category": String(item.category),
			"effect": String(item.effect),
		}
		if item.has("weapon_id"):
			if not _is_json_integer(item.weapon_id):
				return _failure("shop weapon_id must be an integer")
			normalized_item["weapon_id"] = int(item.weapon_id)
		if item.has("unlock"):
			if typeof(item.unlock) != TYPE_DICTIONARY:
				return _failure("shop unlock must be an object")
			var unlock: Dictionary = item.unlock
			if typeof(unlock.get("kind")) != TYPE_STRING or not _is_json_integer(unlock.get("threshold")):
				return _failure("shop unlock is malformed")
			normalized_item["unlock"] = {
				"kind": String(unlock.kind),
				"threshold": int(unlock.threshold),
			}
		else:
			normalized_item["unlock"] = {"kind": "always", "threshold": 0}
		normalized.append(normalized_item)
	var accuracy_thresholds := {18: 70, 19: 80, 20: 90}
	for item_value in normalized:
		var normalized_item := item_value as Dictionary
		var item_id := int(normalized_item.id)
		if not accuracy_thresholds.has(item_id):
			continue
		var unlock := normalized_item.unlock as Dictionary
		if (
			String(unlock.get("kind", "")) != "hit_percent_above_level_25"
			or int(unlock.get("threshold", -1)) != int(accuracy_thresholds[item_id])
		):
			return _failure(
				"shop item %d accuracy threshold diverges from retail history"
				% item_id
			)
	for item_id in accuracy_thresholds:
		if not ids.has(item_id):
			return _failure("shop.json is missing historical item %d" % item_id)
	return _success(normalized)


static func _validate_difficulties(document: Dictionary) -> Dictionary:
	# v2 added the hurry-up special-ship health and speed bases, v3 the
	# planet-debris hazard rules, and v4 the two G20 secret-ship health bases
	# (docs/evidence/HURRY_UP_SECRET_SHIPS.md).
	if not _is_json_integer(document.get("version")) or int(document.version) != 4:
		return _failure("difficulties.json has an unsupported version")
	if typeof(document.get("difficulties")) != TYPE_ARRAY:
		return _failure("difficulties.json is missing difficulties")
	var normalized: Array = []
	var ids: Dictionary = {}
	for value in document.difficulties:
		if typeof(value) != TYPE_DICTIONARY:
			return _failure("difficulty entries must be objects")
		var difficulty: Dictionary = value
		if typeof(difficulty.get("id")) != TYPE_STRING or typeof(difficulty.get("name")) != TYPE_STRING:
			return _failure("difficulty ids and names must be strings")
		for key in [
			"simulation_scale_numerator",
			"simulation_scale_denominator",
			"timer_a_initial_adjustment",
			"timer_a_floor",
			"timer_b_initial_adjustment",
			"timer_b_floor",
			"timed_effect_seconds",
			"bonus_time_start",
			"bonus_time_max",
			"bonus_time_floor",
			"bonus_drop_denominator",
			"alien_projectile_speed_numerator",
			"alien_projectile_speed_denominator",
			"player_base_speed_numerator",
			"player_base_speed_denominator",
			"player_speed_upgrade_numerator",
			"player_speed_upgrade_denominator",
			# Hurry-up special-ship bases (docs/evidence/HURRY_UP_SECRET_SHIPS.md).
			"special_health_base_a",
			"special_health_base_b",
			"special_health_base_c",
			"special_health_base_d",
			"special_speed_maximum",
			# Planet-debris hazard rules (same evidence document).
			"debris_lifetime_base",
			"debris_lifetime_range",
			"debris_speed_minimum_milli",
			"debris_speed_maximum_milli",
			"debris_steering_threshold",
		]:
			if not _is_json_integer(difficulty.get(key)):
				return _failure("difficulty %s must be an integer" % key)
		for key in [
			"simulation_scale_numerator",
			"simulation_scale_denominator",
			"timer_a_floor",
			"timer_b_floor",
			"timed_effect_seconds",
			"bonus_time_start",
			"bonus_time_max",
			"bonus_time_floor",
			"bonus_drop_denominator",
			"alien_projectile_speed_numerator",
			"alien_projectile_speed_denominator",
			"player_base_speed_numerator",
			"player_base_speed_denominator",
			"player_speed_upgrade_numerator",
			"player_speed_upgrade_denominator",
			"special_health_base_a",
			"special_health_base_b",
			"special_health_base_c",
			"special_health_base_d",
			"special_speed_maximum",
			"debris_lifetime_base",
			"debris_lifetime_range",
			"debris_speed_minimum_milli",
			"debris_speed_maximum_milli",
			"debris_steering_threshold",
		]:
			if int(difficulty.get(key)) <= 0:
				return _failure("difficulty %s must be positive" % key)
		var difficulty_id := String(difficulty.id)
		if ids.has(difficulty_id):
			return _failure("duplicate difficulty id %s" % difficulty_id)
		ids[difficulty_id] = true
		var scale_numerator := int(difficulty.simulation_scale_numerator)
		var scale_denominator := int(difficulty.simulation_scale_denominator)
		if scale_denominator != 6:
			return _failure("difficulty simulation scale denominator must be six")
		var player_base_speed_fp := _ratio_to_fp(
			int(difficulty.player_base_speed_numerator),
			int(difficulty.player_base_speed_denominator)
		)
		var player_speed_upgrade_fp := _ratio_to_fp(
			int(difficulty.player_speed_upgrade_numerator),
			int(difficulty.player_speed_upgrade_denominator)
		)
		normalized.append({
			"id": difficulty_id,
			"name": String(difficulty.name),
			"simulation_scale_numerator": scale_numerator,
			"simulation_scale_denominator": scale_denominator,
			"timer_a_initial_adjustment": int(difficulty.timer_a_initial_adjustment),
			"timer_a_floor": int(difficulty.timer_a_floor),
			"timer_b_initial_adjustment": int(difficulty.timer_b_initial_adjustment),
			"timer_b_floor": int(difficulty.timer_b_floor),
			"timed_effect_seconds": int(difficulty.timed_effect_seconds),
			"bonus_time_start": int(difficulty.bonus_time_start),
			"bonus_time_max": int(difficulty.bonus_time_max),
			"bonus_time_floor": int(difficulty.bonus_time_floor),
			"bonus_drop_denominator": int(difficulty.bonus_drop_denominator),
			"alien_projectile_speed_fp": _ratio_to_fp(
				int(difficulty.alien_projectile_speed_numerator),
				int(difficulty.alien_projectile_speed_denominator)
			),
			"player_base_speed_fp": player_base_speed_fp,
			"player_speed_upgrade_fp": player_speed_upgrade_fp,
			"player_speed_cap_fp": player_base_speed_fp + 16 * player_speed_upgrade_fp,
			"special_health_base_a": int(difficulty.special_health_base_a),
			"special_health_base_b": int(difficulty.special_health_base_b),
			"special_health_base_c": int(difficulty.special_health_base_c),
			"special_health_base_d": int(difficulty.special_health_base_d),
			"special_speed_maximum": int(difficulty.special_speed_maximum),
			"debris_lifetime_base": int(difficulty.debris_lifetime_base),
			"debris_lifetime_range": int(difficulty.debris_lifetime_range),
			"debris_speed_minimum_milli": int(difficulty.debris_speed_minimum_milli),
			"debris_speed_maximum_milli": int(difficulty.debris_speed_maximum_milli),
			"debris_steering_threshold": int(difficulty.debris_steering_threshold),
		})
	for required_id in ["easy", "normal", "hard", "ace"]:
		if not ids.has(required_id):
			return _failure("difficulties.json is missing %s" % required_id)
	return _success(normalized)


static func _validate_sprite_frames(document: Dictionary) -> Dictionary:
	if (
		not _is_json_integer(document.get("version"))
		or not SPRITE_CATALOG_LEVEL_COUNTS.has(int(document.version))
	):
		return _failure("sprite_frames.json has an unsupported version")
	var catalog_version := int(document.version)
	if String(document.get("schema", "")) != "warblade.sprite-frames.v%d" % catalog_version:
		return _failure("sprite_frames.json has an unsupported schema")
	if catalog_version >= 10 and not _state_ten_frame_contract_is_exact(document):
		return _failure("sprite_frames.json state-10 frame producer is invalid")
	var enemy_layout: Variant = document.get("enemy_frame_layout")
	var fighter_sheets: Variant = document.get("fighter_sheets")
	var projectile_sheet: Variant = document.get("projectile_sheet")
	var level_usage: Variant = document.get("level_usage")
	var enemy_sheets: Variant = document.get("enemy_sheets")
	var hit_mask_format: Variant = document.get("hit_mask_format")
	var supplemental_linkages: Variant = document.get("supplemental_spawn_linkages")
	if typeof(enemy_layout) != TYPE_DICTIONARY:
		return _failure("sprite_frames.json is missing enemy_frame_layout")
	if typeof(fighter_sheets) != TYPE_ARRAY or (fighter_sheets as Array).size() != 2:
		return _failure("sprite_frames.json must contain two fighter sheets")
	if typeof(projectile_sheet) != TYPE_DICTIONARY:
		return _failure("sprite_frames.json is missing projectile_sheet")
	if not hit_mask_format is Dictionary:
		return _failure("sprite_frames.json is missing hit-mask provenance")
	var hit_mask_assets: Variant = (hit_mask_format as Dictionary).get("assets")
	if not hit_mask_assets is Array:
		return _failure("sprite_frames.json is missing hit-mask asset pins")
	var hit_mask_assets_by_id: Dictionary = {}
	for asset_value in hit_mask_assets as Array:
		if not asset_value is Dictionary:
			return _failure("sprite hit-mask asset pins must be objects")
		var asset := asset_value as Dictionary
		var asset_id := String(asset.get("id", ""))
		if (
			asset_id.is_empty()
			or hit_mask_assets_by_id.has(asset_id)
			or not _is_lower_hex_sha256(String(asset.get("hit_mask_sha256", "")))
		):
			return _failure("sprite hit-mask asset pins are missing, duplicated, or invalid")
		hit_mask_assets_by_id[asset_id] = asset
	var expected_level_count := int(SPRITE_CATALOG_LEVEL_COUNTS[catalog_version])
	if (
		typeof(level_usage) != TYPE_ARRAY
		or (level_usage as Array).size() != expected_level_count
	):
		return _failure(
			"sprite_frames.json must contain %d level usage records"
			% expected_level_count
		)
	var expected_sheet_ids := [
		"alien001", "alien_2", "alien_3", "alien000", "alien_lilla",
	]
	if catalog_version >= 3:
		expected_sheet_ids.append_array([
			"alien003",
			"alien003_3",
			"alien_big1_1",
			"alien_big1_2",
			"alien_big1_3",
			"alien_big1_4",
			"alien_big1_5",
			"alien_big1_6",
		])
	if catalog_version >= 4:
		expected_sheet_ids.append_array([
			"alien_rakett",
			"alien_rakett_gronn",
			"alien_baller",
			"alien_baller2",
		])
	if catalog_version >= 5:
		expected_sheet_ids.append_array([
			"alien_green_lilla_t",
			"alien_cyan_lilla_t",
		])
	if catalog_version >= 6:
		expected_sheet_ids.append_array([
			"alien_raudkule",
			"alien_raudkule2",
			"alien_blavinger_gf",
			"alien_blavinger_gf2",
			"alien_rbille",
		])
	if catalog_version >= 7:
		expected_sheet_ids.append_array([
			"alien_big2_1",
			"alien_big2_2",
			"alien_big2_3",
			"alien_big2_4",
			"alien_big2_5",
			"alien_big2_6",
		])
	if catalog_version >= 8:
		expected_sheet_ids.append_array([
			"alien_gultop",
			"alien_lillatop",
			"alien_bluekreps",
			"alien_lbluekreps",
			"alien_brownkreps",
			"alien_brownkreps2",
			"alien_gulkreps",
			"alien_rvinggk",
			"alien_gvingbk",
		])
	if catalog_version >= 9:
		expected_sheet_ids.append_array([
			"alien_lila_royr", "alien_lblaa_royr",
			"alien_lilla_makk", "alien_lblaa_makk",
			"alien_rocktalien", "alien_rocktalieng",
			"alien_big3_1", "alien_big3_2", "alien_big3_3",
			"alien_big3_4", "alien_big3_5", "alien_big3_6",
			"alien_gspis", "alien_rspis",
			"alien001_gul", "alien001_raud", "alien001_blue", "alien002",
			"alien_lysper2", "alien_lysper",
			"alien_n1_bla", "alien_n1_gron", "alien_n1_lilla",
			"alien_n2_bla", "alien_n2_red", "alien_n2_green",
			"alien_metaballs", "alien_metaball2", "alien_metaball3",
			"alien_kuler", "alien_kuleg", "alien_kuleb", "alien_kuleo",
			"alien_kulel", "alien_mkuler",
			"alien_big4_1", "alien_big4_2", "alien_big4_3",
			"alien_big4_4", "alien_big4_5", "alien_big4_6",
		])
	if catalog_version >= 11:
		# Retail match mode 6 binds eighteen sheets no classic level references.
		expected_sheet_ids.append_array([
			"alien_timetrial_1", "alien_timetrial_3k", "alien_timetrial_2",
			"alien3", "alien_timetrial_3", "alien_timetrial_3b",
			"alien_timetrial_3c", "alien_10_green", "alien_10", "alien_10_lilla",
			"alien_12", "alien_12_blue", "alien_12_red", "alien_11",
			"alien_11_gul", "alien_13", "alien_13_orange", "alien002_cyan",
		])
	var expected_usage_ids := [
		"alien001", "alien001", "alien001", "alien001",
		"alien_2", "alien_2", "alien_2", "alien_2",
		"alien_3", "alien_3", "alien_3", "alien_3",
		"alien000", "alien000", "alien000", "alien000",
		"alien_lilla", "alien_lilla", "alien_lilla", "alien_lilla",
	]
	if catalog_version >= 3:
		expected_usage_ids.append_array([
			"alien003", "alien003", "alien003", "alien003", "alien_big1_1",
		])
	if catalog_version >= 4:
		expected_usage_ids.append_array([
			"alien_rakett", "alien_rakett", "alien_rakett", "alien_rakett", "alien_baller",
		])
	if catalog_version >= 5:
		expected_usage_ids.append_array([
			"alien_baller", "alien_baller", "alien_baller",
			"alien_green_lilla_t", "alien_green_lilla_t",
		])
	if catalog_version >= 6:
		expected_usage_ids.append_array([
			"alien_green_lilla_t", "alien_green_lilla_t",
			"alien_raudkule", "alien_raudkule", "alien_raudkule", "alien_raudkule",
			"alien_blavinger_gf", "alien_blavinger_gf", "alien_blavinger_gf",
			"alien_blavinger_gf2",
			"alien_rbille", "alien_rbille", "alien_rbille", "alien_rbille",
		])
	if catalog_version >= 7:
		expected_usage_ids.append("alien_big2_1")
	if catalog_version >= 8:
		expected_usage_ids.append_array([
			"alien_gultop", "alien_gultop", "alien_gultop", "alien_gultop",
			"alien_bluekreps", "alien_bluekreps", "alien_bluekreps",
			"alien_brownkreps2",
			"alien_rvinggk", "alien_rvinggk", "alien_rvinggk",
			"alien_gvingbk",
		])
	if catalog_version >= 9:
		expected_usage_ids.append_array([
			"alien_lila_royr", "alien_lblaa_royr", "alien_lblaa_royr",
			"alien_lblaa_royr", "alien_lilla_makk", "alien_lilla_makk",
			"alien_lblaa_makk", "alien_lblaa_makk", "alien_rocktalien",
			"alien_rocktalieng", "alien_rocktalien", "alien_rocktalien",
			"alien_big3_1", "alien_gspis", "alien_gspis", "alien_rspis",
			"alien_rspis", "alien001_gul", "alien001_blue", "alien001_gul",
			"alien001_raud", "alien_lysper2", "alien_lysper2", "alien_lysper2",
			"alien_lysper2", "alien_n1_bla", "alien_n1_bla", "alien_n1_bla",
			"alien_n1_lilla", "alien_n2_bla", "alien_n2_bla", "alien_n2_green",
			"alien_metaballs", "alien003_3", "alien_kuleg", "alien_kuler",
			"alien_n2_bla", "alien_big4_1",
		])
	for usage_index in range(expected_level_count):
		var usage_value: Variant = (level_usage as Array)[usage_index]
		if (
			not usage_value is Dictionary
			or int((usage_value as Dictionary).get("level_id", 0)) != usage_index + 1
		):
			return _failure("sprite_frames.json level usage diverges from retail LVD evidence")
		var usage_sheet_id := String(
			(usage_value as Dictionary).get("enemy_sheet_id", "")
		)
		if usage_sheet_id != expected_usage_ids[usage_index]:
			return _failure("sprite_frames.json level usage diverges from retail LVD evidence")
		if catalog_version >= 3:
			var usage_resources: Variant = (usage_value as Dictionary).get(
				"enemy_resources"
			)
			if not usage_resources is Array or (usage_resources as Array).is_empty():
				return _failure("sprite_frames.json usage is missing enemy resources")
			for resource_index in range((usage_resources as Array).size()):
				var resource_value: Variant = (usage_resources as Array)[resource_index]
				if not resource_value is Dictionary:
					return _failure("sprite level enemy resources must be objects")
				var resource := resource_value as Dictionary
				if (
					int(resource.get("resource_slot_id", 0)) != resource_index + 1
					or typeof(resource.get("raw_name")) != TYPE_STRING
					or String(resource.get("raw_name", "")).is_empty()
					or typeof(resource.get("enemy_sheet_id")) != TYPE_STRING
					or not _is_json_integer(resource.get("kill_score"))
					or int(resource.get("kill_score", -1)) < 0
				):
					return _failure("sprite level enemy resource binding is malformed")
				if not expected_sheet_ids.has(String(resource.enemy_sheet_id)):
					return _failure("sprite level usage references an unknown enemy sheet")
	if (
		typeof(enemy_sheets) != TYPE_ARRAY
		or (enemy_sheets as Array).size() != expected_sheet_ids.size()
	):
		return _failure("sprite_frames.json enemy sheet count is invalid")
	var seen_sheet_ids: Dictionary = {}
	for sheet_index in range(expected_sheet_ids.size()):
		var sheet_value: Variant = (enemy_sheets as Array)[sheet_index]
		if not sheet_value is Dictionary:
			return _failure("sprite_frames.json enemy sheets must be objects")
		var sheet := sheet_value as Dictionary
		var sheet_id := String(sheet.get("id", ""))
		if sheet_id != expected_sheet_ids[sheet_index] or seen_sheet_ids.has(sheet_id):
			return _failure("sprite_frames.json enemy sheet IDs are missing, duplicated, or reordered")
		seen_sheet_ids[sheet_id] = true
		if (
			typeof(sheet.get("texture")) != TYPE_STRING
			or typeof(sheet.get("hit_mask")) != TYPE_STRING
			or not hit_mask_assets_by_id.has(sheet_id)
			or int(sheet.get("sheet_width", 0)) != 576
			or int(sheet.get("sheet_height", 0)) != 96
		):
			return _failure("sprite_frames.json enemy sheet geometry is invalid")
		var hit_mask_asset := hit_mask_assets_by_id[sheet_id] as Dictionary
		if String(hit_mask_asset.get("hit_mask", "")) != String(sheet.hit_mask):
			return _failure("sprite enemy HMA path differs from its SHA-256 pin")
	if typeof(supplemental_linkages) != TYPE_ARRAY:
		return _failure("sprite_frames.json is missing supplemental spawn linkages")
	var expected_supplemental_records := [[3, 0], [7, 0], [11, 0], [15, 0], [19, 0]]
	if catalog_version >= 3:
		expected_supplemental_records.append([23, 0])
	if catalog_version >= 4:
		expected_supplemental_records.append([28, 0])
	if catalog_version >= 5:
		expected_supplemental_records.append([32, 0])
	if catalog_version >= 6:
		expected_supplemental_records.append_array([
			[36, 0], [36, 1], [40, 0], [44, 0], [48, 0],
		])
	if catalog_version >= 8:
		expected_supplemental_records.append_array([
			[53, 0], [53, 1], [57, 0], [61, 0],
		])
	if catalog_version >= 9:
		expected_supplemental_records.append_array([
			[65, 0], [65, 1], [69, 0], [73, 0], [78, 0],
			[82, 0], [86, 0], [90, 0], [94, 0], [98, 0],
		])
	var late_supplemental_contracts := {
		"53:0": {
			"raw_words": [2, 1, 59, 925, 8],
			"fixed_words": [4, 0, 0, 0],
			"resource_selector": 1,
			"enemy_sheet_id": "alien_gultop",
		},
		"53:1": {
			"raw_words": [2, 1, 79, 1054, 22],
			"fixed_words": [4, 0, 0, 0],
			"resource_selector": 1,
			"enemy_sheet_id": "alien_gultop",
		},
		"57:0": {
			"raw_words": [4, 3, 98, 1441, 7],
			"fixed_words": [4, 1, 0, 0],
			"resource_selector": 3,
			"enemy_sheet_id": "alien_brownkreps",
		},
		"61:0": {
			"raw_words": [4, 1, 88, 1162, 23],
			"fixed_words": [4, 1, 0, 0],
			"resource_selector": 1,
			"enemy_sheet_id": "alien_rvinggk",
			"phase_count": 4,
		},
		"65:0": {
			"raw_words": [2, 1, 110, 1484, 14],
			"fixed_words": [4, 1, 0, 0],
			"resource_selector": 1,
			"enemy_sheet_id": "alien_lblaa_royr",
			"phase_count": 4,
		},
		"65:1": {
			"raw_words": [2, 2, 110, 1570, 14],
			"fixed_words": [4, 1, 0, 0],
			"resource_selector": 2,
			"enemy_sheet_id": "alien_lila_royr",
			"phase_count": 4,
		},
		"69:0": {
			"raw_words": [4, 1, 108, 1119, 17],
			"fixed_words": [4, 1, 0, 0],
			"resource_selector": 1,
			"enemy_sheet_id": "alien_lblaa_makk",
			"phase_count": 4,
		},
		"73:0": {
			"raw_words": [5, 1, 110, 1291, 10],
			"fixed_words": [4, 1, 0, 0],
			"resource_selector": 1,
			"enemy_sheet_id": "alien_rocktalien",
			"phase_count": 4,
		},
		"78:0": {
			"raw_words": [4, 1, 98, 1742, 26],
			"fixed_words": [4, 1, 0, 0],
			"resource_selector": 1,
			"enemy_sheet_id": "alien_rspis",
			"phase_count": 4,
		},
		"82:0": {
			"raw_words": [5, 1, 300, 1600, 5],
			"fixed_words": [4, 1, 0, 0],
			"resource_selector": 1,
			"enemy_sheet_id": "alien001_gul",
			"phase_count": 4,
		},
		"86:0": {
			"raw_words": [4, 1, 72, 710, 18],
			"fixed_words": [4, 0, 0, 0],
			"resource_selector": 1,
			"enemy_sheet_id": "alien_lysper2",
			"phase_count": 4,
		},
		"90:0": {
			"raw_words": [3, 2, 118, 1398, 25],
			"fixed_words": [7, 1, 0, 0],
			"resource_selector": 2,
			"enemy_sheet_id": "alien_n1_gron",
			"phase_count": 7,
		},
		"94:0": {
			"raw_words": [4, 1, 118, 968, 23],
			"fixed_words": [7, 1, 0, 0],
			"resource_selector": 1,
			"enemy_sheet_id": "alien_n2_green",
			"phase_count": 7,
		},
		"98:0": {
			"raw_words": [10, 3, 150, 2000, 10],
			"fixed_words": [6, 1, 0, 0],
			"resource_selector": 3,
			"enemy_sheet_id": "alien_mkuler",
			"phase_count": 6,
		},
	}
	if (supplemental_linkages as Array).size() != expected_supplemental_records.size():
		return _failure("sprite_frames.json supplemental spawn linkage count is invalid")
	for linkage_index in range(expected_supplemental_records.size()):
		var linkage_value: Variant = (supplemental_linkages as Array)[linkage_index]
		var expected_record := expected_supplemental_records[linkage_index] as Array
		if (
			not linkage_value is Dictionary
			or int((linkage_value as Dictionary).get("level_id", 0))
			!= int(expected_record[0])
			or int((linkage_value as Dictionary).get("record_index", -1))
			!= int(expected_record[1])
		):
			return _failure("sprite_frames.json supplemental reachability diverges from retail LVD evidence")
		if catalog_version >= 4:
			var linkage := linkage_value as Dictionary
			var phase_count := int(linkage.get("animation_phase_count", 0))
			var valid_phases: Variant = linkage.get("valid_animation_phases")
			var fixed_words: Variant = linkage.get("fixed_record_raw_words")
			var phases_are_contiguous := (
				valid_phases is Array
				and (valid_phases as Array).size() == phase_count
			)
			if phases_are_contiguous:
				for phase_index in range(phase_count):
					if (
						not _is_json_integer((valid_phases as Array)[phase_index])
						or int((valid_phases as Array)[phase_index]) != phase_index
					):
						phases_are_contiguous = false
						break
			var fixed_words_are_integers := fixed_words is Array
			if fixed_words_are_integers:
				for word in fixed_words as Array:
					if not _is_json_integer(word):
						fixed_words_are_integers = false
						break
			if (
				not _is_json_integer(linkage.get("animation_phase_count"))
				or phase_count < 1
				or phase_count > 7
				or not phases_are_contiguous
				or not fixed_words is Array
				or (fixed_words as Array).size() != 4
				or not fixed_words_are_integers
				or int((fixed_words as Array)[0]) != phase_count
			):
				return _failure("sprite supplemental animation phases are invalid")
			if (
				int(linkage.level_id) == 28
				and (
					phase_count != 4
					or int((fixed_words as Array)[0]) != 4
					or int((fixed_words as Array)[1]) != 0
					or int((fixed_words as Array)[2]) != 0
					or int((fixed_words as Array)[3]) != 0
				)
			):
				return _failure("level 28 must use exactly four supplemental phases")
			if int(linkage.level_id) == 32 and phase_count != 4:
				return _failure("level 32 must use exactly four supplemental phases")
			if int(linkage.level_id) in [36, 40, 44, 48] and phase_count != 4:
				return _failure("levels 36, 40, 44, and 48 must use exactly four supplemental phases")
			var late_contract_key := "%d:%d" % [
				int(linkage.level_id),
				int(linkage.record_index),
			]
			if late_supplemental_contracts.has(late_contract_key):
				var expected_late := late_supplemental_contracts[late_contract_key] as Dictionary
				var selector_result_value: Variant = linkage.get("resource_selector_result")
				if not selector_result_value is Dictionary:
					return _failure(
						"late-campaign supplemental linkage is missing its resource binding"
					)
				var selector_result := selector_result_value as Dictionary
				if (
					not _json_integer_array_matches(
						linkage.get("raw_words"),
						expected_late.raw_words
					)
					or not _json_integer_array_matches(
						linkage.get("fixed_record_raw_words"),
						expected_late.fixed_words
					)
					or int(linkage.get("resource_selector", 0))
					!= int(expected_late.resource_selector)
					or String(selector_result.get("enemy_sheet_id", ""))
					!= String(expected_late.enemy_sheet_id)
					or phase_count != int(expected_late.get("phase_count", 4))
				):
					return _failure(
						"late-campaign supplemental linkage diverges from retail LVD evidence"
					)
	var families: Variant = (enemy_layout as Dictionary).get("families")
	if typeof(families) != TYPE_DICTIONARY:
		return _failure("sprite_frames.json is missing enemy frame families")
	for family_id in [
		"directional_32",
		"formation_animation_32",
		"supplemental_large_animation_64",
	]:
		var family: Variant = (families as Dictionary).get(family_id)
		if typeof(family) != TYPE_DICTIONARY:
			return _failure("sprite_frames.json is missing %s" % family_id)
		var frames: Variant = (family as Dictionary).get("frames")
		if typeof(frames) != TYPE_ARRAY or (frames as Array).is_empty():
			return _failure("sprite frame family %s is empty" % family_id)
		if family_id == "supplemental_large_animation_64" and (frames as Array).size() != 7:
			return _failure("sprite supplemental family must contain reachable frames zero through six")
	var projectile_frames: Variant = (projectile_sheet as Dictionary).get("frames")
	if typeof(projectile_frames) != TYPE_ARRAY or (projectile_frames as Array).is_empty():
		return _failure("sprite_frames.json contains no projectile frames")
	for frame_value in projectile_frames as Array:
		if typeof(frame_value) != TYPE_DICTIONARY:
			return _failure("sprite projectile frames must be objects")
		var frame := frame_value as Dictionary
		if (
			not _is_json_integer(frame.get("prototype_id"))
			or not _is_json_integer(frame.get("next_prototype_id"))
			or typeof(frame.get("persistent")) != TYPE_BOOL
		):
			return _failure("sprite projectile animation metadata is invalid")
	var enemy_projectiles: Variant = document.get("enemy_projectile_contracts")
	if not enemy_projectiles is Dictionary:
		return _failure("sprite_frames.json is missing enemy projectile contracts")
	for contract_id in ["ordinary_type_7", "supplemental_state_6_type_6"]:
		var contract_value: Variant = (enemy_projectiles as Dictionary).get(contract_id)
		if not contract_value is Dictionary:
			return _failure("sprite_frames.json is missing %s" % contract_id)
		var sheet_masks: Variant = (contract_value as Dictionary).get("sheet_masks")
		if (
			not sheet_masks is Dictionary
			or (sheet_masks as Dictionary).size() != expected_sheet_ids.size()
		):
			return _failure("sprite enemy projectile contract has incomplete sheet coverage")
		for sheet_id in expected_sheet_ids:
			var mask_value: Variant = (sheet_masks as Dictionary).get(sheet_id)
			if not mask_value is Dictionary:
				return _failure("sprite enemy projectile contract is missing %s" % sheet_id)
			var broad_bounds: Variant = (mask_value as Dictionary).get(
				"retail_broad_phase_bounds"
			)
			var exact_empty_ordinary_cells: bool = (
				catalog_version >= 9
				and contract_id == "ordinary_type_7"
				and sheet_id == "alien_mkuler"
			)
			# Time Trial sheets leave the supplemental state-6 cell blank; no Time
			# Trial level carries a supplemental spawn record, so the rectangle is
			# exactly empty rather than absent.
			var exact_empty_time_trial_cells: bool = (
				catalog_version >= 11
				and contract_id == "supplemental_state_6_type_6"
				and TIME_TRIAL_EMPTY_SUPPLEMENTAL_SHEET_IDS.has(sheet_id)
			)
			var exact_empty_cells := (
				exact_empty_ordinary_cells or exact_empty_time_trial_cells
			)
			if (
				(not exact_empty_cells and (
					not broad_bounds is Array
					or (broad_bounds as Array).size() != 4
				))
				or (
					exact_empty_cells
					and (
						not (mask_value as Dictionary).has("retail_broad_phase_bounds")
						or broad_bounds != null
					)
				)
			):
				return _failure("sprite enemy projectile retail broad-phase metadata is invalid")
			var phases: Variant = (mask_value as Dictionary).get("phases")
			if not phases is Array or (phases as Array).size() != 2:
				return _failure("sprite enemy projectile masks must contain two phases")
			for phase_index in range(2):
				var phase_value: Variant = (phases as Array)[phase_index]
				if not phase_value is Dictionary:
					return _failure("sprite enemy projectile phases must be objects")
				var phase := phase_value as Dictionary
				var bounds: Variant = phase.get("local_inclusive_bounds")
				var occupied_pixel_count: int = int(phase.get("occupied_pixel_count", -1))
				var known_blank_phase: bool = (
					(
						catalog_version >= 6
						and contract_id == "supplemental_state_6_type_6"
						and sheet_id == "alien_raudkule2"
						and phase_index == 1
					)
					or exact_empty_ordinary_cells
					or exact_empty_time_trial_cells
				) and (
					phase.has("local_inclusive_bounds")
					and phase.has("occupied_pixel_count")
					and bounds == null
					and occupied_pixel_count == 0
				)
				if not known_blank_phase and (
					not bounds is Array
					or (bounds as Array).size() != 4
					or occupied_pixel_count <= 0
				):
					return _failure("sprite enemy projectile mask metadata is invalid")
	return _success(document.duplicate(true))


static func _state_ten_frame_contract_is_exact(document: Dictionary) -> bool:
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


static func _validate_level_sprite_bindings(
	levels: Array,
	sprites: Dictionary
) -> Dictionary:
	var level_usage: Array = sprites.get("level_usage", [])
	if level_usage.size() != levels.size():
		return _failure("level and sprite resource binding counts diverge")
	var sheet_ids: Dictionary = {}
	for sheet_value in sprites.get("enemy_sheets", []):
		if not sheet_value is Dictionary:
			return _failure("sprite enemy sheet definition must be an object")
		var sheet := sheet_value as Dictionary
		var sheet_id := String(sheet.get("id", ""))
		if (
			sheet_id.is_empty()
			or String(sheet.get("texture", "")).is_empty()
			or String(sheet.get("hit_mask", "")).is_empty()
		):
			return _failure("sprite enemy sheet resource is incomplete")
		sheet_ids[sheet_id] = true
	for level_index in range(levels.size()):
		var level := levels[level_index] as Dictionary
		var usage := level_usage[level_index] as Dictionary
		if int(usage.get("level_id", 0)) != int(level.id):
			return _failure("level and sprite resource binding order diverges")
		var level_resources: Array = level.get("enemy_resources", [])
		var usage_resources: Array = usage.get("enemy_resources", [])
		if int(sprites.get("version", 0)) == 2:
			usage_resources = [{
				"resource_slot_id": 1,
				"raw_name": String(level_resources[0].raw_name),
				"enemy_sheet_id": String(usage.get("enemy_sheet_id", "")),
				"kill_score": int(level_resources[0].kill_score),
			}]
		if usage_resources.size() != level_resources.size():
			return _failure("sprite usage omits a level enemy resource binding")
		for resource_index in range(level_resources.size()):
			var level_resource := level_resources[resource_index] as Dictionary
			var usage_resource := usage_resources[resource_index] as Dictionary
			for key in ["resource_slot_id", "raw_name", "enemy_sheet_id", "kill_score"]:
				if level_resource.get(key) != usage_resource.get(key):
					return _failure(
						"level and sprite resource binding field %s diverges" % key
					)
			if not sheet_ids.has(String(level_resource.enemy_sheet_id)):
				return _failure("level enemy resource references an undefined sprite sheet")
	return _success(true)


static func _validate_time_trial(document: Dictionary) -> Dictionary:
	# Retail match mode 6 is its own fifteen-level product with a fixed clock.
	# The authored payloads reuse the classic authored-LVD schema, so the shared
	# validators stay authoritative; only the mode rules are Time Trial specific.
	if String(document.get("schema", "")) != TIME_TRIAL_SCHEMA:
		return _failure("time_trial.json has an unsupported schema")
	var runtime_value: Variant = document.get("runtime")
	if not runtime_value is Dictionary:
		return _failure("time_trial.json is missing its runtime contract")
	var runtime := runtime_value as Dictionary
	if int(runtime.get("retail_match_mode_id", -1)) != TIME_TRIAL_RETAIL_MATCH_MODE_ID:
		return _failure("time_trial.json must declare retail match mode 6")
	var clock_value: Variant = runtime.get("clock")
	if not clock_value is Dictionary:
		return _failure("time_trial.json is missing its match clock")
	var clock := clock_value as Dictionary
	if (
		int(clock.get("match_milliseconds", 0)) != TIME_TRIAL_MATCH_CLOCK_MS
		or int(clock.get("grouped_best_extra_minute_milliseconds", 0))
		!= TIME_TRIAL_EXTRA_MINUTE_CLOCK_MS
		or int(clock.get("missing_levels_milliseconds", 0))
		!= TIME_TRIAL_MISSING_LEVELS_CLOCK_MS
		or String(clock.get("expiry_behavior", "")) != "game_over"
	):
		return _failure("time_trial.json match clock diverges from retail evidence")
	var rules_value: Variant = runtime.get("rules")
	if not rules_value is Dictionary:
		return _failure("time_trial.json is missing its mode rules")
	var rules := rules_value as Dictionary
	for disabled_key in [
		"shops",
		"warp",
		"warp_malfunction",
		"bonus_modes",
		"rank_promotion",
		"credits",
		"hurry_up_special_ships",
		"death_resets_loadout",
	]:
		if rules.get(disabled_key) != false:
			return _failure(
				"time_trial.json must disable %s in match mode 6" % disabled_key
			)
	if (
		int(rules.get("starting_weapon_id", -1)) != 0
		or int(rules.get("seats", 0)) != 1
		or String(rules.get("tally_kind", "")) != "time_trial"
		or String(rules.get("hiscore_table_kind", "")) != "timetrial"
	):
		return _failure("time_trial.json mode rules diverge from retail evidence")
	var loader_value: Variant = runtime.get("loader")
	if not loader_value is Dictionary:
		return _failure("time_trial.json is missing its level loader contract")
	var loader := loader_value as Dictionary
	if (
		String(loader.get("file_format", "")) != "timetrial_%02d.lvd"
		or int(loader.get("authored_level_count", 0)) != TIME_TRIAL_LEVEL_COUNT
		or String(loader.get("selection", "")) != "sequential_level_counter"
		or loader.get("wrap_after_last_level") != true
	):
		return _failure("time_trial.json loader diverges from retail evidence")
	var levels_value: Variant = document.get("levels")
	if not levels_value is Array:
		return _failure("time_trial.json is missing levels")
	var levels := levels_value as Array
	if levels.size() != TIME_TRIAL_LEVEL_COUNT:
		return _failure(
			"time_trial.json must contain exactly the %d authored levels"
			% TIME_TRIAL_LEVEL_COUNT
		)
	var normalized: Array = []
	for level_index in range(levels.size()):
		var level_value: Variant = levels[level_index]
		if not level_value is Dictionary:
			return _failure("Time Trial level entries must be objects")
		var level := level_value as Dictionary
		if not _is_json_integer(level.get("id")) or int(level.id) != level_index + 1:
			return _failure("Time Trial level IDs must run 1 through 15 in order")
		var level_id := int(level.id)
		for key in ["title", "author", "enemy_sprite"]:
			if typeof(level.get(key)) != TYPE_STRING:
				return _failure("Time Trial level %s must be a string" % key)
		if level.get("shop_after") != false:
			return _failure("Time Trial levels must never declare a shop")
		if (
			not _is_json_integer(level.get("ordinary_kill_score"))
			or int(level.ordinary_kill_score) < 0
		):
			return _failure("Time Trial level ordinary_kill_score must be nonnegative")
		var resources_result := _validate_enemy_resources(level, 9)
		if not resources_result.ok:
			return resources_result
		var authored_runtime_value: Variant = level.get("authored_runtime")
		if (
			not authored_runtime_value is Dictionary
			or (authored_runtime_value as Dictionary).size() != 1
			or not _is_json_integer(
				(authored_runtime_value as Dictionary).get("ordinary_speed_fp")
			)
			or int((authored_runtime_value as Dictionary).ordinary_speed_fp) != FP_ONE
		):
			return _failure(
				"Time Trial levels must declare the source-backed ordinary speed"
			)
		var authored_result := _validate_authored_lvd(level.get("authored_lvd"), level_id)
		if not authored_result.ok:
			return authored_result
		var authored := authored_result.value as Dictionary
		if authored.is_empty():
			return _failure("Time Trial levels must carry authored LVD payloads")
		if not TIME_TRIAL_SUPPORTED_LEVEL_MODE_IDS.has(int(authored.get("level_mode_id", 0))):
			return _failure(
				"Time Trial level %d uses an unsupported authored level mode" % level_id
			)
		if authored.get("mirror_x") != false:
			return _failure("Time Trial levels never mirror the authored field")
		var reference_result := _validate_level_resource_references(
			authored,
			resources_result.value,
			false
		)
		if not reference_result.ok:
			return reference_result
		for record_value in authored.get("supplemental_spawn_records_raw_words", []):
			var record := record_value as Array
			if not record.is_empty() and int(record[0]) > 0:
				return _failure(
					"Time Trial level %d must not carry supplemental spawn records"
					% level_id
				)
		normalized.append({
			"id": level_id,
			"title": String(level.title),
			"author": String(level.author),
			"enemy_sprite": String(level.enemy_sprite),
			"ordinary_kill_score": int(level.ordinary_kill_score),
			"enemy_resources": resources_result.value,
			"shop_after": false,
			"authored_runtime": {
				"ordinary_speed_fp": int(
					(authored_runtime_value as Dictionary).ordinary_speed_fp
				),
			},
			"authored_lvd": authored,
		})
	return _success({
		"runtime": runtime.duplicate(true),
		"levels": normalized,
	})


static func _validate_time_trial_sprite_bindings(
	levels: Array,
	sprites: Dictionary
) -> Dictionary:
	var usage_value: Variant = sprites.get("time_trial_level_usage")
	if not usage_value is Array:
		return _failure("sprite frames must declare Time Trial level usage")
	var usage := usage_value as Array
	if usage.size() != levels.size():
		return _failure("Time Trial level and sprite binding counts diverge")
	var sheet_ids: Dictionary = {}
	for sheet_value in sprites.get("enemy_sheets", []):
		if not sheet_value is Dictionary:
			return _failure("sprite enemy sheet definition must be an object")
		sheet_ids[String((sheet_value as Dictionary).get("id", ""))] = true
	for level_index in range(levels.size()):
		var level := levels[level_index] as Dictionary
		var entry := usage[level_index] as Dictionary
		if int(entry.get("level_id", 0)) != int(level.id):
			return _failure("Time Trial level and sprite binding order diverges")
		var level_resources: Array = level.get("enemy_resources", [])
		var usage_resources: Array = entry.get("enemy_resources", [])
		if usage_resources.size() != level_resources.size():
			return _failure("Time Trial sprite usage omits an enemy resource binding")
		for resource_index in range(level_resources.size()):
			var level_resource := level_resources[resource_index] as Dictionary
			var usage_resource := usage_resources[resource_index] as Dictionary
			for key in ["resource_slot_id", "raw_name", "enemy_sheet_id", "kill_score"]:
				if level_resource.get(key) != usage_resource.get(key):
					return _failure(
						"Time Trial sprite binding field %s diverges" % key
					)
			if not sheet_ids.has(String(level_resource.enemy_sheet_id)):
				return _failure(
					"Time Trial enemy resource references an undefined sprite sheet"
				)
	return _success(true)


static func _validate_swd_paths(document: Dictionary) -> Dictionary:
	if not _version_is_supported(document):
		return _failure("swd_paths.json has an unsupported version")
	if String(document.get("schema", "")) != "warblade.swd.runtime.v1":
		return _failure("swd_paths.json has an unsupported schema")
	if (
		String(document.get("selection_scope", "")) != "global_loaded_catalog"
		or String(document.get("inactive_runtime_point_policy", "")) != "zero_fill"
	):
		return _failure("swd_paths.json does not preserve the retail runtime policy")
	if typeof(document.get("source_executable_sha256")) != TYPE_STRING:
		return _failure("swd_paths.json is missing executable provenance")
	var values: Variant = document.get("paths")
	if typeof(values) != TYPE_ARRAY or (values as Array).size() != 14:
		return _failure("swd_paths.json must contain fourteen packaged paths")
	var normalized: Array = []
	for path_index in range((values as Array).size()):
		var value: Variant = (values as Array)[path_index]
		if typeof(value) != TYPE_DICTIONARY:
			return _failure("SWD path entries must be objects")
		var path := value as Dictionary
		for key in [
			"id",
			"initial_velocity_x_fixed_256",
			"initial_velocity_y_fixed_256",
			"return_selector",
			"active_point_count",
		]:
			if not _is_json_integer(path.get(key)):
				return _failure("SWD path %s must be an integer" % key)
		if int(path.id) != path_index:
			return _failure("SWD runtime IDs must be contiguous")
		if String(path.get("source_file", "")) != "att%03d.swd" % (path_index + 1):
			return _failure("SWD source filenames must preserve loader order")
		if String(path.get("source_sha256", "")).length() != 64:
			return _failure("SWD source hashes must be SHA-256 values")
		if int(path.return_selector) < 1 or int(path.return_selector) > 3:
			return _failure("SWD return selector is outside the proven first-five set")
		var points_value: Variant = path.get("points")
		if typeof(points_value) != TYPE_ARRAY:
			return _failure("SWD path points must be an array")
		var point_values := points_value as Array
		if point_values.size() != int(path.active_point_count) or point_values.size() > 150:
			return _failure("SWD active point count does not match its points")
		var points: Array = []
		for point_value in point_values:
			if typeof(point_value) != TYPE_DICTIONARY:
				return _failure("SWD points must be objects")
			var point := point_value as Dictionary
			for key in [
				"acceleration_x_fixed_256",
				"acceleration_y_fixed_256",
				"opcode",
				"unresolved_word_3",
				"progress_threshold",
			]:
				if not _is_json_integer(point.get(key)):
					return _failure("SWD point %s must be an integer" % key)
			if not [0, 1, 6].has(int(point.opcode)):
				return _failure("SWD point opcode is unsupported")
			if int(point.progress_threshold) < 0:
				return _failure("SWD progress thresholds must be nonnegative")
			points.append({
				"acceleration_x_fixed_256": int(point.acceleration_x_fixed_256),
				"acceleration_y_fixed_256": int(point.acceleration_y_fixed_256),
				"opcode": int(point.opcode),
				"unresolved_word_3": int(point.unresolved_word_3),
				"progress_threshold": int(point.progress_threshold),
			})
		normalized.append({
			"id": path_index,
			"source_file": String(path.source_file),
			"source_sha256": String(path.source_sha256),
			"initial_velocity_x_fixed_256": int(path.initial_velocity_x_fixed_256),
			"initial_velocity_y_fixed_256": int(path.initial_velocity_y_fixed_256),
			"return_selector": int(path.return_selector),
			"active_point_count": int(path.active_point_count),
			"points": points,
		})
	return _success(normalized)


static func _version_is_supported(document: Dictionary) -> bool:
	return _is_json_integer(document.get("version")) and int(document.version) == 1


static func _is_json_integer(value: Variant) -> bool:
	if typeof(value) == TYPE_INT:
		return true
	if typeof(value) != TYPE_FLOAT:
		return false
	var numeric := float(value)
	return is_finite(numeric) and numeric == floor(numeric)


static func _json_integer_array_matches(value: Variant, expected: Array) -> bool:
	if not value is Array or (value as Array).size() != expected.size():
		return false
	for index in range(expected.size()):
		var item: Variant = (value as Array)[index]
		if not _is_json_integer(item) or int(item) != int(expected[index]):
			return false
	return true


static func _is_lower_hex_sha256(value: String) -> bool:
	if value.length() != 64:
		return false
	for character in value:
		if "0123456789abcdef".find(String(character)) < 0:
			return false
	return true


static func _ratio_to_fp(numerator: int, denominator: int) -> int:
	return (numerator * FP_ONE + denominator / 2) / denominator


static func _hash_files(
	files: Dictionary,
	file_names: Array[String] = []
) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	var ordered_names := file_names
	if ordered_names.is_empty():
		if files.has("ordnance.json"):
			ordered_names = REQUIRED_FILES
		elif files.has("bosses.json"):
			ordered_names = REQUIRED_FILES.slice(0, REQUIRED_FILES.size() - 1)
		else:
			ordered_names = LEGACY_REQUIRED_FILES
	for file_name in ordered_names:
		if not files.has(file_name):
			return ""
		context.update(file_name.to_utf8_buffer())
		context.update(PackedByteArray([0]))
		context.update(files[file_name])
	return context.finish().hex_encode()


static func _hash_text(value: String) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(value.to_utf8_buffer())
	return context.finish().hex_encode()


static func _hash_bytes(value: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(value)
	return context.finish().hex_encode()


static func canonical_payload_sha256(value: Variant) -> String:
	var encoded := _canonical_payload_text(value)
	if not bool(encoded.get("ok", false)):
		return ""
	return _hash_text(String(encoded.value))


static func canonical_authored_lvd_sha256(
	value: Variant,
	level_id: int,
	allow_mode_four: bool = false,
	mode_four_opcode_allowlist: Array = []
) -> String:
	var authored_result := _validate_authored_lvd(
		value,
		level_id,
		allow_mode_four,
		mode_four_opcode_allowlist
	)
	if not bool(authored_result.get("ok", false)):
		return ""
	return canonical_payload_sha256(authored_result.value)


static func _canonical_payload_text(value: Variant) -> Dictionary:
	match typeof(value):
		TYPE_NIL:
			return _success("n")
		TYPE_BOOL:
			return _success("b1" if bool(value) else "b0")
		TYPE_INT:
			return _success("i%d;" % int(value))
		TYPE_STRING, TYPE_STRING_NAME:
			var string_value := String(value)
			return _success(
				"s%d:%s" % [string_value.to_utf8_buffer().size(), string_value]
			)
		TYPE_ARRAY:
			var array_value := value as Array
			var array_text := "a%d[" % array_value.size()
			for item in array_value:
				var encoded_item := _canonical_payload_text(item)
				if not bool(encoded_item.get("ok", false)):
					return encoded_item
				array_text += String(encoded_item.value)
			return _success(array_text + "]")
		TYPE_DICTIONARY:
			var dictionary_value := value as Dictionary
			var keys: Array[String] = []
			for key_value in dictionary_value:
				if typeof(key_value) not in [TYPE_STRING, TYPE_STRING_NAME]:
					return _failure("canonical payload keys must be strings")
				keys.append(String(key_value))
			keys.sort()
			var dictionary_text := "d%d{" % keys.size()
			for key in keys:
				var encoded_key := _canonical_payload_text(key)
				var encoded_value := _canonical_payload_text(dictionary_value[key])
				if not bool(encoded_value.get("ok", false)):
					return encoded_value
				dictionary_text += (
					String(encoded_key.value) + String(encoded_value.value)
				)
			return _success(dictionary_text + "}")
	return _failure("canonical payload contains an unsupported value type")


static func _success(value: Variant) -> Dictionary:
	return {"ok": true, "error": "", "value": value}


static func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}


static func _fallback_catalog() -> Dictionary:
	var weapons: Array = [
		_weapon(0, "Single Shot", FP_ONE, 6, [[0, 0, 0, 0, -6 * FP_ONE, 4, 10]]),
		_weapon(1, "Double Shot", 2 * FP_ONE, 6, [[1, -6 * FP_ONE, 0, 0, -6 * FP_ONE, 4, 10], [1, 6 * FP_ONE, 0, 0, -6 * FP_ONE, 4, 10]]),
		_weapon(2, "Triple Shot", 3 * FP_ONE, 6, [[9, 0, 0, 0, -6 * FP_ONE, 4, 10], [9, -6 * FP_ONE, 0, -FP_ONE, -6 * FP_ONE, 4, 10], [9, 6 * FP_ONE, 0, FP_ONE, -6 * FP_ONE, 4, 10]]),
		_weapon(3, "Quad Shot", 163840, 6, [[4, -9 * FP_ONE, 0, -FP_ONE, -6 * FP_ONE, 4, 10], [4, -3 * FP_ONE, 0, 0, -6 * FP_ONE, 4, 10], [4, 3 * FP_ONE, 0, 0, -6 * FP_ONE, 4, 10], [4, 9 * FP_ONE, 0, FP_ONE, -6 * FP_ONE, 4, 10]]),
		_weapon(4, "Super Triple", 4 * FP_ONE, 6, [[8, 0, 0, 0, -7 * FP_ONE, 6, 12], [8, -8 * FP_ONE, 0, -FP_ONE, -6 * FP_ONE, 6, 12], [8, 8 * FP_ONE, 0, FP_ONE, -6 * FP_ONE, 6, 12]]),
		_weapon(5, "Plasma", 360448, 6, [[18, 0, 0, 0, -7 * FP_ONE, 10, 16]]),
		_weapon(6, "Fireballs", 6 * FP_ONE, 6, [[25, -5 * FP_ONE, 0, -FP_ONE, -6 * FP_ONE, 12, 12], [25, 5 * FP_ONE, 0, FP_ONE, -6 * FP_ONE, 12, 12]]),
		_weapon(7, "Laser", 10 * FP_ONE, 6, [[22, 0, -86 * FP_ONE, 0, 0, 16, 100]]),
		_weapon(8, "War.I.Plasma", 15 * FP_ONE, 6, [[19, 0, 0, 0, -8 * FP_ONE, 14, 20]]),
	]
	var titles := [
		"JUST WARMING UP",
		"JUST WARMING UP",
		"THE FIRST BIG ONE",
		"K A M I K A Z E",
		"GETTING A BIT WARMER",
	]
	var levels: Array = []
	var ordinary_kill_scores := [50, 20, 50, 500, 50]
	for index in range(5):
		levels.append({
			"id": index + 1,
			"title": titles[index],
			"author": "EDGAR VIGDAL",
			"enemy_sprite": "alien001" if index < 4 else "alien_2",
			"ordinary_kill_score": ordinary_kill_scores[index],
			"shop_after": index == 3,
			"waves": [{
				"start_tick": 30,
				"count": 8 + index * 2,
				"columns": 8,
				"spawn_x": 120,
				"spawn_y": -32,
				"spacing_x": 64,
				"spacing_y": 38,
				"health_fp": FP_ONE + index * (FP_ONE / 2),
				"speed_fp": FP_ONE,
				"path": "sine_entry",
				"fire_interval_ticks": max(75, 150 - index * 12),
				"projectile_speed_fp": 3 * FP_ONE,
				"score": 10 + index * 5,
				"cash": 2 + index,
			}],
		})
	var shop_names := [
		"Extra Speed",
		"Extra Bullet",
		"Double Shot",
		"Less Speed",
		"Triple Shot",
		"Quad Shot",
		"Auto Fire Unit",
		"Super Triple",
		"Ship Armour",
		"Plasma",
		"Extra Life",
		"Fire Balls",
		"Game Secret",
		"Rank Marker",
		"Extra Time",
		"Laser Beam",
		"War.I.Plasma",
	]
	var prices := [50, 75, 100, 150, 200, 300, 400, 500, 600, 750, 800, 990, 1000, 1250, 1500, 2000, 3000]
	var effects := [
		"speed_up",
		"bullet_capacity_up",
		"equip_weapon",
		"speed_down",
		"equip_weapon",
		"equip_weapon",
		"enable_autofire",
		"equip_weapon",
		"armor_up",
		"equip_weapon",
		"life_up",
		"equip_weapon",
		"buy_secret",
		"rank_marker_up",
		"bonus_time_up",
		"equip_weapon",
		"equip_weapon",
	]
	var weapon_ids := [-1, -1, 1, -1, 2, 3, -1, 4, -1, 5, -1, 6, -1, -1, -1, 7, 8]
	var items: Array = []
	for index in range(shop_names.size()):
		var item := {
			"id": index + 1,
			"name": shop_names[index],
			"price": prices[index],
			"category": "upgrade",
			"effect": effects[index],
			"unlock": {"kind": "always", "threshold": 0},
		}
		if weapon_ids[index] >= 0:
			item["weapon_id"] = weapon_ids[index]
		items.append(item)
	var difficulties: Array = [
		_difficulty("easy", "Easy", 6, 400, 300, 210, 252, 48),
		_difficulty("normal", "Normal", 6, 200, 200, 258, 240, 42),
		_difficulty("hard", "Hard", 7, -50, 190, 350, 210, 36),
		_difficulty("ace", "Ace", 8, -200, 180, 440, 180, 30),
	]
	return {
		"weapons": weapons,
		"bonuses": _fallback_bonuses(),
		"levels": levels,
		"shop": items,
		"difficulties": difficulties,
		"sprites": {},
		"swd_paths": [],
		"bonus_modes": {},
		"bosses": {},
	}


static func _fallback_bonuses() -> Array:
	var bonuses: Array = []
	for bonus_index in range(BONUS_WEIGHTS.size()):
		var bonus := {
			"id": bonus_index,
			"effect_id": bonus_index,
			"effect_key": BONUS_EFFECT_KEYS[bonus_index],
			"weight": BONUS_WEIGHTS[bonus_index],
			"source_x": 0,
			"source_y": BONUS_SOURCE_Y[bonus_index],
			"width": 20,
			"height": 20,
			"frame_count": 10,
		}
		if bonus_index >= 12 and bonus_index <= 14:
			bonus["reroll_gate"] = _bonus_reroll_gate([50, 150, 300][bonus_index - 12])
		bonuses.append(bonus)
	return bonuses


static func _bonus_reroll_gate(random_max_argument: int) -> Dictionary:
	return {
		"kind": "random_result_below_active_player_progression",
		"random_min_argument": 0,
		"random_max_argument": random_max_argument,
		"comparison": "strict_less_than",
		"active_player_progression_base_va": "0x008487bc",
		"active_player_stride_bytes": 1240,
	}


static func _bonus_reroll_gate_matches(value: Variant, random_max_argument: int) -> bool:
	if typeof(value) != TYPE_DICTIONARY:
		return false
	var gate := value as Dictionary
	if gate.size() != 6:
		return false
	return (
		String(gate.get("kind", "")) == "random_result_below_active_player_progression"
		and _is_json_integer(gate.get("random_min_argument"))
		and int(gate.random_min_argument) == 0
		and _is_json_integer(gate.get("random_max_argument"))
		and int(gate.random_max_argument) == random_max_argument
		and String(gate.get("comparison", "")) == "strict_less_than"
		and String(gate.get("active_player_progression_base_va", "")) == "0x008487bc"
		and _is_json_integer(gate.get("active_player_stride_bytes"))
		and int(gate.active_player_stride_bytes) == 1240
	)


static func _weapon(id: int, name: String, damage_fp: int, _cooldown_ticks: int, definitions: Array) -> Dictionary:
	var projectiles: Array = []
	for definition in definitions:
		projectiles.append({
			"prototype_id": definition[0],
			"offset_x_fp": definition[1],
			"offset_y_fp": definition[2],
			"velocity_x_fp": definition[3],
			"velocity_y_fp": definition[4],
			"width": definition[5],
			"height": definition[6],
		})
	return {
		"id": id,
		"name": name,
		"damage_fp": damage_fp,
		"sound": name.to_lower().replace(" ", ""),
		"projectiles": projectiles,
	}


static func _difficulty(
	id: String,
	name: String,
	scale_numerator: int,
	timer_adjustment: int,
	timer_floor: int,
	projectile_speed_numerator: int,
	player_speed_numerator: int,
	player_upgrade_numerator: int
) -> Dictionary:
	var player_base_speed_fp := _ratio_to_fp(player_speed_numerator, 60)
	var player_speed_upgrade_fp := _ratio_to_fp(player_upgrade_numerator, 60)
	var timed_effect_seconds: int = int(
		{"easy": 50, "normal": 40, "hard": 30, "ace": 20}[id]
	)
	var bonus_time_start: int = 20
	var bonus_time_max: int = 45
	var bonus_time_floor: int = int(
		{"easy": 15, "normal": 10, "hard": 5, "ace": 5}[id]
	)
	var bonus_drop_denominator: int = int(
		{"easy": 18, "normal": 28, "hard": 38, "ace": 48}[id]
	)
	var special_health_base_a: int = int(
		{"easy": 10, "normal": 16, "hard": 20, "ace": 25}[id]
	)
	var special_health_base_c: int = int(
		{"easy": 75, "normal": 100, "hard": 125, "ace": 150}[id]
	)
	var special_health_base_b: int = int(
		{"easy": 300, "normal": 350, "hard": 450, "ace": 600}[id]
	)
	var special_health_base_d: int = int(
		{"easy": 1500, "normal": 1750, "hard": 2000, "ace": 2500}[id]
	)
	var special_speed_maximum: int = int(
		{"easy": 3, "normal": 4, "hard": 5, "ace": 6}[id]
	)
	var debris_lifetime_base: int = int(
		{"easy": 200, "normal": 200, "hard": 210, "ace": 220}[id]
	)
	var debris_lifetime_range: int = int(
		{"easy": 200, "normal": 225, "hard": 230, "ace": 235}[id]
	)
	var debris_speed_minimum_milli: int = int(
		{"easy": 2400, "normal": 3100, "hard": 3300, "ace": 3500}[id]
	)
	var debris_speed_maximum_milli: int = int(
		{"easy": 3200, "normal": 3800, "hard": 4300, "ace": 4800}[id]
	)
	var debris_steering_threshold: int = int(
		{"easy": 50, "normal": 40, "hard": 30, "ace": 20}[id]
	)
	return {
		"id": id,
		"name": name,
		"special_health_base_a": special_health_base_a,
		"special_health_base_b": special_health_base_b,
		"special_health_base_c": special_health_base_c,
		"special_health_base_d": special_health_base_d,
		"special_speed_maximum": special_speed_maximum,
		"debris_lifetime_base": debris_lifetime_base,
		"debris_lifetime_range": debris_lifetime_range,
		"debris_speed_minimum_milli": debris_speed_minimum_milli,
		"debris_speed_maximum_milli": debris_speed_maximum_milli,
		"debris_steering_threshold": debris_steering_threshold,
		"simulation_scale_numerator": scale_numerator,
		"simulation_scale_denominator": 6,
		"timer_a_initial_adjustment": timer_adjustment,
		"timer_a_floor": timer_floor,
		"timer_b_initial_adjustment": timer_adjustment,
		"timer_b_floor": timer_floor,
		"timed_effect_seconds": timed_effect_seconds,
		"bonus_time_start": bonus_time_start,
		"bonus_time_max": bonus_time_max,
		"bonus_time_floor": bonus_time_floor,
		"bonus_drop_denominator": bonus_drop_denominator,
		"alien_projectile_speed_fp": _ratio_to_fp(projectile_speed_numerator, 60),
		"player_base_speed_fp": player_base_speed_fp,
		"player_speed_upgrade_fp": player_speed_upgrade_fp,
		"player_speed_cap_fp": player_base_speed_fp + 16 * player_speed_upgrade_fp,
	}

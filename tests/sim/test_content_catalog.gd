extends SceneTree

const Catalog := preload("res://src/sim/content_catalog.gd")
const Simulation := preload("res://src/sim/game_simulation.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	var catalog := Catalog.load_catalog()
	_expect(
		bool(catalog.get("ok", false)),
		"compiled content catalog should load: %s" % String(catalog.get("error", "unknown error"))
	)
	if bool(catalog.get("ok", false)):
		_verify_bonus_table(catalog.get("bonuses", []), "compiled")
		_verify_bonus_modes(catalog.get("bonus_modes", {}))
		_verify_full_campaign_content(catalog)
		_verify_time_trial_content(catalog)
		_test_version_compatibility_and_fail_closed_contracts()
		_expect(
			String(catalog.get("content_hash", "")).length() == 64,
			"catalog hash should include all required content"
		)
		var raw_files: Dictionary = {}
		for file_name in Catalog.REQUIRED_FILES:
			raw_files[file_name] = FileAccess.get_file_as_bytes(
				"res://content/%s" % file_name
			)
		var baseline_hash := Catalog._hash_files(raw_files)
		var changed_bonus_modes: PackedByteArray = raw_files["bonus_modes.json"].duplicate()
		changed_bonus_modes.append(10)
		var changed_bonus_files := raw_files.duplicate(true)
		changed_bonus_files["bonus_modes.json"] = changed_bonus_modes
		_expect(
			baseline_hash == String(catalog.get("content_hash", ""))
			and Catalog._hash_files(changed_bonus_files) != baseline_hash,
			"bonus_modes.json must participate in the authoritative content hash"
		)
		var changed_bosses: PackedByteArray = raw_files["bosses.json"].duplicate()
		changed_bosses.append(10)
		var changed_boss_files := raw_files.duplicate(true)
		changed_boss_files["bosses.json"] = changed_bosses
		_expect(
			Catalog._hash_files(changed_boss_files) != baseline_hash,
			"bosses.json must participate in the authoritative content hash"
		)
		var changed_ordnance: PackedByteArray = raw_files["ordnance.json"].duplicate()
		changed_ordnance.append(10)
		var changed_ordnance_files := raw_files.duplicate(true)
		changed_ordnance_files["ordnance.json"] = changed_ordnance
		_expect(
			Catalog._hash_files(changed_ordnance_files) != baseline_hash,
			"ordnance.json must participate in the authoritative content hash"
		)
	var fallback := Catalog.load_catalog("res://missing-content-catalog", "", true)
	_expect(bool(fallback.get("ok", false)), "explicit development fallback should load")
	if bool(fallback.get("ok", false)):
		_verify_bonus_table(fallback.get("bonuses", []), "fallback")
	if _failures.is_empty():
		print("CONTENT CATALOG TESTS PASSED")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("CONTENT CATALOG TESTS FAILED: %d" % _failures.size())
	quit(1)


func _verify_bonus_table(value: Variant, label: String) -> void:
	_expect(typeof(value) == TYPE_ARRAY, "%s bonuses should be an array" % label)
	if typeof(value) != TYPE_ARRAY:
		return
	var bonuses := value as Array
	_expect(bonuses.size() == 37, "%s should expose all 37 retail bonus types" % label)
	if bonuses.size() != 37:
		return
	var total_weight := 0
	for bonus_index in range(bonuses.size()):
		var bonus := bonuses[bonus_index] as Dictionary
		_expect(int(bonus.get("id", -1)) == bonus_index, "%s bonus IDs should be contiguous" % label)
		total_weight += int(bonus.get("weight", 0))
	_expect(total_weight == 2252, "%s bonus weights should retain the retail total" % label)
	_expect(int(bonuses[16].source_y) == 380, "%s type 16 should retain the SCOOP row" % label)
	_expect(String(bonuses[16].effect_key) == "scoop", "%s type 16 should retain its proven meaning" % label)
	_expect(int(bonuses[21].source_y) == 500, "%s type 21 should retain the armour row" % label)
	_expect(int(bonuses[28].source_y) == 480, "%s type 28 should retain the extra-time row" % label)
	_expect(
		int(bonuses[14].reroll_gate.random_max_argument) == 300,
		"%s type 14 should retain its progression reroll argument" % label
	)


func _verify_bonus_modes(value: Variant) -> void:
	_expect(value is Dictionary, "compiled bonus-mode contract should be an object")
	if not value is Dictionary:
		return
	var contract := value as Dictionary
	_expect(int(contract.get("meteor_storm", {}).get("slot_count", 0)) == 30, "Meteor contract retains all 30 slots")
	_expect(int(contract.get("level_8_bonus", {}).get("level_id", 0)) == 8, "mode-3 contract is bound to level 8")
	var recurring: Dictionary = contract.get("mode_three_bonus", {})
	_expect(int(recurring.get("level_mode_id", 0)) == 3, "canonical mode-three contract retains retail mode 3")
	_expect(
		not recurring.has("level_id")
		and not recurring.has("authored_target_count")
		and not recurring.has("background_texture"),
		"canonical mode-three contract remains level-neutral"
	)
	_expect(
		not recurring.get("rewards", {}).has("authored_enemy_score")
		and not recurring.get("timing_and_flow", {}).has("shop_rule"),
		"canonical shared rules leave per-level score and shop prose in their projections"
	)
	var recurring_levels: Array = recurring.get("levels", [])
	_expect(
		recurring_levels.size() == 12
			and int(recurring_levels[0].get("level_id", 0)) == 8
			and int(recurring_levels[0].get("authored_target_count", 0)) == 20
			and int(recurring_levels[1].get("level_id", 0)) == 16
			and int(recurring_levels[1].get("authored_target_count", 0)) == 30
			and int(recurring_levels[2].get("level_id", 0)) == 24
			and int(recurring_levels[2].get("authored_target_count", 0)) == 30
			and int(recurring_levels[3].get("level_id", 0)) == 33
			and int(recurring_levels[3].get("authored_target_count", 0)) == 30
			and int(recurring_levels[3].get("authored_enemy_score", 0)) == 500
			and int(recurring_levels[4].get("level_id", 0)) == 41
			and int(recurring_levels[4].get("authored_target_count", 0)) == 40
			and int(recurring_levels[4].get("authored_enemy_score", 0)) == 500
			and int(recurring_levels[5].get("level_id", 0)) == 49
			and int(recurring_levels[5].get("authored_target_count", 0)) == 40
			and int(recurring_levels[5].get("authored_enemy_score", 0)) == 750
			and int(recurring_levels[6].get("level_id", 0)) == 58
			and int(recurring_levels[6].get("authored_target_count", 0)) == 80
			and int(recurring_levels[6].get("authored_enemy_score", 0)) == 500
			and int(recurring_levels[7].get("level_id", 0)) == 66
			and int(recurring_levels[8].get("level_id", 0)) == 74
			and int(recurring_levels[9].get("level_id", 0)) == 83
			and int(recurring_levels[10].get("level_id", 0)) == 91
			and int(recurring_levels[11].get("level_id", 0)) == 99,
		"canonical mode-three contract binds all twelve recurring levels"
	)
	_expect(
		contract.get("rank_promotion", {}).get("ranks", []).size() == 20,
		"promotion contract covers ranks 1 through 20"
	)


func _verify_full_campaign_content(catalog: Dictionary) -> void:
	var levels: Array = catalog.get("levels", [])
	_expect(levels.size() == 100, "compiled catalog exposes all one hundred classic levels")
	if levels.size() != 100:
		return
	var expected_sheets := [
		"alien001", "alien001", "alien001", "alien001",
		"alien_2", "alien_2", "alien_2", "alien_2",
		"alien_3", "alien_3", "alien_3", "alien_3",
		"alien000", "alien000", "alien000", "alien000",
		"alien_lilla", "alien_lilla", "alien_lilla", "alien_lilla",
		"alien003", "alien003", "alien003", "alien003", "alien_big1_1",
		"alien_rakett", "alien_rakett", "alien_rakett", "alien_rakett", "alien_baller",
		"alien_baller", "alien_baller", "alien_baller",
		"alien_green_lilla_t", "alien_green_lilla_t",
		"alien_green_lilla_t", "alien_green_lilla_t",
		"alien_raudkule", "alien_raudkule", "alien_raudkule", "alien_raudkule",
		"alien_blavinger_gf", "alien_blavinger_gf", "alien_blavinger_gf",
		"alien_blavinger_gf2",
		"alien_rbille", "alien_rbille", "alien_rbille", "alien_rbille",
		"alien_big2_1",
		"alien_gultop", "alien_gultop", "alien_gultop", "alien_gultop",
		"alien_bluekreps", "alien_bluekreps", "alien_bluekreps",
		"alien_brownkreps2",
		"alien_rvinggk", "alien_rvinggk", "alien_rvinggk",
		"alien_gvingbk",
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
	]
	for level_index in range(100):
		var level: Dictionary = levels[level_index]
		_expect(int(level.get("id", 0)) == level_index + 1, "classic level IDs remain contiguous")
		_expect(String(level.get("enemy_sprite", "")) == expected_sheets[level_index], "classic enemy-sheet mapping matches retail LVDs")
		var authored: Dictionary = level.get("authored_lvd", {})
		_expect(String(authored.get("schema", "")) == "warblade.lvd.authored.v2", "classic levels use authored LVD v2")
		_expect(authored.get("fixed_table_records_raw_words", []).size() == 50, "authored LVD v2 preserves all fifty fixed records")
	_expect(bool(levels[11].get("shop_after", false)), "level 12 retains the four-level shop cadence")
	_expect(bool(levels[15].get("shop_after", false)), "level 16 retains the four-level shop cadence")
	_expect(bool(levels[19].get("shop_after", false)), "level 20 retains the terminal shop cadence")
	_expect(bool(levels[23].get("shop_after", false)), "level 24 retains the four-level shop cadence")
	_expect(bool(levels[27].get("shop_after", false)), "level 28 retains the four-level shop cadence")
	_expect(bool(levels[31].get("shop_after", false)), "level 32 retains the four-level shop cadence")
	_expect(bool(levels[35].get("shop_after", false)), "level 36 retains the four-level shop cadence")
	_expect(bool(levels[39].get("shop_after", false)), "level 40 retains the four-level shop cadence")
	_expect(bool(levels[43].get("shop_after", false)), "level 44 retains the four-level shop cadence")
	_expect(bool(levels[47].get("shop_after", false)), "level 48 retains the four-level shop cadence")
	_expect(bool(levels[51].get("shop_after", false)), "level 52 retains the four-level shop cadence")
	_expect(bool(levels[55].get("shop_after", false)), "level 56 retains the four-level shop cadence")
	_expect(bool(levels[59].get("shop_after", false)), "level 60 retains the four-level shop cadence")
	_expect(
		int(levels[23].get("authored_lvd", {}).get("level_mode_id", 0)) == 3,
		"level 24 retains the recurring mode-three contract"
	)
	_expect(
		levels[20].get("enemy_resources", []).size() == 2
		and int(levels[20].enemy_resources[0].kill_score) == 200
		and int(levels[20].enemy_resources[1].kill_score) == 300,
		"level 21 preserves slot-specific enemy scores"
	)
	_expect(
		levels[24].get("enemy_resources", []).size() == 6,
		"level 25 preserves all six boss resource bindings"
	)
	_expect(
		levels[27].get("enemy_resources", []).size() == 2
		and int(levels[27].enemy_resources[0].kill_score) == 300
		and int(levels[27].enemy_resources[1].kill_score) == 400,
		"level 28 preserves slot-specific rocket scores"
	)
	_expect(
		levels[27].authored_lvd.supplemental_spawn_records_raw_words[0]
		== [2, 1, 30, 560, 7]
		and levels[27].authored_lvd.fixed_table_records_raw_words[0]
		== [4, 0, 0, 0],
		"level 28 preserves two four-phase supplemental enemies"
	)
	_expect(
		levels[29].get("enemy_resources", []).size() == 2
		and int(levels[29].enemy_resources[0].kill_score) == 500
		and int(levels[29].enemy_resources[1].kill_score) == 600,
		"level 30 preserves slot-specific baller scores"
	)
	_expect(
		int(levels[32].get("authored_lvd", {}).get("level_mode_id", 0)) == 3
		and levels[32].get("enemy_resources", []).size() == 2
		and int(levels[32].enemy_resources[0].kill_score) == 500
		and int(levels[32].enemy_resources[1].kill_score) == 600,
		"level 33 retains mode three and its slot-specific baller scores"
	)
	_expect(
		String(levels[33].get("enemy_sprite", "")) == "alien_green_lilla_t"
		and String(levels[34].get("enemy_sprite", "")) == "alien_green_lilla_t"
		and String(levels[33].enemy_resources[1].enemy_sheet_id) == "alien_cyan_lilla_t"
		and String(levels[34].enemy_resources[1].enemy_sheet_id) == "alien_cyan_lilla_t",
		"levels 34 and 35 retain both new green/cyan retail resources"
	)
	_expect(
		levels[35].authored_lvd.supplemental_spawn_records_raw_words[0]
		== [2, 2, 40, 818, 10]
		and levels[35].authored_lvd.supplemental_spawn_records_raw_words[1]
		== [1, 1, 59, 968, 14],
		"level 36 preserves both exact supplemental spawn records"
	)
	_expect(
		int(levels[40].get("authored_lvd", {}).get("level_mode_id", 0)) == 3
		and int(levels[40].enemy_resources[0].kill_score) == 500
		and int(levels[48].get("authored_lvd", {}).get("level_mode_id", 0)) == 3
		and int(levels[48].enemy_resources[0].kill_score) == 750,
		"levels 41 and 49 retain their recurring mode-three scores"
	)
	_expect(
		String(levels[38].enemy_resources[1].enemy_sheet_id) == "alien_raudkule2"
		and String(levels[43].enemy_resources[1].enemy_sheet_id) == "alien_blavinger_gf2"
		and String(levels[48].enemy_resources[0].enemy_sheet_id) == "alien_rbille",
		"levels 39, 44, and 49 retain their new retail resource bindings"
	)
	_expect(
		levels[52].authored_lvd.supplemental_spawn_records_raw_words[0]
		== [2, 1, 59, 925, 8]
		and levels[52].authored_lvd.supplemental_spawn_records_raw_words[1]
		== [2, 1, 79, 1054, 22]
		and levels[52].authored_lvd.fixed_table_records_raw_words[0]
		== [4, 0, 0, 0]
		and levels[52].authored_lvd.fixed_table_records_raw_words[1]
		== [4, 0, 0, 0],
		"level 53 preserves both exact supplemental spawn records"
	)
	_expect(
		int(levels[53].authored_lvd.level_mode_id) == 2
		and String(levels[53].enemy_resources[1].enemy_sheet_id)
		== "alien_rakett_gronn"
		and int(levels[61].authored_lvd.level_mode_id) == 2,
		"levels 54 and 62 retain mode two while level 54 reuses the green rocket"
	)
	_expect(
		levels[56].authored_lvd.supplemental_spawn_records_raw_words[0]
		== [4, 3, 98, 1441, 7]
		and levels[56].authored_lvd.fixed_table_records_raw_words[0]
		== [4, 1, 0, 0]
		and String(levels[56].enemy_resources[2].enemy_sheet_id)
		== "alien_brownkreps",
		"level 57 preserves its resource-selector-three supplemental record"
	)
	_expect(
		int(levels[57].authored_lvd.level_mode_id) == 3
		and levels[57].enemy_resources.size() == 2
		and int(levels[57].enemy_resources[0].kill_score) == 500
		and int(levels[57].enemy_resources[1].kill_score) == 500,
		"level 58 retains mode three and both 500-point resource bindings"
	)
	_expect(
		levels[60].authored_lvd.supplemental_spawn_records_raw_words[0]
		== [4, 1, 88, 1162, 23]
		and levels[60].authored_lvd.fixed_table_records_raw_words[0]
		== [4, 1, 0, 0]
		and String(levels[60].enemy_resources[0].enemy_sheet_id)
		== "alien_rvinggk",
		"level 61 preserves its exact supplemental spawn record"
	)
	_expect(
		catalog.get("bosses", {}).has("retail_big_boss_v1"),
		"compiled catalog exposes the validated level-25 boss contract"
	)
	_expect(
		catalog.get("bosses", {}).has("retail_big_boss_level_50_v1"),
		"compiled catalog exposes the validated level-50 boss contract"
	)
	_expect(
		catalog.get("bosses", {}).has("retail_big_boss_level_75_v1")
		and catalog.get("bosses", {}).has("retail_big_boss_level_100_v1"),
		"compiled catalog exposes the validated late boss contracts"
	)
	var boss_contract := catalog.get("bosses", {}).get(
		"retail_big_boss_v1",
		{}
	) as Dictionary
	_expect(
		String(boss_contract.get("authored_level_payload", {}).get("sha256", ""))
		== Catalog.canonical_authored_lvd_sha256(
			levels[24].authored_lvd,
			25,
			true,
			boss_contract.path.opcode_allowlist
		),
		"the boss contract is bound to the exact normalized level-25 authored payload"
	)
	_expect(
		String(boss_contract.get("authored_level_payload", {}).get("sha256", ""))
		== Catalog.canonical_authored_lvd_sha256(
			levels[24].authored_lvd,
			25,
			true
		),
		"the legacy three-argument mode-4 payload hash remains compatible"
	)
	var level_50_contract := catalog.get("bosses", {}).get(
		"retail_big_boss_level_50_v1",
		{}
	) as Dictionary
	_expect(
		levels[49].enemy_resources.size() == 6
		and int(levels[49].authored_lvd.level_mode_id) == 4
		and levels[49].authored_lvd.supplemental_spawn_records_raw_words[0]
		== [1, 1, 500, 1377, 8],
		"level 50 preserves its six-resource state-13 initialization"
	)
	_expect(
		String(level_50_contract.get("authored_level_payload", {}).get("sha256", ""))
		== Catalog.canonical_authored_lvd_sha256(
			levels[49].authored_lvd,
			50,
			true,
			level_50_contract.path.opcode_allowlist
		),
		"the level-50 boss contract is bound to its exact normalized authored payload"
	)
	var sprites: Dictionary = catalog.get("sprites", {})
	_expect(int(sprites.get("version", 0)) == 11, "compiled sprite-frame catalog uses v11")
	_expect(sprites.get("level_usage", []).size() == 100, "sprite-frame catalog maps all one hundred levels")
	_expect(
		int(catalog.get("ordnance", {}).get("version", 0)) == 1,
		"compiled catalog exposes the validated ordnance contract"
	)


func _verify_time_trial_content(catalog: Dictionary) -> void:
	_expect(
		int(catalog.get("time_trial_version", 0)) == 1,
		"levels v10 must publish the Time Trial catalog version"
	)
	var time_trial: Dictionary = catalog.get("time_trial", {})
	var levels: Array = time_trial.get("levels", [])
	_expect(
		levels.size() == Catalog.TIME_TRIAL_LEVEL_COUNT,
		"Time Trial ships exactly fifteen authored levels"
	)
	var runtime: Dictionary = time_trial.get("runtime", {})
	var clock: Dictionary = runtime.get("clock", {})
	_expect(
		int(clock.get("match_milliseconds", 0)) == 181000
		and int(clock.get("grouped_best_extra_minute_milliseconds", 0)) == 241000
		and int(clock.get("missing_levels_milliseconds", 0)) == 10000,
		"the Time Trial clock matches the pinned retail instruction bytes"
	)
	var mode_ids: Dictionary = {}
	for level_value in levels:
		var level := level_value as Dictionary
		_expect(
			bool(level.has("authored_lvd")) and not bool(level.shop_after),
			"Time Trial level %d is authored and shopless" % int(level.id)
		)
		mode_ids[int((level.authored_lvd as Dictionary).level_mode_id)] = true
		for resource_value in level.enemy_resources as Array:
			var sheet_id := String((resource_value as Dictionary).enemy_sheet_id)
			_expect(
				not sheet_id.is_empty(),
				"Time Trial level %d binds every enemy resource" % int(level.id)
			)
	var sorted_mode_ids := mode_ids.keys()
	sorted_mode_ids.sort()
	_expect(
		sorted_mode_ids == [1, 2],
		"the Time Trial set uses only authored level modes 1 and 2"
	)


func _test_version_compatibility_and_fail_closed_contracts() -> void:
	var levels_document := _read_json("res://content/levels.json")
	var sprites_document := _read_json("res://content/sprite_frames.json")
	var bosses_document := _read_json("res://content/bosses.json")
	var ordnance_document := _read_json("res://content/ordnance.json")
	if (
		levels_document.is_empty()
		or sprites_document.is_empty()
		or bosses_document.is_empty()
		or ordnance_document.is_empty()
	):
		return
	var bosses_result := Catalog._validate_bosses(bosses_document)
	_expect(bool(bosses_result.get("ok", false)), "boss contract fixture validates")
	if not bool(bosses_result.get("ok", false)):
		return
	var levels_result := Catalog._validate_levels(levels_document, bosses_result.value)
	var sprites_result := Catalog._validate_sprite_frames(sprites_document)
	var ordnance_result := Catalog._validate_ordnance(ordnance_document)
	_expect(bool(levels_result.get("ok", false)), "levels v10 fixture validates")
	_expect(bool(sprites_result.get("ok", false)), "sprite frames v11 fixture validates")
	_expect(bool(ordnance_result.get("ok", false)), "ordnance v1 fixture validates")
	if bool(levels_result.get("ok", false)) and bool(sprites_result.get("ok", false)):
		_expect(
			bool(Catalog._validate_level_sprite_bindings(
				levels_result.value,
				sprites_result.value
			).get("ok", false)),
			"levels v10 and sprite frames v11 bindings agree"
		)
	var compatibility: Dictionary = Catalog.LEVEL_CATALOG_COMPATIBILITY
	_expect(
		compatibility == {
			1: {"bosses_version": 0, "ordnance_version": 0, "sprite_frames_version": 2, "level_count": 20},
			2: {"bosses_version": 1, "ordnance_version": 0, "sprite_frames_version": 3, "level_count": 25},
			3: {"bosses_version": 2, "ordnance_version": 1, "sprite_frames_version": 4, "level_count": 30},
			4: {"bosses_version": 2, "ordnance_version": 1, "sprite_frames_version": 5, "level_count": 35},
			5: {"bosses_version": 2, "ordnance_version": 1, "sprite_frames_version": 6, "level_count": 49},
			6: {"bosses_version": 3, "ordnance_version": 1, "sprite_frames_version": 7, "level_count": 50},
			7: {"bosses_version": 3, "ordnance_version": 1, "sprite_frames_version": 8, "level_count": 62},
			8: {"bosses_version": 4, "ordnance_version": 1, "sprite_frames_version": 9, "level_count": 100},
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
		},
		"level catalog compatibility is explicit through levels v10"
	)
	var v8_levels := levels_document.duplicate(true)
	v8_levels.version = 8
	v8_levels.schema = "warblade.levels.v8"
	_remove_authored_runtime(v8_levels)
	var v8_levels_result := Catalog._validate_levels(v8_levels, bosses_result.value)
	var v9_sprites := _v10_sprite_document(sprites_document)
	v9_sprites.version = 9
	v9_sprites.schema = "warblade.sprite-frames.v9"
	var v9_sprites_result := Catalog._validate_sprite_frames(v9_sprites)
	_expect(bool(v8_levels_result.get("ok", false)), "levels v8 remains readable")
	_expect(bool(v9_sprites_result.get("ok", false)), "sprite frames v9 remains readable")
	var v10_sprites := _v10_sprite_document(sprites_document)
	var v10_sprites_result := Catalog._validate_sprite_frames(v10_sprites)
	_expect(bool(v10_sprites_result.get("ok", false)), "sprite frames v10 remains readable")
	if (
		bool(v8_levels_result.get("ok", false))
		and bool(v9_sprites_result.get("ok", false))
	):
		_expect(
			bool(Catalog._validate_level_sprite_bindings(
				v8_levels_result.value,
				v9_sprites_result.value
			).get("ok", false)),
			"levels v8 and sprite frames v9 remain compatible"
		)
	var v6_levels := levels_document.duplicate(true)
	v6_levels.version = 6
	v6_levels.schema = "warblade.levels.v6"
	v6_levels.erase("level_mode_runtime")
	_remove_authored_runtime(v6_levels)
	(v6_levels.levels as Array).resize(50)
	var v6_levels_result := Catalog._validate_levels(v6_levels, bosses_result.value)
	var v7_sprites := _v7_sprite_document(sprites_document)
	var v7_sprites_result := Catalog._validate_sprite_frames(v7_sprites)
	_expect(bool(v6_levels_result.get("ok", false)), "levels v6 remains readable")
	_expect(bool(v7_sprites_result.get("ok", false)), "sprite frames v7 remains readable")
	if (
		bool(v6_levels_result.get("ok", false))
		and bool(v7_sprites_result.get("ok", false))
	):
		_expect(
			bool(Catalog._validate_level_sprite_bindings(
				v6_levels_result.value,
				v7_sprites_result.value
			).get("ok", false)),
			"levels v6 and sprite frames v7 remain compatible"
		)
	var v4_levels := levels_document.duplicate(true)
	v4_levels.version = 4
	v4_levels.schema = "warblade.levels.v4"
	v4_levels.erase("level_mode_runtime")
	_remove_authored_runtime(v4_levels)
	(v4_levels.levels as Array).resize(35)
	var v4_levels_result := Catalog._validate_levels(v4_levels, bosses_result.value)
	var v5_sprites := _v5_sprite_document(sprites_document)
	var v5_sprites_result := Catalog._validate_sprite_frames(v5_sprites)
	_expect(bool(v4_levels_result.get("ok", false)), "levels v4 remains readable")
	_expect(bool(v5_sprites_result.get("ok", false)), "sprite frames v5 remains readable")
	if (
		bool(v4_levels_result.get("ok", false))
		and bool(v5_sprites_result.get("ok", false))
	):
		_expect(
			bool(Catalog._validate_level_sprite_bindings(
				v4_levels_result.value,
				v5_sprites_result.value
			).get("ok", false)),
			"levels v4 and sprite frames v5 remain compatible"
		)

	var v3_levels := levels_document.duplicate(true)
	v3_levels.version = 3
	v3_levels.schema = "warblade.levels.v3"
	v3_levels.erase("level_mode_runtime")
	_remove_authored_runtime(v3_levels)
	(v3_levels.levels as Array).resize(30)
	var v3_levels_result := Catalog._validate_levels(v3_levels, bosses_result.value)
	var v4_sprites := _v4_sprite_document(sprites_document)
	var v4_sprites_result := Catalog._validate_sprite_frames(v4_sprites)
	_expect(bool(v3_levels_result.get("ok", false)), "levels v3 remains readable")
	_expect(bool(v4_sprites_result.get("ok", false)), "sprite frames v4 remains readable")
	if (
		bool(v3_levels_result.get("ok", false))
		and bool(v4_sprites_result.get("ok", false))
	):
		_expect(
			bool(Catalog._validate_level_sprite_bindings(
				v3_levels_result.value,
				v4_sprites_result.value
			).get("ok", false)),
			"levels v3 and sprite frames v4 remain compatible"
		)

	# Use the exact tagged artifacts instead of relabeling the v3 document: both
	# historical contracts predate the four evidence-only Level-25 additions.
	var v2_bosses := _read_json(
		"res://tests/sim/fixtures/bosses_v2_v0_7_0.json"
	)
	var v2_bosses_result := Catalog._validate_bosses(v2_bosses)
	var v1_bosses := _read_json(
		"res://tests/sim/fixtures/bosses_v1_v0_4_0.json"
	)
	var v1_bosses_result := Catalog._validate_bosses(v1_bosses)
	var v2_levels := levels_document.duplicate(true)
	v2_levels.version = 2
	v2_levels.schema = "warblade.levels.v2"
	v2_levels.erase("level_mode_runtime")
	_remove_authored_runtime(v2_levels)
	(v2_levels.levels as Array).resize(25)
	var v2_levels_result := Catalog._validate_levels(v2_levels, v1_bosses_result.value)
	var v3_sprites := _v3_sprite_document(sprites_document)
	var v3_sprites_result := Catalog._validate_sprite_frames(v3_sprites)
	_expect(bool(v2_bosses_result.get("ok", false)), "legacy bosses v2 remains readable")
	_expect(bool(v1_bosses_result.get("ok", false)), "legacy bosses v1 remains readable")
	_expect(bool(v2_levels_result.get("ok", false)), "levels v2 remains readable")
	_expect(bool(v3_sprites_result.get("ok", false)), "sprite frames v3 remains readable")
	if (
		bool(v2_levels_result.get("ok", false))
		and bool(v3_sprites_result.get("ok", false))
	):
		_expect(
			bool(Catalog._validate_level_sprite_bindings(
				v2_levels_result.value,
				v3_sprites_result.value
			).get("ok", false)),
			"levels v2 and sprite frames v3 remain compatible"
		)

	var v5_levels := levels_document.duplicate(true)
	v5_levels.version = 5
	v5_levels.schema = "warblade.levels.v5"
	v5_levels.erase("level_mode_runtime")
	_remove_authored_runtime(v5_levels)
	(v5_levels.levels as Array).resize(49)
	var v5_levels_result := Catalog._validate_levels(
		v5_levels,
		v2_bosses_result.value
	)
	var v6_sprites := _v6_sprite_document(sprites_document)
	var v6_sprites_result := Catalog._validate_sprite_frames(v6_sprites)
	_expect(bool(v5_levels_result.get("ok", false)), "levels v5 remains readable")
	_expect(bool(v6_sprites_result.get("ok", false)), "sprite frames v6 remains readable")
	if (
		bool(v5_levels_result.get("ok", false))
		and bool(v6_sprites_result.get("ok", false))
	):
		_expect(
			bool(Catalog._validate_level_sprite_bindings(
				v5_levels_result.value,
				v6_sprites_result.value
			).get("ok", false)),
			"levels v5 and sprite frames v6 remain compatible"
		)

	var legacy_levels := levels_document.duplicate(true)
	legacy_levels.version = 1
	legacy_levels.erase("schema")
	legacy_levels.erase("level_mode_runtime")
	_remove_authored_runtime(legacy_levels)
	var legacy_level_entries := legacy_levels.levels as Array
	legacy_level_entries.resize(20)
	for level_value in legacy_level_entries:
		(level_value as Dictionary).erase("enemy_resources")
	var legacy_levels_result := Catalog._validate_levels(legacy_levels)
	var legacy_sprites := _legacy_sprite_document(sprites_document)
	var legacy_sprites_result := Catalog._validate_sprite_frames(legacy_sprites)
	_expect(bool(legacy_levels_result.get("ok", false)), "legacy levels v1 remains readable")
	_expect(bool(legacy_sprites_result.get("ok", false)), "legacy sprite frames v2 remains readable")
	if (
		bool(legacy_levels_result.get("ok", false))
		and bool(legacy_sprites_result.get("ok", false))
	):
		_expect(
			bool(Catalog._validate_level_sprite_bindings(
				legacy_levels_result.value,
				legacy_sprites_result.value
			).get("ok", false)),
			"legacy levels v1 and sprite frames v2 remain compatible"
		)

	var missing_resource := levels_document.duplicate(true)
	(missing_resource.levels[20].enemy_resources as Array).remove_at(1)
	_expect(
		not bool(Catalog._validate_levels(missing_resource, bosses_result.value).get("ok", false)),
		"authored resource slots without bindings fail closed"
	)
	var missing_authored_runtime := levels_document.duplicate(true)
	missing_authored_runtime.levels[0].erase("authored_runtime")
	_expect(
		not bool(Catalog._validate_levels(
			missing_authored_runtime,
			bosses_result.value
		).get("ok", false)),
		"levels v9 fail closed without explicit authored runtime defaults"
	)
	var changed_authored_speed := levels_document.duplicate(true)
	changed_authored_speed.levels[0].authored_runtime.ordinary_speed_fp = 1
	_expect(
		not bool(Catalog._validate_levels(
			changed_authored_speed,
			bosses_result.value
		).get("ok", false)),
		"levels v9 fail closed when the source-backed ordinary speed changes"
	)
	var changed_compatibility_wave := levels_document.duplicate(true)
	changed_compatibility_wave.levels[0].waves[0].speed_fp = 123456
	_expect(
		bool(Catalog._validate_levels(
			changed_compatibility_wave,
			bosses_result.value
		).get("ok", false)),
		"v9 compatibility waves remain readable data rather than authored authority"
	)
	var extra_resource_field := levels_document.duplicate(true)
	extra_resource_field.levels[20].enemy_resources[0]["unsupported"] = true
	_expect(
		not bool(Catalog._validate_levels(extra_resource_field, bosses_result.value).get("ok", false)),
		"levels v5 enemy resources reject fields outside the exact schema"
	)
	var missing_mask := sprites_document.duplicate(true)
	missing_mask.enemy_sheets[13].erase("hit_mask")
	_expect(
		not bool(Catalog._validate_sprite_frames(missing_mask).get("ok", false)),
		"enemy sheets without HMA paths fail closed"
	)
	var malformed_mask_digest := sprites_document.duplicate(true)
	malformed_mask_digest.hit_mask_format.assets[15].hit_mask_sha256 = "NOT-A-SHA256"
	_expect(
		not bool(Catalog._validate_sprite_frames(malformed_mask_digest).get("ok", false)),
		"enemy sheets without valid pinned HMA digests fail closed"
	)
	var changed_state_ten_region := sprites_document.duplicate(true)
	for contract_value in changed_state_ten_region.renderer_state_contracts:
		var contract := contract_value as Dictionary
		if String((contract.snapshot_match as Dictionary).authored_state) == "state_ten":
			contract.frame_selection.selection_instruction_region.sha256 = "0".repeat(64)
	_expect(
		not bool(Catalog._validate_sprite_frames(
			changed_state_ten_region
		).get("ok", false)),
		"sprite frames v10 fail closed when the state-10 producer region drifts"
	)
	var unsupported_blank_projectile_phase := sprites_document.duplicate(true)
	var unsupported_blank := (
		unsupported_blank_projectile_phase.enemy_projectile_contracts
		.ordinary_type_7.sheet_masks.alien_rbille.phases[1]
	) as Dictionary
	unsupported_blank.local_inclusive_bounds = null
	unsupported_blank.occupied_pixel_count = 0
	_expect(
		not bool(Catalog._validate_sprite_frames(
			unsupported_blank_projectile_phase
		).get("ok", false)),
		"only the SHA-pinned alien_raudkule2 supplemental blank phase is accepted"
	)
	var changed_score := sprites_document.duplicate(true)
	changed_score.level_usage[20].enemy_resources[1].kill_score = 301
	var changed_score_sprites := Catalog._validate_sprite_frames(changed_score)
	_expect(bool(changed_score_sprites.get("ok", false)), "score fixture remains structurally valid")
	if bool(levels_result.get("ok", false)) and bool(changed_score_sprites.get("ok", false)):
		_expect(
			not bool(Catalog._validate_level_sprite_bindings(
				levels_result.value,
				changed_score_sprites.value
			).get("ok", false)),
			"level and sprite score divergence fails closed"
		)
	var invalid_level_28_phases := sprites_document.duplicate(true)
	invalid_level_28_phases.supplemental_spawn_linkages[6].animation_phase_count = 7
	_expect(
		not bool(Catalog._validate_sprite_frames(invalid_level_28_phases).get("ok", false)),
		"level 28 supplemental phases fail closed when they exceed zero through three"
	)
	var changed_level_98_supplemental := sprites_document.duplicate(true)
	changed_level_98_supplemental.supplemental_spawn_linkages[26].raw_words[4] = 11
	_expect(
		not bool(Catalog._validate_sprite_frames(
			changed_level_98_supplemental
		).get("ok", false)),
		"late-campaign supplemental records fail closed on source-word drift"
	)
	var extra_mode_six_runtime_field := levels_document.duplicate(true)
	extra_mode_six_runtime_field.level_mode_runtime["6"]["unsupported"] = true
	_expect(
		not bool(Catalog._validate_levels(
			extra_mode_six_runtime_field,
			bosses_result.value
		).get("ok", false)),
		"the mode-6 runtime contract rejects fields outside its exact schema"
	)
	var missing_ordnance_runtime := ordnance_document.duplicate(true)
	missing_ordnance_runtime.erase("missile_runtime")
	_expect(
		not bool(Catalog._validate_ordnance(missing_ordnance_runtime).get("ok", false)),
		"ordnance contracts missing runtime evidence fail closed"
	)
	var changed_ordnance_weight := ordnance_document.duplicate(true)
	changed_ordnance_weight.missile_runtime.targeting.weights["8"] = [6, 9, 11]
	_expect(
		not bool(Catalog._validate_ordnance(changed_ordnance_weight).get("ok", false)),
		"gameplay-critical ordnance drift fails the whole-contract digest"
	)
	var changed_rocket_grant := ordnance_document.duplicate(true)
	changed_rocket_grant.rocket_pack.purchase.grant = 9
	_expect(
		not bool(Catalog._validate_ordnance(changed_rocket_grant).get("ok", false)),
		"shop ordnance drift fails the whole-contract digest"
	)
	var unresolved_boss := bosses_document.duplicate(true)
	unresolved_boss.bosses.retail_big_boss_v1["test_unresolved"] = "unresolved"
	_expect(
		not bool(Catalog._validate_bosses(unresolved_boss).get("ok", false)),
		"unresolved boss gameplay behavior fails closed"
	)
	var incomplete_trace := bosses_document.duplicate(true)
	incomplete_trace.bosses.retail_big_boss_v1.exact_trace_complete = false
	_expect(
		not bool(Catalog._validate_bosses(incomplete_trace).get("ok", false)),
		"boss contracts without the exact-complete trace gate fail closed"
	)
	var malformed_payload_digest := bosses_document.duplicate(true)
	malformed_payload_digest.bosses.retail_big_boss_v1.authored_level_payload.sha256 = (
		"NOT-A-SHA256"
	)
	_expect(
		not bool(Catalog._validate_bosses(malformed_payload_digest).get("ok", false)),
		"boss contracts reject malformed authored-payload digests"
	)
	var changed_boss_path := levels_document.duplicate(true)
	changed_boss_path.levels[24].authored_lvd.groups[1].path_points[0].acceleration_x_milli += 1
	var changed_boss_path_result := Catalog._validate_levels(
		changed_boss_path,
		bosses_result.value
	)
	_expect(
		not bool(changed_boss_path_result.get("ok", false))
		and String(changed_boss_path_result.get("error", "")).contains(
			"exact boss contract"
		),
		"gameplay-critical level-25 path drift must fail its canonical boss binding"
	)
	var changed_level_50_path := levels_document.duplicate(true)
	changed_level_50_path.levels[49].authored_lvd.groups[1].path_points[0].acceleration_x_milli += 1
	var changed_level_50_path_result := Catalog._validate_levels(
		changed_level_50_path,
		bosses_result.value
	)
	_expect(
		not bool(changed_level_50_path_result.get("ok", false))
		and String(changed_level_50_path_result.get("error", "")).contains(
			"exact boss contract"
		),
		"gameplay-critical level-50 path drift must fail its canonical boss binding"
	)
	var level_25_big2_alias := levels_document.duplicate(true)
	level_25_big2_alias.levels[24].enemy_sprite = "alien_big2_1"
	level_25_big2_alias.levels[24].enemy_resources[0].enemy_sheet_id = "alien_big2_1"
	_expect(
		not bool(Catalog._validate_levels(
			level_25_big2_alias,
			bosses_result.value
		).get("ok", false)),
		"level 25 cannot cross-bind a level-50 Big2 resource"
	)
	var level_50_big1_alias := levels_document.duplicate(true)
	level_50_big1_alias.levels[49].enemy_sprite = "alien_big1_1"
	level_50_big1_alias.levels[49].enemy_resources[0].enemy_sheet_id = "alien_big1_1"
	_expect(
		not bool(Catalog._validate_levels(
			level_50_big1_alias,
			bosses_result.value
		).get("ok", false)),
		"level 50 cannot cross-bind a level-25 Big1 resource"
	)
	var missing_death_contract := bosses_document.duplicate(true)
	missing_death_contract.bosses.retail_big_boss_v1.erase("death")
	_expect(
		not bool(Catalog._validate_bosses(missing_death_contract).get("ok", false)),
		"boss contracts missing exact gameplay sections fail closed"
	)
	var missing_effect_runtime := bosses_document.duplicate(true)
	missing_effect_runtime.bosses.retail_big_boss_v1.erase("effect_runtime")
	_expect(
		not bool(Catalog._validate_bosses(missing_effect_runtime).get("ok", false)),
		"boss contracts missing the bounded effect runtime fail closed"
	)
	var wrong_effect_density := bosses_document.duplicate(true)
	wrong_effect_density.bosses.retail_big_boss_v1.effect_runtime.preset.particle_density = 150
	_expect(
		not bool(Catalog._validate_bosses(wrong_effect_density).get("ok", false)),
		"boss contracts cannot select a non-authoritative effect preset"
	)
	var wrong_effect_capacity := bosses_document.duplicate(true)
	wrong_effect_capacity.bosses.retail_big_boss_v1.effect_runtime.pools.smoke.capacity = 499
	_expect(
		not bool(Catalog._validate_bosses(wrong_effect_capacity).get("ok", false)),
		"boss contracts must pin all retail effect pool capacities"
	)
	var wrong_boss_level := bosses_document.duplicate(true)
	wrong_boss_level.bosses.retail_big_boss_v1.level_id = 24
	_expect(
		not bool(Catalog._validate_bosses(wrong_boss_level).get("ok", false)),
		"boss contracts bound to the wrong encounter fail closed"
	)
	var missing_level_50_boss := bosses_document.duplicate(true)
	missing_level_50_boss.bosses.erase("retail_big_boss_level_50_v1")
	_expect(
		not bool(Catalog._validate_bosses(missing_level_50_boss).get("ok", false)),
		"bosses v3 requires both unique state-13 encounter IDs"
	)
	var duplicate_level_50_identity := bosses_document.duplicate(true)
	duplicate_level_50_identity.bosses.retail_big_boss_level_50_v1.id = (
		"retail_big_boss_v1"
	)
	_expect(
		not bool(Catalog._validate_bosses(
			duplicate_level_50_identity
		).get("ok", false)),
		"bosses v3 rejects duplicate embedded contract identities"
	)
	var v3_bosses := _v3_boss_document(bosses_document)
	var v3_bosses_result := Catalog._validate_bosses(v3_bosses)
	_expect(
		bool(v3_bosses_result.get("ok", false)),
		"the synthesized pre-v4 boss catalog remains readable"
	)
	var v7_levels := levels_document.duplicate(true)
	v7_levels.version = 7
	v7_levels.schema = "warblade.levels.v7"
	v7_levels.erase("level_mode_runtime")
	_remove_authored_runtime(v7_levels)
	(v7_levels.levels as Array).resize(62)
	var v7_levels_result := Catalog._validate_levels(
		v7_levels,
		v3_bosses_result.get("value", {})
	)
	var v8_sprites := _v8_sprite_document(sprites_document)
	var v8_sprites_result := Catalog._validate_sprite_frames(v8_sprites)
	_expect(bool(v7_levels_result.get("ok", false)), "levels v7 remains readable")
	_expect(bool(v8_sprites_result.get("ok", false)), "sprite frames v8 remains readable")
	if (
		bool(v7_levels_result.get("ok", false))
		and bool(v8_sprites_result.get("ok", false))
	):
		_expect(
			bool(Catalog._validate_level_sprite_bindings(
				v7_levels_result.value,
				v8_sprites_result.value
			).get("ok", false)),
			"levels v7 and sprite frames v8 remain compatible"
		)
	var bonus_modes_document := _read_json("res://content/bonus_modes.json")
	if not bonus_modes_document.is_empty():
		var legacy_bonus_modes := bonus_modes_document.duplicate(true)
		(legacy_bonus_modes.mode_three_bonus.levels as Array).resize(3)
		var v4_bonus_modes := bonus_modes_document.duplicate(true)
		(v4_bonus_modes.mode_three_bonus.levels as Array).resize(4)
		var v6_bonus_modes := bonus_modes_document.duplicate(true)
		(v6_bonus_modes.mode_three_bonus.levels as Array).resize(6)
		var v7_bonus_modes := bonus_modes_document.duplicate(true)
		(v7_bonus_modes.mode_three_bonus.levels as Array).resize(7)
		for legacy_levels_version in [1, 2, 3]:
			_expect(
				bool(Catalog._validate_bonus_modes(
					legacy_bonus_modes,
					legacy_levels_version
				).get("ok", false)),
				"levels v%d retains the historical three-entry mode-three contract"
				% legacy_levels_version
			)
		_expect(
			bool(Catalog._validate_bonus_modes(v4_bonus_modes, 4).get("ok", false)),
			"levels v4 requires the level-33 mode-three evidence alias"
		)
		_expect(
			not bool(Catalog._validate_bonus_modes(legacy_bonus_modes, 4).get("ok", false)),
			"levels v4 fails closed when its level-33 mode-three entry is missing"
		)
		_expect(
			bool(Catalog._validate_bonus_modes(
				v6_bonus_modes,
				6,
				v6_levels_result.value
			).get("ok", false)),
			"levels v6 requires the level-41 and level-49 mode-three evidence aliases"
		)
		_expect(
				not bool(Catalog._validate_bonus_modes(
				v4_bonus_modes,
				6,
				v6_levels_result.value
			).get("ok", false)),
			"levels v6 fails closed when its level-41 and level-49 entries are missing"
		)
		_expect(
			bool(Catalog._validate_bonus_modes(
				v7_bonus_modes,
				7,
				v7_levels_result.get("value", [])
			).get("ok", false)),
			"levels v7 requires the level-58 mode-three evidence alias"
		)
		var wrong_mode_three_score_levels := (
			v7_levels_result.get("value", []) as Array
		).duplicate(true)
		wrong_mode_three_score_levels[57].enemy_resources[0].kill_score = 501
		_expect(
			not bool(Catalog._validate_bonus_modes(
				v7_bonus_modes,
				7,
				wrong_mode_three_score_levels
			).get("ok", false)),
			"levels v7 fails closed when level 58 diverges from its resource score"
		)
		var v1_loaded := _load_compatibility_fixture(
			"v1",
			legacy_levels,
			legacy_sprites,
			legacy_bonus_modes
		)
		_expect(
			bool(v1_loaded.get("ok", false)),
			"a historical levels-v1 catalog remains loadable: %s"
			% String(v1_loaded.get("error", "unknown error"))
		)
		var v2_loaded := _load_compatibility_fixture(
			"v2",
			v2_levels,
			v3_sprites,
			legacy_bonus_modes,
			v1_bosses
		)
		_expect(
			bool(v2_loaded.get("ok", false)),
			"a historical levels-v2 catalog remains loadable: %s"
			% String(v2_loaded.get("error", "unknown error"))
		)
		_expect_legacy_boss_simulation_configures(
			"bosses-v1/v0.4.0",
			"user://content-catalog-compat-v2"
		)
		var v3_loaded := _load_compatibility_fixture(
			"v3",
			v3_levels,
			v4_sprites,
			legacy_bonus_modes,
			v2_bosses,
			true
		)
		_expect(
			bool(v3_loaded.get("ok", false)),
			"a historical levels-v3 catalog remains loadable: %s"
			% String(v3_loaded.get("error", "unknown error"))
		)
		var v4_loaded := _load_compatibility_fixture(
			"v4",
			v4_levels,
			v5_sprites,
			v4_bonus_modes,
			v2_bosses,
			true
		)
		_expect(
			bool(v4_loaded.get("ok", false)),
			"a historical levels-v4 catalog remains loadable: %s"
			% String(v4_loaded.get("error", "unknown error"))
		)
		var v5_loaded := _load_compatibility_fixture(
			"v5",
			v5_levels,
			v6_sprites,
			v6_bonus_modes,
			v2_bosses,
			true
		)
		_expect(
			bool(v5_loaded.get("ok", false)),
			"a historical levels-v5 catalog remains loadable: %s"
			% String(v5_loaded.get("error", "unknown error"))
		)
		_expect_legacy_boss_simulation_configures(
			"bosses-v2/v0.7.0",
			"user://content-catalog-compat-v5"
		)
		var v6_loaded := _load_compatibility_fixture(
			"v6",
			v6_levels,
			v7_sprites,
			v6_bonus_modes,
			v3_bosses,
			true
		)
		_expect(
			bool(v6_loaded.get("ok", false)),
			"the v0.8 levels-v6/sprites-v7 catalog remains loadable: %s"
			% String(v6_loaded.get("error", "unknown error"))
		)
		_expect_legacy_boss_simulation_configures(
			"bosses-v3/v0.8.0",
			"user://content-catalog-compat-v6",
			50
		)
		var v7_loaded := _load_compatibility_fixture(
			"v7",
			v7_levels,
			v8_sprites,
			v7_bonus_modes,
			v3_bosses,
			true
		)
		_expect(
			bool(v7_loaded.get("ok", false)),
			"the levels-v7/sprites-v8 catalog remains loadable: %s"
			% String(v7_loaded.get("error", "unknown error"))
		)
		var missing_level_33_loaded := _load_compatibility_fixture(
			"v4-missing-level-33",
			v4_levels,
			v5_sprites,
			legacy_bonus_modes,
			v2_bosses,
			true
		)
		_expect(
			not bool(missing_level_33_loaded.get("ok", false))
			and String(missing_level_33_loaded.get("error", "")).contains(
				"mode three"
			),
			"the full levels-v4 loader rejects a missing level-33 mode-three entry"
		)
		var missing_level_41_loaded := _load_compatibility_fixture(
			"v6-missing-level-41",
			v6_levels,
			v7_sprites,
			v4_bonus_modes,
			v3_bosses,
			true
		)
		_expect(
			not bool(missing_level_41_loaded.get("ok", false))
			and String(missing_level_41_loaded.get("error", "")).contains(
				"mode three"
			),
			"the full levels-v6 loader rejects missing level-41/49 mode-three entries"
		)
		var missing_level_58_loaded := _load_compatibility_fixture(
			"v7-missing-level-58",
			v7_levels,
			v8_sprites,
			v6_bonus_modes,
			v3_bosses,
			true
		)
		_expect(
			not bool(missing_level_58_loaded.get("ok", false)),
			"the full levels-v7 loader rejects a missing level-58 mode-three entry"
		)


func _v3_boss_document(source: Dictionary) -> Dictionary:
	var v3 := source.duplicate(true)
	v3.version = 3
	v3.schema = "warblade.bosses.v3"
	v3.bosses.erase("retail_big_boss_level_75_v1")
	v3.bosses.erase("retail_big_boss_level_100_v1")
	for contract_id in [
		"retail_big_boss_v1",
		"retail_big_boss_level_50_v1",
	]:
		var contract := v3.bosses[contract_id] as Dictionary
		contract.initialization.erase("mirror_x")
		contract.initialization.erase("fixed_record_0_raw_words")
		contract.initialization.erase("supplemental_record_0_raw_words")
		contract.opcode_2.erase("burst_groups")
		contract.opcode_2.erase("dynamic_record_count")
		contract.opcode_2.erase("speed")
		contract.path.erase("group_opcode_sequences")
		contract.aimed_fire.erase("origin_groups")
	return v3


func _remove_authored_runtime(document: Dictionary) -> void:
	for level_value in document.get("levels", []):
		if level_value is Dictionary:
			(level_value as Dictionary).erase("authored_runtime")


func _legacy_sprite_document(source: Dictionary) -> Dictionary:
	var legacy := source.duplicate(true)
	legacy.version = 2
	legacy.schema = "warblade.sprite-frames.v2"
	var sheets := legacy.enemy_sheets as Array
	sheets.resize(5)
	var usage := legacy.level_usage as Array
	usage.resize(20)
	for usage_value in usage:
		(usage_value as Dictionary).erase("enemy_resources")
	var linkages := legacy.supplemental_spawn_linkages as Array
	linkages.resize(5)
	var legacy_sheet_ids := ["alien001", "alien_2", "alien_3", "alien000", "alien_lilla"]
	for contract_id in legacy.enemy_projectile_contracts:
		var masks := legacy.enemy_projectile_contracts[contract_id].sheet_masks as Dictionary
		for sheet_id in masks.keys():
			if not legacy_sheet_ids.has(sheet_id):
				masks.erase(sheet_id)
	return legacy


func _v3_sprite_document(source: Dictionary) -> Dictionary:
	var v3 := source.duplicate(true)
	v3.version = 3
	v3.schema = "warblade.sprite-frames.v3"
	var sheets := v3.enemy_sheets as Array
	sheets.resize(13)
	var usage := v3.level_usage as Array
	usage.resize(25)
	var linkages := v3.supplemental_spawn_linkages as Array
	linkages.resize(6)
	var v3_sheet_ids := [
		"alien001", "alien_2", "alien_3", "alien000", "alien_lilla",
		"alien003", "alien003_3", "alien_big1_1", "alien_big1_2",
		"alien_big1_3", "alien_big1_4", "alien_big1_5", "alien_big1_6",
	]
	for contract_id in v3.enemy_projectile_contracts:
		var masks := v3.enemy_projectile_contracts[contract_id].sheet_masks as Dictionary
		for sheet_id in masks.keys():
			if not v3_sheet_ids.has(sheet_id):
				masks.erase(sheet_id)
	return v3


func _v4_sprite_document(source: Dictionary) -> Dictionary:
	var v4 := source.duplicate(true)
	v4.version = 4
	v4.schema = "warblade.sprite-frames.v4"
	var sheets := v4.enemy_sheets as Array
	sheets.resize(17)
	var usage := v4.level_usage as Array
	usage.resize(30)
	var linkages := v4.supplemental_spawn_linkages as Array
	linkages.resize(7)
	var v4_sheet_ids := [
		"alien001", "alien_2", "alien_3", "alien000", "alien_lilla",
		"alien003", "alien003_3", "alien_big1_1", "alien_big1_2",
		"alien_big1_3", "alien_big1_4", "alien_big1_5", "alien_big1_6",
		"alien_rakett", "alien_rakett_gronn", "alien_baller", "alien_baller2",
	]
	for contract_id in v4.enemy_projectile_contracts:
		var masks := v4.enemy_projectile_contracts[contract_id].sheet_masks as Dictionary
		for sheet_id in masks.keys():
			if not v4_sheet_ids.has(sheet_id):
				masks.erase(sheet_id)
	return v4


func _v5_sprite_document(source: Dictionary) -> Dictionary:
	var v5 := source.duplicate(true)
	v5.version = 5
	v5.schema = "warblade.sprite-frames.v5"
	var sheets := v5.enemy_sheets as Array
	sheets.resize(19)
	var usage := v5.level_usage as Array
	usage.resize(35)
	var linkages := v5.supplemental_spawn_linkages as Array
	linkages.resize(8)
	var v5_sheet_ids := [
		"alien001", "alien_2", "alien_3", "alien000", "alien_lilla",
		"alien003", "alien003_3", "alien_big1_1", "alien_big1_2",
		"alien_big1_3", "alien_big1_4", "alien_big1_5", "alien_big1_6",
		"alien_rakett", "alien_rakett_gronn", "alien_baller", "alien_baller2",
		"alien_green_lilla_t", "alien_cyan_lilla_t",
	]
	for contract_id in v5.enemy_projectile_contracts:
		var masks := v5.enemy_projectile_contracts[contract_id].sheet_masks as Dictionary
		for sheet_id in masks.keys():
			if not v5_sheet_ids.has(sheet_id):
				masks.erase(sheet_id)
	return v5


func _v6_sprite_document(source: Dictionary) -> Dictionary:
	var v6 := source.duplicate(true)
	v6.version = 6
	v6.schema = "warblade.sprite-frames.v6"
	var sheets := v6.enemy_sheets as Array
	sheets.resize(24)
	var usage := v6.level_usage as Array
	usage.resize(49)
	var linkages := v6.supplemental_spawn_linkages as Array
	linkages.resize(13)
	var v6_sheet_ids: Array[String] = []
	for sheet_value in sheets:
		v6_sheet_ids.append(String((sheet_value as Dictionary).id))
	for contract_id in v6.enemy_projectile_contracts:
		var masks := v6.enemy_projectile_contracts[contract_id].sheet_masks as Dictionary
		for sheet_id in masks.keys():
			if not v6_sheet_ids.has(String(sheet_id)):
				masks.erase(sheet_id)
	return v6


func _v7_sprite_document(source: Dictionary) -> Dictionary:
	var v7 := source.duplicate(true)
	v7.version = 7
	v7.schema = "warblade.sprite-frames.v7"
	var sheets := v7.enemy_sheets as Array
	sheets.resize(30)
	var usage := v7.level_usage as Array
	usage.resize(50)
	var linkages := v7.supplemental_spawn_linkages as Array
	linkages.resize(13)
	var v7_sheet_ids: Array[String] = []
	for sheet_value in sheets:
		v7_sheet_ids.append(String((sheet_value as Dictionary).id))
	for contract_id in v7.enemy_projectile_contracts:
		var masks := v7.enemy_projectile_contracts[contract_id].sheet_masks as Dictionary
		for sheet_id in masks.keys():
			if not v7_sheet_ids.has(String(sheet_id)):
				masks.erase(sheet_id)
	return v7


func _v10_sprite_document(source: Dictionary) -> Dictionary:
	var v10 := source.duplicate(true)
	v10.version = 10
	v10.schema = "warblade.sprite-frames.v10"
	v10.erase("time_trial_level_usage")
	var sheets := v10.enemy_sheets as Array
	sheets.resize(80)
	var v10_sheet_ids: Array[String] = []
	for sheet_value in sheets:
		v10_sheet_ids.append(String((sheet_value as Dictionary).id))
	for contract_id in v10.enemy_projectile_contracts:
		var masks := v10.enemy_projectile_contracts[contract_id].sheet_masks as Dictionary
		for sheet_id in masks.keys():
			if not v10_sheet_ids.has(String(sheet_id)):
				masks.erase(sheet_id)
	return v10


func _v8_sprite_document(source: Dictionary) -> Dictionary:
	var v8 := source.duplicate(true)
	v8.version = 8
	v8.schema = "warblade.sprite-frames.v8"
	var sheets := v8.enemy_sheets as Array
	sheets.resize(39)
	var usage := v8.level_usage as Array
	usage.resize(62)
	var linkages := v8.supplemental_spawn_linkages as Array
	linkages.resize(17)
	var v8_sheet_ids: Array[String] = []
	for sheet_value in sheets:
		v8_sheet_ids.append(String((sheet_value as Dictionary).id))
	for contract_id in v8.enemy_projectile_contracts:
		var masks := v8.enemy_projectile_contracts[contract_id].sheet_masks as Dictionary
		for sheet_id in masks.keys():
			if not v8_sheet_ids.has(String(sheet_id)):
				masks.erase(sheet_id)
	return v8


func _load_compatibility_fixture(
	label: String,
	levels: Dictionary,
	sprites: Dictionary,
	bonus_modes: Dictionary,
	bosses: Dictionary = {},
	include_ordnance: bool = false
) -> Dictionary:
	var base_path := "user://content-catalog-compat-%s" % label
	var absolute_path := ProjectSettings.globalize_path(base_path)
	var mkdir_error := DirAccess.make_dir_recursive_absolute(absolute_path)
	if mkdir_error != OK:
		return {"ok": false, "error": "cannot create compatibility fixture directory"}
	var overridden_documents := {
		"levels.json": levels,
		"sprite_frames.json": sprites,
		"bonus_modes.json": bonus_modes,
	}
	for file_name in Catalog.LEGACY_REQUIRED_FILES:
		var destination := base_path.path_join(file_name)
		var output := FileAccess.open(destination, FileAccess.WRITE)
		if output == null:
			return {"ok": false, "error": "cannot write %s" % destination}
		if overridden_documents.has(file_name):
			output.store_string(
				JSON.stringify(overridden_documents[file_name], "\t") + "\n"
			)
		else:
			output.store_buffer(FileAccess.get_file_as_bytes(
				"res://content/%s" % file_name
			))
	if not bosses.is_empty():
		var bosses_output := FileAccess.open(
			base_path.path_join("bosses.json"),
			FileAccess.WRITE
		)
		if bosses_output == null:
			return {"ok": false, "error": "cannot write bosses fixture"}
		# Boss contract order is part of the fail-closed schema. Preserve the
		# source document order instead of JSON.stringify's default key sort.
		bosses_output.store_string(JSON.stringify(bosses, "\t", false) + "\n")
	if include_ordnance:
		var ordnance_output := FileAccess.open(
			base_path.path_join("ordnance.json"),
			FileAccess.WRITE
		)
		if ordnance_output == null:
			return {"ok": false, "error": "cannot write ordnance fixture"}
		ordnance_output.store_buffer(FileAccess.get_file_as_bytes(
			"res://content/ordnance.json"
		))
	return Catalog.load_catalog(base_path)


func _expect_legacy_boss_simulation_configures(
	label: String,
	base_path: String,
	level_id: int = 25
) -> void:
	var simulation := Simulation.new()
	var configured := simulation.configure({
		"mode": "solo",
		"difficulty": "normal",
		"coop_balance": "classic",
		"collision_mode": "simple",
		"seed": 250700,
		"start_level": level_id,
		"end_level": level_id,
		"record_replay": false,
		"content_base_path": base_path,
	})
	_expect(
		configured,
		"the authentic %s catalog configures the full simulation: %s"
		% [label, simulation.get_last_error()]
	)


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	_expect(file != null, "%s is readable" % path)
	if file == null:
		return {}
	var parser := JSON.new()
	var parse_error := parser.parse(file.get_as_text())
	_expect(parse_error == OK and parser.data is Dictionary, "%s contains a JSON object" % path)
	if parse_error != OK or not parser.data is Dictionary:
		return {}
	return (parser.data as Dictionary).duplicate(true)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

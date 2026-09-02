class_name WBHiscoreStore
extends RefCounted

## Local halls of fame, modeled on the retail per-mode tables: one table per
## difficulty plus Meteor Storm and Time Trial, top 20 entries each, with the
## retail per-entry details (rank, duration, shots, hits, hit rate, date).
## Scores are the end-of-game totals (raw score plus the GAME BONUSES sum).

const DEFAULT_PATH := "user://hiscores.json"
const STORE_VERSION := 1
const TABLE_KINDS := ["easy", "normal", "hard", "ace", "meteorstorm", "timetrial"]
const MAX_ENTRIES := 20

var _path := DEFAULT_PATH
var _tables: Dictionary = {}
var last_save_error := ""


func configure_path(path: String) -> void:
	_path = path


func load_tables() -> void:
	_tables = {}
	for kind in TABLE_KINDS:
		_tables[kind] = []
	if not FileAccess.file_exists(_path):
		return
	var file := FileAccess.open(_path, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return
	var stored_tables: Variant = (parsed as Dictionary).get("tables", {})
	if not stored_tables is Dictionary:
		return
	for kind in TABLE_KINDS:
		var entries_value: Variant = (stored_tables as Dictionary).get(kind, [])
		if not entries_value is Array:
			continue
		var entries: Array = []
		for entry_value: Variant in (entries_value as Array):
			if entry_value is Dictionary:
				entries.append(_sanitize_entry(entry_value as Dictionary))
		_sort_and_trim(entries)
		_tables[kind] = entries


func table(kind: String) -> Array:
	var entries_value: Variant = _tables.get(kind, [])
	return (entries_value as Array).duplicate(true) if entries_value is Array else []


## Records every scoring entry a finished match produces: the difficulty
## table receives each participating seat's total, and the Meteor Storm table
## receives non-zero meteor scores. Demo results must not be passed here.
func record_result(
	result: Dictionary,
	mode: String,
	difficulty: String,
	names_by_seat: Array
) -> bool:
	# Retail match mode 6 has its own hall of fame instead of a difficulty
	# table, so a Time Trial run never lands in the difficulty ladder.
	var table_kind := (
		"timetrial" if mode == "time_trial"
		else (difficulty if difficulty in TABLE_KINDS else "normal")
	)
	var tallies: Array = result.get("tally_by_seat", [])
	var profile_stats: Array = result.get("profile_stats", [])
	var duration_ticks := maxi(0, int(result.get("tick", 0)))
	var level_reached := int(result.get("level_reached", result.get("level_id", 1)))
	var recorded := false
	var now := int(Time.get_unix_time_from_system())
	for seat_id in range(names_by_seat.size()):
		var seat_name := str(names_by_seat[seat_id])
		if seat_name.is_empty():
			continue
		var tally: Dictionary = (
			tallies[seat_id] if seat_id < tallies.size() and tallies[seat_id] is Dictionary
			else {}
		)
		if tally.is_empty():
			continue
		var stats: Dictionary = (
			profile_stats[seat_id]
			if seat_id < profile_stats.size() and profile_stats[seat_id] is Dictionary
			else {}
		)
		var entry := {
			"name": seat_name,
			"score": int(tally.get("total_score", 0)),
			"rank_index": int(tally.get("rank_index", 0)),
			"duration_ticks": duration_ticks,
			"shots": int(stats.get("projectile_objects_fired", 0)),
			"hits": int(stats.get("successful_hits", 0)),
			"hit_percent": int(tally.get("hit_percent", 0)),
			"level": level_reached,
			"mode": mode,
			"at": now,
		}
		if int(entry.score) > 0:
			_insert_entry(table_kind, entry)
			recorded = true
		var meteor_score := int(stats.get("meteor_score", 0))
		if meteor_score > 0:
			_insert_entry(
				"meteorstorm",
				{
					"name": seat_name,
					"score": meteor_score,
					"rank_index": int(tally.get("rank_index", 0)),
					"duration_ticks": duration_ticks,
					"shots": 0,
					"hits": 0,
					"hit_percent": 0,
					"level": level_reached,
					"mode": mode,
					"at": now,
				}
			)
			recorded = true
	if not recorded:
		return true
	return save_tables()


func record_time_trial(entry: Dictionary) -> bool:
	_insert_entry("timetrial", _sanitize_entry(entry))
	return save_tables()


func save_tables() -> bool:
	last_save_error = ""
	var payload := JSON.stringify(
		{"version": STORE_VERSION, "tables": _tables},
		"\t"
	)
	var temporary_path := "%s.tmp-%d" % [_path, Time.get_ticks_usec()]
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		last_save_error = "Unable to create a temporary hiscore file."
		return false
	file.store_string(payload)
	file.close()
	var error := DirAccess.rename_absolute(
		ProjectSettings.globalize_path(temporary_path),
		ProjectSettings.globalize_path(_path)
	)
	if error != OK:
		last_save_error = "Unable to publish the hiscore file (error %d)." % error
		var absolute_temporary := ProjectSettings.globalize_path(temporary_path)
		if FileAccess.file_exists(absolute_temporary):
			DirAccess.remove_absolute(absolute_temporary)
		return false
	return true


func _insert_entry(kind: String, entry: Dictionary) -> void:
	var entries_value: Variant = _tables.get(kind, [])
	var entries: Array = entries_value if entries_value is Array else []
	entries.append(_sanitize_entry(entry))
	_sort_and_trim(entries)
	_tables[kind] = entries


static func _sort_and_trim(entries: Array) -> void:
	entries.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
		if int(left.get("score", 0)) == int(right.get("score", 0)):
			return int(left.get("at", 0)) < int(right.get("at", 0))
		return int(left.get("score", 0)) > int(right.get("score", 0))
	)
	while entries.size() > MAX_ENTRIES:
		entries.pop_back()


static func _sanitize_entry(entry: Dictionary) -> Dictionary:
	return {
		"name": str(entry.get("name", "PILOT")).substr(0, 16),
		"score": maxi(0, int(entry.get("score", 0))),
		"rank_index": clampi(int(entry.get("rank_index", 0)), 0, 32),
		"duration_ticks": maxi(0, int(entry.get("duration_ticks", 0))),
		"shots": maxi(0, int(entry.get("shots", 0))),
		"hits": maxi(0, int(entry.get("hits", 0))),
		"hit_percent": clampi(int(entry.get("hit_percent", 0)), 0, 100),
		"level": clampi(int(entry.get("level", 1)), 1, 3999),
		"mode": str(entry.get("mode", "solo")).substr(0, 16),
		"at": maxi(0, int(entry.get("at", 0))),
	}

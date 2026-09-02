class_name WBSaveGameStore
extends RefCounted

## Retail in-shop saved games. The retail writer (`FUN_00537c80`) and loader
## (`FUN_005384f0`) address slots through
## `%s\warblade\profiles\profile%03d.svg` and serialize a raw image of the
## retail state block, so byte compatibility with the original files is neither
## reachable nor meaningful for a different engine. The remake keeps the
## behavioral contract — shop-only writes, slot-addressed files, a resumable
## run — and stores its own authoritative shop-boundary state.

const SLOT_COUNT := 10
const DEFAULT_DIRECTORY := "user://savegames"
const STORE_VERSION := 1

var last_error := ""

var _directory := DEFAULT_DIRECTORY


func configure_directory(path: String) -> void:
	_directory = path


func slot_path(slot: int) -> String:
	return _directory.path_join("savegame%03d.json" % slot)


func has_slot(slot: int) -> bool:
	return _is_valid_slot(slot) and FileAccess.file_exists(slot_path(slot))


## One line per slot for the load menu: whether it is occupied and, when it is,
## the run's mode, difficulty, level, and score.
func slot_summaries() -> Array[Dictionary]:
	var summaries: Array[Dictionary] = []
	for slot in range(SLOT_COUNT):
		var summary := {
			"slot": slot,
			"occupied": false,
			"mode": "",
			"difficulty": "",
			"level_id": 0,
			"score": 0,
			"saved_at": 0,
		}
		var save := load_slot(slot)
		if not save.is_empty():
			var match_config: Dictionary = save.get("match_config", {})
			var state: Dictionary = save.get("state", {})
			var progression: Dictionary = state.get("shared_progression", {})
			summary["occupied"] = true
			summary["mode"] = str(match_config.get("mode", ""))
			summary["difficulty"] = str(match_config.get("difficulty", ""))
			summary["level_id"] = int(state.get("level_id", 0))
			summary["score"] = int(progression.get("score", 0))
			summary["saved_at"] = int(save.get("saved_at", 0))
		summaries.append(summary)
	return summaries


func save_slot(slot: int, save: Dictionary) -> bool:
	last_error = ""
	if not _is_valid_slot(slot):
		last_error = "save slot is out of range"
		return false
	if save.is_empty():
		last_error = "saved run is empty"
		return false
	var payload := save.duplicate(true)
	payload["store_version"] = STORE_VERSION
	payload["slot"] = slot
	payload["saved_at"] = int(Time.get_unix_time_from_system())
	if DirAccess.make_dir_recursive_absolute(_directory) != OK:
		if not DirAccess.dir_exists_absolute(_directory):
			last_error = "cannot create the saved-game directory"
			return false
	var canonical := slot_path(slot)
	var temporary := "%s.tmp-%d" % [canonical, Time.get_ticks_usec()]
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		last_error = "cannot write save slot %d" % slot
		return false
	file.store_string(JSON.stringify(payload, "\t"))
	file.close()
	var error := DirAccess.rename_absolute(
		ProjectSettings.globalize_path(temporary),
		ProjectSettings.globalize_path(canonical)
	)
	if error != OK:
		last_error = "cannot publish save slot %d (error %d)" % [slot, error]
		var absolute_temporary := ProjectSettings.globalize_path(temporary)
		if FileAccess.file_exists(absolute_temporary):
			DirAccess.remove_absolute(absolute_temporary)
		return false
	return true


func load_slot(slot: int) -> Dictionary:
	last_error = ""
	if not has_slot(slot):
		return {}
	var file := FileAccess.open(slot_path(slot), FileAccess.READ)
	if file == null:
		last_error = "cannot read save slot %d" % slot
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		last_error = "save slot %d is malformed" % slot
		return {}
	var save := parsed as Dictionary
	if int(save.get("store_version", 0)) != STORE_VERSION:
		last_error = "save slot %d uses an unsupported store version" % slot
		return {}
	return save


func clear_slot(slot: int) -> bool:
	last_error = ""
	if not has_slot(slot):
		return true
	if DirAccess.remove_absolute(
		ProjectSettings.globalize_path(slot_path(slot))
	) != OK:
		last_error = "cannot clear save slot %d" % slot
		return false
	return true


func _is_valid_slot(slot: int) -> bool:
	return slot >= 0 and slot < SLOT_COUNT

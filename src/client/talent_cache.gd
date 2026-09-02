class_name WBTalentCache
extends RefCounted

## The last talent/profile state the lobby server sent, cached at
## user://talent_cache.json so offline solo and couch play still apply the
## grants the player has earned. Same flushed temp+rename publish pattern as
## the other stores.

const DEFAULT_PATH := "user://talent_cache.json"
const VERSION := 1

var _path := DEFAULT_PATH


func configure_path(path: String) -> void:
	_path = path


## Returns the cached profile state, or {} when nothing valid is cached.
func load_state() -> Dictionary:
	if not FileAccess.file_exists(_path):
		return {}
	var file := FileAccess.open(_path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return {}
	var record := parsed as Dictionary
	if int(record.get("version", 0)) != VERSION:
		return {}
	var state_value: Variant = record.get("profile_state", {})
	return (state_value as Dictionary).duplicate(true) if state_value is Dictionary else {}


func store_state(state: Dictionary) -> bool:
	var record := {
		"version": VERSION,
		"cached_unix": int(Time.get_unix_time_from_system()),
		"profile_state": state.duplicate(true),
	}
	var temporary_path := _path + ".tmp"
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(record, "\t"))
	file.flush()
	file.close()
	var absolute_temporary := ProjectSettings.globalize_path(temporary_path)
	var absolute_target := ProjectSettings.globalize_path(_path)
	return DirAccess.rename_absolute(absolute_temporary, absolute_target) == OK


func clear() -> bool:
	if FileAccess.file_exists(_path):
		return DirAccess.remove_absolute(ProjectSettings.globalize_path(_path)) == OK
	return true

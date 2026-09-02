class_name WBJukeboxStore
extends RefCounted

## Modern reimplementation of the retail Jukebox: per-slot soundtrack
## overrides and a Main-slot playlist, persisted inside settings.json.
## Retail stored playlists per profile (Warblade.wpl); the remake keeps one
## global configuration because the audio director is configured before any
## profile is selected (documented modernization).

const VERSION := 1
const MAX_PLAYLIST_ENTRIES := 64

## slot_id -> canonical music key consumed by WBAudioDirector.
const SLOTS := {
	"title": "title",
	"main": "warblade",
	"shop": "shop",
	"boss": "boss",
	"memorystation": "memory",
	"meteorstorm": "meteor",
	"gemdrop": "gems",
	"hiscore": "hiscore",
	"promoted": "promoted",
	"timetrial": "timetrial",
	"end": "end",
}
const SLOT_LABELS := {
	"title": "TITLE MUSIC",
	"main": "MAIN MUSIC",
	"shop": "SHOP MUSIC",
	"boss": "BOSS MUSIC",
	"memorystation": "MEMORYSTATION MUSIC",
	"meteorstorm": "METEORSTORM MUSIC",
	"gemdrop": "GEM DROP MUSIC",
	"hiscore": "HISCORE MUSIC",
	"promoted": "PROMOTED MUSIC",
	"timetrial": "TIMETRIAL MUSIC",
	"end": "END MUSIC",
}
const USER_FILE_EXTENSIONS := ["mp3", "ogg"]

var _config: Dictionary = {}


func _init() -> void:
	_config = sanitize({})


func configure(config: Variant) -> void:
	_config = sanitize(config)


func values() -> Dictionary:
	return _config.duplicate(true)


static func slot_for_music_key(key: String) -> String:
	for slot_id in SLOTS:
		if str(SLOTS[slot_id]) == key:
			return str(slot_id)
	return ""


## Returns {} when the built-in track should play, or an override:
## {"kind": "builtin", "key": other_music_key}
## {"kind": "user", "path": absolute_path}
## {"kind": "playlist", "entries": [slot entries]} (main slot only)
func override_for_music_key(key: String) -> Dictionary:
	if key == str(SLOTS["main"]) and bool(_config.get("main_playlist_enabled", false)):
		var entries: Array = _config.get("main_playlist", [])
		if not entries.is_empty():
			return {"kind": "playlist", "entries": entries.duplicate(true)}
	var slot_id := slot_for_music_key(key)
	if slot_id.is_empty():
		return {}
	var slots: Dictionary = _config.get("slots", {})
	var slot_value: Variant = slots.get(slot_id)
	if not slot_value is Dictionary:
		return {}
	var slot := slot_value as Dictionary
	match str(slot.get("source", "")):
		"builtin":
			var target := str(slot.get("key", ""))
			if not target.is_empty() and target != key:
				return {"kind": "builtin", "key": target}
		"user":
			var path := str(slot.get("path", ""))
			if not path.is_empty():
				return {"kind": "user", "path": path}
	return {}


## Loads a user-supplied MP3/OGG file; returns null (never raises) when the
## file is missing or unreadable so callers always fall back to the built-in.
static func load_user_stream(path: String) -> AudioStream:
	if path.is_empty() or not FileAccess.file_exists(path):
		return null
	var extension := path.get_extension().to_lower()
	if extension == "mp3":
		return AudioStreamMP3.load_from_file(path)
	if extension == "ogg":
		return AudioStreamOggVorbis.load_from_file(path)
	return null


static func sanitize(value: Variant) -> Dictionary:
	var result := {
		"version": VERSION,
		"slots": {},
		"main_playlist": [],
		"main_playlist_enabled": false,
	}
	if not value is Dictionary:
		return result
	var source := value as Dictionary
	var slots_value: Variant = source.get("slots", {})
	if slots_value is Dictionary:
		for slot_id_value: Variant in (slots_value as Dictionary):
			var slot_id := str(slot_id_value)
			if not SLOTS.has(slot_id):
				continue
			var slot_value: Variant = (slots_value as Dictionary)[slot_id_value]
			if not slot_value is Dictionary:
				continue
			var entry := _sanitize_entry(slot_value as Dictionary)
			if not entry.is_empty():
				(result["slots"] as Dictionary)[slot_id] = entry
	var playlist_value: Variant = source.get("main_playlist", [])
	if playlist_value is Array:
		var playlist: Array = []
		for entry_value: Variant in (playlist_value as Array):
			if playlist.size() >= MAX_PLAYLIST_ENTRIES:
				break
			if entry_value is Dictionary:
				var entry := _sanitize_entry(entry_value as Dictionary)
				if not entry.is_empty():
					playlist.append(entry)
		result["main_playlist"] = playlist
	result["main_playlist_enabled"] = (
		bool(source.get("main_playlist_enabled", false))
		and not (result["main_playlist"] as Array).is_empty()
	)
	return result


static func _sanitize_entry(entry: Dictionary) -> Dictionary:
	match str(entry.get("source", "")):
		"builtin":
			var key := str(entry.get("key", "")).strip_edges().to_lower()
			if not key.is_empty() and key.length() <= 64:
				return {"source": "builtin", "key": key}
		"user":
			var path := str(entry.get("path", "")).strip_edges()
			if not path.is_empty() and path.length() <= 1024:
				if path.get_extension().to_lower() in USER_FILE_EXTENSIONS:
					return {"source": "user", "path": path}
	return {}

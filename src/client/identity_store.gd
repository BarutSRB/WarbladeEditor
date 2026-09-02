class_name WBIdentityStore
extends RefCounted

## The player's lobby identity: a random device key generated on first run
## plus the nickname registered with the lobby server. Persisted at
## user://identity.json with the same flushed temp+rename pattern the
## profile store uses. The key never leaves this file except inside the
## authentication request; profile ids derive from its hash, never the key.

const DEFAULT_PATH := "user://identity.json"
const VERSION := 1
const DEVICE_KEY_BYTES := 32
const PROFILE_ID_PREFIX := "dev_"

var _path := DEFAULT_PATH
var _record: Dictionary = {}


func configure_path(path: String) -> void:
	_path = path


## Loads the identity, generating and publishing a fresh device key when the
## file is missing or invalid. Returns the record view.
func load_identity() -> Dictionary:
	_record = {}
	if FileAccess.file_exists(_path):
		var file := FileAccess.open(_path, FileAccess.READ)
		if file != null:
			var parsed: Variant = JSON.parse_string(file.get_as_text())
			if parsed is Dictionary and int((parsed as Dictionary).get("version", 0)) == VERSION:
				_record = (parsed as Dictionary).duplicate(true)
	if not is_valid_device_key(str(_record.get("device_key", ""))):
		_record = {
			"version": VERSION,
			"device_key": generate_device_key(),
			"nickname": "",
		}
		_publish()
	elif not WBLobbyContract.is_valid_nickname(str(_record.get("nickname", ""))):
		_record["nickname"] = ""
	return values()


func values() -> Dictionary:
	return _record.duplicate(true)


func device_key() -> String:
	return str(_record.get("device_key", ""))


func nickname() -> String:
	return str(_record.get("nickname", ""))


func has_nickname() -> bool:
	return not nickname().is_empty()


func set_nickname(name: String) -> bool:
	if _record.is_empty():
		return false
	if not name.is_empty() and not WBLobbyContract.is_valid_nickname(name):
		return false
	_record["nickname"] = name
	return _publish()


## The local profile id bound to this identity: a prefix plus the first 16
## hex characters of the key's SHA-256, so the id can be shown and stored
## without exposing the key.
func profile_id() -> String:
	var key := device_key()
	if key.is_empty():
		return ""
	return PROFILE_ID_PREFIX + key.sha256_text().substr(0, 16)


func clear() -> bool:
	_record = {}
	if FileAccess.file_exists(_path):
		return DirAccess.remove_absolute(ProjectSettings.globalize_path(_path)) == OK
	return true


static func generate_device_key() -> String:
	return Crypto.new().generate_random_bytes(DEVICE_KEY_BYTES).hex_encode()


static func is_valid_device_key(key: String) -> bool:
	if key.length() != DEVICE_KEY_BYTES * 2:
		return false
	for character in key:
		if not "0123456789abcdef".contains(character):
			return false
	return true


func _publish() -> bool:
	var temporary_path := _path + ".tmp"
	var file := FileAccess.open(temporary_path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(_record, "\t"))
	file.flush()
	file.close()
	var absolute_temporary := ProjectSettings.globalize_path(temporary_path)
	var absolute_target := ProjectSettings.globalize_path(_path)
	return DirAccess.rename_absolute(absolute_temporary, absolute_target) == OK

class_name WBAssetLibrary
extends RefCounted

const DEFAULT_MANIFEST_PATH := "res://content/presentation.json"
const SUPPORTED_MANIFEST_SCHEMAS := {
	1: "warblade.presentation.v1",
	2: "warblade.presentation.v2",
}
const PACK_SCHEMA := "warblade.sprite-pack.v1"
const PACK_VERSION := 1
const PACK_ROOTS: Array[String] = ["res://assets/packs", "user://packs"]

## The active sprite pack overrides retail textures key-by-key with same-size
## replacements. It is class-level state so every library instance in the
## client resolves through the same pack; a broken or partial pack always
## falls back to retail art and can never fail boot validation.
static var _active_pack_name := ""
static var _active_pack_dir := ""
static var _active_pack_textures: Dictionary = {}
static var _pack_warned: Dictionary = {}

var last_error := ""

var _manifest_path := DEFAULT_MANIFEST_PATH
var _manifest: Dictionary = {}
var _textures: Dictionary = {}
var _music: Dictionary = {}
var _sfx: Dictionary = {}
var _voices: Dictionary = {}
var _voice_pack_clips: Dictionary = {}
var _loaded := false
var _manifest_ok := false
var _manifest_hash := ""


func configure(path: String = DEFAULT_MANIFEST_PATH) -> bool:
	clear()
	_manifest_path = path
	return _load_manifest()


func texture(key: String) -> Texture2D:
	if not _load_manifest():
		return null
	var asset_id := _asset_id(key)
	if _textures.has(asset_id):
		return _textures[asset_id] as Texture2D
	var pack_texture := _pack_texture(asset_id)
	if pack_texture != null:
		_textures[asset_id] = pack_texture
		return pack_texture
	var resource := _load_typed_resource("textures", asset_id)
	if resource is Texture2D:
		_textures[asset_id] = resource
		return resource as Texture2D
	return null


func music(key: String) -> AudioStream:
	return _audio_resource("music", key, _music)


func sfx(key: String) -> AudioStream:
	return _audio_resource("sfx", key, _sfx)


func voice(key: String) -> AudioStream:
	return _audio_resource("voices", key, _voices)


func voice_pack(pack_id: int, key: String) -> AudioStream:
	if pack_id <= 1:
		return voice(key)
	if not _load_manifest():
		return null
	var asset_id := _asset_id(key)
	var cache_key := "%d:%s" % [pack_id, asset_id]
	if _voice_pack_clips.has(cache_key):
		return _voice_pack_clips[cache_key] as AudioStream
	var entry := voice_pack_clip_metadata(pack_id, asset_id)
	if entry.is_empty():
		last_error = "presentation asset is not declared: voice_pack_%d:%s" % [pack_id, asset_id]
		return null
	var path := String(entry.get("path", ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		last_error = "presentation resource is unavailable: voice_pack_%d:%s" % [pack_id, asset_id]
		return null
	var resource := ResourceLoader.load(path)
	if resource is AudioStream:
		_voice_pack_clips[cache_key] = resource
		return resource as AudioStream
	last_error = "presentation resource failed to load: voice_pack_%d:%s" % [pack_id, asset_id]
	return null


func voice_pack_clip_metadata(pack_id: int, key: String) -> Dictionary:
	if not _load_manifest():
		return {}
	var packs_value: Variant = _manifest.get("voice_packs", {})
	if not packs_value is Dictionary:
		return {}
	var pack_value: Variant = (packs_value as Dictionary).get(str(pack_id), {})
	if not pack_value is Dictionary:
		return {}
	var clips_value: Variant = (pack_value as Dictionary).get("clips", {})
	if not clips_value is Dictionary:
		return {}
	var entry_value: Variant = (clips_value as Dictionary).get(_asset_id(key))
	return (entry_value as Dictionary).duplicate(true) if entry_value is Dictionary else {}


func audio(key: String) -> AudioStream:
	var music_stream := music(key)
	if music_stream != null:
		return music_stream
	var sfx_stream := sfx(key)
	if sfx_stream != null:
		return sfx_stream
	return voice(key)


func texture_metadata(key: String) -> Dictionary:
	return _entry("textures", key)


func music_metadata(key: String) -> Dictionary:
	return _entry("music", key)


func sfx_metadata(key: String) -> Dictionary:
	return _entry("sfx", key)


func voice_metadata(key: String) -> Dictionary:
	return _entry("voices", key)


func section(name: String) -> Dictionary:
	if not _load_manifest():
		return {}
	var value: Variant = _manifest.get(name, {})
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func has_asset(key: String) -> bool:
	if not _load_manifest():
		return false
	var asset_id := _asset_id(key)
	return (
		(_manifest.get("textures", {}) as Dictionary).has(asset_id)
		or (_manifest.get("music", {}) as Dictionary).has(asset_id)
		or (_manifest.get("sfx", {}) as Dictionary).has(asset_id)
		or (_manifest.get("voices", {}) as Dictionary).has(asset_id)
	)


func manifest_hash() -> String:
	if not _load_manifest():
		return ""
	return _manifest_hash


func manifest_version() -> int:
	if not _load_manifest():
		return 0
	return int(_manifest.get("version", 0))


func validate_required(include_audio: bool = true, include_optional: bool = false) -> Dictionary:
	if not _load_manifest():
		return {"ok": false, "errors": [last_error], "counts": {}}
	var errors: Array[String] = []
	var counts := {
		"textures": 0,
		"hit_masks": 0,
		"music": 0,
		"sfx": 0,
		"voices": 0,
		"voice_pack_clips": 0,
		"ending_slides": 0,
	}
	_validate_texture_entries(errors, counts, include_optional)
	_validate_hit_mask_entries(errors, counts, include_optional)
	if include_audio:
		_validate_audio_entries("music", errors, counts, include_optional)
		_validate_audio_entries("sfx", errors, counts, include_optional)
		_validate_audio_entries("voices", errors, counts, include_optional)
		if include_optional:
			_validate_voice_pack_entries(errors, counts)
	_validate_ending_contract(errors, counts)
	last_error = "" if errors.is_empty() else "; ".join(errors)
	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"counts": counts,
		"manifest_hash": _manifest_hash,
	}


func clear() -> void:
	_textures.clear()
	_music.clear()
	_sfx.clear()
	_voices.clear()
	_voice_pack_clips.clear()
	_manifest.clear()
	_manifest_hash = ""
	last_error = ""
	_loaded = false
	_manifest_ok = false


func _load_manifest() -> bool:
	# Health is tracked by _manifest_ok, not last_error: a missed lookup
	# (for example an intentionally incomplete voice pack) records its
	# message without poisoning every later load.
	if _loaded:
		return _manifest_ok
	_loaded = true
	if not FileAccess.file_exists(_manifest_path):
		return _fail("presentation manifest is missing: %s" % _manifest_path)
	var file := FileAccess.open(_manifest_path, FileAccess.READ)
	if file == null:
		return _fail("presentation manifest cannot be read: %s" % _manifest_path)
	var raw := file.get_as_text()
	file.close()
	var json := JSON.new()
	if json.parse(raw) != OK or typeof(json.data) != TYPE_DICTIONARY:
		return _fail("presentation manifest is not valid JSON")
	var document := json.data as Dictionary
	var version := int(document.get("version", 0))
	if not SUPPORTED_MANIFEST_SCHEMAS.has(version):
		return _fail("unsupported presentation manifest version")
	if String(document.get("schema", "")) != String(SUPPORTED_MANIFEST_SCHEMAS[version]):
		return _fail("unsupported presentation manifest schema")
	for section_name in ["textures", "music", "sfx", "voices"]:
		if typeof(document.get(section_name)) != TYPE_DICTIONARY:
			return _fail("presentation manifest is missing %s" % section_name)
	_manifest = document
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(raw.to_utf8_buffer())
	_manifest_hash = context.finish().hex_encode()
	last_error = ""
	_manifest_ok = true
	return true


func _audio_resource(section_name: String, key: String, cache: Dictionary) -> AudioStream:
	if not _load_manifest():
		return null
	var asset_id := _asset_id(key)
	if cache.has(asset_id):
		return cache[asset_id] as AudioStream
	var resource := _load_typed_resource(section_name, asset_id)
	if resource is AudioStream:
		cache[asset_id] = resource
		return resource as AudioStream
	return null


func _load_typed_resource(section_name: String, asset_id: String) -> Resource:
	var entry := _entry(section_name, asset_id)
	if entry.is_empty():
		last_error = "presentation asset is not declared: %s:%s" % [section_name, asset_id]
		return null
	var path := String(entry.get("path", ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		last_error = "presentation resource is unavailable: %s:%s" % [section_name, asset_id]
		return null
	var resource := ResourceLoader.load(path)
	if resource == null:
		last_error = "presentation resource failed to load: %s:%s" % [section_name, asset_id]
	return resource


func _entry(section_name: String, key: String) -> Dictionary:
	if not _load_manifest():
		return {}
	var entries: Dictionary = _manifest.get(section_name, {})
	var value: Variant = entries.get(_asset_id(key))
	return (value as Dictionary).duplicate(true) if value is Dictionary else {}


func _validate_texture_entries(
	errors: Array[String],
	counts: Dictionary,
	include_optional: bool
) -> void:
	var entries: Dictionary = _manifest.get("textures", {})
	for asset_id_value in entries:
		var asset_id := String(asset_id_value)
		var entry: Dictionary = entries[asset_id]
		if String(entry.get("kind", "texture")) != "texture":
			continue
		if not include_optional and not bool(entry.get("required", false)):
			continue
		var texture_resource := texture(asset_id)
		if texture_resource == null:
			errors.append(last_error)
			continue
		var expected_width := int(entry.get("width", 0))
		var expected_height := int(entry.get("height", 0))
		if texture_resource.get_width() != expected_width or texture_resource.get_height() != expected_height:
			errors.append(
				"presentation texture dimensions differ: %s expected %dx%d got %dx%d"
				% [
					asset_id,
					expected_width,
					expected_height,
					texture_resource.get_width(),
					texture_resource.get_height(),
				]
			)
			continue
		counts["textures"] = int(counts["textures"]) + 1


func _validate_hit_mask_entries(
	errors: Array[String],
	counts: Dictionary,
	include_optional: bool
) -> void:
	var entries: Dictionary = _manifest.get("textures", {})
	for asset_id_value in entries:
		var asset_id := String(asset_id_value)
		var entry: Dictionary = entries[asset_id]
		if String(entry.get("kind", "texture")) != "hit_mask":
			continue
		if not include_optional and not bool(entry.get("required", false)):
			continue
		var path := String(entry.get("path", ""))
		if path.is_empty() or not FileAccess.file_exists(path):
			errors.append("presentation hit mask is unavailable: %s" % asset_id)
			continue
		var file := FileAccess.open(path, FileAccess.READ)
		if file == null:
			errors.append("presentation hit mask cannot be read: %s" % asset_id)
			continue
		var bytes := file.get_buffer(file.get_length())
		file.close()
		var width := int(entry.get("width", 0))
		var height := int(entry.get("height", 0))
		var expected_size := int(entry.get("byte_size", 0))
		if width <= 0 or height <= 0 or expected_size != width * height:
			errors.append("presentation hit-mask metadata is invalid: %s" % asset_id)
			continue
		if bytes.size() != expected_size:
			errors.append(
				"presentation hit-mask byte count differs: %s expected %d got %d"
				% [asset_id, expected_size, bytes.size()]
			)
			continue
		var allowed_values: Array = entry.get("value_domain", [])
		var allowed_domain: Dictionary = {}
		for allowed_value in allowed_values:
			allowed_domain[int(allowed_value)] = true
		var invalid_value := -1
		for value in bytes:
			if not allowed_domain.has(int(value)):
				invalid_value = int(value)
				break
		if invalid_value >= 0:
			errors.append(
				"presentation hit mask contains value %d outside its declared domain: %s"
				% [invalid_value, asset_id]
			)
			continue
		var expected_hash := String(entry.get("source_sha256", ""))
		var actual_hash := FileAccess.get_sha256(path)
		if expected_hash.is_empty() or actual_hash != expected_hash:
			errors.append(
				"presentation hit-mask hash differs: %s expected %s got %s"
				% [asset_id, expected_hash, actual_hash]
			)
			continue
		counts["hit_masks"] = int(counts["hit_masks"]) + 1


func _validate_ending_contract(errors: Array[String], counts: Dictionary) -> void:
	var ending_value: Variant = _manifest.get("ending", {})
	if not ending_value is Dictionary:
		errors.append("presentation manifest is missing the ending contract")
		return
	var ending := ending_value as Dictionary
	var slides_value: Variant = ending.get("slides", [])
	if not slides_value is Array or (slides_value as Array).size() != 13:
		errors.append("presentation ending must declare thirteen ordered slides")
		return
	for slide_value: Variant in slides_value:
		if not slide_value is Dictionary:
			errors.append("presentation ending slide metadata is invalid")
			continue
		var slide := slide_value as Dictionary
		var texture_key := str(slide.get("texture", ""))
		if texture_key.is_empty() or texture(texture_key) == null:
			errors.append("presentation ending slide is unavailable: %s" % texture_key)
			continue
		if float(slide.get("duration_seconds", 0.0)) <= 0.0:
			errors.append("presentation ending slide duration is invalid: %s" % texture_key)
			continue
		counts["ending_slides"] = int(counts["ending_slides"]) + 1
	if str(ending.get("story_text", "")).is_empty() or str(
		ending.get("credits_text", "")
	).is_empty():
		errors.append("presentation ending text is missing")
	if (
		float(ending.get("scroll_pixels_per_second", 0.0)) <= 0.0
		or float(ending.get("accelerated_multiplier", 0.0)) <= 1.0
	):
		errors.append("presentation ending timing is invalid")
	if bool(ending.get("loop", true)):
		errors.append("presentation ending slides must hold on the final image")
	var evidence_value: Variant = ending.get("evidence", {})
	if (
		not evidence_value is Dictionary
		or not bool((evidence_value as Dictionary).get("text_loop", false))
	):
		errors.append("presentation ending text-loop evidence is missing")
	elif (
		int((evidence_value as Dictionary).get("instruction_overlay_duration_ms", 0))
		!= 8000
		or str((evidence_value as Dictionary).get("left_mouse_scope", ""))
		!= "hold_to_pause_text_scroll_only"
		or str((evidence_value as Dictionary).get("right_mouse_scope", ""))
		!= "hold_to_accelerate_text_scroll_only"
		or bool((evidence_value as Dictionary).get("slide_clock_pause_on_left_mouse", true))
		or bool((evidence_value as Dictionary).get("music_pause_on_left_mouse", true))
	):
		errors.append("presentation ending control-scope evidence is invalid")
	var music_key := str(ending.get("music", ""))
	if music_key.is_empty() or music_metadata(music_key).is_empty():
		errors.append("presentation ending music is unavailable")
	var modes_value: Variant = ending.get("modes", {})
	if not modes_value is Dictionary:
		errors.append("presentation ending modes are missing")
	else:
		var modes := modes_value as Dictionary
		for mode_id in ["0", "2"]:
			var mode_value: Variant = modes.get(mode_id, {})
			if not mode_value is Dictionary:
				errors.append("presentation ending mode %s is missing" % mode_id)
				continue
			var mode := mode_value as Dictionary
			for key in [
				"title", "text", "fireworks"
			]:
				if not mode.has(key):
					errors.append(
					"presentation ending mode %s is missing %s" % [mode_id, key]
				)
	var controls_value: Variant = ending.get("controls", {})
	if not controls_value is Dictionary:
		errors.append("presentation ending controls are missing")
	else:
		var controls := controls_value as Dictionary
		for key in ["left_mouse", "right_mouse", "continue"]:
			if str(controls.get(key, "")).is_empty():
				errors.append("presentation ending control %s is missing" % key)


func _validate_audio_entries(
	section_name: String,
	errors: Array[String],
	counts: Dictionary,
	include_optional: bool
) -> void:
	var entries: Dictionary = _manifest.get(section_name, {})
	for asset_id_value in entries:
		var asset_id := String(asset_id_value)
		var entry: Dictionary = entries[asset_id]
		if not include_optional and not bool(entry.get("required", false)):
			continue
		var stream: AudioStream
		match section_name:
			"music":
				stream = music(asset_id)
			"sfx":
				stream = sfx(asset_id)
			"voices":
				stream = voice(asset_id)
			_:
				errors.append("unsupported presentation audio section: %s" % section_name)
				continue
		if stream == null:
			errors.append(last_error)
			continue
		counts[section_name] = int(counts[section_name]) + 1


func _validate_voice_pack_entries(errors: Array[String], counts: Dictionary) -> void:
	var packs_value: Variant = _manifest.get("voice_packs", {})
	if not packs_value is Dictionary:
		return
	var packs := packs_value as Dictionary
	for pack_id_value in packs:
		var pack_id := String(pack_id_value)
		var pack_value: Variant = packs[pack_id]
		if not pack_value is Dictionary:
			errors.append("presentation voice pack metadata is invalid: %s" % pack_id)
			continue
		var clips_value: Variant = (pack_value as Dictionary).get("clips", {})
		if not clips_value is Dictionary:
			continue
		var clips := clips_value as Dictionary
		for clip_key_value in clips:
			var clip_key := String(clip_key_value)
			var stream := voice_pack(int(pack_id), clip_key)
			if stream == null:
				errors.append(last_error)
				continue
			counts["voice_pack_clips"] = int(counts["voice_pack_clips"]) + 1


func _asset_id(key: String) -> String:
	return key.strip_edges().to_lower()


func _fail(message: String) -> bool:
	last_error = message
	return false


static func set_active_pack(name: String) -> bool:
	_active_pack_name = ""
	_active_pack_dir = ""
	_active_pack_textures = {}
	_pack_warned = {}
	var pack_name := name.strip_edges().to_lower()
	if pack_name.is_empty():
		return true
	for root in PACK_ROOTS:
		var dir := root.path_join(pack_name)
		var manifest := _read_pack_manifest(dir)
		if manifest.is_empty():
			continue
		_active_pack_name = pack_name
		_active_pack_dir = dir
		_active_pack_textures = manifest.get("textures", {})
		return true
	push_warning("Sprite pack was not found or is invalid: %s" % pack_name)
	return false


static func active_pack_name() -> String:
	return _active_pack_name


static func available_packs() -> Array[String]:
	var names: Array[String] = []
	for root in PACK_ROOTS:
		var dir := DirAccess.open(root)
		if dir == null:
			continue
		dir.list_dir_begin()
		var entry := dir.get_next()
		while not entry.is_empty():
			if (
				dir.current_is_dir()
				and not entry.begins_with("_")
				and not entry.begins_with(".")
				and FileAccess.file_exists(root.path_join(entry).path_join("pack.json"))
				and not names.has(entry)
			):
				names.append(entry)
			entry = dir.get_next()
		dir.list_dir_end()
	names.sort()
	return names


## Reports every pack entry that cannot override its retail texture. Partial
## coverage is the normal case and is not an error; unknown keys, unreadable
## files, and size mismatches are.
func validate_pack() -> Dictionary:
	var errors: Array[String] = []
	var overridden := 0
	if _active_pack_name.is_empty():
		return {"ok": true, "pack": "", "overridden": 0, "errors": errors}
	if not _load_manifest():
		return {"ok": false, "pack": _active_pack_name, "overridden": 0, "errors": [last_error]}
	for asset_id_value in _active_pack_textures:
		var asset_id := String(asset_id_value)
		var retail_entry := _entry("textures", asset_id)
		if retail_entry.is_empty():
			errors.append("pack key is not a retail texture: %s" % asset_id)
			continue
		if String(retail_entry.get("kind", "texture")) != "texture":
			errors.append("pack key targets a non-texture entry: %s" % asset_id)
			continue
		if _pack_texture(asset_id) == null:
			errors.append("pack entry does not resolve (missing file or wrong size): %s" % asset_id)
			continue
		overridden += 1
	return {
		"ok": errors.is_empty(),
		"pack": _active_pack_name,
		"overridden": overridden,
		"errors": errors,
	}


static func _read_pack_manifest(dir: String) -> Dictionary:
	var path := dir.path_join("pack.json")
	if not FileAccess.file_exists(path):
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		push_warning("Sprite pack manifest is not valid JSON: %s" % path)
		return {}
	var manifest := parsed as Dictionary
	if (
		int(manifest.get("version", 0)) != PACK_VERSION
		or String(manifest.get("schema", "")) != PACK_SCHEMA
		or not manifest.get("textures") is Dictionary
	):
		push_warning("Sprite pack manifest is unsupported: %s" % path)
		return {}
	return manifest


## Pack overrides load from loose PNGs (no import step) and must match the
## retail entry's exact dimensions; anything else warns once and falls back.
func _pack_texture(asset_id: String) -> Texture2D:
	if _active_pack_textures.is_empty() or not _active_pack_textures.has(asset_id):
		return null
	var entry_value: Variant = _active_pack_textures[asset_id]
	if not entry_value is Dictionary:
		return null
	var relative_path := String((entry_value as Dictionary).get("path", ""))
	if relative_path.is_empty() or relative_path.begins_with("/") or relative_path.contains(".."):
		_warn_pack_once(asset_id, "sprite pack path is invalid")
		return null
	var retail_entry := _entry("textures", asset_id)
	if retail_entry.is_empty() or String(retail_entry.get("kind", "texture")) != "texture":
		_warn_pack_once(asset_id, "sprite pack key has no retail texture")
		return null
	var image := Image.new()
	var absolute_path := ProjectSettings.globalize_path(_active_pack_dir.path_join(relative_path))
	if image.load(absolute_path) != OK:
		_warn_pack_once(asset_id, "sprite pack image failed to load")
		return null
	if (
		image.get_width() != int(retail_entry.get("width", 0))
		or image.get_height() != int(retail_entry.get("height", 0))
	):
		_warn_pack_once(asset_id, "sprite pack dimensions differ from retail")
		return null
	return ImageTexture.create_from_image(image)


static func _warn_pack_once(asset_id: String, message: String) -> void:
	if _pack_warned.has(asset_id):
		return
	_pack_warned[asset_id] = true
	push_warning("%s: %s:%s" % [message, _active_pack_name, asset_id])

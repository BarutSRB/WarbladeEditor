class_name WBAudioDirector
extends Node

const MUSIC_BUS := "WarbladeMusic"
const SFX_BUS := "WarbladeSFX"
const VOICE_BUS := "WarbladeVoice"
const MAX_SFX_VOICES := 64
const MAX_PERSISTENT_LOOPS := 16
const MAX_SEEN_EVENTS := 4096
const MUSIC_FADE_SECONDS := 0.18
const MUSIC_SILENCE_DB := -60.0
const FP_ONE := 65536.0
const ARENA_CENTER := Vector2(400.0, 300.0)

const MUSIC_ALIASES := {
	"game": "warblade",
	"ingame": "warblade",
}
const LOOPING_MUSIC := {
	"title": true,
	"warblade": true,
	"shop": true,
	"promoted": true,
	"memory": true,
	"meteor": true,
	"gems": true,
	"boss": true,
	"endgame": true,
	"hiscore": true,
	"timetrial": true,
	"end": true,
}
const GAMEPLAY_MUSIC_INTERRUPTS := {
	"shop": true,
	"memory": true,
	"meteor": true,
	"gems": true,
}
const SFX_ALIASES := {
	"purchase": "chaching",
	"levelcomplete": "fanfare",
	"gameover": "over",
	"ui_click": "buttonclick",
	"ui_hover": "rollover",
}
const SFX_PRESENTATION := {
	"singleshot": {"frequency_hz": 44100.0, "source_hz": 32000.0, "volume_linear": 1.0},
	"alienshoot2": {"frequency_hz": 25000.0, "source_hz": 32000.0, "volume_linear": 180.0 / 255.0},
	"alienshoot16": {"frequency_hz": 22000.0, "source_hz": 32000.0, "volume_linear": 220.0 / 255.0},
	"alienshoot12_2": {"frequency_hz": 32000.0, "source_hz": 32000.0, "volume_linear": 150.0 / 255.0},
	"alienshoot3": {"frequency_hz": 32000.0, "source_hz": 32000.0, "volume_linear": 128.0 / 255.0},
	"alienshoot9": {"frequency_hz": 17500.0, "source_hz": 32000.0, "volume_linear": 128.0 / 255.0},
	"alienshoot17": {"frequency_hz": 28000.0, "source_hz": 32000.0, "volume_linear": 128.0 / 255.0},
	"laser2": {"frequency_hz": 24000.0, "source_hz": 32000.0, "volume_linear": 120.0 / 255.0},
	"alienshoot15": {"frequency_hz": 44100.0, "source_hz": 32000.0, "volume_linear": 1.0},
	"alienshoot4": {"frequency_hz": 20000.0, "source_hz": 32000.0, "volume_linear": 200.0 / 255.0},
	# The extracted jingles MP3 is 44.1 kHz; Gem Drop supplies its exact
	# per-catch retail playback frequency in each authoritative event.
	"jingles": {"frequency_hz": 44100.0, "source_hz": 44100.0, "volume_linear": 1.0},
}
const PER_SAMPLE_MAX_VOICES := {
	"bell1": 6,
	"bell2": 6,
	"bell3": 20,
	"bigfire": 5,
	"bigsmall": 6,
	"scopehum": 1,
	"shieldhum": 1,
	"mother": 3,
	"guard": 1,
	"boss": 1,
	"mshiphum": 4,
}

var _assets := WBAssetLibrary.new()
var _jukebox := WBJukeboxStore.new()
var _voice_pack := 1
var _playlist_entries: Array = []
var _playlist_index := 0
var _playlist_active := false
var _music := AudioStreamPlayer.new()
var _speech := AudioStreamPlayer.new()
var _voices: Array[AudioStreamPlayer2D] = []
var _voice_state: Array[Dictionary] = []
var _voice_queue: Array[Dictionary] = []
var _active_voice_request: Dictionary = {}
var _voice_padding_timer: SceneTreeTimer
var _voice_queue_generation := 0
var _persistent_loops: Dictionary = {}
var _settings: Dictionary = {}
var _silent := false
var _current_music_key := ""
var _requested_music_key := ""
var _game_music_position := 0.0
var _game_music_position_saved := false
var _music_generation := 0
var _music_tween: Tween
var _voice_serial := 0
var _seen_event_ids: Dictionary = {}
var _seen_event_order: Array[String] = []


func _ready() -> void:
	_silent = DisplayServer.get_name() == "headless"
	_ensure_bus(MUSIC_BUS)
	_ensure_bus(SFX_BUS)
	_ensure_bus(VOICE_BUS)
	_music.name = "Music"
	_music.bus = MUSIC_BUS
	_music.finished.connect(_on_music_finished)
	add_child(_music)
	_speech.name = "Voice"
	_speech.bus = VOICE_BUS
	_speech.finished.connect(_on_voice_finished)
	add_child(_speech)
	for index in range(MAX_SFX_VOICES):
		var player := _make_sfx_player("Sfx%d" % index)
		add_child(player)
		_voices.append(player)
		_voice_state.append({"key": "", "priority": -1, "serial": -1})
	_apply_settings()


func configure(settings: Dictionary) -> void:
	_settings = settings.duplicate(true)
	_voice_pack = 2 if int(_settings.get("voice_pack", 1)) == 2 else 1
	_jukebox.configure(_settings.get("jukebox", {}))
	_apply_settings()


func play_music(key: String) -> void:
	if _silent or DisplayServer.get_name() == "headless":
		return
	var canonical := _canonical_music_key(key)
	if canonical.is_empty() or canonical == _requested_music_key:
		return
	# Jukebox overrides swap the stream only; the canonical slot key keeps
	# owning interrupt/resume semantics and the loop policy.
	var playlist: Array = []
	var stream: AudioStream = null
	var override := _jukebox.override_for_music_key(canonical)
	match str(override.get("kind", "")):
		"playlist":
			var entries: Array = override.get("entries", [])
			var start := _playlist_entry_stream(entries, 0)
			if start.get("stream") != null:
				playlist = entries
				stream = start["stream"] as AudioStream
		"builtin":
			stream = _load_music(str(override.get("key", "")))
		"user":
			stream = WBJukeboxStore.load_user_stream(str(override.get("path", "")))
	if stream == null:
		playlist = []
		stream = _load_music(canonical)
	if stream == null:
		return
	if canonical == _current_music_key and _music.playing:
		_music_generation += 1
		_cancel_music_tween()
		_requested_music_key = canonical
		return
	var previous_key := _current_music_key
	if (
		previous_key == "warblade"
		and GAMEPLAY_MUSIC_INTERRUPTS.has(canonical)
		and _music.playing
	):
		_game_music_position = _music.get_playback_position()
		_game_music_position_saved = true
	elif canonical == "title":
		_game_music_position = 0.0
		_game_music_position_saved = false
	elif canonical == "warblade" and not GAMEPLAY_MUSIC_INTERRUPTS.has(previous_key):
		_game_music_position = 0.0
		_game_music_position_saved = false
	var resume_position := (
		_game_music_position
		if (
			canonical == "warblade"
			and GAMEPLAY_MUSIC_INTERRUPTS.has(previous_key)
			and _game_music_position_saved
		)
		else 0.0
	)
	_requested_music_key = canonical
	_music_generation += 1
	var generation := _music_generation
	_cancel_music_tween()
	if _music.playing:
		_music_tween = create_tween()
		_music_tween.tween_property(_music, "volume_db", MUSIC_SILENCE_DB, MUSIC_FADE_SECONDS)
		_music_tween.tween_callback(
			func() -> void: _commit_music_switch(generation, canonical, stream, resume_position, playlist)
		)
	else:
		_commit_music_switch(generation, canonical, stream, resume_position, playlist)


func stop_music() -> void:
	_music_generation += 1
	_cancel_music_tween()
	_music.stop()
	_music.stream = null
	_music.volume_db = 0.0
	_current_music_key = ""
	_requested_music_key = ""


func play_request(request: Dictionary) -> bool:
	if request.is_empty() or _silent:
		return false
	var event_id := str(request.get("event_id", ""))
	if not event_id.is_empty() and not _remember_event(event_id):
		return false
	if str(request.get("category", "sfx")).to_lower() == "voice":
		return _enqueue_voice_request(request)
	var delay_ms := maxi(0, int(request.get("delay_ms", 0)))
	if delay_ms > 0:
		var delayed_request := request.duplicate(true)
		delayed_request.erase("delay_ms")
		get_tree().create_timer(float(delay_ms) / 1000.0).timeout.connect(
			func() -> void: _play_request_now(delayed_request)
		)
		return true
	return _play_request_now(request)


func _play_request_now(request: Dictionary) -> bool:
	var category := str(request.get("category", "sfx")).to_lower()
	if category == "music":
		play_music(str(request.get("key", "")))
		return true
	if category == "voice":
		return _enqueue_voice_request(request)
	var action := str(request.get("action", "play"))
	if action == "start_loop":
		var default_handle := str(request.get("event_id", ""))
		return start_loop(
			str(request.get("handle", default_handle)),
			str(request.get("key", "")),
			request
		)
	if action == "stop_loop":
		return stop_loop(str(request.get("handle", "")))
	if action == "update_loop":
		return update_loop(str(request.get("handle", "")), request)
	return play_sfx(str(request.get("key", "")), request)


func _enqueue_voice_request(request: Dictionary) -> bool:
	if (
		bool(request.get("drop_if_voice_busy", false))
		and (
			not _active_voice_request.is_empty()
			or not _voice_queue.is_empty()
			or _voice_padding_timer != null
		)
	):
		return false
	var canonical := _canonical_voice_key(str(request.get("key", "")))
	if canonical.is_empty():
		return false
	var stream := _load_voice(canonical)
	if stream == null:
		return false
	var queued := request.duplicate(true)
	queued["category"] = "voice"
	queued["key"] = canonical
	queued["queue_padding_ms"] = clampi(
		int(request.get("queue_padding_ms", 0)),
		0,
		60000
	)
	queued["_stream"] = stream
	_voice_queue.append(queued)
	_start_next_voice()
	return true


func _start_next_voice() -> void:
	if not _active_voice_request.is_empty() or _voice_padding_timer != null:
		return
	if _voice_queue.is_empty():
		return
	var request: Dictionary = _voice_queue.pop_front()
	var stream := request.get("_stream") as AudioStream
	if stream == null:
		_start_next_voice()
		return
	_active_voice_request = request
	_speech.stop()
	_speech.stream = stream
	if DisplayServer.get_name() != "headless":
		_speech.play()


func _on_voice_finished() -> void:
	if _active_voice_request.is_empty():
		return
	var padding_ms := int(_active_voice_request.get("queue_padding_ms", 0))
	_active_voice_request.clear()
	_speech.stream = null
	if padding_ms <= 0 or get_tree() == null:
		_start_next_voice()
		return
	_voice_queue_generation += 1
	var generation := _voice_queue_generation
	_voice_padding_timer = get_tree().create_timer(float(padding_ms) / 1000.0)
	_voice_padding_timer.timeout.connect(
		func() -> void: _finish_voice_padding(generation)
	)


func _finish_voice_padding(generation: int) -> void:
	if generation != _voice_queue_generation:
		return
	_voice_padding_timer = null
	_start_next_voice()


func _clear_voice_queue() -> void:
	_voice_queue_generation += 1
	_voice_padding_timer = null
	_voice_queue.clear()
	_active_voice_request.clear()
	_speech.stop()
	_speech.stream = null


func play_sfx(key: String, request: Dictionary = {}) -> bool:
	if _silent or DisplayServer.get_name() == "headless":
		return false
	var canonical := _canonical_sfx_key(key)
	var stream := _load_sfx(canonical)
	if canonical.is_empty() or stream == null:
		return false
	var presentation := _presentation_for(canonical, request)
	var priority := int(presentation["priority"])
	var max_voices := int(presentation["max_voices"])
	var voice_index := _select_voice(canonical, max_voices, priority)
	if voice_index < 0:
		return false
	var player := _voices[voice_index]
	player.stop()
	player.stream = stream
	player.position = position_for_event(request)
	player.pitch_scale = float(presentation["pitch_scale"])
	player.volume_db = _linear_to_db_safe(float(presentation["volume_linear"]))
	_voice_serial += 1
	_voice_state[voice_index] = {
		"key": canonical,
		"priority": priority,
		"serial": _voice_serial,
	}
	player.play()
	return true


func start_loop(handle: String, key: String, request: Dictionary = {}) -> bool:
	if _silent or handle.is_empty():
		return false
	var canonical := _canonical_sfx_key(key)
	var stream := _load_sfx(canonical)
	if canonical.is_empty() or stream == null:
		return false
	if _persistent_loops.has(handle):
		var existing: Dictionary = _persistent_loops[handle]
		var existing_player := existing.get("player") as AudioStreamPlayer2D
		if str(existing.get("key", "")) == canonical and existing_player != null:
			return update_loop(handle, request)
		stop_loop(handle)
	if _persistent_loops.size() >= MAX_PERSISTENT_LOOPS:
		return false
	var presentation := _presentation_for(canonical, request)
	var same_sample_loops := 0
	for loop_value in _persistent_loops.values():
		if loop_value is Dictionary and str(loop_value.get("key", "")) == canonical:
			same_sample_loops += 1
	if same_sample_loops >= int(presentation["max_voices"]):
		return false
	var player := _make_sfx_player("Loop_%s" % handle.validate_node_name())
	player.stream = _looped_copy(stream)
	player.position = position_for_event(request)
	player.pitch_scale = float(presentation["pitch_scale"])
	player.volume_db = _linear_to_db_safe(float(presentation["volume_linear"]))
	add_child(player)
	_persistent_loops[handle] = {"key": canonical, "player": player}
	player.play()
	return true


func update_loop(handle: String, request: Dictionary = {}) -> bool:
	if not _persistent_loops.has(handle):
		return false
	var state := _persistent_loops[handle] as Dictionary
	var player := state.get("player") as AudioStreamPlayer2D
	if player == null:
		return false
	var tween_value: Variant = state.get("pitch_tween")
	if tween_value is Tween and (tween_value as Tween).is_valid():
		(tween_value as Tween).kill()
	state.erase("pitch_tween")
	player.position = position_for_event(request)
	var presentation := _presentation_for(str(state.get("key", "")), request)
	var target_pitch := float(presentation["pitch_scale"])
	var duration_ms := maxi(0, int(request.get("duration_ms", 0)))
	if duration_ms > 0 and get_tree() != null and DisplayServer.get_name() != "headless":
		var pitch_tween := create_tween()
		pitch_tween.tween_property(
			player,
			"pitch_scale",
			target_pitch,
			float(duration_ms) / 1000.0
		)
		state["pitch_tween"] = pitch_tween
	else:
		player.pitch_scale = target_pitch
	return true


func stop_loop(handle: String) -> bool:
	if not _persistent_loops.has(handle):
		return false
	var state: Dictionary = _persistent_loops[handle]
	var tween_value: Variant = state.get("pitch_tween")
	if tween_value is Tween and (tween_value as Tween).is_valid():
		(tween_value as Tween).kill()
	var player := state.get("player") as AudioStreamPlayer2D
	if player != null:
		player.stop()
		player.queue_free()
	_persistent_loops.erase(handle)
	return true


static func position_for_event(request: Dictionary) -> Vector2:
	if request.has("legacy_pan_table_index"):
		# Retail passes legacy_pan_attribute_raw unchanged to BASS. Godot has a
		# spatial player instead of that attribute, so the source table index is
		# deliberately adapted back to its 0..799 logical x coordinate. The raw
		# attribute remains in the request for diagnostics/replay evidence.
		var legacy_x := clampf(
			float(request.get("legacy_pan_table_index", 400)),
			0.0,
			799.0
		)
		return Vector2(legacy_x, ARENA_CENTER.y)
	if not request.has("x_fp"):
		return ARENA_CENTER
	var x := clampf(float(request.get("x_fp", 400.0 * FP_ONE)) / FP_ONE, 0.0, 800.0)
	var y := clampf(float(request.get("y_fp", 300.0 * FP_ONE)) / FP_ONE, 0.0, 600.0)
	return Vector2(x, y)


func _commit_music_switch(
	generation: int,
	key: String,
	stream: AudioStream,
	resume_position: float,
	playlist: Array = []
) -> void:
	if generation != _music_generation or key != _requested_music_key:
		return
	_playlist_entries = playlist
	_playlist_index = 0
	_playlist_active = not playlist.is_empty()
	_music.stop()
	var loop_stream := bool(LOOPING_MUSIC.get(key, false)) and not _playlist_active
	_music.stream = _looped_copy(stream) if loop_stream else stream
	_music.volume_db = MUSIC_SILENCE_DB
	var start_position := resume_position
	var length := _music.stream.get_length()
	if length > 0.0:
		start_position = fmod(maxf(0.0, start_position), length)
	_music.play(start_position)
	_current_music_key = key
	_music_tween = create_tween()
	_music_tween.tween_property(_music, "volume_db", 0.0, MUSIC_FADE_SECONDS)


func _on_music_finished() -> void:
	if not _playlist_active or _playlist_entries.is_empty():
		return
	if _current_music_key != _requested_music_key:
		return
	var next := _playlist_entry_stream(
		_playlist_entries,
		(_playlist_index + 1) % _playlist_entries.size()
	)
	var stream := next.get("stream") as AudioStream
	if stream == null:
		# No playable entry remains: fall back to the looped built-in slot track.
		var fallback := _load_music(_current_music_key)
		if fallback != null:
			_playlist_active = false
			_music.stream = _looped_copy(fallback)
			_music.play()
		return
	_playlist_index = int(next.get("index", 0))
	_music.stream = stream
	_music.play()


## Finds the first playable playlist entry starting at start_index (wrapping),
## returning {"stream": AudioStream|null, "index": int}.
func _playlist_entry_stream(entries: Array, start_index: int) -> Dictionary:
	if entries.is_empty():
		return {"stream": null, "index": 0}
	for offset in range(entries.size()):
		var index := (start_index + offset) % entries.size()
		var entry_value: Variant = entries[index]
		if not entry_value is Dictionary:
			continue
		var entry := entry_value as Dictionary
		var stream: AudioStream = null
		match str(entry.get("source", "")):
			"builtin":
				stream = _load_music(str(entry.get("key", "")))
			"user":
				stream = WBJukeboxStore.load_user_stream(str(entry.get("path", "")))
		if stream != null:
			return {"stream": stream, "index": index}
	return {"stream": null, "index": start_index}


func _cancel_music_tween() -> void:
	if _music_tween != null and _music_tween.is_valid():
		_music_tween.kill()
	_music_tween = null
	_music.volume_db = 0.0


func _select_voice(key: String, max_voices: int, incoming_priority: int) -> int:
	var same_sample: Array[int] = []
	for index in range(_voices.size()):
		if _voices[index].playing and str(_voice_state[index].get("key", "")) == key:
			same_sample.append(index)
	if same_sample.size() >= max_voices:
		return _replacement_voice(same_sample, incoming_priority)
	for index in range(_voices.size()):
		if not _voices[index].playing:
			return index
	var all_indices: Array[int] = []
	for index in range(_voices.size()):
		all_indices.append(index)
	return _replacement_voice(all_indices, incoming_priority)


func _replacement_voice(indices: Array[int], incoming_priority: int) -> int:
	var candidate := -1
	for index in indices:
		if candidate < 0:
			candidate = index
			continue
		var state: Dictionary = _voice_state[index]
		var current: Dictionary = _voice_state[candidate]
		var priority := int(state.get("priority", -1))
		var current_priority := int(current.get("priority", -1))
		if (
			priority < current_priority
			or (
				priority == current_priority
				and int(state.get("serial", -1)) < int(current.get("serial", -1))
			)
		):
			candidate = index
	if candidate < 0 or int(_voice_state[candidate].get("priority", -1)) > incoming_priority:
		return -1
	return candidate


func _presentation_for(key: String, request: Dictionary) -> Dictionary:
	var result := {
		"priority": 30,
		"max_voices": _default_max_voices(key),
		"pitch_scale": 1.0,
		"volume_linear": 1.0,
		"source_hz": 0.0,
	}
	var defaults: Dictionary = SFX_PRESENTATION.get(key, {})
	_apply_presentation(result, defaults, request)
	if _assets.has_method("sfx_metadata"):
		var manifest_value: Variant = _assets.call("sfx_metadata", key)
		if manifest_value is Dictionary:
			var manifest: Dictionary = manifest_value
			var tuning_confidence := str(
				manifest.get("tuning_confidence", "unresolved")
			).to_lower()
			if tuning_confidence in ["proven", "supported", "verified"]:
				_apply_presentation(result, manifest, request)
				var manifest_presentation: Variant = manifest.get("presentation", {})
				if manifest_presentation is Dictionary:
					_apply_presentation(result, manifest_presentation, request)
	var supplied: Variant = request.get("presentation", {})
	if supplied is Dictionary:
		_apply_presentation(result, supplied, request)
	_apply_presentation(result, request, request)
	result["priority"] = clampi(int(result["priority"]), 0, 100)
	result["max_voices"] = clampi(int(result["max_voices"]), 1, MAX_SFX_VOICES)
	result["pitch_scale"] = clampf(float(result["pitch_scale"]), 0.25, 4.0)
	result["volume_linear"] = clampf(float(result["volume_linear"]), 0.0, 2.0)
	result.erase("source_hz")
	return result


func _apply_presentation(result: Dictionary, source: Dictionary, request: Dictionary) -> void:
	for property in ["priority", "max_voices"]:
		if source.has(property):
			result[property] = source[property]
	if source.has("volume_index"):
		# Retail passes a 0..255 table index to its SFX wrapper. At maximum
		# SFX volume that table resolves exactly to index / 255; the Remake's
		# SFX bus applies the user's volume setting independently.
		result["volume_linear"] = clampi(int(source["volume_index"]), 0, 255) / 255.0
	elif source.has("volume_linear"):
		result["volume_linear"] = source["volume_linear"]
	elif source.has("volume"):
		result["volume_linear"] = source["volume"]
	if source.has("source_hz"):
		result["source_hz"] = maxf(1.0, float(source["source_hz"]))
	if source.has("frequency_hz") and float(result.get("source_hz", 0.0)) > 0.0:
		result["pitch_scale"] = (
			float(source["frequency_hz"])
			/ float(result["source_hz"])
		)
	elif source.has("pitch_scale"):
		result["pitch_scale"] = source["pitch_scale"]
	if source.has("pitch_min") or source.has("pitch_max"):
		var minimum := float(source.get("pitch_min", result["pitch_scale"]))
		var maximum := float(source.get("pitch_max", result["pitch_scale"]))
		if maximum < minimum:
			var swap := minimum
			minimum = maximum
			maximum = swap
		var event_hash := str(request.get("event_id", request.get("tick", "0"))).hash()
		var unit := float(posmod(event_hash, 10001)) / 10000.0
		result["pitch_scale"] = lerpf(minimum, maximum, unit)


func _default_max_voices(key: String) -> int:
	if key.begins_with("alienshoot"):
		return 15
	return int(PER_SAMPLE_MAX_VOICES.get(key, 8))


func _make_sfx_player(player_name: String) -> AudioStreamPlayer2D:
	var player := AudioStreamPlayer2D.new()
	player.name = player_name
	player.bus = SFX_BUS
	player.attenuation = 0.0
	player.max_distance = 10000.0
	player.panning_strength = 1.0
	return player


func _looped_copy(stream: AudioStream) -> AudioStream:
	var copy := stream.duplicate() as AudioStream
	if copy == null:
		copy = stream
	if copy is AudioStreamMP3:
		(copy as AudioStreamMP3).loop = true
	elif copy is AudioStreamOggVorbis:
		(copy as AudioStreamOggVorbis).loop = true
	return copy


func _load_music(key: String) -> AudioStream:
	if _assets.has_method("music"):
		return _assets.call("music", key) as AudioStream
	return _assets.audio(key)


func _load_sfx(key: String) -> AudioStream:
	if _assets.has_method("sfx"):
		return _assets.call("sfx", key) as AudioStream
	return _assets.audio(key)


func _load_voice(key: String) -> AudioStream:
	# Retail plays whichever numbered pack is selected and simply misses cues
	# the pack lacks; the remake keeps the selected pack authoritative but
	# falls back per clip to the complete pack 1 (documented modernization).
	if _voice_pack > 1 and _assets.has_method("voice_pack"):
		var pack_stream := _assets.call("voice_pack", _voice_pack, key) as AudioStream
		if pack_stream != null:
			return pack_stream
	if _assets.has_method("voice"):
		return _assets.call("voice", key) as AudioStream
	return _assets.audio(key)


func _canonical_music_key(key: String) -> String:
	var normalized := key.strip_edges().to_lower()
	return str(MUSIC_ALIASES.get(normalized, normalized))


func _canonical_sfx_key(key: String) -> String:
	var normalized := key.strip_edges().to_lower()
	return str(SFX_ALIASES.get(normalized, normalized))


func _canonical_voice_key(key: String) -> String:
	return key.strip_edges().to_lower().replace("_", "").replace("-", "").replace(" ", "")


func _remember_event(event_id: String) -> bool:
	if _seen_event_ids.has(event_id):
		return false
	_seen_event_ids[event_id] = true
	_seen_event_order.append(event_id)
	while _seen_event_order.size() > MAX_SEEN_EVENTS:
		_seen_event_ids.erase(_seen_event_order.pop_front())
	return true


func _apply_settings() -> void:
	var music_volume := clampf(float(_settings.get("music_volume", 0.75)), 0.0, 1.0)
	var sfx_volume := clampf(float(_settings.get("sfx_volume", 0.9)), 0.0, 1.0)
	var voice_volume := clampf(float(_settings.get("voice_volume", sfx_volume)), 0.0, 1.0)
	var music_bus := AudioServer.get_bus_index(MUSIC_BUS)
	if music_bus >= 0:
		AudioServer.set_bus_mute(music_bus, music_volume <= 0.0)
		AudioServer.set_bus_volume_db(music_bus, _linear_to_db_safe(music_volume))
	var sfx_bus := AudioServer.get_bus_index(SFX_BUS)
	if sfx_bus >= 0:
		AudioServer.set_bus_mute(sfx_bus, sfx_volume <= 0.0)
		AudioServer.set_bus_volume_db(sfx_bus, _linear_to_db_safe(sfx_volume))
	var voice_bus := AudioServer.get_bus_index(VOICE_BUS)
	if voice_bus >= 0:
		AudioServer.set_bus_mute(voice_bus, voice_volume <= 0.0)
		AudioServer.set_bus_volume_db(voice_bus, _linear_to_db_safe(voice_volume))


func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) >= 0:
		return
	AudioServer.add_bus()
	var index := AudioServer.bus_count - 1
	AudioServer.set_bus_name(index, bus_name)
	AudioServer.set_bus_send(index, "Master")


func _linear_to_db_safe(value: float) -> float:
	return linear_to_db(maxf(value, 0.0001))


func _exit_tree() -> void:
	stop_music()
	_clear_voice_queue()
	for player in _voices:
		player.stop()
		player.stream = null
	for handle in _persistent_loops.keys().duplicate():
		stop_loop(str(handle))
	_seen_event_ids.clear()
	_seen_event_order.clear()
	_assets.clear()

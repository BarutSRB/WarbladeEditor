extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_test_weapon_sound_content()
	_test_event_position()
	_test_event_mapping_and_deduplication()
	_test_bonus_mode_music_cues()
	_test_boss_music_cue()
	_test_boss_hum_loop_requests()
	_test_rank_promotion_audio()
	_test_ending_audio()
	_test_voice_asset_manifest()
	_test_voice_pack_selection()
	_test_jukebox_music_resolution()
	await _test_audio_topology()
	if _failures.is_empty():
		print("AUDIO TESTS PASSED")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("AUDIO TESTS FAILED: %d" % _failures.size())
	quit(1)


func _test_weapon_sound_content() -> void:
	var sounds := WBClientSession.load_weapon_sounds("res://content/weapons.json")
	_expect_equal(sounds.size(), 9, "all playable weapon sounds come from content")
	_expect_equal(str(sounds.get(0, "")), "singleshot", "single shot uses recovered sample")
	_expect_equal(str(sounds.get(8, "")), "laser2", "War.I.Plasma uses recovered sample")


func _test_event_position() -> void:
	_expect_equal(
		WBAudioDirector.position_for_event({}),
		Vector2(400.0, 300.0),
		"events without coordinates remain centered"
	)
	_expect_equal(
		WBAudioDirector.position_for_event({"x_fp": 64 * 65536, "y_fp": 120 * 65536}),
		Vector2(64.0, 120.0),
		"authoritative fixed-point coordinates drive positional playback"
	)


func _test_event_mapping_and_deduplication() -> void:
	var session := WBClientSession.new()
	var requests: Array[Dictionary] = []
	session.audio_requested.connect(func(request: Dictionary) -> void: requests.append(request))
	var previous := {"tick": 9, "phase": "level"}
	var current := {
		"tick": 10,
		"phase": "level",
		"level_id": 5,
		"events": [
			{"event_id": 101, "kind": "weapon_fired", "weapon_id": 8, "x_fp": 100 * 65536},
			{
				"event_id": 102,
				"kind": "enemy_fired",
				"entity_id": 7,
				"enemy_projectile_type": 7,
				"x_fp": 700 * 65536,
			},
			{"event_id": 103, "kind": "pickup_collected", "pickup_kind": "money"},
			{"event_id": 104, "kind": "player_destroyed", "seat_id": 0},
			{
				"event_id": 105,
				"kind": "warp_malfunction_started",
				"sfx_key": "alienshoot15",
				"frequency_hz": 12345,
				"source_hz": 32000,
			},
			{"event_id": 106, "kind": "warp_malfunction_message_cue", "sfx_key": "warpmalfunction"},
			{
				"event_id": 107,
				"kind": "sound_cue",
				"key": "meteorpass",
				"frequency_hz": 15000,
				"source_hz": 32000,
				"volume_index": 87,
				"x_fp": 512 * 65536,
			},
		],
	}
	session._emit_audio_events(previous, current)
	session._emit_audio_events(previous, current)
	_expect_equal(requests.size(), 7, "replayed snapshot events emit audio only once")
	if requests.size() == 7:
		_expect_equal(str(requests[0].get("key", "")), "laser2", "weapon event uses content mapping")
		_expect_equal(str(requests[1].get("key", "")), "alienshoot10", "ordinary enemy shots use the recovered type-7 sample")
		_expect_equal(str(requests[2].get("key", "")), "coin", "money pickup uses coin sample")
		_expect_equal(str(requests[3].get("key", "")), "explo3", "player destruction uses large explosion")
		_expect_equal(str(requests[4].get("key", "")), "alienshoot15", "mode-16 entry uses the original pitched alien sample")
		_expect_equal(int(requests[4].get("frequency_hz", 0)), 12345, "mode-16 entry preserves its random playback frequency")
		_expect_equal(int(requests[4].get("source_hz", 0)), 32000, "mode-16 entry preserves the sample source frequency")
		_expect_equal(str(requests[5].get("key", "")), "warpmalfunction", "the delayed mode-16 cue uses the original voice sample")
		_expect_equal(str(requests[5].get("category", "")), "voice", "spoken malfunction cues use the voice queue")
		_expect_equal(int(requests[1].get("x_fp", 0)), 700 * 65536, "enemy pan coordinate survives dispatch")
		_expect_equal(str(requests[6].get("key", "")), "meteorpass", "Meteor threshold crossing uses the traced flyby sample")
		_expect_equal(int(requests[6].get("frequency_hz", 0)), 15000, "Meteor flyby retains its traced playback frequency")
		_expect_equal(int(requests[6].get("volume_index", -1)), 87, "Meteor flyby retains its per-slot retail volume-table index")
		_expect_equal(int(requests[6].get("x_fp", 0)), 512 * 65536, "Meteor flyby remains spatialized from its authoritative x coordinate")
	_expect_equal(
		session._enemy_shot_sound({"enemy_projectile_type": 6}, current),
		"alienshoot2",
		"state-6 projectile events fall back to their recovered type-6 sample"
	)
	_expect_equal(
		session._enemy_shot_sound({"enemy_projectile_type": 7}, current),
		"alienshoot10",
		"ordinary projectile events fall back to their recovered type-7 sample"
	)
	_expect_equal(
		session._enemy_shot_sound(
			{"enemy_projectile_type": 6, "sfx_key": "alienshoot15"}, current
		),
		"alienshoot15",
		"authoritative event sound keys override projectile-type fallback"
	)
	session.free()


func _test_rank_promotion_audio() -> void:
	_expect_equal(
		WBAppShell.gameplay_music_key("music_promoted"),
		"promoted",
		"app shell routes the promotion phase cue to the promoted music asset"
	)
	var session := WBClientSession.new()
	var requests: Array[Dictionary] = []
	var sounds: Array[String] = []
	session.audio_requested.connect(func(request: Dictionary) -> void: requests.append(request))
	session.sound_requested.connect(func(key: String) -> void: sounds.append(key))
	var promotion := {
		"tick": 20,
		"phase": "rank_promotion",
		"events": [
			{"event_id": 201, "kind": "rank_promotion_firework"},
			{
				"event_id": 202,
				"kind": "rank_promotion_firework",
				"sfx_key": "explo4",
			},
			{
				"event_id": 203,
				"kind": "rank_promotion_voice",
				"voice_key": "congratulations",
				"queue_padding_ms": 100,
			},
			{
				"event_id": 204,
				"kind": "rank_promotion_voice",
				"voice_key": "lieutenant",
				"queue_padding_ms": 50,
			},
			{
				"event_id": 205,
				"kind": "rank_promotion_voice",
				"voice_key": "rank",
				"queue_padding_ms": 50,
			},
		],
	}
	session._emit_audio_events({"tick": 19, "phase": "shop"}, promotion)
	session._emit_audio_events(promotion, {"tick": 21, "phase": "get_ready", "events": []})
	_expect_equal(requests.size(), 6, "promotion fireworks, queued rank phrase, and getready voice emit one request per event")
	if requests.size() >= 5:
		_expect_equal(str(requests[0].get("key", "")), "explo3", "promotion firework defaults to explo3")
		_expect_equal(int(requests[0].get("priority", 0)), 35, "promotion firework uses retail effect priority")
		_expect_equal(int(requests[0].get("max_voices", 0)), 8, "promotion fireworks retain eight voices")
		_expect_equal(str(requests[1].get("key", "")), "explo4", "explicit promotion firework sample is authoritative")
		_expect_equal(str(requests[2].get("key", "")), "congratulations", "promotion phrase starts with congratulations")
		_expect_equal(str(requests[2].get("category", "")), "voice", "promotion speech is routed as voice audio")
		_expect_equal(int(requests[2].get("queue_padding_ms", 0)), 100, "congratulations owns the retail 100-ms following gap")
		_expect_equal(str(requests[3].get("key", "")), "lieutenant", "first promotion queues lieutenant")
		_expect(not requests[3].has("delay_ms"), "promotion speech uses completion-relative padding, not absolute delay guesses")
		_expect_equal(int(requests[3].get("queue_padding_ms", 0)), 50, "lieutenant owns the retail 50-ms following gap")
		_expect_equal(str(requests[4].get("key", "")), "rank", "first promotion queues rank")
		_expect(not requests[4].has("delay_ms"), "rank stays in the same completion-driven speech queue")
		_expect_equal(int(requests[4].get("queue_padding_ms", 0)), 50, "rank retains its declared trailing padding")
	_expect_equal(
		sounds,
		["music_promoted", "music_warblade"],
		"promotion phase starts promoted music and Get Ready restores gameplay music"
	)
	session.free()


func _test_ending_audio() -> void:
	_expect_equal(
		WBAppShell.gameplay_music_key("music_endgame"),
		"endgame",
		"app shell routes credits to the recovered endgame track"
	)
	_expect(
		bool(WBAudioDirector.LOOPING_MUSIC.get("endgame", false)),
		"endgame music loops while the client-local credits await continue"
	)
	var assets := WBAssetLibrary.new()
	var metadata := assets.music_metadata("endgame")
	_expect(not metadata.is_empty(), "the ending music is declared in presentation content")
	_expect(bool(metadata.get("loop", false)), "the recovered ending music is marked looping")
	assets.clear()


func _test_bonus_mode_music_cues() -> void:
	var session := WBClientSession.new()
	var requests: Array[Dictionary] = []
	var sounds: Array[String] = []
	session.audio_requested.connect(func(request: Dictionary) -> void: requests.append(request))
	session.sound_requested.connect(func(key: String) -> void: sounds.append(key))
	var entered := {
		"tick": 30,
		"phase": "bonus_mode",
		"bonus_mode": {"kind": "meteor_storm"},
		"events": [{
			"event_id": 301,
			"kind": "music_cue",
			"key": "meteor",
			"action": "play",
		}],
	}
	session._emit_audio_events({"tick": 29, "phase": "level"}, entered)
	_expect_equal(requests.size(), 1, "authoritative Meteor entry music is dispatched once")
	if requests.size() == 1:
		_expect_equal(str(requests[0].get("category", "")), "music", "Meteor play cue uses the music channel")
		_expect_equal(str(requests[0].get("action", "")), "play", "Meteor entry starts its recovered music")
	_expect_equal(sounds, ["music_meteor"], "phase entry still owns one idempotent Meteor music transition")
	var gem_drop := {
		"tick": 31,
		"phase": "bonus_mode",
		"bonus_mode": {"kind": "gem_drop"},
		"events": [
			{
				"event_id": 302,
				"kind": "music_cue",
				"key": "gems",
				"action": "play",
			},
			{
				"event_id": 303,
				"kind": "sound_cue",
				"key": "jingles",
				"frequency_hz": 37500,
				"volume_index": 255,
				"legacy_pan_attribute_raw": 101.6812515258789,
				"legacy_pan_table_index": 319,
			},
			{
				"event_id": 304,
				"kind": "voice_cue",
				"key": "bonus",
				"queue_padding_ms": 50,
				"drop_if_voice_busy": true,
			},
		],
	}
	session._emit_audio_events(entered, gem_drop)
	_expect_equal(requests.size(), 4, "Gem Drop dispatches music, jingles, and bonus voice through generic cue events")
	if requests.size() == 4:
		_expect_equal(str(requests[1].get("key", "")), "gems", "Gem Drop starts its dedicated recovered music")
		_expect_equal(str(requests[2].get("key", "")), "jingles", "Gem Drop catch plays the recovered jingles sample")
		_expect_equal(int(requests[2].get("frequency_hz", 0)), 37500, "Gem Drop preserves the authoritative random jingles frequency")
		_expect(
			is_equal_approx(float(requests[2].get("legacy_pan_attribute_raw", 0.0)), 101.6812515258789),
			"Gem Drop retains the raw executable BASS pan attribute as evidence"
		)
		_expect_equal(int(requests[2].get("legacy_pan_table_index", -1)), 319, "Gem Drop retains the raw pan table index for explicit client adaptation")
		_expect_equal(str(requests[3].get("key", "")), "bonus", "Gem Drop catch queues the generic bonus voice")
		_expect(bool(requests[3].get("drop_if_voice_busy", false)), "Gem Drop bonus voice retains retail drop-if-busy behavior")
	_expect_equal(sounds, ["music_meteor"], "Gem Drop's authoritative music event avoids a duplicate phase fallback")
	session.free()


func _test_boss_music_cue() -> void:
	var session := WBClientSession.new()
	var requests: Array[Dictionary] = []
	var sounds: Array[String] = []
	session.audio_requested.connect(func(request: Dictionary) -> void: requests.append(request))
	session.sound_requested.connect(func(key: String) -> void: sounds.append(key))
	var entered := {
		"tick": 2500,
		"phase": "level",
		"level_id": 25,
		"boss": {"active": true},
		"events": [{
			"event_id": 25001,
			"kind": "music_cue",
			"key": "boss",
			"action": "play",
		}],
	}
	session._emit_audio_events(
		{"tick": 2499, "phase": "warp", "level_id": 24, "boss": {"active": false}},
		entered
	)
	session._emit_audio_events(entered, entered)
	_expect_equal(requests.size(), 1, "the authoritative level-25 boss music cue emits once")
	if requests.size() == 1:
		_expect_equal(str(requests[0].get("key", "")), "boss", "the boss cue selects the packaged boss track")
		_expect_equal(str(requests[0].get("category", "")), "music", "the boss cue uses the music channel")
	_expect_equal(
		sounds,
		[],
		"ordinary level entry music must not overwrite an active boss music cue"
	)
	session.free()


func _test_boss_hum_loop_requests() -> void:
	var session := WBClientSession.new()
	var requests: Array[Dictionary] = []
	session.audio_requested.connect(func(request: Dictionary) -> void: requests.append(request))
	var previous := {"tick": 2500, "phase": "level", "level_id": 25, "events": []}
	var current := {
		"tick": 2501,
		"phase": "level",
		"level_id": 25,
		"events": [{
			"event_id": 25011,
			"kind": "audio_loop_started",
			"sound_key": "boss",
			"handle": "boss:state13",
			"frequency_hz": 18000,
		}, {
			"event_id": 25012,
			"kind": "boss_hum_pitch",
			"sound_key": "boss",
			"handle": "boss:state13",
			"frequency_hz": 22000,
			"duration_ms": 160,
		}, {
			"event_id": 25013,
			"kind": "audio_loop_stopped",
			"sound_key": "boss",
			"handle": "boss:state13",
		}],
	}
	session._emit_audio_events(previous, current)
	_expect_equal(requests.size(), 3, "boss hum start, traced pitch slide, and stop all reach the audio director")
	if requests.size() == 3:
		_expect_equal(str(requests[0].get("action", "")), "start_loop", "boss hum starts as a persistent loop")
		_expect_equal(str(requests[1].get("action", "")), "update_loop", "boss hum pitch changes update the existing loop")
		_expect_equal(int(requests[1].get("frequency_hz", 0)), 22000, "boss hum update retains its traced target frequency")
		_expect_equal(int(requests[1].get("duration_ms", 0)), 160, "boss hum update retains its traced slide duration")
		_expect_equal(str(requests[2].get("action", "")), "stop_loop", "boss defeat stops the persistent hum")
	session.free()


func _test_voice_asset_manifest() -> void:
	var assets := WBAssetLibrary.new()
	_expect(assets.configure(), "presentation manifest with voices configures")
	var voices := assets.section("voices")
	_expect_equal(voices.size(), 103, "voice manifest declares all recovered retail voice pack clips")
	_expect(assets.voice("congratulations") is AudioStream, "voice cache loads congratulations from the voice section")
	_expect(assets.voice("four") is AudioStream, "Memory countdown voice four resolves from the restricted pack")
	_expect(assets.voice("ten") is AudioStream, "Memory countdown voice ten resolves from the restricted pack")
	_expect_equal(
		int(assets.voice_metadata("congratulations").get("voice_pack_id", 0)),
		1,
		"voice metadata preserves the recovered rank-0 pack identity"
	)
	var errors: Array[String] = []
	var counts := {"voices": 0}
	assets._validate_audio_entries("voices", errors, counts, false)
	_expect(errors.is_empty(), "required voice manifest entries validate")
	_expect_equal(int(counts.get("voices", 0)), voices.size(), "voice validation counts every required clip")
	assets.clear()


func _test_voice_pack_selection() -> void:
	var assets := WBAssetLibrary.new()
	_expect(assets.configure(), "manifest with voice packs configures")
	var packs := assets.section("voice_packs")
	_expect_equal(packs.size(), 2, "manifest declares both retail voice packs")
	_expect_equal(
		int((packs.get("2", {}) as Dictionary).get("clip_count", 0)),
		36,
		"pack 2 declares the complete retail alternate clip set"
	)
	_expect(assets.voice_pack(2, "gameover") is AudioStreamOggVorbis, "pack-2 gameover loads as ogg")
	_expect(assets.voice_pack(2, "loser") is AudioStreamOggVorbis, "pack-2-only loser clip loads")
	_expect(assets.voice_pack(2, "admiral") == null, "pack 2 lacks admiral and reports it")
	_expect(assets.voice_pack(1, "admiral") is AudioStream, "pack id 1 routes to the rank-0 voices")
	_expect_equal(
		int(assets.voice_pack_clip_metadata(2, "gameover").get("voice_pack_id", 0)),
		2,
		"pack-2 clip metadata keeps its pack identity"
	)
	_expect(
		not bool(assets.voice_pack_clip_metadata(2, "loser").get("pack_1_fallback_available", true)),
		"loser is recorded as pack-2-only"
	)
	assets.clear()

	var director := WBAudioDirector.new()
	director.configure({"voice_pack": 2})
	_expect(
		director._load_voice("gameover") is AudioStreamOggVorbis,
		"selected pack 2 resolves gameover from the alternate pack"
	)
	_expect(
		director._load_voice("admiral") is AudioStreamMP3,
		"missing pack-2 clips fall back per clip to pack 1"
	)
	director.configure({"voice_pack": 1})
	_expect(
		director._load_voice("gameover") is AudioStreamMP3,
		"pack 1 keeps resolving the rank-0 clip"
	)
	director.configure({"voice_pack": 99})
	_expect(
		director._load_voice("gameover") is AudioStreamMP3,
		"unknown pack ids sanitize back to pack 1"
	)
	director.free()


func _test_jukebox_music_resolution() -> void:
	var director := WBAudioDirector.new()
	for key in ["hiscore", "timetrial", "end"]:
		_expect(
			bool(WBAudioDirector.LOOPING_MUSIC.get(key, false)),
			"%s music is configured to loop" % key
		)
		_expect(director._load_music(key) is AudioStream, "%s music asset resolves" % key)
	director.configure({
		"jukebox": {"slots": {"shop": {"source": "builtin", "key": "boss"}}}
	})
	var override := director._jukebox.override_for_music_key("shop")
	_expect_equal(str(override.get("kind", "")), "builtin", "shop slot override resolves to a builtin swap")
	_expect_equal(str(override.get("key", "")), "boss", "shop slot override targets the boss track")
	_expect(
		director._jukebox.override_for_music_key("title").is_empty(),
		"slots without overrides keep the built-in track"
	)
	director.configure({
		"jukebox": {
			"main_playlist_enabled": true,
			"main_playlist": [
				{"source": "user", "path": "/nonexistent/missing.mp3"},
				{"source": "builtin", "key": "gems"},
			],
		}
	})
	var playlist_override := director._jukebox.override_for_music_key("warblade")
	_expect_equal(
		str(playlist_override.get("kind", "")),
		"playlist",
		"an enabled main playlist overrides the gameplay slot"
	)
	var start := director._playlist_entry_stream(playlist_override.get("entries", []), 0)
	_expect(start.get("stream") is AudioStream, "playlist resolution skips unplayable entries")
	_expect_equal(int(start.get("index", -1)), 1, "the first playable entry is selected")
	var user_stream := WBJukeboxStore.load_user_stream("/nonexistent/missing.mp3")
	_expect(user_stream == null, "missing user files resolve to null for builtin fallback")
	director.free()


func _test_audio_topology() -> void:
	var director := WBAudioDirector.new()
	root.add_child(director)
	await process_frame
	_expect_equal(director._voices.size(), 64, "director preallocates the global non-looping voice ceiling")
	_expect(AudioServer.get_bus_index("WarbladeMusic") >= 0, "music has a dedicated bus")
	_expect(AudioServer.get_bus_index("WarbladeSFX") >= 0, "sound effects have a dedicated bus")
	_expect(AudioServer.get_bus_index("WarbladeVoice") >= 0, "speech has a dedicated voice bus")
	_expect(
		bool(WBAudioDirector.LOOPING_MUSIC.get("promoted", false)),
		"rank-promotion music is configured to loop for the authoritative phase duration"
	)
	_expect(director._load_music("promoted") is AudioStream, "the promoted music asset resolves at runtime")
	_expect(director._load_music("gems") is AudioStream, "the Gem Drop music asset resolves at runtime")
	_expect(director._load_music("boss") is AudioStream, "the level-25 boss music asset resolves at runtime")
	_expect(director._load_sfx("jingles") is AudioStream, "the Gem Drop collection sample resolves at runtime")
	_expect(director._load_voice("bonus") is AudioStream, "the Gem Drop bonus voice resolves at runtime")
	_expect(bool(WBAudioDirector.LOOPING_MUSIC.get("gems", false)), "Gem Drop music loops for the standalone state-18 duration")
	_expect(bool(WBAudioDirector.LOOPING_MUSIC.get("boss", false)), "boss music loops for the authoritative state-13 encounter")
	_expect(bool(WBAudioDirector.GAMEPLAY_MUSIC_INTERRUPTS.get("gems", false)), "Gem Drop preserves the interrupted gameplay music position")
	_expect(director._load_voice("congratulations") is AudioStream, "the promotion congratulations voice resolves at runtime")
	_expect(director._load_voice("lieutenant") is AudioStream, "the first-promotion rank name resolves as a voice")
	_expect(director._load_voice("rank") is AudioStream, "the first-promotion rank suffix resolves as a voice")
	var hum_player := AudioStreamPlayer2D.new()
	director.add_child(hum_player)
	director._persistent_loops["boss:test"] = {"key": "boss", "player": hum_player}
	var hum_request := {"frequency_hz": 22000, "duration_ms": 160}
	var expected_hum_pitch := float(
		director._presentation_for("boss", hum_request).pitch_scale
	)
	_expect(
		director.update_loop("boss:test", hum_request)
		and is_equal_approx(hum_player.pitch_scale, expected_hum_pitch),
		"headless loop updates apply the traced boss-hum target pitch deterministically"
	)
	director.stop_loop("boss:test")
	var single_shot := director._presentation_for("singleshot", {})
	_expect(
		is_equal_approx(float(single_shot.get("pitch_scale", 0.0)), 44100.0 / 32000.0),
		"recovered single-shot playback frequency is preserved"
	)
	_expect(
		is_equal_approx(
			float(director._presentation_for("alienshoot2", {}).get("volume_linear", 0.0)),
			180.0 / 255.0
		),
		"provisional manifest tuning cannot replace recovered alien-shot volume"
	)
	var manifest_volume := {"volume_linear": 1.0}
	director._apply_presentation(manifest_volume, {"volume": 0.25}, {})
	_expect(
		is_equal_approx(float(manifest_volume.get("volume_linear", 0.0)), 0.25),
		"normalized manifest volume maps to runtime linear volume"
	)
	var indexed_volume := {"volume_linear": 1.0}
	director._apply_presentation(indexed_volume, {"volume_index": 87}, {})
	_expect(
		is_equal_approx(float(indexed_volume.get("volume_linear", 0.0)), 87.0 / 255.0),
		"retail SFX volume indices map exactly to index / 255 before bus volume"
	)
	var jingles_presentation := director._presentation_for("jingles", {"frequency_hz": 37500})
	_expect(
		is_equal_approx(float(jingles_presentation.get("pitch_scale", 0.0)), 37500.0 / 44100.0),
		"Gem Drop's random retail jingles frequency is adapted from the extracted 44.1-kHz sample"
	)
	_expect_equal(
		WBAudioDirector.position_for_event({
			"x_fp": 700 * 65536,
			"legacy_pan_attribute_raw": 101.6812515258789,
			"legacy_pan_table_index": 319,
		}),
		Vector2(319.0, 300.0),
		"Godot spatial playback explicitly adapts the legacy table index while preserving its raw attribute"
	)
	_expect_equal(
		int(director._presentation_for("alienshoot4", {}).get("max_voices", 0)),
		15,
		"alien samples use their recovered simultaneous-voice allowance"
	)
	director._voice_state[0] = {"key": "hit1", "priority": 20, "serial": 2}
	director._voice_state[1] = {"key": "hit1", "priority": 20, "serial": 1}
	_expect_equal(
		director._replacement_voice([0, 1], 20),
		1,
		"equal-priority saturation steals the oldest voice"
	)
	_expect_equal(
		director._replacement_voice([0, 1], 10),
		-1,
		"low-priority audio cannot steal a more important voice"
	)
	var source := load("res://assets/original/music/title.mp3") as AudioStream
	var looped := director._looped_copy(source)
	_expect(looped is AudioStreamMP3 and (looped as AudioStreamMP3).loop, "MP3 contexts receive runtime looping")
	director._silent = false
	var congratulations := {
		"category": "voice",
		"key": "congratulations",
		"event_id": "rank-queue:1",
		"queue_padding_ms": 1,
	}
	_expect(director.play_request(congratulations), "the first voice request starts the single speech queue")
	_expect(not director.play_request(congratulations), "a repeated authoritative voice event is deduplicated")
	_expect(not director.play_request({
		"category": "voice",
		"key": "ten",
		"event_id": "memory-countdown:10",
		"drop_if_voice_busy": true,
	}), "Memory countdown speech uses the retail drop-if-busy queue tag")
	_expect(director.play_request({
		"category": "voice",
		"key": "lieutenant",
		"event_id": "rank-queue:2",
		"delay_ms": 60000,
		"queue_padding_ms": 0,
	}), "the second voice request queues without using its legacy absolute delay")
	_expect(director.play_request({
		"category": "voice",
		"key": "rank",
		"event_id": "rank-queue:3",
		"queue_padding_ms": 0,
	}), "the third voice request joins the same queue")
	_expect_equal(str(director._active_voice_request.get("key", "")), "congratulations", "voice playback starts in event order")
	_expect_equal(director._voice_queue.size(), 2, "later rank clips wait for per-clip completion")
	if director._voice_queue.size() == 2:
		_expect_equal(str(director._voice_queue[0].get("key", "")), "lieutenant", "lieutenant remains second in the exact queue")
		_expect_equal(str(director._voice_queue[1].get("key", "")), "rank", "rank remains third in the exact queue")
	director._speech.stop()
	director._on_voice_finished()
	_expect(director._active_voice_request.is_empty(), "the next clip waits through the completed clip's padding")
	await create_timer(0.02).timeout
	_expect_equal(str(director._active_voice_request.get("key", "")), "lieutenant", "completion plus padding starts the second clip")
	director._speech.stop()
	director._on_voice_finished()
	_expect_equal(str(director._active_voice_request.get("key", "")), "rank", "zero padding advances immediately to the third clip")
	director._speech.stop()
	director._on_voice_finished()
	_expect(director._active_voice_request.is_empty() and director._voice_queue.is_empty(), "the exact rank voice queue drains once")
	director._silent = true
	_expect(not director.play_sfx("singleshot"), "headless audio playback remains silent")
	director.free()
	await process_frame


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		_failures.append("%s (expected %s, got %s)" % [message, expected, actual])

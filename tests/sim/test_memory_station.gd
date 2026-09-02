extends SceneTree

const MemoryStation := preload("res://src/sim/memory_station_simulation.gd")
const Rng := preload("res://src/sim/deterministic_rng.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_retail_seeded_grid_and_geometry()
	_test_retail_atlas_and_effect_contract()
	_test_executable_pinned_effect_dispatch()
	_test_keyboard_match_timing_and_success_growth()
	_test_keyboard_mismatch_timing()
	_test_instant_tile_timing_and_semantic_effects()
	_test_timeout_strict_boundary()
	_test_kill_time_rng_and_throttle()
	_test_countdown_voice_contract()
	_test_mouse_keyboard_semantic_parity()
	_test_read_only_action_validation()
	_test_state_for_hash_is_ordered_and_repeatable()
	if _failures.is_empty():
		print("MEMORY STATION TESTS PASSED")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _test_retail_seeded_grid_and_geometry() -> void:
	var rng := Rng.new(1)
	var simulation := MemoryStation.new()
	_expect(simulation.configure(MemoryStation.retail_contract()), simulation.get_last_error())
	var entered: Dictionary = simulation.enter(0, {
		"bonus_time": 20,
		"memory_columns": 4,
		"memory_rows": 4,
	}, rng, 0, 0)
	_expect(bool(entered.get("ok", false)), "retail Memory Station entry should succeed")
	_expect(
		String(entered.events[2].kind) == "voice_cue"
		and String(entered.events[2].key) == "memorystation"
		and int(entered.events[2].queue_padding_ms) == 50,
		"Memory entry should queue its rank-0 announcement with the recovered 50-ms padding"
	)
	var state: Dictionary = simulation.snapshot()
	var actual_types: Array[int] = []
	for tile_value in state.tiles:
		var tile: Dictionary = tile_value
		actual_types.append(int(tile.type))
	_expect(
		actual_types == [23, 3, 9, 18, 31, 5, 9, 17, 2, 2, 2, 2, 8, 27, 29, 8],
		"seed 1 should reproduce the retail placement stream; got %s" % [actual_types]
	)
	_expect(rng.draw_count == 41253, "retail grid entry should consume exactly 41,253 raw draws")
	_expect(
		rng.snapshot() == {
			"x": 2213971731,
			"y": 2529148008,
			"z": 4158084025,
			"w": 2186537312,
			"c": 1978750326,
			"draw_count": 41253,
		},
		"retail grid generation should leave the shared RNG at the pinned five-word state"
	)
	_expect(
		int(state.surface_width) == 800 and int(state.surface_height) == 600,
		"Memory Station coordinates should use the retail 800x600 surface"
	)
	_expect(
		int(state.tile_size) == 64
		and int(state.grid_origin_x) == 272
		and int(state.grid_origin_y) == 172,
		"a 4x4 retail grid should be centered at logical (272,172)"
	)
	var first: Dictionary = state.tiles[0]
	var next_column: Dictionary = state.tiles[4]
	_expect(
		int(first.tile_index) == 0
		and int(first.x) == 272
		and int(first.y) == 172
		and int(next_column.tile_index) == 8
		and int(next_column.x) == 336,
		"tiles should be returned column-major with fixed eight-row protocol indices"
	)
	var evidence: Dictionary = MemoryStation.retail_contract().evidence
	_expect(
		String(evidence.executable_sha256)
		== "ddf1778c307af1087ff9dcb512786111e665d972298aeaac3f1b4b2996d079ef",
		"the retail contract should pin its executable evidence"
	)


func _test_retail_atlas_and_effect_contract() -> void:
	var contract: Dictionary = MemoryStation.retail_contract()
	var atlas: Dictionary = contract.atlas
	_expect(
		int(atlas.width) == 256
		and int(atlas.height) == 640
		and String(atlas.source_sha256)
		== "0222a6a6885ef96cf4aa9b534d8505d31d4f8e062c91cdff407dfdc8086dc2cf",
		"Memory Station should pin the exact 256x640 retail atlas"
	)
	var effects: Dictionary = contract.tile_effects
	_expect(effects.size() == 39, "the normalized dispatcher should cover tile IDs 0 through 38")
	var expected_keys := {
		0: "no_effect", 1: "deadline_delta_applied", 2: "timed_score_multiplier",
		3: "timed_score_multiplier", 4: "score_applied", 5: "score_applied",
		6: "score_applied", 7: "money_doubler", 8: "money_or_score",
		9: "money_or_score", 10: "money_or_score", 11: "deadline_delta_applied",
		12: "life_armour_or_score", 13: "rank_marker_or_score",
		14: "rank_marker_or_score", 15: "rank_marker_or_score",
		16: "rank_marker_or_score", 17: "rank_marker_or_score",
		18: "rank_marker_or_score", 19: "bullet_capacity_or_score",
		20: "no_effect", 21: "no_effect", 22: "no_effect", 23: "no_effect",
		24: "gem_drop_progress_or_score", 25: "gem_drop_progress_or_score",
		26: "gem_drop_progress_or_score", 27: "gem_drop_progress_or_score",
		28: "gem_drop_progress_or_score", 29: "gem_drop_progress_or_score",
		30: "gem_drop_progress_or_score", 31: "extra_letter_or_score",
		32: "extra_letter_or_score", 33: "extra_letter_or_score",
		34: "extra_letter_or_score", 35: "extra_letter_or_score",
		36: "extra_speed_or_score", 37: "bonus_time_or_score",
		38: "money_cap_star",
	}
	for tile_type_value in expected_keys:
		var tile_type := int(tile_type_value)
		_expect(
			String((effects[tile_type] as Dictionary).effect_key)
			== String(expected_keys[tile_type]),
			"tile %d should expose its executable-pinned normalized effect" % tile_type
		)
	# The retail skull tile (skalle art; the manual changelog's "-15 seconds
	# tile") is type 1: its penalty must stay pinned at exactly -15000 ms.
	_expect(
		int((effects[1] as Dictionary).get("delta_ms", 0)) == -15000
		and String((effects[1] as Dictionary).get("case_address", "")) == "0x005e23be",
		"the skull tile should keep its exact -15 second retail penalty"
	)

	var fixture := _fixture(2)
	var simulation = fixture.simulation
	_set_tile_type(simulation, 0, 0, 38)
	var face_down: Dictionary = simulation.snapshot().tiles[0]
	_expect(
		face_down.source_rect == {"x": 0, "y": 0, "width": 64, "height": 64}
		and face_down.face_up_source_rect == {"x": 128, "y": 576, "width": 64, "height": 64},
		"type 38 should retain its exact atlas cell while face-down uses cell zero"
	)
	simulation._tiles[0]["face_down"] = false
	var face_up: Dictionary = simulation.snapshot().tiles[0]
	_expect(
		face_up.source_rect == {"x": 128, "y": 576, "width": 64, "height": 64},
		"a revealed type-38 tile should draw atlas cell (128,576)"
	)
	var initial_cursor: Dictionary = simulation.snapshot().cursor_highlight
	_expect(
		initial_cursor.source_rect == {"x": 0, "y": 320, "width": 64, "height": 64}
		and initial_cursor.destination_rect == {"x": 272, "y": 172, "width": 64, "height": 64},
		"the cursor should begin at the retail atlas/destination rectangles"
	)
	var animated: Dictionary = simulation.step(1, 1, 0).snapshot.cursor_highlight
	_expect(
		int(animated.animation_frame) == 1
		and int(animated.animation_deadline_ms) == 51,
		"cursor animation should advance at strict 50ms deadlines"
	)


func _test_executable_pinned_effect_dispatch() -> void:
	var fixture := _fixture(3, {
		"money": 99980,
		"money_cap": 99990,
		"bullet_capacity": 50,
		"bonus_time": 45,
		"bonus_time_max": 45,
		"memory_money_stars": 9,
		"memory_star_floor": 22,
		"memory_star_cycle": 1,
	})
	var simulation = fixture.simulation
	var events: Array[Dictionary] = []
	var deltas: Dictionary = {}
	var actions: Array[Dictionary] = []
	var original_deadline := int(simulation.snapshot().mode_deadline_ms)
	simulation._dispatch_tile_effect(1, 1, "effect", events, deltas, actions)
	_expect(
		int(simulation.snapshot().mode_deadline_ms) == original_deadline - 15000
		and String(actions[-1].effect_key) == "deadline_delta_applied",
		"skull should subtract the executable-pinned 15 seconds inside the controller"
	)
	simulation._dispatch_tile_effect(2, 2, "match", events, deltas, actions)
	simulation._dispatch_tile_effect(4, 2, "match", events, deltas, actions)
	_expect(
		int(deltas.get("score_multiplier", 0)) == 1
		and int(deltas.get("score", 0)) == 200
		and int(actions[-2].duration_ms) == 45000,
		"x2 should reset a bonus-time duration and multiply later Memory score tiles"
	)
	simulation._dispatch_tile_effect(8, 2, "match", events, deltas, actions)
	_expect(
		int(deltas.get("money", 0)) == 10
		and int(deltas.get("score", 0)) == 300
		and String(actions[-1].branch) == "cap_and_score",
		"cash overflow should clamp and score only the cash amount, multiplied"
	)
	simulation._dispatch_tile_effect(19, 2, "match", events, deltas, actions)
	_expect(
		int(deltas.get("score", 0)) == 50300
		and String(actions[-1].branch) == "score",
		"a bullet tile at the hard capacity 50 should award 25000 times multiplier"
	)
	simulation._dispatch_tile_effect(37, 2, "match", events, deltas, actions)
	_expect(
		int(deltas.get("score", 0)) == 100300
		and String(actions[-1].branch) == "score",
		"clock at bonus-time maximum should clamp and award 25000 times multiplier"
	)
	simulation._dispatch_tile_effect(38, 1, "effect", events, deltas, actions)
	_expect(
		int(deltas.get("memory_money_stars", 0)) == 1
		and int(deltas.get("money_cap", 0)) == 900000
		and int(actions[-1].money_cap) == 999990,
		"the tenth Memory star should unlock the retail 999990 cash ceiling"
	)

	var gem_fixture := _fixture(4, {
		"gem_progress_origin": 452,
		"gem_progress": 452 + 98 * 8,
		"gem_progress_step": 8,
	})
	var gem_simulation = gem_fixture.simulation
	var gem_deltas: Dictionary = {}
	var gem_actions: Array[Dictionary] = []
	var gem_events: Array[Dictionary] = []
	var gem_draws_before := int(gem_fixture.rng.draw_count)
	gem_simulation._dispatch_tile_effect(
		24, 2, "match", gem_events, gem_deltas, gem_actions
	)
	_expect(
		String(gem_actions[0].branch) == "gem_drop_transition"
		and int(gem_actions[0].transition_ms) == 4000
		and int(gem_deltas.get("gem_progress", 0)) == 16
		and int(gem_deltas.get("score", 0)) == 0,
		"a diamond pair crossing the 100-step boundary should request exact Gem Drop transition"
	)
	_expect(
		int(gem_fixture.rng.draw_count) == gem_draws_before + 1
		and _event_kinds(gem_events) == ["sound_cue", "voice_cue", "memory_tile_effect"]
		and String(gem_events[0].get("key", "")) == "bell1"
		and int(gem_events[0].get("frequency_hz", 0)) >= 22000
		and int(gem_events[0].get("frequency_hz", 0)) < 32000
		and int(gem_events[0].get("source_hz", 0)) == 32000
		and int(gem_events[0].get("volume_index", 0)) == 255
		and String(gem_events[1].get("key", "")) == "gemdrop"
		and bool(gem_events[1].get("drop_if_voice_busy", false))
		and int(gem_events[1].get("queue_padding_ms", 0)) == 50,
		"Memory gems should consume bell RNG before progress and queue only gemdrop after a threshold"
	)

	var last_pair_fixture := _fixture(41, {
		"gem_progress_origin": 452,
		"gem_progress": 452 + 98 * 8,
		"gem_progress_step": 8,
	})
	var last_pair = last_pair_fixture.simulation
	_set_single_pair_board(last_pair, 24)
	last_pair.step(1, 100, 0, [{"action_kind": 1, "tile_index": 0}])
	last_pair.step(2, 120, 0, [{"action_kind": 1, "tile_index": 8}])
	var threshold_result: Dictionary = last_pair.step(3, 271, 0)
	_expect(
		String(threshold_result.snapshot.stage) == "active"
		and threshold_result.bonus_actions.size() == 1
		and String(threshold_result.bonus_actions[0].branch) == "gem_drop_transition"
		and not _has_sound_event(threshold_result.events, "harpgliss1")
		and not _event_kinds(threshold_result.events).has("memory_station_success_started"),
		"a threshold on the last pair should bypass Memory's harp and success-hold tail for Gem Drop"
	)

	var letters_fixture := _fixture(5, {
		"lives": 4,
		"lives_max": 5,
		"letter_bits": 0,
	})
	var letters_simulation = letters_fixture.simulation
	var letter_deltas: Dictionary = {}
	var letter_actions: Array[Dictionary] = []
	var letter_events: Array[Dictionary] = []
	for tile_type in range(31, 36):
		letters_simulation._dispatch_tile_effect(
			tile_type, 2, "match", letter_events, letter_deltas, letter_actions
		)
	_expect(
		int(letter_deltas.get("letter_bits", 0)) == 0
		and int(letter_deltas.get("lives", 0)) == 1
		and String(letter_actions[-1].effect_key) == "extra_letter_or_score",
		"completing EXTRA should grant the life/armour/score cascade and clear its letters"
	)


func _test_keyboard_match_timing_and_success_growth() -> void:
	var fixture := _fixture(7, {
		"memory_success_streak": 1,
		"memory_point_bonus": 10,
		"memory_point_step": 5,
		"score_multiplier": 2,
	})
	var simulation = fixture.simulation
	_set_single_pair_board(simulation, 2)

	var first: Dictionary = simulation.step(1, 100, MemoryStation.ACTION_FIRE)
	_expect(not bool(first.snapshot.tiles[0].face_down), "Fire should reveal the selected first tile")
	simulation.step(2, 101, 0)
	simulation.step(3, 102, MemoryStation.ACTION_RIGHT)
	simulation.step(4, 103, 0)
	var second: Dictionary = simulation.step(5, 120, MemoryStation.ACTION_FIRE)
	_expect(String(second.snapshot.pending_kind) == "match", "equal keyboard tiles should schedule a match")
	_expect(int(second.snapshot.reveal_deadline_ms) == 270, "keyboard matches should wait 150ms")

	var equality: Dictionary = simulation.step(6, 270, 0)
	_expect(
		String(equality.snapshot.pending_kind) == "match",
		"pending reveals should remain unresolved at exact deadline equality"
	)
	var resolved: Dictionary = simulation.step(7, 271, 0)
	_expect(String(resolved.snapshot.stage) == "success_hold", "the last pair should begin success hold")
	_expect(
		_has_sound_event(resolved.events, "harpgliss1", 255),
		"a non-Gem-Drop last pair should play the executable-traced full-volume harp glissando"
	)
	_expect(resolved.bonus_actions.size() == 1, "a resolved pair should request one semantic tile effect")
	_expect(
		int(resolved.bonus_actions[0].tile_type) == 2
		and int(resolved.bonus_actions[0].removed_count) == 2,
		"the semantic effect should identify the exact removed pair"
	)
	_expect(int(resolved.snapshot.success_deadline_ms) == 3271, "success should hold for 3000ms")

	var hold_equality: Dictionary = simulation.step(8, 3271, 0)
	_expect(hold_equality.completion.is_empty(), "success should not complete at exact hold equality")
	var completed: Dictionary = simulation.step(9, 3272, 0)
	_expect(bool(completed.completion.success), "success should complete after the strict hold boundary")
	_expect(
		int(completed.completion.memory_columns) == 5
		and int(completed.completion.memory_rows) == 5
		and int(completed.completion.memory_success_streak) == 0,
		"every second successful board should grow both dimensions and reset the streak"
	)
	_expect(
		int(completed.completion.memory_point_bonus) == 15
		and int(completed.completion.score_award) == 30,
		"success should add the supplied retail point step before multiplier scoring"
	)
	_expect(
		int(completed.progression_deltas.get("score", 0)) == 30
		and int(completed.progression_deltas.get("memory_columns", 0)) == 1
		and int(completed.progression_deltas.get("memory_rows", 0)) == 1
		and int(completed.progression_deltas.get("memory_success_streak", 0)) == -1,
		"completion should return authoritative progression deltas"
	)


func _test_keyboard_mismatch_timing() -> void:
	var fixture := _fixture(8)
	var simulation = fixture.simulation
	_set_unique_board(simulation)
	_set_tile_type(simulation, 0, 0, 2)
	_set_tile_type(simulation, 1, 0, 3)
	_set_tile_type(simulation, 0, 1, 4)
	_set_tile_type(simulation, 1, 1, 4)

	simulation.step(1, 10, MemoryStation.ACTION_FIRE)
	simulation.step(2, 11, 0)
	simulation.step(3, 12, MemoryStation.ACTION_RIGHT)
	simulation.step(4, 13, 0)
	var second: Dictionary = simulation.step(5, 20, MemoryStation.ACTION_FIRE)
	_expect(String(second.snapshot.pending_kind) == "mismatch", "unequal tiles should schedule concealment")
	_expect(int(second.snapshot.reveal_deadline_ms) == 470, "keyboard mismatches should wait 450ms")
	simulation.step(6, 470, 0)
	var resolved: Dictionary = simulation.step(7, 471, 0)
	_expect(
		bool(resolved.snapshot.tiles[0].face_down)
		and bool(resolved.snapshot.tiles[4].face_down),
		"a mismatch should conceal every active revealed tile after the strict boundary"
	)
	_expect(
		int(resolved.snapshot.tries) == 1 and int(resolved.snapshot.mismatches) == 1,
		"mismatch accounting should retain the retail try"
	)


func _test_instant_tile_timing_and_semantic_effects() -> void:
	var delays := {0: 150, 1: 350, 11: 450, 38: 450}
	for tile_type_value in delays:
		var tile_type := int(tile_type_value)
		var fixture := _fixture(20 + tile_type)
		var simulation = fixture.simulation
		_set_unique_board(simulation)
		_set_tile_type(simulation, 0, 0, tile_type)
		_set_tile_type(simulation, 0, 1, 5)
		_set_tile_type(simulation, 1, 1, 5)
		var selected: Dictionary = simulation.step(1, 100, MemoryStation.ACTION_FIRE)
		_expect(
			String(selected.snapshot.pending_kind) == "effect"
			and int(selected.snapshot.reveal_deadline_ms) == 100 + int(delays[tile_type]),
			"instant tile %d should use its executable delay" % tile_type
		)
		var equality_ms := 100 + int(delays[tile_type])
		simulation.step(2, equality_ms, 0)
		var resolved: Dictionary = simulation.step(3, equality_ms + 1, 0)
		_expect(
			resolved.bonus_actions.size() == 1
			and int(resolved.bonus_actions[0].tile_type) == tile_type,
			"instant tile %d should emit one normalized semantic effect" % tile_type
		)

	var effect_fixture := _fixture(31)
	var effect_simulation = effect_fixture.simulation
	var original_deadline := int(effect_simulation.snapshot().mode_deadline_ms)
	var applied: Dictionary = effect_simulation.step(1, 1, 0, [
		{"kind": "memory_time_delta", "milliseconds": 2500},
		{"kind": "score_delta", "amount": 700},
	])
	_expect(
		int(applied.snapshot.mode_deadline_ms) == original_deadline + 2500,
		"resolved semantic effects should authoritatively change the mode deadline"
	)
	_expect(
		int(applied.progression_deltas.get("score", 0)) == 700,
		"resolved semantic score effects should return a progression delta"
	)


func _test_timeout_strict_boundary() -> void:
	var fixture := _fixture(40)
	var simulation = fixture.simulation
	var deadline := int(simulation.snapshot().mode_deadline_ms)
	var equality: Dictionary = simulation.step(1, deadline, 0)
	_expect(
		String(equality.snapshot.stage) == "active" and equality.completion.is_empty(),
		"Memory Station should remain active at exact timeout equality"
	)
	var expired: Dictionary = simulation.step(2, deadline + 1, 0)
	_expect(
		String(expired.snapshot.stage) == "complete"
		and not bool(expired.completion.success),
		"Memory Station should fail immediately after the strict timeout boundary"
	)


func _test_kill_time_rng_and_throttle() -> void:
	var fixture := _fixture(50)
	var simulation = fixture.simulation
	var rng = fixture.rng
	var before_draws := int(rng.draw_count)
	var killed: Dictionary = simulation.step(1, 1, MemoryStation.ACTION_SECONDARY)
	_expect(int(rng.draw_count) == before_draws + 4, "kill-time should consume exactly four raw RNG draws")
	_expect(
		int(killed.snapshot.mode_deadline_ms) == 29000,
		"kill-time should subtract exactly 1000ms from the deadline"
	)
	var score := int(killed.progression_deltas.get("score", 0))
	_expect(score >= 100 and score <= 1000 and score % 100 == 0, "kill-time score should be 100..1000")
	var throttled: Dictionary = simulation.step(2, 2, MemoryStation.ACTION_SECONDARY)
	_expect(
		int(rng.draw_count) == before_draws + 4
		and throttled.progression_deltas.is_empty(),
		"held kill-time should be blocked while now is not strictly past its 25ms gate"
	)
	var strict_gate: Dictionary = simulation.step(3, 26, MemoryStation.ACTION_SECONDARY)
	_expect(strict_gate.progression_deltas.is_empty(), "kill-time should remain blocked at exact gate equality")
	var repeated: Dictionary = simulation.step(4, 27, MemoryStation.ACTION_SECONDARY)
	_expect(
		int(rng.draw_count) == before_draws + 8
		and int(repeated.snapshot.mode_deadline_ms) == 28000,
		"kill-time should repeat only after the strict 25ms gate"
	)


func _test_mouse_keyboard_semantic_parity() -> void:
	var keyboard_fixture := _fixture(60)
	var keyboard = keyboard_fixture.simulation
	_set_single_pair_board(keyboard, 6)
	keyboard.step(1, 100, MemoryStation.ACTION_FIRE)
	keyboard.step(2, 101, 0)
	keyboard.step(3, 102, MemoryStation.ACTION_RIGHT)
	keyboard.step(4, 103, 0)
	keyboard.step(5, 120, MemoryStation.ACTION_FIRE)
	var keyboard_result: Dictionary = keyboard.step(6, 271, 0)

	var pointer_fixture := _fixture(60)
	var pointer = pointer_fixture.simulation
	_set_single_pair_board(pointer, 6)
	pointer.step(1, 100, 0, [{"action_kind": 1, "tile_index": 0}])
	pointer.step(2, 101, 0)
	pointer.step(3, 102, 0)
	pointer.step(4, 103, 0)
	var pointer_second: Dictionary = pointer.step(5, 120, 0, [{"action_kind": 1, "tile_index": 8}])
	_expect(
		int(pointer_second.snapshot.reveal_deadline_ms) == 270,
		"normalized pointer and FIRE selections should use the same authoritative delay"
	)
	var pointer_result: Dictionary = pointer.step(6, 271, 0)

	_expect(
		_tile_activity(keyboard_result.snapshot.tiles) == _tile_activity(pointer_result.snapshot.tiles),
		"keyboard and semantic pointer selection should produce the same authoritative grid"
	)
	_expect(
		keyboard_result.bonus_actions == pointer_result.bonus_actions,
		"keyboard and semantic pointer selection should request the same tile effect"
	)
	_expect(
		int(pointer_result.snapshot.cursor_col) == 1
		and int(pointer_result.snapshot.cursor_row) == 0,
		"semantic tile indices should update the authoritative cursor"
	)
	_expect(
		keyboard.state_for_hash() == pointer.state_for_hash(),
		"same seed/tick/tile actions should hash identically across keyboard, gamepad, and pointer input"
	)


func _test_read_only_action_validation() -> void:
	var fixture := _fixture(65)
	var simulation = fixture.simulation
	_set_single_pair_board(simulation, 7)
	var before: Dictionary = simulation.state_for_hash()
	var valid_select: Dictionary = simulation.validate_action(1, 0, 1, 1)
	_expect(bool(valid_select.ok), "validation should accept an active face-down fixed-stride tile")
	_expect(
		simulation.state_for_hash() == before,
		"action validation should never mutate deterministic state"
	)
	var invalid_tile: Dictionary = simulation.validate_action(1, 7, 1, 1)
	_expect(
		not bool(invalid_tile.ok) and String(invalid_tile.reason) == "tile_is_outside_active_grid",
		"validation should reject fixed-stride rows outside the active grid"
	)
	simulation.step(1, 10, 0, [{"action_kind": 1, "tile_index": 0}])
	var revealed: Dictionary = simulation.validate_action(1, 0, 2, 11)
	_expect(
		not bool(revealed.ok) and String(revealed.reason) == "tile_is_already_revealed",
		"validation should reject an already revealed tile"
	)
	simulation.step(2, 11, 0, [{"action_kind": 1, "tile_index": 8}])
	var pending: Dictionary = simulation.validate_action(1, 1, 3, 12)
	_expect(
		not bool(pending.ok) and String(pending.reason) == "reveal_pending",
		"validation should reject selection while pair resolution is pending"
	)

	var kill_fixture := _fixture(66)
	var kill_simulation = kill_fixture.simulation
	var initial_gate: Dictionary = kill_simulation.validate_action(2, -1, 1, 0)
	_expect(
		not bool(initial_gate.ok) and String(initial_gate.reason) == "kill_time_throttled",
		"kill-time validation should preserve the strict initial millisecond gate"
	)
	var valid_kill: Dictionary = kill_simulation.validate_action(2, -1, 1, 1)
	_expect(bool(valid_kill.ok), "kill-time validation should accept the first post-zero action")


func _test_state_for_hash_is_ordered_and_repeatable() -> void:
	var first_fixture := _fixture(70)
	var second_fixture := _fixture(70)
	var first_state: Dictionary = first_fixture.simulation.state_for_hash()
	var second_state: Dictionary = second_fixture.simulation.state_for_hash()
	_expect(first_state == second_state, "equal seed/config entries should expose identical hash state")
	var indexes: Array[int] = []
	for tile_value in first_state.tiles:
		indexes.append(int((tile_value as Dictionary).tile_index))
	_expect(
		indexes == [0, 1, 2, 3, 8, 9, 10, 11, 16, 17, 18, 19, 24, 25, 26, 27],
		"hash tiles should be explicitly ordered by column then row"
	)


func _test_countdown_voice_contract() -> void:
	var spoken_fixture := _fixture(67)
	var spoken: Dictionary = spoken_fixture.simulation.step(1, 19_500, 0)
	var spoken_events: Array = spoken.events.filter(
		func(event: Dictionary) -> bool: return String(event.kind) == "memory_countdown"
	)
	_expect(
		spoken_events.size() == 1
		and int(spoken_events[0].seconds) == 10
		and int(spoken_fixture.simulation.snapshot().countdown_gate) == 10,
		"Memory should speak ten only inside its strict 10-to-11-second window"
	)

	var lower_boundary := _fixture(68)
	var lower: Dictionary = lower_boundary.simulation.step(1, 20_000, 0)
	_expect(
		lower.events.all(func(event: Dictionary) -> bool: return String(event.kind) != "memory_countdown")
		and int(lower_boundary.simulation.snapshot().countdown_gate) == 11,
		"Memory countdown should remain silent at exact ten-second equality"
	)

	var suppressed_fixture := _fixture(69)
	var suppressed: Dictionary = suppressed_fixture.simulation.step(
		1,
		19_500,
		0,
		[{"action_kind": MemoryStation.BONUS_ACTION_KILL_TIME, "tile_index": -1}]
	)
	_expect(
		suppressed.events.all(func(event: Dictionary) -> bool: return String(event.kind) != "memory_countdown")
		and int(suppressed_fixture.simulation.snapshot().countdown_gate) == 10,
		"kill-time input should consume the countdown gate while suppressing its spoken digit"
	)


func _fixture(seed_value: int, overrides: Dictionary = {}) -> Dictionary:
	var contract := MemoryStation.retail_contract()
	contract["placement_iterations"] = 64
	contract["tile_types"] = [2]
	contract["tile_weights"] = [1]
	# range [1,1000) can never be below one, disabling special injection
	# without changing the retail generator's one-roll draw contract.
	contract["special_roll_threshold"] = 1
	var simulation := MemoryStation.new()
	_expect(simulation.configure(contract), simulation.get_last_error())
	var progression := {
		"bonus_time": 20,
		"memory_columns": 4,
		"memory_rows": 4,
		"memory_success_streak": 0,
		"memory_point_bonus": 0,
		"memory_point_step": 0,
		"score_multiplier": 1,
	}
	progression.merge(overrides, true)
	var rng := Rng.new(seed_value)
	var entered: Dictionary = simulation.enter(0, progression, rng, 0, 0)
	_expect(bool(entered.get("ok", false)), simulation.get_last_error())
	return {"simulation": simulation, "rng": rng}


func _event_kinds(events: Array) -> Array[String]:
	var kinds: Array[String] = []
	for event_value in events:
		kinds.append(String((event_value as Dictionary).get("kind", "")))
	return kinds


func _has_sound_event(events: Array, key: String, volume_index: int = -1) -> bool:
	for event_value in events:
		var event: Dictionary = event_value
		if String(event.get("kind", "")) != "sound_cue":
			continue
		if String(event.get("key", "")) != key:
			continue
		if volume_index >= 0 and int(event.get("volume_index", -1)) != volume_index:
			continue
		return true
	return false


func _set_unique_board(simulation) -> void:
	for index in range(simulation._tiles.size()):
		var tile: Dictionary = simulation._tiles[index]
		tile["active"] = true
		tile["face_down"] = true
		tile["state"] = 0
		tile["type"] = 100 + index


func _set_single_pair_board(simulation, tile_type: int) -> void:
	_set_unique_board(simulation)
	_set_tile_type(simulation, 0, 0, tile_type)
	_set_tile_type(simulation, 1, 0, tile_type)


func _set_tile_type(simulation, col: int, row: int, tile_type: int) -> void:
	var index := col * int(simulation._rows) + row
	var tile: Dictionary = simulation._tiles[index]
	tile["type"] = tile_type


func _tile_activity(tiles: Array) -> Array[bool]:
	var activity: Array[bool] = []
	for tile_value in tiles:
		activity.append(bool((tile_value as Dictionary).active))
	return activity


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

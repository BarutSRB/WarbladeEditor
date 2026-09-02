extends SceneTree

const Simulation := preload("res://src/sim/game_simulation.gd")
const Protocol := preload("res://src/net/protocol_codec.gd")
const Rng := preload("res://src/sim/deterministic_rng.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_retail_progression_flags_reach_boss_entry()
	_test_entry_rng_flags_snapshot_and_music()
	_test_classic_and_balanced_coop_health()
	_test_generic_runtime_is_excluded()
	_test_common_projectile_pool_and_order()
	_test_controller_results_and_projectile_callbacks_fail_closed()
	_test_deferred_sound_gate()
	_test_campaign_entry_inherits_global_sound_gate()
	_test_boss_projectile_collision_policy()
	_test_public_hit_and_render_boundary()
	_test_public_defeat_reward_and_terminal_route()
	_test_public_defeat_continues_to_level_twenty_six()
	if _failures.is_empty():
		print("LEVEL 25 BOSS INTEGRATION TESTS PASSED")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _test_retail_progression_flags_reach_boss_entry() -> void:
	var config := _boss_config("solo", "classic", 2500)
	config.start_level = 24
	var simulation := Simulation.new()
	_expect(
		simulation.configure(config),
		"the level-24 progression producer fixture should configure"
	)
	if not simulation._configured:
		return
	var progression: Dictionary = simulation._progression_for_seat(0)
	progression.rank_markers = 0x3f
	simulation._apply_shop_effect(simulation._shop_by_id[14], 0)
	_expect(
		bool(simulation._match_persistent_flags_by_seat[0].rank_ready),
		"a paid full-mask Rank Marker should produce the retail rank-ready flag"
	)
	for _pickup in range(3):
		simulation._apply_retail_bonus_type(22, progression, 0)
	_expect(
		bool(simulation._match_persistent_flags_by_seat[0].only_blue_coins_active),
		"the third blue-money sucker pickup should produce the retail only-blue flag"
	)
	simulation._begin_level(25)
	_expect(
		bool(simulation.get_snapshot().boss.active)
		and bool(simulation._retail_big_boss.state_hash_payload().only_blue_coins_active),
		"both gameplay-produced flags should persist through level 25 boss entry"
	)


func _test_entry_rng_flags_snapshot_and_music() -> void:
	var config := _boss_config("solo", "classic", 2501, [{
		"rank_ready": true,
		"only_blue_coins_active": true,
	}, {
		"rank_ready": false,
		"only_blue_coins_active": false,
	}])
	var simulation = _new_boss(config)
	if simulation == null:
		return
	var initial: Dictionary = simulation.get_snapshot()
	_expect(
		initial.phase == "level"
		and int(initial.level_id) == 25
		and bool(initial.boss.active)
		and int(initial.boss.state) == 13
		and int(initial.boss.stage) == 0
		and String(initial.boss.sheet) == "alien_big1_1",
		"direct level-25 entry should expose active state 13 without changing the public phase"
	)
	_expect(
		float(initial.boss.health) == 300.0
		and float(initial.boss.max_health) == 300.0
		and float(initial.boss.x) == 384.0
		and float(initial.boss.y) == -189.0
		and initial.boss.parts.size() == 2,
		"classic entry should publish retail health, anchor, and both packed render parts"
	)
	_expect(
		int(initial.rng.draw_count) == 555
		and int(simulation._retail_global_sound_gate) == 4,
		"boss animation and hum draws must follow the warp, 100 common-slot, 150 entity-slot, and tail draws"
	)
	_expect(
		bool(simulation._match_persistent_flags_by_seat[0].rank_ready)
		and bool(simulation._match_persistent_flags_by_seat[0].only_blue_coins_active)
		and not simulation._shared.has("rank_ready")
		and not simulation._shared.has("only_blue_coins_active"),
		"physical-seat boss flags should hydrate independently of shared co-op progression"
	)
	_expect(
		bool(simulation._retail_big_boss.state_hash_payload().only_blue_coins_active),
		"state 13 should sample the selected physical player's only-blue-coins flag at entry"
	)
	var replay: Dictionary = simulation.get_replay()
	_expect(
		replay.match_persistent_flags_by_seat == simulation._match_persistent_flags_by_seat,
		"replays should retain normalized per-physical-seat boss flags"
	)
	_expect(
		JSON.parse_string(JSON.stringify(initial)) is Dictionary,
		"the always-present boss snapshot should remain network/JSON safe"
	)
	var packet := Protocol.encode_snapshot(initial, 25)
	var decoded := Protocol.decode_packet(packet)
	_expect(
		not packet.is_empty()
		and bool(decoded.get("ok", false))
		and int(decoded.get("type", 0)) == Protocol.MessageType.SNAPSHOT
		and int(decoded.get("sequence", 0)) == 25
		and int(decoded.payload.get("version", 0)) == Protocol.SNAPSHOT_VERSION,
		"an active mode-4 snapshot should round-trip through the real v9 network codec"
	)
	if bool(decoded.get("ok", false)):
		var decoded_boss := decoded.payload.get("boss", {}) as Dictionary
		_expect(
			bool(decoded_boss.get("active", false))
			and int(decoded_boss.get("state", 0)) == 13
			and String(decoded_boss.get("sheet", "")) == "alien_big1_1"
			and (decoded_boss.get("parts", []) as Array).size() == 2,
			"the network snapshot should preserve the active controller projection and both parts"
		)

	var first: Dictionary = simulation.step()
	var first_kinds := _event_kinds(first)
	_expect(
		first_kinds.count("music_cue") == 1
		and first_kinds.count("audio_loop_started") == 1,
		"entry should deliver exactly one boss music cue and one hum-loop start on the first observable tick"
	)
	var second: Dictionary = simulation.step()
	_expect(
		_event_kinds(second).count("music_cue") == 0,
		"boss music must not be re-emitted by later level ticks"
	)

	var twin = _new_boss(config)
	if twin != null:
		twin.step()
		twin.step()
		_expect(
			twin.state_hash() == simulation.state_hash(),
			"identical level-25 inputs should produce identical controller/effect/root hashes"
		)


func _test_classic_and_balanced_coop_health() -> void:
	var classic = _new_boss(_boss_config("coop", "classic", 2525))
	var balanced = _new_boss(_boss_config("coop", "balanced", 2525))
	if classic == null or balanced == null:
		return
	_expect(
		float(classic.get_snapshot().boss.max_health) == 300.0,
		"Classic co-op should retain the retail 300-point boss health"
	)
	_expect(
		float(balanced.get_snapshot().boss.max_health) == 600.0,
		"Balanced co-op should apply the established two-times boss health rule"
	)
	classic._match_persistent_flags_by_seat[0].rank_ready = true
	_expect(
		not bool(classic._match_persistent_flags_by_seat[1].rank_ready),
		"co-op physical-seat flags must not alias each other even though progression is shared"
	)


func _test_generic_runtime_is_excluded() -> void:
	var simulation = _new_boss(_boss_config("solo", "classic", 2526))
	if simulation == null:
		return
	simulation._spawn_due_waves()
	simulation._enemy_liveness_idle_updates = Simulation.LEVEL_LIVENESS_UPDATE_LIMIT + 10
	simulation._level_watchdog_start_tick = (
		simulation._tick - Simulation.LEVEL_WATCHDOG_TICKS - 10
	)
	var snapshot: Dictionary = simulation.step()
	_expect(
		snapshot.enemies.is_empty()
		and simulation._spawned_waves.is_empty()
		and int(snapshot.level_resolution.liveness_idle_updates) == 0
		and not bool(snapshot.level_resolution.resolved)
		and snapshot.phase == "level",
		"generic spawning, liveness, and watchdog completion must never own mode 4"
	)


func _test_common_projectile_pool_and_order() -> void:
	var simulation = _new_boss(_boss_config("solo", "classic", 2527))
	if simulation == null:
		return
	var draws_before := int(simulation._rng.snapshot().draw_count)
	var allocations: Array[Dictionary] = []
	for index in range(Simulation.COMMON_PROJECTILE_SLOT_COUNT + 1):
		allocations.append(simulation._allocate_retail_boss_common_projectile({
			"owner_kind": "boss",
			"enemy_projectile_type": 15,
			"retail_left": 100.0,
			"retail_top": 100.0,
			"reservation_phase": "active_and_top_left",
		}))
	_expect(
		bool(allocations[0].ok)
		and String(allocations[0].error).is_empty()
		and bool(allocations[0].allocated)
		and int(allocations[0].common_slot) == 0
		and bool(allocations[99].allocated)
		and int(allocations[99].common_slot) == 99
		and bool(allocations[100].ok)
		and String(allocations[100].error).is_empty()
		and not bool(allocations[100].allocated)
		and int(allocations[100].common_slot) == -1,
		"boss allocation should distinguish successful pool exhaustion from callback failure"
	)
	_expect(
		int(simulation._rng.snapshot().draw_count) == draws_before,
		"the boss common-projectile allocator must not consume root RNG"
	)
	_expect(
		simulation._projectiles.is_empty()
		and allocations[0].has("retained_animation_frame")
		and allocations[0].has("retained_animation_period")
		and allocations[0].has("retained_animation_countdown"),
		"reservation should retain slot animation fields without publishing a partial projectile"
	)

	var finalized = _new_boss(_boss_config("solo", "classic", 2531))
	if finalized == null:
		return
	(finalized._common_projectile_slots[0] as Dictionary).animation_frame = 5
	(finalized._common_projectile_slots[0] as Dictionary).animation_period_fp = 2 * Simulation.FP_ONE
	(finalized._common_projectile_slots[0] as Dictionary).animation_countdown_fp = Simulation.FP_ONE
	var reservation: Dictionary = finalized._allocate_retail_boss_common_projectile({
		"owner_kind": "boss",
		"enemy_projectile_type": 15,
		"retail_left": 100.0,
		"retail_top": 100.0,
		"reservation_phase": "active_and_top_left",
	})
	var finalize_result := _finalize_boss_projectile(
		finalized,
		reservation,
		15,
		100.0,
		100.0,
		1.0,
		2.0
	)
	_expect(bool(finalize_result.get("ok", false)), "a traced type-15 reservation should finalize")
	if finalized._projectiles.is_empty():
		return
	var projectile := finalized._projectiles[0] as Dictionary
	_expect(
		int(projectile.get("common_slot", -1)) == 0
		and int(projectile.get("enemy_projectile_type", 0)) == 15
		and String(projectile.get("owner_kind", "")) == "boss"
		and String(projectile.get("enemy_sheet", "")) == "alien_big1_1"
		and int(projectile.x_fp) == 116 * Simulation.FP_ONE
		and int(projectile.y_fp) == 116 * Simulation.FP_ONE
		and int(projectile.animation_frame) == 5
		and projectile.source_rect == [160, 64, 32, 32]
		and finalized._enemy_projectile_broad_metadata(projectile) == [8, 8, 24, 24],
		"type-15 finalization should retain raw slot phase and bind the fixed sprite, center, and inset"
	)
	var x_before := int(projectile.x_fp)
	finalized._update_common_projectiles()
	_expect(
		int(projectile.x_fp) == x_before + Simulation.FP_ONE,
		"a common boss shot present at tick entry should move through the root projectile updater"
	)
	projectile.velocity_x_fp = 0
	projectile.velocity_y_fp = 0
	projectile.animation_frame = 3
	projectile.animation_period_fp = 2 * Simulation.FP_ONE
	projectile.animation_countdown_fp = 0
	finalized._update_common_projectiles()
	_expect(
		int(projectile.animation_frame) == 0
		and int(projectile.animation_countdown_fp) == 2 * Simulation.FP_ONE
		and projectile.source_rect == [0, 64, 32, 32],
		"type-15 animation should advance only after strict countdown underflow and wrap 3 to 0"
	)
	projectile.retail_top_fp = 600 * Simulation.FP_ONE
	projectile.y_fp = 616 * Simulation.FP_ONE
	finalized._update_common_projectiles()
	_expect(not bool(projectile.expired), "boss shots should survive at top-left Y exactly 600")
	projectile.retail_top_fp = 600 * Simulation.FP_ONE + 1
	projectile.y_fp = 616 * Simulation.FP_ONE + 1
	finalized._update_common_projectiles()
	_expect(bool(projectile.expired), "boss shots should retire only above top-left Y 600")

	var burst = _new_boss(_boss_config("solo", "classic", 2532))
	if burst == null:
		return
	var burst_reservation: Dictionary = burst._allocate_retail_boss_common_projectile({
		"owner_kind": "boss",
		"enemy_projectile_type": 14,
		"retail_left": 200.0,
		"retail_top": 150.0,
	})
	var burst_finalize := _finalize_boss_projectile(
		burst,
		burst_reservation,
		14,
		200.0,
		150.0,
		0.0,
		1.0
	)
	_expect(bool(burst_finalize.get("ok", false)), "a traced type-14 reservation should finalize")
	if not burst._projectiles.is_empty():
		var burst_projectile := burst._projectiles[0] as Dictionary
		_expect(
			int(burst_projectile.animation_frame) == 0
			and int(burst_projectile.animation_period_fp) == 2 * Simulation.FP_ONE
			and int(burst_projectile.animation_countdown_fp) == 3 * Simulation.FP_ONE
			and burst_projectile.source_rect == [512, 0, 32, 32]
			and burst._enemy_projectile_broad_metadata(burst_projectile) == [4, 4, 28, 28],
			"type-14 finalization should overwrite retained animation and bind its first traced frame"
		)
		burst_projectile.animation_frame = 2
		burst_projectile.animation_countdown_fp = 0
		burst._update_common_projectiles()
		_expect(
			int(burst_projectile.animation_frame) == 3
			and burst_projectile.source_rect == [544, 0, 32, 32],
			"type-14 animation should cross from the x512 column to x544 at phase three"
		)

	var fractional = _new_boss(_boss_config("solo", "classic", 2542))
	if fractional == null:
		return
	var fractional_left := Rng._float32(496.0001)
	var fractional_top := Rng._float32(180.25)
	var fractional_reservation: Dictionary = (
		fractional._allocate_retail_boss_common_projectile({
			"owner_kind": "boss",
			"enemy_projectile_type": 15,
			"retail_left": fractional_left,
			"retail_top": fractional_top,
			"reservation_phase": "active_and_top_left",
		})
	)
	var controller_center_x_fp := roundi(
		Rng._float32(fractional_left + 16.0) * Simulation.FP_ONE
	)
	var additive_center_x_fp := (
		roundi(fractional_left * Simulation.FP_ONE)
		+ 16 * Simulation.FP_ONE
	)
	var fractional_finalize := _finalize_boss_projectile(
		fractional,
		fractional_reservation,
		15,
		fractional_left,
		fractional_top,
		0.0,
		1.0
	)
	_expect(
		controller_center_x_fp != additive_center_x_fp
		and bool(fractional_finalize.get("ok", false))
		and not fractional._projectiles.is_empty()
		and int((fractional._projectiles[0] as Dictionary).x_fp)
		== controller_center_x_fp,
		"fractional boss-shot centers must use float32(top-left + 16), not fixed-point distributivity"
	)

	var ordered = _new_boss(_boss_config("solo", "classic", 2528))
	if ordered == null:
		return
	ordered._retail_big_boss._current_group_id = 1
	(ordered._players[0] as Dictionary).invulnerable_ticks = 100000
	var spawned_event: Dictionary = {}
	var spawned_snapshot: Dictionary = {}
	for _guard in range(2500):
		var candidate: Dictionary = ordered.step()
		for event_value in candidate.events:
			var event := event_value as Dictionary
			if String(event.kind) == "boss_projectile_spawned":
				spawned_event = event
				spawned_snapshot = candidate
				break
		if not spawned_event.is_empty():
			break
	_expect(
		not spawned_event.is_empty(),
		"the deterministic loop-group fixture should eventually emit an aimed boss shot"
	)
	if spawned_event.is_empty():
		return
	var spawned_id := int(spawned_event.projectile_id)
	var spawned := _snapshot_projectile(spawned_snapshot, spawned_id)
	var aimed_sample := false
	for event_value in spawned_snapshot.events:
		var event := event_value as Dictionary
		if String(event.kind) == "sound_cue" and String(event.get("key", "")) == "bigsmall":
			aimed_sample = true
	_expect(
		not spawned.is_empty()
		and int(spawned.spawn_tick) == int(spawned_snapshot.tick)
		and int(spawned.x_fp) == int(spawned_event.x_fp)
		and aimed_sample,
		"a shot finalized during controller step should remain still that tick and use bigsmall"
	)
	var velocity_x_fp := int(spawned.velocity_x_fp)
	var next: Dictionary = ordered.step()
	var moved := _snapshot_projectile(next, spawned_id)
	if not moved.is_empty():
		_expect(
			int(moved.x_fp) == int(spawned.x_fp) + velocity_x_fp,
			"a newly allocated boss shot should first move on the following root tick"
		)


func _test_controller_results_and_projectile_callbacks_fail_closed() -> void:
	var rejected = _new_boss(_boss_config("solo", "classic", 2539))
	if rejected == null:
		return
	rejected._events.clear()
	var rejection: Dictionary = rejected._allocate_retail_boss_common_projectile({
		"owner_kind": "boss",
		"enemy_projectile_type": 7,
		"retail_left": 100.0,
		"retail_top": 100.0,
	})
	_expect(
		not bool(rejection.get("ok", true))
		and not String(rejection.get("error", "")).is_empty()
		and not bool(rejection.get("allocated", true))
		and bool(rejected._boss_runtime_blocked),
		"an invalid root reservation must return an explicit callback error, not pool-full"
	)

	var failed_result = _new_boss(_boss_config("solo", "classic", 2540))
	if failed_result == null:
		return
	failed_result._events.clear()
	var failed_score_before := int(failed_result._shared.score)
	var failed_render_before: Dictionary = (
		failed_result._boss_render_snapshot as Dictionary
	).duplicate(true)
	failed_result._ingest_boss_controller_result({
		"ok": false,
		"error": "injected controller failure",
		"snapshot": {"poisoned": true},
		"events": [{
			"kind": "boss_reward",
			"base_score": 500000,
			"owner_seat_id": 0,
			"apply_active_score_multiplier": false,
		}],
	})
	var failed_kinds := _event_kinds({"events": failed_result._events})
	_expect(
		bool(failed_result._boss_runtime_blocked)
		and int(failed_result._shared.score) == failed_score_before
		and failed_result._boss_render_snapshot == failed_render_before
		and not failed_kinds.has("boss_reward")
		and failed_kinds.count("boss_controller_error") == 1,
		"a failed controller result must be rejected before snapshot or event publication"
	)

	var unknown_event = _new_boss(_boss_config("solo", "classic", 2541))
	if unknown_event == null:
		return
	unknown_event._events.clear()
	var unknown_score_before := int(unknown_event._shared.score)
	var unknown_render_before: Dictionary = (
		unknown_event._boss_render_snapshot as Dictionary
	).duplicate(true)
	unknown_event._ingest_boss_controller_result({
		"ok": true,
		"error": "",
		"snapshot": {"poisoned": true},
		"events": [
			{
				"kind": "boss_reward",
				"base_score": 500000,
				"owner_seat_id": 0,
				"apply_active_score_multiplier": false,
			},
			{"kind": "untraced_boss_event"},
		],
	})
	var unknown_kinds := _event_kinds({"events": unknown_event._events})
	_expect(
		bool(unknown_event._boss_runtime_blocked)
		and int(unknown_event._shared.score) == unknown_score_before
		and unknown_event._boss_render_snapshot == unknown_render_before
		and not unknown_kinds.has("boss_reward")
		and not unknown_kinds.has("untraced_boss_event")
		and unknown_kinds.count("boss_controller_error") == 1,
		"an unknown controller event must reject the whole result before any event is published"
	)


func _test_public_hit_and_render_boundary() -> void:
	var simulation = _new_boss(_boss_config("solo", "classic", 2529))
	if simulation == null:
		return
	var projectile := _fire_public_projectile(simulation)
	if projectile.is_empty():
		return
	simulation._retail_big_boss._x = 400.0
	simulation._retail_big_boss._y = 180.0
	projectile.x_fp = 400 * Simulation.FP_ONE
	projectile.y_fp = 240 * Simulation.FP_ONE
	projectile.damage_fp = 10 * Simulation.FP_ONE
	var hits_before := int(simulation._profile_stats_by_seat[0].successful_hits)
	var snapshot: Dictionary = simulation.step()
	_expect(
		float(snapshot.boss.health) == 299.0
		and int(simulation._profile_stats_by_seat[0].successful_hits) == hits_before + 1
		and bool(projectile.expired),
		"a public player projectile should damage state 13, record one hit, and be consumed"
	)
	_expect(
		bool(snapshot.boss.parts[0].hit_flash)
		and bool(snapshot.boss.parts[1].hit_flash)
		and int(simulation._retail_big_boss.state_hash_payload().hit_flash_countdown) == 3,
		"the public snapshot should publish the pre-render flash while hashed controller state advances past both parts"
	)


func _test_boss_projectile_collision_policy() -> void:
	var simple = _new_boss(_boss_config("solo", "classic", 2533))
	if simple == null:
		return
	var reservation: Dictionary = simple._allocate_retail_boss_common_projectile({
		"owner_kind": "boss",
		"enemy_projectile_type": 15,
		"retail_left": 0.0,
		"retail_top": 0.0,
		"reservation_phase": "active_and_top_left",
	})
	if not bool(_finalize_boss_projectile(
		simple,
		reservation,
		15,
		0.0,
		0.0,
		0.0,
		0.0
	).get("ok", false)):
		return
	var projectile := simple._projectiles[0] as Dictionary
	var player := simple._players[0] as Dictionary
	var player_left := int(player.x_fp) / Simulation.FP_ONE - 20
	var player_top := int(player.y_fp) / Simulation.FP_ONE - 14
	projectile.retail_left_fp = (player_left - 32) * Simulation.FP_ONE
	projectile.retail_top_fp = (player_top - 8) * Simulation.FP_ONE
	projectile.x_fp = int(projectile.retail_left_fp) + 16 * Simulation.FP_ONE
	projectile.y_fp = int(projectile.retail_top_fp) + 16 * Simulation.FP_ONE
	_expect(
		not simple._enemy_projectile_hits_object(projectile, player),
		"type-15 broad collision should miss when its right edge only touches the fighter"
	)
	projectile.retail_left_fp = int(projectile.retail_left_fp) + Simulation.FP_ONE
	projectile.x_fp = int(projectile.x_fp) + Simulation.FP_ONE
	_expect(
		simple._enemy_projectile_hits_object(projectile, player),
		"type-15 broad collision should hit after one integer pixel of strict overlap"
	)
	player.invulnerable_ticks = 0
	player.projectile_suppression_ticks = 0
	simple._shared.shield_ticks = 0
	simple._shared.armour_fp = Simulation.FP_ONE
	simple._resolve_enemy_projectile_collisions()
	_expect(
		bool(player.alive)
		and int(simple._shared.armour_fp) == 0
		and bool(projectile.expired),
		"a boss shot should be consumed and apply exactly one armour charge"
	)

	var pixel_config := _boss_config("solo", "classic", 2534)
	pixel_config.collision_mode = "pixel"
	var pixel = _new_boss(pixel_config)
	if pixel == null:
		return
	var pixel_reservation: Dictionary = pixel._allocate_retail_boss_common_projectile({
		"owner_kind": "boss",
		"enemy_projectile_type": 15,
		"retail_left": float(player_left - 31),
		"retail_top": float(player_top - 8),
		"reservation_phase": "active_and_top_left",
	})
	if not bool(_finalize_boss_projectile(
		pixel,
		pixel_reservation,
		15,
		float(player_left - 31),
		float(player_top - 8),
		0.0,
		0.0
	).get("ok", false)):
		return
	var pixel_projectile := pixel._projectiles[0] as Dictionary
	var pixel_player := pixel._players[0] as Dictionary
	pixel_projectile.mask_id = "missing_boss_hma"
	_expect(
		pixel._enemy_projectile_hits_object(pixel_projectile, pixel_player),
		"state-13 pixel collision should use the broad hit when either HMA pointer is null"
	)
	pixel_projectile.mask_id = "alien_big1_1"
	pixel_projectile.animation_frame = 3
	pixel._set_enemy_projectile_mask_rect(pixel_projectile)
	_expect(
		not pixel._enemy_projectile_hits_object(pixel_projectile, pixel_player),
		"type-15 phase three should miss in pixel mode because its traced HMA frame is empty"
	)


func _test_deferred_sound_gate() -> void:
	var open = _new_boss(_boss_config("solo", "classic", 2535))
	if open == null:
		return
	open._events.clear()
	open._retail_global_sound_gate = 0
	open._retail_big_boss._fire_opcode_two_burst(open._boss_tick_scale())
	open._ingest_boss_controller_result(open._retail_big_boss._result())
	open._advance_retail_global_sound_gate()
	var bigfire_index := -1
	var alienshoot_index := -1
	for event_index in range(open._events.size()):
		var event := open._events[event_index] as Dictionary
		if String(event.kind) != "sound_cue":
			continue
		if String(event.get("key", "")) == "bigfire":
			bigfire_index = event_index
		elif String(event.get("key", "")) == "alienshoot2":
			alienshoot_index = event_index
	_expect(
		bigfire_index >= 0
		and alienshoot_index > bigfire_index
		and int(open._retail_global_sound_gate) == 1
		and open._boss_pending_deferred_sound.is_empty(),
		"an open process-global gate should flush only the last alienshoot2 after direct bigfire"
	)

	var closed = _new_boss(_boss_config("solo", "classic", 2536))
	if closed == null:
		return
	closed._events.clear()
	closed._retail_global_sound_gate = 1
	closed._retail_big_boss._fire_opcode_two_burst(closed._boss_tick_scale())
	closed._ingest_boss_controller_result(closed._retail_big_boss._result())
	closed._advance_retail_global_sound_gate()
	var closed_samples: Dictionary = {}
	for event_value in closed._events:
		var event := event_value as Dictionary
		if String(event.kind) == "sound_cue":
			closed_samples[String(event.get("key", ""))] = true
	_expect(
		closed_samples.has("bigfire")
		and not closed_samples.has("alienshoot2")
		and int(closed._retail_global_sound_gate) == 0
		and not closed._boss_pending_deferred_sound.is_empty(),
		"a closed gate should suppress alienshoot2 while hashing its one-tick pending handle"
	)
	var closed_hash: String = closed.state_hash()
	closed.step()
	_expect(
		closed._boss_pending_deferred_sound.is_empty()
		and int(closed._retail_global_sound_gate) == 1
		and closed.state_hash() != closed_hash,
		"the next state-13 pre-loop should discard a closed pending handle before advancing the gate"
	)


func _test_campaign_entry_inherits_global_sound_gate() -> void:
	var mapping = _new_boss(_boss_config("solo", "classic", 2538))
	if mapping != null:
		for enabled_phase in [
			Simulation.PHASE_LEVEL,
			Simulation.PHASE_GET_READY,
			Simulation.PHASE_WARP,
			Simulation.PHASE_WARP_MALFUNCTION,
		]:
			mapping._phase = enabled_phase
			_expect(
				mapping._retail_mode_calls_global_sound_gate(),
				"retail global sound gate should advance in mapped phase %s" % enabled_phase
			)
		for disabled_phase in [
			Simulation.PHASE_SHOP,
			Simulation.PHASE_BONUS_MODE,
			Simulation.PHASE_RANK_PROMOTION,
		]:
			mapping._phase = disabled_phase
			_expect(
				not mapping._retail_mode_calls_global_sound_gate(),
				"retail global sound gate should not advance in unmapped phase %s" % disabled_phase
			)
		mapping._phase = Simulation.PHASE_GET_READY
		mapping._pending_level_id = 0
		mapping._retail_global_sound_gate = 4
		mapping.step()
		_expect(
			int(mapping._retail_global_sound_gate) == 3,
			"the pre-step dispatcher should advance the gate during Get Ready"
		)
		mapping._phase = Simulation.PHASE_SHOP
		mapping._shop_warp_until_tick = mapping._tick + 100
		mapping.step()
		_expect(
			int(mapping._retail_global_sound_gate) == 3,
			"the pre-step dispatcher should leave the gate unchanged during shop mode 9"
		)

	var config := _boss_config("solo", "classic", 2537)
	config.start_level = 24
	config.end_level = 25
	var simulation := Simulation.new()
	_expect(
		simulation.configure(config),
		"the level-24 to level-25 gate-inheritance fixture should configure"
	)
	if not simulation._configured:
		return
	_expect(
		int(simulation._retail_global_sound_gate) == 4,
		"a fresh deterministic match process should seed the retail sound gate at four"
	)
	for _tick_index in range(3):
		simulation.step()
	_expect(
		int(simulation._retail_global_sound_gate) == 1,
		"three ordinary campaign ticks should advance the process-global gate from four to one"
	)
	simulation._begin_level(25)
	_expect(
		int(simulation._retail_global_sound_gate) == 1
		and bool(simulation.get_snapshot().boss.active),
		"campaign entry into level 25 should inherit gate history instead of reseeding it"
	)
	simulation.step()
	_expect(
		int(simulation._retail_global_sound_gate) == 0,
		"the first inherited state-13 main call should continue the accumulated gate sequence"
	)

	var routed := Simulation.new()
	_expect(
		routed.configure(config),
		"the exact level-24 Warp/shop/Get Ready parity fixture should configure"
	)
	if not routed._configured:
		return
	routed._progression_for_seat(0).money = 100
	routed._begin_warp(false, "level_twenty_four_gate_fixture", 0)
	routed._retail_global_sound_gate = 4
	routed._warp_malfunction_interval = 0
	for _warp_update in range(400):
		routed.step()
	_expect(
		String(routed.get_snapshot().phase) == Simulation.PHASE_SHOP
		and int(routed._retail_global_sound_gate) == 0,
		"four hundred eligible Warp calls should reach shop with the saturated gate at zero"
	)
	routed._shop_warp_until_tick = 0
	_expect(
		routed.set_shop_ready(0, true)
		and String(routed.get_snapshot().phase) == Simulation.PHASE_GET_READY,
		"the level-24 shop should route into Get Ready without advancing the gate"
	)
	for _get_ready_update in range(Simulation.GET_READY_TICKS + 1):
		routed.step()
	_expect(
		String(routed.get_snapshot().phase) == Simulation.PHASE_LEVEL
		and int(routed.get_snapshot().level_id) == 25
		and bool(routed.get_snapshot().boss.active)
		and int(routed._retail_global_sound_gate) == 1,
		"400 Warp plus 121 Get Ready calls should enter state 13 with inherited gate one"
	)


func _test_public_defeat_reward_and_terminal_route() -> void:
	var config := _boss_config("solo", "classic", 2530, [{
		"rank_ready": true,
		"only_blue_coins_active": true,
	}])
	var simulation = _new_boss(config)
	var twin = _new_boss(config)
	if simulation == null or twin == null:
		return
	var snapshot := _drive_public_defeat(simulation)
	var twin_snapshot := _drive_public_defeat(twin)
	if snapshot.is_empty() or twin_snapshot.is_empty():
		return
	var kinds := _event_kinds(snapshot)
	_expect(
		snapshot.phase == "complete"
		and bool(snapshot.result.completed)
		and int(snapshot.result.level_reached) == 25
		and int(snapshot.level_resolution.pending_level_id) == 0,
		"strict-negative boss defeat should complete level 25 in the same dispatcher tick without requesting 26"
	)
	_expect(
		not bool(snapshot.boss.active)
		and bool(snapshot.boss.defeated)
		and kinds.has("boss_reward")
		and kinds.has("boss_level_complete_mark")
		and kinds.has("audio_loop_stopped")
		and kinds.has("boss_defeated")
		and kinds.has("level_completed"),
		"boss defeat should forward reward, completion, hum-stop, defeat, and terminal events"
	)
	var mapped_samples: Dictionary = {}
	var hit_volumes: Dictionary = {}
	for event_value in snapshot.events:
		var event := event_value as Dictionary
		if String(event.kind) == "sound_cue":
			var sample_key := String(event.get("key", ""))
			mapped_samples[sample_key] = true
			if event.has("volume_index"):
				hit_volumes[sample_key] = int(event.volume_index)
	_expect(
		mapped_samples.has("hit1")
		and mapped_samples.has("hit2")
		and mapped_samples.has("explo4")
		and int(hit_volumes.get("hit1", -1)) == 250
		and int(hit_volumes.get("hit2", -1)) == 200,
		"terminal collision should route the traced normal-hit, terminal-hit, and death samples"
	)
	_expect(
		int(simulation._shared.score) == 1000000
		and int(simulation._shared.rockets) == 0
		and int(simulation._shared.rank_markers) == 0x15,
		"root progression should apply the 500,000-point active multiplier while the lethal allocated shot suppresses ordinary rockets without changing rank marks"
	)
	_expect(
		int(simulation._profile_stats_by_seat[0].successful_hits) == 1
		and simulation._boss_destroyed_counts_by_seat == [1, 0],
		"the lethal public shot should record one successful hit and the traced physical-seat completion count"
	)
	_expect(
		int(simulation._retail_big_boss_effects.snapshot().pools.particle.active_count) > 0
		and not ("level_26" in kinds),
		"death effects should remain root-authoritative while terminal routing never fabricates level 26"
	)
	var replay: Dictionary = simulation.get_replay()
	var twin_replay: Dictionary = twin.get_replay()
	_expect(
		not replay.frames.is_empty()
		and String(replay.frames[-1].state_hash) == simulation.state_hash(),
		"the terminal replay frame should hash controller, effect-pool, and root state together"
	)
	_expect(
		simulation.state_hash() == twin.state_hash()
		and replay.frames == twin_replay.frames
		and snapshot == twin_snapshot,
		"identical public inputs should preserve snapshot, replay, and state-hash parity through terminal defeat"
	)


func _test_public_defeat_continues_to_level_twenty_six() -> void:
	var config := _boss_config("solo", "classic", 2538)
	config.end_level = 30
	var simulation = _new_boss(config)
	if simulation == null:
		return
	var defeated := _drive_public_defeat(simulation)
	if defeated.is_empty():
		return
	_expect(
		String(defeated.get("phase", "")) == Simulation.PHASE_GET_READY
		and int(defeated.get("level_id", 0)) == 25
		and int((defeated.get("level_resolution", {}) as Dictionary).get(
			"pending_level_id",
			0
		)) == 26
		and (defeated.get("result", {}) as Dictionary).is_empty(),
		"a thirty-level match should route the traced boss defeat into Get Ready for level 26"
	)
	_expect(
		not bool((defeated.get("boss", {}) as Dictionary).get("active", true)),
		"boss ownership should be inactive as soon as the defeated encounter enters Get Ready"
	)
	for _get_ready_tick in range(Simulation.GET_READY_TICKS + 1):
		simulation.set_input(0, 0)
		simulation.step()
	var level_twenty_six: Dictionary = simulation.get_snapshot()
	_expect(
		String(level_twenty_six.get("phase", "")) == Simulation.PHASE_LEVEL
		and int(level_twenty_six.get("level_id", 0)) == 26
		and not bool((level_twenty_six.get("boss", {}) as Dictionary).get(
			"active",
			true
		)),
		"the boss bridge should enter ordinary level 26 exactly once with no boss owner"
	)
	_expect(
		int((level_twenty_six.get("profile_stats", []) as Array)[0].get(
			"best_hit_percent_above_level_25",
			0
		)) == 100,
		"entering level 26 should commit the clamped one-hit/one-fired-object accuracy sample"
	)


func _drive_public_defeat(simulation) -> Dictionary:
	simulation._shared.score_multiplier = 2
	simulation._shared.score_multiplier_ticks = 100
	simulation._shared.rank_markers = 0x15
	simulation._shared.rockets = 0
	var projectile := _fire_public_projectile(simulation)
	if projectile.is_empty():
		return {}
	simulation._retail_big_boss._x = 400.0
	simulation._retail_big_boss._y = 180.0
	projectile.x_fp = 400 * Simulation.FP_ONE
	projectile.y_fp = 240 * Simulation.FP_ONE
	projectile.damage_fp = 3010 * Simulation.FP_ONE
	return simulation.step()


func _finalize_boss_projectile(
	simulation,
	reservation: Dictionary,
	projectile_type: int,
	top_left_x: float,
	top_left_y: float,
	velocity_x: float,
	velocity_y: float
) -> Dictionary:
	var animation_frame := (
		0 if projectile_type == 14 else int(reservation.retained_animation_frame)
	)
	var animation_period := (
		2.0 if projectile_type == 14 else float(reservation.retained_animation_period)
	)
	var animation_countdown := (
		3.0 if projectile_type == 14 else float(reservation.retained_animation_countdown)
	)
	var inset := 4 if projectile_type == 14 else 8
	var extent := 28 if projectile_type == 14 else 24
	var frame_max := 5 if projectile_type == 14 else 3
	var source_rect := (
		[512, 0, 32, 32]
		if projectile_type == 14
		else [animation_frame * 32, 64, 32, 32]
	)
	return simulation._finalize_retail_boss_common_projectile({
		"allocated": true,
		"common_slot": int(reservation.common_slot),
		"projectile_id": int(reservation.projectile_id),
		"owner_kind": "boss",
		"enemy_projectile_type": projectile_type,
		"retail_left": top_left_x,
		"retail_top": top_left_y,
		"top_left_x": top_left_x,
		"top_left_y": top_left_y,
		"x": Rng._float32(top_left_x + 16.0),
		"y": Rng._float32(top_left_y + 16.0),
		"velocity_x": velocity_x,
		"velocity_y": velocity_y,
		"velocity_is_tick_scaled": true,
		"width": 32,
		"height": 32,
		"resource_slot_id": 1,
		"enemy_sheet_id": "alien_big1_1",
		"mask_id": "alien_big1_1",
		"source_rect": source_rect,
		"animation_frame": animation_frame,
		"animation_period": animation_period,
		"animation_countdown": animation_countdown,
		"animation_frame_max": frame_max,
		"animation_source_unclamped": projectile_type == 15,
		"broadphase_inset_x": inset,
		"broadphase_inset_y": inset,
		"broadphase_width": extent,
		"broadphase_height": extent,
		"retire_top_left_y_strictly_above": 600,
		"damage_fp": Simulation.FP_ONE,
		"damage_policy": "one_armour_step",
		"consume_on_player_hit": true,
	})


func _fire_public_projectile(simulation) -> Dictionary:
	_expect(
		simulation.set_input(0, Simulation.ACTION_FIRE),
		"the public fire input should be accepted for the boss fixture"
	)
	simulation.step()
	simulation.set_input(0, 0)
	for projectile_value in simulation._projectiles:
		var projectile := projectile_value as Dictionary
		if String(projectile.get("owner_kind", "")) == "player":
			return projectile
	_expect(false, "public fire input should allocate a player projectile")
	return {}


func _new_boss(config: Dictionary):
	var simulation := Simulation.new()
	_expect(
		simulation.configure(config),
		"level-25 simulation should configure: %s" % simulation.get_last_error()
	)
	return simulation if simulation._configured else null


func _boss_config(
	mode: String,
	balance: String,
	seed: int,
	seats: Array = []
) -> Dictionary:
	return {
		"mode": mode,
		"difficulty": "normal",
		"coop_balance": balance,
		"collision_mode": "simple",
		"seed": seed,
		"start_level": 25,
		"end_level": 25,
		"record_replay": true,
		"seats": seats,
	}


func _event_kinds(snapshot: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for event_value in snapshot.get("events", []):
		result.append(String((event_value as Dictionary).get("kind", "")))
	return result


func _snapshot_projectile(snapshot: Dictionary, projectile_id: int) -> Dictionary:
	for projectile_value in snapshot.get("projectiles", []):
		var projectile := projectile_value as Dictionary
		if int(projectile.get("id", 0)) == projectile_id:
			return projectile
	return {}


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

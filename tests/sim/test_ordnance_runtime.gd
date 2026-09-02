extends SceneTree

const Simulation := preload("res://src/sim/game_simulation.gd")
const Rng := preload("res://src/sim/deterministic_rng.gd")

const ROCKET_PACK_ID := 18
const ALIEN_LOCK_ID := 19
const ROCKET_DAMAGE_FP := 200 * Simulation.FP_ONE

var _failures: Array[String] = []
var _contract: Dictionary = {}


func _initialize() -> void:
	_contract = _load_contract()
	_test_contract_is_release_ready()
	_test_rocket_pack_purchase_grant_clamp_and_rejection()
	_test_legacy_catalog_ordnance_is_disabled()
	_test_release_armed_secondary_input()
	_test_public_step_and_replay_path()
	_test_pool_and_target_failure_atomicity()
	_test_weighted_draw_reservation_and_spawn_order()
	_test_pixel_collision_damage_and_accuracy_accounting()
	_test_boss_damage_policy()
	_test_expiry_releases_target_and_consumes_effect_rng()
	_test_alien_lock_targeting_equivalence_and_lifecycle()
	_test_coop_physical_seat_order()
	_test_final_kill_allocation_flag()
	if _failures.is_empty():
		print("ORDNANCE RUNTIME TESTS PASSED")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _load_contract() -> Dictionary:
	var file := FileAccess.open("res://content/ordnance.json", FileAccess.READ)
	if file == null:
		_expect(false, "content/ordnance.json should be readable")
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		_expect(false, "content/ordnance.json should parse as an object")
		return {}
	return parsed as Dictionary


func _test_contract_is_release_ready() -> void:
	if _contract.is_empty():
		return
	var missile: Dictionary = _contract.get("missile_runtime", {})
	var integration: Dictionary = _contract.get("integration", {})
	var spawn: Dictionary = missile.get("spawn", {})
	var record: Dictionary = spawn.get("record", {})
	var rendering: Dictionary = missile.get("rendering", {})
	var atlas: Dictionary = rendering.get("atlas", {})
	var frame_size := atlas.get("frame_size", []) as Array
	_expect(
		int(_contract.get("version", 0)) == 1
		and String(_contract.get("schema", "")) == "warblade.ordnance.v1"
		and bool((_contract.get("source", {}) as Dictionary).get(
			"exact_trace_complete",
			false
		))
		and bool(integration.get("exact_trace_complete", false)),
		"the runtime suite must be backed by the complete executable ordnance trace"
	)
	_expect(
		int((missile.get("pool", {}) as Dictionary).get("capacity", 0)) == 100
		and int(record.get("damage_offset_0x14", 0)) == 200
		and frame_size.size() == 2
		and int(frame_size[0]) == 24
		and int(frame_size[1]) == 24,
		"the golden suite should pin the 100-record pool, 200 damage, and 24px frames"
	)


func _test_rocket_pack_purchase_grant_clamp_and_rejection() -> void:
	var simulation = _new_sim("solo", 26001)
	if simulation == null:
		return
	_prepare_shop(simulation, 0, 100, 25000)
	var progression: Dictionary = simulation._progression_for_seat(0)
	progression.rockets = 0
	var first: Dictionary = simulation.submit_shop_purchase(0, ROCKET_PACK_ID, 18001)
	_expect(
		bool(first.get("accepted", false))
		and int(progression.rockets) == 10
		and int(progression.money) == 20000,
		"Rocket Pack should grant ten rockets and charge its price exactly once"
	)


	progression.rockets = 41
	var clamped: Dictionary = simulation.submit_shop_purchase(0, ROCKET_PACK_ID, 18002)
	_expect(
		bool(clamped.get("accepted", false))
		and int(progression.rockets) == 50
		and int(progression.money) == 15000,
		"a pre-count below fifty should accept and clamp the ten-rocket grant to fifty"
	)

	var money_before := int(progression.money)
	var rejected: Dictionary = simulation.submit_shop_purchase(0, ROCKET_PACK_ID, 18003)
	_expect(
		not bool(rejected.get("accepted", true))
		and String(rejected.get("reason", "")) == "upgrade_at_cap"
		and int(progression.rockets) == 50
		and int(progression.money) == money_before,
		"a pre-count of fifty should reject without changing inventory or cash"
	)


func _test_legacy_catalog_ordnance_is_disabled() -> void:
	var simulation = _new_sim("solo", 26016)
	if simulation == null:
		return
	_prepare_shop(simulation, 0, 100, 50000)
	simulation._ordnance_contract.clear()
	var progression: Dictionary = simulation._progression_for_seat(0)
	var rocket_item := simulation._shop_by_id[ROCKET_PACK_ID] as Dictionary
	var lock_item := simulation._shop_by_id[ALIEN_LOCK_ID] as Dictionary
	_expect(
		not simulation._shop_item_is_unlocked(rocket_item, 0)
		and not simulation._shop_item_is_unlocked(lock_item, 0)
		and not simulation._can_apply_shop_effect(rocket_item, 0)
		and not simulation._can_apply_shop_effect(lock_item, 0),
		"legacy catalogs should neither advertise nor apply contractless ordnance upgrades"
	)
	var money_before := int(progression.money)
	var rejected: Dictionary = simulation.submit_shop_purchase(0, ROCKET_PACK_ID, 18100)
	_expect(
		not bool(rejected.get("accepted", true))
		and int(progression.get("rockets", 0)) == 0
		and int(progression.money) == money_before,
		"a legacy catalog should not charge for unusable Rocket Pack inventory"
	)
	progression.upgrades.alien_lock = 1
	simulation._enemies = [_captured_enemy(18101, 0, 0)]
	simulation._apply_alien_lock_transition_policy("legacy_transition")
	_expect(
		simulation._enemies.is_empty(),
		"legacy transitions should not retain captives without the traced ordnance contract"
	)


func _test_release_armed_secondary_input() -> void:
	var simulation = _new_sim("solo", 26002)
	if simulation == null:
		return
	var progression: Dictionary = simulation._progression_for_seat(0)
	progression.rockets = 3
	simulation._enemies = [_target_enemy(6001, 6, 400, 300)]
	simulation._events.clear()
	_dispatch_secondary(simulation, 0, true)
	_expect(
		_rockets(simulation).size() == 1
		and int(progression.rockets) == 2
		and not bool(simulation._secondary_rocket_armed[0]),
		"an armed secondary press should allocate once, consume one rocket, and clear the latch"
	)
	_dispatch_secondary(simulation, 0, true)
	_expect(
		_rockets(simulation).size() == 1 and int(progression.rockets) == 2,
		"holding secondary should not allocate a second missile"
	)
	_dispatch_secondary(simulation, 0, false)
	_expect(
		bool(simulation._secondary_rocket_armed[0]),
		"a released secondary action should re-arm the physical-seat latch"
	)
	# State 13 does not reserve, so the same live record remains eligible.
	(simulation._enemies[0] as Dictionary).behavior_state_id = 13
	(simulation._enemies[0] as Dictionary).rocket_reserved = false
	_dispatch_secondary(simulation, 0, true)
	_expect(
		_rockets(simulation).size() == 2 and int(progression.rockets) == 1,
		"the next press after release should allocate exactly one more missile"
	)


func _test_public_step_and_replay_path() -> void:
	var config := {
		"mode": "solo",
		"difficulty": "normal",
		"collision_mode": "simple",
		"seed": 26015,
		"start_level": 26,
		"end_level": 30,
		"record_replay": true,
		"starting_rockets": 2,
	}
	var simulation := Simulation.new()
	var twin := Simulation.new()
	_expect(
		simulation.configure(config) and twin.configure(config),
		"public ordnance replay fixtures should configure"
	)
	if not simulation._configured or not twin._configured:
		return
	_expect(
		simulation.set_input(0, Simulation.ACTION_SECONDARY)
		and twin.set_input(0, Simulation.ACTION_SECONDARY),
		"public secondary input should be accepted by both deterministic fixtures"
	)
	var snapshot: Dictionary = simulation.step()
	var twin_snapshot: Dictionary = twin.step()
	var public_rockets := (snapshot.get("projectiles", []) as Array).filter(
		func(projectile: Dictionary) -> bool:
			return String(projectile.get("projectile_kind", "")) == "rocket_missile"
	)
	var replay: Dictionary = simulation.get_replay()
	var frames := replay.get("frames", []) as Array
	_expect(
		public_rockets.size() == 1
		and int((snapshot.get("shared", {}) as Dictionary).get("rockets", 0)) == 1
		and not frames.is_empty()
		and (int((frames[-1] as Dictionary).get("inputs", [0])[0])
			& Simulation.ACTION_SECONDARY) != 0,
		"one public step should transport secondary input, spend ammo, publish the missile, and record the replay mask"
	)
	_expect(
		snapshot == twin_snapshot
		and simulation.state_hash() == twin.state_hash()
		and String((frames[-1] as Dictionary).get("state_hash", ""))
		== simulation.state_hash(),
		"identical public secondary input should preserve local snapshot, replay, and hash parity"
	)


func _test_pool_and_target_failure_atomicity() -> void:
	var no_target = _new_sim("solo", 26003)
	if no_target != null:
		var progression: Dictionary = no_target._progression_for_seat(0)
		progression.rockets = 2
		no_target._enemies.clear()
		var draws_before := int(no_target._rng.snapshot().draw_count)
		var events_before: int = no_target._events.size()
		_dispatch_secondary(no_target, 0, true)
		_expect(
			_rockets(no_target).is_empty()
			and int(progression.rockets) == 2
			and int(no_target._rng.snapshot().draw_count) == draws_before
			and no_target._events.size() == events_before
			and not bool(no_target._secondary_rocket_armed[0]),
			"no-target failure should consume the edge but not ammo, RNG, pool, or sound"
		)
		no_target._enemies = [_target_enemy(6002, 13, 400, 300)]
		_dispatch_secondary(no_target, 0, true)
		_expect(
			_rockets(no_target).is_empty(),
			"a failed press should require a release before retrying"
		)
		_dispatch_secondary(no_target, 0, false)
		_dispatch_secondary(no_target, 0, true)
		_expect(
			_rockets(no_target).size() == 1 and int(progression.rockets) == 1,
			"release should permit a later successful retry"
		)

	var full = _new_sim("solo", 26004)
	if full == null:
		return
	var full_progression: Dictionary = full._progression_for_seat(0)
	full_progression.rockets = 2
	full._enemies = [_target_enemy(6003, 6, 400, 300)]
	full._projectiles = _full_player_pool()
	var full_draws_before := int(full._rng.snapshot().draw_count)
	_dispatch_secondary(full, 0, true)
	_expect(
		_rockets(full).is_empty()
		and int(full_progression.rockets) == 2
		and int(full._rng.snapshot().draw_count) == full_draws_before
		and not bool((full._enemies[0] as Dictionary).rocket_reserved),
		"a full physical pool should stop before target scan, reservation, RNG, ammo, and sound"
	)


func _test_weighted_draw_reservation_and_spawn_order() -> void:
	var simulation = _new_sim("solo", 26005)
	if simulation == null:
		return
	var progression: Dictionary = simulation._progression_for_seat(0)
	progression.rockets = 5
	var candidates := [
		_target_enemy(6100, 6, 300, 250),
		_target_enemy(6101, 13, 400, 250),
		_target_enemy(6102, 7, 500, 250),
	]
	simulation._enemies = candidates
	var rng_before: Dictionary = simulation._rng.snapshot()
	var oracle := Rng.new()
	oracle.restore(rng_before)
	var selected_bucket := oracle.next_range(25)
	var expected_index := 0 if selected_bucket < 8 else (1 if selected_bucket < 24 else 2)
	var expected_period := oracle.next_range(3) + 4
	var expected_countdown := oracle.next_range(3) + 3
	var player := simulation._players[0] as Dictionary
	_dispatch_secondary(simulation, 0, true)
	var rockets := _rockets(simulation)
	if rockets.is_empty():
		_expect(false, "the weighted target fixture should spawn one rocket")
		return
	var rocket := rockets[0] as Dictionary
	var selected := candidates[expected_index] as Dictionary
	_expect(
		int(rocket.target_entity_id) == int(selected.id)
		and bool(rocket.target_reserved) == (int(selected.behavior_state_id) not in [13, 18])
		and bool(selected.rocket_reserved) == bool(rocket.target_reserved),
		"one weighted root draw should select the exact candidate and apply its state reservation class"
	)
	_expect(
		int(simulation._rng.snapshot().draw_count) == int(rng_before.draw_count) + 3
		and int(rocket.animation_period_fp) == expected_period * Simulation.FP_ONE
		and int(rocket.animation_countdown_fp) == expected_countdown * Simulation.FP_ONE,
		"successful spawn should draw target, animation period, then animation countdown"
	)
	_expect(
		int(rocket.player_slot) == 0
		and int(rocket.owner_id) == 0
		and int(rocket.damage_fp) == ROCKET_DAMAGE_FP
		and int(rocket.width) == 24
		and int(rocket.height) == 24
		and int(rocket.x_fp) == int(player.x_fp) + Simulation.FP_ONE
		and int(rocket.y_fp) == int(player.y_fp) - 10 * Simulation.FP_ONE,
		"spawn should claim ascending slot zero and preserve the traced owner, damage, size, and origin offsets"
	)
	_expect(
		String(rocket.projectile_kind) == "rocket_missile"
		and String(rocket.sprite_sheet_id) == "rocket"
		and rocket.source_rect == [0, 0, 24, 24]
		and String(rocket.mask_id) == "rocket",
		"the authoritative projectile should publish canonical rocket presentation and HMA identity"
	)
	var public_rocket := _public_projectile_by_id(
		simulation.get_snapshot(),
		int(rocket.id)
	)
	_expect(
		String(public_rocket.get("projectile_kind", "")) == "rocket_missile"
		and String(public_rocket.get("sprite_sheet_id", "")) == "rocket"
		and public_rocket.get("source_rect", []) == [0, 0, 24, 24],
		"snapshot v9 should retain canonical projectile kind, sheet, and source rectangle"
	)
	_expect(
		_event_count_with_key(simulation._events, "sound_cue", "rocket") == 1,
		"successful allocation should emit the rocket sound exactly once"
	)


func _test_pixel_collision_damage_and_accuracy_accounting() -> void:
	var simulation = _new_sim("solo", 26006, "pixel")
	if simulation == null:
		return
	var progression: Dictionary = simulation._progression_for_seat(0)
	progression.rockets = 2
	var target := _target_enemy(6200, 13, 400, 300)
	target.health_fp = ROCKET_DAMAGE_FP
	target.max_health_fp = ROCKET_DAMAGE_FP
	simulation._enemies = [target]
	var stats: Dictionary = simulation._profile_stats_by_seat[0]
	var denominator_before := int(stats.projectile_objects_fired)
	var hits_before := int(stats.successful_hits)
	_dispatch_secondary(simulation, 0, true)
	var rockets := _rockets(simulation)
	if rockets.is_empty():
		_expect(false, "the pixel-collision fixture should spawn one rocket")
		return
	var rocket := rockets[0] as Dictionary
	target.x_fp = int(rocket.x_fp)
	target.y_fp = int(rocket.y_fp)
	target.collision_x_fp = int(rocket.x_fp)
	target.collision_y_fp = int(rocket.y_fp)
	simulation._update_enemy_mask_rect(target)
	simulation._resolve_rocket_ordinary_collision(rocket, target)
	_expect(
		bool(target.dead)
		and bool(rocket.expired)
		and not bool(target.rocket_reserved)
		and int(rocket.mask_source_width) == 24
		and int(rocket.mask_source_height) == 24,
		"the 24x24 rocket HMA should confirm an opaque overlap, deal 200 damage, and release the target"
	)
	_expect(
		int(stats.projectile_objects_fired) == denominator_before
		and denominator_before == 0
		and int(stats.successful_hits) == hits_before + 1,
		"a rocket hit should increment the shared hit numerator without entering the ordinary-shot denominator"
	)


func _test_boss_damage_policy() -> void:
	var simulation = _new_sim("solo", 26007, "simple", 25)
	if simulation == null:
		return
	var health_before := float(simulation.get_snapshot().boss.health)
	var rocket := _manual_rocket(0, 0, 7001)
	simulation._retail_big_boss._x = 400.0
	simulation._retail_big_boss._y = 180.0
	rocket.x_fp = 400 * Simulation.FP_ONE
	rocket.y_fp = 240 * Simulation.FP_ONE
	simulation._projectiles = [rocket]
	var shots_before := int(simulation._profile_stats_by_seat[0].projectile_objects_fired)
	var hits_before := int(simulation._profile_stats_by_seat[0].successful_hits)
	simulation._resolve_boss_player_projectile_collisions()
	var health_after := float(simulation.get_snapshot().boss.health)
	_expect(
		health_after == health_before - 20.0
		and bool(rocket.expired),
		"state 13 should apply max(1, 200/10) = 20 rocket damage and consume the missile"
	)
	_expect(
		int(simulation._profile_stats_by_seat[0].projectile_objects_fired) == shots_before
		and int(simulation._profile_stats_by_seat[0].successful_hits) == hits_before + 1,
		"boss rocket impact should count one hit but no ordinary projectile object"
	)


func _test_expiry_releases_target_and_consumes_effect_rng() -> void:
	var simulation = _new_sim("solo", 26008)
	if simulation == null:
		return
	var target := _target_enemy(6300, 6, 400, 300)
	target.rocket_reserved = true
	simulation._enemies = [target]
	var rocket := _manual_rocket(0, int(target.id), 7002)
	rocket.target_reserved = true
	rocket.lifetime_fp = 1
	simulation._projectiles = [rocket]
	var draws_before := int(simulation._rng.snapshot().draw_count)
	simulation._events.clear()
	simulation._update_rocket_missiles()
	_expect(
		bool(rocket.expired)
		and not bool(target.rocket_reserved)
		and int(simulation._rng.snapshot().draw_count) == draws_before + 5,
		"lifetime expiry should release the stored reservation before the five ordered effect draws"
	)
	_expect(
		_event_count(simulation._events, "rocket_expired") == 1,
		"expiry should publish one deterministic rocket-expired effect event"
	)


func _test_alien_lock_targeting_equivalence_and_lifecycle() -> void:
	var unlocked = _new_sim("solo", 26009)
	var locked = _new_sim("solo", 26009)
	if unlocked == null or locked == null:
		return
	for simulation in [unlocked, locked]:
		var progression: Dictionary = simulation._progression_for_seat(0)
		progression.rockets = 2
		simulation._enemies = [
			_target_enemy(6400, 6, 350, 250),
			_target_enemy(6401, 13, 450, 250),
		]
	locked._progression_for_seat(0).upgrades.alien_lock = 1
	_dispatch_secondary(unlocked, 0, true)
	_dispatch_secondary(locked, 0, true)
	if _rockets(unlocked).is_empty() or _rockets(locked).is_empty():
		_expect(false, "Alien Lock equivalence fixtures should each spawn one missile")
		return
	var unlocked_rocket := _rockets(unlocked)[0] as Dictionary
	var locked_rocket := _rockets(locked)[0] as Dictionary
	_expect(
		int(unlocked_rocket.target_entity_id) == int(locked_rocket.target_entity_id)
		and bool(unlocked_rocket.target_reserved) == bool(locked_rocket.target_reserved)
		and unlocked._rng.snapshot() == locked._rng.snapshot(),
		"Alien Lock on/off must not alter missile candidates, weights, reservation, or RNG"
	)

	var retained = _new_sim("solo", 26010)
	var cleared = _new_sim("solo", 26010)
	if retained == null or cleared == null:
		return
	retained._progression_for_seat(0).upgrades.alien_lock = 1
	cleared._progression_for_seat(0).upgrades.alien_lock = 0
	retained._enemies = [_captured_enemy(6450, 0, 0)]
	cleared._enemies = [_captured_enemy(6450, 0, 0)]
	retained._begin_level(27)
	cleared._begin_level(27)
	_expect(
		_has_captive(retained, 0) and not _has_captive(cleared, 0),
		"Alien Lock should preserve both captive identity and state across level transition only when owned"
	)
	var player := retained._players[0] as Dictionary
	retained._damage_player(player, Simulation.FP_ONE)
	_expect(
		int(retained._progression_for_seat(0).upgrades.get("alien_lock", 0)) == 0,
		"ordinary player death should clear Alien Lock even though Warp preserves it"
	)


func _test_coop_physical_seat_order() -> void:
	for mode in ["coop"]:
		var simulation = _new_sim(mode, 26011)
		if simulation == null:
			continue
		for seat_id in range(2):
			simulation._progression_for_seat(seat_id).rockets = 4
		# State 13 deliberately remains unreserved, allowing both physical seats
		# to select the same target in one deterministic seat-order dispatch.
		simulation._enemies = [_target_enemy(6500, 13, 400, 250)]
		_dispatch_secondary(simulation, 0, true)
		_dispatch_secondary(simulation, 1, true)
		var rockets := _rockets(simulation)
		_expect(
			rockets.size() == 2
			and int((rockets[0] as Dictionary).owner_id) == 0
			and int((rockets[0] as Dictionary).player_slot) == 0
			and int((rockets[1] as Dictionary).owner_id) == 1
			and int((rockets[1] as Dictionary).player_slot) == 1,
			"%s secondary dispatch should remain physical-seat 0 then 1 in ascending shared pool slots"
			% mode
		)
		_expect(
			int(simulation._progression_for_seat(0).rockets) == 2,
			"co-op should consume twice from its shared progression in stable seat order"
		)


func _test_final_kill_allocation_flag() -> void:
	var failed = _new_sim("solo", 26012)
	if failed != null:
		var failed_progression: Dictionary = failed._progression_for_seat(0)
		failed_progression.rockets = 5
		failed._enemies.clear()
		_dispatch_secondary(failed, 0, true)
		failed._alien_projectile_processed_this_level = true
		failed._award_final_kill_rockets(0)
		_expect(
			int(failed_progression.rockets) == 15,
			"a failed secondary press must not set the allocation flag that suppresses final-kill rockets"
		)

	var primary = _new_sim("solo", 26013)
	if primary != null:
		var primary_progression: Dictionary = primary._progression_for_seat(0)
		primary_progression.rockets = 5
		primary._fire_player_weapon(primary._players[0])
		primary._alien_projectile_processed_this_level = true
		primary._award_final_kill_rockets(0)
		_expect(
			int(primary_progression.rockets) == 5,
			"a successful primary allocation should suppress the final-kill inventory reward"
		)

	var rocket = _new_sim("solo", 26014)
	if rocket != null:
		var rocket_progression: Dictionary = rocket._progression_for_seat(0)
		rocket_progression.rockets = 5
		rocket._enemies = [_target_enemy(6600, 13, 400, 250)]
		_dispatch_secondary(rocket, 0, true)
		rocket._alien_projectile_processed_this_level = true
		rocket._award_final_kill_rockets(0)
		_expect(
			int(rocket_progression.rockets) == 4,
			"a successful missile allocation should also suppress final-kill rockets after consuming one ammo"
		)


func _new_sim(
	mode: String,
	seed: int,
	collision_mode: String = "simple",
	start_level: int = 26
):
	var simulation := Simulation.new()
	var configured := simulation.configure({
		"mode": mode,
		"difficulty": "normal",
		"collision_mode": collision_mode,
		"seed": seed,
		"start_level": start_level,
		"end_level": 30,
		"record_replay": false,
		"starting_rockets": 0,
	})
	_expect(
		configured,
		"%s level-%d ordnance fixture should configure: %s"
		% [mode, start_level, simulation.get_last_error()]
	)
	return simulation if configured else null


func _prepare_shop(simulation, seat_id: int, accuracy: int, money: int) -> void:
	simulation._phase = Simulation.PHASE_SHOP
	simulation._turn_seat = seat_id
	simulation._shop_warp_until_tick = 0
	simulation._profile_stats_by_seat[seat_id].best_hit_percent_above_level_25 = accuracy
	simulation._progression_for_seat(seat_id).money = money


func _dispatch_secondary(simulation, seat_id: int, pressed: bool) -> void:
	_expect(
		simulation.set_input(
			seat_id,
			Simulation.ACTION_SECONDARY if pressed else 0
		),
		"secondary fixture input should be accepted for seat %d" % seat_id
	)
	simulation._try_fire_rocket(simulation._players[seat_id])


func _target_enemy(
	entity_id: int,
	state_id: int,
	x: int,
	y: int
) -> Dictionary:
	return {
		"id": entity_id,
		"active": true,
		"dead": false,
		"authored_lvd": false,
		"authored_state": "hold",
		"behavior_state_id": state_id,
		"targetability_scalar": 1.0,
		"targetability_fp": Simulation.FP_ONE,
		"rocket_reserved": false,
		"x_fp": x * Simulation.FP_ONE,
		"y_fp": y * Simulation.FP_ONE,
		"width": 32,
		"height": 32,
		"health_fp": ROCKET_DAMAGE_FP,
		"max_health_fp": ROCKET_DAMAGE_FP,
		"score": 0,
		"cash": 0,
		"sprite": "alien001",
		"mask_id": "alien001",
	}


func _captured_enemy(entity_id: int, owner_seat: int, side: int) -> Dictionary:
	var enemy := _target_enemy(entity_id, 8, 400, 530)
	enemy.authored_state = "captured"
	enemy.captured_owner_seat = owner_seat
	enemy.captured_side = side
	enemy.captured_latched = true
	enemy.capture_offset_fp = (-36 if side == 0 else 36) * Simulation.FP_ONE
	return enemy


func _manual_rocket(owner_id: int, target_entity_id: int, entity_id: int) -> Dictionary:
	return {
		"id": entity_id,
		"owner_kind": "player",
		"owner_id": owner_id,
		"player_slot": 0,
		"projectile_kind": "rocket_missile",
		"sprite_sheet_id": "rocket",
		"target_entity_id": target_entity_id,
		"target_kind": "enemy",
		"target_reserved": target_entity_id > 0,
		"heading": 1,
		"lifetime_fp": 300 * Simulation.FP_ONE,
		"animation_row": 0,
		"animation_period_fp": 4 * Simulation.FP_ONE,
		"animation_countdown_fp": 3 * Simulation.FP_ONE,
		"steering_period_fp": Simulation.FP_ONE,
		"steering_countdown_fp": Simulation.FP_ONE,
		"x_fp": 400 * Simulation.FP_ONE,
		"y_fp": 300 * Simulation.FP_ONE,
		"velocity_x_fp": 0,
		"velocity_y_fp": -10 * Simulation.FP_ONE,
		"width": 24,
		"height": 24,
		"damage_fp": ROCKET_DAMAGE_FP,
		"prototype_id": 200,
		"capacity_contribution": 0,
		"source_rect": [0, 0, 24, 24],
		"mask_id": "rocket",
		"mask_required": true,
		"mask_source_x": 0,
		"mask_source_y": 0,
		"mask_source_width": 24,
		"mask_source_height": 24,
		"spawn_tick": 0,
		"expired": false,
	}


func _full_player_pool() -> Array:
	var result: Array = []
	for slot_index in range(Simulation.PLAYER_PROJECTILE_SLOT_COUNT):
		var projectile := _manual_rocket(0, 0, 8000 + slot_index)
		projectile.projectile_kind = "primary"
		projectile.sprite_sheet_id = "weapons_big"
		projectile.mask_id = "weapons_big"
		projectile.player_slot = slot_index
		result.append(projectile)
	return result


func _rockets(simulation) -> Array:
	return simulation._projectiles.filter(func(projectile: Dictionary) -> bool:
		return String(projectile.get("projectile_kind", "")) == "rocket_missile"
	)


func _public_projectile_by_id(snapshot: Dictionary, entity_id: int) -> Dictionary:
	for projectile_value in snapshot.get("projectiles", []):
		var projectile := projectile_value as Dictionary
		if int(projectile.get("id", 0)) == entity_id:
			return projectile
	return {}


func _has_captive(simulation, owner_seat: int) -> bool:
	for enemy_value in simulation._enemies:
		var enemy := enemy_value as Dictionary
		if (
			int(enemy.get("behavior_state_id", 0)) == 8
			and int(enemy.get("captured_owner_seat", -1)) == owner_seat
		):
			return true
	return false


func _event_count(events: Array, kind: String) -> int:
	var count := 0
	for event_value in events:
		var event := event_value as Dictionary
		if String(event.get("type", event.get("kind", ""))) == kind:
			count += 1
	return count


func _event_count_with_key(events: Array, kind: String, key: String) -> int:
	var count := 0
	for event_value in events:
		var event := event_value as Dictionary
		if (
			String(event.get("type", event.get("kind", ""))) == kind
			and String(event.get("key", "")) == key
		):
			count += 1
	return count


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

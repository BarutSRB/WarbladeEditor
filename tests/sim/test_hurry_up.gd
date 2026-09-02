extends SceneTree

## Contract tests for the retail hurry-up secret ships, see
## docs/evidence/HURRY_UP_SECRET_SHIPS.md. Every number asserted here is read
## back from pinned retail instruction bytes by tools/hurry_up_extract.py.

const Simulation := preload("res://src/sim/game_simulation.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_deadline_arms_from_difficulty()
	_test_no_spawn_before_the_deadline()
	_test_spawn_creates_the_mothership()
	_test_entry_sides_are_both_reachable()
	_test_mothership_departs_and_rearms()
	_test_mothership_kill_records_secret_three()
	_test_rare_ship_fires_on_the_eighth_wave()
	_test_rare_ship_kill_records_secret_six()
	_test_time_trial_never_spawns()
	_test_pixel_masks_decide_hurry_up_hits()
	_test_planet_sweep_emits_homing_debris()
	_test_state_survives_a_snapshot_round_trip()
	_test_money_sucker_trigger_guards()
	_test_money_sucker_patrols_and_drains_cash()
	_test_money_sucker_kill_raises_health_base_b()
	_test_guard_trigger_guards()
	_test_guard_fires_a_beam_column_and_holds_position()
	_test_guard_kill_raises_health_base_d()
	_test_secret_ship_state_survives_a_shop_save()
	if _failures.is_empty():
		print("HURRY UP TESTS PASSED")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	print("HURRY UP TESTS FAILED: %d" % _failures.size())
	quit(1)


func _configure(difficulty: String = "normal", mode: String = "solo") -> Object:
	var simulation := Simulation.new()
	if not simulation.configure({
		"mode": mode,
		"difficulty": difficulty,
		"collision_mode": "simple",
		"seed": 90210,
		"starting_lives": 9,
		"record_replay": false,
		"seats": [{
			"seat": 0,
			"profile_id": "hurry_up_test",
			"display_name": "PILOT",
			"secret_session_earned": _zero_secret_flags(),
			"local": true,
		}],
	}):
		_failures.append(
			"hurry-up simulation must configure: %s" % simulation.get_last_error()
		)
	return simulation


func _zero_secret_flags() -> Array:
	var flags: Array = []
	for _index in range(30):
		flags.append(0)
	return flags


## Drives the spawner directly so a test does not have to play a level long
## enough for the real deadline to elapse.
func _force_hurry_up_wave(simulation: Object) -> Array:
	simulation._hurry_up_deadline_ms = -1
	simulation._step_hurry_up_spawner()
	var spawned: Array = []
	for enemy_value in simulation._enemies:
		var enemy: Dictionary = enemy_value
		if not bool(enemy.get("dead", false)) and simulation._is_hurry_up_ship(enemy):
			spawned.append(enemy)
	return spawned


func _test_deadline_arms_from_difficulty() -> void:
	for entry in [
		["easy", 50000],
		["normal", 40000],
		["hard", 30000],
		["ace", 20000],
	]:
		var simulation := _configure(String(entry[0]))
		_expect(
			int(simulation._hurry_up_interval_ms) == int(entry[1]),
			"%s arms the traced %d ms hurry-up interval" % [entry[0], int(entry[1])]
		)
		_expect(
			int(simulation._hurry_up_deadline_ms) == int(entry[1]),
			"%s arms the deadline at the interval from tick zero" % entry[0]
		)


func _test_no_spawn_before_the_deadline() -> void:
	var simulation := _configure()
	var rng_before: Dictionary = simulation._rng.snapshot()
	for _tick in range(120):
		simulation.step()
	for enemy_value in simulation._enemies:
		_expect(
			not simulation._is_hurry_up_ship(enemy_value as Dictionary),
			"no hurry-up ship exists before the deadline elapses"
		)
	# The guards run before any draw, so a suppressed frame must not move the
	# stream on its own. Stepping the level does consume draws, so compare the
	# spawner in isolation instead.
	var idle := _configure()
	idle._hurry_up_deadline_ms = 1_000_000
	rng_before = idle._rng.snapshot()
	idle._step_hurry_up_spawner()
	_expect(
		idle._rng.snapshot() == rng_before,
		"a suppressed hurry-up frame consumes no random draws"
	)


func _test_spawn_creates_the_mothership() -> void:
	var simulation := _configure()
	var total_before := int(simulation._level_total_entities)
	var spawned := _force_hurry_up_wave(simulation)
	_expect(spawned.size() == 1, "the first wave spawns exactly one ship")
	if spawned.is_empty():
		return
	var mothership: Dictionary = spawned[0]
	_expect(
		int(mothership.behavior_state_id) == 9
		and String(mothership.sprite) == "mothership2",
		"the wave ship is the state-9 mothership"
	)
	_expect(int(mothership.score) == 2500, "the mothership is worth 2,500")
	_expect(
		int(mothership.width) == 96 and int(mothership.height) == 57,
		"the mothership frame is the traced 96x57"
	)
	_expect(
		int(mothership.collision_width) == 96
		and int(mothership.collision_height) == 57,
		"the mothership hitbox is the traced 96x57"
	)
	_expect(
		int(mothership.health_fp) == 16 * Simulation.FP_ONE,
		"normal difficulty gives the mothership the traced base-A health"
	)
	_expect(
		int(mothership.y_fp) == 20 * Simulation.FP_ONE + 57 * Simulation.FP_ONE / 2,
		"the mothership spawns on the traced y = 20 top edge"
	)
	_expect(
		int(simulation._level_total_entities) == total_before + 1,
		"a hurry-up ship raises the level object total"
	)
	_expect(
		int(simulation._hurry_up_interval_ms) == 10000
		and int(simulation._hurry_up_deadline_ms)
		== simulation._simulation_milliseconds() + 10000,
		"the spawner tail re-arms on the flat ten-second interval"
	)
	var banner_events := 0
	var voice_events := 0
	for event_value in simulation._events:
		var event: Dictionary = event_value
		if String(event.get("type", "")) == "hurry_up_banner":
			banner_events += 1
			_expect(
				String(event.get("text", "")) == "H U R R Y   U P"
				and int(event.get("duration_ms", 0)) == 1000,
				"the banner carries the traced text and one-second life"
			)
		elif (
			String(event.get("type", "")) == "voice_cue"
			and String(event.get("cause", "")) == "hurry_up"
		):
			voice_events += 1
			_expect(
				String(event.get("voice_key", "")) in ["hurryup1", "hurryup2"],
				"the wave plays one of the two hurry-up voice clips"
			)
	_expect(banner_events == 1, "the wave raises exactly one banner")
	_expect(voice_events == 1, "the wave plays exactly one voice clip")


func _test_entry_sides_are_both_reachable() -> void:
	var seen_right := false
	var seen_left := false
	for seed_value in range(24):
		var simulation := Simulation.new()
		if not simulation.configure({
			"mode": "solo",
			"difficulty": "normal",
			"collision_mode": "simple",
			"seed": 1000 + seed_value,
			"record_replay": false,
		}):
			continue
		var spawned := _force_hurry_up_wave(simulation)
		if spawned.is_empty():
			continue
		var mothership: Dictionary = spawned[0]
		if bool(mothership.hurry_up_enters_from_right):
			seen_right = true
			_expect(
				int(mothership.x_fp)
				== 800 * Simulation.FP_ONE + 96 * Simulation.FP_ONE / 2,
				"a right entry starts on the surface edge"
			)
		else:
			seen_left = true
			_expect(
				int(mothership.x_fp)
				== -288 * Simulation.FP_ONE + 96 * Simulation.FP_ONE / 2,
				"a left entry starts a full sheet width off-surface"
			)
	_expect(seen_right and seen_left, "both traced entry sides are reachable")


func _test_mothership_departs_and_rearms() -> void:
	var simulation := _configure()
	var spawned := _force_hurry_up_wave(simulation)
	if spawned.is_empty():
		_failures.append("the departure test needs a spawned mothership")
		return
	var mothership: Dictionary = spawned[0]
	var escaped_before := int(simulation._level_escaped_entities)
	# Park it one step short of the traced despawn edge on its own travel side.
	if bool(mothership.hurry_up_enters_from_right):
		mothership.x_fp = -70 * Simulation.FP_ONE + 96 * Simulation.FP_ONE / 2
	else:
		mothership.x_fp = (
			(800 + 70) * Simulation.FP_ONE + 96 * Simulation.FP_ONE / 2
		)
	simulation._hurry_up_interval_ms = 40000
	simulation._update_hurry_up_mothership(mothership)
	_expect(bool(mothership.dead), "the mothership leaves at the traced edge")
	_expect(
		int(simulation._level_escaped_entities) == escaped_before + 1,
		"a departing mothership counts as an escaped level object"
	)
	_expect(
		int(simulation._hurry_up_deadline_ms)
		== simulation._simulation_milliseconds() + 40000,
		"departure re-arms the deadline on the difficulty interval"
	)


func _test_mothership_kill_records_secret_three() -> void:
	var simulation := _configure()
	var spawned := _force_hurry_up_wave(simulation)
	if spawned.is_empty():
		_failures.append("the kill test needs a spawned mothership")
		return
	var mothership: Dictionary = spawned[0]
	var progression: Dictionary = simulation._progression_for_seat(0)
	var score_before := int(progression.score)
	simulation._kill_enemy(mothership, 0)
	_expect(
		int(progression.score) - score_before
		== 2500 * int(progression.get("score_multiplier", 1)),
		"a mothership kill awards the traced 2,500 times the multiplier"
	)
	var seen: Array = progression.get("secret_session_seen", [])
	_expect(
		seen.size() > 3 and int(seen[3]) == 1,
		"a mothership kill records found-secret 3"
	)
	_expect(int(seen[6]) == 0, "a mothership kill does not record the money-ship secret")


func _test_rare_ship_fires_on_the_eighth_wave() -> void:
	var simulation := _configure()
	var rare_waves: Array[int] = []
	for wave in range(1, 17):
		for enemy_value in simulation._enemies:
			(enemy_value as Dictionary).dead = true
		var spawned := _force_hurry_up_wave(simulation)
		for enemy_value in spawned:
			var enemy: Dictionary = enemy_value
			if int(enemy.behavior_state_id) == 12:
				rare_waves.append(wave)
				_expect(
					String(enemy.sprite) == "moneyship"
					and int(enemy.score) == 25000,
					"the rare ship is the 25,000 point money ship"
				)
				_expect(
					int(enemy.collision_width) == 100
					and int(enemy.collision_height) == 100,
					"the money-ship hitbox is the traced 100x100"
				)
				_expect(
					int(enemy.health_fp) == 100 * Simulation.FP_ONE,
					"normal difficulty gives the money ship the traced base-C health"
				)
				_expect(
					int(enemy.y_fp)
					== -110 * Simulation.FP_ONE + 128 * Simulation.FP_ONE / 2,
					"the money ship enters above the surface at the traced y"
				)
				var left := int(enemy.x_fp) - 128 * Simulation.FP_ONE / 2
				_expect(
					left >= 100 * Simulation.FP_ONE
					and left < 400 * Simulation.FP_ONE,
					"the money ship spawns inside the traced x window"
				)
	_expect(
		rare_waves.size() == 2 and rare_waves[0] == 8 and rare_waves[1] == 16,
		"the money ship fires on every eighth wave, saw %s" % str(rare_waves)
	)


func _test_rare_ship_kill_records_secret_six() -> void:
	var simulation := _configure()
	var money_ship: Dictionary = {}
	for wave in range(8):
		for enemy_value in simulation._enemies:
			(enemy_value as Dictionary).dead = true
		for enemy_value in _force_hurry_up_wave(simulation):
			var enemy: Dictionary = enemy_value
			if int(enemy.behavior_state_id) == 12:
				money_ship = enemy
	if money_ship.is_empty():
		_failures.append("the money-ship kill test needs a spawned money ship")
		return
	var progression: Dictionary = simulation._progression_for_seat(0)
	var score_before := int(progression.score)
	simulation._kill_enemy(money_ship, 0)
	_expect(
		int(progression.score) - score_before
		== 25000 * int(progression.get("score_multiplier", 1)),
		"a money-ship kill awards the traced 25,000 times the multiplier"
	)
	var seen: Array = progression.get("secret_session_seen", [])
	_expect(
		seen.size() > 6 and int(seen[6]) == 1,
		"a money-ship kill records found-secret 6"
	)


func _test_time_trial_never_spawns() -> void:
	var simulation := Simulation.new()
	if not simulation.configure({
		"mode": "time_trial",
		"difficulty": "normal",
		"collision_mode": "simple",
		"seed": 77,
		"record_replay": false,
		"seats": [{
			"seat": 0,
			"profile_id": "hurry_up_time_trial",
			"display_name": "PILOT",
			"local": true,
		}],
	}):
		_failures.append("the Time Trial exclusion test must configure")
		return
	var rng_before: Dictionary = simulation._rng.snapshot()
	var spawned := _force_hurry_up_wave(simulation)
	_expect(spawned.is_empty(), "match mode 6 never spawns a hurry-up ship")
	_expect(
		simulation._rng.snapshot() == rng_before,
		"the Time Trial guard aborts before any random draw"
	)


## Retail tests the traced rectangle and then samples the sprite's hit mask.
## `mothership.hma` packs its twenty 96x57 frames in a single column while the
## texture uses 3x8, and `moneyship.hma` is a straight row-major copy of its
## sheet; both probe offsets below are read out of those files.
func _test_pixel_masks_decide_hurry_up_hits() -> void:
	var simulation := Simulation.new()
	if not simulation.configure({
		"mode": "solo",
		"difficulty": "normal",
		"collision_mode": "pixel",
		"seed": 4711,
		"record_replay": false,
	}):
		_failures.append("the pixel-mask test must configure")
		return
	var mothership: Dictionary = {}
	var money_ship: Dictionary = {}
	for wave in range(8):
		for enemy_value in simulation._enemies:
			(enemy_value as Dictionary).dead = true
		for enemy_value in _force_hurry_up_wave(simulation):
			var enemy: Dictionary = enemy_value
			if int(enemy.behavior_state_id) == 9:
				mothership = enemy
			else:
				money_ship = enemy
	if mothership.is_empty() or money_ship.is_empty():
		_failures.append("the pixel-mask test needs both hurry-up ships")
		return
	_expect(
		String(mothership.mask_id) == "mothership2"
		and String(money_ship.mask_id) == "moneyship"
		and bool(mothership.mask_required)
		and bool(money_ship.mask_required),
		"both hurry-up ships require their own mask"
	)
	_expect(
		int(mothership.mask_source_x) == 0
		and int(mothership.mask_source_width) == 96
		and int(mothership.mask_source_height) == 57
		and int(mothership.mask_source_y)
		== int(mothership.authored_animation_frame) * 57,
		"the mothership mask rectangle follows the single-column mask layout"
	)
	for probe in [
		[mothership, "mothership2", 96, 57, -7.5, -16.0, true, "hull"],
		[mothership, "mothership2", 96, 57, -45.5, -26.0, false, "transparent corner"],
		[money_ship, "moneyship", 128, 128, -1.5, -58.5, true, "hull"],
		[money_ship, "moneyship", 128, 128, -47.5, -47.5, false, "transparent corner"],
	]:
		var enemy: Dictionary = probe[0]
		var atlas: HitMaskAtlas = simulation._hit_masks[String(probe[1])]
		var mask_width := int(probe[2])
		var mask_height := int(probe[3])
		var solid := atlas.is_solid_source_rect_scaled(
			Rect2i(
				int(enemy.mask_source_x),
				int(enemy.mask_source_y),
				int(enemy.mask_source_width),
				int(enemy.mask_source_height)
			),
			roundi((float(probe[4]) + mask_width / 2.0) * Simulation.FP_ONE),
			roundi((float(probe[5]) + mask_height / 2.0) * Simulation.FP_ONE),
			mask_width,
			mask_height
		)
		_expect(
			solid == bool(probe[6]),
			"the %s mask should be %s at its %s"
			% [
				String(probe[1]),
				"solid" if bool(probe[6]) else "clear",
				String(probe[7]),
			]
		)
	# The traced rectangle still bounds the mask: a shot inside the money ship's
	# 128px frame but outside its 100px box never reaches the mask at all.
	var outside_box := {
		"x_fp": int(money_ship.x_fp) + 60 * Simulation.FP_ONE,
		"y_fp": int(money_ship.y_fp),
		"width": 1,
		"height": 1,
		"collision_simple": true,
	}
	_expect(
		not simulation._objects_collide(outside_box, money_ship),
		"a shot outside the traced money-ship rectangle misses"
	)
	_expect(
		(simulation._hit_masks["mothership2"] as HitMaskAtlas).frame_count == 20
		and (simulation._hit_masks["moneyship"] as HitMaskAtlas).frame_count == 10,
		"both hurry-up hit masks load with their traced frame counts"
	)


## Sweeping a planet drops one object into the shared 100-slot hazard pool
## (retail 0x00af7ea4). It homes at the fighter on the rocket sheet's
## 32-direction circle and expires on its difficulty-scaled lifetime.
func _test_planet_sweep_emits_homing_debris() -> void:
	var simulation := _configure()
	var spawned := _force_hurry_up_wave(simulation)
	if spawned.is_empty():
		_failures.append("the debris test needs a spawned mothership")
		return
	var mothership: Dictionary = spawned[0]
	_expect(
		simulation._active_effect_objects().is_empty(),
		"the pool starts empty"
	)
	# Put one planet directly behind the mothership so the next sweep clears it.
	simulation._hurry_up_planet_count = 1
	var ship_left: int = simulation._trunc_fp_to_int(
		int(mothership.x_fp) - 96 * Simulation.FP_ONE / 2
	)
	simulation._hurry_up_planet_x[0] = (
		ship_left + 40 if bool(mothership.hurry_up_enters_from_right)
		else ship_left - 40
	)
	simulation._sweep_hurry_up_planets(mothership)
	var objects: Array = simulation._active_effect_objects()
	_expect(objects.size() == 1, "a swept planet emits exactly one pool object")
	if objects.is_empty():
		return
	var debris: Dictionary = objects[0]
	_expect(
		int(debris.kind) == 9 and String(debris.sprite) == "rocket",
		"the debris is a kind-9 object on the rocket sheet"
	)
	_expect(
		int(debris.width) == 24 and int(debris.height) == 24,
		"the debris uses the traced 24x24 frame"
	)
	_expect(
		int(debris.heading) == 17,
		"the debris starts on the straight-down heading"
	)
	var lifetime := int(debris.lifetime_fp) / Simulation.FP_ONE
	_expect(
		lifetime >= 200 and lifetime < 200 + 225,
		"normal difficulty gives the debris its traced lifetime window, saw %d"
		% lifetime
	)
	_expect(
		int(simulation._hurry_up_planet_x[0]) == 0,
		"the swept planet is cleared"
	)
	# A second sweep with no remaining planet must not allocate again.
	simulation._sweep_hurry_up_planets(mothership)
	_expect(
		simulation._active_effect_objects().size() == 1,
		"a sweep that clears nothing emits nothing"
	)
	# The lifetime runs the object out of the pool.
	var guard := 0
	while not simulation._active_effect_objects().is_empty() and guard < 60000:
		guard += 1
		simulation._step_effect_pool()
	_expect(
		simulation._active_effect_objects().is_empty(),
		"the debris expires on its lifetime"
	)


func _test_state_survives_a_snapshot_round_trip() -> void:
	var simulation := _configure()
	_force_hurry_up_wave(simulation)
	simulation._hurry_up_planet_x[0] = 321
	var hash_state: Dictionary = simulation._state_for_hash()
	_expect(
		int(hash_state.get("hurry_up_deadline_ms", -1))
		== int(simulation._hurry_up_deadline_ms)
		and int(hash_state.get("hurry_up_spawn_counter", -1))
		== int(simulation._hurry_up_spawn_counter)
		and int(hash_state.get("hurry_up_planet_count", -1))
		== int(simulation._hurry_up_planet_count),
		"the hash state carries the hurry-up deadline, counter, and planet count"
	)
	var planets: Array = hash_state.get("hurry_up_planet_x", [])
	_expect(
		planets.size() == 8 and int(planets[0]) == 321,
		"the hash state carries the parallax planet row"
	)
	var snapshot: Dictionary = simulation.get_snapshot()
	var rendered := 0
	for enemy_value in snapshot.get("enemies", []):
		var enemy: Dictionary = enemy_value
		if String(enemy.get("sprite", "")) != "mothership2":
			continue
		rendered += 1
		var source: Array = enemy.get("source_rect", [])
		_expect(
			source.size() == 4 and int(source[2]) == 96 and int(source[3]) == 57,
			"the snapshot publishes a renderer-ready mothership source rectangle"
		)
	_expect(rendered == 1, "the snapshot publishes the spawned mothership")


## --- Money sucker and guard ship (gap G20) ----------------------------------


## Both spawners sit behind a random gate, so a test forces the gates instead of
## replaying until the draws happen to line up.
func _force_secret_ship(simulation: Object, state: String) -> Dictionary:
	simulation._spawn_secret_ship(state)
	for enemy_value in simulation._enemies:
		var enemy: Dictionary = enemy_value
		if (
			not bool(enemy.get("dead", false))
			and String(enemy.get("authored_state", "")) == state
		):
			return enemy
	return {}


func _test_money_sucker_trigger_guards() -> void:
	var simulation := _configure()
	var progression: Dictionary = simulation._progression_for_seat(0)
	progression.money = 750
	var rng_before: Dictionary = simulation._rng.snapshot()
	simulation._step_money_sucker_spawner()
	_expect(
		simulation._rng.snapshot() == rng_before,
		"cash at the 750 threshold suppresses the money sucker before any draw"
	)
	_expect(
		not simulation._has_active_secret_ship(11),
		"cash at the threshold spawns no money sucker"
	)
	# Above the threshold the spawner reaches its draws, and one that gets
	# through arms the traced two-minute cooldown.
	progression.money = 100000
	# The cooldown compares against the running clock, which is zero on the very
	# first frame, so the test opens it the way the real deadline would.
	simulation._money_sucker_deadline_ms = -1
	var spawned := false
	for _attempt in range(200000):
		simulation._step_money_sucker_spawner()
		if simulation._has_active_secret_ship(11):
			spawned = true
			break
	_expect(spawned, "a rich fighter eventually draws the money sucker")
	if not spawned:
		return
	_expect(
		int(simulation._money_sucker_deadline_ms)
		== int(simulation._simulation_milliseconds()) + 120000,
		"a money-sucker spawn arms the traced 120,000 ms cooldown"
	)
	var count := 0
	for enemy_value in simulation._enemies:
		if int((enemy_value as Dictionary).get("behavior_state_id", 0)) == 11:
			count += 1
	simulation._money_sucker_deadline_ms = -1
	for _attempt in range(20000):
		simulation._step_money_sucker_spawner()
	var after := 0
	for enemy_value in simulation._enemies:
		if int((enemy_value as Dictionary).get("behavior_state_id", 0)) == 11:
			after += 1
	_expect(
		count == 1 and after == 1,
		"only one money sucker is ever on the surface"
	)


func _test_money_sucker_patrols_and_drains_cash() -> void:
	var simulation := _configure()
	var enemy := _force_secret_ship(simulation, "money_sucker")
	if enemy.is_empty():
		_failures.append("the money-sucker patrol test needs a spawned ship")
		return
	_expect(
		int(enemy.width) == 128
		and int(enemy.height) == 51
		and int(enemy.collision_height) == 50,
		"the money sucker uses its traced 128x50 box inside a 128x51 frame"
	)
	_expect(
		int(enemy.health_fp) == 350 * Simulation.FP_ONE,
		"a normal-difficulty money sucker takes health base B"
	)
	var top := int(enemy.y_fp) / Simulation.FP_ONE - int(enemy.height) / 2
	_expect(
		top >= 200 and top < 350,
		"the money sucker enters inside the traced 200..350 lane: %d" % top
	)
	# Park it inside the drain window and force the per-frame gate through.
	var progression: Dictionary = simulation._progression_for_seat(0)
	progression.money = 5000
	enemy.x_fp = 400 * Simulation.FP_ONE
	var drained := false
	for _attempt in range(4000):
		var before := int(progression.money)
		simulation._drain_money_sucker_cash(enemy)
		var delta := before - int(progression.money)
		if delta != 0:
			_expect(
				delta in [10, 50, 100, 200],
				"a drained coin is one of the traced money values: %d" % delta
			)
			drained = true
			break
	_expect(drained, "a money sucker inside the window eventually drains cash")
	# Outside the window it never touches the fighter's cash.
	enemy.x_fp = -60 * Simulation.FP_ONE
	var guarded := int(progression.money)
	var rng_before: Dictionary = simulation._rng.snapshot()
	for _attempt in range(200):
		simulation._drain_money_sucker_cash(enemy)
	_expect(
		int(progression.money) == guarded
		and simulation._rng.snapshot() == rng_before,
		"a money sucker outside the window drains nothing and draws nothing"
	)
	# The patrol turns around at the far edge instead of leaving.
	enemy.x_fp = (Simulation.FIELD_WIDTH + 200) * Simulation.FP_ONE
	enemy.secret_ship_mode = 0
	simulation._advance_secret_ship(enemy)
	_expect(
		int(enemy.secret_ship_mode) == 1 and not bool(enemy.get("dead", false)),
		"the money sucker reverses at the right edge rather than departing"
	)


func _test_money_sucker_kill_raises_health_base_b() -> void:
	var simulation := _configure()
	var enemy := _force_secret_ship(simulation, "money_sucker")
	if enemy.is_empty():
		_failures.append("the money-sucker kill test needs a spawned ship")
		return
	var progression: Dictionary = simulation._progression_for_seat(0)
	var seen_before: Array = (progression.get("secret_session_seen", []) as Array).duplicate()
	var base_before := int(simulation._special_health_base_b)
	simulation._kill_enemy(enemy, 0)
	_expect(
		int(simulation._special_health_base_b) == base_before + 20,
		"a money-sucker kill raises special health base B by twenty"
	)
	_expect(
		(progression.get("secret_session_seen", []) as Array) == seen_before,
		"a money-sucker kill records no found secret"
	)
	var next := _force_secret_ship(simulation, "money_sucker")
	_expect(
		not next.is_empty()
		and int(next.health_fp) == (base_before + 20) * Simulation.FP_ONE,
		"the next money sucker is built from the raised base"
	)


func _test_guard_trigger_guards() -> void:
	var simulation := _configure()
	simulation._level_id = 15
	var rng_before: Dictionary = simulation._rng.snapshot()
	simulation._step_guard_spawner()
	_expect(
		simulation._rng.snapshot() == rng_before
		and not simulation._has_active_secret_ship(18),
		"level 15 suppresses the guard before any draw"
	)
	# Level 16 is an authored mode-three bonus, which the remake suppresses for
	# the same object-total reason it suppresses the hurry-up wave there, so the
	# first level a guard can actually reach is 17.
	simulation._level_id = 17
	simulation._guard_previous_level = 10
	rng_before = simulation._rng.snapshot()
	simulation._step_guard_spawner()
	_expect(
		simulation._rng.snapshot() == rng_before,
		"fewer than ten levels since the last guard suppresses it before any draw"
	)
	# The trigger is a one-in-three-thousand frame gate behind a further
	# one-in-forty roll, so the positive case is driven rather than sampled.
	simulation._guard_previous_level = 0
	rng_before = simulation._rng.snapshot()
	simulation._step_guard_spawner()
	_expect(
		simulation._rng.snapshot() != rng_before,
		"a qualifying level lets the guard spawner reach its draws"
	)
	var guard := _force_secret_ship(simulation, "guard_ship")
	_expect(
		not guard.is_empty() and int(simulation._guard_previous_level) == 17,
		"a guard spawn records the level it appeared on"
	)


func _test_guard_fires_a_beam_column_and_holds_position() -> void:
	var simulation := _configure()
	simulation._level_id = 20
	var enemy := _force_secret_ship(simulation, "guard_ship")
	if enemy.is_empty():
		_failures.append("the guard beam test needs a spawned guard")
		return
	_expect(
		int(enemy.width) == 128 and int(enemy.height) == 64,
		"the guard uses its traced 128x64 box"
	)
	_expect(
		int(enemy.health_fp) == 1750 * Simulation.FP_ONE,
		"a normal-difficulty guard takes health base D"
	)
	enemy.x_fp = 400 * Simulation.FP_ONE
	enemy.y_fp = 232 * Simulation.FP_ONE
	simulation._fire_guard_beam(enemy)
	var segments: Array = []
	for slot_value in simulation._active_effect_objects():
		var slot: Dictionary = slot_value
		if int(slot.kind) == 18:
			segments.append(slot)
	var column_top := 232 - 32 + 30
	var expected := 0
	var walk := column_top
	while walk <= Simulation.FIELD_HEIGHT:
		expected += 1
		walk += 70
	_expect(
		segments.size() == expected,
		"the beam walks the surface in seventy-pixel steps: %d of %d"
		% [segments.size(), expected]
	)
	if not segments.is_empty():
		var first: Dictionary = segments[0]
		_expect(
			int(first.width) == 64 and int(first.height) == 70,
			"each beam segment is the traced 64x70"
		)
		_expect(
			int(first.y_fp) == (column_top + 35) * Simulation.FP_ONE,
			"the column starts thirty pixels below the guard's own top"
		)
	# A busy pool shortens the column instead of dropping it.
	var full := _configure()
	full._level_id = 20
	var crowded := _force_secret_ship(full, "guard_ship")
	for slot_index in range(100):
		full._effect_pool[slot_index] = {"slot": slot_index, "kind": 18}
	full._fire_guard_beam(crowded)
	_expect(
		full._active_effect_objects().size() == 100,
		"a full pool simply stops the beam"
	)
	# The guard stops moving while its firing window is open.
	simulation._guard_beam_window = 20
	var x_before := int(enemy.x_fp)
	simulation._update_guard_ship(enemy)
	_expect(
		int(enemy.x_fp) == x_before,
		"the guard holds position while its firing window is open"
	)
	simulation._guard_beam_window = 0
	enemy.secret_ship_mode = 0
	simulation._update_guard_ship(enemy)
	_expect(
		int(enemy.x_fp) != x_before,
		"the guard resumes its patrol once the window closes"
	)


func _test_guard_kill_raises_health_base_d() -> void:
	var simulation := _configure()
	simulation._level_id = 20
	var enemy := _force_secret_ship(simulation, "guard_ship")
	if enemy.is_empty():
		_failures.append("the guard kill test needs a spawned guard")
		return
	var progression: Dictionary = simulation._progression_for_seat(0)
	var seen_before: Array = (progression.get("secret_session_seen", []) as Array).duplicate()
	var base_before := int(simulation._special_health_base_d)
	simulation._kill_enemy(enemy, 0)
	_expect(
		int(simulation._special_health_base_d) == base_before + 250,
		"a guard kill raises special health base D by two hundred and fifty"
	)
	_expect(
		(progression.get("secret_session_seen", []) as Array) == seen_before,
		"a guard kill records no found secret"
	)


func _test_secret_ship_state_survives_a_shop_save() -> void:
	var simulation := _configure()
	simulation._money_sucker_deadline_ms = 4321
	simulation._guard_previous_level = 17
	simulation._guard_beam_window = 9
	simulation._special_health_base_b = 370
	simulation._special_health_base_d = 2000
	var hash_state: Dictionary = simulation._state_for_hash()
	_expect(
		int(hash_state.get("money_sucker_deadline_ms", -1)) == 4321
		and int(hash_state.get("guard_previous_level", -1)) == 17
		and int(hash_state.get("guard_beam_window", -1)) == 9
		and int(hash_state.get("special_health_base_b", -1)) == 370
		and int(hash_state.get("special_health_base_d", -1)) == 2000,
		"the hash state carries every secret-ship escalation field"
	)
	# A run can only be saved from the shop.
	simulation._phase = Simulation.PHASE_SHOP
	var save: Dictionary = simulation.export_shop_save()
	_expect(
		not save.is_empty(),
		"the secret-ship shop save exports: %s" % simulation.get_last_error()
	)
	var restored := _configure()
	_expect(
		restored.restore_shop_save(save),
		"a secret-ship shop save restores: %s" % restored.get_last_error()
	)
	_expect(
		int(restored._money_sucker_deadline_ms) == 4321
		and int(restored._guard_previous_level) == 17
		and int(restored._guard_beam_window) == 9
		and int(restored._special_health_base_b) == 370
		and int(restored._special_health_base_d) == 2000,
		"a resumed run keeps every secret-ship escalation field"
	)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

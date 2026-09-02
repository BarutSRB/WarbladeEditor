extends SceneTree

# Endless campaign contract tests. The rules under test are executable-backed:
# docs/evidence/ENDLESS_PROGRESSION.md pins the retail content cycling, mirror,
# and per-hundred progression step.

const Simulation := preload("res://src/sim/game_simulation.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_wrap_and_mirror_formulas()
	_test_endless_spawn_progression()
	_test_endless_content_and_cadence_resolution()
	_test_retail_clamp_configuration()
	if _failures.is_empty():
		print("ENDLESS PROGRESSION TESTS PASSED")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _config(start_level: int, end_level: int, seed: int) -> Dictionary:
	return {
		"mode": "solo",
		"difficulty": "normal",
		"seed": seed,
		"start_level": start_level,
		"end_level": end_level,
	}


func _test_wrap_and_mirror_formulas() -> void:
	_expect(Simulation.authored_level_id_for(1) == 1, "level 1 authors itself")
	_expect(Simulation.authored_level_id_for(100) == 100, "level 100 authors itself")
	_expect(Simulation.authored_level_id_for(101) == 1, "level 101 wraps to authored level 1")
	_expect(Simulation.authored_level_id_for(200) == 100, "level 200 wraps to authored level 100")
	_expect(Simulation.authored_level_id_for(3999) == 99, "the retail clamp wraps to authored level 99")
	_expect(not Simulation.endless_mirror_for_level(1), "level 1 is not mirrored")
	_expect(Simulation.endless_mirror_for_level(100), "level 100 is mirrored")
	_expect(Simulation.endless_mirror_for_level(101), "level 101 is mirrored")
	_expect(Simulation.endless_mirror_for_level(199), "level 199 is mirrored")
	_expect(not Simulation.endless_mirror_for_level(200), "level 200 is not mirrored")
	_expect(not Simulation.endless_mirror_for_level(201), "level 201 is not mirrored")
	_expect(Simulation.endless_mirror_for_level(300), "level 300 is mirrored")
	_expect(Simulation.endless_steps_for_level(100) == 0, "level 100 has no progression step")
	_expect(Simulation.endless_steps_for_level(101) == 1, "level 101 applies one progression step")
	_expect(Simulation.endless_steps_for_level(200) == 1, "level 200 applies one progression step")
	_expect(Simulation.endless_steps_for_level(201) == 2, "level 201 applies two progression steps")
	_expect(Simulation.endless_steps_for_level(3999) == 39, "the retail clamp applies 39 progression steps")


func _test_endless_spawn_progression() -> void:
	var base := Simulation.new()
	_expect(base.configure(_config(1, 1, 7001)), "level-1 reference match should configure")
	base.step()
	var endless := Simulation.new()
	_expect(endless.configure(_config(101, 150, 7001)), "level-101 endless match should configure")
	endless.step()
	_expect(endless._endless_step_count == 1, "level 101 begins with one progression step")
	_expect(
		int(endless._difficulty.timer_a_initial_adjustment)
			== int(base._difficulty.timer_a_initial_adjustment) - 50,
		"each hundred subtracts 50 from the timer-A initial adjustment"
	)
	_expect(
		int(endless._difficulty.timer_b_initial_adjustment)
			== int(base._difficulty.timer_b_initial_adjustment) - 50,
		"each hundred subtracts 50 from the timer-B initial adjustment"
	)
	_expect(
		int(endless._difficulty.alien_projectile_speed_fp)
			== int(base._difficulty.alien_projectile_speed_fp) * 41 / 40,
		"each hundred multiplies the ordinary projectile base speed by 41/40"
	)
	# Folded scale: (1.0 + 3/25) * (60 + 3) / 60 = 1.176 in fixed point.
	_expect(
		endless._endless_simulation_scale_fp() == 77070,
		"level 101 folds the +3/25 scale step and the +3 update-target step"
	)
	_expect(
		base._endless_simulation_scale_fp() == Simulation.FP_ONE,
		"authored levels keep the exact base simulation scale"
	)
	_expect(
		not base._enemies.is_empty() and not endless._enemies.is_empty(),
		"both reference and endless levels spawn their first group"
	)
	if base._enemies.is_empty() or endless._enemies.is_empty():
		return
	var base_enemy: Dictionary = base._enemies[0]
	var endless_enemy: Dictionary = endless._enemies[0]
	_expect(
		int(endless_enemy.health_fp) - int(base_enemy.health_fp) == Simulation.FP_ONE,
		"level 101 ordinary enemies gain exactly one health over authored"
	)
	_expect(
		int(endless_enemy.behavior_timer_a) == int(base_enemy.behavior_timer_a) - 50,
		"level 101 spawn timers tighten by the per-hundred adjustment"
	)
	_expect(
		int(endless_enemy.projectile_speed_fp)
			== int(base_enemy.projectile_speed_fp) * 41 / 40,
		"level 101 spawn projectile speed carries the per-hundred multiplier"
	)
	_expect(
		int(endless_enemy.anchor_x_fp)
			== 800 * Simulation.FP_ONE - int(base_enemy.anchor_x_fp),
		"level 101 mirrors the level-1 entry formation horizontally"
	)
	_expect(
		bool(endless_enemy.mirror_x) and not bool(base_enemy.mirror_x),
		"level 101 enemies record the mirrored spawn flag"
	)


func _test_endless_content_and_cadence_resolution() -> void:
	var simulation := Simulation.new()
	_expect(simulation.configure(_config(101, 3999, 7002)), "endless clamp match should configure")
	_expect(
		String(simulation._level_data_for(101).get("title", ""))
			== String(simulation._level_data_for(1).get("title", "")),
		"level 101 resolves the authored level-1 content"
	)
	_expect(
		bool(simulation._level_data_for(104).get("shop_after", false)),
		"level 104 keeps the wrapped shop-after cadence of authored level 4"
	)
	simulation._level_id = 125
	_expect(
		simulation._is_retail_big_boss_level(),
		"level 125 resolves the wrapped level-25 big boss encounter"
	)
	simulation._level_id = 101
	_expect(
		not simulation._is_retail_big_boss_level(),
		"level 101 is an ordinary wrapped level"
	)


func _test_retail_clamp_configuration() -> void:
	var clamped := Simulation.new()
	_expect(
		clamped.configure(_config(3999, 3999, 7003)),
		"the retail clamp level should configure"
	)
	_expect(
		clamped._endless_step_count == 39,
		"the retail clamp applies 39 progression steps"
	)
	_expect(
		int(clamped._difficulty.timer_a_initial_adjustment)
			== maxi(200 - 50 * 39, -500),
		"the timer adjustment floors at -500"
	)
	var too_far := Simulation.new()
	_expect(
		not too_far.configure(_config(3999, 4000, 7004)),
		"configurations beyond the retail clamp are rejected"
	)

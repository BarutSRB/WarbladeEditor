extends SceneTree

const HitMask := preload("res://src/sim/hit_mask_atlas.gd")
const Simulation := preload("res://src/sim/game_simulation.gd")
const ENEMY_SHEET_IDS := [
	"alien001", "alien_2", "alien_3", "alien000", "alien_lilla",
	"alien_raudkule", "alien_raudkule2", "alien_blavinger_gf",
	"alien_blavinger_gf2", "alien_rbille",
]
const ENEMY_PROJECTILE_MASKS := {
	7: {
		"alien001": [[[0, 0, 5, 13], 76], [[0, 0, 5, 13], 76]],
		"alien_2": [[[0, 0, 3, 11], 38], [[0, 0, 3, 11], 38]],
		"alien_3": [[[0, 0, 5, 12], 71], [[0, 0, 6, 12], 73]],
		"alien000": [[[0, 0, 7, 13], 104], [[0, 0, 7, 13], 96]],
		"alien_lilla": [[[0, 0, 5, 9], 43], [[0, 0, 5, 9], 42]],
		"alien_raudkule": [[[2, 2, 5, 7], 24], [[2, 2, 4, 5], 10]],
		"alien_raudkule2": [[[0, 0, 7, 9], 64], [[0, 0, 7, 9], 64]],
		"alien_blavinger_gf": [[[2, 2, 7, 7], 20], [[0, 0, 9, 9], 47]],
		"alien_blavinger_gf2": [[[2, 2, 7, 7], 20], [[0, 0, 9, 9], 52]],
		"alien_rbille": [[[0, 0, 7, 7], 49], [[0, 0, 7, 7], 50]],
	},
	6: {
		"alien001": [[[0, 1, 11, 12], 72], [[0, 0, 11, 11], 132]],
		"alien_2": [[[2, 2, 9, 9], 64], [[0, 0, 11, 11], 144]],
		"alien_3": [[[0, 0, 31, 12], 94], [[0, 0, 31, 12], 135]],
		"alien000": [[[0, 0, 13, 16], 187], [[0, 0, 13, 16], 186]],
		"alien_lilla": [[[0, 0, 11, 11], 69], [[0, 0, 11, 11], 98]],
		"alien_raudkule": [[[4, 4, 9, 9], 18], [[0, 0, 17, 17], 276]],
		"alien_raudkule2": [[[0, 0, 17, 17], 276], [[32, 32, -1, -1], 0]],
		"alien_blavinger_gf": [[[0, 0, 13, 13], 132], [[0, 0, 13, 13], 116]],
		"alien_blavinger_gf2": [[[0, 0, 13, 13], 56], [[0, 0, 13, 13], 40]],
		"alien_rbille": [[[0, 0, 17, 17], 308], [[0, 0, 17, 17], 309]],
	},
}

var _failures: Array[String] = []


func _initialize() -> void:
	_test_frame_addressing_and_scaling()
	_test_transparent_and_solid_overlap()
	_test_extracted_fighter_atlases()
	_test_enemy_projectile_source_rectangles()
	_test_packed_source_rectangles()
	_test_invalid_masks()
	if _failures.is_empty():
		print("HIT MASK TESTS PASSED")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _test_frame_addressing_and_scaling() -> void:
	var pixels := PackedByteArray()
	pixels.resize(8)
	pixels[2] = 1
	var atlas := HitMask.new()
	_expect(atlas.configure(pixels, 4, 2, 2, 2), "two-frame synthetic atlas should configure")
	_expect(atlas.frame_count == 2, "frame count should derive from atlas metadata")
	_expect(not atlas.is_solid(0, 0, 0), "frame zero should address its own transparent pixels")
	_expect(atlas.is_solid(1, 0, 0), "frame one should address its own solid pixels")
	_expect(
		atlas.is_solid_scaled(1, HitMask.FP_ONE, HitMask.FP_ONE, 4, 4),
		"integer scaling should map logical pixels into source pixels"
	)
	_expect(
		not atlas.is_solid_scaled(1, 3 * HitMask.FP_ONE, 3 * HitMask.FP_ONE, 4, 4),
		"scaled transparent source pixels should remain transparent"
	)


func _test_transparent_and_solid_overlap() -> void:
	var top_left_pixels := PackedByteArray()
	top_left_pixels.resize(16)
	top_left_pixels[0] = 1
	var bottom_right_pixels := PackedByteArray()
	bottom_right_pixels.resize(16)
	bottom_right_pixels[15] = 1
	var matching_pixels := PackedByteArray()
	matching_pixels.resize(16)
	matching_pixels[0] = 1
	var top_left := HitMask.new()
	var bottom_right := HitMask.new()
	var matching := HitMask.new()
	top_left.configure(top_left_pixels, 4, 4, 4, 4)
	bottom_right.configure(bottom_right_pixels, 4, 4, 4, 4)
	matching.configure(matching_pixels, 4, 4, 4, 4)
	_expect(
		not top_left.overlaps(0, 0, 0, 4, 4, bottom_right, 0, 0, 0, 4, 4),
		"overlapping AABBs with disjoint solid pixels should not collide"
	)
	_expect(
		top_left.overlaps(0, 0, 0, 4, 4, matching, 0, 0, 0, 4, 4),
		"overlapping AABBs with matching solid pixels should collide"
	)
	_expect(
		not top_left.overlaps(0, 0, 0, 4, 4, matching, 0, 0, 5 * HitMask.FP_ONE, 4, 4),
		"separated broad-phase AABBs should not enter the mask narrow phase"
	)


func _test_extracted_fighter_atlases() -> void:
	var simulation := Simulation.new()
	_expect(simulation.configure({
		"mode": "solo",
		"difficulty": "normal",
		"collision_mode": "pixel",
	}), "pixel-mode simulation should load the extracted fighter masks")
	var player: Dictionary = simulation.get_snapshot().players[0]
	_expect(
		player.width == 40 and player.height == 28,
		"simulation collision dimensions should preserve the 40 by 28 source mask"
	)
	for fighter_id in ["fighter1", "fighter2"]:
		var atlas := HitMask.new()
		_expect(atlas.load_file(
			"res://assets/original/textures/player/%s.hma" % fighter_id,
			440,
			28,
			40,
			28
		), "%s extracted mask should load" % fighter_id)
		_expect(atlas.frame_count == 11, "%s should contain eleven 40 by 28 frames" % fighter_id)
		var solid_pixel := Vector2i(-1, -1)
		for source_y in range(28):
			for source_x in range(40):
				if atlas.is_solid(5, source_x, source_y):
					solid_pixel = Vector2i(source_x, source_y)
					break
			if solid_pixel.x >= 0:
				break
		_expect(solid_pixel.x >= 0, "%s frame five should contain a solid collision pixel" % fighter_id)
		if solid_pixel.x >= 0:
			_expect(
				atlas.is_solid_scaled(
					5,
					solid_pixel.x * HitMask.FP_ONE + HitMask.FP_HALF,
					solid_pixel.y * HitMask.FP_ONE + HitMask.FP_HALF,
					int(player.width),
					int(player.height)
				),
				"%s logical fighter extent should map one-to-one onto its source mask" % fighter_id
			)
	for enemy_id in ENEMY_SHEET_IDS:
		var enemy_atlas := HitMask.new()
		_expect(enemy_atlas.load_file(
			"res://assets/original/textures/enemies/%s.hma" % enemy_id,
			576,
			96,
			576,
			96
		), "%s extracted enemy mask should load" % enemy_id)
		_expect(enemy_atlas.frame_count == 1, "%s should expose its packed 576x96 atlas" % enemy_id)


func _test_enemy_projectile_source_rectangles() -> void:
	for enemy_id in ENEMY_SHEET_IDS:
		var atlas := HitMask.new()
		if not atlas.load_file(
			"res://assets/original/textures/enemies/%s.hma" % enemy_id,
			576,
			96,
			576,
			96
		):
			_expect(false, "%s projectile mask atlas should load" % enemy_id)
			continue
		for projectile_type in [6, 7]:
			var source_x := 448 if projectile_type == 6 else 480
			for phase in range(2):
				var source_rect := Rect2i(source_x, phase * 32, 32, 32)
				var measured := _measure_source_rect(atlas, source_rect)
				var expected: Array = ENEMY_PROJECTILE_MASKS[projectile_type][enemy_id][phase]
				_expect(
					measured.bounds == expected[0]
					and int(measured.occupied_pixel_count) == int(expected[1]),
					"%s type-%d phase %d should retain exact HMA bounds/count"
					% [enemy_id, projectile_type, phase]
				)


func _measure_source_rect(atlas: HitMaskAtlas, source_rect: Rect2i) -> Dictionary:
	var bounds := [32, 32, -1, -1]
	var occupied_pixel_count := 0
	for local_y in range(source_rect.size.y):
		for local_x in range(source_rect.size.x):
			if not atlas.is_solid_source_rect_scaled(
				source_rect,
				local_x * HitMask.FP_ONE + HitMask.FP_HALF,
				local_y * HitMask.FP_ONE + HitMask.FP_HALF,
				source_rect.size.x,
				source_rect.size.y
			):
				continue
			occupied_pixel_count += 1
			bounds[0] = mini(bounds[0], local_x)
			bounds[1] = mini(bounds[1], local_y)
			bounds[2] = maxi(bounds[2], local_x)
			bounds[3] = maxi(bounds[3], local_y)
	return {"bounds": bounds, "occupied_pixel_count": occupied_pixel_count}


func _test_invalid_masks() -> void:
	var atlas := HitMask.new()
	_expect(not atlas.configure(PackedByteArray([0, 1, 0]), 2, 2, 2, 2), "wrong byte counts should be rejected")
	_expect(not atlas.configure(PackedByteArray([0, 2, 0, 1]), 2, 2, 2, 2), "non-binary mask bytes should be rejected")
	_expect(not atlas.configure(PackedByteArray([0, 1, 0, 1]), 2, 2, 3, 2), "non-divisible frame metadata should be rejected")
	_expect(
		not atlas.load_file(
			"res://assets/original/textures/enemies/alien001.hma",
			576,
			96,
			576,
			96,
			"0".repeat(64)
		),
		"collision masks whose bytes differ from the pinned digest should be rejected"
	)
	_expect(
		atlas.last_error.contains("SHA-256"),
		"a collision digest mismatch should identify the fail-closed reason"
	)


func _test_packed_source_rectangles() -> void:
	var atlas := HitMask.new()
	_expect(atlas.load_file(
		"res://assets/original/textures/weapons/weapons_big.hma",
		672,
		100,
		672,
		100
	), "packed projectile hit-mask sheet should load as one atlas")
	var source_rect := Rect2i(176, 0, 22, 41)
	var solid_pixel := Vector2i(-1, -1)
	for local_y in range(source_rect.size.y):
		for local_x in range(source_rect.size.x):
			if atlas.is_solid_source_rect_scaled(
				source_rect,
				local_x * HitMask.FP_ONE + HitMask.FP_HALF,
				local_y * HitMask.FP_ONE + HitMask.FP_HALF,
				source_rect.size.x,
				source_rect.size.y
			):
				solid_pixel = Vector2i(local_x, local_y)
				break
		if solid_pixel.x >= 0:
			break
	_expect(solid_pixel.x >= 0, "packed plasma rectangle should contain collision pixels")
	_expect(
		atlas.overlaps_source_rect(
			source_rect,
			0,
			0,
			source_rect.size.x,
			source_rect.size.y,
			atlas,
			source_rect,
			0,
			0,
			source_rect.size.x,
			source_rect.size.y
		),
		"identical packed source rectangles should overlap at the same position"
	)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

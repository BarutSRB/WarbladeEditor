extends SceneTree

const Rng := preload("res://src/sim/deterministic_rng.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_test_seed_one_reference_vector()
	_test_u32_wrap()
	_test_range_draw_contract()
	_test_float32_wrapper()
	_test_maximum_word_endpoint_and_modulo_contract()
	_test_zero_seed()
	_test_high_bit_seed_vectors()
	_test_snapshot_restore()
	_test_signed_range()
	if _failures.is_empty():
		print("DETERMINISTIC RNG TESTS PASSED")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _test_seed_one_reference_vector() -> void:
	var rng := Rng.new(1)
	_expect(
		rng.snapshot() == {
			"x": 0x00000029,
			"y": 0x000b8d9b,
			"z": 0x000f8409,
			"w": 0,
			"c": 0,
			"draw_count": 0,
		},
		"seed 1 should reproduce the executable's initialized five-word state; got %s" % [rng.snapshot()]
	)
	var expected: Array[int] = [
		0xff014960,
		0x5c35a3de,
		0x7b7559fd,
		0x5c35a736,
		0x6e1afd2f,
		0x2eabf9e1,
		0x41f38d8a,
		0x3fa68159,
		0xfb551b94,
		0xa9d56ef4,
	]
	var actual: Array[int] = []
	for index in range(expected.size()):
		actual.append(rng.next_u32())
	_expect(actual == expected, "seed 1 should reproduce the first ten executable outputs; got %s" % [actual])
	_expect(rng.draw_count == 10, "each raw transition should increment the draw counter once")


func _test_u32_wrap() -> void:
	var rng := Rng.new()
	rng.restore({
		"x": 0xffffffff,
		"y": 0x80000000,
		"z": 0x7fffffff,
		"w": 0xf1234567,
		"c": 0x80000001,
		"draw_count": 27,
	})
	_expect(rng.next_u32() == 0x8ea35cb9, "transition arithmetic should wrap as unsigned 32-bit")
	_expect(
		rng.snapshot() == {
			"x": 0x80000000,
			"y": 0x7fffffff,
			"z": 0xf1234567,
			"w": 0x8ea35cb9,
			"c": 0x7ffff802,
			"draw_count": 28,
		},
		"all five state words should retain their wrapped unsigned values"
	)


func _test_range_draw_contract() -> void:
	var rng := Rng.new(1)
	_expect(rng.next_range(0) == 0, "an empty range should return zero")
	_expect(rng.draw_count == 0, "an empty range should not consume a raw draw")
	_expect(rng.next_range(1) == 0, "a span-one range should return zero")
	_expect(rng.draw_count == 1, "a span-one range should still consume one raw draw")
	_expect(rng.w == 0xff014960, "the span-one draw should perform the ordinary raw transition")


func _test_float32_wrapper() -> void:
	var rng := Rng.new(1)
	var velocity := rng.next_float32(1.2, 1.8)
	_expect(
		_float32_bits(velocity) == 0x3fe619fc,
		"the retail float wrapper should preserve the executable's float32 boundary"
	)
	var period := rng.next_float32(3.0, 7.0)
	_expect(
		_float32_bits(period) == 0x408e1ad2,
		"successive float draws should use one full-width raw word each"
	)
	var before_zero_width := rng.draw_count
	_expect(rng.next_float32(4.5, 4.5) == 4.5, "a zero-width float range should return its boundary")
	_expect(
		rng.draw_count == before_zero_width + 1,
		"a zero-width float range should still consume one raw draw"
	)


func _test_maximum_word_endpoint_and_modulo_contract() -> void:
	# With x/w zero, c=0xff00ff00 inverts c^(c>>8) to the maximum word.
	# This makes the otherwise rare endpoint behavior reproducible without a
	# seed search or a test-only RNG implementation.
	var endpoint := Rng.new()
	endpoint.restore({
		"x": 0,
		"y": 0,
		"z": 0,
		"w": 0,
		"c": 0xff00ff00,
		"draw_count": 40,
	})
	var value := endpoint.next_float32(0.0, 1.0)
	_expect(
		_float32_bits(value) == 0x3f800000
		and int(endpoint.draw_count) == 41,
		"maximum U32 must round to the float32 upper endpoint after one retail draw"
	)

	var modulo := Rng.new()
	modulo.restore({
		"x": 0,
		"y": 0,
		"z": 0,
		"w": 0,
		"c": 0xff00ff00,
		"draw_count": 7,
	})
	_expect(
		modulo.next_range(10) == 5
		and int(modulo.draw_count) == 8
		and 4294967296 % 10 == 6,
		"integer ranges must apply one-draw retail modulo, retaining its six-remainder bias"
	)


func _test_zero_seed() -> void:
	var rng := Rng.new(0)
	_expect(
		rng.snapshot() == {
			"x": 0x00000026,
			"y": 0x000479ca,
			"z": 0x0010ca4e,
			"w": 0,
			"c": 0,
			"draw_count": 0,
		},
		"seed zero should remain valid instead of being remapped to one"
	)
	_expect(rng.next_u32() == 0xff013115, "seed zero should have its own reproducible output stream")


func _test_high_bit_seed_vectors() -> void:
	var rng := Rng.new(0xffffffff)
	_expect(
		rng.snapshot() == {
			"x": 35,
			"y": 1040865,
			"z": 1158955,
			"w": 0,
			"c": 0,
			"draw_count": 0,
		},
		"the initializer should preserve all 32 seed bits"
	)
	var expected: Array[int] = [
		0xff01193a,
		0x7f7c06db,
		0x8c1a9ae3,
		0x7f7c18b7,
		0x844be6f2,
		0xd8962999,
		0xdb265a89,
		0xb8bf80f4,
	]
	var actual: Array[int] = []
	for index in range(expected.size()):
		actual.append(rng.next_u32())
	_expect(actual == expected, "high-bit seed output should match the executable fixture; got %s" % [actual])


func _test_snapshot_restore() -> void:
	var rng := Rng.new(0x89abcdef)
	for index in range(3):
		rng.next_u32()
	var checkpoint: Dictionary = rng.snapshot()
	var expected: Array[int] = []
	for index in range(6):
		expected.append(rng.next_u32())
	rng.restore(checkpoint)
	var actual: Array[int] = []
	for index in range(6):
		actual.append(rng.next_u32())
	_expect(actual == expected, "restoring a snapshot should reproduce all later outputs")
	_expect(rng.draw_count == 9, "snapshot restore should also restore the monotonic draw counter")
	_expect(rng.state == rng.w, "the scalar compatibility state should expose the current output word")
	rng.state = 0x1ffffffff
	_expect(rng.w == 0xffffffff, "the scalar compatibility setter should preserve u32 wrapping")


func _test_signed_range() -> void:
	var rng := Rng.new(1)
	_expect(rng.next_signed(0) == 0, "zero signed magnitude should return zero")
	_expect(rng.draw_count == 0, "zero signed magnitude should not consume a raw draw")
	_expect(rng.next_signed(7) == -2, "signed ranges should apply modulo to one full-width raw draw")
	_expect(rng.draw_count == 1, "a non-empty signed range should consume exactly one draw")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _float32_bits(value: float) -> int:
	return PackedFloat32Array([value]).to_byte_array().decode_u32(0)

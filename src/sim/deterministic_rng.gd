class_name DeterministicRng
extends RefCounted

# WarBlade 1.34's five-word generator. The executable implementation is at
# 0x0052f750 and its MSVCRT-based initializer is at 0x0052ea50.
const U32_MASK: int = 0xffffffff
const MSVCRT_MULTIPLIER: int = 214013
const MSVCRT_INCREMENT: int = 2531011

var x: int = 0
var y: int = 0
var z: int = 0
var w: int = 0
var c: int = 0
var draw_count: int = 0

# Temporary compatibility alias for callers that still consume one scalar.
# New state serialization must use snapshot() so none of the five words are
# discarded.
var state: int:
	get:
		return w
	set(value):
		w = _u32(value)


func _init(seed_value: int = 1) -> void:
	self.seed(seed_value)


func seed(seed_value: int) -> void:
	var initializer_state := _u32(seed_value)
	initializer_state = _msvcrt_step(initializer_state)
	x = (initializer_state >> 16) & 0x7fff

	initializer_state = _msvcrt_step(initializer_state)
	var second := (initializer_state >> 16) & 0x7fff
	y = _u32(second * x)

	initializer_state = _msvcrt_step(initializer_state)
	var third := (initializer_state >> 16) & 0x7fff
	z = _u32(third * x + y)

	w = 0
	c = 0
	draw_count = 0


func next_u32() -> int:
	var t := _u32(x ^ _u32(x << 11))
	c = _u32(c - t)
	x = y
	y = z
	z = w
	w = _u32((w ^ (w >> 19)) ^ (c ^ (c >> 8)))
	draw_count += 1
	return w


# Retained for source compatibility. Retail gameplay draws one full-width word
# and only then applies the requested mask or range operation.
func next_u31() -> int:
	return next_u32() & 0x7fffffff


func next_range(upper_exclusive: int) -> int:
	if upper_exclusive <= 0:
		return 0
	return next_u32() % upper_exclusive


func next_float32(minimum: float, maximum: float) -> float:
	# Retail's wrapper loads float32 arguments, rounds their subtraction to a
	# float32 span, scales one unsigned raw word by exact 2^-32, then stores the
	# result back to float32. Unlike the integer helper, even a zero-width range
	# consumes one raw draw.
	var minimum_f32 := _float32(minimum)
	var maximum_f32 := _float32(maximum)
	var span_f32 := _float32(maximum_f32 - minimum_f32)
	var raw := next_u32()
	return _float32(
		minimum_f32 + float(raw) * float(span_f32) / 4294967296.0
	)


func next_signed(magnitude: int) -> int:
	if magnitude <= 0:
		return 0
	return next_range(magnitude * 2 + 1) - magnitude


func snapshot() -> Dictionary:
	return {
		"x": x,
		"y": y,
		"z": z,
		"w": w,
		"c": c,
		"draw_count": draw_count,
	}


func restore(snapshot_data: Dictionary) -> void:
	x = _u32(int(snapshot_data.get("x", 0)))
	y = _u32(int(snapshot_data.get("y", 0)))
	z = _u32(int(snapshot_data.get("z", 0)))
	w = _u32(int(snapshot_data.get("w", 0)))
	c = _u32(int(snapshot_data.get("c", 0)))
	draw_count = maxi(0, int(snapshot_data.get("draw_count", 0)))


static func _msvcrt_step(value: int) -> int:
	return _u32(value * MSVCRT_MULTIPLIER + MSVCRT_INCREMENT)


static func _u32(value: int) -> int:
	return value & U32_MASK


static func _float32(value: float) -> float:
	var storage := PackedFloat32Array([value])
	return float(storage[0])

class_name FixedPoint
extends RefCounted

const ONE: int = 65536
const HALF: int = 32768


static func from_int(value: int) -> int:
	return value * ONE


static func to_int(value: int) -> int:
	return value >> 16


static func multiply(left: int, right: int) -> int:
	return (left * right) >> 16


static func divide(numerator: int, denominator: int) -> int:
	if denominator == 0:
		return 0
	return (numerator << 16) / denominator


static func clamp_value(value: int, minimum: int, maximum: int) -> int:
	if value < minimum:
		return minimum
	if value > maximum:
		return maximum
	return value


static func abs_value(value: int) -> int:
	return -value if value < 0 else value

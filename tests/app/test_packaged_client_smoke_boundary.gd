extends SceneTree

const PackagedClientSmoke := preload("res://src/app/packaged_client_smoke.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	var absent := PackagedClientSmoke.parse_end_level_arguments(PackedStringArray())
	_expect(not bool(absent.get("provided", true)), "an absent boundary remains distinct")
	_expect(bool(absent.get("valid", false)), "an absent boundary uses the default campaign")

	var endless := PackagedClientSmoke.parse_end_level_arguments(
		PackedStringArray(["--end-level=101"])
	)
	_expect(bool(endless.get("valid", false)), "level 101 is accepted for endless play")
	_expect(int(endless.get("value", 0)) == 101, "the endless boundary is reported exactly")

	var maximum := PackagedClientSmoke.parse_end_level_arguments(
		PackedStringArray(["--end-level=3999"])
	)
	_expect(bool(maximum.get("valid", false)), "the retail clamp is accepted")
	_expect(int(maximum.get("value", 0)) == 3999, "the retail clamp is preserved exactly")

	var overflow := PackagedClientSmoke.parse_end_level_arguments(
		PackedStringArray(["--end-level=4000"])
	)
	_expect(not bool(overflow.get("valid", true)), "levels beyond the retail clamp are rejected by the app")
	_expect(int(overflow.get("value", 0)) == 4000, "the rejected boundary is reported exactly")

	var malformed := PackagedClientSmoke.parse_end_level_arguments(
		PackedStringArray(["--end-level=not-a-number"])
	)
	_expect(not bool(malformed.get("valid", true)), "a malformed boundary is rejected")

	var duplicate := PackagedClientSmoke.parse_end_level_arguments(
		PackedStringArray(["--end-level=99", "--end-level=100"])
	)
	_expect(not bool(duplicate.get("valid", true)), "duplicate boundaries are rejected")

	if _failures.is_empty():
		print("PACKAGED CLIENT BOUNDARY TEST PASSED")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)

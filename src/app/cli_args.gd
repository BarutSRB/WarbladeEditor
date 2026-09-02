class_name WBCliArgs
extends RefCounted

var _values: Dictionary = {}
var _flags: Dictionary = {}


func _init(arguments: PackedStringArray = PackedStringArray()) -> void:
	var source := arguments
	if source.is_empty():
		source = OS.get_cmdline_user_args()
	for argument in source:
		if not argument.begins_with("--"):
			continue
		var separator := argument.find("=")
		if separator < 0:
			_flags[argument.substr(2)] = true
			continue
		var key := argument.substr(2, separator - 2)
		_values[key] = argument.substr(separator + 1)


func has_flag(name: String) -> bool:
	return bool(_flags.get(name, false))


func value(name: String, fallback: String = "") -> String:
	return str(_values.get(name, fallback))


func integer(name: String, fallback: int = 0) -> int:
	var raw := value(name)
	return fallback if raw.is_empty() or not raw.is_valid_int() else raw.to_int()


func all_values() -> Dictionary:
	return _values.duplicate(true)

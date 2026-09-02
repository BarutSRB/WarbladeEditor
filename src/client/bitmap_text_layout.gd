class_name WBBitmapTextLayout
extends RefCounted

var last_error := ""

var _cell_size := Vector2i.ZERO
var _advance := 0
var _space_advance := 0
var _glyph_indices: Dictionary = {}
var _source_rows: Dictionary = {}
var _pair_kerning: Dictionary = {}


func configure(contract: Dictionary) -> bool:
	last_error = ""
	_cell_size = _vector2i(contract.get("cell_size", []))
	_advance = int(contract.get("advance", 0))
	_space_advance = int(contract.get("space_advance", _advance))
	var glyphs_value: Variant = contract.get("glyph_indices", {})
	var rows_value: Variant = contract.get("source_rows", {"1": 0})
	var kerning_value: Variant = contract.get("pair_kerning", {})
	if (
		_cell_size.x <= 0
		or _cell_size.y <= 0
		or _advance <= 0
		or _space_advance <= 0
		or not glyphs_value is Dictionary
		or not rows_value is Dictionary
		or (rows_value as Dictionary).is_empty()
		or not kerning_value is Dictionary
	):
		return _fail("bitmap-font contract is incomplete")
	_glyph_indices = (glyphs_value as Dictionary).duplicate(true)
	_source_rows = (rows_value as Dictionary).duplicate(true)
	_pair_kerning = (kerning_value as Dictionary).duplicate(true)
	return true


func cell_size() -> Vector2i:
	return _cell_size


func line_width(text: String) -> int:
	var width := 0
	var previous := ""
	for index in range(text.length()):
		var character := text.substr(index, 1).to_upper()
		if character == "\n":
			break
		width += _pair_adjustment(previous, character)
		width += _space_advance if character == " " else _advance
		previous = character
	return maxi(0, width)


func text_size(text: String) -> Vector2i:
	var lines := text.split("\n", true)
	var width := 0
	for line in lines:
		width = maxi(width, line_width(str(line)))
	return Vector2i(width, maxi(1, lines.size()) * _cell_size.y)


func glyph_placements(
	text: String,
	origin: Vector2 = Vector2.ZERO,
	style: int = 1
) -> Array[Dictionary]:
	var placements: Array[Dictionary] = []
	if _cell_size == Vector2i.ZERO:
		return placements
	var cursor := Vector2.ZERO
	var previous := ""
	var source_y := int(_source_rows.get(str(style), _source_rows.values()[0]))
	for index in range(text.length()):
		var character := text.substr(index, 1).to_upper()
		if character == "\n":
			cursor.x = 0.0
			cursor.y += float(_cell_size.y)
			previous = ""
			continue
		cursor.x += float(_pair_adjustment(previous, character))
		if character != " " and _glyph_indices.has(character):
			var glyph_index := int(_glyph_indices[character])
			placements.append({
				"character": character,
				"source": Rect2i(
					glyph_index * _cell_size.x,
					source_y,
					_cell_size.x,
					_cell_size.y
				),
				"destination": Rect2(origin + cursor, Vector2(_cell_size)),
			})
		cursor.x += float(_space_advance if character == " " else _advance)
		previous = character
	return placements


func _pair_adjustment(previous: String, current: String) -> int:
	if previous.is_empty() or current.is_empty():
		return 0
	return int(_pair_kerning.get("%s|%s" % [previous, current], 0))


func _vector2i(value: Variant) -> Vector2i:
	if value is Array and (value as Array).size() == 2:
		return Vector2i(int(value[0]), int(value[1]))
	if value is Vector2i:
		return value
	return Vector2i.ZERO


func _fail(message: String) -> bool:
	last_error = message
	return false

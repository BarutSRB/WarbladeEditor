class_name WBHudOverlay
extends Control

const BitmapTextLayoutScript := preload("res://src/client/bitmap_text_layout.gd")

const DIGIT_SIZE := Vector2i(8, 9)
const DIGIT_PALETTE_WHITE := 0
const DIGIT_PALETTE_GREEN := 168
const DIGIT_PALETTE_ORANGE := 336
const REQUIRED_ASSET_KEYS: Array[String] = [
	"numbers", "abcd_2", "abcd_3", "bonuses", "marks", "div",
]

# Original sidebar layout, anchored on the retail executable HUD routines
# (money/right-align at 0x005d5ba7, reserve stack at 0x005d5ec8, EXTRA letter
# slots at 0x005d5ce2-0x005d5e21, and the top-center HISCORE/PL1 composition
# at 0x005d88f1-0x005d89b8) and the retained retail level-1 screenshot.
const RESERVE_ICON_SOURCE := Rect2i(0, 0, 16, 10)
const MULTIPLIER_X2_SOURCE := Rect2i(16, 0, 16, 10)
const MULTIPLIER_X5_SOURCE := Rect2i(32, 0, 16, 10)
const ARMOUR_PIP_SOURCES: Array[Rect2i] = [
	Rect2i(65, 0, 14, 8),
	Rect2i(49, 0, 14, 8),
]
const EXTRA_LETTER_SOURCE_X := 60
const EXTRA_LETTER_SOURCE_Y: Array[int] = [60, 80, 100, 120, 140]
const EXTRA_LETTER_SOURCE_SIZE := Vector2i(20, 20)
const RANK_MARK_ROWS := 6
const RANK_MARK_CELL := 20
const BAR_S_SOURCE := Rect2i(51, 22, 45, 5)
const BAR_B_SOURCE := Rect2i(51, 28, 45, 5)
const BAR_T_SOURCE := Rect2i(51, 34, 45, 5)
const SPEED_BASE_BY_DIFFICULTY := {
	"easy": 252.0 / 60.0,
	"normal": 240.0 / 60.0,
	"hard": 210.0 / 60.0,
	"ace": 180.0 / 60.0,
}
const SPEED_CAP_BY_DIFFICULTY := {
	"easy": 252.0 / 60.0 + 16.0 * 48.0 / 60.0,
	"normal": 240.0 / 60.0 + 16.0 * 42.0 / 60.0,
	"hard": 210.0 / 60.0 + 16.0 * 36.0 / 60.0,
	"ace": 180.0 / 60.0 + 16.0 * 30.0 / 60.0,
}
const BULLET_CAPACITY_MAX := 50
const BONUS_TIME_MAX_SECONDS := 45

var _assets := WBAssetLibrary.new()
var _textures: Dictionary = {}
var _snapshot: Dictionary = {}
var _level := Label.new()
var _score := Label.new()
var _lives := Label.new()
var _money := Label.new()
var _placeholder_notice := Label.new()
var _asset_error := Label.new()
var _bitmap_text := BitmapTextLayoutScript.new()
var _bitmap_text_ready := false
var _bitmap_text_3 := BitmapTextLayoutScript.new()
var _bitmap_text_3_ready := false
var _hiscore: int = 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for key in REQUIRED_ASSET_KEYS:
		var texture := _assets.texture(key)
		if texture != null:
			_textures[key] = texture
	for label in [_level, _score, _lives, _money]:
		_style_label(label)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		add_child(label)
	# Keep semantic Labels for accessibility while the retail atlas art owns
	# every pixel of the HUD.
	for bitmap_owned_label in [_level, _score, _lives, _money]:
		bitmap_owned_label.modulate.a = 0.0
	_level.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lives.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_money.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	_placeholder_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_placeholder_notice.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_placeholder_notice.add_theme_color_override("font_color", Color("#ffd36b"))
	_placeholder_notice.add_theme_font_size_override("font_size", 11)
	_placeholder_notice.text = "CONTENT PREVIEW — UNVERIFIED FIELDS REMAIN"
	_placeholder_notice.visible = false
	add_child(_placeholder_notice)

	_asset_error.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_asset_error.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_asset_error.add_theme_color_override("font_color", Color("#ff7d88"))
	_asset_error.add_theme_font_size_override("font_size", 11)
	var missing: Array[String] = []
	for key in REQUIRED_ASSET_KEYS:
		if not _textures.has(key):
			missing.append(key)
	_asset_error.text = "HUD ASSET ERROR: %s" % ", ".join(missing)
	_asset_error.visible = not missing.is_empty()
	add_child(_asset_error)
	var fonts: Dictionary = _assets.section("bitmap_fonts")
	var primary_value: Variant = fonts.get("abcd_2", {})
	_bitmap_text_ready = (
		primary_value is Dictionary
		and _bitmap_text.configure(primary_value as Dictionary)
	)
	if not _bitmap_text_ready:
		_asset_error.text += " BITMAP FONT CONTRACT ERROR"
		_asset_error.visible = true
	var secondary_value: Variant = fonts.get("abcd_3", {})
	_bitmap_text_3_ready = (
		secondary_value is Dictionary
		and _bitmap_text_3.configure(secondary_value as Dictionary)
	)
	if not _bitmap_text_3_ready:
		_asset_error.text += " SECONDARY FONT CONTRACT ERROR"
		_asset_error.visible = true

	resized.connect(_layout)
	_layout()


func _exit_tree() -> void:
	_assets.clear()
	_textures.clear()


func output_rect() -> Rect2:
	return WBAspectFit.calculate(size)


func required_asset_keys() -> Array[String]:
	return REQUIRED_ASSET_KEYS.duplicate()


func uses_original_hud_art() -> bool:
	return (
		_textures.has("numbers")
		and _textures.has("abcd_2")
		and _textures.has("abcd_3")
		and _textures.has("bonuses")
		and _textures.has("marks")
		and _textures.has("div")
		and _bitmap_text_ready
		and _bitmap_text_3_ready
	)


func digit_source_rect(digit: int, palette_offset: int = DIGIT_PALETTE_WHITE) -> Rect2i:
	var bounded_digit := clampi(digit, 0, 9)
	return Rect2i(
		palette_offset + bounded_digit * DIGIT_SIZE.x,
		0,
		DIGIT_SIZE.x,
		DIGIT_SIZE.y
	)


func set_hiscore(value: int) -> void:
	_hiscore = maxi(0, value)


func _layout() -> void:
	var arena := output_rect()
	if arena.size.x <= 0.0:
		return
	_set_logical_rect(_score, Rect2(260.0, 0.0, 280.0, 26.0), arena)
	_set_logical_rect(_lives, Rect2(2.0, 14.0, 60.0, 44.0), arena)
	_set_logical_rect(_money, Rect2(2.0, 0.0, 60.0, 12.0), arena)
	_set_logical_rect(_level, Rect2(2.0, 578.0, 60.0, 22.0), arena)
	_set_logical_rect(_placeholder_notice, Rect2(200.0, 38.0, 400.0, 28.0), arena)
	_set_logical_rect(_asset_error, Rect2(170.0, 70.0, 460.0, 30.0), arena)


func _set_logical_rect(control: Control, logical: Rect2, arena: Rect2) -> void:
	var scale := arena.size.x / 800.0
	control.position = arena.position + logical.position * scale
	control.size = logical.size * scale


func update_snapshot(snapshot: Dictionary) -> void:
	_snapshot = snapshot.duplicate(true)
	var shared: Dictionary = snapshot.get("shared", {})
	var p1 := _progression_for_seat(0, shared)
	var score := int(shared.get("score", p1.get("score", 0)))
	_hiscore = maxi(_hiscore, score)
	_score.text = "HISCORE %d  PL1 %d" % [_hiscore, score]
	_money.text = "$%d" % int(p1.get("money", 0))
	_lives.text = "FIGHTERS %d" % int(p1.get("lives", 0))
	_level.text = "LEVEL %04d" % int(_snapshot.get("level_id", 1))
	var time_trial: Dictionary = _snapshot.get("time_trial", {})
	if bool(time_trial.get("active", false)):
		# Retail match mode 6 counts its clock down on screen.
		var remaining_ms := maxi(0, int(time_trial.get("remaining_ms", 0)))
		_level.text = "LEVEL %04d  TIME %d:%02d" % [
			int(time_trial.get("authored_level_id", 1)),
			remaining_ms / 60000,
			(remaining_ms / 1000) % 60,
		]
	queue_redraw()


func show_placeholder_notice(visible: bool) -> void:
	_placeholder_notice.visible = visible


func _draw() -> void:
	if _snapshot.is_empty() or not uses_original_hud_art():
		return
	var arena := output_rect()
	if arena.size.x <= 0.0:
		return
	var shared: Dictionary = _snapshot.get("shared", {})
	_draw_top_scores(arena, shared)
	_draw_player_rail(0, false, arena, shared)
	var mode := str(_snapshot.get("mode", "solo"))
	if mode == "coop":
		_draw_player_rail(1, true, arena, shared)


func _draw_top_scores(arena: Rect2, shared: Dictionary) -> void:
	# Retail 0x005d88f1-0x005d89b8: HISCORE row at y=2, player row at y=14,
	# horizontally balanced around x=400 by digit count.
	var p1 := _progression_for_seat(0, shared)
	var score := int(shared.get("score", p1.get("score", 0)))
	var hiscore := maxi(_hiscore, score)
	var hiscore_digits := maxi(1, str(hiscore).length())
	var score_digits := maxi(1, str(score).length())
	_draw_font_text(
		"HISCORE", 2,
		Vector2(400.0 - 6.0 * hiscore_digits - 60.0, 2.0), arena
	)
	_draw_font_text(
		str(hiscore), 5,
		Vector2(400.0 - 6.0 * hiscore_digits + 36.0, 2.0), arena
	)
	var player_label := "PL1"
	_draw_font_text(
		player_label, 2,
		Vector2(400.0 - 6.0 * score_digits - 36.0, 14.0), arena
	)
	_draw_font_text(
		str(score), 1,
		Vector2(400.0 - 6.0 * score_digits + 12.0, 14.0), arena
	)


func _draw_player_rail(
		seat_id: int, right_side: bool, arena: Rect2, shared: Dictionary
	) -> void:
	var progression := _progression_for_seat(seat_id, shared)
	# Money: "$%d" right-aligned ending at x=32 (retail 0x005d5ba7), drawn
	# with the retail half-scale small text (4 px advance).
	var money_text := "$%d" % int(progression.get("money", 0))
	var money_width := 4.0 * money_text.length()
	var money_right := 32.0 if not right_side else 768.0
	_draw_tiny_text(
		money_text, 3,
		Vector2(money_right - money_width, 2.0), arena
	)
	# Reserve fighters: 16x10 thumbs stacked vertically (retail 0x005d5ec8),
	# one icon hidden for the active fighter, at most four shown.
	var lives := int(progression.get("lives", 0))
	var reserve_count := clampi(lives - 1, 0, 4)
	for index in range(reserve_count):
		_draw_region(
			"div", RESERVE_ICON_SOURCE,
			Vector2(24.0, 22.0 + 10.0 * index), arena, right_side
		)
	# Active points multiplier below the reserve stack (retail 0x005d6153+).
	var multiplier := int(progression.get("score_multiplier", 1))
	if multiplier == 2:
		_draw_region(
			"div", MULTIPLIER_X2_SOURCE, Vector2(24.0, 68.0), arena, right_side
		)
	elif multiplier == 5:
		_draw_region(
			"div", MULTIPLIER_X5_SOURCE, Vector2(24.0, 68.0), arena, right_side
		)
	# EXTRA letters, one 20x20 tile per collected letter (retail
	# 0x005d5ce2-0x005d5e21, slots 21 px apart from y=85).
	var letters := String(progression.get("extra_letters", "")).to_upper()
	for letter_index in range(5):
		var letter := "EXTRA".substr(letter_index, 1)
		if not letters.contains(letter):
			continue
		_draw_region(
			"bonuses",
			Rect2i(
				EXTRA_LETTER_SOURCE_X,
				EXTRA_LETTER_SOURCE_Y[letter_index],
				EXTRA_LETTER_SOURCE_SIZE.x,
				EXTRA_LETTER_SOURCE_SIZE.y
			),
			Vector2(22.0, 85.0 + 21.0 * letter_index), arena, right_side
		)
	# Armour charges (retail maximum two).
	var armour := clampi(
		int(progression.get("armour_fp", 0)) / 65536, 0, ARMOUR_PIP_SOURCES.size()
	)
	for pip in range(armour):
		_draw_region(
			"div", ARMOUR_PIP_SOURCES[pip],
			Vector2(24.0, 231.0 + 12.0 * pip), arena, right_side
		)
	# Collected rank marks as small coloured orbs in contract order.
	var rank_marks := int(progression.get("rank_markers", 0))
	for mark in range(RANK_MARK_ROWS):
		if (rank_marks & (1 << mark)) == 0:
			continue
		_draw_region(
			"marks",
			Rect2i(0, mark * RANK_MARK_CELL, RANK_MARK_CELL, RANK_MARK_CELL),
			Vector2(28.0, 193.0 + 10.0 * mark), arena, right_side,
			Vector2(8.0, 8.0)
		)
	_draw_info_bars(progression, arena, right_side)
	# Level indicator, bottom of the rail.
	_draw_small_text("LEVEL", 3, Vector2(7.0, 580.0), arena)
	_draw_number(
		int(_snapshot.get("level_id", 1)), 4,
		Vector2(14.0, 589.0), DIGIT_PALETTE_GREEN, arena
	)


func _draw_info_bars(
		progression: Dictionary, arena: Rect2, right_side: bool
	) -> void:
	# S / B / T labelled bars (retail letters with 45 px source strips).
	var difficulty := str(_snapshot.get("difficulty", "normal"))
	var speed_base: float = SPEED_BASE_BY_DIFFICULTY.get(difficulty, 4.0)
	var speed_cap: float = SPEED_CAP_BY_DIFFICULTY.get(difficulty, 15.2)
	var speed_fp := int(progression.get("speed_fp", 65536))
	var speed_fill := clampf(
		(float(speed_fp) / 65536.0 - speed_base) / (speed_cap - speed_base),
		0.0, 1.0
	)
	var bullet_fill := clampf(
		float(int(progression.get("bullet_capacity", 5)))
		/ float(BULLET_CAPACITY_MAX),
		0.0, 1.0
	)
	var time_fill := clampf(
		float(int(progression.get("bonus_time", 20)))
		/ float(BONUS_TIME_MAX_SECONDS),
		0.0, 1.0
	)
	_draw_tiny_text("S", 3, Vector2(2.0, 278.0), arena)
	_draw_tiny_text("B", 3, Vector2(2.0, 285.0), arena)
	_draw_tiny_text("T", 3, Vector2(2.0, 292.0), arena)
	_draw_bar(BAR_S_SOURCE, speed_fill, Vector2(7.0, 279.0), arena, right_side)
	_draw_bar(BAR_B_SOURCE, bullet_fill, Vector2(7.0, 286.0), arena, right_side)
	_draw_bar(BAR_T_SOURCE, time_fill, Vector2(7.0, 293.0), arena, right_side)
	# Wide gauge: remaining bonus-time capacity on the gray retail track.
	var track := Rect2(9.0, 331.0, 46.0, 9.0)
	_draw_track(track, time_fill, arena, right_side)


func _draw_font_text(
		text: String, style: int, logical_position: Vector2, arena: Rect2
	) -> void:
	if not _bitmap_text_3_ready:
		return
	var texture: Texture2D = _textures.get("abcd_3")
	if texture == null or text.is_empty():
		return
	var scale := arena.size.x / 800.0
	for placement in _bitmap_text_3.glyph_placements(text, logical_position, style):
		var logical_destination: Rect2 = placement["destination"]
		var destination := Rect2(
			arena.position + logical_destination.position * scale,
			logical_destination.size * scale
		)
		draw_texture_rect_region(texture, destination, placement["source"])


func _draw_tiny_text(
	text: String, style: int, logical_position: Vector2, arena: Rect2
) -> void:
	# The retail small text renderer (0x005d0ed0) draws the abcd_2 cells at
	# half scale with a 4 px advance (money, bar letters).
	if not _bitmap_text_ready:
		return
	var texture: Texture2D = _textures.get("abcd_2")
	if texture == null or text.is_empty():
		return
	var scale := arena.size.x / 800.0
	for placement in _bitmap_text.glyph_placements(text, Vector2.ZERO, style):
		var logical_destination: Rect2 = placement["destination"]
		var half_rect := Rect2(
			logical_position + logical_destination.position * 0.5,
			logical_destination.size * 0.5
		)
		var destination := Rect2(
			arena.position + half_rect.position * scale,
			half_rect.size * scale
		)
		draw_texture_rect_region(texture, destination, placement["source"])


func _draw_small_text(
		text: String, style: int, logical_position: Vector2, arena: Rect2
	) -> void:
	if not _bitmap_text_ready:
		return
	var texture: Texture2D = _textures.get("abcd_2")
	if texture == null or text.is_empty():
		return
	var scale := arena.size.x / 800.0
	for placement in _bitmap_text.glyph_placements(text, logical_position, style):
		var logical_destination: Rect2 = placement["destination"]
		var destination := Rect2(
			arena.position + logical_destination.position * scale,
			logical_destination.size * scale
		)
		draw_texture_rect_region(texture, destination, placement["source"])


func _draw_region(
		key: String,
		source: Rect2i,
		logical_position: Vector2,
		arena: Rect2,
		right_side: bool,
		logical_size: Vector2 = Vector2.ZERO
	) -> void:
	var texture: Texture2D = _textures.get(key)
	if texture == null:
		return
	var size := logical_size
	if size == Vector2.ZERO:
		size = Vector2(source.size)
	var x := logical_position.x
	if right_side:
		x = 800.0 - x - size.x
	var scale := arena.size.x / 800.0
	var destination := Rect2(
		arena.position + Vector2(x, logical_position.y) * scale,
		size * scale
	)
	draw_texture_rect_region(texture, destination, Rect2(source))


func _draw_bar(
		source: Rect2i,
		fill: float,
		logical_position: Vector2,
		arena: Rect2,
		right_side: bool
	) -> void:
	var width := 40.0
	var fill_width := width * fill
	var x := logical_position.x
	if right_side:
		x = 800.0 - x - width
	var scale := arena.size.x / 800.0
	# The track is the dim rail colour; the fill is the retail source strip.
	var track := Rect2(
		arena.position + Vector2(x, logical_position.y) * scale,
		Vector2(width, 5.0) * scale
	)
	draw_rect(track, Color(0.14, 0.18, 0.16, 0.9))
	if fill_width <= 0.0:
		return
	var texture: Texture2D = _textures.get("div")
	if texture == null:
		return
	var source_width := maxi(1, roundi(float(source.size.x) * fill))
	var fill_rect := Rect2(
		track.position,
		Vector2(fill_width * scale, track.size.y)
	)
	draw_texture_rect_region(
		texture, fill_rect,
		Rect2(source.position.x, source.position.y, source_width, source.size.y)
	)


func _draw_track(
		logical: Rect2, fill: float, arena: Rect2, right_side: bool
	) -> void:
	var x := logical.position.x
	if right_side:
		x = 800.0 - x - logical.size.x
	var scale := arena.size.x / 800.0
	var track := Rect2(
		arena.position + Vector2(x, logical.position.y) * scale,
		logical.size * scale
	)
	draw_rect(track, Color(0.43, 0.48, 0.47, 0.95))
	var fill_width := logical.size.x * clampf(fill, 0.0, 1.0)
	if fill_width <= 0.0:
		return
	var fill_rect := Rect2(
		track.position, Vector2(fill_width * scale, track.size.y)
	)
	draw_rect(fill_rect, Color(0.27, 0.87, 0.17, 0.95))


func _progression_for_seat(seat_id: int, fallback: Dictionary) -> Dictionary:
	for entry: Variant in _snapshot.get("players", []):
		if not entry is Dictionary:
			continue
		var player := entry as Dictionary
		if int(player.get("seat_id", -1)) == seat_id:
			var progression: Variant = player.get("progression", fallback)
			if progression is Dictionary:
				return progression as Dictionary
	return fallback


func _draw_number(
	value: int,
	digits: int,
	logical_position: Vector2,
	palette_offset: int,
	arena: Rect2
) -> void:
	var texture: Texture2D = _textures.get("numbers")
	if texture == null:
		return
	var digits_text := str(value).pad_zeros(digits).right(digits)
	var scale := arena.size.x / 800.0
	for index in range(digits_text.length()):
		var source := digit_source_rect(int(digits_text[index]), palette_offset)
		var logical_destination := Rect2(
			logical_position + Vector2(index * DIGIT_SIZE.x, 0.0),
			Vector2(DIGIT_SIZE)
		)
		var destination := Rect2(
			arena.position + logical_destination.position * scale,
			logical_destination.size * scale
		)
		draw_texture_rect_region(texture, destination, source)


func _style_label(label: Label) -> void:
	label.add_theme_font_size_override("font_size", 10)
	label.add_theme_color_override("font_color", Color("#e9f8ff"))
	label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.95))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)

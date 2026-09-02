class_name HitMaskAtlas
extends RefCounted

const FP_ONE: int = 65536
const FP_HALF: int = 32768

var image_width: int = 0
var image_height: int = 0
var frame_width: int = 0
var frame_height: int = 0
var columns: int = 0
var rows: int = 0
var frame_count: int = 0
var last_error: String = ""

var _pixels := PackedByteArray()


func load_file(
	path: String,
	atlas_width: int,
	atlas_height: int,
	sprite_frame_width: int,
	sprite_frame_height: int,
	expected_sha256: String = ""
) -> bool:
	if not FileAccess.file_exists(path):
		last_error = "hit mask file does not exist"
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		last_error = "hit mask file cannot be read"
		return false
	var pixels := file.get_buffer(file.get_length())
	if not expected_sha256.is_empty():
		var context := HashingContext.new()
		context.start(HashingContext.HASH_SHA256)
		context.update(pixels)
		if context.finish().hex_encode() != expected_sha256:
			last_error = "hit mask SHA-256 differs from its pinned content definition"
			return false
	return configure(
		pixels,
		atlas_width,
		atlas_height,
		sprite_frame_width,
		sprite_frame_height
	)


func configure(
	pixels: PackedByteArray,
	atlas_width: int,
	atlas_height: int,
	sprite_frame_width: int,
	sprite_frame_height: int
) -> bool:
	last_error = ""
	if atlas_width <= 0 or atlas_height <= 0:
		return _fail("atlas dimensions must be positive")
	if sprite_frame_width <= 0 or sprite_frame_height <= 0:
		return _fail("frame dimensions must be positive")
	if atlas_width % sprite_frame_width != 0 or atlas_height % sprite_frame_height != 0:
		return _fail("frame dimensions must divide the atlas")
	if pixels.size() != atlas_width * atlas_height:
		return _fail("hit mask byte count must equal atlas pixel count")
	for value in pixels:
		if value != 0 and value != 1:
			return _fail("hit mask bytes must be zero or one")
	image_width = atlas_width
	image_height = atlas_height
	frame_width = sprite_frame_width
	frame_height = sprite_frame_height
	columns = image_width / frame_width
	rows = image_height / frame_height
	frame_count = columns * rows
	_pixels = pixels.duplicate()
	return true


func is_valid() -> bool:
	return frame_count > 0 and _pixels.size() == image_width * image_height


func is_solid(frame_index: int, source_x: int, source_y: int) -> bool:
	if not is_valid() or frame_index < 0 or frame_index >= frame_count:
		return false
	if source_x < 0 or source_x >= frame_width or source_y < 0 or source_y >= frame_height:
		return false
	var frame_x: int = (frame_index % columns) * frame_width
	var frame_y: int = (frame_index / columns) * frame_height
	var atlas_index: int = (frame_y + source_y) * image_width + frame_x + source_x
	return _pixels[atlas_index] == 1


func is_solid_scaled(
	frame_index: int,
	local_x_fp: int,
	local_y_fp: int,
	logical_width: int,
	logical_height: int
) -> bool:
	return is_solid_source_rect_scaled(
		frame_source_rect(frame_index),
		local_x_fp,
		local_y_fp,
		logical_width,
		logical_height
	)


func frame_source_rect(frame_index: int) -> Rect2i:
	if frame_index < 0 or frame_index >= frame_count:
		return Rect2i()
	return Rect2i(
		(frame_index % columns) * frame_width,
		(frame_index / columns) * frame_height,
		frame_width,
		frame_height
	)


func is_solid_source_rect_scaled(
	source_rect: Rect2i,
	local_x_fp: int,
	local_y_fp: int,
	logical_width: int,
	logical_height: int
) -> bool:
	if not is_valid():
		return false
	if logical_width <= 0 or logical_height <= 0:
		return false
	if (
		source_rect.size.x <= 0
		or source_rect.size.y <= 0
		or source_rect.position.x < 0
		or source_rect.position.y < 0
		or source_rect.end.x > image_width
		or source_rect.end.y > image_height
	):
		return false
	if local_x_fp < 0 or local_y_fp < 0:
		return false
	if local_x_fp >= logical_width * FP_ONE or local_y_fp >= logical_height * FP_ONE:
		return false
	var source_x: int = source_rect.position.x + (
		local_x_fp * source_rect.size.x
	) / (logical_width * FP_ONE)
	var source_y: int = source_rect.position.y + (
		local_y_fp * source_rect.size.y
	) / (logical_height * FP_ONE)
	return _pixels[source_y * image_width + source_x] == 1


func overlaps(
	frame_index: int,
	x_fp: int,
	y_fp: int,
	logical_width: int,
	logical_height: int,
	other: HitMaskAtlas,
	other_frame_index: int,
	other_x_fp: int,
	other_y_fp: int,
	other_logical_width: int,
	other_logical_height: int
) -> bool:
	return overlaps_source_rect(
		frame_source_rect(frame_index),
		x_fp,
		y_fp,
		logical_width,
		logical_height,
		other,
		other.frame_source_rect(other_frame_index) if other != null else Rect2i(),
		other_x_fp,
		other_y_fp,
		other_logical_width,
		other_logical_height
	)


func overlaps_source_rect(
	source_rect: Rect2i,
	x_fp: int,
	y_fp: int,
	logical_width: int,
	logical_height: int,
	other: HitMaskAtlas,
	other_source_rect: Rect2i,
	other_x_fp: int,
	other_y_fp: int,
	other_logical_width: int,
	other_logical_height: int
) -> bool:
	if not is_valid() or other == null or not other.is_valid():
		return false
	var left_min_x := x_fp - logical_width * FP_ONE / 2
	var left_max_x := x_fp + logical_width * FP_ONE / 2
	var left_min_y := y_fp - logical_height * FP_ONE / 2
	var left_max_y := y_fp + logical_height * FP_ONE / 2
	var right_min_x := other_x_fp - other_logical_width * FP_ONE / 2
	var right_max_x := other_x_fp + other_logical_width * FP_ONE / 2
	var right_min_y := other_y_fp - other_logical_height * FP_ONE / 2
	var right_max_y := other_y_fp + other_logical_height * FP_ONE / 2
	var overlap_min_x: int = maxi(left_min_x, right_min_x)
	var overlap_max_x: int = mini(left_max_x, right_max_x)
	var overlap_min_y: int = maxi(left_min_y, right_min_y)
	var overlap_max_y: int = mini(left_max_y, right_max_y)
	if overlap_min_x >= overlap_max_x or overlap_min_y >= overlap_max_y:
		return false
	var first_cell_x := _floor_fp(overlap_min_x)
	var last_cell_x := _ceil_fp(overlap_max_x) - 1
	var first_cell_y := _floor_fp(overlap_min_y)
	var last_cell_y := _ceil_fp(overlap_max_y) - 1
	for world_y in range(first_cell_y, last_cell_y + 1):
		var cell_min_y := world_y * FP_ONE
		var cell_max_y := cell_min_y + FP_ONE
		var sample_y := maxi(cell_min_y, overlap_min_y) + (
			mini(cell_max_y, overlap_max_y) - maxi(cell_min_y, overlap_min_y)
		) / 2
		for world_x in range(first_cell_x, last_cell_x + 1):
			var cell_min_x := world_x * FP_ONE
			var cell_max_x := cell_min_x + FP_ONE
			var sample_x := maxi(cell_min_x, overlap_min_x) + (
				mini(cell_max_x, overlap_max_x) - maxi(cell_min_x, overlap_min_x)
			) / 2
			if not is_solid_source_rect_scaled(
				source_rect,
				sample_x - left_min_x,
				sample_y - left_min_y,
				logical_width,
				logical_height
			):
				continue
			if other.is_solid_source_rect_scaled(
				other_source_rect,
				sample_x - right_min_x,
				sample_y - right_min_y,
				other_logical_width,
				other_logical_height
			):
				return true
	return false


func _floor_fp(value: int) -> int:
	if value >= 0:
		return value / FP_ONE
	return -((-value + FP_ONE - 1) / FP_ONE)


func _ceil_fp(value: int) -> int:
	if value >= 0:
		return (value + FP_ONE - 1) / FP_ONE
	return -((-value) / FP_ONE)


func _fail(message: String) -> bool:
	last_error = message
	return false

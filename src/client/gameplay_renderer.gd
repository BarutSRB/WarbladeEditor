class_name WBGameplayRenderer
extends Control

const SpriteFrameCatalogScript := preload("res://src/shared/sprite_frame_catalog.gd")
const PresentationEffectsScript := preload("res://src/client/presentation_effects.gd")

const FP_ONE := 65536.0
const TICK_MICROSECONDS := 16666.6667
const LOGICAL_WIDTH := 800.0
const LOGICAL_HEIGHT := 600.0
const PLAYFIELD_LEFT := 64.0
const PLAYFIELD_RIGHT := 736.0
const BACKGROUND_TILE_HEIGHT := 600.0
const BACKGROUND_SCROLL_DIVISOR := 20.0
const THRUST_FRAME_SIZE := Vector2i(16, 25)
const THRUST_FRAME_COUNT := 10
const THRUST_CENTER_OFFSET := Vector2(0.0, 19.5)
const ENEMY_PROJECTILE_FRAME_SIZE := Vector2i(32, 32)
const ENEMY_PROJECTILE_SOURCE_X := 480
const ENEMY_PROJECTILE_FRAME_COUNT := 2
const BOSS_PART_SIZE := Vector2(256.0, 64.0)
const BOSS_SHEET_SIZE := Vector2i(576, 96)
const BOSS_PART_COUNT := 2
const BOSS_SOURCE_RECTS := {
	"0": Rect2(0.0, 0.0, 256.0, 64.0),
	"1": Rect2(256.0, 0.0, 256.0, 64.0),
}
const PICKUP_ROW_Y := {
	"money": 600,
	"armour": 500,
	"letter": 60,
	"bonus_time": 480,
}
const REQUIRED_ASSET_KEYS: Array[String] = [
	"fighter1",
	"fighter2",
	"figterfire2",
	"malfunction1",
	"malfunction3",
	"malfunction4",
	"alien_malfold_blue",
	"alien_malfold_green",
	"weapons_big",
	"rocket",
	"bonuses",
	"marks",
	"memoryblocks",
	"meteors",
	"meteorbonuses",
	"meteormeter2",
	"diamantbig",
	"stars1",
	"stars2",
	"stars3",
	"stars4",
	"stars5",
	"border",
	"border_easy",
	"border_hard",
	"border_ace",
	# Hurry-up secret ships (docs/evidence/HURRY_UP_SECRET_SHIPS.md).
	"mothership2",
	"moneyship",
	# The shared effect pool: planet debris draws on the rocket sheet and the
	# guard ship's beam on its own.
	"beam",
	# The two independently spawned secret ships (gap G20).
	"moneysucker2",
	"guard",
]

var _assets := WBAssetLibrary.new()
var _sprite_frames := SpriteFrameCatalogScript.new()
var _effects := PresentationEffectsScript.new()
var _textures: Dictionary = {}
var _presentation_errors: Array[String] = []
var _error_set: Dictionary = {}
var _previous: Dictionary = {}
var _current: Dictionary = {}
var _received_at_usec := 0
var _interpolation_window_usec := TICK_MICROSECONDS
var _entity_previous: Dictionary = {}
var _effects_mode := "enhanced"
var _texture_filter_mode := "smooth"
var _background_scroll_offset := 0.0
var _background_draw_offset := 0.0
var _background_previous_draw_offset := 0.0
var _background_last_tick := -1
var _background_has_authoritative_offset := false


func _ready() -> void:
	if not _sprite_frames.load_file():
		_record_error("cannot load sprite frames: %s" % _sprite_frames.last_error)
	_load_required_assets()
	_effects.configure(_assets, _effects_mode)
	_effects.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_effects)
	set_process(true)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func configure(options: Dictionary) -> void:
	var requested_mode := str(options.get("effects_mode", options.get("presentation_mode", "enhanced")))
	_effects_mode = "original" if requested_mode.to_lower() == "original" else "enhanced"
	_effects.set_effects_mode(_effects_mode)
	var requested_filter := str(options.get("texture_filter", "smooth")).to_lower()
	_texture_filter_mode = "sharp" if requested_filter == "sharp" else "smooth"
	texture_filter = (
		CanvasItem.TEXTURE_FILTER_NEAREST
		if _texture_filter_mode == "sharp"
		else CanvasItem.TEXTURE_FILTER_LINEAR
	)
	_effects.reset()
	_background_scroll_offset = 0.0
	_background_draw_offset = 0.0
	_background_previous_draw_offset = 0.0
	_background_last_tick = -1
	_background_has_authoritative_offset = false


func set_snapshot(snapshot: Dictionary) -> void:
	_update_background_scroll(snapshot)
	_previous = _current
	_current = snapshot.duplicate(true)
	if (
		not _previous.is_empty()
		and int(_previous.get("level_id", -1)) == int(_current.get("level_id", -2))
		and str(_previous.get("phase", "")) == str(_current.get("phase", ""))
	):
		var tick_delta := int(_current.get("tick", 0)) - int(_previous.get("tick", 0))
		_interpolation_window_usec = maxf(
			TICK_MICROSECONDS,
			float(maxi(1, tick_delta)) * TICK_MICROSECONDS
		)
	else:
		_previous.clear()
		_interpolation_window_usec = TICK_MICROSECONDS
	_received_at_usec = Time.get_ticks_usec()
	_entity_previous = _index_entities(_previous)
	_effects.set_snapshot(_current)
	queue_redraw()


func output_rect() -> Rect2:
	return WBAspectFit.calculate(size)


func playfield_rect() -> Rect2:
	var arena := output_rect()
	var scale := arena.size.x / LOGICAL_WIDTH
	return Rect2(
		arena.position + Vector2(PLAYFIELD_LEFT * scale, 0.0),
		Vector2((PLAYFIELD_RIGHT - PLAYFIELD_LEFT) * scale, arena.size.y)
	)


static func background_destination_quads(offset: float) -> Array[Rect2]:
	return [
		Rect2(PLAYFIELD_LEFT, offset - BACKGROUND_TILE_HEIGHT, 672.0, BACKGROUND_TILE_HEIGHT),
		Rect2(PLAYFIELD_LEFT, offset, 672.0, BACKGROUND_TILE_HEIGHT),
	]


static func advance_background_scroll(
	offset: float,
	warp_scale: float,
	phase: String = "warp",
	update_count: int = 1
) -> float:
	if phase != "warp" or update_count <= 0:
		return offset
	var result := offset
	for _update in range(update_count):
		result += warp_scale / BACKGROUND_SCROLL_DIVISOR
		if result >= BACKGROUND_TILE_HEIGHT:
			result -= BACKGROUND_TILE_HEIGHT
		if result <= 0.0:
			result += BACKGROUND_TILE_HEIGHT
	return result


func background_scroll_offset() -> float:
	return _background_scroll_offset


func background_draw_offset() -> float:
	return _background_draw_offset


func interpolated_background_draw_offset(alpha: float) -> float:
	if not _background_has_authoritative_offset:
		return _background_draw_offset
	var delta := _background_draw_offset - _background_previous_draw_offset
	if delta > BACKGROUND_TILE_HEIGHT * 0.5:
		delta -= BACKGROUND_TILE_HEIGHT
	elif delta < -BACKGROUND_TILE_HEIGHT * 0.5:
		delta += BACKGROUND_TILE_HEIGHT
	return fposmod(
		_background_previous_draw_offset + delta * clampf(alpha, 0.0, 1.0),
		BACKGROUND_TILE_HEIGHT
	)


func interpolation_alpha(now_usec: int = -1) -> float:
	if _previous.is_empty() or _current.is_empty():
		return 1.0
	var now := Time.get_ticks_usec() if now_usec < 0 else now_usec
	return clampf(float(now - _received_at_usec) / _interpolation_window_usec, 0.0, 1.0)


func required_asset_keys() -> Array[String]:
	var result := _renderer_asset_keys()
	for key in _effects.required_asset_keys():
		if not result.has(key):
			result.append(key)
	return result


func _renderer_asset_keys() -> Array[String]:
	var result := REQUIRED_ASSET_KEYS.duplicate()
	for key in _sprite_frames.enemy_sheet_ids():
		if not result.has(key):
			result.append(key)
		if key.begins_with("alien_big"):
			var mask_key := "%s_mask" % key
			if not result.has(mask_key):
				result.append(mask_key)
	return result


func resolved_asset_keys() -> Array[String]:
	var result: Array[String] = []
	for key in _textures:
		result.append(str(key))
	result.sort()
	return result


func presentation_errors() -> Array[String]:
	var result := _presentation_errors.duplicate()
	for message in _effects.presentation_errors():
		if not result.has(message):
			result.append(message)
	return result


func has_presentation_error() -> bool:
	return not presentation_errors().is_empty()


func pickup_texture_key() -> String:
	return "bonuses"


func pickup_source_rect(kind: String, frame: int = 0, variant: int = 0) -> Rect2i:
	if not PICKUP_ROW_Y.has(kind):
		return Rect2i()
	var source_y := int(PICKUP_ROW_Y[kind])
	if kind == "letter":
		source_y += clampi(variant, 0, 4) * 20
	elif kind == "money":
		var money_rows := [600, 580, 620, 640]
		source_y = money_rows[posmod(variant, money_rows.size())]
	return Rect2i(posmod(frame, 10) * 20, source_y, 20, 20)


func thrust_frame_size() -> Vector2i:
	return THRUST_FRAME_SIZE


func thrust_frame_count() -> int:
	return THRUST_FRAME_COUNT


func thrust_center_offset() -> Vector2:
	return THRUST_CENTER_OFFSET


func enemy_projectile_source_rect(
	frame: int = 0,
	projectile_type: int = 7
) -> Rect2i:
	return Rect2i(
		448 if projectile_type == 6 else ENEMY_PROJECTILE_SOURCE_X,
		posmod(frame, ENEMY_PROJECTILE_FRAME_COUNT) * ENEMY_PROJECTILE_FRAME_SIZE.y,
		ENEMY_PROJECTILE_FRAME_SIZE.x,
		ENEMY_PROJECTILE_FRAME_SIZE.y
	)


func projectile_snapshot_source_rect(projectile: Dictionary) -> Rect2i:
	var owner_kind := str(projectile.get("owner_kind", "player"))
	if owner_kind == "player":
		if str(projectile.get("projectile_kind", "")) == "rocket_missile":
			if str(projectile.get("sprite_sheet_id", "")) != "rocket":
				return Rect2i()
			var rocket_source: Variant = projectile.get("source_rect")
			if not rocket_source is Array or (rocket_source as Array).size() != 4:
				return Rect2i()
			for coordinate: Variant in rocket_source as Array:
				if (
					typeof(coordinate) not in [TYPE_INT, TYPE_FLOAT]
					or float(coordinate) != float(int(coordinate))
				):
					return Rect2i()
			var heading := int(projectile.get("heading", 0))
			var animation_row := int(projectile.get("animation_row", -1))
			if heading < 1 or heading > 32 or animation_row < 0 or animation_row > 2:
				return Rect2i()
			var rocket_rect := Rect2i(
				int((rocket_source as Array)[0]),
				int((rocket_source as Array)[1]),
				int((rocket_source as Array)[2]),
				int((rocket_source as Array)[3])
			)
			var expected_rocket_rect := Rect2i(
				(heading - 1) * 24,
				animation_row * 24,
				24,
				24
			)
			return rocket_rect if rocket_rect == expected_rocket_rect else Rect2i()
		return _sprite_frames.projectile_source_rect(
			int(projectile.get("prototype_id", -1))
		)
	if owner_kind != "boss":
		return enemy_projectile_source_rect(
			int(projectile.get("animation_frame", 0)),
			int(projectile.get("enemy_projectile_type", 7))
		)
	var projectile_type := int(projectile.get("enemy_projectile_type", -1))
	var frame := int(projectile.get("animation_frame", -1))
	var source_value: Variant = projectile.get("source_rect")
	var expected_sheet := _sprite_frames.enemy_sheet_for_resource(
		int(_current.get("level_id", 0)),
		1,
		_level_namespace()
	)
	if (
		projectile_type not in [14, 15]
		or not expected_sheet.begins_with("alien_big")
		or str(projectile.get("enemy_sheet", "")) != expected_sheet
		or not source_value is Array
		or (source_value as Array).size() != 4
	):
		return Rect2i()
	for coordinate: Variant in source_value as Array:
		if (
			typeof(coordinate) not in [TYPE_INT, TYPE_FLOAT]
			or float(coordinate) != float(int(coordinate))
		):
			return Rect2i()
	var source := Rect2i(
		int((source_value as Array)[0]),
		int((source_value as Array)[1]),
		int((source_value as Array)[2]),
		int((source_value as Array)[3])
	)
	var expected := Rect2i()
	if projectile_type == 14:
		if frame < 0 or frame > 5:
			return Rect2i()
		expected = Rect2i(
			512 if frame < 3 else 544,
			posmod(frame, 3) * 32,
			32,
			32
		)
	else:
		if frame < 0:
			return Rect2i()
		expected = Rect2i(frame * 32, 64, 32, 32)
	return source if source == expected else Rect2i()


func enemy_projectile_texture_key(projectile: Dictionary) -> String:
	var declared_sheet := str(projectile.get("sprite_sheet_id", ""))
	if projectile.has("enemy_sheet"):
		var enemy_sheet := str(projectile.get("enemy_sheet", ""))
		if not declared_sheet.is_empty() and declared_sheet != enemy_sheet:
			return ""
		return enemy_sheet
	var expected_sheet := _sprite_frames.enemy_sheet_for_level(
		int(_current.get("level_id", 0)),
		_level_namespace()
	)
	if not declared_sheet.is_empty() and declared_sheet != expected_sheet:
		return ""
	return expected_sheet


## Retail match mode 6 numbers its own fifteen authored levels from one, so its
## sprite bindings live in a separate catalog namespace from the campaign.
func _level_namespace() -> String:
	return (
		WBSpriteFrameCatalog.LEVEL_NAMESPACE_TIME_TRIAL
		if str(_current.get("mode", "")) == "time_trial"
		else ""
	)


func active_effect_count() -> int:
	return _effects.active_effect_count()


func explosion_frame_count() -> int:
	return _effects.explosion_frame_count()


func effects_mode() -> String:
	return _effects.effects_mode()


func texture_filter_mode() -> String:
	return _texture_filter_mode


func has_seen_effect_event(event_id: int) -> bool:
	return _effects.has_seen_event(event_id)


func meteor_slot_interpolation_key(slot: Dictionary) -> String:
	return "meteor_slot:%d:%d" % [
		int(slot.get("slot_id", -1)),
		int(slot.get("spawn_serial", 0)),
	]


func meteor_ship_interpolation_key(bonus_mode: Dictionary) -> String:
	return "meteor_ship:%d:%d" % [
		int(bonus_mode.get("owner_seat_id", -1)),
		int(bonus_mode.get("entry_tick", -1)),
	]


func boss_part_interpolation_key(part: Dictionary) -> String:
	return "boss_part:%s" % str(part.get("part_id", ""))


func boss_part_source_rect(part: Dictionary) -> Rect2:
	var part_id := str(part.get("part_id", ""))
	if not BOSS_SOURCE_RECTS.has(part_id):
		return Rect2()
	var source_value: Variant = part.get("source_rect", [])
	if not source_value is Array or (source_value as Array).size() != 4:
		return Rect2()
	for coordinate: Variant in source_value as Array:
		if (
			typeof(coordinate) not in [TYPE_INT, TYPE_FLOAT]
			or float(coordinate) != float(int(coordinate))
		):
			return Rect2()
	var source := _rect_from_value(source_value)
	if source != BOSS_SOURCE_RECTS[part_id]:
		return Rect2()
	return source


func boss_part_logical_destination(
	part: Dictionary,
	position: Vector2 = Vector2.INF
) -> Rect2:
	if position == Vector2.INF:
		var direct_destination := _boss_part_direct_destination(part)
		if direct_destination.size == BOSS_PART_SIZE:
			return direct_destination
		var position_entity := _boss_part_position_entity(part)
		if position_entity.is_empty():
			return Rect2()
		position = _position_from(position_entity)
	return Rect2(position - BOSS_PART_SIZE * 0.5, BOSS_PART_SIZE)


func _boss_part_direct_destination(part: Dictionary) -> Rect2:
	var destination_value: Variant = part.get("destination_rect", [])
	if not destination_value is Array or (destination_value as Array).size() != 4:
		return Rect2()
	for coordinate: Variant in destination_value as Array:
		if (
			typeof(coordinate) not in [TYPE_INT, TYPE_FLOAT]
			or float(coordinate) != float(int(coordinate))
		):
			return Rect2()
	var destination := _rect_from_value(destination_value)
	if destination.size != BOSS_PART_SIZE:
		return Rect2()
	return destination


func _boss_part_position_entity(part: Dictionary) -> Dictionary:
	if part.has("destination_rect"):
		var destination := _boss_part_direct_destination(part)
		if destination.size != BOSS_PART_SIZE:
			return {}
		var center := destination.position + destination.size * 0.5
		return {
			"x_fp": roundi(center.x * FP_ONE),
			"y_fp": roundi(center.y * FP_ONE),
		}
	if (
		not part.has("x_fp")
		or not part.has("y_fp")
		or typeof(part.x_fp) not in [TYPE_INT, TYPE_FLOAT]
		or typeof(part.y_fp) not in [TYPE_INT, TYPE_FLOAT]
	):
		return {}
	for dimension_key in ["width", "height"]:
		if (
			part.has(dimension_key)
			and typeof(part[dimension_key]) not in [TYPE_INT, TYPE_FLOAT]
		):
			return {}
	if (
		float(part.get("width", BOSS_PART_SIZE.x)) != BOSS_PART_SIZE.x
		or float(part.get("height", BOSS_PART_SIZE.y)) != BOSS_PART_SIZE.y
	):
		return {}
	return {
		"x_fp": part.x_fp,
		"y_fp": part.y_fp,
	}


func boss_render_commands(boss: Dictionary, alpha: float = 1.0) -> Array[Dictionary]:
	var commands: Array[Dictionary] = []
	if not bool(boss.get("active", false)):
		return commands
	var parts_value: Variant = boss.get("parts", [])
	if not parts_value is Array:
		_record_error("active boss parts must be an array")
		return commands
	var parts := parts_value as Array
	if parts.size() != BOSS_PART_COUNT:
		_record_error("active boss must publish exactly two renderer parts")
		return commands
	var ordered_sheets := _sprite_frames.enemy_sheets_for_level(
		int(_current.get("level_id", 0)),
		_level_namespace()
	)
	if ordered_sheets.size() != 6:
		_record_error("active boss level must declare exactly six ordered enemy sheets")
		return commands
	var stage := int(boss.get("stage", -1))
	if stage < 0 or stage >= ordered_sheets.size():
		_record_error("active boss stage must select one of the current level's enemy sheets")
		return commands
	var sheet := str(boss.get("sheet", ""))
	var expected_sheet := ordered_sheets[stage]
	var seen_part_ids: Dictionary = {}
	var known_sheets := _sprite_frames.enemy_sheet_ids()
	if (
		sheet != expected_sheet
		or not expected_sheet.begins_with("alien_big")
		or not known_sheets.has(sheet)
	):
		_record_error(
			"active boss stage %d references unknown or mismatched enemy sheet: %s"
			% [stage, sheet]
		)
		return commands
	var commands_by_part_id: Dictionary = {}
	for entry: Variant in parts:
		if not entry is Dictionary:
			_record_error("active boss part must be an object")
			continue
		var part := entry as Dictionary
		if not part.has("part_id") or str(part.get("part_id", "")).is_empty():
			_record_error("active boss part is missing a stable part_id")
			continue
		var part_id := str(part.part_id)
		if seen_part_ids.has(part_id):
			_record_error("active boss has duplicate part_id %s" % part_id)
			continue
		seen_part_ids[part_id] = true
		if not BOSS_SOURCE_RECTS.has(part_id):
			_record_error("active boss has unknown part_id %s" % part_id)
			continue
		if part.has("sheet") and str(part.sheet) != sheet:
			_record_error(
				"boss part %s references a sheet other than the active boss sheet"
				% part_id
			)
			continue
		var render_handle := str(part.get("render_handle", sheet))
		if render_handle not in [sheet, "%s_mask" % sheet]:
			_record_error(
				"boss part %s references an invalid render handle for stage %d"
				% [part_id, stage]
			)
			continue
		var source := boss_part_source_rect(part)
		if source != BOSS_SOURCE_RECTS[part_id]:
			_record_error(
				"boss part %s has incorrect state-13 source geometry"
				% part_id
			)
			continue
		var position_entity := _boss_part_position_entity(part)
		if position_entity.is_empty():
			_record_error("boss part %s has incorrect state-13 destination geometry" % part_id)
			continue
		var position := _interpolated_position(
			boss_part_interpolation_key(part),
			position_entity,
			alpha
		)
		var destination := boss_part_logical_destination(part, position)
		if destination.size != BOSS_PART_SIZE:
			_record_error("boss part %s has incorrect state-13 destination geometry" % part_id)
			continue
		commands_by_part_id[part_id] = {
			"part_id": part_id,
			"sheet": render_handle,
			"source_rect": source,
			"logical_destination": destination,
		}
	if commands_by_part_id.size() != BOSS_PART_COUNT:
		return commands
	for part_id in ["0", "1"]:
		commands.append(commands_by_part_id[part_id])
	return commands


func meteor_ship_render_source_rect(ship: Dictionary) -> Rect2:
	var render_source := _rect_from_value(ship.get("render_source_rect", []))
	if render_source.size.x > 0.0 and render_source.size.y > 0.0:
		return render_source
	var render_width := maxf(1.0, float(ship.get("width", 40)))
	var render_height := maxf(1.0, float(ship.get("height", 28)))
	return Rect2(
		float(int(ship.get("frame_index", 0))) * render_width,
		0.0,
		render_width,
		render_height
	)


func meteor_ship_render_destination(ship: Dictionary, center: Vector2) -> Rect2:
	var render_size := meteor_ship_render_source_rect(ship).size
	return Rect2(center - render_size * 0.5, render_size)


func gem_drop_slot_interpolation_key(
	bonus_mode: Dictionary,
	slot: Dictionary
) -> String:
	# Older Gem Drop snapshots do not carry spawn_serial. Their x coordinate,
	# speed, colour, and entry tick are invariant for one fall, so together they
	# prevent a recycled slot from interpolating across its offscreen respawn.
	return "gem_drop_slot:%d:%d:%d:%d:%d:%d" % [
		int(bonus_mode.get("entry_tick", -1)),
		int(slot.get("slot_id", -1)),
		int(slot.get("spawn_serial", slot.get("x_fp", 0))),
		int(slot.get("fall_speed_fp", 0)),
		int(slot.get("source_x", 0)),
		int(bonus_mode.get("owner_seat_id", -1)),
	]


func gem_drop_player_interpolation_key(
	bonus_mode: Dictionary,
	player: Dictionary
) -> String:
	return "gem_drop_player:%d:%d" % [
		int(bonus_mode.get("entry_tick", -1)),
		int(player.get("seat_id", -1)),
	]


func gem_drop_presentation_state(bonus_mode: Dictionary) -> Dictionary:
	var super_drop := bool(bonus_mode.get("super_gem_drop", false))
	var now_ms := int(bonus_mode.get("now_ms", 0))
	var intro_until_ms := int(bonus_mode.get("intro_until_ms", now_ms))
	return {
		"title": (
			"S U P E R   G E M   D R O P"
			if super_drop
			else "G E M   D R O P"
		),
		# The retail unsigned deadline gate ends at equality, not one update
		# later. Prefer the absolute times so presentation follows that boundary.
		"show_get_ready": now_ms < intro_until_ms,
		"intro_remaining_ms": maxi(0, intro_until_ms - now_ms),
		"stage": str(bonus_mode.get("stage", "")),
	}


func level_eight_presentation_state(level_eight_bonus: Dictionary) -> Dictionary:
	if not bool(level_eight_bonus.get("active", false)):
		return {}
	var players: Array[Dictionary] = []
	for player_value in level_eight_bonus.get("players", []):
		if not player_value is Dictionary:
			continue
		var player := player_value as Dictionary
		if not bool(player.get("participating", false)):
			continue
		players.append({
			"seat_id": int(player.get("seat_id", players.size())),
			"hits": int(player.get("hud_hits", player.get("actual_hits", 0))),
			"total_targets": int(player.get("total_targets", 0)),
			"misses": int(player.get("hud_misses", player.get("misses", 0))),
			"perfect_awarded": bool(player.get("perfect_awarded", false)),
			"perfect_reward": int(player.get("perfect_reward", 0)),
			"next_perfect_reward": int(player.get("next_perfect_reward", 0)),
		})
	var result_initialized := bool(level_eight_bonus.get("result_initialized", false))
	var title := str(level_eight_bonus.get("header", "")).strip_edges()
	if title.is_empty():
		title = "BONUS TARGETS"
	return {
		"kind": "results" if result_initialized else "hud",
		"title": title,
		"players": players,
		"reveal_countdown": int(level_eight_bonus.get("reveal_countdown", 0)),
		"reveal_deadline_ms": int(level_eight_bonus.get("reveal_deadline_ms", 0)),
		"result_deadline_ms": int(level_eight_bonus.get("result_deadline_ms", 0)),
	}


func memory_station_presentation_state(bonus_mode: Dictionary) -> Dictionary:
	var now_ms := int(bonus_mode.get("now_ms", 0))
	if bool(bonus_mode.get("gem_drop_active", false)):
		var super_drop := bool(bonus_mode.get("super_gem_drop", false))
		return {
			"kind": "super_gem_drop" if super_drop else "gem_drop",
			"title": "SUPER GEM DROP" if super_drop else "GEM DROP",
			"remaining_ms": maxi(
				0,
				int(bonus_mode.get("gem_drop_until_ms", now_ms)) - now_ms
			),
		}
	var stage := str(bonus_mode.get("stage", ""))
	var completion_value: Variant = bonus_mode.get("completion", {})
	var completion: Dictionary = (
		completion_value as Dictionary if completion_value is Dictionary else {}
	)
	if stage == "success_hold" or bool(completion.get("success", false)):
		return {
			"kind": "success",
			"title": "MEMORY STATION COMPLETE",
			"matches": int(completion.get("matches", bonus_mode.get("matches", 0))),
			"mismatches": int(
				completion.get("mismatches", bonus_mode.get("mismatches", 0))
			),
			"tries": int(completion.get("tries", bonus_mode.get("tries", 0))),
			"score_award": int(completion.get("score_award", 0)),
			"remaining_ms": maxi(
				0,
				int(bonus_mode.get("success_deadline_ms", now_ms)) - now_ms
			),
		}
	if stage == "complete" and not completion.is_empty():
		return {
			"kind": "failure",
			"title": "MEMORY STATION FAILED",
			"matches": int(completion.get("matches", bonus_mode.get("matches", 0))),
			"mismatches": int(
				completion.get("mismatches", bonus_mode.get("mismatches", 0))
			),
			"tries": int(completion.get("tries", bonus_mode.get("tries", 0))),
		}
	return {}


func meteor_storm_result_presentation_state(bonus_mode: Dictionary) -> Dictionary:
	var completion_value: Variant = bonus_mode.get("completion", {})
	if not completion_value is Dictionary or (completion_value as Dictionary).is_empty():
		return {}
	var completion := completion_value as Dictionary
	var success := bool(completion.get("success", false))
	var now_ms := int(bonus_mode.get("now_ms", 0))
	return {
		"kind": "success" if success else "failure",
		"title": "METEOR STORM COMPLETE" if success else "METEOR COLLISION",
		"tier": str(completion.get("tier", "")).to_upper().replace("_", " "),
		"speed_percentage": float(completion.get("speed_percentage", 0.0)),
		"score_reward": int(completion.get("score_reward", 0)),
		"cash_reward": int(completion.get("cash_reward", 0)),
		"score_delta_total": int(completion.get("score_delta_total", 0)),
		"cash_delta_total": int(completion.get("cash_delta_total", 0)),
		"gem_count_delta_total": int(completion.get("gem_count_delta_total", 0)),
		"meteor_score_delta_total": int(
			completion.get("meteor_score_delta_total", 0)
		),
		"meteor_streak": int(completion.get("meteor_streak", 0)),
		"collision_slot_id": int(completion.get("collision_slot_id", -1)),
		"drunk_reward": bool(completion.get("drunk_reward", false)),
		"remaining_ms": maxi(
			0,
			int(bonus_mode.get("transition_until_ms", now_ms)) - now_ms
		),
	}


func _process(_delta: float) -> void:
	if _current.is_empty():
		return
	var alpha := interpolation_alpha()
	var current_tick := float(_current.get("tick", 0))
	var tick_span := 3.0
	if not _previous.is_empty():
		tick_span = float(maxi(1, int(_current.get("tick", 0)) - int(_previous.get("tick", 0))))
	_effects.set_render_tick(current_tick + alpha * tick_span)
	queue_redraw()


func _exit_tree() -> void:
	_assets.clear()
	_textures.clear()
	_previous.clear()
	_current.clear()
	_entity_previous.clear()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("#03050d"))
	var arena := output_rect()
	if arena.size.x <= 0.0:
		return
	draw_rect(arena, Color("#071022"))
	if _current.is_empty():
		return
	var level_id := int(_current.get("level_id", 0))
	var background_key := _background_texture_key(level_id)
	if background_key.is_empty():
		_record_error("level %d has no authored background mapping" % level_id)
	var background := _texture(background_key) if not background_key.is_empty() else null
	if background != null:
		_draw_original_background(background, arena)
	var bonus_mode: Dictionary = _current.get("bonus_mode", {})
	match str(bonus_mode.get("kind", "")):
		"memory_station":
			_draw_memory_station(arena, bonus_mode)
			_draw_presentation_errors(arena)
			return
		"meteor_storm":
			_draw_meteor_storm(arena, bonus_mode, interpolation_alpha())
			_draw_presentation_errors(arena)
			return
		"gem_drop":
			_draw_gem_drop(arena, bonus_mode, interpolation_alpha())
			_draw_presentation_errors(arena)
			return
	var alpha := interpolation_alpha()
	_draw_enemies(arena, alpha)
	_draw_boss(arena, alpha)
	_draw_projectiles(arena, alpha)
	_draw_effect_objects(arena, alpha)
	_draw_pickups(arena, alpha)
	_draw_players(arena, alpha)
	_draw_side_rails(arena)
	draw_rect(arena, Color("#3a6b9b80"), false, maxf(1.0, arena.size.x / LOGICAL_WIDTH))
	_draw_level_eight_presentation(arena)
	_draw_presentation_errors(arena)


func _draw_original_background(texture: Texture2D, arena: Rect2) -> void:
	if texture.get_width() != 1024 or texture.get_height() != 1024:
		_record_error("retail background source must be exactly 1024x1024")
		return
	var source := Rect2(0.0, 0.0, 1024.0, 1024.0)
	var render_offset := interpolated_background_draw_offset(interpolation_alpha())
	for destination in background_destination_quads(render_offset):
		_draw_logical_region(texture, arena, destination, source)


func _update_background_scroll(snapshot: Dictionary) -> void:
	var tick := int(snapshot.get("tick", 0))
	var warp_value: Variant = snapshot.get("warp", {})
	var warp: Dictionary = warp_value as Dictionary if warp_value is Dictionary else {}
	if (
		warp.has("background_draw_offset")
		and warp.has("background_post_draw_offset")
	):
		var next_draw_offset := float(warp.background_draw_offset)
		if not _background_has_authoritative_offset or tick < _background_last_tick:
			_background_previous_draw_offset = next_draw_offset
		elif tick > _background_last_tick:
			_background_previous_draw_offset = _background_draw_offset
		_background_draw_offset = next_draw_offset
		_background_scroll_offset = float(warp.background_post_draw_offset)
		_background_last_tick = tick
		_background_has_authoritative_offset = true
		return
	if _background_last_tick < 0:
		_background_last_tick = tick
		return
	if tick < _background_last_tick:
		_background_scroll_offset = 0.0
		_background_draw_offset = 0.0
		_background_previous_draw_offset = 0.0
		_background_last_tick = tick
		return
	var update_count := tick - _background_last_tick
	_background_last_tick = tick
	if update_count <= 0:
		return
	for _update in range(update_count):
		# Retail draws the two quads before advancing and wrapping the offset.
		_background_draw_offset = _background_scroll_offset
		_background_scroll_offset = advance_background_scroll(
			_background_scroll_offset,
			float(warp.get("scale", 0.0)),
			str(snapshot.get("phase", "")),
			1
		)


func _background_texture_key(level_id: int) -> String:
	var backgrounds: Dictionary = _assets.section("backgrounds")
	var levels_value: Variant = backgrounds.get("levels", {})
	if levels_value is Dictionary:
		var level_value: Variant = (levels_value as Dictionary).get(str(level_id), {})
		if level_value is Dictionary:
			var key := str((level_value as Dictionary).get("texture", ""))
			if not key.is_empty():
				return key
	return ""


func _draw_memory_station(arena: Rect2, bonus_mode: Dictionary) -> void:
	var texture := _texture("memoryblocks")
	if texture != null:
		for tile_value in bonus_mode.get("tiles", []):
			if not tile_value is Dictionary:
				continue
			var tile: Dictionary = tile_value
			if not bool(tile.get("active", false)):
				continue
			var source := _rect_from_value(tile.get("source_rect", {}))
			if source.size.x <= 0.0 or source.size.y <= 0.0:
				continue
			_draw_logical_region(
				texture,
				arena,
				Rect2(
					float(tile.get("x", 0)),
					float(tile.get("y", 0)),
					float(tile.get("tile_size", bonus_mode.get("tile_size", 64))),
					float(tile.get("tile_size", bonus_mode.get("tile_size", 64)))
				),
				source
			)
		var cursor_value: Variant = bonus_mode.get("cursor_highlight", {})
		if cursor_value is Dictionary:
			var cursor: Dictionary = cursor_value
			var cursor_source := _rect_from_value(cursor.get("source_rect", {}))
			var cursor_destination := _rect_from_value(cursor.get("destination_rect", {}))
			if cursor_source.size.x > 0.0 and cursor_destination.size.x > 0.0:
				_draw_logical_region(
					texture,
					arena,
					cursor_destination,
					cursor_source
				)
	_draw_memory_station_presentation(arena, bonus_mode)


func _draw_meteor_storm(
	arena: Rect2,
	bonus_mode: Dictionary,
	alpha: float
) -> void:
	var surface_offset_x := int(bonus_mode.get("surface_offset_x", 0))
	var surface_offset_y := int(bonus_mode.get("surface_offset_y", 0))
	var surface_offset := Vector2(surface_offset_x, surface_offset_y)
	for slot_value in bonus_mode.get("slots", []):
		if not slot_value is Dictionary:
			continue
		var slot: Dictionary = slot_value
		if not bool(slot.get("active", false)):
			continue
		var source := _rect_from_value(slot.get("source_rect", []))
		if source.size.x <= 0.0 or source.size.y <= 0.0:
			continue
		var texture := _texture(str(slot.get("texture_id", "")))
		if texture == null:
			continue
		var slot_position := _interpolated_position(
			meteor_slot_interpolation_key(slot),
			slot,
			alpha
		) + surface_offset
		_draw_logical_region(
			texture,
			arena,
			Rect2(slot_position, source.size),
			source
		)
	var ship_value: Variant = bonus_mode.get("ship", {})
	if ship_value is Dictionary:
		var ship: Dictionary = ship_value
		var ship_texture := _texture(str(ship.get("fighter_id", "fighter1")))
		var ship_source := meteor_ship_render_source_rect(ship)
		if ship_texture != null and ship_source.size.x > 0.0:
			var ship_position := _interpolated_position(
				meteor_ship_interpolation_key(bonus_mode),
				ship,
				alpha
			) + surface_offset
			_draw_logical_region(
				ship_texture,
				arena,
				meteor_ship_render_destination(ship, ship_position),
				ship_source
			)
	var meter_value: Variant = bonus_mode.get("meter", {})
	if meter_value is Dictionary:
		var meter: Dictionary = meter_value
		var meter_texture := _texture(str(meter.get("texture_id", "meteormeter2")))
		if meter_texture != null:
			var column_source := _rect_from_value(meter.get("column_source_rect", []))
			var column_destination := _rect_from_value(meter.get("column_destination", []))
			var distance_source := _rect_from_value(meter.get("distance_source_rect", []))
			var distance_destination := _rect_from_value(
				meter.get("distance_destination", [])
			)
			if column_source.size.x > 0.0 and column_destination.size.x > 0.0:
				_draw_logical_region(
					meter_texture,
					arena,
					column_destination,
					column_source
				)
			if distance_source.size.x > 0.0 and distance_destination.size.x > 0.0:
				_draw_logical_region(
					meter_texture,
					arena,
					distance_destination,
					distance_source
				)
	_draw_meteor_storm_result(arena, bonus_mode)


func _draw_gem_drop(
	arena: Rect2,
	bonus_mode: Dictionary,
	alpha: float
) -> void:
	var gem_texture := _texture("diamantbig")
	if gem_texture != null:
		for slot_value in bonus_mode.get("slots", []):
			if not slot_value is Dictionary:
				continue
			var slot := slot_value as Dictionary
			if not bool(slot.get("active", false)):
				continue
			var source := _rect_from_value(slot.get("source_rect", []))
			if source.size.x <= 0.0 or source.size.y <= 0.0:
				continue
			var position := _interpolated_position(
				gem_drop_slot_interpolation_key(bonus_mode, slot),
				slot,
				alpha
			)
			_draw_logical_region(
				gem_texture,
				arena,
				Rect2(position, source.size),
				source
			)

	for player_value in bonus_mode.get("players", []):
		if not player_value is Dictionary:
			continue
		var player := player_value as Dictionary
		if not bool(player.get("active", false)) or not bool(player.get("alive", false)):
			continue
		var fighter_key := str(
			player.get("fighter_id", "fighter%d" % (int(player.get("seat_id", 0)) + 1))
		)
		var fighter_texture := _texture(fighter_key)
		if fighter_texture == null:
			continue
		var render_player := player.duplicate()
		render_player["sprite_frame"] = int(player.get("mask_frame", 5))
		_draw_player_fighter(
			arena,
			render_player,
			_interpolated_position(
				gem_drop_player_interpolation_key(bonus_mode, player),
				player,
				alpha
			),
			fighter_texture,
			Color.WHITE,
			false
		)

	var presentation := gem_drop_presentation_state(bonus_mode)
	_draw_logical_text(
		arena,
		str(presentation.get("title", "G E M   D R O P")),
		Vector2(0.0, 44.0),
		22,
		Color("#8eefff"),
		LOGICAL_WIDTH,
		HORIZONTAL_ALIGNMENT_CENTER
	)
	if bool(presentation.get("show_get_ready", false)):
		_draw_logical_text(
			arena,
			"GET READY",
			Vector2(0.0, 306.0),
			28,
			Color.WHITE,
			LOGICAL_WIDTH,
			HORIZONTAL_ALIGNMENT_CENTER
		)


func _draw_level_eight_presentation(arena: Rect2) -> void:
	var state := level_eight_presentation_state(
		_current.get("level_eight_bonus", {})
	)
	if state.is_empty():
		return
	var players: Array = state.get("players", [])
	if str(state.get("kind", "")) == "hud":
		var panel := Rect2(176.0, 12.0, 448.0, 46.0 + players.size() * 24.0)
		_draw_presentation_panel(arena, panel, Color("#4ddcff"))
		_draw_logical_text(
			arena,
			str(state.get("title", "BONUS TARGETS")),
			panel.position + Vector2(0.0, 23.0),
			14,
			Color("#9defff"),
			panel.size.x,
			HORIZONTAL_ALIGNMENT_CENTER
		)
		for index in range(players.size()):
			var player: Dictionary = players[index]
			_draw_logical_text(
				arena,
				"P%d   HITS %d/%d   MISSES %d" % [
					int(player.get("seat_id", index)) + 1,
					int(player.get("hits", 0)),
					int(player.get("total_targets", 0)),
					int(player.get("misses", 0)),
				],
				panel.position + Vector2(18.0, 49.0 + index * 24.0),
				13,
				Color.WHITE,
				panel.size.x - 36.0,
				HORIZONTAL_ALIGNMENT_CENTER
			)
		return

	draw_rect(arena, Color(0.0, 0.015, 0.06, 0.66))
	var panel_height := 100.0 + players.size() * 62.0
	var result_panel := Rect2(84.0, (LOGICAL_HEIGHT - panel_height) * 0.5, 632.0, panel_height)
	_draw_presentation_panel(arena, result_panel, Color("#ffd95a"))
	_draw_logical_text(
		arena,
		str(state.get("title", "BONUS LEVEL RESULTS")),
		result_panel.position + Vector2(0.0, 38.0),
		17,
		Color("#ffe790"),
		result_panel.size.x,
		HORIZONTAL_ALIGNMENT_CENTER
	)
	for index in range(players.size()):
		var player: Dictionary = players[index]
		var row_y := 75.0 + index * 62.0
		_draw_logical_text(
			arena,
			"P%d   HITS %d/%d   MISSES %d" % [
				int(player.get("seat_id", index)) + 1,
				int(player.get("hits", 0)),
				int(player.get("total_targets", 0)),
				int(player.get("misses", 0)),
			],
			result_panel.position + Vector2(24.0, row_y),
			16,
			Color.WHITE,
			result_panel.size.x - 48.0,
			HORIZONTAL_ALIGNMENT_CENTER
		)
		var reward_text := "NEXT PERFECT BONUS %d" % int(
			player.get("next_perfect_reward", 0)
		)
		var reward_color := Color("#8bdcff")
		if bool(player.get("perfect_awarded", false)):
			reward_text = "PERFECT BONUS +%d" % int(player.get("perfect_reward", 0))
			reward_color = Color("#9dff8a")
		_draw_logical_text(
			arena,
			reward_text,
			result_panel.position + Vector2(24.0, row_y + 25.0),
			13,
			reward_color,
			result_panel.size.x - 48.0,
			HORIZONTAL_ALIGNMENT_CENTER
		)
	if int(state.get("reveal_countdown", 0)) > 0:
		_draw_logical_text(
			arena,
			"COUNTING HITS... %d" % int(state.get("reveal_countdown", 0)),
			result_panel.position + Vector2(0.0, result_panel.size.y - 18.0),
			11,
			Color("#c4ccdb"),
			result_panel.size.x,
			HORIZONTAL_ALIGNMENT_CENTER
		)


func _draw_memory_station_presentation(arena: Rect2, bonus_mode: Dictionary) -> void:
	var presentation_snapshot := bonus_mode.duplicate()
	presentation_snapshot["now_ms"] = _current_simulation_milliseconds()
	var state := memory_station_presentation_state(presentation_snapshot)
	if state.is_empty():
		return
	var kind := str(state.get("kind", ""))
	draw_rect(arena, Color(0.0, 0.01, 0.04, 0.7))
	if kind in ["gem_drop", "super_gem_drop"]:
		var gem_panel := Rect2(210.0, 148.0, 380.0, 304.0)
		var accent := Color("#c67dff") if kind == "super_gem_drop" else Color("#52efff")
		_draw_presentation_panel(arena, gem_panel, accent)
		_draw_logical_text(
			arena,
			str(state.get("title", "GEM DROP")),
			gem_panel.position + Vector2(0.0, 54.0),
			25,
			accent,
			gem_panel.size.x,
			HORIZONTAL_ALIGNMENT_CENTER
		)
		var gem_texture := _texture("diamantbig")
		if gem_texture != null:
			_draw_logical_region(
				gem_texture,
				arena,
				Rect2(gem_panel.position + Vector2(110.0, 92.0), Vector2(160.0, 102.0)),
				Rect2(0.0, 0.0, 80.0, 51.0)
			)
		_draw_logical_text(
			arena,
			"MEMORY STATION PAUSED",
			gem_panel.position + Vector2(0.0, 235.0),
			13,
			Color.WHITE,
			gem_panel.size.x,
			HORIZONTAL_ALIGNMENT_CENTER
		)
		_draw_logical_text(
			arena,
			"CONTINUING IN %d" % _seconds_remaining(int(state.get("remaining_ms", 0))),
			gem_panel.position + Vector2(0.0, 267.0),
			12,
			Color("#c9d4e8"),
			gem_panel.size.x,
			HORIZONTAL_ALIGNMENT_CENTER
		)
		return

	var success := kind == "success"
	var accent := Color("#80ff8f") if success else Color("#ff6875")
	var result_panel := Rect2(190.0, 202.0, 420.0, 196.0)
	_draw_presentation_panel(arena, result_panel, accent)
	_draw_logical_text(
		arena,
		str(state.get("title", "MEMORY STATION COMPLETE")),
		result_panel.position + Vector2(0.0, 48.0),
		21,
		accent,
		result_panel.size.x,
		HORIZONTAL_ALIGNMENT_CENTER
	)
	_draw_logical_text(
		arena,
		"MATCHES %d   MISMATCHES %d   TRIES %d" % [
			int(state.get("matches", 0)),
			int(state.get("mismatches", 0)),
			int(state.get("tries", 0)),
		],
		result_panel.position + Vector2(20.0, 96.0),
		14,
		Color.WHITE,
		result_panel.size.x - 40.0,
		HORIZONTAL_ALIGNMENT_CENTER
	)
	var footer := "BOARD CLEARED" if success else "TIME EXPIRED"
	if int(state.get("score_award", 0)) > 0:
		footer += "   SCORE +%d" % int(state.get("score_award", 0))
	_draw_logical_text(
		arena,
		footer,
		result_panel.position + Vector2(20.0, 145.0),
		14,
		accent,
		result_panel.size.x - 40.0,
		HORIZONTAL_ALIGNMENT_CENTER
	)


func _draw_meteor_storm_result(arena: Rect2, bonus_mode: Dictionary) -> void:
	var presentation_snapshot := bonus_mode.duplicate()
	presentation_snapshot["now_ms"] = _current_simulation_milliseconds()
	var state := meteor_storm_result_presentation_state(presentation_snapshot)
	if state.is_empty():
		return
	var success := str(state.get("kind", "")) == "success"
	var accent := Color("#77f49a") if success else Color("#ff5c68")
	draw_rect(arena, Color(0.0, 0.01, 0.04, 0.72))
	var panel := Rect2(140.0, 148.0, 520.0, 304.0)
	_draw_presentation_panel(arena, panel, accent)
	_draw_logical_text(
		arena,
		str(state.get("title", "METEOR STORM COMPLETE")),
		panel.position + Vector2(0.0, 48.0),
		23,
		accent,
		panel.size.x,
		HORIZONTAL_ALIGNMENT_CENTER
	)
	if success:
		_draw_logical_text(
			arena,
			"TIER %s   SPEED %.1f%%" % [
				str(state.get("tier", "")),
				float(state.get("speed_percentage", 0.0)),
			],
			panel.position + Vector2(30.0, 94.0),
			15,
			Color.WHITE,
			panel.size.x - 60.0,
			HORIZONTAL_ALIGNMENT_CENTER
		)
		_draw_logical_text(
			arena,
			"SCORE REWARD +%d   CASH REWARD +%d" % [
				int(state.get("score_reward", 0)),
				int(state.get("cash_reward", 0)),
			],
			panel.position + Vector2(30.0, 134.0),
			13,
			Color("#ffe68a"),
			panel.size.x - 60.0,
			HORIZONTAL_ALIGNMENT_CENTER
		)
	else:
		_draw_logical_text(
			arena,
			"SHIP LOST TO METEOR SLOT %d" % int(state.get("collision_slot_id", -1)),
			panel.position + Vector2(30.0, 104.0),
			15,
			Color.WHITE,
			panel.size.x - 60.0,
			HORIZONTAL_ALIGNMENT_CENTER
		)
	_draw_logical_text(
		arena,
		"RUN SCORE %d   CASH %d   GEMS %d" % [
			int(state.get("score_delta_total", 0)),
			int(state.get("cash_delta_total", 0)),
			int(state.get("gem_count_delta_total", 0)),
		],
		panel.position + Vector2(30.0, 180.0),
		13,
		Color.WHITE,
		panel.size.x - 60.0,
		HORIZONTAL_ALIGNMENT_CENTER
	)
	_draw_logical_text(
		arena,
		"METEOR SCORE %d   STREAK %d" % [
			int(state.get("meteor_score_delta_total", 0)),
			int(state.get("meteor_streak", 0)),
		],
		panel.position + Vector2(30.0, 216.0),
		13,
		accent,
		panel.size.x - 60.0,
		HORIZONTAL_ALIGNMENT_CENTER
	)
	_draw_logical_text(
		arena,
		"CONTINUING IN %d" % _seconds_remaining(int(state.get("remaining_ms", 0))),
		panel.position + Vector2(0.0, 270.0),
		12,
		Color("#c9d4e8"),
		panel.size.x,
		HORIZONTAL_ALIGNMENT_CENTER
	)


func _draw_presentation_panel(arena: Rect2, logical_rect: Rect2, accent: Color) -> void:
	_draw_logical_rect(arena, logical_rect, Color(0.025, 0.045, 0.09, 0.96))
	_draw_logical_rect(arena, logical_rect, accent, false, 2.0)


func _draw_logical_rect(
	arena: Rect2,
	logical_rect: Rect2,
	color: Color,
	filled: bool = true,
	width: float = -1.0
) -> void:
	var scale := arena.size.x / LOGICAL_WIDTH
	draw_rect(
		Rect2(
			arena.position + logical_rect.position * scale,
			logical_rect.size * scale
		),
		color,
		filled,
		maxf(1.0, width * scale) if not filled else width
	)


func _draw_logical_text(
	arena: Rect2,
	text: String,
	logical_baseline: Vector2,
	font_size: int,
	color: Color,
	logical_width: float = -1.0,
	alignment = HORIZONTAL_ALIGNMENT_LEFT
) -> void:
	var scale := arena.size.x / LOGICAL_WIDTH
	draw_string(
		ThemeDB.fallback_font,
		arena.position + logical_baseline * scale,
		text,
		alignment,
		logical_width * scale if logical_width >= 0.0 else -1.0,
		maxi(1, int(round(float(font_size) * scale))),
		color
	)


func _seconds_remaining(milliseconds: int) -> int:
	return int(ceil(float(maxi(0, milliseconds)) / 1000.0))


func _current_simulation_milliseconds() -> int:
	return int(_current.get("tick", 0)) * 1000 / 60


func _draw_logical_region(
	texture: Texture2D,
	arena: Rect2,
	logical_destination: Rect2,
	source: Rect2
) -> void:
	var scale := arena.size.x / LOGICAL_WIDTH
	var destination := Rect2(
		arena.position + logical_destination.position * scale,
		logical_destination.size * scale
	)
	draw_texture_rect_region(texture, destination, source)


func _rect_from_value(value: Variant) -> Rect2:
	if value is Rect2:
		return value
	if value is Rect2i:
		return Rect2(value)
	if value is Array and (value as Array).size() == 4:
		var parts := value as Array
		return Rect2(
			float(parts[0]),
			float(parts[1]),
			float(parts[2]),
			float(parts[3])
		)
	if value is Dictionary:
		var fields := value as Dictionary
		return Rect2(
			float(fields.get("x", 0)),
			float(fields.get("y", 0)),
			float(fields.get("width", 0)),
			float(fields.get("height", 0))
		)
	return Rect2()


func _draw_side_rails(arena: Rect2) -> void:
	var difficulty := str(_current.get("difficulty", "normal"))
	var border_key: String = str({
		"easy": "border_easy",
		"hard": "border_hard",
		"ace": "border_ace",
	}.get(difficulty, "border"))
	var texture := _texture(border_key)
	if texture == null:
		return
	var scale := arena.size.x / LOGICAL_WIDTH
	var rail_width := PLAYFIELD_LEFT * scale
	draw_texture_rect_region(
		texture,
		Rect2(arena.position, Vector2(rail_width, arena.size.y)),
		Rect2(0.0, 0.0, 64.0, float(texture.get_height()))
	)
	draw_texture_rect_region(
		texture,
		Rect2(
			arena.position + Vector2(PLAYFIELD_RIGHT * scale, 0.0),
			Vector2(rail_width, arena.size.y)
		),
		Rect2(64.0, 0.0, 64.0, float(texture.get_height()))
	)


func _draw_players(arena: Rect2, alpha: float) -> void:
	var players: Array = _current.get("players", [])
	for entry: Variant in players:
		if not entry is Dictionary:
			continue
		var player := entry as Dictionary
		if not bool(player.get("active", true)) or not bool(player.get("alive", true)):
			continue
		var seat := int(player.get("seat_id", player.get("seat", 0)))
		var position := _interpolated_position("player:%d" % seat, player, alpha)
		var texture := _texture("fighter%d" % (seat + 1))
		if texture == null:
			continue
		var tint := Color.WHITE
		if int(player.get("invulnerable_ticks", 0)) > 0 and (int(_current.get("tick", 0)) / 3) % 2 == 0:
			tint.a = 0.32
		_draw_player_fighter(arena, player, position, texture, tint, false)
		if bool(player.get("mirror_active", false)):
			var mirror_position := Vector2(LOGICAL_WIDTH - position.x, position.y)
			_draw_player_fighter(arena, player, mirror_position, texture, tint, true)


func _draw_player_fighter(
	arena: Rect2,
	player: Dictionary,
	position: Vector2,
	texture: Texture2D,
	tint: Color,
	mirrored: bool
) -> void:
	var output := WBAspectFit.logical_to_output(position, arena)
	var scale := arena.size.x / LOGICAL_WIDTH
	_draw_fighter_thrust(output, scale, tint)
	var frame := int(player.get("sprite_frame", 5))
	if mirrored:
		frame = 10 - frame
	var source_rect := _sprite_frames.fighter_source_rect(frame)
	var sprite_size := Vector2(source_rect.size) * scale
	draw_texture_rect_region(
		texture,
		Rect2(output - sprite_size * 0.5, sprite_size),
		Rect2(source_rect),
		tint
	)


func _draw_fighter_thrust(output: Vector2, scale: float, tint: Color) -> void:
	var texture := _texture("figterfire2")
	if texture == null:
		return
	var frame := posmod(int(_current.get("tick", 0)), THRUST_FRAME_COUNT)
	var source := Rect2(
		frame * THRUST_FRAME_SIZE.x,
		0.0,
		THRUST_FRAME_SIZE.x,
		THRUST_FRAME_SIZE.y
	)
	var destination_size := Vector2(THRUST_FRAME_SIZE) * scale
	var center := output + THRUST_CENTER_OFFSET * scale
	draw_texture_rect_region(
		texture,
		Rect2(center - destination_size * 0.5, destination_size),
		source,
		tint
	)


func _draw_enemies(arena: Rect2, alpha: float) -> void:
	var enemies: Array = _current.get("enemies", [])
	var level_id := int(_current.get("level_id", 1))
	for entry: Variant in enemies:
		if not entry is Dictionary:
			continue
		var enemy := entry as Dictionary
		var enemy_id := int(enemy.get("id", 0))
		var texture_key := str(enemy.get(
			"sprite",
			_sprite_frames.enemy_sheet_for_level(level_id, _level_namespace())
		))
		var texture := _texture(texture_key)
		if texture == null:
			continue
		var position := _interpolated_position("enemy:%d" % enemy_id, enemy, alpha)
		if enemy.has("render_x_fp"):
			# Captured aliens deliberately teleport between their canonical and
			# reflected attachments in retail. The authoritative snapshot already
			# sampled that per-captive RNG choice, so do not interpolate across it.
			position.x = float(enemy.render_x_fp) / FP_ONE
		var output := WBAspectFit.logical_to_output(position, arena)
		var scale := arena.size.x / LOGICAL_WIDTH
		var width := float(enemy.get("width", 40)) * scale
		var height := float(enemy.get("height", 28)) * scale
		# The hurry-up ships carry their own sheet rectangle: retail writes the
		# source offsets straight onto the entity instead of resolving them from
		# an authored frame family.
		var source_rect := Rect2i()
		if enemy.has("source_rect"):
			source_rect = Rect2i(_rect_from_value(enemy.get("source_rect")))
		else:
			source_rect = _sprite_frames.enemy_source_rect(
				enemy,
				int(_current.get("tick", 0))
			)
		if source_rect.size.x <= 0 or source_rect.size.y <= 0:
			_record_error("enemy %d has no authored source frame" % enemy_id)
			continue
		draw_texture_rect_region(
			texture,
			Rect2(output - Vector2(width, height) * 0.5, Vector2(width, height)),
			Rect2(source_rect)
		)


## The shared 100-slot hazard pool. Each object carries its own sheet and
## source rectangle, so the renderer never has to know the kind.
func _draw_effect_objects(arena: Rect2, alpha: float) -> void:
	for entry: Variant in _current.get("effect_objects", []):
		if not entry is Dictionary:
			continue
		var effect := entry as Dictionary
		var texture := _texture(str(effect.get("sprite", "")))
		if texture == null:
			continue
		var source_rect := Rect2i(_rect_from_value(effect.get("source_rect", [])))
		if source_rect.size.x <= 0 or source_rect.size.y <= 0:
			continue
		var position := _interpolated_position(
			"effect:%d" % int(effect.get("slot", 0)),
			effect,
			alpha
		)
		var output := WBAspectFit.logical_to_output(position, arena)
		var scale := arena.size.x / LOGICAL_WIDTH
		var size := Vector2(
			float(effect.get("width", source_rect.size.x)) * scale,
			float(effect.get("height", source_rect.size.y)) * scale
		)
		draw_texture_rect_region(
			texture,
			Rect2(output - size * 0.5, size),
			Rect2(source_rect)
		)


func _draw_boss(arena: Rect2, alpha: float) -> void:
	var boss_value: Variant = _current.get("boss", {})
	if not boss_value is Dictionary:
		_record_error("snapshot boss must be an object")
		return
	for command in boss_render_commands(boss_value as Dictionary, alpha):
		var sheet := str(command.sheet)
		var texture := _texture(sheet)
		if texture == null:
			continue
		if (
			texture.get_width() != BOSS_SHEET_SIZE.x
			or texture.get_height() != BOSS_SHEET_SIZE.y
		):
			_record_error(
				"boss sheet %s must be exactly 576x96" % sheet
			)
			continue
		_draw_logical_region(
			texture,
			arena,
			command.logical_destination,
			command.source_rect
		)


func _draw_projectiles(arena: Rect2, alpha: float) -> void:
	for entry: Variant in _current.get("projectiles", []):
		if not entry is Dictionary:
			continue
		var projectile := entry as Dictionary
		var projectile_id := int(projectile.get("id", 0))
		var position := _interpolated_position("projectile:%d" % projectile_id, projectile, alpha)
		var output := WBAspectFit.logical_to_output(position, arena)
		var scale := arena.size.x / LOGICAL_WIDTH
		var owner_kind := str(projectile.get("owner_kind", "player"))
		var texture: Texture2D
		var source_rect := Rect2i()
		var destination_size := Vector2(
			maxf(2.0, float(projectile.get("width", 4)) * scale),
			maxf(4.0, float(projectile.get("height", 10)) * scale)
		)
		if owner_kind == "player":
			var player_sheet := (
				"rocket"
				if str(projectile.get("projectile_kind", "")) == "rocket_missile"
				else "weapons_big"
			)
			texture = _texture(player_sheet)
			source_rect = projectile_snapshot_source_rect(projectile)
			if player_sheet == "rocket":
				destination_size = Vector2(source_rect.size) * scale
		else:
			texture = _texture(enemy_projectile_texture_key(projectile))
			source_rect = projectile_snapshot_source_rect(projectile)
			destination_size = Vector2(source_rect.size) * scale
		if texture == null:
			continue
		if source_rect.size.x <= 0 or source_rect.size.y <= 0:
			_record_error("projectile %d has no authored source frame" % projectile_id)
			continue
		draw_texture_rect_region(
			texture,
			Rect2(output - destination_size * 0.5, destination_size),
			Rect2(source_rect)
		)


func _draw_pickups(arena: Rect2, alpha: float) -> void:
	var scale := arena.size.x / LOGICAL_WIDTH
	for entry: Variant in _current.get("pickups", []):
		if not entry is Dictionary:
			continue
		var pickup := entry as Dictionary
		var pickup_id := int(pickup.get("id", 0))
		var texture := _texture(str(pickup.get("texture_key", "bonuses")))
		if texture == null:
			continue
		var source_rect := Rect2i()
		if pickup.has("source_y"):
			source_rect = Rect2i(
				posmod(int(pickup.get("animation_frame", 0)), 10) * 20,
				int(pickup.source_y),
				int(pickup.get("width", 20)),
				int(pickup.get("height", 20))
			)
		else:
			source_rect = pickup_source_rect(
				str(pickup.get("kind", "")),
				int(pickup.get("animation_frame", 0)),
				int(pickup.get("variant", 0))
			)
		if source_rect.size.x <= 0 or source_rect.size.y <= 0:
			_record_error("pickup %d has no original bonuses frame" % pickup_id)
			continue
		var position := _interpolated_position("pickup:%d" % pickup_id, pickup, alpha)
		var output := WBAspectFit.logical_to_output(position, arena)
		var destination_size := Vector2(source_rect.size) * scale
		draw_texture_rect_region(
			texture,
			Rect2(output - destination_size * 0.5, destination_size),
			Rect2(source_rect)
		)


func _draw_presentation_errors(arena: Rect2) -> void:
	var errors := presentation_errors()
	if errors.is_empty():
		return
	var scale := arena.size.x / LOGICAL_WIDTH
	var panel := Rect2(
		arena.position + Vector2(96.0, 76.0) * scale,
		Vector2(608.0, 112.0) * scale
	)
	draw_rect(panel, Color(0.12, 0.015, 0.02, 0.94))
	draw_rect(panel, Color("#ff5964"), false, maxf(1.0, scale * 2.0))
	var font := ThemeDB.fallback_font
	draw_string(
		font,
		panel.position + Vector2(18.0, 30.0) * scale,
		"PRESENTATION ASSET ERROR",
		HORIZONTAL_ALIGNMENT_LEFT,
		-1.0,
		int(18.0 * scale),
		Color("#ff9aa1")
	)
	draw_string(
		font,
		panel.position + Vector2(18.0, 63.0) * scale,
		str(errors[0]),
		HORIZONTAL_ALIGNMENT_LEFT,
		panel.size.x - 36.0 * scale,
		int(13.0 * scale),
		Color.WHITE
	)


func _interpolated_position(key: String, entity: Dictionary, alpha: float) -> Vector2:
	var current_position := _position_from(entity)
	if not _entity_previous.has(key):
		return current_position
	var previous: Dictionary = _entity_previous[key]
	return _position_from(previous).lerp(current_position, alpha)


func _position_from(entity: Dictionary) -> Vector2:
	if entity.has("x_fp") and entity.has("y_fp"):
		return Vector2(float(entity["x_fp"]) / FP_ONE, float(entity["y_fp"]) / FP_ONE)
	var position: Variant = entity.get("position", Vector2.ZERO)
	if position is Vector2:
		return position
	if position is Array and position.size() >= 2:
		return Vector2(float(position[0]), float(position[1]))
	return Vector2.ZERO


func _index_entities(snapshot: Dictionary) -> Dictionary:
	var indexed: Dictionary = {}
	for entry: Variant in snapshot.get("players", []):
		if entry is Dictionary:
			var player := entry as Dictionary
			indexed["player:%d" % int(player.get("seat_id", player.get("seat", 0)))] = player
	for entry: Variant in snapshot.get("enemies", []):
		if entry is Dictionary:
			var enemy := entry as Dictionary
			indexed["enemy:%d" % int(enemy.get("id", 0))] = enemy
	for entry: Variant in snapshot.get("projectiles", []):
		if entry is Dictionary:
			var projectile := entry as Dictionary
			indexed["projectile:%d" % int(projectile.get("id", 0))] = projectile
	for entry: Variant in snapshot.get("pickups", []):
		if entry is Dictionary:
			var pickup := entry as Dictionary
			indexed["pickup:%d" % int(pickup.get("id", 0))] = pickup
	var boss_value: Variant = snapshot.get("boss", {})
	if boss_value is Dictionary and bool((boss_value as Dictionary).get("active", false)):
		var boss_parts_value: Variant = (boss_value as Dictionary).get("parts", [])
		if not boss_parts_value is Array:
			boss_parts_value = []
		for part_value: Variant in boss_parts_value as Array:
			if not part_value is Dictionary:
				continue
			var part := part_value as Dictionary
			if not part.has("part_id") or str(part.get("part_id", "")).is_empty():
				continue
			var position_entity := _boss_part_position_entity(part)
			if position_entity.is_empty():
				continue
			indexed[boss_part_interpolation_key(part)] = position_entity
	var bonus_value: Variant = snapshot.get("bonus_mode", {})
	if bonus_value is Dictionary:
		var bonus_mode := bonus_value as Dictionary
		var bonus_kind := str(bonus_mode.get("kind", ""))
		if bonus_kind == "meteor_storm":
			var ship_value: Variant = bonus_mode.get("ship", {})
			if ship_value is Dictionary and not (ship_value as Dictionary).is_empty():
				indexed[meteor_ship_interpolation_key(bonus_mode)] = ship_value
			for slot_value in bonus_mode.get("slots", []):
				if not slot_value is Dictionary:
					continue
				var slot := slot_value as Dictionary
				if bool(slot.get("active", false)):
					indexed[meteor_slot_interpolation_key(slot)] = slot
		elif bonus_kind == "gem_drop":
			for player_value in bonus_mode.get("players", []):
				if not player_value is Dictionary:
					continue
				var player := player_value as Dictionary
				if bool(player.get("active", false)) and bool(player.get("alive", false)):
					indexed[gem_drop_player_interpolation_key(bonus_mode, player)] = player
			for slot_value in bonus_mode.get("slots", []):
				if not slot_value is Dictionary:
					continue
				var slot := slot_value as Dictionary
				if bool(slot.get("active", false)):
					indexed[gem_drop_slot_interpolation_key(bonus_mode, slot)] = slot
	return indexed


func _load_required_assets() -> void:
	for key in _renderer_asset_keys():
		var texture := _assets.texture(key)
		if texture == null:
			_record_error("missing required presentation asset: %s" % key)
		else:
			_textures[key] = texture


func _texture(key: String) -> Texture2D:
	var texture: Texture2D = _textures.get(key)
	if texture == null:
		_record_error("missing required presentation asset: %s" % key)
	return texture


func _record_error(message: String) -> void:
	if _error_set.has(message):
		return
	_error_set[message] = true
	_presentation_errors.append(message)
	queue_redraw()

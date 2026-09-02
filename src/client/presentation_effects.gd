class_name WBPresentationEffects
extends Control

const FP_ONE := 65536.0
const POOL_SIZE := 96
const SEEN_EVENT_LIMIT := 4096
const EXPLOSION_COLUMNS := 5
const EXPLOSION_FRAME_SIZE := Vector2i(32, 32)
const EXPLOSION_FRAME_COUNT := 13

var _assets: WBAssetLibrary
var _textures: Dictionary = {}
var _errors: Array[String] = []
var _slots: Array[Dictionary] = []
var _active_slots: Array[int] = []
var _free_slots: Array[int] = []
var _seen_events: Dictionary = {}
var _seen_order: Array[int] = []
var _snapshot_tick := 0
var _render_tick := 0.0
var _effects_mode := "enhanced"
var _glow_layer := Control.new()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_initialize_pool()
	_glow_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_glow_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var additive := CanvasItemMaterial.new()
	additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow_layer.material = additive
	_glow_layer.draw.connect(_draw_enhancement)
	add_child(_glow_layer)
	_load_textures()


func configure(assets: WBAssetLibrary, effects_mode: String = "enhanced") -> void:
	_assets = assets
	set_effects_mode(effects_mode)
	reset()
	if is_inside_tree():
		_load_textures()


func set_effects_mode(value: String) -> void:
	_effects_mode = "original" if value.to_lower() == "original" else "enhanced"
	_glow_layer.visible = _effects_mode == "enhanced"
	queue_redraw()
	_glow_layer.queue_redraw()


func effects_mode() -> String:
	return _effects_mode


func set_snapshot(snapshot: Dictionary) -> void:
	var next_tick := int(snapshot.get("tick", _snapshot_tick))
	if next_tick < _snapshot_tick:
		reset()
	_snapshot_tick = next_tick
	_render_tick = float(next_tick)
	var requested_mode := str(snapshot.get("effects_mode", ""))
	var presentation: Variant = snapshot.get("presentation", {})
	if requested_mode.is_empty() and presentation is Dictionary:
		requested_mode = str((presentation as Dictionary).get("effects_mode", ""))
	if not requested_mode.is_empty():
		set_effects_mode(requested_mode)
	for event_value: Variant in snapshot.get("events", []):
		if event_value is Dictionary:
			_ingest_event(event_value as Dictionary)
	_prune_expired()
	queue_redraw()
	_glow_layer.queue_redraw()


func set_render_tick(value: float) -> void:
	_render_tick = maxf(value, float(_snapshot_tick))
	_prune_expired()
	queue_redraw()
	_glow_layer.queue_redraw()


func reset() -> void:
	_seen_events.clear()
	_seen_order.clear()
	_active_slots.clear()
	_free_slots.clear()
	if _slots.size() != POOL_SIZE:
		_initialize_pool()
	else:
		for index in range(POOL_SIZE - 1, -1, -1):
			_slots[index].clear()
			_free_slots.append(index)
	_snapshot_tick = 0
	_render_tick = 0.0
	queue_redraw()
	_glow_layer.queue_redraw()


func required_asset_keys() -> Array[String]:
	return ["expl_small", "flare1", "flare2", "flare4"]


func presentation_errors() -> Array[String]:
	return _errors.duplicate()


func active_effect_count() -> int:
	return _active_slots.size()


func explosion_frame_count() -> int:
	return EXPLOSION_FRAME_COUNT


func has_seen_event(event_id: int) -> bool:
	return _seen_events.has(event_id)


func active_event_ids() -> Array[int]:
	var result: Array[int] = []
	for slot_index in _active_slots:
		result.append(int(_slots[slot_index].get("event_id", -1)))
	return result


func active_effect_kinds() -> Array[String]:
	var result: Array[String] = []
	for slot_index in _active_slots:
		result.append(str(_slots[slot_index].get("kind", "")))
	return result


func active_effect_frame_indices() -> Array[int]:
	var result: Array[int] = []
	for slot_index in _active_slots:
		var effect := _slots[slot_index]
		if str(effect.get("kind", "")) in [
			"enemy_destroyed",
			"player_destroyed",
			"type_10_impact",
		]:
			var age := _render_tick - float(effect.get("start_tick", 0))
			result.append(_explosion_frame(effect, age))
	return result


func _initialize_pool() -> void:
	_slots.clear()
	_active_slots.clear()
	_free_slots.clear()
	_slots.resize(POOL_SIZE)
	for index in range(POOL_SIZE - 1, -1, -1):
		_slots[index] = {}
		_free_slots.append(index)


func _load_textures() -> void:
	_textures.clear()
	_errors.clear()
	if _assets == null:
		return
	for key in required_asset_keys():
		var texture := _assets.texture(key)
		if texture == null:
			_errors.append("missing required presentation asset: %s" % key)
		else:
			_textures[key] = texture


func _ingest_event(event: Dictionary) -> void:
	var event_id := int(event.get("event_id", -1))
	if event_id < 0 or _seen_events.has(event_id):
		return
	_seen_events[event_id] = true
	_seen_order.append(event_id)
	while _seen_order.size() > SEEN_EVENT_LIMIT:
		_seen_events.erase(_seen_order.pop_front())
	var kind := str(event.get("type", event.get("kind", "")))
	var effect_key := str(event.get("effect_key", "")).to_lower()
	var retail_type_10 := _retail_type_10_event(event, kind)
	var explicit_type_10 := (
		int(event.get("effect_type", -1)) == 10
		or effect_key == "expl_small"
		or not retail_type_10.is_empty()
	)
	if _effects_mode == "original" and not explicit_type_10:
		return
	if not kind in [
		"enemy_destroyed",
		"player_destroyed",
		"enemy_hit",
		"enemy_fired",
		"armour_hit",
		"pickup_collected",
		"weapon_fired",
		"rocket_expired",
		"boss_hit",
	]:
		if not explicit_type_10:
			return
	var x_fp_value: Variant = event.get("x_fp")
	var y_fp_value: Variant = event.get("y_fp")
	if not retail_type_10.is_empty():
		x_fp_value = retail_type_10.x_fp
		y_fp_value = retail_type_10.y_fp
		effect_key = "expl_small"
	if x_fp_value == null or y_fp_value == null:
		return
	var frame_hold_updates := 1
	var duration := EXPLOSION_FRAME_COUNT
	if explicit_type_10:
		kind = "type_10_impact"
	if not retail_type_10.is_empty():
		frame_hold_updates = int(retail_type_10.frame_period) + 1
		duration = EXPLOSION_FRAME_COUNT * frame_hold_updates
	match kind:
		"player_destroyed":
			duration = EXPLOSION_FRAME_COUNT
		"enemy_hit":
			duration = 10
		"enemy_fired", "weapon_fired":
			duration = 7
		"armour_hit", "pickup_collected":
			duration = 18
	var start_tick := int(event.get("tick", _snapshot_tick))
	if _snapshot_tick - start_tick >= duration:
		return
	var slot_index := _acquire_slot()
	_slots[slot_index] = {
		"event_id": event_id,
		"kind": kind,
		"start_tick": start_tick,
		"duration_ticks": duration,
		"frame_hold_updates": frame_hold_updates,
		"x_fp": int(x_fp_value),
		"y_fp": int(y_fp_value),
		"seat_id": int(event.get("seat_id", -1)),
		"weapon_id": int(event.get("weapon_id", -1)),
		"effect_key": effect_key,
		"red": int(event.get("red", 255)),
		"green": int(event.get("green", 255)),
		"angle": float(event.get("angle", 0.0)),
		"speed": float(event.get("speed", 0.0)),
	}
	_active_slots.append(slot_index)


func _retail_type_10_event(event: Dictionary, kind: String) -> Dictionary:
	if kind != "boss_retail_effect" or str(event.get("call", "")) != "FUN_005dfee0":
		return {}
	if typeof(event.get("allocated_count")) != TYPE_INT or int(event.allocated_count) <= 0:
		return {}
	var payload_value: Variant = event.get("payload", {})
	if not payload_value is Dictionary:
		return {}
	var payload := payload_value as Dictionary
	if (
		str(payload.get("kind", "")) != "boss_hit"
		or typeof(payload.get("x")) not in [TYPE_INT, TYPE_FLOAT]
			or typeof(payload.get("y")) not in [TYPE_INT, TYPE_FLOAT]
			or typeof(event.get("frame_period")) != TYPE_INT
			or int(event.frame_period) not in [0, 1]
		):
		return {}
	return {
		"x_fp": roundi(float(payload.x) * FP_ONE),
		"y_fp": roundi(float(payload.y) * FP_ONE),
		"frame_period": int(event.frame_period),
	}


func _acquire_slot() -> int:
	if not _free_slots.is_empty():
		return _free_slots.pop_back()
	var recycled: int = _active_slots.pop_front()
	_slots[recycled].clear()
	return recycled


func _prune_expired() -> void:
	var surviving: Array[int] = []
	for slot_index in _active_slots:
		var effect := _slots[slot_index]
		var age := _render_tick - float(effect.get("start_tick", 0))
		if age < float(effect.get("duration_ticks", 1)):
			surviving.append(slot_index)
		else:
			effect.clear()
			_free_slots.append(slot_index)
	_active_slots = surviving


func _draw() -> void:
	if _textures.is_empty():
		return
	var arena := WBAspectFit.calculate(size)
	if arena.size.x <= 0.0:
		return
	var output_scale := arena.size.x / 800.0
	for slot_index in _active_slots:
		var effect := _slots[slot_index]
		var kind := str(effect.get("kind", ""))
		var age := _render_tick - float(effect.get("start_tick", 0))
		var duration := float(effect.get("duration_ticks", 1))
		if age < 0.0 or age >= duration:
			continue
		var position := _effect_position(effect, arena)
		if kind in ["enemy_destroyed", "player_destroyed", "type_10_impact"]:
			_draw_explosion(effect, position, age, duration, output_scale)
		else:
			_draw_flare(effect, position, age, duration, output_scale, kind)


func _draw_explosion(
	effect: Dictionary,
	position: Vector2,
	age: float,
	duration: float,
	output_scale: float
) -> void:
	var texture: Texture2D = _textures.get("expl_small")
	if texture == null:
		return
	var frame := _explosion_frame(effect, age)
	var source := Rect2(
		(frame % EXPLOSION_COLUMNS) * EXPLOSION_FRAME_SIZE.x,
		(frame / EXPLOSION_COLUMNS) * EXPLOSION_FRAME_SIZE.y,
		EXPLOSION_FRAME_SIZE.x,
		EXPLOSION_FRAME_SIZE.y
	)
	var destination_size := Vector2(EXPLOSION_FRAME_SIZE) * output_scale
	draw_texture_rect_region(
		texture,
		Rect2(position - destination_size * 0.5, destination_size),
		source
	)


func _explosion_frame(effect: Dictionary, age: float) -> int:
	var frame_hold_updates := maxi(1, int(effect.get("frame_hold_updates", 1)))
	return mini(
		EXPLOSION_FRAME_COUNT - 1,
		maxi(0, int(floor(age / float(frame_hold_updates))))
	)


func _draw_flare(
	effect: Dictionary,
	position: Vector2,
	age: float,
	duration: float,
	output_scale: float,
	kind: String
) -> void:
	var texture_key := "flare1"
	if kind in ["armour_hit", "pickup_collected"]:
		texture_key = "flare2"
	elif kind == "rocket_expired":
		texture_key = "flare4"
	var texture: Texture2D = _textures.get(texture_key)
	if texture == null:
		return
	var progress := clampf(age / duration, 0.0, 1.0)
	var visual_size := (20.0 + 22.0 * progress) * output_scale
	var tint := Color(1.0, 1.0, 1.0, 1.0 - progress)
	if kind == "rocket_expired":
		var angle_radians := deg_to_rad(float(effect.get("angle", 0.0)))
		var travel := float(effect.get("speed", 0.0)) * age * output_scale
		position += Vector2(cos(angle_radians), sin(angle_radians)) * travel
		visual_size = 64.0 * output_scale
		tint = Color(
			clampf(float(effect.get("red", 255)) / 255.0, 0.0, 1.0),
			clampf(float(effect.get("green", 255)) / 255.0, 0.0, 1.0),
			1.0,
			1.0 - progress
		)
	draw_texture_rect(
		texture,
		Rect2(position - Vector2.ONE * visual_size * 0.5, Vector2.ONE * visual_size),
		false,
		tint
	)


func _draw_enhancement() -> void:
	if _effects_mode != "enhanced" or _textures.is_empty():
		return
	var arena := WBAspectFit.calculate(size)
	if arena.size.x <= 0.0:
		return
	var output_scale := arena.size.x / 800.0
	for slot_index in _active_slots:
		var effect := _slots[slot_index]
		var age := _render_tick - float(effect.get("start_tick", 0))
		var duration := float(effect.get("duration_ticks", 1))
		if age < 0.0 or age >= duration:
			continue
		var progress := clampf(age / duration, 0.0, 1.0)
		var effect_kind := str(effect.get("kind", ""))
		var texture_key := "flare2" if effect_kind == "armour_hit" else "flare1"
		if effect_kind == "rocket_expired":
			texture_key = "flare4"
		var texture: Texture2D = _textures.get(texture_key)
		if texture == null:
			continue
		var position := _effect_position(effect, arena)
		var visual_size := (38.0 + 28.0 * progress) * output_scale
		if str(effect.get("kind", "")) == "player_destroyed":
			visual_size *= 1.65
		var tint := Color(0.72, 0.88, 1.0, (1.0 - progress) * 0.34)
		_glow_layer.draw_texture_rect(
			texture,
			Rect2(position - Vector2.ONE * visual_size * 0.5, Vector2.ONE * visual_size),
			false,
			tint
		)


func _effect_position(effect: Dictionary, arena: Rect2) -> Vector2:
	return WBAspectFit.logical_to_output(
		Vector2(
			float(effect.get("x_fp", 0)) / FP_ONE,
			float(effect.get("y_fp", 0)) / FP_ONE
		),
		arena
	)

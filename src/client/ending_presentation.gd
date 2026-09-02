class_name WBEndingPresentation
extends Control

signal dismissed
signal audio_requested(request: Dictionary)

const REQUIRED_SLIDE_COUNT := 13
const LOGICAL_SIZE := Vector2(800.0, 600.0)
const DeterministicRngScript := preload("res://src/sim/deterministic_rng.gd")
const PRESENTATION_UPDATES_PER_SECOND := 60.0
const FIREWORK_UPDATE_BOUNDARY_EPSILON := 1.0e-9
# Winner-only routing is retail-backed. Cadence and particle composition are
# an intentional deterministic client presentation, not a retail fidelity claim.
const DEFAULT_FIREWORK_INTERVAL := 0.65
const DEFAULT_FIREWORK_DURATION := 1.1
const DEFAULT_FIREWORK_PARTICLES := 16

var last_error := ""

var _assets: WBAssetLibrary
var _contract: Dictionary = {}
var _terminal: Dictionary = {}
var _slides: Array[Dictionary] = []
var _mode_config: Dictionary = {}
var _active := false
var _paused := false
var _accelerated := false
var _dismissed := false
var _loop_enabled := true
var _text_loop_enabled := true
var _scroll_speed := 24.0
var _accelerated_multiplier := 4.0
var _slide_index := 0
var _slide_elapsed := 0.0
var _cycle_elapsed := 0.0
var _loop_count := 0
var _scroll_y := LOGICAL_SIZE.y
var _music_key := ""
var _instruction_duration := 8.0
var _instruction_elapsed := 0.0

var _fireworks_enabled := false
var _firework_interval := DEFAULT_FIREWORK_INTERVAL
var _firework_duration := DEFAULT_FIREWORK_DURATION
var _firework_particles := DEFAULT_FIREWORK_PARTICLES
var _firework_sfx := ""
var _firework_interval_updates := 39
var _firework_duration_updates := 66
var _firework_elapsed_update_total := 0.0
var _firework_elapsed_update_compensation := 0.0
var _firework_clock_updates := 0
var _firework_serial := 0
var _firework_bursts: Array[Dictionary] = []
var _firework_texture: Texture2D
var _firework_rng = DeterministicRngScript.new(1)
var _firework_seed_tick := 0

var _slide_view := TextureRect.new()
var _shade := ColorRect.new()
var _scroll_clip := Control.new()
var _scroll_label := Label.new()
var _instruction := Label.new()
var _pause_status := Label.new()
var _firework_layer := Control.new()
var _ui_created := false


func _ready() -> void:
	_ensure_ui()
	set_process(_active)


func configure(
	assets: WBAssetLibrary,
	ending_contract: Dictionary,
	terminal: Dictionary
) -> bool:
	_ensure_ui()
	reset()
	_assets = assets
	_contract = ending_contract.duplicate(true)
	_terminal = terminal.duplicate(true)
	if _contract.is_empty():
		return _fail("presentation manifest is missing the ending contract")
	var slide_values: Variant = _contract.get("slides", [])
	if not slide_values is Array or (slide_values as Array).size() != REQUIRED_SLIDE_COUNT:
		return _fail("ending contract must declare exactly thirteen ordered slides")
	for slide_value: Variant in slide_values:
		var slide: Dictionary = {}
		if slide_value is String:
			slide = {"texture": str(slide_value), "duration_seconds": 1.0}
		elif slide_value is Dictionary:
			slide = (slide_value as Dictionary).duplicate(true)
		else:
			return _fail("ending slide entries must be strings or dictionaries")
		var texture_key := str(slide.get(
			"texture",
			slide.get("asset_id", slide.get("key", ""))
		)).strip_edges()
		var duration_seconds := float(slide.get("duration_seconds", 0.0))
		if texture_key.is_empty() or duration_seconds <= 0.0:
			return _fail("ending slide metadata is incomplete")
		var texture := _assets.texture(texture_key) if _assets != null else null
		if texture == null:
			return _fail("ending slide texture is unavailable: %s" % texture_key)
		_slides.append({
			"texture_key": texture_key,
			"texture": texture,
			"duration_seconds": duration_seconds,
		})
	_scroll_speed = float(_contract.get("scroll_pixels_per_second", 0.0))
	_accelerated_multiplier = float(_contract.get("accelerated_multiplier", 0.0))
	if _scroll_speed <= 0.0 or _accelerated_multiplier <= 1.0:
		return _fail("ending scroll and acceleration constants are invalid")
	_loop_enabled = bool(_contract.get("loop", false))
	var evidence_value: Variant = _contract.get("evidence", {})
	var evidence: Dictionary = (
		evidence_value as Dictionary if evidence_value is Dictionary else {}
	)
	_text_loop_enabled = bool(evidence.get("text_loop", true))
	_instruction_duration = maxf(
		0.0,
		float(evidence.get("instruction_overlay_duration_ms", 8000)) / 1000.0
	)
	_music_key = str(_contract.get("music", "")).strip_edges().to_lower()
	if _music_key.is_empty():
		return _fail("ending contract is missing its music key")
	_mode_config = _ending_mode(
		_contract.get("modes", {}),
		int(_terminal.get("ending_mode_id", 0))
	)
	_configure_firework_rng()
	_configure_fireworks(_mode_config)
	var story_text := str(_contract.get("story_text", ""))
	var credits_text := str(_contract.get("credits_text", ""))
	if story_text.is_empty() or credits_text.is_empty():
		return _fail("ending contract is missing story or credits text")
	_scroll_clip.offset_top = 18.0
	# The executable-owned display bytes are authoritative. Mode routing is a
	# remake overlay policy and must never rewrite or duplicate this scroll.
	_scroll_label.text = story_text + credits_text
	_instruction.text = _control_text(_contract.get("controls", {}))
	_instruction.visible = not _instruction.text.is_empty()
	_pause_status.text = ""
	_apply_slide(0)
	_layout_text()
	last_error = ""
	return true


func start() -> void:
	if not last_error.is_empty() or _slides.size() != REQUIRED_SLIDE_COUNT:
		return
	_active = true
	_dismissed = false
	_paused = false
	_accelerated = false
	visible = true
	set_process(true)
	_restart_presentation()
	if _fireworks_enabled:
		_spawn_firework()


func reset() -> void:
	_active = false
	_paused = false
	_accelerated = false
	_dismissed = false
	_slides.clear()
	_mode_config.clear()
	_firework_bursts.clear()
	_firework_elapsed_update_total = 0.0
	_firework_elapsed_update_compensation = 0.0
	_firework_clock_updates = 0
	_firework_serial = 0
	_instruction_elapsed = 0.0
	_fireworks_enabled = false
	_firework_texture = null
	_slide_index = 0
	_slide_elapsed = 0.0
	_cycle_elapsed = 0.0
	_loop_count = 0
	_scroll_y = LOGICAL_SIZE.y
	_music_key = ""
	last_error = ""
	visible = false
	set_process(false)
	if _ui_created:
		_slide_view.texture = null
		_scroll_label.text = ""
		_instruction.text = ""
		_instruction.visible = false
		_pause_status.text = ""
		_firework_layer.queue_redraw()


func handle_input(event: InputEvent) -> bool:
	if not _active:
		return false
	if event is InputEventMouseButton:
		var mouse_button := event as InputEventMouseButton
		if mouse_button.is_echo():
			return false
		if mouse_button.button_index == MOUSE_BUTTON_LEFT:
			set_paused(mouse_button.pressed)
			return true
		if mouse_button.button_index == MOUSE_BUTTON_RIGHT:
			set_accelerated(mouse_button.pressed)
			return true
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if not key_event.pressed or key_event.echo:
			return false
		if key_event.keycode in [KEY_ESCAPE, KEY_SPACE]:
			dismiss()
			return true
	if (
		event.is_action_pressed("p1_fire")
		or event.is_action_pressed("p2_fire")
		or event.is_action_pressed("p1_cancel")
		or event.is_action_pressed("p2_cancel")
	):
		dismiss()
		return true
	return false


func _gui_input(event: InputEvent) -> void:
	if handle_input(event):
		accept_event()


func set_paused(value: bool) -> void:
	_paused = value
	_pause_status.text = "PAUSED" if _paused else ""


func set_accelerated(value: bool) -> void:
	_accelerated = value


func dismiss() -> void:
	if not _active or _dismissed:
		return
	_dismissed = true
	_active = false
	_accelerated = false
	set_process(false)
	dismissed.emit()


func advance_for_test(delta: float) -> void:
	_advance(delta)


func is_active() -> bool:
	return _active


func is_paused() -> bool:
	return _paused


func is_accelerated() -> bool:
	return _accelerated


func current_slide_index() -> int:
	return _slide_index


func loop_count() -> int:
	return _loop_count


func fireworks_enabled() -> bool:
	return _fireworks_enabled


func firework_signature() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for burst in _firework_bursts:
		result.append({
			"serial": int(burst.get("serial", 0)),
			"center": burst.get("center", Vector2.ZERO),
			"phase": float(burst.get("phase", 0.0)),
		})
	return result


func firework_update_count() -> int:
	return _firework_clock_updates


func firework_render_progresses() -> Array[float]:
	var result: Array[float] = []
	for burst in _firework_bursts:
		result.append(_firework_burst_progress(burst))
	return result


func music_key() -> String:
	return _music_key


func scroll_position() -> float:
	return _scroll_y


func _process(delta: float) -> void:
	_advance(delta)


func _advance(delta: float) -> void:
	if not _active or delta <= 0.0:
		return
	var text_delta := delta * (
		_accelerated_multiplier if _accelerated else 1.0
	)
	_slide_elapsed += delta
	_cycle_elapsed += delta
	_instruction_elapsed += delta
	if (
		_instruction_duration > 0.0
		and _instruction_elapsed >= _instruction_duration
	):
		_instruction.visible = false
	if not _paused:
		_scroll_y -= _scroll_speed * text_delta
		_update_scroll_position()
		if (
			_text_loop_enabled
			and _scroll_y + maxf(_scroll_label.size.y, 1.0) < 0.0
		):
			_restart_text(true)
	while _slide_elapsed >= float(_slides[_slide_index].get("duration_seconds", 1.0)):
		_slide_elapsed -= float(_slides[_slide_index].get("duration_seconds", 1.0))
		_slide_index += 1
		if _slide_index >= _slides.size():
			if _loop_enabled:
				_slide_index = 0
				_cycle_elapsed = 0.0
			else:
				_slide_index = _slides.size() - 1
				_slide_elapsed = 0.0
				break
		_apply_slide(_slide_index)
	_advance_fireworks(delta)


func _restart_presentation() -> void:
	_slide_index = 0
	_slide_elapsed = 0.0
	_cycle_elapsed = 0.0
	_loop_count = 0
	_instruction_elapsed = 0.0
	_instruction.visible = not _instruction.text.is_empty()
	_restart_text(false)
	_apply_slide(0)


func _restart_text(count_loop: bool) -> void:
	if count_loop:
		_loop_count += 1
	_scroll_y = maxf(
		LOGICAL_SIZE.y,
		_scroll_clip.size.y if _scroll_clip.size.y > 0.0 else LOGICAL_SIZE.y
	)
	_update_scroll_position()


func _apply_slide(index: int) -> void:
	if index < 0 or index >= _slides.size():
		return
	_slide_view.texture = _slides[index].get("texture") as Texture2D


func _layout_text() -> void:
	var width := maxf(320.0, (size.x if size.x > 0.0 else LOGICAL_SIZE.x) - 160.0)
	_scroll_label.position.x = 80.0
	_scroll_label.size.x = width
	_scroll_label.reset_size()
	_scroll_label.size.x = width
	_scroll_label.size.y = maxf(
		_scroll_label.get_combined_minimum_size().y,
		LOGICAL_SIZE.y
	)
	_update_scroll_position()


func _update_scroll_position() -> void:
	_scroll_label.position.y = _scroll_y


func _configure_fireworks(mode_config: Dictionary) -> void:
	var fireworks_value: Variant = mode_config.get("fireworks", false)
	var fireworks: Dictionary = {}
	if fireworks_value is Dictionary:
		fireworks = (fireworks_value as Dictionary).duplicate(true)
		_fireworks_enabled = bool(fireworks.get("enabled", true))
	else:
		_fireworks_enabled = bool(fireworks_value)
	_firework_interval = maxf(
		0.05,
		float(fireworks.get("interval_seconds", DEFAULT_FIREWORK_INTERVAL))
	)
	_firework_duration = maxf(
		0.1,
		float(fireworks.get("duration_seconds", DEFAULT_FIREWORK_DURATION))
	)
	_firework_interval_updates = maxi(
		1,
		int(fireworks.get(
			"interval_updates",
			roundi(_firework_interval * PRESENTATION_UPDATES_PER_SECOND)
		))
	)
	_firework_duration_updates = maxi(
		1,
		int(fireworks.get(
			"duration_updates",
			roundi(_firework_duration * PRESENTATION_UPDATES_PER_SECOND)
		))
	)
	_firework_particles = clampi(
		int(fireworks.get("particle_count", DEFAULT_FIREWORK_PARTICLES)),
		4,
		64
	)
	_firework_sfx = str(fireworks.get("sfx", "")).strip_edges().to_lower()
	if _fireworks_enabled and _assets != null:
		_firework_texture = _assets.texture(str(fireworks.get("texture", "flare1")))


func _configure_firework_rng() -> void:
	_firework_seed_tick = int(_terminal.get("presentation_tick", 0))
	var rng_value: Variant = _terminal.get("presentation_rng", {})
	if rng_value is Dictionary:
		var rng_snapshot := rng_value as Dictionary
		if ["x", "y", "z", "w", "c"].all(func(key: String) -> bool: return rng_snapshot.has(key)):
			_firework_rng.restore(rng_snapshot)
			return
	var fallback_seed := (
		_firework_seed_tick
		^ ((int(_terminal.get("winner_seat_id", -1)) + 2) * 0x45d9f3b)
		^ (int(_terminal.get("ending_mode_id", 0)) * 0x119de1f3)
	)
	_firework_rng.seed(fallback_seed)


func _advance_fireworks(delta: float) -> void:
	if not _fireworks_enabled:
		return
	# Kahan accumulation keeps the fixed 60-update presentation clock invariant
	# when one elapsed interval is partitioned by common high-refresh frame rates.
	var scaled_delta := maxf(delta, 0.0) * PRESENTATION_UPDATES_PER_SECOND
	var corrected_delta := scaled_delta - _firework_elapsed_update_compensation
	var next_total := _firework_elapsed_update_total + corrected_delta
	_firework_elapsed_update_compensation = (
		(next_total - _firework_elapsed_update_total) - corrected_delta
	)
	_firework_elapsed_update_total = next_total
	var target_value := _firework_elapsed_update_total
	var nearest_boundary: float = roundf(target_value)
	if absf(target_value - nearest_boundary) <= FIREWORK_UPDATE_BOUNDARY_EPSILON:
		target_value = nearest_boundary
	var target_updates := maxi(
		_firework_clock_updates,
		int(floor(target_value))
	)
	var elapsed_updates := target_updates - _firework_clock_updates
	for _update in range(elapsed_updates):
		_firework_clock_updates += 1
		if _firework_clock_updates % _firework_interval_updates == 0:
			_spawn_firework()
	var survivors: Array[Dictionary] = []
	for burst_value in _firework_bursts:
		var burst := burst_value.duplicate(true)
		if (
			_firework_clock_updates - int(burst.get("spawn_update", 0))
			< _firework_duration_updates
		):
			survivors.append(burst)
	_firework_bursts = survivors
	_firework_layer.queue_redraw()


func _spawn_firework() -> void:
	_firework_serial += 1
	var center := Vector2(
		_firework_rng.next_float32(120.0, 680.0),
		_firework_rng.next_float32(90.0, 340.0)
	)
	_firework_bursts.append({
		"serial": _firework_serial,
		"spawn_update": _firework_clock_updates,
		"center": center,
		"phase": _firework_rng.next_float32(0.0, TAU),
	})
	if not _firework_sfx.is_empty():
		audio_requested.emit({
			"category": "sfx",
			"key": _firework_sfx,
			"event_id": "ending_firework_%d_%d" % [
				_firework_seed_tick,
				_firework_serial,
			],
			"priority": 35,
			"max_voices": 8,
		})


func _draw_fireworks() -> void:
	if _firework_texture == null or _firework_bursts.is_empty():
		return
	var arena := WBAspectFit.calculate(_firework_layer.size)
	var scale := arena.size.x / LOGICAL_SIZE.x if arena.size.x > 0.0 else 1.0
	for burst in _firework_bursts:
		var progress := _firework_burst_progress(burst)
		var center := WBAspectFit.logical_to_output(
			burst.get("center", LOGICAL_SIZE * 0.5),
			arena
		)
		var phase := float(burst.get("phase", 0.0))
		for particle in range(_firework_particles):
			var angle := phase + TAU * float(particle) / float(_firework_particles)
			var radius := (22.0 + 92.0 * progress) * scale
			var position := center + Vector2(cos(angle), sin(angle)) * radius
			var visual_size := maxf(2.0, 10.0 * (1.0 - progress)) * scale
			var hue := fmod(float(particle) / float(_firework_particles) + phase / TAU, 1.0)
			var tint := Color.from_hsv(hue, 0.55, 1.0, 1.0 - progress)
			_firework_layer.draw_texture_rect(
				_firework_texture,
				Rect2(position - Vector2.ONE * visual_size * 0.5, Vector2.ONE * visual_size),
				false,
				tint
			)


func _firework_burst_progress(burst: Dictionary) -> float:
	# Spawn/lifetime decisions remain on the integer 60-update clock, while the
	# compensated fractional total supplies presentation-only high-refresh motion.
	var render_update := maxf(
		_firework_elapsed_update_total,
		float(_firework_clock_updates)
	)
	var age_updates := maxf(
		0.0,
		render_update - float(burst.get("spawn_update", 0))
	)
	return clampf(
		age_updates / float(_firework_duration_updates),
		0.0,
		1.0
	)


func _ensure_ui() -> void:
	if _ui_created:
		return
	_ui_created = true
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = true
	visible = false
	resized.connect(_layout_text)

	var background := ColorRect.new()
	background.color = Color.BLACK
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	_slide_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_slide_view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_slide_view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	_slide_view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_slide_view)

	_shade.color = Color(0.0, 0.0, 0.0, 0.42)
	_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_shade)

	_firework_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_firework_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_firework_layer.draw.connect(_draw_fireworks)
	add_child(_firework_layer)


	_scroll_clip.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scroll_clip.offset_top = 70.0
	_scroll_clip.offset_bottom = -62.0
	_scroll_clip.clip_contents = true
	_scroll_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_scroll_clip)

	_scroll_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_scroll_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_scroll_label.add_theme_font_size_override("font_size", 18)
	_scroll_label.add_theme_color_override("font_color", Color.WHITE)
	_scroll_label.add_theme_color_override("font_shadow_color", Color.BLACK)
	_scroll_label.add_theme_constant_override("shadow_offset_x", 1)
	_scroll_label.add_theme_constant_override("shadow_offset_y", 1)
	_scroll_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll_clip.add_child(_scroll_label)

	_instruction.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_instruction.position = Vector2(-360.0, -48.0)
	_instruction.size = Vector2(720.0, 30.0)
	_instruction.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_instruction.add_theme_font_size_override("font_size", 13)
	_instruction.add_theme_color_override("font_color", Color("#d6ecff"))
	_instruction.add_theme_color_override("font_shadow_color", Color.BLACK)
	_instruction.add_theme_constant_override("shadow_offset_x", 1)
	_instruction.add_theme_constant_override("shadow_offset_y", 1)
	_instruction.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_instruction)

	_pause_status.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_pause_status.position = Vector2(-160.0, 22.0)
	_pause_status.size = Vector2(132.0, 30.0)
	_pause_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_pause_status.add_theme_font_size_override("font_size", 16)
	_pause_status.add_theme_color_override("font_color", Color("#ffe58a"))
	_pause_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_pause_status)


static func _ending_mode(modes_value: Variant, ending_mode_id: int) -> Dictionary:
	if modes_value is Dictionary:
		var modes := modes_value as Dictionary
		var value: Variant = modes.get(str(ending_mode_id), modes.get(ending_mode_id, {}))
		if value is Dictionary:
			return (value as Dictionary).duplicate(true)
	if modes_value is Array:
		for value: Variant in modes_value:
			if value is Dictionary and int((value as Dictionary).get("id", -1)) == ending_mode_id:
				return (value as Dictionary).duplicate(true)
	return {}


static func _control_text(controls_value: Variant) -> String:
	if controls_value is Array:
		var parts: Array[String] = []
		for value: Variant in controls_value:
			var text := str(value).strip_edges()
			if not text.is_empty():
				parts.append(text)
		return "   •   ".join(parts)
	if controls_value is Dictionary:
		var controls := controls_value as Dictionary
		var parts: Array[String] = []
		for aliases in [
			["pause", "left_mouse"],
			["speed_up", "right_mouse", "accelerate"],
			["continue", "dismiss"],
		]:
			var text := ""
			for key in aliases:
				text = str(controls.get(key, "")).strip_edges()
				if not text.is_empty():
					break
			if not text.is_empty():
				parts.append(text)
		return "   •   ".join(parts)
	return str(controls_value)


func _fail(message: String) -> bool:
	last_error = message
	_active = false
	visible = false
	set_process(false)
	return false

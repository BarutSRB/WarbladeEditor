extends SceneTree
## Windowed 3D->2D sprite renderer for the Tripo pipeline.
##
## Invoked by tools/tripo_pipeline.py:
##   godot --path Remake --script res://tools/render/render_cli.gd -- --job=<job.json>
##
## NOT --headless: the headless driver cannot rasterize, so this runs with a
## tiny unfocused window while a SubViewport does the actual offscreen work.
## The job file is schema warblade.render-job.v1; frames land in
## <out_dir>/<shot_id>/frame_NN.png plus a render_report.json the pipeline
## checks. A job glb of "__builtin_probe__" renders built-in primitives so the
## whole pipeline can be exercised offline without a Tripo model.

const JOB_SCHEMA := "warblade.render-job.v1"
const TIMEOUT_MSEC := 180000

var _job: Dictionary = {}
var _report := {"ok": false, "shots": {}, "warnings": []}
var _start_msec := 0


func _initialize() -> void:
	_start_msec = Time.get_ticks_msec()
	_run.call_deferred()


func _run() -> void:
	var args := WBCliArgs.new()
	var job_path := args.value("job")
	if job_path.is_empty():
		_abort("render job path is missing (--job=<path>)")
		return
	var raw := FileAccess.get_file_as_string(job_path)
	var parsed: Variant = JSON.parse_string(raw)
	if not parsed is Dictionary:
		_abort("render job is not valid JSON: %s" % job_path)
		return
	_job = parsed as Dictionary
	if String(_job.get("schema", "")) != JOB_SCHEMA:
		_abort("render job schema is unsupported: %s" % String(_job.get("schema", "")))
		return
	_shrink_window()

	var render_size := int(_job.get("render_size", 512))
	var viewport := SubViewport.new()
	viewport.size = Vector2i(render_size, render_size)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = _msaa_mode(int(_job.get("msaa", 4)))
	root.add_child(viewport)

	var environment := WorldEnvironment.new()
	environment.environment = _build_environment(String(_job.get("light_rig", "key_fill_rim")))
	viewport.add_child(environment)
	for light in _build_lights(String(_job.get("light_rig", "key_fill_rim"))):
		viewport.add_child(light)

	var pivot := Node3D.new()
	viewport.add_child(pivot)
	var model := _load_model(String(_job.get("glb", "")))
	if model == null:
		_abort("model failed to load: %s" % String(_job.get("glb", "")))
		return
	var offset := Node3D.new()
	pivot.add_child(offset)
	offset.add_child(model)
	_sanitize_materials(model)
	# Base orientation: Tripo models arrive with arbitrary authored axes; the
	# concept's model_rotation_degrees turns them nose-up / back-to-camera
	# BEFORE the AABB is measured and shot poses spin the pivot above.
	var base_rotation: Array = _job.get("model", {}).get("model_rotation_degrees", [0.0, 0.0, 0.0])
	if base_rotation.size() == 3:
		offset.rotation_degrees = Vector3(
			float(base_rotation[0]), float(base_rotation[1]), float(base_rotation[2])
		)
	await process_frame
	var bounds := _merged_aabb(model)
	if bounds.size == Vector3.ZERO:
		_abort("model has no visible meshes")
		return
	if bool(_job.get("model", {}).get("recenter", true)):
		offset.position = -(bounds.position + bounds.size * 0.5)

	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	var margin := float(_job.get("camera", {}).get("framing_margin", 1.12))
	var extent := maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
	camera.size = extent * margin
	var pitch := deg_to_rad(float(_job.get("camera", {}).get("pitch_degrees", 75.0)))
	var direction := Vector3(0.0, sin(pitch), cos(pitch)).normalized()
	var up := Vector3(0.0, 0.0, -1.0) if absf(direction.dot(Vector3.UP)) > 0.99 else Vector3.UP
	# look_at() needs a node inside the tree; build the transform directly.
	camera.transform = Transform3D(Basis.looking_at(-direction, up), direction * extent * 3.0)
	camera.near = 0.01
	camera.far = extent * 10.0
	viewport.add_child(camera)

	_report["aabb"] = {
		"size": [bounds.size.x, bounds.size.y, bounds.size.z],
	}
	var out_dir := String(_job.get("out_dir", ""))
	var shots: Array = _job.get("shots", [])
	for shot_value in shots:
		var shot := shot_value as Dictionary
		var produced := await _render_shot(viewport, pivot, shot, out_dir)
		if produced < 0:
			return
		(_report["shots"] as Dictionary)[String(shot.get("id", ""))] = produced
	_report["ok"] = true
	_write_report(out_dir)
	print(JSON.stringify({"ok": true, "out_dir": out_dir}))
	quit(0)


func _render_shot(
	viewport: SubViewport, pivot: Node3D, shot: Dictionary, out_dir: String
) -> int:
	var shot_id := String(shot.get("id", "shot"))
	var mode := String(shot.get("mode", "static"))
	var frames := int(shot.get("frames", 1))
	if mode == "turntable16":
		frames = 16
	elif mode == "turntable32":
		frames = 32
	var shot_dir := out_dir.path_join(shot_id)
	DirAccess.make_dir_recursive_absolute(shot_dir)
	var model_config: Dictionary = _job.get("model", {})
	var yaw_offset := float(model_config.get("yaw_offset_degrees", 0.0))
	var clockwise := bool(model_config.get("clockwise", true))
	for index in range(frames):
		if Time.get_ticks_msec() - _start_msec > TIMEOUT_MSEC:
			_abort("render timed out in shot %s" % shot_id)
			return -1
		_pose_for_frame(pivot, mode, shot, index, frames, yaw_offset, clockwise)
		var image := await _capture(viewport)
		if image == null or image.get_used_rect().size == Vector2i.ZERO:
			# First capture after a pose change can race the driver; give it
			# one more frame before treating emptiness as fatal.
			image = await _capture(viewport)
		if image == null or image.get_used_rect().size == Vector2i.ZERO:
			(_report["warnings"] as Array).append("empty frame %d in shot %s" % [index, shot_id])
		var path := shot_dir.path_join("frame_%02d.png" % index)
		if image == null or image.save_png(path) != OK:
			_abort("frame save failed: %s" % path)
			return -1
	return frames


func _pose_for_frame(
	pivot: Node3D,
	mode: String,
	shot: Dictionary,
	index: int,
	frames: int,
	yaw_offset: float,
	clockwise: bool
) -> void:
	pivot.rotation = Vector3.ZERO
	pivot.scale = Vector3.ONE
	var direction := -1.0 if clockwise else 1.0
	match mode:
		"turntable16", "turntable32":
			pivot.rotation.y = deg_to_rad(yaw_offset + direction * (360.0 / float(frames)) * index)
		"pose_wobble":
			var phase := TAU * float(index) / float(maxi(1, frames))
			var wobble := deg_to_rad(float(shot.get("wobble_degrees", 6.0)))
			pivot.rotation.y = deg_to_rad(yaw_offset)
			pivot.rotation.x = sin(phase) * wobble
			pivot.rotation.z = cos(phase) * wobble * 0.6
			var pulse := float(shot.get("scale_pulse", 0.0))
			pivot.scale = Vector3.ONE * (1.0 + sin(phase) * pulse)
		"banking_sweep":
			var half := float(frames - 1) * 0.5
			var bank := deg_to_rad(float(shot.get("max_bank_degrees", 38.0)))
			pivot.rotation.y = deg_to_rad(yaw_offset)
			pivot.rotation.z = bank * ((float(index) - half) / half)
		_:
			pivot.rotation.y = deg_to_rad(yaw_offset)


func _capture(viewport: SubViewport) -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	var texture := viewport.get_texture()
	return texture.get_image() if texture != null else null


func _load_model(path: String) -> Node3D:
	if path == "__builtin_probe__":
		return _builtin_probe()
	if not FileAccess.file_exists(path):
		return null
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	if document.append_from_file(path, state) != OK:
		return null
	var scene := document.generate_scene(state)
	return scene as Node3D


## A colored primitive cluster standing in for a Tripo model so the whole
## pipeline can run offline: hull box, glowing core sphere, wing panels.
func _builtin_probe() -> Node3D:
	var probe := Node3D.new()
	var hull := MeshInstance3D.new()
	var hull_mesh := BoxMesh.new()
	hull_mesh.size = Vector3(1.2, 0.5, 1.6)
	hull.mesh = hull_mesh
	var hull_material := StandardMaterial3D.new()
	hull_material.albedo_color = Color("#c9702e")
	hull_material.roughness = 0.55
	hull.material_override = hull_material
	probe.add_child(hull)
	var core := MeshInstance3D.new()
	var core_mesh := SphereMesh.new()
	core_mesh.radius = 0.34
	core_mesh.height = 0.68
	core.mesh = core_mesh
	core.position = Vector3(0.0, 0.42, 0.0)
	var core_material := StandardMaterial3D.new()
	core_material.albedo_color = Color("#ffe9a8")
	core_material.emission_enabled = true
	core_material.emission = Color("#ffb347")
	core_material.emission_energy_multiplier = 2.0
	core.material_override = core_material
	probe.add_child(core)
	for side in [-1.0, 1.0]:
		var wing := MeshInstance3D.new()
		var wing_mesh := BoxMesh.new()
		wing_mesh.size = Vector3(0.9, 0.12, 0.9)
		wing.mesh = wing_mesh
		wing.position = Vector3(side * 0.95, -0.05, 0.1)
		wing.rotation.z = side * 0.18
		var wing_material := StandardMaterial3D.new()
		wing_material.albedo_color = Color("#8a4520")
		wing_material.roughness = 0.4
		wing.material_override = wing_material
		probe.add_child(wing)
	return probe


## Tripo PBR can arrive with mirror metallics or transmission that render
## black under gl_compatibility; clamp to values the driver shades well.
func _sanitize_materials(model: Node3D) -> void:
	for mesh_instance: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := mesh_instance.mesh
		if mesh == null:
			continue
		for surface in range(mesh.get_surface_count()):
			var material := mesh_instance.get_active_material(surface)
			if material is StandardMaterial3D:
				var standard := material as StandardMaterial3D
				standard.metallic = minf(standard.metallic, 0.6)
				standard.roughness = maxf(standard.roughness, 0.25)
				standard.refraction_enabled = false
				if standard.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS:
					standard.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA


func _merged_aabb(model: Node3D) -> AABB:
	var merged := AABB()
	var first := true
	for mesh_instance: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		var bounds := mesh_instance.global_transform * mesh_instance.get_aabb()
		if first:
			merged = bounds
			first = false
		else:
			merged = merged.merge(bounds)
	return merged if not first else AABB()


func _build_environment(rig: String) -> Environment:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_CLEAR_COLOR
	environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	match rig:
		"flat_toon":
			environment.ambient_light_color = Color("#9aa0c9")
			environment.ambient_light_energy = 0.6
		"dramatic_top":
			environment.ambient_light_color = Color("#2b3350")
			environment.ambient_light_energy = 0.15
		_:
			environment.ambient_light_color = Color("#39406b")
			environment.ambient_light_energy = 0.35
	return environment


func _build_lights(rig: String) -> Array[Node3D]:
	var lights: Array[Node3D] = []
	match rig:
		"flat_toon":
			lights.append(_directional(Color("#ffffff"), 1.1, Vector3(-0.2, -0.9, -0.3)))
		"dramatic_top":
			lights.append(_directional(Color("#fff4e0"), 2.0, Vector3(0.0, -1.0, -0.15)))
			lights.append(_directional(Color("#7d9cff"), 0.3, Vector3(0.6, -0.2, 0.7)))
		_:
			# key_fill_rim: warm key upper-left, cool fill right, teal rim from
			# behind-below -- the Solstice board's lighting statement.
			lights.append(_directional(Color("#fff0d9"), 1.3, Vector3(-0.55, -0.75, -0.35)))
			lights.append(_directional(Color("#cfe8ff"), 0.4, Vector3(0.7, -0.4, -0.1)))
			lights.append(_directional(Color("#6ff2ff"), 0.9, Vector3(0.35, 0.55, 0.75)))
	return lights


func _directional(color: Color, energy: float, direction: Vector3) -> DirectionalLight3D:
	var light := DirectionalLight3D.new()
	light.light_color = color
	light.light_energy = energy
	var target := direction.normalized()
	var up := Vector3.UP if absf(target.dot(Vector3.UP)) < 0.99 else Vector3.BACK
	# look_at() needs a node inside the tree; build the basis directly. A
	# DirectionalLight3D shines along its -Z axis.
	light.transform = Transform3D(Basis.looking_at(target, up), -target * 10.0)
	return light


func _shrink_window() -> void:
	if DisplayServer.get_name() == "headless":
		return
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_NO_FOCUS, true)
	DisplayServer.window_set_size(Vector2i(64, 64))
	DisplayServer.window_set_position(Vector2i(24, 48))
	DisplayServer.window_set_title("warblade sprite render")


func _msaa_mode(samples: int) -> int:
	match samples:
		8:
			return Viewport.MSAA_8X
		4:
			return Viewport.MSAA_4X
		2:
			return Viewport.MSAA_2X
	return Viewport.MSAA_DISABLED


func _write_report(out_dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(out_dir)
	var file := FileAccess.open(out_dir.path_join("render_report.json"), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(_report, "  "))
		file.close()


func _abort(message: String) -> void:
	_report["ok"] = false
	(_report["warnings"] as Array).append(message)
	var out_dir := String(_job.get("out_dir", ""))
	if not out_dir.is_empty():
		_write_report(out_dir)
	printerr(JSON.stringify({"ok": false, "error": message}))
	quit(2)

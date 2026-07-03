# Real first-person seated cockpit view, normal materials (no debug shader)
# -- to actually SEE what Alex is describing ("a big metal box blocking
# half the tank", "not everything seems interactive") instead of guessing
# from reading cockpit_builder.gd. Reuses asset_showcase.gd's real
# PlayerTank + CockpitBuilder construction, just points the camera from
# the real seat-anchor eye position looking forward, like a seated player.
# Run: godot --path . scenes/cockpit_view_check.tscn
extends Node3D

func _ready() -> void:
	var terrain := Terrain.new({
		"rolling": 1.0, "dunes": false, "pond": false, "coast": false,
		"flatten": [[Vector2(0, 0), 40.0, 0.0]],
		"village": {}, "city": {}, "castle": {}, "mud": [],
		"arena_radius": 60.0, "spawn": Vector2.ZERO, "spawn_h": 0.0,
		"tint": Color(1, 1, 1),
	})
	add_child(terrain)
	var fx := FxPool.new()
	add_child(fx)
	var projectiles := Projectiles.new(terrain, fx)
	add_child(projectiles)

	var sun := DirectionalLight3D.new()
	sun.light_cull_mask = ~2  # matches main.gd's real sun setup — exclude cockpit interior layer
	sun.rotation_degrees = Vector3(-50, 40, 0)
	sun.light_energy = 1.25
	add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.5, 0.6, 0.8)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.6, 0.65, 0.7)
	e.ambient_light_energy = 0.5
	env.environment = e
	add_child(env)

	var tank := PlayerTank.new(terrain, projectiles, fx)
	add_child(tank)
	tank.set_physics_process(false)
	tank.set_process(false)
	tank.global_position = Vector3(0, terrain.height(0, 0) + 0.04, 0)
	# battery/dome light on, matching a running tank, so the interior isn't
	# pitch dark (dome_light.light_energy defaults to 0.0 "off until battery on")
	if tank.cockpit.get("dome_light"):
		tank.cockpit["dome_light"].light_energy = 1.0

	var seat: Node3D = tank.cockpit["seat_anchor"]
	var eye_local: Vector3 = tank.cockpit["eye_local"]
	var eye_pos: Vector3 = seat.to_global(eye_local)

	var cam := Camera3D.new()
	cam.cull_mask = 0xFFFFF  # everything, layer 1 AND 2 — a real seated player's camera sees both
	add_child(cam)
	cam.current = true
	await get_tree().process_frame
	cam.global_position = eye_pos
	cam.rotation = Vector3.ZERO   # facing -Z, matching "seat faces -Z" (cockpit_builder.gd header)
	var forward_transform := cam.global_transform
	print("[cockpit-check] eye_pos=", eye_pos, " forward_transform=", forward_transform)
	await get_tree().process_frame
	await get_tree().process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://out"))
	get_viewport().get_texture().get_image().save_png(
		ProjectSettings.globalize_path("res://out/cockpit_view_forward.png"))
	print("[cockpit-check] forward (normal) shot saved")

	# Same exact transform, now with the debug facing shader on the WHOLE
	# tank (hull + cockpit) — settles whether the big flat surface seen in
	# the normal shot is a real backface (hull? cockpit static shell?) or
	# something else (missing texture, wrong material).
	_apply_debug_facing(tank)
	cam.global_transform = forward_transform
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(
		ProjectSettings.globalize_path("res://out/cockpit_view_forward_debug.png"))
	print("[cockpit-check] forward (debug facing, same transform) shot saved")
	get_tree().quit(0)

func _debug_facing_mat() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = "shader_type spatial;\nrender_mode cull_disabled, unshaded;\nvoid fragment() {\n\tif (FRONT_FACING) { ALBEDO = vec3(0.15, 0.95, 0.15); } else { ALBEDO = vec3(1.0, 0.05, 0.05); }\n}"
	var mat := ShaderMaterial.new()
	mat.shader = sh
	return mat

func _apply_debug_facing(root: Node) -> void:
	if root is MeshInstance3D:
		root.material_override = _debug_facing_mat()
	for c in root.get_children():
		_apply_debug_facing(c)

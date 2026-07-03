# Does terrain.gd's OWN chunk-mesh index pattern + its OWN real shader
# (not a stand-in material) actually render correctly from above? The
# corrected-convention math (tools/winding_math_check.gd's rule) says
# terrain's (a,c,b)/(b,c,d) index order is wound the SAME wrong way
# MeshKit.box() was — yet terrain visibly renders in every real screenshot.
# Only a real render, with the real shader, resolves the contradiction.
# Run: godot --path . scenes/terrain_winding_test.tscn
extends Node3D

func _ready() -> void:
	var t := Terrain.new({
		"rolling": 0.0, "dunes": false, "pond": false, "coast": false,
		"flatten": [[Vector2(0, 0), 200.0, 0.0]],
		"village": {}, "city": {}, "castle": {}, "mud": [],
		"arena_radius": 232.0, "spawn": Vector2.ZERO, "spawn_h": 0.0,
		"tint": Color(1, 1, 1),
	})
	add_child(t)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-60, 30, 0)
	sun.light_energy = 1.2
	add_child(sun)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.05, 0.05, 0.08)  # dark, so "nothing rendered" is unambiguous
	env.environment = e
	add_child(env)

	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	await get_tree().process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://out"))

	# above, looking straight down
	cam.global_position = Vector3(0, 15, 0)
	cam.look_at(Vector3(0.01, 0, 0), Vector3.FORWARD)
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(
		ProjectSettings.globalize_path("res://out/terrain_from_above.png"))
	print("[terrain-wind] above shot saved")

	# below (through the ground, if it were double-sided/invisible from above
	# but not below), looking straight up
	cam.global_position = Vector3(0, -8, 0)
	cam.look_at(Vector3(0.01, 0, 0), Vector3.FORWARD)
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(
		ProjectSettings.globalize_path("res://out/terrain_from_below.png"))
	print("[terrain-wind] below shot saved")

	# typical player vantage: standing near the surface, looking out at a
	# shallow angle (not straight down) -- the actual everyday view
	cam.global_position = Vector3(0, 1.7, 20)
	cam.look_at(Vector3(0, 1.5, 0), Vector3.UP)
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(
		ProjectSettings.globalize_path("res://out/terrain_eye_level.png"))
	print("[terrain-wind] eye-level shot saved")
	get_tree().quit(0)

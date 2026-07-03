# Decisive winding ground-truth test — no debug shaders, no audits, no
# interpretation. One MeshKit.box() and one MeshKit.cyl() rendered with a
# STRICT cull_back material (Godot's default for every StandardMaterial3D):
#   - If they're visible from OUTSIDE  -> MeshKit's winding matches Godot's
#     front-face convention (correct).
#   - If they're INVISIBLE from outside (and visible from a camera placed
#     inside) -> MeshKit's winding has been globally inverted since the
#     beginning, mesh_audit.gd shares the same backwards convention (it only
#     ever checked self-consistency), and every "looks inside-out" report
#     from VR was correct.
# Run:  godot --path . scenes/winding_ground_truth.tscn
extends Node3D

func _ready() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.9, 0.5, 0.1)
	mat.cull_mode = BaseMaterial3D.CULL_BACK   # explicit, though it's the default

	var st := MeshKit.begin()
	MeshKit.box(st, Transform3D(Basis(), Vector3(-1.5, 0, 0)), Vector3(2, 2, 2), Color(0.9, 0.5, 0.1))
	MeshKit.cyl(st, Transform3D(Basis(), Vector3(1.5, -1, 0)), 1.0, 1.0, 2.0, 12, Color(0.2, 0.6, 0.9))
	var mi := MeshInstance3D.new()
	mi.mesh = MeshKit.commit(st, mat)
	add_child(mi)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, 30, 0)
	add_child(light)
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.5, 0.55, 0.6)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(1, 1, 1)
	e.ambient_light_energy = 0.6
	env.environment = e
	add_child(env)

	var cam := Camera3D.new()
	add_child(cam)
	await get_tree().process_frame

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://out"))

	# Shot 1: from OUTSIDE. Visible shapes = winding correct. Empty = flipped.
	cam.global_position = Vector3(0, 2.5, 6)
	cam.look_at(Vector3(0, 0, 0), Vector3.UP)
	cam.current = true
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(
		ProjectSettings.globalize_path("res://out/winding_test_outside.png"))
	print("[winding] outside shot saved")

	# Shot 2: from INSIDE the box. Visible walls here + empty outside = flipped.
	cam.global_position = Vector3(-1.5, 0, 0)
	cam.look_at(Vector3(-1.5, 0, 1.0), Vector3.UP)
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(
		ProjectSettings.globalize_path("res://out/winding_test_inside.png"))
	print("[winding] inside shot saved")
	get_tree().quit(0)

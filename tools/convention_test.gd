# THE convention test. One triangle, vertices (0,0,0),(1,0,0),(0,1,0) in
# that order — right-hand-rule/geometric normal = +Z. Strict CULL_BACK
# material. Camera A at +Z looking back (-Z); camera B at -Z looking +Z.
#   - Triangle visible from +Z  -> Godot front face = counter-clockwise
#     (OpenGL convention): RHR-front renders.
#   - Triangle visible from -Z  -> Godot front face = clockwise: RHR-front
#     is culled.
# Two PNGs, one of which will be empty. No interpretation possible.
# Run: godot --path . scenes/convention_test.tscn
extends Node3D

func _ready() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for v in [Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0)]:
		st.set_normal(Vector3(0, 0, 1))
		st.add_vertex(v)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.3, 0.0)
	mat.cull_mode = BaseMaterial3D.CULL_BACK
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED  # no lighting ambiguity
	var mesh := st.commit()
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	add_child(mi)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.2, 0.25, 0.3)
	env.environment = e
	add_child(env)

	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	await get_tree().process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://out"))

	cam.global_position = Vector3(0.33, 0.33, 2.0)   # +Z side (RHR-normal side)
	cam.look_at(Vector3(0.33, 0.33, 0), Vector3.UP)
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(
		ProjectSettings.globalize_path("res://out/convention_from_plusZ.png"))
	print("[conv] +Z shot saved")

	cam.global_position = Vector3(0.33, 0.33, -2.0)  # -Z side (behind the RHR normal)
	cam.look_at(Vector3(0.33, 0.33, 0), Vector3.UP)
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(
		ProjectSettings.globalize_path("res://out/convention_from_minusZ.png"))
	print("[conv] -Z shot saved")
	get_tree().quit(0)

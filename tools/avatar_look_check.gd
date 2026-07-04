# One-shot render check for AvatarRig's soldier dressing pass.
# Run: godot --path . --xr-mode off scenes/avatar_look_check.tscn
extends Node3D

func _ready() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.25, 0.28, 0.32)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.7, 0.7, 0.75)
	e.ambient_light_energy = 0.6
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-45, 35, 0)
	add_child(sun)
	var av := AvatarRig.new()
	add_child(av)
	av.configure(AvatarRig.Mode.ON_FOOT, Color(0.30, 0.55, 0.90))
	av.position = Vector3(-0.45, 1.55, 0)
	av.update_live(0.0, Transform3D(), Transform3D(Basis(), Vector3(-0.35, -0.45, -0.25)), Transform3D(Basis(), Vector3(0.35, -0.5, -0.2)))
	var av2 := AvatarRig.new()
	add_child(av2)
	av2.configure(AvatarRig.Mode.SEATED, Color(0.85, 0.4, 0.25))
	av2.position = Vector3(0.55, 1.35, 0)
	av2.update_live(0.0, Transform3D(), Transform3D(Basis(), Vector3(-0.3, -0.4, -0.3)), Transform3D(Basis(), Vector3(0.3, -0.4, -0.3)))
	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	cam.position = Vector3(0.05, 1.3, 2.1)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://out"))
	get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://out/avatar_look.png"))
	print("[avatar-check] saved")
	get_tree().quit(0)

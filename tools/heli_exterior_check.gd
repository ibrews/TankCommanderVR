# Quick exterior sanity check for the rebuilt Heli cockpit position — verifies
# the cockpit bubble (moved forward past the fuselage's front cap to fix
# Alex's "no good view / doesn't feel like a cockpit" report) still reads as
# part of the helicopter and doesn't look like a detached blob floating in
# front of the nose.
# Run: godot --path . scenes/heli_exterior_check.tscn
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

	var heli := PlayerAlt.Heli.new(terrain, projectiles, fx)
	add_child(heli)
	heli.set_physics_process(false)
	heli.set_process(false)
	heli.global_position = Vector3(0, terrain.height(0, 0) + 2.0, 0)
	heli.rotation = Vector3.ZERO

	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	await get_tree().process_frame
	cam.global_position = heli.global_position + Vector3(4.5, 1.0, -1.0)
	cam.look_at(heli.global_position + Vector3(0, 0.3, -1.0), Vector3.UP)
	await get_tree().process_frame
	await get_tree().process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://out"))
	get_viewport().get_texture().get_image().save_png(
		ProjectSettings.globalize_path("res://out/heli_exterior_side.png"))
	print("[heli-exterior-check] side shot saved")

	cam.global_position = heli.global_position + Vector3(0.3, 0.6, -5.0)
	cam.look_at(heli.global_position + Vector3(0, 0.2, 0), Vector3.UP)
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(
		ProjectSettings.globalize_path("res://out/heli_exterior_front.png"))
	print("[heli-exterior-check] front shot saved")
	get_tree().quit(0)

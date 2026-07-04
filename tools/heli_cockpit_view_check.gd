# Real first-person seated cockpit view for the HELICOPTER, same recipe as
# tools/cockpit_view_check.gd (the tank version) — verifying Alex's live-
# headset report "In the helicopter I don't have a good view and don't feel
# like I'm in a cockpit" after rebuilding PlayerAlt.Heli's cockpit.
# Run: godot --path . scenes/heli_cockpit_view_check.tscn
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

	var heli := PlayerAlt.Heli.new(terrain, projectiles, fx)
	add_child(heli)
	heli.set_physics_process(false)
	heli.set_process(false)
	heli.global_position = Vector3(0, terrain.height(0, 0) + 2.0, 0)
	heli.rotation = Vector3.ZERO

	var seat: Node3D = heli.cockpit["seat_anchor"]
	var eye_local: Vector3 = heli.cockpit["eye_local"]
	var eye_pos: Vector3 = seat.to_global(eye_local)

	var cam := Camera3D.new()
	cam.cull_mask = 0xFFFFF  # everything, layer 1 AND 2 — a real seated player's camera sees both
	add_child(cam)
	cam.current = true
	await get_tree().process_frame
	cam.global_position = eye_pos
	cam.global_transform = Transform3D(heli.global_transform.basis, eye_pos)  # facing heli's -Z, matching seated pilot
	var forward_transform := cam.global_transform
	print("[heli-cockpit-check] eye_pos=", eye_pos, " forward_transform=", forward_transform)
	await get_tree().process_frame
	await get_tree().process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://out"))
	get_viewport().get_texture().get_image().save_png(
		ProjectSettings.globalize_path("res://out/heli_cockpit_view_forward.png"))
	print("[heli-cockpit-check] forward (normal) shot saved")

	# look down-and-forward too, to check the chin/canopy view toward the ground
	cam.global_transform = forward_transform
	cam.rotate_object_local(Vector3.RIGHT, deg_to_rad(35))
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(
		ProjectSettings.globalize_path("res://out/heli_cockpit_view_down.png"))
	print("[heli-cockpit-check] down-angle shot saved")
	get_tree().quit(0)

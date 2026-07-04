# Real first-person seated PLANE cockpit view, normal materials (no debug
# shader) -- to actually SEE what Alex described ("I can't see over the top
# of the front... single yellow lever... doesn't feel like a cockpit")
# instead of guessing from reading player_plane.gd. Points the camera from
# the real seat-anchor eye position looking forward, like a seated pilot.
# Run: godot --path . scenes/plane_cockpit_view_check.tscn
extends Node3D

func _ready() -> void:
	var terrain := Terrain.new(Levels.get_config("outdoor"))
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

	for is_biplane in [false, true]:
		var plane := PlayerPlane.new(terrain, projectiles, fx)
		plane.biplane = is_biplane
		add_child(plane)
		plane.set_physics_process(false)
		plane.set_process(false)
		plane.global_position = Vector3(0, terrain.height(0, 0) + 3.0, 0)
		plane.basis = Basis.IDENTITY

		var seat: Node3D = plane.cockpit["seat_anchor"]
		var eye_local: Vector3 = plane.cockpit["eye_local"]
		var eye_pos: Vector3 = seat.to_global(eye_local)

		var cam := Camera3D.new()
		cam.cull_mask = 0xFFFFF  # everything, layer 1 AND 2 — a real seated player's camera sees both
		add_child(cam)
		cam.current = true
		await get_tree().process_frame
		cam.global_position = eye_pos
		cam.global_transform = cam.global_transform.looking_at(eye_pos + (-plane.global_transform.basis.z), Vector3.UP)
		print("[plane-cockpit-check] biplane=", is_biplane, " eye_pos=", eye_pos)
		await get_tree().process_frame
		await get_tree().process_frame
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://out"))
		var suffix := "biplane" if is_biplane else "plane"
		get_viewport().get_texture().get_image().save_png(
			ProjectSettings.globalize_path("res://out/plane_cockpit_view_%s.png" % suffix))
		print("[plane-cockpit-check] ", suffix, " forward shot saved")

		cam.queue_free()
		plane.queue_free()
		await get_tree().process_frame

	get_tree().quit(0)

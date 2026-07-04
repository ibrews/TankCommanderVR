# Render-test for Alex's "enemies look flat solid white, basic shading, no
# textures" report. enemy_tank.gd's hull/turret meshes use MeshKit.mat_vcol()
# (StandardMaterial3D.vertex_color_use_as_albedo=true) with real per-vertex
# tan/dark colors written via SurfaceTool.set_color() (confirmed by code
# review) -- this test settles whether that actually reaches the render or
# silently falls back to the material's default white albedo_color, same
# "build a real render test instead of guessing" discipline as
# cockpit_view_check.gd. Run non-headless: godot --path . scenes/enemy_material_check.tscn
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
	var player_stub := PlayerTank.new(terrain, projectiles, fx)
	add_child(player_stub)
	player_stub.set_physics_process(false)
	player_stub.set_process(false)
	player_stub.global_position = Vector3(30, terrain.height(30, 0), 0)

	# EXACT copy of main.gd._setup_environment()'s real values, sky-source
	# ambient included -- this is the actual in-game lighting, untested by
	# the previous two attempts (both used a flat AMBIENT_SOURCE_COLOR,
	# which is NOT what the real game uses).
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.28, 0.42, 0.66)
	sky_mat.sky_horizon_color = Color(0.66, 0.60, 0.50)
	sky_mat.ground_bottom_color = Color(0.32, 0.28, 0.22)
	sky_mat.ground_horizon_color = Color(0.60, 0.54, 0.46)
	sky_mat.sun_angle_max = 22.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_sky_contribution = 1.0
	e.ambient_light_energy = 0.85
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-38), deg_to_rad(48), 0)
	sun.light_color = Color(1.0, 0.93, 0.80)
	sun.light_energy = 1.25
	add_child(sun)

	var enemy := EnemyTank.new(terrain, projectiles, fx, player_stub)
	add_child(enemy)
	enemy.set_physics_process(false)
	enemy.set_process(false)
	enemy.global_position = Vector3(0, terrain.height(0, 0), 0)

	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	await get_tree().process_frame
	cam.global_position = Vector3(0, 3.0, 8.0)
	cam.look_at(enemy.global_position + Vector3(0, 1.2, 0), Vector3.UP)
	await get_tree().process_frame
	await get_tree().process_frame
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://out"))
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("res://out/enemy_material_check.png"))
	# Sample the hull's actual pixel color at the image center -- cheap,
	# self-grading check (per the "grade your own debug script against a
	# known-bad case before trusting it" lesson) instead of eyeballing only.
	var w := img.get_width()
	var h := img.get_height()
	var sample := img.get_pixel(int(w * 0.5), int(h * 0.45))
	print("[enemy-check] center pixel color=", sample)
	print("[enemy-check] expected roughly tan (0.55,0.48,0.38)-ish, NOT near-white (1,1,1)")
	get_tree().quit(0)

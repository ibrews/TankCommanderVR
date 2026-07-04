# Consolidated Meta Quest App Lab store-art capture pass -- one process run,
# multiple stages, each a REAL in-engine render via
# get_viewport().get_texture() (same discipline as cockpit_view_check.gd /
# enemy_material_check.gd: build the actual game classes, don't fake it).
# Feeds intelligence/runbooks/meta-quest-app-lab-store-assets.md's size
# table -- this script only captures raw PNGs at generous resolutions;
# ImageMagick composes the exact required sizes afterward.
#
# Resizes its own window per stage via DisplayServer (never touches
# project.godot's window/size, which is shared with normal gameplay runs).
# Run non-headless (needs a real framebuffer) from the project root:
#   Godot..._console.exe --path . scenes/store_capture.tscn
# Output: res://out/store/*.png
extends Node3D

var terrain: Terrain
var fx: FxPool
var projectiles: Projectiles
var cam: Camera3D
var env: Environment
const OUT_DIR := "res://out/store"

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	DisplayServer.window_set_position(Vector2i(0, 0))

	terrain = Terrain.new({
		"rolling": 3.0, "detail": 1.0, "rim": true,
		"dunes": false, "pond": true, "coast": false, "island": false, "archipelago": false, "volcano": false,
		"flatten": [[Vector2(0, 0), 90.0, 0.0]],
		"village": {}, "city": {}, "castle": {}, "mud": [],
		"arena_radius": 260.0, "spawn": Vector2.ZERO, "spawn_h": 0.0,
		"tint": Color(1, 1, 1),
	})
	add_child(terrain)
	fx = FxPool.new()
	add_child(fx)
	projectiles = Projectiles.new(terrain, fx)
	add_child(projectiles)
	_build_lighting()

	cam = Camera3D.new()
	add_child(cam)
	cam.current = true
	cam.far = 4000.0
	await get_tree().process_frame

	await _stage_hero()
	await _stage_vehicles()
	await _stage_combat()
	await _stage_cockpit()
	print("[store-capture] ALL DONE")
	get_tree().quit(0)

# ---------------------------------------------------------------- lighting
# Exact values from main.gd._setup_environment() -- real game lighting, not
# a flat neutral stage light, since this feeds "real in-experience" store art.
func _build_lighting() -> void:
	env = Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.28, 0.42, 0.66)
	sky_mat.sky_horizon_color = Color(0.66, 0.60, 0.50)
	sky_mat.ground_bottom_color = Color(0.32, 0.28, 0.22)
	sky_mat.ground_horizon_color = Color(0.60, 0.54, 0.46)
	sky_mat.sun_angle_max = 22.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_bloom = 0.08
	env.glow_hdr_threshold = 1.05
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-42), deg_to_rad(55), 0)
	sun.light_color = Color(1.0, 0.93, 0.80)
	sun.light_energy = 1.3
	sun.shadow_enabled = true
	add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(deg_to_rad(-14), deg_to_rad(55 + 180), 0)
	fill.light_color = Color(0.85, 0.78, 0.65)
	fill.light_energy = 0.24
	add_child(fill)

func _sky_env() -> void:
	env.background_mode = Environment.BG_SKY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.ambient_light_energy = 0.9
	env.fog_enabled = false

func _chroma_env() -> void:
	# Solid magenta -- not used anywhere in vehicle materials -- so the
	# spatialized-tile foreground layer can be keyed to alpha in ImageMagick.
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(1, 0, 1)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 0.75
	env.fog_enabled = false

func _gy(x: float, z: float) -> float:
	return terrain.height(x, z)

func _freeze(n: Node) -> void:
	if n.has_method("set_physics_process"):
		n.set_physics_process(false)
	if n.has_method("set_process"):
		n.set_process(false)

func _resize(w: int, h: int) -> void:
	DisplayServer.window_set_size(Vector2i(w, h))
	await get_tree().process_frame
	await get_tree().process_frame

func _shot(name: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path(OUT_DIR + "/" + name + ".png"))
	print("[store-capture] saved ", name)

# ---------------------------------------------------------------- hero master
# One wide composition, all 5 vehicles + an explosion, subject kept centered
# with generous margin -- this is the master ImageMagick crops from for
# landscape/square/portrait/hero cover art (see the runbook's "don't reuse
# one crop for every aspect ratio" gotcha). 2800x1400 fits this monitor
# (3440x1440) without exceeding it.
func _stage_hero() -> void:
	await _resize(2800, 1400)
	_sky_env()

	var tank := PlayerTank.new(terrain, projectiles, fx)
	add_child(tank)
	_freeze(tank)
	tank.global_position = Vector3(0, _gy(0, 8) + 0.04, 8)
	tank.rotation.y = deg_to_rad(200)
	if tank.reticle:
		tank.reticle.visible = false

	var plane := PlayerPlane.new(terrain, projectiles, fx)
	add_child(plane)
	_freeze(plane)
	plane.global_position = Vector3(-19, 15, -10)
	plane.rotation = Vector3(deg_to_rad(-6), deg_to_rad(150), deg_to_rad(8))

	var biplane := PlayerPlane.new(terrain, projectiles, fx)
	biplane.biplane = true
	add_child(biplane)
	_freeze(biplane)
	biplane.global_position = Vector3(20, 12, -6)
	biplane.rotation = Vector3(deg_to_rad(-4), deg_to_rad(-160), deg_to_rad(-6))

	var heli := PlayerAlt.Heli.new(terrain, projectiles, fx)
	add_child(heli)
	_freeze(heli)
	heli.global_position = Vector3(12, 8, 20)
	heli.rotation.y = deg_to_rad(210)

	var boat := PlayerBoat.new(terrain, projectiles, fx)
	add_child(boat)
	_freeze(boat)
	boat.global_position = Vector3(-15, _gy(-15, 24) + 0.3, 24)
	boat.rotation.y = deg_to_rad(230)

	await get_tree().process_frame
	fx.explosion(Vector3(4, _gy(4, 6) + 1.0, 6), true, Vector3(0, 6, -20))

	cam.global_position = Vector3(0, 6.2, -20)
	cam.look_at(Vector3(0, 3.5, 9), Vector3.UP)
	cam.fov = 50
	await get_tree().create_timer(0.2).timeout
	_shot("hero_master")

	for c in [tank, plane, biplane, heli, boat]:
		c.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

# ---------------------------------------------------------------- per-vehicle
# pos is set AFTER add_child (Node3D.global_position is a no-op outside the
# tree, and _ready()'s own _respawn() would clobber a pre-add_child value
# anyway) -- setting it after is the only order that actually sticks.
func _capture_solo(node: Node3D, pos: Vector3, cam_off: Vector3, look_off: Vector3, vname: String) -> void:
	add_child(node)
	_freeze(node)
	node.global_position = pos
	var reticle = node.get("reticle")
	if reticle:
		reticle.visible = false
	await get_tree().process_frame
	await get_tree().process_frame

	_sky_env()
	cam.global_position = node.global_position + cam_off
	cam.look_at(node.global_position + look_off, Vector3.UP)
	cam.fov = 42
	await get_tree().create_timer(0.25).timeout
	_shot("vehicle_" + vname)

	# Chroma-key cutout for the spatialized-tile foreground layer: background
	# color alone leaves the ground/mountains visible below the horizon, so
	# hide the terrain outright rather than relying on env state alone.
	terrain.visible = false
	_chroma_env()
	await get_tree().create_timer(0.25).timeout
	_shot("vehicle_" + vname + "_chroma")

	terrain.visible = true
	_sky_env()
	await get_tree().create_timer(0.3).timeout

	node.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

func _stage_vehicles() -> void:
	await _resize(2560, 1440)
	var g := _gy(0, 0)

	await _capture_solo(PlayerTank.new(terrain, projectiles, fx),
		Vector3(0, g + 0.04, 0), Vector3(6.6, 3.1, 7.2), Vector3(0, 1.4, 0), "tank")

	await _capture_solo(PlayerPlane.new(terrain, projectiles, fx),
		Vector3(0, g + 2.2, 0), Vector3(9.0, 2.6, 9.5), Vector3(0, 1.0, 0), "plane")

	var biplane := PlayerPlane.new(terrain, projectiles, fx)
	biplane.biplane = true
	await _capture_solo(biplane,
		Vector3(0, g + 2.2, 0), Vector3(8.0, 3.0, 8.5), Vector3(0, 1.2, 0), "biplane")

	await _capture_solo(PlayerAlt.Heli.new(terrain, projectiles, fx),
		Vector3(0, g + 1.6, 0), Vector3(7.0, 3.2, 8.0), Vector3(0, 1.4, 0), "heli")

	await _capture_solo(PlayerBoat.new(terrain, projectiles, fx),
		Vector3(0, g + 0.3, 0), Vector3(7.0, 2.6, 7.5), Vector3(0, 1.0, 0), "boat")

# ---------------------------------------------------------------- combat action
func _stage_combat() -> void:
	await _resize(2560, 1440)
	_sky_env()

	var player := PlayerTank.new(terrain, projectiles, fx)
	add_child(player)
	_freeze(player)
	player.global_position = Vector3(-8, _gy(-8, 0) + 0.04, 0)
	player.rotation.y = deg_to_rad(80)
	if player.reticle:
		player.reticle.visible = false

	var e1 := EnemyTank.new(terrain, projectiles, fx, player)
	add_child(e1)
	_freeze(e1)
	e1.global_position = Vector3(14, _gy(14, -4) + 0.04, -4)

	var e2 := EnemyTank.new(terrain, projectiles, fx, player)
	add_child(e2)
	_freeze(e2)
	e2.global_position = Vector3(20, _gy(20, 10) + 0.04, 10)

	cam.global_position = Vector3(-14, 4.5, 10)
	cam.look_at(Vector3(6, 2.0, 2), Vector3.UP)
	cam.fov = 60
	await get_tree().process_frame

	fx.explosion(Vector3(16, _gy(16, 2) + 1.0, 2), true, cam.global_position)
	await get_tree().create_timer(0.12).timeout
	_shot("combat_explosion")

	for c in [player, e1, e2]:
		c.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

# ---------------------------------------------------------------- cockpit interior
# Same real seat-anchor eye transform as cockpit_view_check.gd, just folded
# into this consolidated capture pass at store-art resolution.
func _stage_cockpit() -> void:
	await _resize(2560, 1440)
	_sky_env()

	var tank := PlayerTank.new(terrain, projectiles, fx)
	add_child(tank)
	_freeze(tank)
	tank.global_position = Vector3(0, _gy(0, 0) + 0.04, 0)
	if tank.cockpit.get("dome_light"):
		tank.cockpit["dome_light"].light_energy = 1.0

	var seat: Node3D = tank.cockpit["seat_anchor"]
	var eye_local: Vector3 = tank.cockpit["eye_local"]
	var eye_pos: Vector3 = seat.to_global(eye_local)

	cam.top_level = true
	cam.cull_mask = 0xFFFFF
	cam.global_position = eye_pos
	cam.rotation = Vector3.ZERO
	cam.fov = 75
	await get_tree().process_frame
	await get_tree().process_frame
	_shot("cockpit_interior")

	tank.queue_free()
	await get_tree().process_frame

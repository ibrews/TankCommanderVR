# Meta Horizon Store 360-degree preview -- 6x1 monoscopic cubestrip capture.
# Per intelligence/runbooks/meta-quest-app-lab-store-assets.md (verified
# against developers.meta.com/horizon/resources/asset-guidelines/ 2026-07-04):
# minimum target 12288x2048 (2048 per face), face order left/right/up/down/
# front/back. Uses the REAL "outdoor" level config (Terrain + WorldDressing's
# actual scatter -- village, dunes, pond, trees/rocks, wrecks) so the 360
# environment is genuine in-experience content, not a staged/minimal stand-in.
#
# Run non-headless (needs a real framebuffer):
#   Godot..._console.exe --path . scenes/cubestrip_capture.tscn > log.txt 2>&1
# (direct file redirect, NOT tee -- see godot-headless-write-movie.md gotcha)
# Output: res://out/cubestrip/face_*.png (2048x2048 each) -- assemble into
# the final strip afterward with ImageMagick (+append in the order above).
extends Node3D

const FACE_SIZE := 2048

var terrain: Terrain
var cam: Camera3D

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://out/cubestrip"))
	DisplayServer.window_set_size(Vector2i(FACE_SIZE, FACE_SIZE))
	await get_tree().process_frame
	await get_tree().process_frame

	var cfg: Dictionary = Levels.CONFIGS["outdoor"].duplicate(true)
	terrain = Terrain.new(cfg)
	add_child(terrain)
	var wd := WorldDressing.new(terrain)
	add_child(wd)
	await get_tree().process_frame

	_build_lighting()

	cam = Camera3D.new()
	add_child(cam)
	cam.current = true
	cam.fov = 90
	cam.far = 4000.0

	var spawn: Vector2 = cfg["spawn"]
	var eye := Vector3(spawn.x, terrain.height(spawn.x, spawn.y) + 1.6, spawn.y)

	await get_tree().process_frame
	await get_tree().create_timer(0.4).timeout

	# Face order per Meta's spec: left, right, up, down, front, back -- but
	# the names are GL cubemap slots (+X -X +Y -Y +Z -Z), not what's on the
	# viewer's left/right: the store viewer samples the cube from inside,
	# which mirrors each face, so "left" must hold the view 90-deg to the
	# RIGHT of front (and vice versa), and up/down need image-top toward
	# back/front. Ground truth: Meta's own OVRCubemapCapture.cs generator.
	# Taking the names literally transposed left/right and rolled up/down
	# 180 -- broke all 4 vertical seams on the store page (near-uniform
	# sky/ground faces hid their half of the bug). front = -Z per this
	# project's "seat faces -Z" forward convention (cockpit_builder.gd).
	var dirs := [
		{"name": "left", "look": Vector3(1, 0, 0), "up": Vector3.UP},
		{"name": "right", "look": Vector3(-1, 0, 0), "up": Vector3.UP},
		{"name": "up", "look": Vector3(0, 1, 0), "up": Vector3(0, 0, 1)},
		{"name": "down", "look": Vector3(0, -1, 0), "up": Vector3(0, 0, -1)},
		{"name": "front", "look": Vector3(0, 0, -1), "up": Vector3.UP},
		{"name": "back", "look": Vector3(0, 0, 1), "up": Vector3.UP},
	]
	for d in dirs:
		cam.global_position = eye
		cam.look_at(eye + d["look"], d["up"])
		await get_tree().process_frame
		await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		img.save_png(ProjectSettings.globalize_path("res://out/cubestrip/face_" + d["name"] + ".png"))
		print("[cubestrip] saved ", d["name"])

	print("[cubestrip] ALL DONE")
	get_tree().quit(0)

func _build_lighting() -> void:
	var env := Environment.new()
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
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-42), deg_to_rad(55), 0)
	sun.light_color = Color(1.0, 0.93, 0.80)
	sun.light_energy = 1.3
	add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(deg_to_rad(-14), deg_to_rad(55 + 180), 0)
	fill.light_color = Color(0.85, 0.78, 0.65)
	fill.light_energy = 0.24
	add_child(fill)

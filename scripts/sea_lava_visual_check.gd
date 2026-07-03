# Debug-only visual verification for the _build_sea()/_build_lava() winding
# fix (2026-07-03) — these two functions aren't reachable from
# asset_showcase.tscn (its terrain cfg deliberately sets coast/volcano to
# false), and mesh_audit.gd's analytical check can't PROVE the fix looks
# right on screen, only that the raw vertex math is now internally
# consistent. This closes that gap with an actual screenshot.
#
# Builds a real WorldDressing with coast=true + volcano=true so BOTH
# _build_sea() and _build_lava() fire through their real _ready() gate (not
# a hand-mirrored replica), flies through a couple of waypoints, and quits.
#
# Run: godot --headless --path . scenes/sea_lava_visual_check.tscn
extends Node3D

var _cam: Camera3D
var _debug_step := 0
const _WAYPOINTS := [
	{"name": "sea_horizon_from_inside", "pos": Vector3(0, 4, 0), "look": Vector3(300, 8, 0)},
	{"name": "sea_horizon_low_angle", "pos": Vector3(150, 2, 150), "look": Vector3(400, 4, 400)},
	{"name": "lava_overview", "pos": Vector3(0, 20, -60), "look": Vector3(0, -3, 0)},
	{"name": "lava_close", "pos": Vector3(20, 3, 20), "look": Vector3(0, -3, 0)},
]


func _ready() -> void:
	_build_lighting()

	var cfg := {
		"rolling": 3.0, "detail": 1.0, "rim": true,
		"dunes": false, "pond": false, "coast": true, "island": false,
		"archipelago": false, "volcano": true,
		"flatten": [], "trees": 0, "palms": 0, "rocks": 10,
		"spawn": Vector2(0, 0), "spawn_h": 0.0,
		"village": {}, "city": {}, "castle": {}, "mud": [],
		"wrecks": 0, "lava_y": -3.2,
		"arena_radius": 232.0,
		"tint": Color(1, 1, 1),
	}
	var terrain := Terrain.new(cfg)
	add_child(terrain)

	# Real _ready() fires here (add_child, not the mesh_audit.gd pattern of
	# deliberately avoiding it) — this is the actual production code path
	# that runs when a coast/volcano level loads, unmodified.
	var wd := WorldDressing.new(terrain)
	add_child(wd)

	_cam = Camera3D.new()
	add_child(_cam)

	print("[sea_lava_check] ready")
	get_tree().create_timer(0.6).timeout.connect(_shot_sequence)


func _build_lighting() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.5, 0.6, 0.75)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-52), deg_to_rad(35), 0)
	sun.light_energy = 1.0
	add_child(sun)


func _shot_sequence() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://out"))
	if _debug_step >= _WAYPOINTS.size():
		print("[sea_lava_check] done")
		get_tree().quit(0)
		return
	var wp: Dictionary = _WAYPOINTS[_debug_step]
	_cam.global_position = wp["pos"]
	_cam.look_at(wp["look"], Vector3.UP)
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("res://out/sealava_%02d_%s.png" % [_debug_step, wp["name"]]))
	print("[sea_lava_check] shot ", wp["name"])
	_debug_step += 1
	get_tree().create_timer(0.15).timeout.connect(_shot_sequence)

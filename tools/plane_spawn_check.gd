# Throwaway visual verification for the plane-spawn-on-edge-flying-toward-
# far-side fix (live playtest, Alex: "when a plane spawns put it on one side
# of the map going into the direction of the farthest side of the map, we
# spawn near the edge of the map"). Spawns a real Terrain + EnemyManager,
# forces a wave-2+ transition (planes don't spawn until wave 2), then takes
# a top-down overview screenshot showing the player spawn, each plane's
# spawn point, and a short trail of its heading so the flight line can be
# checked by eye. Non-headless: godot --path . scenes/plane_spawn_check.tscn
extends Node3D

var terrain: Terrain
var em: EnemyManager
var player_stub: CharacterBody3D
var _frame := 0
var _trails: Array = []  # Array[Array[Vector3]] per plane

func _ready() -> void:
	Levels.current = Levels.get_config("outdoor")
	terrain = Terrain.new(Levels.current)
	add_child(terrain)
	var fx := FxPool.new()
	add_child(fx)
	var projectiles := Projectiles.new(terrain, fx)
	add_child(projectiles)
	player_stub = PlayerTank.new(terrain, projectiles, fx)
	add_child(player_stub)
	player_stub.set_physics_process(false)
	player_stub.set_process(false)
	player_stub.global_position = Vector3(terrain.spawn.x, terrain.height(terrain.spawn.x, terrain.spawn.y) + 1.2, terrain.spawn.y)

	em = EnemyManager.new(terrain, projectiles, fx, player_stub)
	add_child(em)  # Godot calls EnemyManager._ready() automatically here
	# Force straight to wave 2 so planes are included (planes = 1 starting wave >= 2).
	em.wave = 1
	em._spawn_wave()

	print("[plane-check] player spawn (terrain.spawn) = ", terrain.spawn, " arena_radius=", terrain.arena_radius)
	for c in em.get_children():
		if c is EnemyPlane:
			print("[plane-check] plane spawn=", c.global_position, " transit_target=", c.transit_target, " state=", c.state, " heading=", c.heading)
			_trails.append([c])

	var cam := Camera3D.new()
	add_child(cam)
	cam.current = true
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 700.0
	cam.global_position = Vector3(0, 400, 0.001)
	cam.look_at(Vector3.ZERO, Vector3(0, 0, -1))

	# simple debug markers: small colored boxes at spawn / target / player.
	_mark(Vector3(terrain.spawn.x, 5.0, terrain.spawn.y), Color(0, 1, 0))  # player spawn = green
	for c in em.get_children():
		if c is EnemyPlane:
			_mark(c.global_position, Color(1, 0, 0))  # plane spawn = red
			_mark(Vector3(c.transit_target.x, 5.0, c.transit_target.y), Color(1, 1, 0))  # target = yellow

	await get_tree().process_frame
	await get_tree().process_frame

func _mark(pos: Vector3, col: Color) -> void:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(12, 12, 12)
	mi.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = mat
	add_child(mi)
	mi.global_position = pos

func _process(_delta: float) -> void:
	_frame += 1
	# let planes fly under real _physics_process for ~3s of sim time, leaving
	# a breadcrumb trail so the screenshot shows the flight line, not just
	# the spawn point.
	if _frame % 6 == 0:
		for arr in _trails:
			var p: EnemyPlane = arr[0]
			if is_instance_valid(p):
				_mark(p.global_position, Color(1, 0.5, 0, 0.6))
	if _frame == 200:
		for c in em.get_children():
			if c is EnemyPlane:
				print("[plane-check] AFTER 200 frames: plane pos=", c.global_position, " state=", c.state, " heading=", c.heading)
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://out"))
		var img := get_viewport().get_texture().get_image()
		img.save_png(ProjectSettings.globalize_path("res://out/plane_spawn_check.png"))
		print("[plane-check] saved res://out/plane_spawn_check.png")
		get_tree().quit(0)

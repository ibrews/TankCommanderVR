# Meta Quest App Lab trailer capture -- a scripted, deterministic tour
# (cockpit -> tank combat -> plane/biplane/heli/boat flybys -> finale ->
# title card) meant to be captured with Godot's built-in Movie Maker mode,
# which forces a fixed timestep so every await/timer here maps to an exact
# frame count regardless of real render speed, and bakes the real AudioServer
# mix (engine/cannon/explosion SFX) into the output video's audio track.
# Narration is mixed in on top afterward via ffmpeg -- see tools/gen_vo.py's
# convention and the "trailer_*" lines added there.
#
# Run (non-headless, needs a real framebuffer -- same discipline as
# store_capture.gd):
#   Godot..._console.exe --path . --resolution 1920x1080 --fixed-fps 30 \
#       --write-movie out/trailer/trailer_raw.avi scenes/trailer_sequence.tscn
extends Node3D

var terrain: Terrain
var fx: FxPool
var projectiles: Projectiles
var cam: Camera3D
var env: Environment

func _ready() -> void:
	terrain = Terrain.new({
		"rolling": 3.0, "detail": 1.0, "rim": true,
		"dunes": false, "pond": true, "coast": false, "island": false, "archipelago": false, "volcano": false,
		"flatten": [[Vector2(0, 0), 140.0, 0.0]],
		"village": {}, "city": {}, "castle": {}, "mud": [],
		"arena_radius": 280.0, "spawn": Vector2.ZERO, "spawn_h": 0.0,
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
	cam.fov = 55
	await get_tree().process_frame

	var t0 := Time.get_ticks_msec()
	await _seg_cockpit_intro()
	print("[trailer] cockpit_intro done @", (Time.get_ticks_msec() - t0) / 1000.0, "s wall")
	await _seg_tank_drive()
	print("[trailer] tank_drive done @", (Time.get_ticks_msec() - t0) / 1000.0, "s wall")
	await _seg_tank_combat()
	print("[trailer] tank_combat done @", (Time.get_ticks_msec() - t0) / 1000.0, "s wall")
	await _seg_plane_flyby()
	print("[trailer] plane_flyby done @", (Time.get_ticks_msec() - t0) / 1000.0, "s wall")
	await _seg_biplane_flyby()
	print("[trailer] biplane_flyby done @", (Time.get_ticks_msec() - t0) / 1000.0, "s wall")
	await _seg_heli_pass()
	print("[trailer] heli_pass done @", (Time.get_ticks_msec() - t0) / 1000.0, "s wall")
	await _seg_boat_cruise()
	print("[trailer] boat_cruise done @", (Time.get_ticks_msec() - t0) / 1000.0, "s wall")
	await _seg_finale()
	print("[trailer] finale done @", (Time.get_ticks_msec() - t0) / 1000.0, "s wall")
	await _seg_outro_card()
	print("[trailer] outro_card done @", (Time.get_ticks_msec() - t0) / 1000.0, "s wall")

	print("[trailer] ALL DONE")
	get_tree().quit(0)

# ---------------------------------------------------------------- lighting
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

func _gy(x: float, z: float) -> float:
	return terrain.height(x, z)

# Continuously re-frames the camera behind/around a moving vehicle for the
# whole hold -- a locked-off shot would lose a vehicle that's actually
# flying/driving under real physics, so this is the standard chase-cam
# pattern for every moving segment below. get_process_delta_time() (not a
# wall-clock timer) so it stays correct under Movie Maker's fixed timestep.
func _chase_hold(vehicle: Node3D, offset: Vector3, look_offset: Vector3, duration: float) -> void:
	var t := 0.0
	while t < duration:
		if is_instance_valid(vehicle):
			cam.global_position = vehicle.global_position + offset
			cam.look_at(vehicle.global_position + look_offset, Vector3.UP)
		await get_tree().process_frame
		t += get_process_delta_time()

func _hold(duration: float) -> void:
	await get_tree().create_timer(duration).timeout

# ---------------------------------------------------------------- segments
func _seg_cockpit_intro() -> void:
	var tank := PlayerTank.new(terrain, projectiles, fx)
	add_child(tank)
	tank.global_position = Vector3(0, _gy(0, 0) + 0.04, 0)
	await get_tree().process_frame
	if tank.cockpit.get("dome_light"):
		tank.cockpit["dome_light"].light_energy = 1.0

	var seat: Node3D = tank.cockpit["seat_anchor"]
	var eye_local: Vector3 = tank.cockpit["eye_local"]
	cam.top_level = true
	cam.global_position = seat.to_global(eye_local)
	cam.rotation = Vector3(-0.03, 0.35, 0)
	cam.fov = 70
	tank.quick_start()
	await _hold(3.5)
	cam.top_level = false
	_intro_tank = tank

var _intro_tank: PlayerTank

func _seg_tank_drive() -> void:
	var tank := _intro_tank
	tank.global_position = Vector3(0, _gy(0, 0) + 0.04, 0)
	tank.rotation.y = 0.0
	cam.fov = 55
	await get_tree().process_frame
	var t := 0.0
	while t < 5.0:
		tank.set_stick_drive(Vector2(0.15 * sin(t * 0.6), 0.9))
		tank.set_stick_turret(Vector2(0.4 * sin(t * 0.8), 0.0))
		cam.global_position = tank.global_position + Vector3(-6.5, 3.2, -8.5)
		cam.look_at(tank.global_position + Vector3(0, 1.4, 3), Vector3.UP)
		await get_tree().process_frame
		t += get_process_delta_time()
	_combat_tank = tank

var _combat_tank: PlayerTank

func _seg_tank_combat() -> void:
	var tank := _combat_tank
	var pos := tank.global_position
	var e1 := EnemyTank.new(terrain, projectiles, fx, tank)
	add_child(e1)
	e1.global_position = pos + Vector3(22, _gy(pos.x + 22, pos.z - 6) - _gy(pos.x, pos.z), -6)
	var e2 := EnemyTank.new(terrain, projectiles, fx, tank)
	add_child(e2)
	e2.global_position = pos + Vector3(28, _gy(pos.x + 28, pos.z + 10) - _gy(pos.x, pos.z), 10)

	var t := 0.0
	while t < 7.0:
		tank.set_stick_drive(Vector2(0.1 * sin(t), 0.4))
		tank.set_stick_turret(Vector2(0.5, 0.05 * sin(t * 1.3)))
		cam.global_position = tank.global_position + Vector3(-9.0, 4.0, -6.0)
		cam.look_at(tank.global_position + Vector3(10, 1.5, 4), Vector3.UP)
		if fmod(t, 1.6) < get_process_delta_time():
			tank.stick_fire()
		if fmod(t, 2.3) < get_process_delta_time():
			var target := e1 if randi() % 2 == 0 else e2
			fx.explosion(target.global_position + Vector3(0, 1.0, 0), true, cam.global_position)
		await get_tree().process_frame
		t += get_process_delta_time()

	fx.explosion(e1.global_position + Vector3(0, 1.2, 0), true, cam.global_position)
	fx.explosion(e2.global_position + Vector3(0, 1.2, 0), true, cam.global_position)
	for c in [e1, e2]:
		if is_instance_valid(c):
			c.queue_free()

func _seg_plane_flyby() -> void:
	var plane := PlayerPlane.new(terrain, projectiles, fx)
	add_child(plane)
	plane.global_position = Vector3(-70, 34, -60)
	plane.rotation = Vector3(0, deg_to_rad(35), 0)
	plane.stick = Vector2(0.15, -0.05)
	await get_tree().process_frame
	await _chase_hold(plane, Vector3(-10, 2.0, -14), Vector3(0, 0, 0), 5.0)
	plane.queue_free()

func _seg_biplane_flyby() -> void:
	var biplane := PlayerPlane.new(terrain, projectiles, fx)
	biplane.biplane = true
	add_child(biplane)
	biplane.global_position = Vector3(60, 28, -50)
	biplane.rotation = Vector3(0, deg_to_rad(-145), 0)
	biplane.stick = Vector2(-0.12, -0.04)
	await get_tree().process_frame
	await _chase_hold(biplane, Vector3(9, 1.6, -12), Vector3(0, 0, 0), 4.5)
	biplane.queue_free()

func _seg_heli_pass() -> void:
	var heli := PlayerAlt.Heli.new(terrain, projectiles, fx)
	add_child(heli)
	heli.global_position = Vector3(0, _gy(0, 0) + 10.0, -30)
	await get_tree().process_frame
	var t := 0.0
	while t < 4.5:
		heli.set_stick_drive(Vector2(0, 0.65))
		heli.set_stick_turret(Vector2(0.0, 0.35))
		cam.global_position = heli.global_position + Vector3(8.0, 1.0, -11.0)
		cam.look_at(heli.global_position, Vector3.UP)
		await get_tree().process_frame
		t += get_process_delta_time()
	heli.queue_free()

func _seg_boat_cruise() -> void:
	var boat := PlayerBoat.new(terrain, projectiles, fx)
	add_child(boat)
	boat.global_position = Vector3(-150, -2.4, -30)
	boat.rotation.y = deg_to_rad(70)
	await get_tree().process_frame
	var t := 0.0
	while t < 4.5:
		boat.set_stick_drive(Vector2(0.05 * sin(t), 0.85))
		cam.global_position = boat.global_position + Vector3(-9.0, 2.6, -7.5)
		cam.look_at(boat.global_position + Vector3(0, 0.8, 2), Vector3.UP)
		await get_tree().process_frame
		t += get_process_delta_time()
	boat.queue_free()

func _seg_finale() -> void:
	var tank := PlayerTank.new(terrain, projectiles, fx)
	add_child(tank)
	tank.global_position = Vector3(0, _gy(0, 6) + 0.04, 6)
	tank.rotation.y = deg_to_rad(195)
	if tank.reticle:
		tank.reticle.visible = false

	var plane := PlayerPlane.new(terrain, projectiles, fx)
	add_child(plane)
	plane.global_position = Vector3(-18, 15, -10)
	plane.rotation = Vector3(deg_to_rad(-6), deg_to_rad(150), deg_to_rad(8))

	var heli := PlayerAlt.Heli.new(terrain, projectiles, fx)
	add_child(heli)
	heli.global_position = Vector3(13, 9, 20)

	cam.global_position = Vector3(0, 6.2, -20)
	cam.look_at(Vector3(0, 3.5, 9), Vector3.UP)
	await get_tree().process_frame

	fx.explosion(Vector3(4, _gy(4, 6) + 1.0, 6), true, cam.global_position)
	await _hold(0.6)
	fx.explosion(Vector3(-3, _gy(-3, 9) + 1.0, 9), true, cam.global_position)
	await _hold(2.0)
	fx.explosion(Vector3(6, _gy(6, 10) + 1.0, 10), true, cam.global_position)
	await _hold(2.4)

# ---------------------------------------------------------------- outro card
func _seg_outro_card() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var fade := ColorRect.new()
	fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	fade.color = Color(0, 0, 0, 0)
	layer.add_child(fade)

	var t := 0.0
	while t < 1.0:
		fade.color.a = t
		await get_tree().process_frame
		t += get_process_delta_time()
	fade.color.a = 1.0

	var title := Label.new()
	title.text = "TANK COMMANDER VR"
	title.set_anchors_preset(Control.PRESET_CENTER)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 72)
	title.add_theme_color_override("font_color", Color(1, 1, 1))
	title.position = Vector2(-400, -60)
	title.size = Vector2(800, 80)
	layer.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Available now on the Meta Horizon Store"
	subtitle.set_anchors_preset(Control.PRESET_CENTER)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	subtitle.add_theme_font_size_override("font_size", 30)
	subtitle.add_theme_color_override("font_color", Color(0.8, 0.85, 0.8))
	subtitle.position = Vector2(-400, 20)
	subtitle.size = Vector2(800, 50)
	layer.add_child(subtitle)

	await _hold(3.5)

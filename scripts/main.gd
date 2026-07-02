# Entry point: environment/lighting, world build, player, enemies, rig select
# (XR on device, desktop fallback on PC), perf logging, smoke-test mode.
extends Node3D

var terrain: Terrain
var fx: FxPool
var projectiles: Projectiles
var player: PlayerTank
var _perf_t := 0.0
var _smoke_frames := -1

func _ready() -> void:
	_setup_environment()
	terrain = Terrain.new()
	add_child(terrain)
	add_child(WorldDressing.new(terrain))
	fx = FxPool.new()
	add_child(fx)
	projectiles = Projectiles.new(terrain, fx)
	add_child(projectiles)
	player = PlayerTank.new(terrain, projectiles, fx)
	add_child(player)
	add_child(EnemyManager.new(terrain, projectiles, fx, player))
	_setup_rig()
	if "--smoke" in OS.get_cmdline_user_args():
		_smoke_frames = 140
		print("[smoke] starting smoke test")
	if "--shots" in OS.get_cmdline_user_args():
		_run_shot_sequence()

func _setup_environment() -> void:
	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.28, 0.42, 0.66)
	sky_mat.sky_horizon_color = Color(0.78, 0.72, 0.62)
	sky_mat.ground_bottom_color = Color(0.32, 0.28, 0.22)
	sky_mat.ground_horizon_color = Color(0.72, 0.66, 0.56)
	sky_mat.sun_angle_max = 22.0
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_sky_contribution = 1.0
	env.ambient_light_energy = 1.15
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.0
	env.fog_enabled = true
	env.fog_light_color = Color(0.75, 0.72, 0.66)
	env.fog_density = 0.0016
	env.fog_sky_affect = 0.25
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	# warm late-afternoon sun — NO shadow maps (Quest budget, KB recipe)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-38), deg_to_rad(48), 0)
	sun.light_color = Color(1.0, 0.93, 0.80)
	sun.light_energy = 1.25
	sun.shadow_enabled = false
	add_child(sun)

func _setup_rig() -> void:
	var xr := XRServer.find_interface("OpenXR")
	if xr and xr.is_initialized():
		get_viewport().use_xr = true
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		var rig := XRRig.new(player)
		projectiles.cam = rig.camera
		print("[main] XR active")
	else:
		var rig := DesktopRig.new(player)
		projectiles.cam = rig.camera
		print("[main] desktop fallback rig")

func _process(delta: float) -> void:
	_perf_t += delta
	if _perf_t > 2.0:
		_perf_t = 0.0
		var draws := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
		var prims := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
		print("[perf] fps=%d draws=%d prims=%dk proc=%.1fms" % [
			Engine.get_frames_per_second(), draws, prims / 1000,
			Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0])
	if _smoke_frames > 0:
		_smoke_frames -= 1
		if _smoke_frames == 100:
			# exercise systems during the smoke run
			player.quick_start()
		if _smoke_frames == 60:
			player.set_stick_drive(Vector2(0.2, 1.0))
			player.set_stick_turret(Vector2(0.5, 0.2))
		if _smoke_frames == 30:
			player.stick_fire()
			player.stick_rockets()
		if _smoke_frames == 0:
			print("[smoke] OK — frames ran clean")
			get_tree().quit(0)

# Automated visual-verification sequence (desktop): drives the tank, moves the
# camera, saves numbered screenshots to out/, then quits.
func _run_shot_sequence() -> void:
	var seq := func() -> void:
		await get_tree().create_timer(1.0).timeout
		player.quick_start()
		var cam: Camera3D = projectiles.cam
		await get_tree().create_timer(2.5).timeout
		_shot(cam, "01_cockpit_front")
		# look right toward breech
		cam.rotation = Vector3(-0.05, -1.0, 0)
		await get_tree().create_timer(0.4).timeout
		_shot(cam, "02_cockpit_breech")
		# look left at rocket console
		cam.rotation = Vector3(-0.35, 0.9, 0)
		await get_tree().create_timer(0.4).timeout
		_shot(cam, "03_cockpit_console")
		cam.rotation = Vector3.ZERO
		player.set_stick_drive(Vector2(0.15, 1.0))
		await get_tree().create_timer(3.0).timeout
		_shot(cam, "04_driving")
		player.set_stick_turret(Vector2(0.6, 0.1))
		await get_tree().create_timer(2.0).timeout
		player.set_stick_turret(Vector2.ZERO)
		player.stick_fire()
		await get_tree().create_timer(0.35).timeout
		_shot(cam, "05_firing")
		# exterior beauty shot
		player.set_stick_drive(Vector2.ZERO)
		cam.top_level = true
		var p := player.global_position
		cam.global_position = p + Vector3(-7.0, 4.5, -9.0)
		cam.look_at(p + Vector3(0, 1.5, 0))
		await get_tree().create_timer(0.4).timeout
		_shot(cam, "06_exterior")
		cam.global_position = p + Vector3(10.0, 2.5, 6.0)
		cam.look_at(p + Vector3(0, 1.8, 0))
		await get_tree().create_timer(0.4).timeout
		_shot(cam, "07_exterior_front")
		print("[shots] done")
		get_tree().quit(0)
	seq.call()

func _shot(_cam: Camera3D, tag: String) -> void:
	var img := get_viewport().get_texture().get_image()
	var dir := "res://out"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var path := ProjectSettings.globalize_path(dir + "/" + tag + ".png")
	img.save_png(path)
	print("[shots] saved ", path)

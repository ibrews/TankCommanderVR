# Entry point v2: menu hangar <-> game world lifecycle, rig management,
# solo / co-op / versus / plane modes, perf logging, smoke/shots test modes.
extends Node3D

var terrain: Terrain
var fx: FxPool
var projectiles: Projectiles
var player: PlayerTank
var plane: PlayerPlane
var rig: Node3D           # XRRig or DesktopRig
var world: Node3D         # container for the current level
var hangar: Node3D
var menu: MainMenu
var sun: DirectionalLight3D
var env: Environment

var _perf_t := 0.0
var _smoke_frames := -1

func _ready() -> void:
	add_to_group("main")
	_setup_environment()
	_setup_rig()
	to_menu()
	var args := OS.get_cmdline_user_args()
	if "--smoke" in args:
		_smoke_frames = 200
		print("[smoke] starting smoke test")
	if "--shots" in args:
		_run_shot_sequence()
	if "--mp-host" in args:
		Game.mode = Game.Mode.COOP
		Game.level_id = "outdoor"
		NetManager.host()
		start_game()
		get_tree().create_timer(18.0).timeout.connect(func():
			print("[mp-test] host peers=", multiplayer.get_peers().size())
			get_tree().quit(0))
	if "--mp-join" in args:
		NetManager.join_found.connect(func(cfg):
			Game.mode = cfg.mode
			Game.level_id = cfg.level
			Game.difficulty = cfg.diff
			start_game()
			print("[mp-test] client joined, level=", cfg.level), CONNECT_ONE_SHOT)
		NetManager.search()
		get_tree().create_timer(22.0).timeout.connect(func():
			print("[mp-test] client done, connected=", multiplayer.multiplayer_peer != null and multiplayer.get_peers().size() > 0)
			get_tree().quit(0))

# ---------------------------------------------------------------- environment
func _setup_environment() -> void:
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
	env.ambient_light_energy = 0.85
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.78, 0.72, 0.62)
	env.fog_density = 0.0005
	env.fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-38), deg_to_rad(48), 0)
	sun.light_color = Color(1.0, 0.93, 0.80)
	sun.light_energy = 1.25
	sun.shadow_enabled = false
	sun.light_cull_mask = 0xFFFFF & ~2
	add_child(sun)

func _apply_ambience(menu_mode: bool) -> void:
	if menu_mode:
		env.ambient_light_energy = 0.35
		env.fog_enabled = false
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(0.02, 0.025, 0.03)
		sun.light_energy = 0.0
	else:
		env.ambient_light_energy = 0.85
		env.fog_enabled = true
		env.background_mode = Environment.BG_SKY
		sun.light_energy = Levels.current.get("sun_energy", 1.25)

# ---------------------------------------------------------------- rig
func _setup_rig() -> void:
	var xr := XRServer.find_interface("OpenXR")
	if xr and xr.is_initialized():
		get_viewport().use_xr = true
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		rig = XRRig.new()
		print("[main] XR active")
	else:
		rig = DesktopRig.new()
		print("[main] desktop fallback rig")
	add_child(rig)

# ---------------------------------------------------------------- menu state
func to_menu() -> void:
	Game.state = Game.GState.MENU
	NetManager.leave()
	_clear_world()
	_apply_ambience(true)
	hangar = Node3D.new()
	add_child(hangar)
	# floor disc + overhead lamp pool
	var floor_mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 9.0
	cm.bottom_radius = 9.0
	cm.height = 0.1
	cm.radial_segments = 24
	floor_mi.mesh = cm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.12, 0.13, 0.13)
	fm.roughness = 0.8
	floor_mi.mesh.material = fm
	floor_mi.position.y = -0.05
	hangar.add_child(floor_mi)
	var lamp := SpotLight3D.new()
	lamp.position = Vector3(0, 6, 0)
	lamp.rotation.x = -PI / 2
	lamp.spot_range = 12.0
	lamp.spot_angle = 50.0
	lamp.light_energy = 3.0
	lamp.shadow_enabled = false
	hangar.add_child(lamp)
	# display tank (decorative)
	EnemyTank._build_meshes()
	var disp := Node3D.new()
	disp.position = Vector3(2.8, 0, -3.4)
	disp.rotation.y = deg_to_rad(35)
	var hull := MeshInstance3D.new()
	hull.mesh = EnemyTank._hull_mesh
	disp.add_child(hull)
	var tur := MeshInstance3D.new()
	tur.mesh = EnemyTank._turret_mesh
	tur.position = Vector3(0, 1.45, -0.2)
	disp.add_child(tur)
	hangar.add_child(disp)
	# the menu board
	menu = MainMenu.new()
	menu.position = Vector3(0, 1.5, -1.9)
	hangar.add_child(menu)
	menu.start_requested.connect(_on_start_requested)
	menu.join_requested.connect(_on_join_requested)
	rig.call("to_menu_anchor", hangar)

func _on_start_requested(mode: int, level_id: String, diff: int) -> void:
	Game.mode = mode
	Game.level_id = level_id
	Game.difficulty = diff
	match mode:
		Game.Mode.COOP, Game.Mode.VERSUS:
			NetManager.host()
		_:
			pass
	start_game()

func _on_join_requested() -> void:
	menu.call("_text", "Searching for a host on this Wi-Fi...", Vector2(0, -0.75), 14)
	NetManager.join_found.connect(func(cfg):
		Game.mode = cfg.mode
		Game.level_id = cfg.level
		Game.difficulty = cfg.diff
		start_game(), CONNECT_ONE_SHOT)
	NetManager.search()

# ---------------------------------------------------------------- game state
func start_game() -> void:
	if hangar:
		hangar.queue_free()
		hangar = null
		menu = null
	_clear_world()
	Game.restart()
	Game.state = Game.GState.PLAYING
	Levels.current = Levels.get_config(Game.level_id)
	_apply_ambience(false)
	world = Node3D.new()
	add_child(world)
	terrain = Terrain.new(Levels.current)
	world.add_child(terrain)
	world.add_child(WorldDressing.new(terrain))
	fx = FxPool.new()
	world.add_child(fx)
	projectiles = Projectiles.new(terrain, fx)
	world.add_child(projectiles)
	NetManager.projectiles = projectiles
	NetManager.fx = fx
	if Game.mode == Game.Mode.PLANE:
		plane = PlayerPlane.new(terrain, projectiles, fx)
		world.add_child(plane)
		projectiles.cam = rig.get("camera")
		world.add_child(EnemyManager.new(terrain, projectiles, fx, plane))
		rig.call("attach_to_vehicle", plane)
	else:
		player = PlayerTank.new(terrain, projectiles, fx)
		world.add_child(player)
		projectiles.cam = rig.get("camera")
		if Game.mode == Game.Mode.COOP and NetManager.is_client():
			world.add_child(NetManager.make_replica_pool(terrain))
		else:
			world.add_child(EnemyManager.new(terrain, projectiles, fx, player))
		if Game.mode == Game.Mode.VERSUS:
			NetManager.setup_versus(world, terrain, projectiles, fx, player)
		elif Game.mode == Game.Mode.COOP:
			NetManager.setup_coop(player)
		rig.call("attach_to_vehicle", player)
	Sfx.music_game()

func _clear_world() -> void:
	if world:
		world.queue_free()
		world = null
	player = null
	plane = null

# ---------------------------------------------------------------- perf + test modes
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
		if _smoke_frames == 180:
			# drive the menu programmatically
			var m := Game.Mode.PLANE if "--plane" in OS.get_cmdline_user_args() else Game.Mode.SOLO
			if menu:
				menu.start_requested.emit(m, "castle", 1)
		var v: Node3D = player if player else plane
		if _smoke_frames == 120 and v:
			v.call("quick_start")
		if _smoke_frames == 80 and v:
			v.call("set_stick_drive", Vector2(0.2, 1.0))
			v.call("set_stick_turret", Vector2(0.5, 0.2))
		if _smoke_frames == 40 and v:
			v.call("stick_fire")
			v.call("stick_rockets")
			v.call("set_mg", true)
		if _smoke_frames == 30 and v:
			v.call("set_mg", false)
		if _smoke_frames == 0:
			print("[smoke] OK — frames ran clean")
			get_tree().quit(0)

# Automated visual-verification sequence (desktop).
func _run_shot_sequence() -> void:
	var seq := func() -> void:
		await get_tree().create_timer(1.0).timeout
		var cam: Camera3D = rig.get("camera")
		_shot(cam, "00_menu")
		if menu:
			menu.start_requested.emit(Game.Mode.SOLO, OS.get_environment("SHOT_LEVEL") if OS.get_environment("SHOT_LEVEL") != "" else "outdoor", 1)
		await get_tree().create_timer(1.5).timeout
		player.quick_start()
		await get_tree().create_timer(2.5).timeout
		_shot(cam, "01_cockpit_front")
		cam.rotation = Vector3(-0.05, -1.0, 0)
		await get_tree().create_timer(0.4).timeout
		_shot(cam, "02_cockpit_breech")
		cam.rotation = Vector3(-0.35, 0.9, 0)
		await get_tree().create_timer(0.4).timeout
		_shot(cam, "03_cockpit_console")
		cam.rotation = Vector3(-0.5, 0.0, 0)
		await get_tree().create_timer(0.4).timeout
		_shot(cam, "03b_panel")
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
		cam.top_level = true
		var p := player.global_position
		print("[shots] tank pos A: ", p)
		cam.global_position = p + Vector3(-7.0, 4.5, -9.0)
		cam.look_at(p + Vector3(0, 1.5, 0))
		await get_tree().create_timer(0.4).timeout
		_shot(cam, "06_exterior")
		cam.global_position = player.global_position + Vector3(10.0, 2.5, 6.0)
		cam.look_at(player.global_position + Vector3(0, 1.8, 0))
		await get_tree().create_timer(0.4).timeout
		_shot(cam, "07_exterior_front")
		await get_tree().create_timer(1.5).timeout
		print("[shots] tank pos B: ", player.global_position)
		player.set_stick_drive(Vector2.ZERO)
		cam.far = 4000.0
		cam.global_position = Vector3(0, 420, 1)
		cam.look_at(Vector3(0, 0, 0))
		await get_tree().create_timer(0.4).timeout
		_shot(cam, "08_map_topdown")
		cam.global_position = Vector3(0, 25, 40)
		cam.look_at(Vector3(0, 45, -240))
		await get_tree().create_timer(0.4).timeout
		_shot(cam, "09_rim_profile")
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

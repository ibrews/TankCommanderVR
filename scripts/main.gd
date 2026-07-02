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
var fill: DirectionalLight3D
var env: Environment
var _sky_mat: ProceduralSkyMaterial
var _demo := false
var _demo_t := 0.0

var _perf_t := 0.0
var _smoke_frames := -1

func _ready() -> void:
	add_to_group("main")
	_setup_environment()
	_setup_rig()
	to_menu()
	_check_autostart()
	var args := OS.get_cmdline_user_args()
	if "--smoke" in args:
		_smoke_frames = 200
		print("[smoke] starting smoke test")
	if "--shots" in args:
		_run_shot_sequence()
	if "--disaster" in args:
		get_tree().create_timer(9.0).timeout.connect(func():
			var w: Weather = get_tree().get_first_node_in_group("weather")
			if w:
				w.start_disaster(["tornado", "volcano", "hurricane"][Game.rng.randi() % 3]))
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
	_sky_mat = ProceduralSkyMaterial.new()
	var sky_mat := _sky_mat
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
	# fake GI: a dim upward "bounce" fill from the opposite azimuth
	fill = DirectionalLight3D.new()
	fill.rotation = Vector3(deg_to_rad(-12), deg_to_rad(48 + 180), 0)
	fill.light_color = Color(0.85, 0.75, 0.6)
	fill.light_energy = 0.22
	fill.shadow_enabled = false
	fill.light_cull_mask = 0xFFFFF & ~2
	add_child(fill)
	# glow: mobile renderer supports it in 4.x — emissives (lava, tracers,
	# gauges, muzzle flashes) bloom. Tunable off via tuning.cfg.
	env.glow_enabled = Tune.v("glow_enabled") > 0.5
	env.glow_intensity = Tune.v("glow_intensity")
	env.glow_bloom = 0.06
	env.glow_hdr_threshold = 1.08
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE

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
		sun.light_color = Color(1.0, 0.93, 0.80)
		env.fog_light_color = Color(0.78, 0.72, 0.62)
		env.fog_density = 0.0005
		_sky_mat.sky_top_color = Color(0.28, 0.42, 0.66)
		_sky_mat.sky_horizon_color = Color(0.66, 0.60, 0.50)
		sun.rotation = Vector3(deg_to_rad(-38), deg_to_rad(48), 0)
		if fill:
			fill.light_energy = 0.22
			fill.light_color = Color(0.85, 0.75, 0.6)
		if Game.time_of_day == 1:
			# GOLDEN HOUR: low warm sun, long light, pink horizon
			sun.rotation = Vector3(deg_to_rad(-9), deg_to_rad(96), 0)
			sun.light_energy = 1.15
			sun.light_color = Color(1.0, 0.62, 0.32)
			env.ambient_light_energy = 0.62
			env.fog_light_color = Color(0.9, 0.6, 0.42)
			env.fog_density = 0.0009
			_sky_mat.sky_top_color = Color(0.30, 0.32, 0.55)
			_sky_mat.sky_horizon_color = Color(0.98, 0.55, 0.32)
			if fill:
				fill.light_energy = 0.3
				fill.light_color = Color(0.55, 0.45, 0.65)  # cool sky bounce
		elif Game.time_night:
			# moonlight: dark enough that headlights matter
			sun.light_energy = 0.09
			sun.light_color = Color(0.65, 0.72, 1.0)
			env.ambient_light_energy = 0.10
			env.fog_light_color = Color(0.05, 0.06, 0.10)
			_sky_mat.sky_top_color = Color(0.01, 0.015, 0.05)
			_sky_mat.sky_horizon_color = Color(0.04, 0.05, 0.10)
			if fill:
				fill.light_energy = 0.05
				fill.light_color = Color(0.3, 0.4, 0.7)
		if Game.mutator == "underwater":
			env.fog_light_color = Color(0.15, 0.4, 0.45)
			env.fog_density = 0.012
			env.ambient_light_energy = 0.55
			sun.light_energy *= 0.6
	_set_underwater_audio(Game.mutator == "underwater" and not menu_mode)

var _lp_effect_on := false
func _set_underwater_audio(on: bool) -> void:
	if on == _lp_effect_on:
		return
	_lp_effect_on = on
	if on:
		var lp := AudioEffectLowPassFilter.new()
		lp.cutoff_hz = 850.0
		AudioServer.add_bus_effect(0, lp)
	else:
		for i in range(AudioServer.get_bus_effect_count(0) - 1, -1, -1):
			if AudioServer.get_bus_effect(0, i) is AudioEffectLowPassFilter:
				AudioServer.remove_bus_effect(0, i)

# ---------------------------------------------------------------- rig
func _setup_rig() -> void:
	var xr := XRServer.find_interface("OpenXR")
	if xr and xr.is_initialized():
		get_viewport().use_xr = true
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		if "foveation_level" in xr:
			xr.foveation_level = int(Tune.v("foveation_level"))
			print("[main] foveation_level=", xr.foveation_level)
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

func _on_start_requested(mode: int, level_id: String, diff: int, mutator := "") -> void:
	Game.mode = mode
	Game.endless = level_id == "endless"
	if Game.endless:
		level_id = Levels.ORDER[Game.rng.randi() % Levels.ORDER.size()]
		if mode == Game.Mode.COOP or mode == Game.Mode.VERSUS:
			Game.endless = false   # multiplayer shares one concrete level
	Game.level_id = level_id
	Game.difficulty = diff
	Game.mutator = mutator
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

# endless mode: after a few cleared waves, pack up and fight somewhere new.
# Score/hp/wave ride along via Game.travel_carry (consumed in Game.restart).
func endless_travel() -> void:
	var choices := Levels.ORDER.filter(func(id: String) -> bool: return id != Game.level_id)
	Game.level_id = choices[Game.rng.randi() % choices.size()]
	Game.time_of_day = Game.rng.randi() % 3
	Game.travel_carry = {"score": Game.score, "hp": Game.hp, "wave": Game.wave}
	Sfx.vo("vo_travel", 3, 1.0)
	start_game()
	# arriving mid-tour: engine already hot, no start-ritual tutorial again
	var v: Node3D = player if is_instance_valid(player) else (plane if is_instance_valid(plane) else null)
	if v and v.has_method("quick_start"):
		v.call("quick_start")
		v.set("_hint_stage", 8)

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
	var veh := Game.vehicle
	if Game.mode == Game.Mode.COOP or Game.mode == Game.Mode.VERSUS:
		veh = "tank"   # multiplayer is tank business
	if Game.mode == Game.Mode.PLANE:
		veh = "plane"  # legacy path
	var vehicle: CharacterBody3D
	match veh:
		"plane", "biplane":
			plane = PlayerPlane.new(terrain, projectiles, fx)
			plane.biplane = veh == "biplane"
			vehicle = plane
		"heli":
			vehicle = PlayerAlt.Heli.new(terrain, projectiles, fx)
		"runner":
			vehicle = PlayerAlt.Runner.new(terrain, projectiles, fx)
			vehicle.set("_rig", rig)
		"boat":
			vehicle = PlayerBoat.new(terrain, projectiles, fx)
		_:
			player = PlayerTank.new(terrain, projectiles, fx)
			vehicle = player
	world.add_child(vehicle)
	projectiles.cam = rig.get("camera")
	if Game.mode == Game.Mode.COOP and NetManager.is_client():
		world.add_child(NetManager.make_replica_pool(terrain))
	else:
		world.add_child(EnemyManager.new(terrain, projectiles, fx, vehicle))
	if Game.mode == Game.Mode.VERSUS:
		NetManager.setup_versus(world, terrain, projectiles, fx, player)
	elif Game.mode == Game.Mode.COOP:
		NetManager.setup_coop(player)
	rig.call("attach_to_vehicle", vehicle)
	# the supporting cast
	Npc.CabbageMan.spawn(world, terrain, vehicle)
	if Levels.current.get("trees", 0) >= 100:
		Npc.Creeper.maybe_spawn(world, terrain, vehicle)
	if Levels.current.get("baby", false):
		Npc.GiantBaby.spawn(world, terrain, vehicle)
	if Levels.current.has("ambient_loop"):
		var amb := AudioStreamPlayer.new()
		amb.stream = Sfx.streams.get(Levels.current["ambient_loop"])
		amb.volume_db = -14.0
		amb.autoplay = true
		world.add_child(amb)
	# weather + sky events follow whichever vehicle we're in
	world.add_child(Weather.new(terrain, fx, vehicle, env, sun))
	if Game.mutator == "underwater":
		var bub := AudioStreamPlayer.new()
		bub.stream = Sfx.streams.get("bubbles_loop")
		bub.volume_db = -14.0
		bub.autoplay = true
		world.add_child(bub)
	Sfx.music_game()
	get_tree().create_timer(2.5).timeout.connect(_start_vo)

func _start_vo() -> void:
	if Game.state != Game.GState.PLAYING:
		return
	var lv := {"gym": "vo_gym", "beach": "vo_beach", "island": "vo_island",
		"volcano": "vo_volcano", "babyroom": "vo_babyroom"}
	if lv.has(Game.level_id):
		Sfx.vo(lv[Game.level_id], 2, 60.0)
	if Game.time_night:
		Sfx.vo("vo_night", 2, 60.0)
	var mv := {"lowg": "vo_lowg", "underwater": "vo_underwater",
		"balloon": "vo_balloon", "paintball": "vo_paintball"}
	if mv.has(Game.mutator):
		Sfx.vo(mv[Game.mutator], 1, 60.0)

func _clear_world() -> void:
	if world:
		world.queue_free()
		world = null
	player = null
	plane = null

# ---------------------------------------------------------------- autostart (device profiling)
# adb push a config to the app's files dir and the game boots straight into
# a self-playing scene — no one needs to wear the headset:
#   [auto]
#   level="beach"  vehicle="tank"  mutator=""  time=1  demo=true  delay=6.0
const EXT_FILES := "/sdcard/Android/data/com.agilelens.tankcommander/files"

func _check_autostart() -> void:
	var cfg := ConfigFile.new()
	# user:// is internal on Android; also check the adb-pushable external dir
	if cfg.load("user://autostart.cfg") != OK and cfg.load(EXT_FILES + "/autostart.cfg") != OK:
		return
	var level: String = cfg.get_value("auto", "level", "beach")
	var delay: float = cfg.get_value("auto", "delay", 6.0)
	print("[auto] autostart: ", level, " in ", delay, "s")
	get_tree().create_timer(delay).timeout.connect(func():
		Game.mode = Game.Mode.SOLO
		Game.level_id = level
		Game.difficulty = int(cfg.get_value("auto", "difficulty", 1))
		Game.mutator = str(cfg.get_value("auto", "mutator", ""))
		Game.vehicle = str(cfg.get_value("auto", "vehicle", "tank"))
		Game.time_of_day = int(cfg.get_value("auto", "time", 0))
		_demo = bool(cfg.get_value("auto", "demo", true))
		start_game())

func _demo_tick(delta: float) -> void:
	if not _demo or Game.state != Game.GState.PLAYING or player == null:
		return
	_demo_t += delta
	if _demo_t < 4.0:
		player.quick_start()
	player.set_stick_drive(Vector2(0.3 * sin(_demo_t * 0.13), 0.85))
	player.set_stick_turret(Vector2(0.5 * sin(_demo_t * 0.3), 0.1 * sin(_demo_t * 0.17)))
	if fmod(_demo_t, 7.0) < delta:
		player.stick_fire()
	if fmod(_demo_t, 19.0) < delta:
		player.stick_rockets()

# ---------------------------------------------------------------- perf + test modes
func _process(delta: float) -> void:
	_demo_tick(delta)
	# lava is not a swimming pool
	if Game.state == Game.GState.PLAYING and Levels.current.has("lava_y"):
		var veh: Node3D = plane if plane else (player if player else null)
		if veh == null:
			for n in get_tree().get_nodes_in_group("player"):
				veh = n
				break
		if veh and veh.global_position.y < float(Levels.current["lava_y"]) and Game.alive:
			if veh.has_method("take_damage"):
				veh.take_damage(30.0 * delta, veh.global_position)
			if Game.rng.randf() < delta * 3.0 and fx:
				fx.muzzle_flash(veh.global_position + Vector3(0, 1, 0), 1.2)
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
			if OS.get_environment("SHOT_VEH") != "":
				Game.vehicle = OS.get_environment("SHOT_VEH")
			if menu:
				menu.start_requested.emit(m, OS.get_environment("SHOT_LEVEL") if OS.get_environment("SHOT_LEVEL") != "" else "castle", 1, OS.get_environment("SHOT_MUT"))
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
		if _smoke_frames == 25 and Game.endless:
			print("[smoke] endless travel test: ", Game.level_id, " ->")
			endless_travel()
			print("[smoke] arrived: ", Game.level_id, " wave=", Game.wave, " score=", Game.score)
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
			if OS.get_environment("SHOT_TIME") != "":
				Game.time_of_day = int(OS.get_environment("SHOT_TIME"))
			menu.start_requested.emit(Game.Mode.SOLO,
				OS.get_environment("SHOT_LEVEL") if OS.get_environment("SHOT_LEVEL") != "" else "outdoor",
				1, OS.get_environment("SHOT_MUT"))
		await get_tree().create_timer(1.5).timeout
		player.quick_start()
		# forensics: baked chunk heights vs analytic, and the sea's world y
		var gp := player.global_position
		print("[shots] h(tank)=%.2f tank_y=%.2f" % [terrain.height(gp.x, gp.z), gp.y])
		for c in terrain.get_children():
			if c is MeshInstance3D:
				print("[shots] chunk0 aabb=", c.mesh.get_aabb(), " node_y=", c.global_position.y)
				break
		var sea := world.find_child("Sea", true, false)
		if sea:
			print("[shots] sea y=", sea.global_position.y, " aabb=", sea.mesh.get_aabb())
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

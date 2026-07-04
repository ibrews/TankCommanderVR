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
var current_vehicle: Node3D  # the tank/plane/boat/heli for this mission, if any — null for "runner"
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

# Local player's own body (Alex: "make sure I have a full avatar" — until now
# AvatarRig only ever got attached to REMOTE crew/NPCs, net.gd's own
# update_live() call sites, never to the local player themselves). One
# instance survives the seated<->on-foot transition, same idiom as
# net.gd's _crew_avatar / AvatarRig.configure()'s own doc comment.
var _local_avatar: AvatarRig = null
var _pause_menu: PauseMenu = null

func _ready() -> void:
	add_to_group("main")
	_setup_environment()
	_setup_rig()
	to_menu()
	_check_autostart()
	# Solo playtesting has nobody watching — these are what let a future
	# session see what actually happened without live narration. See
	# event_log.gd for why this is a local user://events.jsonl file (pulled
	# via adb/HzOSDevMCP) and not a network upload.
	Game.game_over.connect(func(): EventLog.log_event("game_over", {"score": Game.score, "wave": Game.wave}))
	Game.wave_changed.connect(func(w): EventLog.log_event("wave_start", {"wave": w}))
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
	if "--rain" in args:
		# Deterministic real-weather screenshot capture — the rain/lightning
		# system (weather.gd's SkyState machine) otherwise only fires on a
		# random ~22% timer check, so docs/screenshots/ never actually got a
		# real rain shot (the existing "disaster_" prefix is the separate
		# tornado/volcano/hurricane easter egg, not this). Self-contained:
		# starts a level directly (same fields autostart.cfg sets), drives,
		# forces the storm, waits out its ~12s BUILDING phase, screenshots.
		get_tree().create_timer(1.0).timeout.connect(func():
			Game.mode = Game.Mode.SOLO
			Game.level_id = "beach"
			Game.difficulty = 1
			Game.mutator = ""
			Game.vehicle = "tank"
			Game.time_of_day = 0
			start_game()
			get_tree().create_timer(2.0).timeout.connect(func():
				if player:
					player.quick_start()
					player.set_stick_drive(Vector2(0.2, 1.0))
				var w: Weather = get_tree().get_first_node_in_group("weather")
				if w:
					w.force_storm(1.0, 60.0)
				get_tree().create_timer(13.0).timeout.connect(func():
					var cam: Camera3D = rig.get("camera")
					cam.top_level = true
					var p: Vector3 = player.global_position
					cam.global_position = p + Vector3(-7.0, 4.5, -9.0)
					cam.look_at(p + Vector3(0, 1.5, 0))
					_shot(cam, "rain_storm")
					get_tree().quit(0))))
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
	# --rain (screenshot verification, see the --rain block in _ready())
	# always wants the plain desktop camera, matching every other SHOT_*/
	# --shots capture — a Meta XR Simulator or Quest Link runtime merely
	# being *installed and running* on the dev machine is enough for
	# is_initialized() to report true even with no headset attached, which
	# would otherwise silently switch this capture to XRRig's stereo camera.
	if "--rain" in OS.get_cmdline_user_args():
		rig = DesktopRig.new()
		print("[main] desktop fallback rig (forced by --rain)")
		add_child(rig)
		return
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
	# Must keep evaluating input (laser pointer on the pause panel, the
	# menu-button toggle itself) while get_tree().paused freezes everything
	# else — see _on_pause_changed()/Game.toggle_pause().
	rig.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(rig)
	Game.pause_changed.connect(_on_pause_changed)

# ---------------------------------------------------------------- pause
# Head-locked pause panel, shown/hidden on Game.pause_changed (menu button
# mid-mission — see Game.toggle_pause()). Parented to the camera so it's
# wherever you're looking; camera exists under both XRRig and DesktopRig.
func _on_pause_changed(is_paused: bool) -> void:
	if is_paused:
		if _pause_menu == null or not is_instance_valid(_pause_menu):
			_pause_menu = PauseMenu.new()
			_pause_menu.resume_requested.connect(func(): Game.set_paused(false))
			_pause_menu.quit_requested.connect(func(): Game.set_paused(false); call_deferred("to_menu"))
		var cam: Node3D = rig.get("camera")
		if cam:
			if _pause_menu.get_parent() != cam:
				if _pause_menu.get_parent():
					_pause_menu.get_parent().remove_child(_pause_menu)
				cam.add_child(_pause_menu)
			_pause_menu.transform = Transform3D(Basis(), Vector3(0, 0, -1.1))
	elif _pause_menu and is_instance_valid(_pause_menu):
		_pause_menu.queue_free()
		_pause_menu = null

# ---------------------------------------------------------------- menu state
func to_menu() -> void:
	# Defensive: quitting to the hangar from a paused mission must not leave
	# the hangar itself frozen — toggle_pause()/set_paused() both no-op once
	# Game.state flips below, so clear these directly instead.
	Game.paused = false
	get_tree().paused = false
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
	EventLog.log_event("level_start", {"mode": Game.mode, "level": Game.level_id,
		"vehicle": Game.vehicle, "diff": Game.difficulty, "mutator": Game.mutator})
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
	# Sphere-world bonus level: the whole point is walking around the
	# floating planet, so solo XR players go on-foot regardless of vehicle
	# selection (multiplayer/desktop keep their vehicle — the moon hangs
	# overhead as scenery for them; DesktopRig has no on-foot equivalent).
	if Levels.current.has("sphere_world") and Game.mode == Game.Mode.SOLO and rig is XRRig:
		veh = "runner"
	var vehicle: CharacterBody3D
	var on_foot := false
	match veh:
		"plane", "biplane":
			plane = PlayerPlane.new(terrain, projectiles, fx)
			plane.biplane = veh == "biplane"
			vehicle = plane
		"heli":
			vehicle = PlayerAlt.Heli.new(terrain, projectiles, fx)
		"runner":
			if rig is XRRig:
				on_foot = true
				vehicle = OnFootBody.new(terrain, projectiles, fx)
				rig.call("set_on_foot_body", vehicle)
			else:
				# on-foot mode needs a real XROrigin3D (XRToolsPlayerBody's
				# hard requirement) — DesktopRig has no equivalent, so fall
				# back to the tank instead of calling a method it lacks.
				push_warning("[main] \"runner\" selected without an active XR rig — falling back to tank")
				player = PlayerTank.new(terrain, projectiles, fx)
				vehicle = player
		"boat":
			vehicle = PlayerBoat.new(terrain, projectiles, fx)
		_:
			player = PlayerTank.new(terrain, projectiles, fx)
			vehicle = player
	if on_foot:
		var dismount := Transform3D()
		dismount.origin = Vector3(Terrain.SPAWN_CENTER.x, 0, Terrain.SPAWN_CENTER.y)
		dismount.origin.y = terrain.height(dismount.origin.x, dismount.origin.z) + 0.1
		if Levels.current.has("sphere_world"):
			# start standing on top of the planet, not on the plain below
			var sw: Dictionary = Levels.current["sphere_world"]
			dismount.origin = Vector3(Terrain.SPAWN_CENTER.x, float(sw["height"]) + float(sw["radius"]) + 0.3, Terrain.SPAWN_CENTER.y)
		rig.call("enter_on_foot", world, dismount)
	else:
		world.add_child(vehicle)
		current_vehicle = vehicle
	projectiles.cam = rig.get("camera")
	var enemy_manager: EnemyManager = null
	if Game.mode == Game.Mode.COOP and NetManager.is_client():
		world.add_child(NetManager.make_replica_pool(terrain))
	elif not Levels.current.get("no_waves", false):
		enemy_manager = EnemyManager.new(terrain, projectiles, fx, vehicle)
		world.add_child(enemy_manager)
	if Game.mode == Game.Mode.VERSUS:
		NetManager.setup_versus(world, terrain, projectiles, fx, player)
	elif Game.mode == Game.Mode.COOP:
		NetManager.setup_coop(player)
	if not on_foot:
		rig.call("attach_to_vehicle", vehicle)
		_auto_start_if_third_person(vehicle)
	_spawn_on_foot_pickables()
	if Levels.current.has("sphere_world"):
		_build_sphere_world(Levels.current["sphere_world"])
	if Levels.current.get("debug_kitchen_sink", false) and enemy_manager:
		_spawn_debug_kitchen_sink(enemy_manager, vehicle)
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

# ---------------------------------------------------------------- on-foot exit/re-entry
# Mid-mission hatch-lever flow: the vehicle keeps running (nothing in
# PlayerTank/Heli/Boat/OnFootBody's own _physics_process gates on rig
# attachment) — enemies can still shoot it, no AI-driver feature, explicitly
# out of scope. Only meaningful under a real XRRig (on-foot mode needs an
# XROrigin3D ancestor for XRToolsPlayerBody); DesktopRig has no equivalent.
# Scatter the three item-gated on-foot abilities near spawn so they're
# discoverable whether the player starts as "runner" or exits a vehicle
# mid-mission. Placement is deliberately simple (fixed offsets from spawn,
# not a per-level design pass) — the plan doesn't specify level integration
# beyond "pick up each of the three pickables and confirm the gated ability".
func _spawn_on_foot_pickables() -> void:
	var offsets := [
		["grapple_hook", Vector2(6.0, 4.0)],
		["climbing_gloves", Vector2(-6.0, 4.0)],
		["energy_drink", Vector2(0.0, 8.0)],
		["pistol", Vector2(4.0, -4.0)],
		["cabbage_grenade", Vector2(-4.0, -4.0)],
	]
	for entry in offsets:
		var pos: Vector2 = Terrain.SPAWN_CENTER + (entry[1] as Vector2)
		var prop: RigidBody3D
		match entry[0]:
			"grapple_hook":
				prop = GrappleHookPickable.new()
			"climbing_gloves":
				prop = ClimbingGlovesPickable.new()
			"pistol":
				prop = PistolPickable.new()
			"cabbage_grenade":
				prop = CabbageGrenadePickable.new()
			_:
				prop = EnergyDrinkPickable.new()
		world.add_child(prop)
		prop.global_position = Vector3(pos.x, terrain.height(pos.x, pos.y) + 0.15, pos.y)

# "DEBUG: KITCHEN SINK" level (Levels.CONFIGS["debug"]) — one of every enemy
# type at close range, all immediately within detect_range_day (150m) so
# they engage right away, for smoke-testing that every 3D model/AI/vehicle
# type still works after a change without waiting through wave escalation
# or traveling far. NPCs and the three on-foot pickables are already spawned
# Sphere-gravity bonus level ("moon"). Same mechanic as godot-xr-tools'
# sphere-world demo, confirmed working on Quest 3S in the 2026-07-03
# isolation test: a point-gravity Area3D with SPACE_OVERRIDE_REPLACE makes
# PhysicsServer report gravity toward the planet center, and
# XRToolsPlayerBody natively re-derives its up vector from total_gravity
# every frame — no custom character code needed. Walk all the way around
# the planet; step off the gravity well and you fall to the plain below
# (re-enter by grappling/climbing back up the rocks, or just enjoy the
# drop — it's a bonus level).
func _build_sphere_world(sw: Dictionary) -> void:
	var r := float(sw["radius"])
	var center := Vector3(Terrain.SPAWN_CENTER.x, float(sw["height"]), Terrain.SPAWN_CENTER.y)
	# planet body: built-in SphereMesh (Godot's own primitive — winding
	# guaranteed) + matching collider
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var shape := CollisionShape3D.new()
	var ss := SphereShape3D.new()
	ss.radius = r
	shape.shape = ss
	body.add_child(shape)
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	sm.radial_segments = 32
	sm.rings = 16
	mi.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.62, 0.62, 0.66)
	mat.roughness = 0.95
	mi.set_surface_override_material(0, mat)
	body.add_child(mi)
	body.position = center
	world.add_child(body)
	# surface crates — landmarks so walking "around the world" reads clearly
	# (MeshKit boxes, oriented so local up = radial out from the center)
	var st := MeshKit.begin()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 10:
		var dir := Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized()
		var up := dir
		var tangent := up.cross(Vector3.RIGHT if absf(up.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD).normalized()
		var basis := Basis(up.cross(tangent), up, tangent).orthonormalized()
		var s := rng.randf_range(0.5, 1.1)
		MeshKit.box(st, Transform3D(basis, dir * (r + s * 0.5)), Vector3(s, s, s), Color(0.45, 0.42, 0.38))
	var crates := MeshInstance3D.new()
	crates.mesh = MeshKit.commit(st, MeshKit.mat_vcol(0.9))
	crates.position = center
	world.add_child(crates)
	# the gravity well — REPLACE so the planet's pull owns this volume
	var grav := Area3D.new()
	grav.gravity_space_override = Area3D.SPACE_OVERRIDE_REPLACE
	grav.gravity_point = true
	grav.gravity_point_center = Vector3.ZERO   # local to the area = planet center
	grav.gravity = 9.8
	var gshape := CollisionShape3D.new()
	var gs := SphereShape3D.new()
	gs.radius = r * 2.2
	gshape.shape = gs
	grav.add_child(gshape)
	grav.position = center
	world.add_child(grav)
	print("[moon] sphere world built: r=%.1f center=%s" % [r, center])

# unconditionally by start_game() regardless of level, so nothing extra is
# needed for those here.
func _spawn_debug_kitchen_sink(enemy_manager: EnemyManager, vehicle: Node3D) -> void:
	var et := EnemyTank.new(terrain, projectiles, fx, vehicle)
	enemy_manager.add_child(et)
	et.global_position = Vector3(28.0, terrain.height(28.0, 15.0) + 0.04, 15.0)

	var jeep := EnemyLight.Jeep.new(terrain, projectiles, fx, vehicle)
	enemy_manager.add_child(jeep)
	jeep.global_position = Vector3(-28.0, terrain.height(-28.0, 15.0) + 0.05, 15.0)

	for k in 3:
		var g := EnemyLight.Gunner.new(terrain, projectiles, vehicle)
		enemy_manager.add_child(g)
		var off := Vector3(Game.rng.randf_range(-4, 4), 0, Game.rng.randf_range(-4, 4))
		g.global_position = Vector3(0.0, 0, -30.0) + off
		g.global_position.y = terrain.height(g.global_position.x, g.global_position.z) + 0.05

	var mortar := EnemyLight.Mortar.new(terrain, projectiles, fx, vehicle)
	enemy_manager.add_child(mortar)
	mortar.global_position = Vector3(40.0, terrain.height(40.0, 20.0) + 0.1, 20.0)

	var plane := EnemyPlane.new(terrain, projectiles, fx, vehicle)
	enemy_manager.add_child(plane)
	plane.global_position = Vector3(60.0, 55.0, -40.0)

	if Levels.current.get("ships", 0) > 0:
		var ship := EnemyShip.new(terrain, projectiles, fx, vehicle)
		enemy_manager.add_child(ship)
		ship.global_position = _ring_pos_from(terrain, 60.0, 90.0, true)

# Same water-seeking search EnemyManager._ring_pos() uses, factored out so
# the debug spawner doesn't need an EnemyManager instance just for this.
func _ring_pos_from(t: Terrain, r_min: float, r_max: float, want_water: bool) -> Vector3:
	var pos := Vector3.ZERO
	for i in 40:
		var a := Game.rng.randf() * TAU
		var r := Game.rng.randf_range(r_min, r_max)
		pos = Vector3(cos(a) * r, 0, sin(a) * r)
		var h := t.height(pos.x, pos.z)
		if want_water and h < -1.8:
			break
	pos.y = -0.8 if want_water else t.height(pos.x, pos.z) + 0.1
	return pos

func exit_vehicle() -> void:
	if not (rig is XRRig) or current_vehicle == null or not is_instance_valid(current_vehicle):
		return
	if Game.player_mode != Game.PlayerMode.SEATED:
		return
	var v := current_vehicle
	var dismount_pos: Vector3 = v.global_position - v.global_transform.basis.z * 2.2
	dismount_pos.y = terrain.height(dismount_pos.x, dismount_pos.z) + 0.1
	var dismount := Transform3D(v.global_transform.basis.orthonormalized(), dismount_pos)
	if rig.on_foot_body == null or not is_instance_valid(rig.on_foot_body):
		rig.call("set_on_foot_body", OnFootBody.new(terrain, projectiles, fx))
	rig.call("enter_on_foot", world, dismount)
	# climbing-out clank + boots-hit-ground thud, with a haptic pulse on both
	# hands so the transition reads physically, not just as a scene cut
	Sfx.play_at("switch", v.global_position, -2.0, 0.85)
	Sfx.play_at("thud", dismount_pos, 0.0, 0.9)
	rig.hand_l.pulse(0.35, 0.12)
	rig.hand_r.pulse(0.35, 0.12)

func enter_vehicle(v: Node3D) -> void:
	if not (rig is XRRig) or v == null or not is_instance_valid(v):
		return
	if Game.player_mode != Game.PlayerMode.ON_FOOT:
		return
	var at := v.global_position
	rig.call("attach_to_vehicle", v)
	_auto_start_if_third_person(v)
	# climbing-in clank + seat click, same haptic language as exit_vehicle()
	Sfx.play_at("switch", at, -2.0, 1.05)
	Sfx.play_at("click", at, -4.0)
	rig.hand_l.pulse(0.3, 0.1)
	rig.hand_r.pulse(0.3, 0.1)

# Alex: "when in third person mode we shouldn't need to do anything to
# 'start' the vehicle unless we're going to properly show the full
# dashboard to a third person player" -- the start ritual (battery switch,
# fuel pump, starter crank) is only discoverable by looking at the physical
# cockpit, which a third-person/chase view never shows. Auto-skip it
# whenever the player's already chosen third person.
func _auto_start_if_third_person(vehicle: Node3D) -> void:
	if Game.third_person and vehicle and vehicle.has_method("quick_start"):
		vehicle.call("quick_start")

func _clear_world() -> void:
	if world:
		world.queue_free()
		world = null
	# on_foot_body lives under the rig (XROrigin3D), not world — see
	# xr_rig.gd's enter_on_foot() — so world.queue_free() never reaches it.
	if rig is XRRig and rig.on_foot_body and is_instance_valid(rig.on_foot_body):
		rig.on_foot_body.queue_free()
		rig.on_foot_body = null
	player = null
	plane = null
	current_vehicle = null

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

# ---------------------------------------------------------------- local avatar
# Attaches/drives an AvatarRig for the LOCAL player's own body — SEATED mode
# parents it directly to current_vehicle (net.gd's _crew_avatar precedent,
# same reasoning: tank space never carries the third-person chase offset,
# unlike `rig` itself), ON_FOOT parents it to the on-foot body so it walks
# with the player. Head is hidden in first person so the camera isn't stuck
# inside it; torso/arms/hands stay visible for the "look down at yourself"
# case that's the whole point of having a body.
func _update_local_avatar(delta: float) -> void:
	if Game.state != Game.GState.PLAYING or rig == null:
		_clear_local_avatar()
		return
	var seated := Game.player_mode == Game.PlayerMode.SEATED
	var parent: Node3D = current_vehicle if seated else (rig.get("on_foot_body") if rig is XRRig else null)
	if parent == null or not is_instance_valid(parent):
		_clear_local_avatar()
		return
	var want_mode := AvatarRig.Mode.SEATED if seated else AvatarRig.Mode.ON_FOOT
	if _local_avatar == null or not is_instance_valid(_local_avatar):
		_local_avatar = AvatarRig.new()
		_local_avatar.configure(want_mode, AvatarCosmetics.tint_for(NetManager.my_id()))
	elif _local_avatar.mode != want_mode:
		_local_avatar.configure(want_mode, _local_avatar.tint)
	if _local_avatar.get_parent() != parent:
		if _local_avatar.get_parent():
			_local_avatar.get_parent().remove_child(_local_avatar)
		parent.add_child(_local_avatar)
	var head_t: Transform3D
	var hand_l_t: Transform3D
	var hand_r_t: Transform3D
	if seated and rig.has_method("local_body_pose"):
		var pose: Dictionary = rig.call("local_body_pose", parent)
		head_t = pose["head"]
		hand_l_t = pose["hand_l"]
		hand_r_t = pose["hand_r"]
	else:
		# on-foot: rig's own position IS the physics-authoritative body
		# location (the addon repositions the origin directly), so no
		# chase-offset correction is needed the way SEATED requires.
		var cam: Node3D = rig.get("camera")
		var hl: Node3D = rig.get("hand_l")
		var hr: Node3D = rig.get("hand_r")
		var inv := parent.global_transform.affine_inverse()
		head_t = inv * cam.global_transform if cam else Transform3D()
		hand_l_t = inv * hl.global_transform if hl else head_t
		hand_r_t = inv * hr.global_transform if hr else head_t
	_local_avatar.set_head_visible(Game.third_person)
	_local_avatar.update_live(delta, head_t, hand_l_t, hand_r_t, {})

func _clear_local_avatar() -> void:
	if _local_avatar and is_instance_valid(_local_avatar):
		_local_avatar.queue_free()
	_local_avatar = null

# Well below anything a level legitimately places you at (rim mountains top
# out around +85, lava_y bottoms out around -3.2) — this only fires if
# something has genuinely fallen through the world (Alex: "if you ever do
# fall too far out of the map, we should have a kill box to refresh you").
# Repositions in place rather than routing through Game.restart(), which
# also zeroes score/wave/hp — a physics glitch shouldn't cost you the run.
const FALL_KILL_Y := -60.0
var _fall_recover_cool := 0.0

func _current_ground_entity() -> Node3D:
	var veh: Node3D = plane if plane else (player if player else null)
	if veh == null:
		for n in get_tree().get_nodes_in_group("player"):
			veh = n
			break
	return veh

func _recover_from_fall(veh: Node3D) -> void:
	if _fall_recover_cool > 0.0 or terrain == null:
		return
	_fall_recover_cool = 1.5
	EventLog.log_event("fall_recover", {"level": Game.level_id, "player_mode": Game.player_mode})
	var spawn_h := terrain.height(terrain.spawn.x, terrain.spawn.y)
	veh.global_position = Vector3(terrain.spawn.x, spawn_h + 1.2, terrain.spawn.y)
	if veh is CharacterBody3D:
		(veh as CharacterBody3D).velocity = Vector3.ZERO
	Sfx.play_at("thud", veh.global_position, 0.0, 0.85)

# ---------------------------------------------------------------- perf + test modes
func _process(delta: float) -> void:
	_demo_tick(delta)
	_update_local_avatar(delta)
	_fall_recover_cool = maxf(0.0, _fall_recover_cool - delta)
	if Game.state == Game.GState.PLAYING:
		var veh := _current_ground_entity()
		if veh and is_instance_valid(veh):
			if veh.global_position.y < FALL_KILL_Y:
				_recover_from_fall(veh)
			# lava is not a swimming pool
			elif Levels.current.has("lava_y") and veh.global_position.y < float(Levels.current["lava_y"]) and Game.alive:
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
		if OS.get_environment("SHOT_TP") != "":
			Game.third_person = true
			rig.call("_apply_camera_mode")
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

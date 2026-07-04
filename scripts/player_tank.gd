# The player's tank: differential-track driving (math ground-follow, collider
# only for walls/enemies), rotating turret cockpit, main gun with a manual
# breech cycle, rocket pods, coax MG. Thumbstick fallbacks drive the same
# controls (levers animate to match).
class_name PlayerTank
extends CharacterBody3D

const MAX_TRACK := 7.0          # m/s per track
const YAW_GAIN := 0.55          # differential yaw authority
const ACCEL := 3.2
const TURRET_SLEW := 0.85       # rad/s
const GUN_EL_MIN := deg_to_rad(-6.0)
const GUN_EL_MAX := deg_to_rad(16.0)
const SHELL_SPEED := 150.0
const MG_PERIOD := 0.11
const ROCKET_COOLDOWN := 3.0

var terrain: Terrain
var projectiles: Projectiles
var fx: FxPool

var turret: Node3D
var gun_pivot: Node3D
var recoil: Node3D
var muzzle: Node3D
var coax: Node3D
var pod_l: Node3D
var pod_r: Node3D
var cockpit: Dictionary
var reticle: Node3D
var blob: MeshInstance3D
var headlights: Array = []
var head_lamp_mat: StandardMaterial3D

# state
var battery_on := false
var fuel_on := false
var gear := 0            # -1 R, 0 N, 1 D
var engine_on := false
var starting := false
var start_hold := 0.0
var fuel := 100.0
var temp := 0.0
var loaded := true
var ammo := 40
var rockets_left := 12
var rockets_armed := false
var rocket_cool := 0.0
var mg_timer := 0.0
var mg_held := false
var gun_elev := 0.0
var yaw := PI  # face -Z world at spawn (spawn is south, center is north)

# net
var puppet := false          # co-op client: host simulates, we mirror
var _net_target := Transform3D()
var _net_turret_y := 0.0
var _net_has := false

# inputs
var tiller_l_v := 0.0
var tiller_r_v := 0.0
var stick_drive := Vector2.ZERO
var turret_input := Vector2.ZERO
var stick_turret := Vector2.ZERO
var auto_reload := false
var auto_reload_t := 0.0

# audio
var engine_p: AudioStreamPlayer3D
var tracks_p: AudioStreamPlayer3D
var turret_p: AudioStreamPlayer3D
var alarm_p: AudioStreamPlayer3D

var _spd := 0.0   # current forward speed
var _yaw_rate := 0.0
var _vy := 0.0    # vertical velocity (airtime/bouncing in low-g)
var _exhaust_t := 0.0
var _hint_stage := 0
var _hint_t := 0.0
var _dust_t := 0.0

func _init(t: Terrain, p: Projectiles, f: FxPool) -> void:
	terrain = t
	projectiles = p
	fx = f
	name = "PlayerTank"
	collision_layer = 2
	collision_mask = 1 | 4
	add_to_group("player")

func _ready() -> void:
	_build_exterior()
	if Game.mutator == "balloon":
		Game.balloonize(self)   # exterior only — cockpit is built next
	cockpit = CockpitBuilder.build(turret)
	_wire_controls()
	_build_reticle()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.3, 1.1, 6.6)
	shape.shape = box
	shape.position = Vector3(0, 1.05, 0)
	add_child(shape)
	engine_p = Sfx.make_loop_player("engine_loop", self, -80.0)
	tracks_p = Sfx.make_loop_player("tracks_loop", self, -80.0)
	turret_p = Sfx.make_loop_player("turret_loop", turret, -80.0)
	alarm_p = Sfx.make_loop_player("alarm", turret, -80.0, 2.0)
	engine_p.play(); tracks_p.play(); turret_p.play(); alarm_p.play()
	Game.game_over.connect(_on_game_over)
	Game.game_restarted.connect(_on_restart)
	Game.score_changed.connect(func(_s): _update_plaque())
	Game.wave_changed.connect(func(_w): _update_plaque())
	# spawn placement
	global_position = Vector3(Terrain.SPAWN_CENTER.x, 0, Terrain.SPAWN_CENTER.y)
	global_position.y = terrain.height(global_position.x, global_position.z) + 0.04
	_update_plaque()

# ------------------------------------------------------------------ exterior
func _build_exterior() -> void:
	var camo := MeshKit.mat_tex("res://assets/tex/camo.png", true, 0.85)
	var hull_c := Color(1, 1, 1)
	var st := MeshKit.begin()
	# hull body
	MeshKit.box(st, Transform3D(Basis(), Vector3(0, 1.1, 0.3)), Vector3(2.4, 0.75, 5.6), hull_c, 0.18)
	# glacis (sloped front)
	MeshKit.box(st, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-38)), Vector3(0, 0.98, -2.95)), Vector3(2.4, 0.72, 1.3), hull_c, 0.18)
	# rear deck + exhaust
	MeshKit.box(st, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(20)), Vector3(0, 1.05, 3.0)), Vector3(2.4, 0.5, 1.0), hull_c, 0.18)
	MeshKit.box(st, Transform3D(Basis(), Vector3(-1.05, 1.3, 2.6)), Vector3(0.25, 0.18, 0.7), Color(0.35, 0.33, 0.3))
	# fenders
	for sx in [-1.45, 1.45]:
		MeshKit.box(st, Transform3D(Basis(), Vector3(sx, 1.42, 0)), Vector3(0.5, 0.06, 6.4), hull_c, 0.18)
	var hull_mi := MeshInstance3D.new()
	hull_mi.mesh = MeshKit.commit(st, camo)
	add_child(hull_mi)

	# tracks + wheels (dark)
	var tst := MeshKit.begin()
	var dark := Color(0.14, 0.14, 0.15)
	for sx in [-1.42, 1.42]:
		MeshKit.box(tst, Transform3D(Basis(), Vector3(sx, 0.85, 0)), Vector3(0.46, 0.55, 6.5), dark)
		for i in 6:
			MeshKit.cyl(tst, Transform3D(Basis(Vector3(0, 0, 1), PI / 2), Vector3(sx, 0.5, -2.5 + i * 1.0)), 0.42, 0.42, 0.5, 8, Color(0.22, 0.22, 0.23))
	var tracks_mi := MeshInstance3D.new()
	tracks_mi.mesh = MeshKit.commit(tst, MeshKit.mat_tex("res://assets/tex/rubber.png", true, 0.95))
	add_child(tracks_mi)

	# turret
	turret = Node3D.new()
	turret.name = "Turret"
	turret.position = Vector3(0, 1.62, -0.2)
	add_child(turret)
	var ust := MeshKit.begin()
	# turret shell — wide flat dome look via stacked cyl + box front
	MeshKit.cyl(ust, Transform3D(Basis(), Vector3(-0.1, 0.38, 0.0)), 1.05, 0.85, 0.78, 12, hull_c)
	# Front armor slab, now with a real driver's-window opening cut through
	# it (x -0.75..-0.06, matching the interior wall's widened gap). The old
	# single solid box covered the interior vision slit COMPLETELY — the
	# actual reason there has never been a front view out of this tank, no
	# matter how much the interior slit was widened.
	var fb := Basis(Vector3.RIGHT, deg_to_rad(12))
	var fc := Vector3(0, 0.35, -0.72)
	MeshKit.box(ust, Transform3D(fb, fc + fb * Vector3(0.345, 0.0, 0.0)), Vector3(0.81, 0.62, 0.5), hull_c, 0.18)
	MeshKit.box(ust, Transform3D(fb, fc + fb * Vector3(-0.405, 0.23, 0.0)), Vector3(0.69, 0.16, 0.5), hull_c, 0.18)
	MeshKit.box(ust, Transform3D(fb, fc + fb * Vector3(-0.405, -0.25, 0.0)), Vector3(0.69, 0.12, 0.5), hull_c, 0.18)
	# mantlet
	MeshKit.box(ust, Transform3D(Basis(), Vector3(0, 0.35, -0.98)), Vector3(0.55, 0.5, 0.3), Color(0.55, 0.57, 0.50), 0.18)
	# commander cupola
	MeshKit.cyl(ust, Transform3D(Basis(), Vector3(-0.28, 0.82, 0.25)), 0.34, 0.30, 0.14, 10, hull_c)
	var tur_mi := MeshInstance3D.new()
	tur_mi.mesh = MeshKit.commit(ust, camo)
	turret.add_child(tur_mi)

	# rocket pods on turret cheeks. Alex, live headset: "the white missile
	# launchers on either side of the tank... it's distracting they are
	# white while the rest of our tank is camouflaged." (0.8,0.82,0.78) is
	# the exact same too-light-to-survive-this-environment's-ambient
	# mistake as enemy_tank.gd's original camo color (see that file's
	# 2026-07-04 fix) -- washes toward white under the sky-source ambient.
	# Darkened to a dull olive-drab matching the rest of the hull, and
	# pushed out/back slightly so they crowd the periscope sightlines less.
	var pst := MeshKit.begin()
	# v0.6.15: pods moved BEHIND the turret (z 0.22 -> 0.62). At z 0.22 they
	# sat directly over the side hatches and inside the side-window z range
	# (-0.15..0.10) — Alex: "missile launchers are still blocking side
	# hatches." Rear-mounted pods clear both (no rear window exists).
	for sx in [-1.1, 1.1]:
		MeshKit.box(pst, Transform3D(Basis(), Vector3(sx, 0.45, 0.62)), Vector3(0.35, 0.4, 0.9), Color(0.28, 0.30, 0.24), 0.18)
		for iy in 2:
			for ix in 2:
				MeshKit.cyl(pst, Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(sx + (ix - 0.5) * 0.16, 0.37 + iy * 0.17, 0.17)), 0.055, 0.055, 0.12, 8, Color(0.1, 0.1, 0.1))
	var pods_mi := MeshInstance3D.new()
	pods_mi.mesh = MeshKit.commit(pst, MeshKit.mat_vcol(0.7, 0.2))
	turret.add_child(pods_mi)
	pod_l = Node3D.new(); pod_l.position = Vector3(-1.1, 0.45, 0.15); turret.add_child(pod_l)
	pod_r = Node3D.new(); pod_r.position = Vector3(1.1, 0.45, 0.15); turret.add_child(pod_r)

	# gun: pivot -> recoil -> barrel + breech
	gun_pivot = Node3D.new()
	gun_pivot.position = Vector3(0, 0.35, -0.55)
	turret.add_child(gun_pivot)
	recoil = Node3D.new()
	gun_pivot.add_child(recoil)
	# barrel (exterior, sun-lit)
	var gst := MeshKit.begin()
	MeshKit.cyl(gst, Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(0, 0, -2.3)), 0.10, 0.085, 3.9, 10, Color(0.30, 0.32, 0.28))
	MeshKit.cyl(gst, Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(0, 0, -4.15)), 0.13, 0.13, 0.45, 10, Color(0.24, 0.26, 0.23))
	var gmi := MeshInstance3D.new()
	gmi.mesh = MeshKit.commit(gst, MeshKit.mat_vcol(0.6, 0.35))
	recoil.add_child(gmi)
	# breech block (interior render layer — no direct sun inside the turret).
	# "Cockpit space = turret space" (cockpit_builder.gd header) — this box
	# is in the SAME local frame as the crew compartment (cockpit Z0=-0.58
	# front wall, EYE.z=0.30, Z1=0.58 rear wall). At the old Z=0.55/0.95
	# (turret-local ≈ -0.35/0.05 after the gun_pivot/turret offsets — still
	# right in the driver's face), the plain untextured breech geometry
	# read as "a big metal box blocking half the tank." Alex correctly
	# guessed it was the gun's own breech, not a wall or console — my
	# earlier console-pedestal theory was wrong (verified: repositioning
	# it changed nothing in a render test). Pulled forward once already
	# today; STILL reported "poking into the center of the cockpit area" on
	# the next pass, so pushed further back again (extra 0.15m clearance on
	# the near block) AND shifted right off the centerline — EYE.x=-0.28
	# (driver seated LEFT of the breech per this file's own header) means
	# an X=0 breech was only ~0.11m clear of the eye's own X position,
	# barely offset at all despite the "seated left of" design intent.
	var bst := MeshKit.begin()
	# v0.6.15: render sweep showed the old block STILL filling the whole
	# right half of the seated view (rear plate ended 5cm from the eye).
	# Shrunk and pulled forward: rear face now ~0.7m ahead of the eye.
	MeshKit.box(bst, Transform3D(Basis(), Vector3(0.12, 0, 0.0)), Vector3(0.30, 0.34, 0.40), Color(0.35, 0.38, 0.34))
	MeshKit.box(bst, Transform3D(Basis(), Vector3(0.12, 0, 0.22)), Vector3(0.22, 0.26, 0.08), Color(0.24, 0.26, 0.24))
	var bmi := MeshInstance3D.new()
	bmi.mesh = MeshKit.commit(bst, MeshKit.mat_vcol(0.6, 0.35))
	bmi.layers = 2
	recoil.add_child(bmi)
	muzzle = Node3D.new()
	muzzle.position = Vector3(0, 0, -4.4)
	recoil.add_child(muzzle)
	coax = Node3D.new()
	coax.position = Vector3(0.35, 0.05, -1.1)
	gun_pivot.add_child(coax)

	# breech reload lever — mounted on the gun cradle, left side (player side)
	var breech_lever := VRControl.Lever.create(0.22, Color(0.75, 0.15, 0.1), 45.0, true)
	breech_lever.center_rate = 5.0
	# base overlaps the breech box's left face (x -0.03) so the lever is
	# visibly MOUNTED on it, not floating mid-air (Alex: "levers not
	# attached to anything")
	breech_lever.position = Vector3(-0.02, 0.0, 0.10)
	breech_lever.rotation.z = deg_to_rad(90)  # sticks out toward player
	gun_pivot.add_child(breech_lever)
	breech_lever.value_changed.connect(_on_breech_lever)
	CockpitBuilder.set_interior_layer(breech_lever)

	# blob shadow
	blob = MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(4.6, 7.6)
	blob.mesh = qm
	var bm := StandardMaterial3D.new()
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.albedo_texture = load("res://assets/tex/blob_shadow.png")
	bm.albedo_color = Color(1, 1, 1, 0.55)
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	blob.material_override = bm
	blob.rotation.x = -PI / 2
	blob.top_level = true
	add_child(blob)

	# headlights
	for sx in [-0.9, 0.9]:
		var spot := SpotLight3D.new()
		spot.position = Vector3(sx, 1.25, -3.2)
		spot.rotation.x = deg_to_rad(-4)
		spot.spot_range = 40.0
		spot.spot_angle = 28.0
		spot.light_energy = 0.0
		spot.shadow_enabled = false
		spot.light_color = Color(1.0, 0.95, 0.8)
		spot.light_cull_mask = 0xFFFFF & ~2  # don't leak into the cockpit
		add_child(spot)
		headlights.append(spot)
	var lst := MeshKit.begin()
	for sx in [-0.9, 0.9]:
		MeshKit.cyl(lst, Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(sx, 1.25, -3.15)), 0.09, 0.09, 0.08, 8, Color.WHITE)
	head_lamp_mat = StandardMaterial3D.new()
	head_lamp_mat.albedo_color = Color(0.38, 0.38, 0.34)
	var lmi := MeshInstance3D.new()
	lmi.mesh = MeshKit.commit(lst, head_lamp_mat)
	add_child(lmi)

func _build_reticle() -> void:
	reticle = Node3D.new()
	reticle.top_level = true
	var mi := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(1, 1)
	mi.mesh = qm
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = load("res://assets/tex/reticle.png")
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.no_depth_test = true
	m.render_priority = 10
	mi.material_override = m
	reticle.add_child(mi)
	add_child(reticle)

# ------------------------------------------------------------------ control wiring
func _wire_controls() -> void:
	var c: Dictionary = cockpit["controls"]
	c["tiller_l"].value_changed.connect(func(v): tiller_l_v = v)
	c["tiller_r"].value_changed.connect(func(v): tiller_r_v = v)
	c["grip"].deflection_changed.connect(func(v): turret_input = v)
	c["battery"].toggled_on.connect(_on_battery)
	c["lights"].toggled_on.connect(_on_lights)
	c["rocket_cover"].toggled_on.connect(func(open): c["rocket_arm"].enabled = open; if not open and rockets_armed: c["rocket_arm"].flip())
	c["rocket_arm"].toggled_on.connect(_on_arm)
	c["rocket_fire"].pressed.connect(fire_rockets)
	c["restart"].value_changed.connect(_on_restart_lever)
	c["fuel_pump"].toggled_on.connect(func(on): fuel_on = on)
	c["gear"].value_changed.connect(_on_gear)
	c["horn"].pressed.connect(func():
		Sfx.play_at("horn", global_position + Vector3(0, 1.5, -3), 4.0)
		_rumble(0.3, 0.08))
	c["radio_volume"].value_changed.connect(func(v): Sfx.music_gain = v * 1.4)
	c["radio_channel"].value_changed.connect(func(v):
		var st := roundi(v * 4.0)
		Sfx.set_radio_station(st)
		cockpit["labels"]["radio_station"].text = Sfx.STATIONS[clampi(st, 0, 4)])
	Sfx.radio_attach(cockpit["radio_node"])
	c["menu_switch"].toggled_on.connect(func(_on):
		var m := get_tree().get_first_node_in_group("main")
		if m:
			m.call_deferred("to_menu"))
	c["seat_btn"].pressed.connect(func():
		var m := get_tree().get_first_node_in_group("main")
		if m and m.rig is XRRig:
			m.rig.set("_calibrated", false)
			m.rig.set("_calib_t", 1.0))
	c["hatch"].value_changed.connect(_on_hatch_lever)

func _on_hatch_lever(v: float) -> void:
	if absf(v) > 0.8 and Game.player_mode == Game.PlayerMode.SEATED:
		var m := get_tree().get_first_node_in_group("main")
		if m:
			m.call_deferred("exit_vehicle")

func _on_gear(v: float) -> void:
	var g := 0
	if v > 0.4:
		g = 1
	elif v < -0.4:
		g = -1
	if g != gear:
		gear = g
		Sfx.play_at("shifter", turret.global_position, -2.0)
		_rumble(0.3, 0.03)

func _on_battery(on: bool) -> void:
	battery_on = on
	cockpit["dome_light"].light_energy = 0.6 if on else 0.0
	cockpit["dome_bulb"].emission_energy_multiplier = 1.2 if on else 0.0

func _on_lights(on: bool) -> void:
	Game.player_lights = on and battery_on
	if on:
		Sfx.vo("vo_lights", 0, 40.0)
	for l in headlights:
		l.light_energy = 3.5 if (on and battery_on) else 0.0
	head_lamp_mat.emission_enabled = on and battery_on
	if head_lamp_mat.emission_enabled:
		head_lamp_mat.emission = Color(1, 0.95, 0.7)
		head_lamp_mat.emission_energy_multiplier = 2.0

func _on_arm(on: bool) -> void:
	rockets_armed = on
	_set_lamp("armed", on)
	if on:
		Sfx.vo("vo_armed", 1, 45.0)

func _on_breech_lever(v: float) -> void:
	if absf(v) > 0.85 and not loaded and ammo > 0:
		if puppet:
			NetManager.c_event.rpc_id(1, "breech")
		else:
			_chamber()

func _chamber() -> void:
	loaded = true
	ammo -= 1
	Sfx.play_at("reload", turret.global_position, 2.0)
	_set_lamp("reload", false)
	cockpit["labels"]["ammo"].text = "AP %d" % ammo
	if ammo == 6:
		Sfx.vo("robot_lowammo" if Game.rng.randf() < 0.5 else "vo_ammo_low", 2, 60.0)

func _on_restart_lever(v: float) -> void:
	if absf(v) > 0.8 and not Game.alive:
		Game.restart()

func _on_game_over() -> void:
	engine_on = false
	starting = false
	alarm_p.volume_db = -4.0
	var c: Dictionary = cockpit["controls"]
	c["restart"].enabled = true
	c["restart"].set_highlight(true)
	cockpit["labels"]["hint"].text = "DESTROYED — PULL YELLOW ROOF HANDLE"
	fx.smoke_column(global_position + Vector3(0, 2.5, 0), 30.0)
	Sfx.sting("sting_over")
	Sfx.vo("vo_gameover", 4, 5.0)
	_set_lamp("engine", false)

func _on_restart() -> void:
	global_position = Vector3(Terrain.SPAWN_CENTER.x, 0, Terrain.SPAWN_CENTER.y)
	global_position.y = terrain.height(global_position.x, global_position.z) + 0.04
	yaw = PI
	_spd = 0.0
	ammo = 40
	rockets_left = 12
	loaded = true
	fuel = 100.0
	alarm_p.volume_db = -80.0
	var c: Dictionary = cockpit["controls"]
	c["restart"].enabled = false
	c["restart"].set_highlight(false)
	cockpit["labels"]["hint"].text = ""
	cockpit["labels"]["ammo"].text = "AP %d" % ammo
	cockpit["labels"]["rockets"].text = "RKT %d" % rockets_left
	_set_lamp("low_hull", false)
	_set_lamp("reload", false)
	_hint_stage = 0
	_hint_t = 0.0
	_update_plaque()

func _set_lamp(name_: String, on: bool) -> void:
	var lamp: Dictionary = cockpit["lamps"][name_]
	var col: Color = lamp["color"]
	lamp["mat"].albedo_color = col if on else col * 0.25
	lamp["mat"].emission_enabled = on
	if on:
		lamp["mat"].emission = col
		lamp["mat"].emission_energy_multiplier = 1.5

func _update_plaque() -> void:
	if Game.mode == Game.Mode.VERSUS:
		cockpit["labels"]["plaque"].text = "YOU %d    THEM %d" % [Game.my_kills, Game.their_kills]
	else:
		cockpit["labels"]["plaque"].text = "WAVE %d   SCORE %d   %s" % [maxi(Game.wave, 1), Game.score, Game.diff_name()]

# ------------------------------------------------------------------ per-frame
func _physics_process(delta: float) -> void:
	if puppet:
		_puppet_update(delta)
		return
	_update_engine(delta)
	_update_drive(delta)
	_update_turret(delta)
	_update_weapons(delta)
	_update_gauges(delta)
	_update_hints()
	_update_reticle()
	# blob shadow follows terrain
	var gp := global_position
	blob.global_position = Vector3(gp.x, terrain.height(gp.x, gp.z) + 0.06, gp.z)
	blob.rotation = Vector3(-PI / 2, yaw, 0)

# co-op client: mirror host state, keep local turret prediction responsive
func _puppet_update(delta: float) -> void:
	if _net_has:
		global_transform = global_transform.interpolate_with(_net_target, clampf(8.0 * delta, 0.0, 1.0))
	var inp := turret_input
	if inp.length() < 0.05 and stick_turret.length() > 0.08:
		inp = stick_turret
	turret.rotation.y += -inp.x * Tune.v("turret_slew") * delta
	turret.rotation.y = lerp_angle(turret.rotation.y, _net_turret_y, clampf(1.5 * delta, 0.0, 1.0))
	gun_elev = clampf(gun_elev + inp.y * 0.5 * delta, GUN_EL_MIN, GUN_EL_MAX)
	gun_pivot.rotation.x = gun_elev
	turret_p.volume_db = -14.0 if inp.length() > 0.1 else -80.0
	_update_gauges(delta)
	_update_reticle()
	var gp := global_position
	blob.global_position = Vector3(gp.x, terrain.height(gp.x, gp.z) + 0.06, gp.z)
	blob.rotation = Vector3(-PI / 2, yaw, 0)

func net_apply(t: Transform3D, turret_y: float, _gun_e: float, na: int, nr: int, nloaded: bool, nengine: bool) -> void:
	_net_target = t
	_net_turret_y = turret_y
	_net_has = true
	if na != ammo:
		ammo = na
		cockpit["labels"]["ammo"].text = "AP %d" % ammo
	if nr != rockets_left:
		rockets_left = nr
		cockpit["labels"]["rockets"].text = "RKT %d" % rockets_left
	if nloaded != loaded:
		loaded = nloaded
		_set_lamp("reload", not loaded)
		if loaded:
			Sfx.play_at("reload", turret.global_position, 0.0)
	if nengine != engine_on:
		engine_on = nengine
		engine_p.volume_db = -6.0 if engine_on else -80.0
		_set_lamp("engine", engine_on)

func _update_engine(delta: float) -> void:
	var starter: VRControl.PushButton = cockpit["controls"]["starter"]
	if starter.is_down and battery_on and fuel_on and not engine_on and not starting and Game.alive:
		start_hold += delta
		if start_hold > 0.25:
			_begin_start()
	else:
		start_hold = 0.0
	if engine_on:
		fuel = maxf(fuel - delta * 0.02, 12.0)
		temp = move_toward(temp, 0.35 + 0.4 * absf(_spd) / MAX_TRACK, delta * 0.05)
	else:
		temp = move_toward(temp, 0.0, delta * 0.03)

func _begin_start() -> void:
	starting = true
	Sfx.play_at("ignition", global_position, 2.0)
	var tw := create_tween()
	tw.tween_interval(1.35)
	tw.tween_callback(func():
		starting = false
		if battery_on and Game.alive:
			engine_on = true
			engine_p.volume_db = -6.0
			_set_lamp("engine", true)
			Sfx.vo("robot_online" if Game.rng.randf() < 0.3 else "vo_start", 2, 30.0))

func effective_drive() -> Vector2:
	# returns (left, right) track command; stick overrides idle tillers
	var l := tiller_l_v
	var r := tiller_r_v
	if absf(l) < 0.04 and absf(r) < 0.04 and stick_drive.length() > 0.08:
		if gear == 0:
			# casual auto-shift into Drive on stick input
			cockpit["controls"]["gear"].value = 1.0
		var fwd := stick_drive.y
		var turn := stick_drive.x
		l = clampf(fwd + turn, -1.0, 1.0)
		r = clampf(fwd - turn, -1.0, 1.0)
		# animate the physical tillers to match
		cockpit["controls"]["tiller_l"].value = l
		cockpit["controls"]["tiller_r"].value = r
	match gear:
		0:
			return Vector2.ZERO      # neutral: engine revs, nothing happens
		-1:
			return Vector2(-l, -r) * 0.6  # reverse gear: inverted, slower
		_:
			return Vector2(l, r)

func _update_drive(delta: float) -> void:
	var cmd := effective_drive() if (engine_on and Game.alive) else Vector2.ZERO
	var mud: float = lerpf(Tune.v("mud_slow"), 1.0, 1.0 if Levels.mud_factor(global_position) >= 1.0 else 0.0)
	var target_fwd := (cmd.x + cmd.y) * 0.5 * Tune.v("tank_max_speed") * mud * Game.speed_scale()
	var target_yaw_rate := (cmd.x - cmd.y) * YAW_GAIN * 2.0
	_spd = move_toward(_spd, target_fwd, ACCEL * delta)
	_yaw_rate = move_toward(_yaw_rate, target_yaw_rate, 2.5 * delta)
	yaw += _yaw_rate * delta

	var fwd_dir := Vector3(-sin(yaw), 0, -cos(yaw))
	# NOTE: Basis yaw convention checked below in _align; forward = -Z rotated by yaw
	# tanks do not swim: refuse to drive into deep water (beach/island)
	# — or into the lava bowl (volcano): same gate, hotter consequences
	if Game.mutator != "underwater":
		var floor_limit := -1.1
		if Levels.current.has("lava_y"):
			floor_limit = float(Levels.current["lava_y"]) + 0.8
		var ahead := global_position + fwd_dir * signf(_spd) * 4.0
		if terrain.height(ahead.x, ahead.z) < floor_limit and terrain.height(global_position.x, global_position.z) > floor_limit:
			_spd = move_toward(_spd, 0.0, 20.0 * delta)
	var hvel := fwd_dir * _spd
	# storm/tornado wind shove
	var weather: Weather = get_tree().get_first_node_in_group("weather")
	if weather:
		hvel += weather.wind_push
	var gp := global_position
	var target_y := terrain.height(gp.x, gp.z) + 0.04
	# vertical: grounded follow with real airtime (hops off crests; low-g bounces)
	var next_y := gp.y + _vy * delta
	if next_y <= target_y + 0.02:
		var impact := _vy
		next_y = target_y
		if impact < -4.0:
			Sfx.play_at("boing" if Game.mutator == "lowg" else "thud", gp, 0.0)
			_rumble(0.5, 0.08)
			fx.dust(Vector3(gp.x, target_y, gp.z), 1.4)
			_vy = -impact * Game.bounce()
		else:
			_vy = 0.0
	else:
		_vy -= Game.fall_g() * delta
	velocity = hvel + Vector3(0, clampf((next_y - gp.y) / delta, -60.0, 60.0), 0)
	move_and_slide()
	# shove rigid props (gym basketballs!) we drive into
	for ci in get_slide_collision_count():
		var col := get_slide_collision(ci)
		var body := col.get_collider()
		if body is RigidBody3D:
			body.apply_central_impulse(-col.get_normal() * maxf(absf(_spd), 2.0) * 8.0 + Vector3(0, 24, 0))
			Sfx.play_at("boing", body.global_position, -4.0)
	# track dust while moving
	_dust_t -= delta
	if _dust_t <= 0.0 and absf(_spd) > 3.0 and _vy == 0.0:
		_dust_t = 0.45
		var behind := global_position - fwd_dir * signf(_spd) * 3.4
		fx.dust(Vector3(behind.x, terrain.height(behind.x, behind.z) + 0.3, behind.z), 1.0)
	# arena clamp
	var flat := Vector2(global_position.x, global_position.z)
	if flat.length() > terrain.arena_radius:
		flat = flat.normalized() * terrain.arena_radius
		global_position.x = flat.x
		global_position.z = flat.y
	_align(delta)

	# audio + exhaust
	var load_k := absf(_spd) / MAX_TRACK
	if engine_on:
		engine_p.pitch_scale = 0.9 + load_k * 0.55
		engine_p.volume_db = -6.0 + load_k * 4.0
		tracks_p.volume_db = -60.0 + load_k * 54.0
		tracks_p.pitch_scale = 0.8 + load_k * 0.5
		_exhaust_t -= delta
		if _exhaust_t <= 0.0 and load_k > 0.2:
			_exhaust_t = 0.5
	else:
		engine_p.volume_db = -80.0
		tracks_p.volume_db = -80.0

func _align(delta: float) -> void:
	var n := terrain.normal(global_position.x, global_position.z)
	var f := Vector3(-sin(yaw), 0, -cos(yaw))
	var right := f.cross(n).normalized() * -1.0
	var fwd := n.cross(right).normalized() * -1.0
	var target := Basis(right * -1.0, n, fwd * -1.0).orthonormalized()
	# Basis columns: x=right(+X), y=up, z=back(+Z). fwd here = -Z direction.
	basis = basis.slerp(target, clampf(5.0 * delta, 0.0, 1.0)).orthonormalized()

func _update_turret(delta: float) -> void:
	var inp := turret_input
	if NetManager.hosting and Game.mode == Game.Mode.COOP:
		inp = NetManager.gunner_input   # the gunner (client) owns the turret
	elif inp.length() < 0.05 and stick_turret.length() > 0.08:
		inp = stick_turret
		var grip: VRControl.TwoAxisGrip = cockpit["controls"]["grip"]
		grip.pivot.rotation = Vector3(inp.y * 0.28, 0, -inp.x * 0.28)
	if not battery_on or not Game.alive:
		inp = Vector2.ZERO
	turret.rotation.y += -inp.x * Tune.v("turret_slew") * delta
	gun_elev = clampf(gun_elev + inp.y * 0.5 * delta, GUN_EL_MIN, GUN_EL_MAX)
	gun_pivot.rotation.x = gun_elev
	turret_p.volume_db = -14.0 if inp.length() > 0.1 else -80.0
	turret_p.pitch_scale = 0.9 + inp.length() * 0.3

func _update_weapons(delta: float) -> void:
	rocket_cool -= delta
	mg_timer -= delta
	var mg_btn_down: bool = cockpit["controls"]["mg_btn"].is_down
	if (mg_held or mg_btn_down) and mg_timer <= 0.0 and Game.alive:
		mg_timer = MG_PERIOD
		_fire_mg()
	if auto_reload and not loaded:
		auto_reload_t -= delta
		if auto_reload_t <= 0.0 and ammo > 0:
			_chamber()

func fire_primary() -> void:
	# rig-facing alias: trigger while holding the turret grip
	fire_cannon(false)

func fire_cannon(from_stick := false) -> void:
	if not Game.alive:
		return
	if puppet:
		# gunner client: host is authoritative, but give local feedback —
		# `loaded` is mirrored by the coop snapshot
		if not loaded:
			Sfx.play_at("click", muzzle.global_position, -6.0)
			if Game.help_on:
				cockpit["labels"]["hint"].text = "PULL RED BREECH LEVER TO RELOAD"
		NetManager.c_event.rpc_id(1, "fire")
		return
	if not loaded:
		Sfx.play_at("click", muzzle.global_position, -6.0)
		if _hint_stage >= 3 and Game.help_on:
			cockpit["labels"]["hint"].text = "PULL RED BREECH LEVER TO RELOAD"
		return
	loaded = false
	if from_stick:
		auto_reload = true
		auto_reload_t = 2.6
	else:
		auto_reload = false
	var dir := -muzzle.global_transform.basis.z
	Game.make_noise()
	projectiles.fire(Projectiles.Kind.SHELL, muzzle.global_position, dir * SHELL_SPEED + velocity, [get_rid()], true)
	NetManager.broadcast_shot(Projectiles.Kind.SHELL, muzzle.global_position, dir * SHELL_SPEED + velocity)
	NetManager.versus_shot(Projectiles.Kind.SHELL, muzzle.global_position, dir * SHELL_SPEED + velocity)
	fx.muzzle_flash(muzzle.global_position + dir * 0.5, 1.6)
	Sfx.play_at("cannon", muzzle.global_position, 4.0)
	_set_lamp("reload", true)
	# recoil kick
	var tw := create_tween()
	tw.tween_property(recoil, "position:z", 0.17, 0.05)
	tw.tween_property(recoil, "position:z", 0.0, 0.35).set_ease(Tween.EASE_OUT)
	_rumble(0.9, 0.12)

func fire_rockets() -> void:
	if puppet:
		NetManager.c_event.rpc_id(1, "rockets")
		return
	if not Game.alive or not rockets_armed or rocket_cool > 0.0 or rockets_left <= 0:
		if not rockets_armed:
			Sfx.play_at("click", global_position, -6.0)
		return
	rocket_cool = ROCKET_COOLDOWN
	for i in 2:
		if rockets_left <= 0:
			break
		rockets_left -= 1
		var pod := pod_l if (rockets_left % 2 == 0) else pod_r
		var dir := -gun_pivot.global_transform.basis.z
		var pos := pod.global_position
		# slight delay on second rocket via deferred timer
		var launch := func():
			var rvel := dir * 45.0 + Vector3(0, 2.0, 0) + velocity
			projectiles.fire(Projectiles.Kind.ROCKET, pos, rvel, [get_rid()], true)
			NetManager.broadcast_shot(Projectiles.Kind.ROCKET, pos, rvel)
			NetManager.versus_shot(Projectiles.Kind.ROCKET, pos, rvel)
			fx.muzzle_flash(pos, 0.9)
			Sfx.play_at("rocket", pos, 2.0)
		if i == 0:
			launch.call()
		else:
			get_tree().create_timer(0.14).timeout.connect(launch)
	cockpit["labels"]["rockets"].text = "RKT %d" % rockets_left
	_rumble(0.5, 0.1)

func _fire_mg() -> void:
	var dir := -coax.global_transform.basis.z
	dir = dir.rotated(Vector3.UP, Game.rng.randf_range(-0.008, 0.008))
	dir = dir.rotated(coax.global_transform.basis.x.normalized(), Game.rng.randf_range(-0.008, 0.008))
	projectiles.fire(Projectiles.Kind.MG, coax.global_position, dir * 220.0, [get_rid()], true)
	Sfx.play_at("mg", coax.global_position, -4.0)
	_rumble(0.15, 0.03)

var _rumble_cb: Callable = Callable()
func _rumble(amp: float, dur: float) -> void:
	if _rumble_cb.is_valid():
		_rumble_cb.call(amp, dur)

func take_damage(amount: float, at: Vector3) -> void:
	if not Game.alive or puppet:
		return
	Game.damage_player(amount)
	Sfx.play_at("hit", at, 2.0)
	fx.muzzle_flash(turret.to_global(Vector3(-0.28, 0.1, 0.0)), 0.35)  # interior spark flash
	_rumble(0.8, 0.2)
	if amount > 12.0:
		Sfx.vo("vo_hit", 2, 14.0)
	if Game.hp < 30.0:
		_set_lamp("low_hull", true)
		alarm_p.volume_db = -10.0
		Sfx.vo("vo_hull_low", 3, 25.0)
	elif Game.alive:
		_set_lamp("low_hull", false)

func _update_gauges(delta: float) -> void:
	var needles: Dictionary = cockpit["needles"]
	var kmh := absf(_spd) * 3.6
	_needle(needles["speed"], kmh / 40.0)
	var rpm := (0.22 + absf(_spd) / MAX_TRACK * 0.55) if engine_on else 0.0
	if starting:
		rpm = 0.15
	_needle(needles["rpm"], rpm)
	_needle(needles["fuel"], fuel / 100.0)
	_needle(needles["temp"], temp)
	needles["azimuth"].rotation.z = turret.rotation.y

func _needle(pivot: Node3D, frac: float) -> void:
	frac = clampf(frac, 0.0, 1.0)
	pivot.rotation.z = deg_to_rad(-(225.0 + 270.0 * frac))

func _update_hints() -> void:
	if not Game.alive:
		return
	var hint: Label3D = cockpit["labels"]["hint"]
	if not Game.help_on:
		# veteran mode: no written coaching (game-over handle text still shows)
		if _hint_stage < 90:
			_hint_stage = 90
			hint.text = ""
		return
	match _hint_stage:
		0:
			hint.text = "FLIP BATTERY SWITCH (LEFT CONSOLE)"
			if battery_on:
				_hint_stage = 1
		1:
			hint.text = "OPEN FUEL PUMP COVER + FLIP THE SWITCH"
			if fuel_on:
				_hint_stage = 2
		2:
			hint.text = "HOLD GREEN STARTER BUTTON"
			if engine_on:
				_hint_stage = 3
		3:
			hint.text = "SHIFT GEAR LEVER TO 'D' (RIGHT PEDESTAL)"
			if gear != 0:
				_hint_stage = 4
		4:
			hint.text = "GRAB TILLERS TO DRIVE — GRIP STICK + TRIGGER TO FIRE"
			if absf(_spd) > 2.0:
				_hint_stage = 5
		5:
			_hint_t += get_physics_process_delta_time()
			hint.text = "ROCKETS: OPEN RED COVER, FLIP ARM, PRESS THE BUTTON"
			if _hint_t > 11.0 or rockets_left < 12:
				_hint_stage = 6
				_hint_t = 0.0
		6:
			_hint_t += get_physics_process_delta_time()
			hint.text = "RADIO KNOB = MUSIC  ·  X BUTTON = QUICK-START"
			if _hint_t > 9.0:
				_hint_stage = 7
		7:
			hint.text = ""
			_hint_stage = 8

func _update_reticle() -> void:
	var from := muzzle.global_position
	var dir := -muzzle.global_transform.basis.z
	var dist := 400.0
	# analytic terrain march
	var t := 10.0
	while t < 400.0:
		var p := from + dir * t
		if p.y < terrain.height(p.x, p.z):
			dist = t
			break
		t += 12.0
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * dist, 1 | 4, [get_rid()])
	var res := get_world_3d().direct_space_state.intersect_ray(q)
	var hit := from + dir * dist
	if res:
		hit = res.position
	reticle.global_position = hit
	var d := from.distance_to(hit)
	reticle.scale = Vector3.ONE * clampf(d * 0.035, 0.35, 12.0)

# ---- stick fallback API (called by rigs)
func set_stick_drive(v: Vector2) -> void:
	stick_drive = v

func set_stick_turret(v: Vector2) -> void:
	stick_turret = v

func stick_fire() -> void:
	fire_cannon(true)

func set_mg(held: bool) -> void:
	mg_held = held

func stick_rockets() -> void:
	var c: Dictionary = cockpit["controls"]
	if not c["rocket_cover"].open:
		c["rocket_cover"].poke_check(c["rocket_cover"].global_position, 1.0)  # force open
	if not rockets_armed:
		c["rocket_arm"].enabled = true
		c["rocket_arm"].flip()
	fire_rockets()

func quick_start() -> void:
	# stick users: L-stick click runs the whole start ritual
	var c: Dictionary = cockpit["controls"]
	if not battery_on:
		c["battery"].flip()
	if not c["fuel_cover"].open:
		c["fuel_cover"].open = true
		c["fuel_cover"].lid.rotation.x = deg_to_rad(-115.0)
		c["fuel_pump"].enabled = true
	if not fuel_on:
		c["fuel_pump"].flip()
	if gear == 0:
		c["gear"].value = 1.0
	if not engine_on and not starting:
		_begin_start()

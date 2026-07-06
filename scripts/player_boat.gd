# Player gunboat: PT-boat with a physical helm (grip the wheel column),
# throttle lever, bow deck gun, and rocket rack. Water-native — on land it
# scrapes along slowly like a beached hovercraft so no level soft-locks.
class_name PlayerBoat
extends CharacterBody3D

const WATERLINE := -0.55

var terrain: Terrain
var projectiles: Projectiles
var fx: FxPool
var cockpit: Dictionary = {}

var throttle := 0.0          # -0.3..1
var rudder := 0.0            # -1..1
var stick_drive := Vector2.ZERO
var stick_turret := Vector2.ZERO
var gun_yaw := 0.0
var gun_pitch := 0.05
var mg_held := false
var mg_timer := 0.0
var rocket_cool := 0.0
var yaw := PI
var spd := 0.0
var _bob_t := 0.0
var _rumble_cb: Callable = Callable()
var engine_p: AudioStreamPlayer3D
var gun_pivot: Node3D
var speed_label: Label3D

func _init(t: Terrain, p: Projectiles, f: FxPool) -> void:
	terrain = t
	projectiles = p
	fx = f
	name = "PlayerBoat"
	collision_layer = 2
	collision_mask = 0
	add_to_group("player")

func _ready() -> void:
	_build()
	engine_p = Sfx.make_loop_player("jeep_loop", self, -4.0, 10.0)
	engine_p.pitch_scale = 0.6
	engine_p.play()
	Game.game_restarted.connect(_respawn)
	_respawn()

func _respawn() -> void:
	yaw = PI
	spd = 0.0
	# put to sea: nearest water to the spawn point, else stay beached
	var sp := Vector2(terrain.spawn.x, terrain.spawn.y)
	var best := sp
	var found := false
	for r in [20.0, 40.0, 70.0, 110.0, 160.0, 210.0]:
		for i in 16:
			var a := TAU * i / 16.0
			var c: Vector2 = sp + Vector2(cos(a), sin(a)) * float(r)
			if terrain.height(c.x, c.y) < -1.6:
				best = c
				found = true
				break
		if found:
			break
	global_position = Vector3(best.x, WATERLINE - 0.1, best.y)
	if not found:
		global_position.y = terrain.height(best.x, best.y) + 0.3
	basis = Basis(Vector3.UP, yaw)

func _build() -> void:
	var st := MeshKit.begin()
	var hull := Color(0.34, 0.38, 0.33)
	var deck := Color(0.52, 0.46, 0.36)
	MeshKit.box(st, Transform3D(Basis(), Vector3(0, 0.35, 0.4)), Vector3(2.2, 0.9, 6.2), hull)
	MeshKit.prism(st, Transform3D(Basis(Vector3.UP, PI / 2), Vector3(0, 0.79, -3.7)), 1.7, 2.2, 0.55, hull)
	MeshKit.box(st, Transform3D(Basis(), Vector3(0, 0.84, 0.4)), Vector3(2.0, 0.1, 5.9), deck)
	# gunwales
	for sx in [-1.05, 1.05]:
		MeshKit.box(st, Transform3D(Basis(), Vector3(sx, 1.05, 0.4)), Vector3(0.1, 0.35, 6.0), hull * 0.9)
	MeshKit.box(st, Transform3D(Basis(), Vector3(0, 1.05, 3.4)), Vector3(2.2, 0.35, 0.1), hull * 0.9)
	var mi := MeshInstance3D.new()
	mi.mesh = MeshKit.commit(st, MeshKit.mat_vcol(0.75))
	add_child(mi)
	# bow deck gun on a pivot (aims via right stick / grip)
	gun_pivot = Node3D.new()
	gun_pivot.position = Vector3(0, 1.1, -2.1)
	add_child(gun_pivot)
	var gst := MeshKit.begin()
	MeshKit.cyl(gst, Transform3D(Basis(), Vector3(0, 0.0, 0)), 0.35, 0.3, 0.5, 8, Color(0.3, 0.32, 0.3))
	MeshKit.cyl(gst, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(94)), Vector3(0, 0.18, -1.0)), 0.07, 0.055, 1.9, 6, Color(0.18, 0.2, 0.2))
	var gmesh := MeshInstance3D.new()
	gmesh.mesh = MeshKit.commit(gst, MeshKit.mat_vcol(0.7))
	gun_pivot.add_child(gmesh)
	# ---- helm console
	var root := Node3D.new()
	root.position = Vector3(0, 1.0, 1.3)
	add_child(root)
	var cst := MeshKit.begin()
	MeshKit.box(cst, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-16)), Vector3(0, 0.12, -0.32)), Vector3(1.2, 0.42, 0.08), Color(0.16, 0.18, 0.17))
	MeshKit.box(cst, Transform3D(Basis(), Vector3(0, -0.35, -0.25)), Vector3(1.1, 0.6, 0.5), Color(0.2, 0.22, 0.2))
	var cmesh := MeshInstance3D.new()
	cmesh.mesh = MeshKit.commit(cst, MeshKit.mat_vcol(0.8))
	root.add_child(cmesh)
	# helm: two-axis grip — x = rudder (grab and swing like a wheel)
	var helm := VRControl.TwoAxisGrip.create()
	helm.position = Vector3(0.22, 0.32, -0.28)
	root.add_child(helm)
	helm.deflection_changed.connect(func(v: Vector2) -> void: rudder = clampf(v.x * 1.6, -1.0, 1.0))
	# throttle lever (left of the console)
	var thr := VRControl.Lever.create(0.26, Color(0.75, 0.2, 0.12), 40.0, false)
	thr.position = Vector3(-0.4, 0.25, -0.22)
	root.add_child(thr)
	thr.value_changed.connect(func(v: float) -> void: throttle = clampf(v, -0.3, 1.0))
	# rocket button
	var rkt := VRControl.PushButton.create(Color(0.85, 0.12, 0.1), 0.03)
	rkt.position = Vector3(0.45, 0.28, -0.26)
	root.add_child(rkt)
	rkt.pressed.connect(fire_rockets)
	# gunwale grab-rail lever — vault over the side to go on-foot mid-mission
	var hatch := VRControl.Lever.create(0.18, Color(0.85, 0.72, 0.15), 42.0, false)
	hatch.position = Vector3(-0.55, 0.05, -0.3)
	hatch.rotation.z = deg_to_rad(90)
	root.add_child(hatch)
	hatch.value_changed.connect(_on_hatch_lever)
	speed_label = Label3D.new()
	speed_label.text = "0 KTS"
	speed_label.font_size = 56
	speed_label.pixel_size = 0.00035
	speed_label.modulate = Color(0.5, 0.95, 0.6)
	speed_label.position = Vector3(-0.02, 0.35, -0.35)
	speed_label.rotation.x = deg_to_rad(-16)
	root.add_child(speed_label)
	if Game.help_on:
		var hint := Label3D.new()
		hint.text = "THROTTLE OR RIGHT TRIGGER · GRAB WHEEL TO STEER · STICK AIMS GUN · RED = ROCKETS"
		hint.font_size = 44
		hint.pixel_size = 0.0003
		hint.modulate = Color(1.0, 0.8, 0.35)
		hint.position = Vector3(0, 0.62, -0.4)
		root.add_child(hint)
	CockpitBuilder.set_interior_layer(root)
	var seat := Node3D.new()
	seat.position = Vector3(0, -0.25, 0.75)
	root.add_child(seat)
	cockpit = {"seat_anchor": seat, "eye_local": Vector3(0, 0.85, -0.05), "controls": {}}

func _physics_process(delta: float) -> void:
	_bob_t += delta
	var gp := global_position
	var h := terrain.height(gp.x, gp.z)
	var afloat := h < -0.9
	# stick fallback: forward = throttle, x = rudder
	var thr_in := maxf(throttle, 0.0) + maxf(stick_drive.y, 0.0)
	# stick_drive.x arrives PRE-NEGATED by xr_rig (tank convention: it sends
	# -ls.x). `yaw -= rud_in` means positive rud_in turns right, so un-negate
	# here or stick-right turns the boat left (Alex, live: "left thumbstick
	# rotate (X) is backwards... It's correct with tank").
	var rud_in := clampf(rudder - stick_drive.x, -1.0, 1.0)
	var max_spd := (Tune.v("boat_speed") if afloat else 4.0) * Game.speed_scale()
	spd = move_toward(spd, clampf(thr_in, -0.3, 1.0) * max_spd, (5.0 if afloat else 8.0) * delta)
	yaw -= rud_in * clampf(spd / 6.0, 0.15, 1.0) * 0.9 * delta
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	# tanks refuse deep water; boats refuse... nothing. Beaching just slows.
	global_position += fwd * spd * delta
	if afloat:
		global_position.y = WATERLINE - 0.05 + sin(_bob_t * 1.5) * 0.06
		rotation.z = sin(_bob_t * 1.1) * 0.02 - rud_in * clampf(spd / 12.0, 0.0, 1.0) * 0.06
		if spd > 6.0 and Game.rng.randf() < delta * 6.0:
			fx.dust(global_position + fwd * -3.2, 0.8)
	else:
		global_position.y = move_toward(gp.y, h + 0.3, 4.0 * delta)
		if spd > 1.5 and Game.rng.randf() < delta * 4.0:
			fx.dust(global_position, 1.0)
	basis = Basis(Vector3.UP, yaw)
	engine_p.pitch_scale = 0.5 + absf(spd) / 18.0
	speed_label.text = "%d KTS%s" % [int(absf(spd) * 1.94), "" if afloat else "  AGROUND"]
	# deck gun aim
	# +Y node rotation is a LEFT turn in Godot, so stick-right must subtract
	# (Alex: "on gunboat right thumbstick X is backwards (yaw)")
	gun_yaw = clampf(gun_yaw - stick_turret.x * 1.8 * delta, -2.4, 2.4)
	gun_pitch = clampf(gun_pitch + stick_turret.y * 1.0 * delta, -0.05, 0.55)
	gun_pivot.rotation = Vector3(gun_pitch, gun_yaw, 0)
	if mg_held:
		mg_timer -= delta
		if mg_timer <= 0.0:
			mg_timer = 0.09
			var mpos := gun_pivot.to_global(Vector3(0, 0.18, -1.6))
			var dir := -gun_pivot.global_transform.basis.z
			projectiles.fire(Projectiles.Kind.MG, mpos, dir * 210.0, [get_rid()], true)
			Sfx.play_at("mg", mpos, -8.0)
			Game.make_noise()
	rocket_cool = maxf(rocket_cool - delta, 0.0)

func fire_primary() -> void:
	if not Game.alive:
		return
	var mpos := gun_pivot.to_global(Vector3(0, 0.18, -2.0))
	var dir := -gun_pivot.global_transform.basis.z
	projectiles.fire(Projectiles.Kind.SHELL, mpos, dir * 85.0 + velocity, [get_rid()], true)
	fx.muzzle_flash(mpos, 1.3)
	Sfx.play_at("cannon", mpos, -2.0, 1.1)
	Game.make_noise()
	if _rumble_cb.is_valid():
		_rumble_cb.call(0.7, 0.15)

func fire_rockets() -> void:
	if rocket_cool > 0.0 or not Game.alive:
		return
	rocket_cool = 2.2
	for i in 2:
		var mpos := to_global(Vector3(-0.5 + i * 1.0, 1.3, 0.6))
		var dir := -gun_pivot.global_transform.basis.z
		projectiles.fire(Projectiles.Kind.ROCKET, mpos, dir * 55.0 + Vector3.UP * 8.0, [get_rid()], true)
		Sfx.play_at("rocket", mpos, -2.0)
	Game.make_noise()

func take_damage(amount: float, at: Vector3) -> void:
	Game.damage_player(amount)
	Sfx.play_at("hit", at, -4.0)
	if _rumble_cb.is_valid():
		_rumble_cb.call(0.5, 0.2)

# rig hooks
func set_stick_drive(v: Vector2) -> void: stick_drive = v
func set_stick_turret(v: Vector2) -> void: stick_turret = v
func stick_fire() -> void: fire_primary()
func stick_rockets() -> void: fire_rockets()
func set_mg(h: bool) -> void: mg_held = h
func quick_start() -> void: pass

func _on_hatch_lever(v: float) -> void:
	if absf(v) > 0.8 and Game.player_mode == Game.PlayerMode.SEATED:
		var m := get_tree().get_first_node_in_group("main")
		if m:
			m.call_deferred("exit_vehicle")

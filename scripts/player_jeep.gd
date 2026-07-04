# Player jeep: fast open-top 4x4 with a rear-mounted tank gun (Alex:
# "gotta drive! can have a tank gun in the back"). Terrain-hugging like the
# enemy jeep (height sample + normal tilt), roughly twice tank speed.
# Physical controls: steering wheel (two-axis grip), throttle lever, red
# fire button; everything mirrored on thumbsticks like every other vehicle.
class_name PlayerJeep
extends CharacterBody3D

const MAX_SPEED := 17.0        # m/s (~38 mph) — fast, that's the point
const REVERSE_FRAC := 0.4

var terrain: Terrain
var projectiles: Projectiles
var fx: FxPool
var cockpit: Dictionary = {}

var throttle := 0.0            # -0.4..1 from the physical lever
var steer := 0.0               # -1..1 from the wheel
var stick_drive := Vector2.ZERO
var stick_turret := Vector2.ZERO
var gun_yaw := PI              # rear gun starts aimed rearward, full 360 traverse
var gun_pitch := 0.06
var mg_held := false
var mg_timer := 0.0
var cannon_cool := 0.0
var yaw := PI
var spd := 0.0
var _rumble_cb: Callable = Callable()
var engine_p: AudioStreamPlayer3D
var gun_pivot: Node3D
var speed_label: Label3D

func _init(t: Terrain, p: Projectiles, f: FxPool) -> void:
	terrain = t
	projectiles = p
	fx = f
	name = "PlayerJeep"
	collision_layer = 2
	collision_mask = 0
	add_to_group("player")

func _ready() -> void:
	_build()
	engine_p = Sfx.make_loop_player("jeep_loop", self, -4.0, 10.0)
	engine_p.play()
	Game.game_restarted.connect(_respawn)
	_respawn()

func _respawn() -> void:
	yaw = PI
	spd = 0.0
	var sp := terrain.spawn
	global_position = Vector3(sp.x, terrain.height(sp.x, sp.y) + 0.35, sp.y)
	basis = Basis(Vector3.UP, yaw)

func _build() -> void:
	var st := MeshKit.begin()
	var body := Color(0.30, 0.32, 0.24)   # olive, pre-darkened for sky ambient
	var dark := Color(0.14, 0.14, 0.15)
	# tub + hood + windshield frame (open top — the driver IS visible)
	MeshKit.box(st, Transform3D(Basis(), Vector3(0, 0.72, 0.2)), Vector3(1.8, 0.5, 3.6), body)
	MeshKit.box(st, Transform3D(Basis(), Vector3(0, 0.95, -1.35)), Vector3(1.7, 0.32, 0.9), body * 0.95)
	# open windshield FRAME (posts + top bar) — a solid slab reads as a
	# blacked-out window from the seat
	for wx in [-0.78, 0.78]:
		MeshKit.box(st, Transform3D(Basis(Vector3.RIGHT, -0.35), Vector3(wx, 1.28, -0.85)), Vector3(0.06, 0.5, 0.06), Color(0.22, 0.26, 0.3))
	MeshKit.box(st, Transform3D(Basis(Vector3.RIGHT, -0.35), Vector3(0, 1.5, -0.93)), Vector3(1.6, 0.06, 0.06), Color(0.22, 0.26, 0.3))
	# wheels
	for sx in [-0.92, 0.92]:
		for sz in [-1.15, 1.25]:
			MeshKit.cyl(st, Transform3D(Basis(Vector3(0, 0, 1), PI / 2), Vector3(sx, 0.42, sz)), 0.42, 0.42, 0.34, 10, dark)
	# rear gun ring pedestal
	MeshKit.cyl(st, Transform3D(Basis(), Vector3(0, 1.02, 1.1)), 0.5, 0.55, 0.12, 12, body * 0.85)
	var mi := MeshInstance3D.new()
	mi.mesh = MeshKit.commit(st, MeshKit.mat_vcol(0.8))
	add_child(mi)
	# rear tank gun on a full-traverse pivot
	gun_pivot = Node3D.new()
	# high enough that the barrel clears the driver's head (eye y=1.32)
	gun_pivot.position = Vector3(0, 1.55, 1.1)
	add_child(gun_pivot)
	var gst := MeshKit.begin()
	MeshKit.box(gst, Transform3D(Basis(), Vector3(0, 0.05, 0.25)), Vector3(0.4, 0.32, 0.7), Color(0.32, 0.34, 0.3))
	MeshKit.cyl(gst, Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(0, 0.08, -1.3)), 0.075, 0.06, 2.6, 8, Color(0.24, 0.26, 0.23))
	MeshKit.cyl(gst, Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(0, 0.08, -2.5)), 0.1, 0.1, 0.3, 8, Color(0.2, 0.22, 0.2))
	var gmesh := MeshInstance3D.new()
	gmesh.mesh = MeshKit.commit(gst, MeshKit.mat_vcol(0.7))
	gun_pivot.add_child(gmesh)
	# ---- driver's station
	var root := Node3D.new()
	root.position = Vector3(-0.42, 1.05, -0.35)
	add_child(root)
	var cst := MeshKit.begin()
	MeshKit.box(cst, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-20)), Vector3(0, -0.06, -0.3)), Vector3(0.8, 0.22, 0.06), Color(0.16, 0.18, 0.17))
	var cmesh := MeshInstance3D.new()
	cmesh.mesh = MeshKit.commit(cst, MeshKit.mat_vcol(0.8))
	root.add_child(cmesh)
	# steering wheel: two-axis grip, x = steer
	var wheel := VRControl.TwoAxisGrip.create()
	wheel.position = Vector3(0.0, 0.16, -0.3)
	root.add_child(wheel)
	wheel.deflection_changed.connect(func(v: Vector2) -> void: steer = clampf(v.x * 1.6, -1.0, 1.0))
	# throttle lever
	var thr := VRControl.Lever.create(0.22, Color(0.75, 0.2, 0.12), 40.0, false)
	thr.position = Vector3(0.42, 0.1, -0.22)
	root.add_child(thr)
	thr.value_changed.connect(func(v: float) -> void: throttle = clampf(v, -REVERSE_FRAC, 1.0))
	# cannon fire button
	var fireb := VRControl.PushButton.create(Color(0.85, 0.12, 0.1), 0.03)
	fireb.position = Vector3(0.62, 0.12, -0.24)
	root.add_child(fireb)
	fireb.pressed.connect(fire_primary)
	# door-rail exit lever
	var hatch := VRControl.Lever.create(0.18, Color(0.85, 0.72, 0.15), 42.0, false)
	hatch.position = Vector3(-0.35, -0.05, -0.25)
	hatch.rotation.z = deg_to_rad(90)
	root.add_child(hatch)
	hatch.value_changed.connect(_on_hatch_lever)
	speed_label = Label3D.new()
	speed_label.text = "0 MPH"
	speed_label.font_size = 56
	speed_label.pixel_size = 0.00035
	speed_label.modulate = Color(0.5, 0.95, 0.6)
	speed_label.position = Vector3(0.0, 0.28, -0.34)
	speed_label.rotation.x = deg_to_rad(-20)
	root.add_child(speed_label)
	if Game.help_on:
		var hint := Label3D.new()
		hint.text = "GRAB WHEEL TO STEER · THROTTLE RIGHT · RIGHT STICK AIMS REAR GUN · TRIGGER = CANNON"
		hint.font_size = 44
		hint.pixel_size = 0.0003
		hint.modulate = Color(1.0, 0.8, 0.35)
		hint.position = Vector3(0, 0.55, -0.4)
		root.add_child(hint)
	CockpitBuilder.set_interior_layer(root)
	var seat := Node3D.new()
	seat.position = Vector3(0.0, -0.45, 0.35)
	root.add_child(seat)
	cockpit = {"seat_anchor": seat, "eye_local": Vector3(0, 0.72, 0), "controls": {}}

func _physics_process(delta: float) -> void:
	var gp := global_position
	# stick fallback: y = throttle (up forward, down reverse), x = steer.
	# stick_drive.x arrives PRE-NEGATED by xr_rig (tank convention: -ls.x);
	# `yaw -= steer_in` turns right for positive steer_in, so un-negate here
	# — same sign rule the boat/heli needed (2026-07-04).
	var thr_in := clampf(throttle + stick_drive.y, -REVERSE_FRAC, 1.0)
	var steer_in := clampf(steer - stick_drive.x, -1.0, 1.0)
	var max_spd := MAX_SPEED * Game.speed_scale() * Levels.mud_factor(gp)
	spd = move_toward(spd, thr_in * max_spd, 9.0 * delta)
	# steering authority scales with speed; flips in reverse like a real car
	yaw -= steer_in * clampf(absf(spd) / 5.0, 0.1, 1.0) * 1.1 * signf(spd if absf(spd) > 0.3 else 1.0) * delta
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	global_position += fwd * spd * delta
	var target_y := terrain.height(global_position.x, global_position.z) + 0.05
	global_position.y = move_toward(gp.y, target_y, 24.0 * delta)
	# hug the slope, like the enemy jeep
	var n := terrain.normal(global_position.x, global_position.z)
	var right := fwd.cross(n).normalized() * -1.0
	var fdir := n.cross(right).normalized() * -1.0
	basis = basis.slerp(Basis(right * -1.0, n, fdir * -1.0).orthonormalized(), clampf(8.0 * delta, 0.0, 1.0)).orthonormalized()
	velocity = fwd * spd   # for exit-airborne checks / netcode readers
	engine_p.pitch_scale = 0.8 + absf(spd) / 14.0
	speed_label.text = "%d MPH" % int(absf(spd) * 2.237)
	if absf(spd) > 8.0 and Game.rng.randf() < delta * 5.0:
		fx.dust(global_position - fwd * 2.0, 0.9)
	# rear gun aim (same fixed sign rules as the boat's deck gun)
	gun_yaw = wrapf(gun_yaw - stick_turret.x * 2.0 * delta, -PI, PI)
	gun_pitch = clampf(gun_pitch + stick_turret.y * 1.0 * delta, -0.05, 0.5)
	gun_pivot.rotation = Vector3(gun_pitch, gun_yaw, 0)
	if mg_held:
		mg_timer -= delta
		if mg_timer <= 0.0:
			mg_timer = 0.09
			var mpos := gun_pivot.to_global(Vector3(0.18, 0.08, -0.9))
			var dir := -gun_pivot.global_transform.basis.z
			projectiles.fire(Projectiles.Kind.MG, mpos, dir * 210.0, [get_rid()], true)
			Sfx.play_at("mg", mpos, -8.0)
			Game.make_noise()
	cannon_cool = maxf(cannon_cool - delta, 0.0)

func fire_primary() -> void:
	if cannon_cool > 0.0 or not Game.alive:
		return
	cannon_cool = 1.6
	var mpos := gun_pivot.to_global(Vector3(0, 0.08, -2.7))
	var dir := -gun_pivot.global_transform.basis.z
	projectiles.fire(Projectiles.Kind.SHELL, mpos, dir * 95.0 + velocity, [get_rid()], true)
	fx.muzzle_flash(mpos, 1.4)
	Sfx.play_at("cannon", mpos, -2.0, 1.05)
	Game.make_noise()
	if _rumble_cb.is_valid():
		_rumble_cb.call(0.8, 0.15)

func take_damage(amount: float, at: Vector3) -> void:
	Game.damage_player(amount)
	Sfx.play_at("hit", at, -4.0)
	if _rumble_cb.is_valid():
		_rumble_cb.call(0.5, 0.2)

# rig hooks
func set_stick_drive(v: Vector2) -> void: stick_drive = v
func set_stick_turret(v: Vector2) -> void: stick_turret = v
func stick_fire() -> void: fire_primary()
func stick_rockets() -> void: fire_primary()
func set_mg(h: bool) -> void: mg_held = h
func quick_start() -> void: pass

func _on_hatch_lever(v: float) -> void:
	if absf(v) > 0.8 and Game.player_mode == Game.PlayerMode.SEATED:
		var m := get_tree().get_first_node_in_group("main")
		if m:
			m.call_deferred("exit_vehicle")

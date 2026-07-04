# Mid-mission plane/biplane bail-out: cockpit ejection (plane) or a bare
# fall (biplane), then a player-deployed parachute. Alex, live headset:
# "if I exit from a plane I should get a cockpit ejection then a parachute.
# Biplane I should just be falling out and then using parachute (deploy
# when falling with trigger or by pulling from your chest out)."
#
# Built as a "vehicle" in the same sense as PlayerTank/PlayerPlane/Heli —
# it exposes seat_anchor/eye_local so xr_rig.gd's existing attach_to_vehicle()
# seat mechanism just works unmodified, and it exposes the same rig-facing
# input API (set_stick_drive/stick_fire/etc.) so the existing seated-input
# code in xr_rig.gd's _physics_process (right trigger with no grip held ->
# stick_fire()) becomes the parachute's deploy trigger for free — no changes
# needed in xr_rig.gd for that path. The chest-pull gesture is checked here
# directly against the rig's own hand positions (see _check_chest_pull()).
class_name PlayerParachute
extends CharacterBody3D

var terrain: Terrain
var projectiles: Projectiles
var fx: FxPool
var cockpit: Dictionary = {}

var ejected := false        # true = plane (scripted eject pop), false = biplane (bare fall)
var deployed := false
var _eject_t := 0.0
const EJECT_DUR := 0.55
var _rumble_cb: Callable = Callable()
var _rig: Node = null

var canopy: Node3D
var _canopy_scale := 0.0    # 0 = packed, 1 = fully open (lerped visual)
var stick_fallback := Vector2.ZERO
var drift := Vector2.ZERO

# fall tuning
const FALL_G := 22.0
const TERMINAL_V := 42.0
const CHUTE_G := 3.0
const CHUTE_TERMINAL_V := 5.5
const CHUTE_DRIFT_SPEED := 6.0

func _init(t: Terrain, p: Projectiles, f: FxPool) -> void:
	terrain = t
	projectiles = p
	fx = f
	name = "PlayerParachute"
	collision_layer = 2
	collision_mask = 0
	add_to_group("player")

func _ready() -> void:
	_build()

# Called by main.exit_vehicle_airborne() right after construction, with the
# plane's position/basis/velocity at the moment of hatch-pull so the fall
# starts from exactly where the pilot left the cockpit, not a teleport.
func launch(from_transform: Transform3D, plane_velocity: Vector3, is_ejected: bool) -> void:
	global_transform = from_transform
	ejected = is_ejected
	if ejected:
		_eject_t = EJECT_DUR
		# scripted "punched out of the cockpit" pop: up and back, clear of the
		# fuselage, with a bit of tumble — not real physics, just a readable
		# beat before free-fall takes over (see _physics_process below).
		velocity = plane_velocity + (-from_transform.basis.z) * -6.0 + Vector3(0, 7.5, 0)
	else:
		# biplane: no ejection beat, you just fall out of the open seat with
		# whatever momentum the plane had.
		_eject_t = 0.0
		velocity = plane_velocity * 0.4 + Vector3(0, -1.0, 0)

func _build() -> void:
	# Minimal harness/pilot proxy — first-person players never see their own
	# body anyway (same as every other vehicle here), this only matters for
	# third-person/chase camera and for the canopy anchor above the head.
	var st := MeshKit.begin()
	MeshKit.box(st, Transform3D(Basis(), Vector3(0, 0.05, 0)), Vector3(0.34, 0.5, 0.22), Color(0.28, 0.32, 0.24))
	MeshKit.box(st, Transform3D(Basis(), Vector3(0, 0.35, 0)), Vector3(0.24, 0.24, 0.22), Color(0.85, 0.7, 0.55))
	var mi := MeshInstance3D.new()
	mi.mesh = MeshKit.commit(st, MeshKit.mat_vcol(0.8, 0.05))
	add_child(mi)

	# canopy: cone dome above the harness, packed flat (scale 0) until deploy
	canopy = Node3D.new()
	canopy.position = Vector3(0, 2.6, 0)
	canopy.scale = Vector3(0.05, 0.05, 0.05)
	add_child(canopy)
	var cst := MeshKit.begin()
	MeshKit.cyl(cst, Transform3D(Basis(), Vector3.ZERO), 2.2, 0.05, 1.6, 12, Color(0.85, 0.25, 0.2), true, false)
	# suspension lines: simple radial struts from the canopy rim down to the
	# harness point, built as small tilted cylinders (decorative only)
	for i in 6:
		var a := TAU * i / 6.0
		var rim := Vector3(cos(a) * 2.15, -0.8, sin(a) * 2.15)
		var mid := rim * 0.5
		var line_len: float = rim.length()
		var pitch := atan2(Vector2(rim.x, rim.z).length(), -rim.y)
		var yaw := atan2(rim.x, rim.z)
		var tf := Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch), mid)
		MeshKit.cyl(cst, tf, 0.012, 0.012, line_len, 4, Color(0.9, 0.88, 0.8))
	var cm := MeshInstance3D.new()
	cm.mesh = MeshKit.commit(cst, MeshKit.mat_vcol(0.85, 0.0))
	canopy.add_child(cm)

	var seat_anchor := Node3D.new()
	seat_anchor.position = Vector3(0, 0.35, 0.02)
	add_child(seat_anchor)
	cockpit = {"seat_anchor": seat_anchor, "eye_local": Vector3(0, 0.05, 0), "controls": {}}

func _physics_process(delta: float) -> void:
	if not Game.alive:
		return
	if _eject_t > 0.0:
		_eject_t -= delta
		# scripted eject arc: gravity bleeds the pop velocity naturally, no
		# player control until the beat finishes
		velocity += Vector3(0, -FALL_G, 0) * delta
		global_position += velocity * delta
		rotation.x += delta * 3.0  # tumble
		_ground_check()
		return
	if not deployed:
		# free fall: fast, no drift control, terminal velocity capped
		velocity.y = maxf(velocity.y - FALL_G * delta, -TERMINAL_V)
		velocity.x = move_toward(velocity.x, 0.0, 4.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 4.0 * delta)
		rotation.x = move_toward(rotation.x, 0.0, delta * 2.0)
		_check_chest_pull()
	else:
		# under canopy: slow descent + stick/thumbstick drift
		velocity.y = move_toward(velocity.y, -CHUTE_TERMINAL_V, CHUTE_G * delta)
		var want := drift if drift.length() > 0.05 else stick_fallback
		var target := Vector3(want.x, 0, -want.y) * CHUTE_DRIFT_SPEED
		velocity.x = move_toward(velocity.x, target.x, 3.0 * delta)
		velocity.z = move_toward(velocity.z, target.z, 3.0 * delta)
		_canopy_scale = move_toward(_canopy_scale, 1.0, delta * 2.5)
		canopy.scale = Vector3.ONE * lerpf(0.05, 1.0, _canopy_scale)
	global_position += velocity * delta
	_ground_check()

func _check_chest_pull() -> void:
	# Alternate deploy gesture: pulling a hand from near the chest outward,
	# like yanking a ripcord handle across your body — trigger-press (routed
	# from xr_rig.gd's existing seated-input path straight into stick_fire())
	# is the primary/simple path; this is the physical flourish for hand
	# tracking or anyone who'd rather not hunt for the trigger while falling.
	if _rig == null or not is_instance_valid(_rig):
		return
	var cam: Node3D = _rig.get("camera")
	if cam == null:
		return
	var chest := cam.global_position + Vector3(0, -0.35, 0)
	for hand_name in ["hand_l", "hand_r"]:
		var hand: Node3D = _rig.get(hand_name)
		if hand == null:
			continue
		var local_to_chest := chest.distance_to(hand.global_position)
		var was_near: bool = get_meta("near_%s" % hand_name, false)
		if local_to_chest < 0.22:
			set_meta("near_%s" % hand_name, true)
		elif was_near and local_to_chest > 0.55:
			# was near the chest, now pulled well clear of it -> ripcord pull
			set_meta("near_%s" % hand_name, false)
			deploy()
			return
		else:
			set_meta("near_%s" % hand_name, was_near and local_to_chest < 0.55)

func deploy() -> void:
	if deployed or _eject_t > 0.0:
		return
	deployed = true
	_canopy_scale = 0.0
	Sfx.play_at("boing", global_position, -4.0, 0.7)
	Sfx.play_at("wind_gust", global_position, -6.0)
	_rumble(0.5, 0.15)

func _ground_check() -> void:
	var gh := terrain.height(global_position.x, global_position.z)
	if global_position.y <= gh + 0.1:
		global_position.y = gh + 0.1
		_land()

func _land() -> void:
	fx.dust(global_position, 0.6 if deployed else 1.1)
	Sfx.play_at("thud", global_position, 0.0, 1.0 if deployed else 1.3)
	_rumble(0.3 if deployed else 0.8, 0.1 if deployed else 0.25)
	if not deployed:
		# hard landing without a chute — same knock as a vehicle crash, less severe
		Game.damage_player(20.0)
	var m := get_tree().get_first_node_in_group("main")
	if m:
		m.call_deferred("_land_parachute", self)

func _rumble(amp: float, dur: float) -> void:
	if _rumble_cb.is_valid():
		_rumble_cb.call(amp, dur)

func take_damage(amount: float, at: Vector3) -> void:
	if not Game.alive:
		return
	Game.damage_player(amount)
	Sfx.play_at("hit", at, 0.0)
	_rumble(0.7, 0.15)

# ---- rig-facing input API (mirrors PlayerTank/PlayerPlane)
func set_stick_drive(v: Vector2) -> void:
	stick_fallback = v

func set_stick_turret(v: Vector2) -> void:
	drift = v

func fire_primary() -> void:
	deploy()

func stick_fire() -> void:
	deploy()

func stick_rockets() -> void:
	pass

func set_mg(_held: bool) -> void:
	pass

func quick_start() -> void:
	pass

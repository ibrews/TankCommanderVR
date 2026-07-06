# Blunderbuss: 8 Kind.MG pellets per shot in a ~8-degree cone. Devastating
# inside 15m, confetti past 40 — the spread plus a low muzzle velocity
# (MG's 1.4s pool TTL caps range at ~100m) makes it the dedicated
# close-quarters answer the pistol and THR3E-FER aren't. Cabbage-merchant
# tie-in: this game's throwable IS produce, so the shotgun is the machine
# that turns cabbage into coleslaw at ballistic speed — hence the brand.
class_name SlawBlasterPickable
extends XRToolsPickable

const PELLETS := 8
const SPREAD_DEG := 8.0
const SPEED := 70.0
const COOLDOWN := 0.9

var _cool := 0.0
var _muzzle: Node3D

func _init() -> void:
	name = "SlawBlaster"
	collision_layer = 1 << 2
	collision_mask = 1 << 0
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC

func _ready() -> void:
	_build_mesh()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.06, 0.13, 0.3)
	shape.shape = box
	shape.position = Vector3(0, 0.035, -0.05)
	add_child(shape)
	super._ready()
	picked_up.connect(func(_p): Sfx.play_at("click", global_position, -6.0))
	action_pressed.connect(_on_action_pressed)

func _process(delta: float) -> void:
	_cool = maxf(0.0, _cool - delta)

func _build_mesh() -> void:
	var st := MeshKit.begin()
	var wood := Color(0.36, 0.23, 0.12)
	var brass := Color(0.65, 0.5, 0.2)
	var cabbage := Color(0.35, 0.55, 0.25)  # same green as the grenade — house colorway
	MeshKit.box(st, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-18)), Vector3(0, -0.035, 0.05)), Vector3(0.04, 0.12, 0.06), wood)
	MeshKit.box(st, Transform3D(Basis(), Vector3(0, 0.03, -0.02)), Vector3(0.042, 0.045, 0.2), wood)
	MeshKit.cyl(st, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(90)), Vector3(0, 0.035, -0.16)), 0.02, 0.02, 0.1, 8, brass)
	# the flare: cyl() cone with the WIDE end forward (blunderbuss silhouette
	# is the entire "short range, big cone" affordance)
	MeshKit.cyl(st, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-90)), Vector3(0, 0.035, -0.24)), 0.022, 0.05, 0.07, 10, brass, true, false)
	# cabbage finial on the stock — merchant-approved
	MeshKit.cyl(st, Transform3D(Basis(), Vector3(0, -0.09, 0.07)), 0.028, 0.024, 0.045, 8, cabbage)
	var mi := MeshInstance3D.new()
	mi.mesh = MeshKit.commit(st, MeshKit.mat_vcol(0.6, 0.3))
	add_child(mi)
	var brand := Label3D.new()
	brand.text = "SLAW BLASTER\n\"COLESLAW AT 60MPH\""
	brand.font_size = 24
	brand.pixel_size = 0.0009
	brand.modulate = Color(0.55, 0.85, 0.3)
	brand.outline_size = 6
	brand.outline_modulate = Color(0.1, 0.15, 0.05)
	brand.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	brand.position = Vector3(0, 0.11, -0.05)
	add_child(brand)
	_muzzle = Node3D.new()
	_muzzle.position = Vector3(0, 0.035, -0.28)
	add_child(_muzzle)

func _on_action_pressed(_p) -> void:
	if _cool > 0.0:
		return
	_cool = COOLDOWN
	var m := get_tree().get_first_node_in_group("main")
	if m == null or m.projectiles == null:
		return
	var b := _muzzle.global_transform.basis
	var exclude := []
	if m.rig is XRRig and m.rig.on_foot_body and is_instance_valid(m.rig.on_foot_body):
		exclude = [m.rig.on_foot_body.get_rid()]
	var tan_spread := tan(deg_to_rad(SPREAD_DEG))
	for i in PELLETS:
		# uniform disc scatter, not gaussian — a blunderbuss should pattern
		# like thrown slaw, edges included
		var a := Game.rng.randf() * TAU
		var r := sqrt(Game.rng.randf()) * tan_spread
		var dir := (-b.z + (b.x * cos(a) + b.y * sin(a)) * r).normalized()
		m.projectiles.fire(Projectiles.Kind.MG, _muzzle.global_position, dir * SPEED, exclude, true)
	if m.fx:
		m.fx.muzzle_flash(_muzzle.global_position, 1.0)
	Sfx.play_at("rifle", _muzzle.global_position, 1.0, 0.7)  # pitched down: boom, not crack
	var ctrl := get_picked_up_by_controller()
	if ctrl and ctrl.has_method("pulse"):
		ctrl.pulse(0.8, 0.07)

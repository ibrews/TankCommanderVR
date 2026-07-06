# Burst SMG: one trigger pull = exactly three Kind.MG rounds, 65ms apart.
# Distinct from the pistol's semi-auto tap-fire — the 2nd/3rd rounds are
# queued through _process rather than fired synchronously, so they track the
# hand's REAL position mid-burst (a swept burst feels mechanical in VR;
# three rounds from one frozen transform would just read as a triple-damage
# pistol). Branded "THR3E-FER" in the same comedic-labeling tradition as the
# cabbage merchant and SUPER FIZZ MAX.
class_name ThreeFerPickable
extends XRToolsPickable

const BURST := 3
const SHOT_GAP := 0.065
const COOLDOWN := 0.55  # between bursts, timed from the FIRST round
const SPEED := 220.0    # same round as the coax MG / pistol — shared feel
const JITTER := 0.014   # per-round scatter: bursts should stitch, not laser

var _cool := 0.0
var _burst_left := 0
var _gap := 0.0
var _muzzle: Node3D

func _init() -> void:
	name = "ThreeFer"
	collision_layer = 1 << 2
	collision_mask = 1 << 0
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC

func _ready() -> void:
	_build_mesh()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.05, 0.15, 0.2)
	shape.shape = box
	shape.position = Vector3(0, 0.03, -0.02)
	add_child(shape)
	super._ready()
	picked_up.connect(func(_p): Sfx.play_at("click", global_position, -6.0))
	action_pressed.connect(_on_action_pressed)

func _process(delta: float) -> void:
	_cool = maxf(0.0, _cool - delta)
	if _burst_left > 0:
		_gap -= delta
		if _gap <= 0.0:
			_gap = SHOT_GAP
			_burst_left -= 1
			_fire_one()

func _build_mesh() -> void:
	var st := MeshKit.begin()
	var polymer := Color(0.14, 0.15, 0.16)
	var bargain := Color(0.9, 0.55, 0.1)  # toy-orange accents: it LOOKS cheap on purpose
	MeshKit.box(st, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-10)), Vector3(0, -0.03, 0.03)), Vector3(0.034, 0.11, 0.05), polymer)
	MeshKit.box(st, Transform3D(Basis(), Vector3(0, 0.035, -0.04)), Vector3(0.036, 0.05, 0.22), polymer)
	# stick mag ahead of the grip — reads "SMG" at a glance in VR
	MeshKit.box(st, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(6)), Vector3(0, -0.03, -0.06)), Vector3(0.026, 0.11, 0.035), Color(0.2, 0.2, 0.22))
	MeshKit.cyl(st, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(90)), Vector3(0, 0.04, -0.17)), 0.012, 0.012, 0.07, 8, bargain)
	# three pips on the receiver: the whole sales pitch in one glance
	for i in 3:
		MeshKit.box(st, Transform3D(Basis(), Vector3(0.02, 0.045, -0.08 + i * 0.03)), Vector3(0.004, 0.012, 0.012), bargain)
	var mi := MeshInstance3D.new()
	mi.mesh = MeshKit.commit(st, MeshKit.mat_vcol(0.5, 0.4))
	add_child(mi)
	var brand := Label3D.new()
	brand.text = "THR3E-FER\nNOW WITH 3!"
	brand.font_size = 26
	brand.pixel_size = 0.0009
	brand.modulate = Color(1.0, 0.6, 0.1)
	brand.outline_size = 6
	brand.outline_modulate = Color(0.1, 0.1, 0.1)
	brand.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	brand.position = Vector3(0, 0.1, -0.04)
	add_child(brand)
	_muzzle = Node3D.new()
	_muzzle.position = Vector3(0, 0.04, -0.21)
	add_child(_muzzle)

func _on_action_pressed(_p) -> void:
	if _cool > 0.0 or _burst_left > 0:
		return
	_cool = COOLDOWN
	_burst_left = BURST
	_gap = 0.0  # first round lands on the very next _process tick

func _fire_one() -> void:
	var m := get_tree().get_first_node_in_group("main")
	if m == null or m.projectiles == null:
		return
	var b := _muzzle.global_transform.basis
	var dir := (-b.z + b.x * Game.rng.randf_range(-JITTER, JITTER) + b.y * Game.rng.randf_range(-JITTER, JITTER)).normalized()
	var exclude := []
	if m.rig is XRRig and m.rig.on_foot_body and is_instance_valid(m.rig.on_foot_body):
		exclude = [m.rig.on_foot_body.get_rid()]
	m.projectiles.fire(Projectiles.Kind.MG, _muzzle.global_position, dir * SPEED, exclude, true)
	if m.fx:
		m.fx.muzzle_flash(_muzzle.global_position, 0.5)
	Sfx.play_at("mg", _muzzle.global_position, -5.0, 1.15)
	var ctrl := get_picked_up_by_controller()
	if ctrl and ctrl.has_method("pulse"):
		ctrl.pulse(0.4, 0.025)

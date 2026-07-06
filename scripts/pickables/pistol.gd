# On-foot sidearm: semi-auto, fires through the SAME Projectiles system the
# tank's coax MG uses (Kind.MG — pooled tracer, ricochet/spark FX, real
# damage against "enemies"/"planes" groups) rather than a parallel damage
# model. Alex's ask (godot-xr-tools session): "picking up weapons and firing
# them... is all here" — the pickup/grab/trigger plumbing was already free
# from XRToolsPickable; only the weapon itself and its fire call were missing.
class_name PistolPickable
extends XRToolsPickable

const COOLDOWN := 0.22
const SPEED := 220.0  # matches the vehicle coax MG's muzzle velocity — same round, same feel

var _cool := 0.0
var _muzzle: Node3D

func _init() -> void:
	name = "Pistol"
	collision_layer = 1 << 2
	collision_mask = 1 << 0
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC

func _ready() -> void:
	_build_mesh()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.045, 0.14, 0.11)
	shape.shape = box
	shape.position = Vector3(0, 0.04, 0)
	add_child(shape)
	super._ready()
	picked_up.connect(func(_p): Sfx.play_at("click", global_position, -6.0))
	action_pressed.connect(_on_action_pressed)

func _process(delta: float) -> void:
	_cool = maxf(0.0, _cool - delta)

func _build_mesh() -> void:
	var st := MeshKit.begin()
	var steel := Color(0.16, 0.16, 0.17)
	MeshKit.box(st, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-12)), Vector3(0, -0.02, 0.02)), Vector3(0.032, 0.12, 0.05), Color(0.22, 0.16, 0.12))
	MeshKit.box(st, Transform3D(Basis(), Vector3(0, 0.045, -0.03)), Vector3(0.03, 0.04, 0.16), steel)
	MeshKit.cyl(st, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(90)), Vector3(0, 0.05, -0.13)), 0.011, 0.011, 0.06, 8, steel)
	var mi := MeshInstance3D.new()
	mi.mesh = MeshKit.commit(st, MeshKit.mat_vcol(0.4, 0.6))
	add_child(mi)
	_muzzle = Node3D.new()
	_muzzle.position = Vector3(0, 0.05, -0.16)
	add_child(_muzzle)

func _on_action_pressed(_p) -> void:
	if _cool > 0.0:
		return
	var m := get_tree().get_first_node_in_group("main")
	if m == null or m.projectiles == null:
		return
	# coffee pickup (scripts/pickables/coffee.gd): sharper reflexes cut the
	# semi-auto cooldown, same multiplier that speeds up the bazooka reload.
	var cooldown_mult := 1.0
	if m.rig is XRRig and m.rig.on_foot_body and is_instance_valid(m.rig.on_foot_body):
		cooldown_mult = m.rig.on_foot_body.coffee_cooldown_mult
	_cool = COOLDOWN * cooldown_mult
	var dir := -_muzzle.global_transform.basis.z
	var exclude := []
	if m.rig is XRRig and m.rig.on_foot_body and is_instance_valid(m.rig.on_foot_body):
		exclude = [m.rig.on_foot_body.get_rid()]
	m.projectiles.fire(Projectiles.Kind.MG, _muzzle.global_position, dir * SPEED, exclude, true)
	if m.fx:
		m.fx.muzzle_flash(_muzzle.global_position, 0.6)
	Sfx.play_at("mg", _muzzle.global_position, -4.0)
	var ctrl := get_picked_up_by_controller()
	if ctrl and ctrl.has_method("pulse"):
		ctrl.pulse(0.5, 0.03)

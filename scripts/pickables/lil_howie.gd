# Palm-sized howitzer: fires the tank's own Kind.SHELL (34 direct + real
# splash) on a long 1.8s cooldown — the anti-pistol. One huge round instead
# of fast follow-ups; SHELL's 3.0 gravity plus a deliberately low muzzle
# velocity gives a visible lob so it reads as artillery, not hitscan, and
# the arc IS the skill ceiling (leading + drop, no homing help). The joke is
# the scale mismatch: full cannon report, full tank-shell damage, from a
# comically small tube branded "LI'L HOWIE" (cabbage merchant / SUPER FIZZ
# MAX comedic-labeling tradition).
class_name LilHowiePickable
extends XRToolsPickable

const COOLDOWN := 1.8
const SPEED := 70.0  # slow enough that the SHELL arc is visible over 40m+

var _cool := 0.0
var _muzzle: Node3D

func _init() -> void:
	name = "LilHowie"
	collision_layer = 1 << 2
	collision_mask = 1 << 0
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC

func _ready() -> void:
	_build_mesh()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.09, 0.14, 0.2)
	shape.shape = box
	shape.position = Vector3(0, 0.03, -0.02)
	add_child(shape)
	super._ready()
	picked_up.connect(func(_p): Sfx.play_at("click", global_position, -6.0))
	action_pressed.connect(_on_action_pressed)

func _process(delta: float) -> void:
	if _cool > 0.0:
		_cool = maxf(0.0, _cool - delta)
		# audible "shell seated" when ready again — cooldown feedback without a UI
		if _cool == 0.0 and is_picked_up():
			Sfx.play_at("reload", global_position, -10.0)

func _build_mesh() -> void:
	var st := MeshKit.begin()
	var iron := Color(0.2, 0.21, 0.23)
	var wood := Color(0.32, 0.2, 0.11)
	MeshKit.box(st, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-14)), Vector3(0, -0.035, 0.03)), Vector3(0.04, 0.11, 0.055), wood)
	# fat stubby barrel — the whole gag is girth on a pistol frame
	MeshKit.cyl(st, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(90)), Vector3(0, 0.04, -0.05)), 0.038, 0.038, 0.17, 10, iron)
	# reinforcing bands like a scaled-down artillery piece
	for z in [-0.11, -0.05, 0.01]:
		MeshKit.cyl(st, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(90)), Vector3(0, 0.04, z)), 0.042, 0.042, 0.018, 10, Color(0.12, 0.12, 0.13))
	# breech bulb at the back
	MeshKit.cyl(st, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(90)), Vector3(0, 0.04, 0.045)), 0.046, 0.038, 0.05, 10, iron)
	var mi := MeshInstance3D.new()
	mi.mesh = MeshKit.commit(st, MeshKit.mat_vcol(0.45, 0.65))
	add_child(mi)
	var brand := Label3D.new()
	brand.text = "LI'L HOWIE"
	brand.font_size = 28
	brand.pixel_size = 0.0009
	brand.modulate = Color(1.0, 0.85, 0.3)
	brand.outline_size = 6
	brand.outline_modulate = Color(0.15, 0.1, 0.05)
	brand.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	brand.position = Vector3(0, 0.12, -0.03)
	add_child(brand)
	_muzzle = Node3D.new()
	_muzzle.position = Vector3(0, 0.04, -0.14)
	add_child(_muzzle)

func _on_action_pressed(_p) -> void:
	if _cool > 0.0:
		return
	_cool = COOLDOWN
	var m := get_tree().get_first_node_in_group("main")
	if m == null or m.projectiles == null:
		return
	var dir := -_muzzle.global_transform.basis.z
	var exclude := []
	if m.rig is XRRig and m.rig.on_foot_body and is_instance_valid(m.rig.on_foot_body):
		exclude = [m.rig.on_foot_body.get_rid()]
	m.projectiles.fire(Projectiles.Kind.SHELL, _muzzle.global_position, dir * SPEED, exclude, true)
	if m.fx:
		m.fx.muzzle_flash(_muzzle.global_position, 1.5)
	Sfx.play_at("cannon", _muzzle.global_position, -2.0, 1.25)  # pitched up: little gun, big bang
	var ctrl := get_picked_up_by_controller()
	if ctrl and ctrl.has_method("pulse"):
		ctrl.pulse(1.0, 0.12)  # the kick is most of the comedy

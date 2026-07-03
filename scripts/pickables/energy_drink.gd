# Energy drink prop: a one-shot consumable, not a permanent toggle. Trigger
# ("action") while held boosts OnFootBody's sprint speed for a fixed duration
# via the same get_tree().create_timer(...).timeout idiom used throughout
# player_tank.gd/main.gd, then the can is dropped and freed.
class_name EnergyDrinkPickable
extends XRToolsPickable

const DURATION := 12.0
const MULTIPLIER := 1.8

func _init() -> void:
	name = "EnergyDrink"
	collision_layer = 1 << 2   # layer 3 "Pickable Objects"
	collision_mask = 1 << 0    # layer 1 "Static World" — rests on the ground
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC

func _ready() -> void:
	_build_mesh()
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.032
	cyl.height = 0.12
	shape.shape = cyl
	shape.position = Vector3(0, 0.06, 0)
	add_child(shape)
	super._ready()
	action_pressed.connect(_on_action_pressed)

func _build_mesh() -> void:
	var st := MeshKit.begin()
	MeshKit.cyl(st, Transform3D(Basis(), Vector3(0, 0.06, 0)), 0.03, 0.032, 0.12, 8, Color(0.85, 0.72, 0.15))
	MeshKit.cyl(st, Transform3D(Basis(), Vector3(0, 0.125, 0)), 0.026, 0.03, 0.02, 8, Color(0.72, 0.72, 0.75))
	var mi := MeshInstance3D.new()
	mi.mesh = MeshKit.commit(st, MeshKit.mat_vcol(0.35, 0.35))
	add_child(mi)

func _on_action_pressed(_p) -> void:
	var m := get_tree().get_first_node_in_group("main")
	if m and m.rig is XRRig:
		var r: XRRig = m.rig
		if r.on_foot_body and is_instance_valid(r.on_foot_body):
			r.on_foot_body.drink_energy(DURATION, MULTIPLIER)
	drop_and_free()

# Climbing gloves prop: holding it enables the rig's single
# XRToolsMovementClimb provider (movement_climb.gd has no concept of gear,
# only of gripping XRToolsClimbable-tagged surfaces — so "gloves enable
# climbing" gates the ability itself, not which walls count. Simpler, matches
# the addon's grain, no surface-tier gating needed).
class_name ClimbingGlovesPickable
extends XRToolsPickable

func _init() -> void:
	name = "ClimbingGloves"
	collision_layer = 1 << 2   # layer 3 "Pickable Objects"
	collision_mask = 1 << 0    # layer 1 "Static World" — rests on the ground
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC

func _ready() -> void:
	_build_mesh()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.18, 0.06, 0.1)
	shape.shape = box
	shape.position = Vector3(0, 0.03, 0)
	add_child(shape)
	super._ready()
	picked_up.connect(func(_p): _set_climb_enabled(true))
	dropped.connect(func(_p): _set_climb_enabled(false))

func _build_mesh() -> void:
	var st := MeshKit.begin()
	var leather := Color(0.42, 0.28, 0.16)
	var grip := Color(0.15, 0.15, 0.16)
	for sx in [-0.05, 0.05]:
		MeshKit.box(st, Transform3D(Basis(), Vector3(sx, 0.03, 0)), Vector3(0.08, 0.05, 0.09), leather)
		# palm grip pads
		MeshKit.box(st, Transform3D(Basis(), Vector3(sx, 0.005, 0.02)), Vector3(0.07, 0.012, 0.06), grip)
		# wrist cuff
		MeshKit.box(st, Transform3D(Basis(), Vector3(sx, 0.03, -0.055)), Vector3(0.085, 0.055, 0.02), leather * 0.85)
	var mi := MeshInstance3D.new()
	mi.mesh = MeshKit.commit(st, MeshKit.mat_vcol(0.75, 0.05))
	add_child(mi)

func _set_climb_enabled(on: bool) -> void:
	var m := get_tree().get_first_node_in_group("main")
	if m and m.rig is XRRig:
		var r: XRRig = m.rig
		r._climb.enabled = on

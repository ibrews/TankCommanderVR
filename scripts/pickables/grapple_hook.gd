# Grappling hook prop: pure XRToolsPickable, MeshKit-built (no imported
# assets, matching every other prop in this game). The player must physically
# find and grab it in the world; the FIRST grab permanently unlocks the rig's
# two XRToolsMovementGrapple providers for the rest of the playthrough
# (rig.acquire_grapple()). Powers used to be always-on regardless of pickup —
# Alex's complaint — so this is the gate. Drop it and you keep the ability
# (Spider-Man doesn't lose his webs by setting the can down); it re-clears only
# on a level restart, which rebuilds the rig.
class_name GrappleHookPickable
extends XRToolsPickable

func _init() -> void:
	name = "GrappleHook"
	collision_layer = 1 << 2   # layer 3 "Pickable Objects"
	collision_mask = 1 << 0    # layer 1 "Static World" — rests on the ground
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC

func _ready() -> void:
	_build_mesh()
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.025
	cap.height = 0.2
	shape.shape = cap
	shape.rotation.x = deg_to_rad(90)
	add_child(shape)
	super._ready()
	picked_up.connect(func(_p):
		_acquire_grapple()
		Sfx.play_at("click", global_position, -4.0, 1.15)
		_pulse_holder(0.4, 0.06))
	# no dropped handler: acquisition is permanent for the playthrough

func _build_mesh() -> void:
	var st := MeshKit.begin()
	var steel := Color(0.55, 0.55, 0.58)
	# handle (dark grip wrap)
	MeshKit.cyl(st, Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(0, -0.08, 0)), 0.018, 0.018, 0.16, 6, Color(0.28, 0.22, 0.16))
	# shaft
	MeshKit.cyl(st, Transform3D(Basis(), Vector3(0, 0.02, 0)), 0.02, 0.02, 0.1, 8, steel)
	# curved hook tip (two angled segments approximate the curl)
	MeshKit.cyl(st, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(35)), Vector3(0.0, 0.09, 0.02)), 0.016, 0.012, 0.09, 6, steel)
	MeshKit.cyl(st, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(120)), Vector3(0.0, 0.145, 0.06)), 0.012, 0.008, 0.07, 6, steel)
	var mi := MeshInstance3D.new()
	mi.mesh = MeshKit.commit(st, MeshKit.mat_vcol(0.35, 0.8))
	add_child(mi)

func _pulse_holder(amp: float, dur: float) -> void:
	var ctrl := get_picked_up_by_controller()
	if ctrl and ctrl.has_method("pulse"):
		ctrl.pulse(amp, dur)

func _acquire_grapple() -> void:
	var m := get_tree().get_first_node_in_group("main")
	if m and m.rig is XRRig:
		(m.rig as XRRig).acquire_grapple()

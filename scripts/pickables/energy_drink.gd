# Energy drink prop: a one-shot consumable, not a permanent toggle. Trigger
# ("action") while held boosts OnFootBody's sprint speed for a fixed duration
# via the same get_tree().create_timer(...).timeout idiom used throughout
# player_tank.gd/main.gd, then the can is dropped and freed.
# Branded "SUPER FIZZ MAX" per Alex, in the same "the world has a cabbage
# merchant, of course the energy drink has a name" comedic-labeling
# tradition as the rest of the game's NPCs/signage.
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
	picked_up.connect(func(_p): _pulse_holder(0.3, 0.05))
	action_pressed.connect(_on_action_pressed)

func _build_mesh() -> void:
	var st := MeshKit.begin()
	MeshKit.cyl(st, Transform3D(Basis(), Vector3(0, 0.06, 0)), 0.03, 0.032, 0.12, 8, Color(0.85, 0.72, 0.15))
	MeshKit.cyl(st, Transform3D(Basis(), Vector3(0, 0.125, 0)), 0.026, 0.03, 0.02, 8, Color(0.72, 0.72, 0.75))
	var mi := MeshInstance3D.new()
	mi.mesh = MeshKit.commit(st, MeshKit.mat_vcol(0.35, 0.35))
	add_child(mi)
	var brand := Label3D.new()
	brand.text = "SUPER\nFIZZ MAX"
	brand.font_size = 28
	brand.pixel_size = 0.0009
	brand.modulate = Color(1.0, 0.15, 0.1)
	brand.outline_size = 6
	brand.outline_modulate = Color(1, 1, 1)
	brand.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	brand.position = Vector3(0, 0.06, 0.033)
	add_child(brand)

func _pulse_holder(amp: float, dur: float) -> void:
	var ctrl := get_picked_up_by_controller()
	if ctrl and ctrl.has_method("pulse"):
		ctrl.pulse(amp, dur)

func _on_action_pressed(_p) -> void:
	# crack it open + a jolt of haptic energy before the sprint boost lands
	Sfx.play_at("pop", global_position, -2.0, 1.1)
	_pulse_holder(0.6, 0.15)
	var m := get_tree().get_first_node_in_group("main")
	if m and m.rig is XRRig:
		var r: XRRig = m.rig
		if r.on_foot_body and is_instance_valid(r.on_foot_body):
			r.on_foot_body.drink_energy(DURATION, MULTIPLIER)
	drop_and_free()

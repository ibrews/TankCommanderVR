# Energy drink prop: a one-shot consumable, not a permanent toggle. Trigger
# ("action") while held boosts OnFootBody's sprint speed for a fixed duration
# via the same get_tree().create_timer(...).timeout idiom used throughout
# player_tank.gd/main.gd, then the can is dropped and freed.
# Branded "SUPER FIZZ MAX" per Alex, in the same "the world has a cabbage
# merchant, of course the energy drink has a name" comedic-labeling
# tradition as the rest of the game's NPCs/signage.
#
# drop_and_free() is ALWAYS call_deferred, never called synchronously from
# inside the action_pressed handler: godot-xr-tools' function_pickup.gd's
# _on_button_pressed() re-reads its picked_up_object member right after
# calling action(), and a synchronous free() nulls it mid-callback, crashing
# on-device.
class_name EnergyDrinkPickable
extends XRToolsPickable

const DURATION := 12.0
const MULTIPLIER := 1.8
const DRINK_WINDOW := 0.15   # gulp/fizz plays out before the can crushes + drops

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

var _mesh: MeshInstance3D

func _build_mesh() -> void:
	var st := MeshKit.begin()
	MeshKit.cyl(st, Transform3D(Basis(), Vector3(0, 0.06, 0)), 0.03, 0.032, 0.12, 8, Color(0.85, 0.72, 0.15))
	MeshKit.cyl(st, Transform3D(Basis(), Vector3(0, 0.125, 0)), 0.026, 0.03, 0.02, 8, Color(0.72, 0.72, 0.75))
	_mesh = MeshInstance3D.new()
	_mesh.mesh = MeshKit.commit(st, MeshKit.mat_vcol(0.35, 0.35))
	add_child(_mesh)
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
	Sfx.play_at("fizz", global_position, -8.0, 1.0)
	_pulse_holder(0.6, 0.15)
	var m := get_tree().get_first_node_in_group("main")
	if m and m.fx:
		m.fx.sparkle_burst(global_position + Vector3(0, 0.13, 0), 0.7)
	if m and m.rig is XRRig:
		var r: XRRig = m.rig
		if r.on_foot_body and is_instance_valid(r.on_foot_body):
			r.on_foot_body.drink_energy(DURATION, MULTIPLIER)
			print("[drink] energy drink applied: duration=", DURATION, " multiplier=", MULTIPLIER)
		else:
			push_warning("[drink] energy drink action fired but no on_foot_body — likely seated in a vehicle; no effect applied")
	# drink experience: gulp sound plays out over DRINK_WINDOW while still
	# held, THEN the can visibly crushes right before it drops — matches the
	# real-world beat (crack -> chug -> crush -> toss) instead of an instant
	# vanish. Position/fx captured by value: by the time this timer fires the
	# pickable may already be a different distance from the player's hand.
	var drink_pos := global_position
	Sfx.play_at("gulp", drink_pos, -3.0, 1.0)
	get_tree().create_timer(DRINK_WINDOW).timeout.connect(func():
		if not is_instance_valid(self):
			return
		_crush_can()
		Sfx.play_at("can_crush", global_position, -2.0, 1.0)
		# call_deferred, NEVER a synchronous drop_and_free() here: godot-xr-
		# tools' function_pickup.gd re-reads picked_up_object right after
		# action() returns, and a synchronous free() nulls it mid-callback,
		# crashing on-device.
		call_deferred("drop_and_free"))

# Crush the can in place (scale/deform the existing MeshKit cylinder) instead
# of swapping meshes — cheap, no second ArrayMesh to build, and reads fine
# for the ~instant before drop_and_free() frees the whole node anyway.
func _crush_can() -> void:
	if not _mesh:
		return
	_mesh.scale = Vector3(1.35, 0.55, 1.4)
	_mesh.position.y -= 0.03

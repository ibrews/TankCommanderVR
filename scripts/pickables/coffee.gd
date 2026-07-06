# Coffee pickup: a one-shot consumable like energy_drink.gd, but tuned for
# reflexes instead of legs — trigger ("action") sips it and cuts weapon
# cooldowns (pistol semi-auto + bazooka reload, see OnFootBody.drink_coffee())
# for a fixed duration rather than boosting sprint speed, so the two pickups
# read as different tools, not one strictly better than the other. Branded
# "MUD RIVER ROAST" travel mug, same comedic-labeling tradition as
# energy_drink.gd's "SUPER FIZZ MAX".
class_name CoffeePickable
extends XRToolsPickable

const DURATION := 10.0
const COOLDOWN_MULT := 0.5   # half the wait between shots/reloads

func _init() -> void:
	name = "Coffee"
	collision_layer = 1 << 2   # layer 3 "Pickable Objects"
	collision_mask = 1 << 0    # layer 1 "Static World" — rests on the ground
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC

func _ready() -> void:
	_build_mesh()
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.034
	cyl.height = 0.11
	shape.shape = cyl
	shape.position = Vector3(0, 0.055, 0)
	add_child(shape)
	super._ready()
	picked_up.connect(_on_picked_up)
	action_pressed.connect(_on_action_pressed)

func _build_mesh() -> void:
	var st := MeshKit.begin()
	var steel := Color(0.62, 0.15, 0.1)   # travel mug body — matte red steel
	MeshKit.cyl(st, Transform3D(Basis(), Vector3(0, 0.055, 0)), 0.034, 0.03, 0.11, 10, steel)
	MeshKit.cyl(st, Transform3D(Basis(), Vector3(0, 0.113, 0)), 0.031, 0.031, 0.006, 10, Color(0.1, 0.1, 0.1))
	# handle loop, approximated as two stacked short cylinders
	MeshKit.cyl(st, Transform3D(Basis(Vector3.FORWARD, deg_to_rad(90)), Vector3(0.042, 0.07, 0)), 0.006, 0.006, 0.05, 6, steel)
	var mi := MeshInstance3D.new()
	mi.mesh = MeshKit.commit(st, MeshKit.mat_vcol(0.5, 0.3))
	add_child(mi)
	var brand := Label3D.new()
	brand.text = "MUD RIVER\nROAST"
	brand.font_size = 24
	brand.pixel_size = 0.0008
	brand.modulate = Color(1.0, 0.85, 0.6)
	brand.outline_size = 6
	brand.outline_modulate = Color(0.2, 0.05, 0.02)
	brand.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	brand.position = Vector3(0, 0.06, 0.035)
	add_child(brand)

func _pulse_holder(amp: float, dur: float) -> void:
	var ctrl := get_picked_up_by_controller()
	if ctrl and ctrl.has_method("pulse"):
		ctrl.pulse(amp, dur)

func _on_picked_up(_p) -> void:
	_pulse_holder(0.25, 0.05)
	var m := get_tree().get_first_node_in_group("main")
	if m and m.fx:
		m.fx.steam_puff(global_position + Vector3(0, 0.13, 0), 0.5)

func _on_action_pressed(_p) -> void:
	# a sip: steam puff + gulp-lite sound before the jolt lands, then the mug
	# is dropped — deferred for the same reason energy_drink.gd's is: xr-tools'
	# function_pickup.gd re-reads picked_up_object right after action() fires,
	# and a synchronous free() nulls it mid-callback, crashing on-device.
	Sfx.play_at("sip", global_position, -4.0, 1.05)
	var sip_pos := global_position
	get_tree().create_timer(0.12).timeout.connect(func():
		Sfx.play_at("steam", sip_pos, -6.0, 1.1))
	var m := get_tree().get_first_node_in_group("main")
	if m and m.fx:
		m.fx.steam_puff(global_position + Vector3(0, 0.13, 0), 0.8)
	_pulse_holder(0.5, 0.12)
	if m and m.rig is XRRig:
		var r: XRRig = m.rig
		if r.on_foot_body and is_instance_valid(r.on_foot_body):
			r.on_foot_body.drink_coffee(DURATION, COOLDOWN_MULT)
	call_deferred("drop_and_free")

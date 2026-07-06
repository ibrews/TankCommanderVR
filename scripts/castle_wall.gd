# Destructible castle wall segment. Cannon/rockets crumble it into rubble
# with a debris burst — satisfying and tactically useful (make your own gate).
class_name CastleWall
extends StaticBody3D

var hp := 55.0
var seg_len: float
var stone: Material
var _mesh: MeshInstance3D
var _shape: CollisionShape3D
var _dead := false

func _init(stone_mat: Material, segment_length: float) -> void:
	stone = stone_mat
	seg_len = segment_length
	collision_layer = 1
	collision_mask = 0

func _ready() -> void:
	_mesh = MeshInstance3D.new()
	_mesh.mesh = _wall_mesh()
	add_child(_mesh)
	_shape = CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(seg_len, 5.2, 1.5)
	_shape.shape = box
	_shape.position = Vector3(0, 2.6, 0)
	add_child(_shape)
	# Climb the ramparts. This body already owns a script (destructible logic),
	# and a node can hold only one — and movement_climb casts the grabbed
	# collider to XRToolsClimbable — so climbing rides a sibling StaticBody on
	# CLIMB_LAYER with the climbable script, sharing the wall's box. It's on the
	# climb layer only (not layer 1), so it adds no extra solid/physics surface,
	# just a grab handle overlapping the real wall.
	var climb := StaticBody3D.new()
	climb.collision_layer = MeshKit.CLIMB_LAYER
	climb.collision_mask = 0
	climb.set_script(load("res://addons/godot-xr-tools/objects/climbable.gd"))
	var ccs := CollisionShape3D.new()
	var cbox := BoxShape3D.new()
	cbox.size = Vector3(seg_len, 5.2, 1.5)
	ccs.shape = cbox
	ccs.position = Vector3(0, 2.6, 0)
	climb.add_child(ccs)
	add_child(climb)

func _wall_mesh() -> ArrayMesh:
	var st := MeshKit.begin()
	MeshKit.box(st, Transform3D(Basis(), Vector3(0, 2.4, 0)), Vector3(seg_len + 0.05, 4.8, 1.4), Color(0.78, 0.76, 0.72), 0.16)
	# crenellations
	var n := int(seg_len / 2.2)
	for i in n:
		var x := -seg_len / 2.0 + (i + 0.5) * seg_len / n
		MeshKit.box(st, Transform3D(Basis(), Vector3(x, 5.3, 0)), Vector3(1.0, 1.0, 1.4), Color(0.72, 0.70, 0.66), 0.16)
	return MeshKit.commit(st, stone)

func _rubble_mesh() -> ArrayMesh:
	var st := MeshKit.begin()
	# local rng, not the Game autoload — keeps this script compilable in
	# headless -s tool mode (autoloads absent there); seeded per segment
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(position)
	for i in 7:
		var x := rng.randf_range(-seg_len / 2.0, seg_len / 2.0)
		MeshKit.box(st, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).rotated(Vector3.RIGHT, rng.randf_range(-0.3, 0.3)),
			Vector3(x, rng.randf_range(0.2, 0.9), rng.randf_range(-0.8, 0.8))),
			Vector3(rng.randf_range(1.0, 2.4), rng.randf_range(0.6, 1.3), rng.randf_range(0.8, 1.6)),
			Color(0.66, 0.64, 0.60))
	return MeshKit.commit(st, stone)

func take_damage(amount: float, at: Vector3) -> void:
	if _dead:
		return
	# autoloads via /root lookup, not bare identifiers — this script must
	# compile in headless -s tool mode where autoload globals don't resolve
	var sfx: Node = get_node_or_null("/root/Sfx")
	hp -= amount
	if hp > 0.0:
		if sfx:
			sfx.play_at("debris", at, -6.0)
		return
	_dead = true
	_mesh.mesh = _rubble_mesh()
	(_shape.shape as BoxShape3D).size = Vector3(seg_len, 1.6, 2.2)
	_shape.position = Vector3(0, 0.8, 0)
	if sfx:
		sfx.play_at("wall_crumble", global_position + Vector3(0, 2, 0), 4.0)
	var fx: FxPool = get_tree().get_first_node_in_group("fx")
	if fx:
		fx.debris_burst(global_position + Vector3(0, 3, 0), 10, Color(0.7, 0.68, 0.64))
		fx.dust(global_position + Vector3(0, 1.5, 0), 2.2)

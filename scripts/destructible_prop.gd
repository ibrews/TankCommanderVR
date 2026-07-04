# Destructible tree/rock. Mirrors castle_wall.gd's take_damage()/FX pattern
# exactly, so shells/rockets/MG rounds that already know how to hurt walls
# hurt trees and rocks for free (Projectiles._impact() just calls
# take_damage() on anything with the method — no projectiles.gd changes
# needed). The VISUAL stays in WorldDressing's MultiMesh (draw-call budget —
# 230 trees/level cannot each be their own MeshInstance3D); this node is a
# thin invisible hitbox that, on death, zeroes its MultiMesh instance's
# transform (hides it — MultiMesh has no per-instance visibility toggle) and
# spawns a small standalone wreck mesh (stump / rubble pile) plus FX so the
# destroyed prop still reads clearly in-headset.
class_name DestructibleProp
extends StaticBody3D

enum Kind { TREE, ROCK }

var kind: int = Kind.TREE
var hp := 1.0
var scale_factor := 1.0
var mm: MultiMesh
var instance_idx := -1
var _dead := false
var _wreck: MeshInstance3D

func _init(k: int, hit_points: float, s: float, multimesh: MultiMesh, idx: int) -> void:
	kind = k
	hp = hit_points
	scale_factor = s
	mm = multimesh
	instance_idx = idx
	collision_layer = 1   # "static world" — same layer as terrain/walls/buildings,
	collision_mask = 0    # so existing player(1|4)/enemy(1|2) projectile masks hit it with no changes elsewhere

func _ready() -> void:
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	if kind == Kind.TREE:
		# trunk rises from ground level (position.y == terrain height at base)
		cyl.radius = 0.35 * scale_factor
		cyl.height = 3.6 * scale_factor
		shape.position = Vector3(0, cyl.height * 0.5, 0)
	else:
		# rock mesh straddles ground level (see _rock_mesh() — boxes centered
		# near local y=0), same as the old add_static_box_collider() this
		# replaces, which centered its box at gy + 0.5*s
		cyl.radius = 0.85 * scale_factor
		cyl.height = 1.1 * scale_factor
		shape.position = Vector3(0, cyl.height * 0.5 - 0.15 * scale_factor, 0)
	shape.shape = cyl
	add_child(shape)

func _stump_mesh() -> ArrayMesh:
	var st := MeshKit.begin()
	var trunk := Color(0.28, 0.19, 0.11)
	MeshKit.cyl(st, Transform3D(Basis(), Vector3(0, 0.35 * scale_factor, 0)),
		0.24 * scale_factor, 0.20 * scale_factor, 0.7 * scale_factor, 6, trunk)
	return MeshKit.commit(st, MeshKit.mat_vcol())

func _rubble_mesh() -> ArrayMesh:
	var st := MeshKit.begin()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(global_position)
	var c := Color(0.52, 0.50, 0.47)
	for i in 5:
		MeshKit.box(st, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).rotated(Vector3.RIGHT, rng.randf_range(-0.3, 0.3)),
			Vector3(rng.randf_range(-0.5, 0.5) * scale_factor, rng.randf_range(0.05, 0.25) * scale_factor, rng.randf_range(-0.5, 0.5) * scale_factor)),
			Vector3(rng.randf_range(0.3, 0.7), rng.randf_range(0.2, 0.4), rng.randf_range(0.3, 0.6)) * scale_factor,
			c * rng.randf_range(0.85, 1.1))
	return MeshKit.commit(st, MeshKit.mat_vcol())

func take_damage(amount: float, at: Vector3) -> void:
	if _dead:
		return
	var sfx: Node = get_node_or_null("/root/Sfx")
	hp -= amount
	if hp > 0.0:
		if sfx:
			sfx.play_at("debris", at, -8.0)
		return
	_dead = true
	# hide the MultiMesh instance — MultiMesh has no per-instance visibility
	# flag, and a degenerate (zero-scale) transform is worth avoiding (some
	# renderers/culling paths don't like a zero-determinant basis), so instead
	# sink it far below the world, same trick as an off-screen object pool
	if mm and instance_idx >= 0 and instance_idx < mm.instance_count:
		mm.set_instance_transform(instance_idx, Transform3D(Basis(), Vector3(0, -500.0, 0)))
	# shrink the hitbox to a low stump/rubble footprint so it stops blocking movement
	var shape := get_child(0) as CollisionShape3D
	if shape:
		var cyl := shape.shape as CylinderShape3D
		cyl.height = 0.6 * scale_factor
		cyl.radius = (0.5 if kind == Kind.ROCK else 0.24) * scale_factor
		shape.position = Vector3(0, cyl.height * 0.5, 0)
	_wreck = MeshInstance3D.new()
	_wreck.mesh = _stump_mesh() if kind == Kind.TREE else _rubble_mesh()
	_wreck.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_wreck)
	if sfx:
		sfx.play_at("crash" if kind == Kind.TREE else "debris", global_position, -2.0)
	var fx: FxPool = get_tree().get_first_node_in_group("fx")
	if fx:
		var top := global_position + Vector3(0, (2.4 if kind == Kind.TREE else 1.0) * scale_factor, 0)
		fx.debris_burst(top, 6 if kind == Kind.TREE else 8, Color(0.3, 0.25, 0.15) if kind == Kind.TREE else Color(0.55, 0.53, 0.5))
		fx.dust(global_position + Vector3(0, 0.5, 0), 1.4 * scale_factor)

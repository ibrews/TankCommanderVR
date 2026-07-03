# Throwable — real RigidBody3D physics (arm-throw velocity comes free from
# XRToolsPickable's own release handling), armed the moment it's let go,
# fixed fuse rather than impact-detection (simpler, forgiving in VR where a
# "miss" still lands somewhere reasonable). A cabbage, not a grenade — this
# game already has a running joke about a cabbage merchant in every level
# (npc.gd's CabbageMan/tragedy()), so the throwable produce is funnier and
# more in-universe than a military prop. Splash damage/FX matches
# Projectiles.Kind.MORTAR's numbers (see projectiles.gd) without routing
# through the pooled-tracer system, which is built for fast invisible
# rounds, not a thrown physical object with its own arm-swing arc.
class_name CabbageGrenadePickable
extends XRToolsPickable

const FUSE := 2.2
const SPLASH_R := 6.0
const SPLASH_DMG := 20.0

var _armed := false
var _fuse_t := 0.0

func _init() -> void:
	name = "CabbageGrenade"
	collision_layer = 1 << 2
	collision_mask = 1 << 0 | 1 << 1  # rests on world AND can bounce off vehicles/enemies
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC

func _ready() -> void:
	_build_mesh()
	var shape := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.05
	shape.shape = sph
	add_child(shape)
	super._ready()
	released.connect(func(_p, _by): _armed = true; _fuse_t = 0.0)

func _build_mesh() -> void:
	var st := MeshKit.begin()
	MeshKit.cyl(st, Transform3D(Basis(), Vector3.ZERO), 0.05, 0.045, 0.09, 8, Color(0.35, 0.55, 0.25))
	MeshKit.box(st, Transform3D(Basis(), Vector3(0, 0.06, 0)), Vector3(0.012, 0.03, 0.012), Color(0.45, 0.5, 0.3))
	var mi := MeshInstance3D.new()
	mi.mesh = MeshKit.commit(st, MeshKit.mat_vcol(0.85, 0.0))
	add_child(mi)

func _physics_process(delta: float) -> void:
	if not _armed:
		return
	_fuse_t += delta
	if _fuse_t >= FUSE:
		_detonate()

func _detonate() -> void:
	var m := get_tree().get_first_node_in_group("main")
	var cam_pos: Vector3 = m.rig.get("camera").global_position if m and m.rig else Vector3.ZERO
	if m and m.fx:
		m.fx.explosion(global_position, false, cam_pos)
	# Splash damage — same shape as Projectiles._impact()'s splash section,
	# hand-rolled here since a thrown prop isn't part of the pooled-tracer
	# system. Only "enemies"/"planes" (matches the existing convention that
	# player-sourced splash weapons never hurt the player).
	for grp in ["enemies", "planes"]:
		for n in get_tree().get_nodes_in_group(grp):
			var node := n as Node3D
			if node == null or not node.has_method("take_damage"):
				continue
			var d := node.global_position.distance_to(global_position)
			if d < SPLASH_R:
				node.take_damage(SPLASH_DMG * clampf(1.0 - d / SPLASH_R, 0.2, 1.0), global_position)
	queue_free()

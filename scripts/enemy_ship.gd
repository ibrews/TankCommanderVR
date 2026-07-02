# Enemy warship: patrols the channels, keeps to deep water, lobs shells
# with target lead like the tanks, and sinks stern-up when killed.
class_name EnemyShip
extends CharacterBody3D

const WATERLINE := -0.55
const DRAFT_MIN := -1.6      # needs water at least this deep ahead

static var _mesh: ArrayMesh

var terrain: Terrain
var projectiles: Projectiles
var fx: FxPool
var player: Node3D
var hp := 30.0
var accuracy := 0.07
var cadence := 6.0
var yaw := 0.0
var spd := 0.0
var orbit_dir := 1.0
var fire_timer := 4.0
var _bob_t := 0.0
var _sink_t := -1.0
var _dead := false
var engine_p: AudioStreamPlayer3D

func _init(t: Terrain, p: Projectiles, f: FxPool, pl: Node3D) -> void:
	terrain = t
	projectiles = p
	fx = f
	player = pl
	collision_layer = 4
	collision_mask = 0
	add_to_group("enemies")

static func _build() -> void:
	if _mesh:
		return
	var st := MeshKit.begin()
	var navy := Color(0.38, 0.41, 0.44)
	var deck := Color(0.5, 0.48, 0.42)
	# hull + bow prism + red waterline stripe
	MeshKit.box(st, Transform3D(Basis(), Vector3(0, 0.55, 0.6)), Vector3(3.0, 1.3, 8.0), navy)
	MeshKit.prism(st, Transform3D(Basis(Vector3.UP, PI / 2), Vector3(0, 1.18, -5.05)), 2.2, 3.0, 0.9, navy)
	MeshKit.box(st, Transform3D(Basis(), Vector3(0, 0.02, 0.6)), Vector3(3.06, 0.25, 8.06), Color(0.55, 0.2, 0.16))
	# deck + bridge + funnel + mast
	MeshKit.box(st, Transform3D(Basis(), Vector3(0, 1.26, 0.6)), Vector3(2.7, 0.14, 7.6), deck)
	MeshKit.box(st, Transform3D(Basis(), Vector3(0, 2.0, 1.6)), Vector3(1.9, 1.4, 2.6), navy * 1.12)
	MeshKit.box(st, Transform3D(Basis(), Vector3(0, 2.85, 1.4)), Vector3(1.3, 0.4, 1.2), navy * 0.9)
	MeshKit.cyl(st, Transform3D(Basis(Vector3.RIGHT, 0.12), Vector3(0, 3.0, 3.1)), 0.34, 0.28, 1.5, 8, Color(0.25, 0.26, 0.28))
	MeshKit.cyl(st, Transform3D(Basis(), Vector3(0, 3.6, 0.6)), 0.05, 0.04, 1.8, 5, Color(0.2, 0.2, 0.2))
	# forward gun turret + barrel
	MeshKit.cyl(st, Transform3D(Basis(), Vector3(0, 1.62, -2.6)), 0.85, 0.75, 0.7, 8, navy * 1.05)
	MeshKit.cyl(st, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(96)), Vector3(0, 1.85, -4.0)), 0.10, 0.08, 2.6, 6, Color(0.2, 0.22, 0.24))
	# depth-charge racks at the stern
	for sx in [-0.8, 0.8]:
		MeshKit.box(st, Transform3D(Basis(), Vector3(sx, 1.5, 4.3)), Vector3(0.5, 0.4, 1.0), Color(0.3, 0.3, 0.28))
	_mesh = MeshKit.commit(st, MeshKit.mat_vcol(0.8))

func _ready() -> void:
	_build()
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh
	add_child(mi)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.2, 3.0, 9.5)
	shape.shape = box
	shape.position = Vector3(0, 1.5, 0)
	add_child(shape)
	yaw = Game.rng.randf() * TAU
	orbit_dir = 1.0 if Game.rng.randf() > 0.5 else -1.0
	fire_timer = Game.rng.randf_range(3.0, 6.0)
	engine_p = Sfx.make_loop_player("jeep_loop", self, -8.0, 10.0)
	engine_p.pitch_scale = 0.55
	engine_p.play()
	if Game.mutator == "balloon":
		Game.balloonize(self)

func _physics_process(delta: float) -> void:
	var gp := global_position
	_bob_t += delta
	if _sink_t >= 0.0:
		# going down by the stern
		_sink_t += delta
		global_position.y = WATERLINE - 0.35 - _sink_t * 0.9
		rotation.x = move_toward(rotation.x, -0.35, delta * 0.12)
		if _sink_t > 5.0:
			queue_free()
		return
	var to_p := player.global_position - gp
	var flat_d := Vector2(to_p.x, to_p.z).length()
	# stand off at ~95 m and circle
	var want := atan2(-to_p.x, -to_p.z) + orbit_dir * (PI / 2.0 + clampf((95.0 - flat_d) / 110.0, -0.7, 0.7))
	# keep to deep water: probe ahead; if it shoals, steer toward deeper side
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	var ahead := gp + fwd * 18.0
	if terrain.height(ahead.x, ahead.z) > DRAFT_MIN:
		var lt := gp + fwd.rotated(Vector3.UP, 0.7) * 18.0
		var rt := gp + fwd.rotated(Vector3.UP, -0.7) * 18.0
		want = yaw + (0.9 if terrain.height(lt.x, lt.z) < terrain.height(rt.x, rt.z) else -0.9)
		spd = move_toward(spd, 2.5, 3.0 * delta)
	else:
		spd = move_toward(spd, 7.5 * Game.diff(0.8, 1.0, 1.15), 2.0 * delta)
	var dy := wrapf(want - yaw, -PI, PI)
	yaw += clampf(dy, -0.5 * delta, 0.5 * delta)
	fwd = Vector3(-sin(yaw), 0, -cos(yaw))
	global_position += fwd * spd * delta
	global_position.y = WATERLINE - 0.28 + sin(_bob_t * 1.3) * 0.08
	basis = Basis(Vector3.UP, yaw)
	rotation.z = sin(_bob_t * 0.9) * 0.02
	# gunnery: same lead math as the tanks, from the bow turret
	fire_timer -= delta
	if fire_timer <= 0.0 and Game.alive and flat_d < 170.0 * Game.detect_scale():
		fire_timer = cadence + Game.rng.randf_range(-1.0, 1.5)
		var pvel: Vector3 = player.get("velocity") if player.get("velocity") != null else Vector3.ZERO
		_fire(player.global_position + pvel * (flat_d / 70.0) * 0.7)

func _fire(target: Vector3) -> void:
	var muzzle_pos := to_global(Vector3(0, 1.85, -4.6))
	var to := target - muzzle_pos
	var flat_dist := Vector2(to.x, to.z).length()
	var v := 70.0
	var sin2 := clampf(9.8 * flat_dist / (v * v), 0.0, 1.0)
	var ang := 0.5 * asin(sin2) + atan2(to.y, flat_dist) * 0.5
	var dir_flat := Vector3(to.x, 0, to.z).normalized()
	dir_flat = dir_flat.rotated(Vector3.UP, Game.rng.randf_range(-accuracy, accuracy))
	var vel := dir_flat * cos(ang) * v + Vector3.UP * sin(ang) * v
	projectiles.fire(Projectiles.Kind.ENEMY_SHELL, muzzle_pos, vel, [get_rid()], false)
	fx.muzzle_flash(muzzle_pos, 1.5)
	Sfx.play_at("cannon", muzzle_pos, -1.0, 0.8)

func take_damage(amount: float, at: Vector3) -> void:
	if _dead:
		return
	hp -= amount
	Sfx.play_at("hit", at, -6.0)
	if hp <= 0.0:
		_dead = true
		remove_from_group("enemies")
		collision_layer = 0
		engine_p.stop()
		var fxp: FxPool = get_tree().get_first_node_in_group("fx") if is_inside_tree() else null
		if fxp:
			fxp.explosion(global_position + Vector3(0, 2, 0), true, player.global_position)
			fxp.smoke_column(global_position + Vector3(0, 2, 0), 6.0)
		Sfx.play_at("crash", global_position, -2.0, 0.7)
		Sfx.play_at("bubbles_loop", global_position, -4.0)
		Game.add_score(150)
		Sfx.vo("vo_sunk" if Game.rng.randf() < 0.6 else "vo_kill", 1, 12.0)
		_sink_t = 0.0

# Attack plane: orbits high, periodically dives on the player and fires two
# rockets, then egresses. Kinematic body so raycasts/MG can hit it.
class_name EnemyPlane
extends CharacterBody3D

enum State { ORBIT, ATTACK, EGRESS, SPIRAL }

static var _mesh: ArrayMesh

var terrain: Terrain
var projectiles: Projectiles
var fx: FxPool
var player: CharacterBody3D

var state := State.ORBIT
var hp := 30.0
var speed := 42.0
var heading := 0.0
var alt := 60.0
var orbit_dir := 1.0
var attack_timer := 10.0
var _fired := false
var prop: MeshInstance3D
var engine_p: AudioStreamPlayer3D
var _spiral_t := 0.0

func _init(t: Terrain, p: Projectiles, f: FxPool, pl: CharacterBody3D) -> void:
	terrain = t
	projectiles = p
	fx = f
	player = pl
	collision_layer = 4
	collision_mask = 0
	add_to_group("planes")

static func _build_mesh() -> void:
	if _mesh:
		return
	var col := Color(0.45, 0.47, 0.5)
	var st := MeshKit.begin()
	# fuselage
	MeshKit.cyl(st, Transform3D(Basis(Vector3.RIGHT, PI / 2)), 0.45, 0.3, 7.0, 8, col)
	MeshKit.cyl(st, Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(0, 0, -3.8)), 0.42, 0.15, 0.8, 8, Color(0.7, 0.2, 0.15))
	# wings
	MeshKit.box(st, Transform3D(Basis(), Vector3(0, -0.1, -0.4)), Vector3(9.0, 0.12, 1.7), col)
	# tail
	MeshKit.box(st, Transform3D(Basis(), Vector3(0, 0.1, 3.2)), Vector3(3.2, 0.1, 0.9), col)
	MeshKit.box(st, Transform3D(Basis(), Vector3(0, 0.7, 3.3)), Vector3(0.08, 1.3, 0.9), Color(0.7, 0.2, 0.15))
	# canopy
	MeshKit.box(st, Transform3D(Basis(), Vector3(0, 0.4, -1.2)), Vector3(0.5, 0.35, 1.1), Color(0.2, 0.3, 0.4))
	_mesh = MeshKit.commit(st, MeshKit.mat_vcol(0.6, 0.3))

func _ready() -> void:
	_build_mesh()
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh
	add_child(mi)
	prop = MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(2.6, 0.15)
	prop.mesh = qm
	prop.position = Vector3(0, 0, -4.25)
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.2, 0.2, 0.2, 0.5)
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	prop.material_override = pm
	add_child(prop)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(9.0, 1.6, 7.0)
	shape.shape = box
	add_child(shape)
	engine_p = Sfx.make_loop_player("plane_loop", self, -2.0, 14.0)
	engine_p.max_distance = 400.0
	engine_p.play()
	heading = Game.rng.randf() * TAU
	orbit_dir = 1.0 if Game.rng.randf() > 0.5 else -1.0
	attack_timer = Game.rng.randf_range(6.0, 14.0)

func _physics_process(delta: float) -> void:
	prop.rotation.z += 40.0 * delta
	if state == State.SPIRAL:
		_spiral(delta)
		return
	var gp := global_position
	var to_player := player.global_position - gp
	var flat_d := Vector2(to_player.x, to_player.z).length()

	match state:
		State.ORBIT:
			# circle the player at ~260 m
			var tangent := atan2(-to_player.x, -to_player.z) + orbit_dir * (PI / 2.0 + clampf((260.0 - flat_d) / 200.0, -0.5, 0.5))
			_steer(tangent, delta, 0.5)
			alt = move_toward(alt, 65.0, 8.0 * delta)
			attack_timer -= delta
			if attack_timer <= 0.0 and Game.alive:
				state = State.ATTACK
				_fired = false
		State.ATTACK:
			var predicted := player.global_position + player.velocity * 2.0
			var want := atan2(-(predicted.x - gp.x), -(predicted.z - gp.z))
			_steer(want, delta, 1.2)
			alt = move_toward(alt, 26.0, 14.0 * delta)
			if flat_d < 300.0 and not _fired and absf(wrapf(want - heading, -PI, PI)) < 0.1:
				_fired = true
				_fire_rockets(predicted)
			if flat_d < 130.0:
				state = State.EGRESS
				attack_timer = Game.rng.randf_range(12.0, 20.0)
		State.EGRESS:
			_steer(heading, delta, 0.2)  # fly straight out
			alt = move_toward(alt, 70.0, 16.0 * delta)
			if flat_d > 240.0:
				state = State.ORBIT

	var fwd := Vector3(-sin(heading), 0, -cos(heading))
	var target_y := maxf(terrain.height(gp.x, gp.z) + 18.0, alt)
	var vy := clampf((target_y - gp.y) * 0.8, -14.0, 14.0)
	velocity = fwd * speed + Vector3(0, vy, 0)
	global_position += velocity * delta
	# visual bank + pitch
	var bank := clampf(-_last_turn * 1.4, -0.9, 0.9)
	basis = Basis.from_euler(Vector3(clampf(-vy * 0.03, -0.5, 0.5), heading + PI, bank))
	engine_p.pitch_scale = clampf(1.0 - velocity.dot(to_player.normalized()) / 150.0, 0.8, 1.3)

var _last_turn := 0.0
func _steer(want: float, delta: float, rate: float) -> void:
	var dy := wrapf(want - heading, -PI, PI)
	var turn := clampf(dy, -rate * delta, rate * delta)
	heading += turn
	_last_turn = lerpf(_last_turn, clampf(dy, -1, 1), 3.0 * delta)

func _fire_rockets(target: Vector3) -> void:
	for i in 2:
		var off := global_transform.basis.x * (1.2 if i == 0 else -1.2)
		var pos := global_position + off + Vector3(0, -0.5, 0)
		var dir := (target - pos).normalized()
		dir = dir.rotated(Vector3.UP, Game.rng.randf_range(-0.04, 0.04))
		projectiles.fire(Projectiles.Kind.PLANE_ROCKET, pos, dir * 95.0 + velocity * 0.5, [get_rid()], false)
		Sfx.play_at("rocket", pos, 0.0)

func take_damage(amount: float, at: Vector3) -> void:
	if state == State.SPIRAL:
		return
	hp -= amount
	Sfx.play_at("hit", at, -8.0, 1.3)
	if hp <= 0.0:
		state = State.SPIRAL
		_spiral_t = 0.0
		remove_from_group("planes")
		collision_layer = 0
		fx.explosion(global_position, false, player.global_position)
		Game.add_score(150)
		engine_p.pitch_scale = 1.5

func _spiral(delta: float) -> void:
	_spiral_t += delta
	heading += 1.8 * delta
	var fwd := Vector3(-sin(heading), 0, -cos(heading))
	velocity = fwd * speed * 0.8 + Vector3(0, -22.0, 0)
	global_position += velocity * delta
	rotation.z += 3.0 * delta
	rotation.x = -0.5
	var ty := terrain.height(global_position.x, global_position.z)
	if global_position.y < ty + 1.0 or _spiral_t > 8.0:
		fx.explosion(Vector3(global_position.x, ty + 1.0, global_position.z), true, player.global_position)
		fx.smoke_column(Vector3(global_position.x, ty + 1.0, global_position.z), 15.0)
		queue_free()

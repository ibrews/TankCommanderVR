# Enemy tank: patrols, engages on sight (buildings block LOS), lobs arcing
# shells with target lead. Death = big explosion + ballistic turret pop.
class_name EnemyTank
extends CharacterBody3D

enum State { PATROL, ENGAGE, DEAD }

static var _hull_mesh: ArrayMesh
static var _turret_mesh: ArrayMesh

var terrain: Terrain
var projectiles: Projectiles
var fx: FxPool
var player: CharacterBody3D

var state := State.PATROL
var hp := 55.0
var yaw := 0.0
var spd := 0.0
var turret: Node3D
var blob: MeshInstance3D
var waypoint := Vector2.ZERO
var fire_timer := 5.0
var accuracy := 0.06     # radians of aim noise (manager scales by wave)
var cadence := 5.5
var _dead_t := 0.0
var _turret_vel := Vector3.ZERO
var _turret_spin := Vector3.ZERO

func _init(t: Terrain, p: Projectiles, f: FxPool, pl: CharacterBody3D) -> void:
	terrain = t
	projectiles = p
	fx = f
	player = pl
	collision_layer = 4
	collision_mask = 1
	add_to_group("enemies")

static func _build_meshes() -> void:
	if _hull_mesh:
		return
	var col := Color(0.55, 0.48, 0.38)  # enemy desert tan
	var dark := Color(0.16, 0.16, 0.17)
	var st := MeshKit.begin()
	MeshKit.box(st, Transform3D(Basis(), Vector3(0, 1.05, 0.2)), Vector3(2.3, 0.7, 5.2), col)
	MeshKit.box(st, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-35)), Vector3(0, 0.95, -2.7)), Vector3(2.3, 0.65, 1.2), col)
	for sx in [-1.35, 1.35]:
		MeshKit.box(st, Transform3D(Basis(), Vector3(sx, 0.8, 0)), Vector3(0.45, 0.5, 6.0), dark)
	_hull_mesh = MeshKit.commit(st, MeshKit.mat_vcol(0.85))
	var ts := MeshKit.begin()
	MeshKit.cyl(ts, Transform3D(Basis(), Vector3(0, 0.3, 0)), 0.95, 0.75, 0.6, 10, col)
	MeshKit.cyl(ts, Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(0, 0.3, -2.5)), 0.09, 0.075, 3.6, 8, dark)
	_turret_mesh = MeshKit.commit(ts, MeshKit.mat_vcol(0.85))

func _ready() -> void:
	_build_meshes()
	var hull := MeshInstance3D.new()
	hull.mesh = _hull_mesh
	add_child(hull)
	turret = Node3D.new()
	turret.position = Vector3(0, 1.45, -0.2)
	add_child(turret)
	var tm := MeshInstance3D.new()
	tm.mesh = _turret_mesh
	turret.add_child(tm)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(3.2, 1.4, 6.2)
	shape.shape = box
	shape.position = Vector3(0, 1.0, 0)
	add_child(shape)
	blob = MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(4.2, 7.0)
	blob.mesh = qm
	var bm := StandardMaterial3D.new()
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.albedo_texture = load("res://assets/tex/blob_shadow.png")
	bm.albedo_color = Color(1, 1, 1, 0.5)
	bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	blob.material_override = bm
	blob.top_level = true
	add_child(blob)
	yaw = Game.rng.randf() * TAU
	_pick_waypoint()
	fire_timer = Game.rng.randf_range(3.0, 7.0)
	_apply_skin()

func _apply_skin() -> void:
	if Game.mutator == "balloon":
		Game.balloonize(self)
	elif Levels.cardboard:
		var card := MeshKit.mat_tex("res://assets/tex/cardboard.png", false, 0.95)
		for c in get_children():
			if c is MeshInstance3D and c != blob:
				c.material_override = card
		if turret.get_child_count() > 0:
			(turret.get_child(0) as MeshInstance3D).material_override = card

func _pick_waypoint() -> void:
	var a := Game.rng.randf() * TAU
	var r := Game.rng.randf_range(40.0, minf(170.0, terrain.arena_radius * 0.8))
	waypoint = Vector2(cos(a) * r, sin(a) * r)

func _physics_process(delta: float) -> void:
	if state == State.DEAD:
		_dead_update(delta)
		return
	var gp := global_position
	var to_player := player.global_position - gp
	var dist := to_player.length()

	# state transitions (night/stealth aware: darkness shrinks their eyes,
	# your headlights and gunfire give you away)
	var see := Tune.v("detect_range_day") * Game.detect_scale()
	if state == State.PATROL and dist < see and _has_los():
		state = State.ENGAGE
		if Game.time_night:
			Sfx.vo("vo_spotted", 2, 20.0)
	elif state == State.ENGAGE and (dist > see * 1.35 + 20.0 or not _has_los()):
		state = State.PATROL

	var target_speed := 0.0
	var desired_yaw := yaw
	if state == State.PATROL:
		var to_wp := waypoint - Vector2(gp.x, gp.z)
		if to_wp.length() < 12.0:
			_pick_waypoint()
		desired_yaw = atan2(-to_wp.x, -to_wp.y)
		target_speed = 3.4
	else:
		desired_yaw = atan2(-to_player.x, -to_player.z)
		target_speed = 3.0 if dist > 100.0 else 0.0
		_update_combat(delta, dist)

	# steer + move
	var dy := wrapf(desired_yaw - yaw, -PI, PI)
	yaw += clampf(dy, -0.5 * delta, 0.5 * delta)
	if absf(dy) > 0.6:
		target_speed *= 0.3
	spd = move_toward(spd, target_speed, 2.0 * delta)
	var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
	# enemy tanks don't swim either: hold at the waterline (shore battery)
	var wcheck := gp + fwd * 6.0
	if terrain.height(wcheck.x, wcheck.z) < -1.0 and terrain.height(gp.x, gp.z) > -1.0:
		spd = move_toward(spd, 0.0, 30.0 * delta)
	var target_y := terrain.height(gp.x, gp.z) + 0.04
	velocity = fwd * spd + Vector3(0, clampf((target_y - gp.y) / delta, -10.0, 10.0), 0)
	move_and_slide()
	var flat := Vector2(global_position.x, global_position.z)
	if flat.length() > terrain.arena_radius:
		_pick_waypoint()
	# align to slope
	var n := terrain.normal(global_position.x, global_position.z)
	var f := Vector3(-sin(yaw), 0, -cos(yaw))
	var right := f.cross(n).normalized() * -1.0
	var fdir := n.cross(right).normalized() * -1.0
	basis = basis.slerp(Basis(right * -1.0, n, fdir * -1.0).orthonormalized(), clampf(4.0 * delta, 0.0, 1.0)).orthonormalized()
	blob.global_position = Vector3(global_position.x, terrain.height(global_position.x, global_position.z) + 0.05, global_position.z)
	blob.rotation = Vector3(-PI / 2, yaw, 0)

func _has_los() -> bool:
	var from := global_position + Vector3(0, 1.8, 0)
	var to := player.global_position + Vector3(0, 1.6, 0)
	var q := PhysicsRayQueryParameters3D.create(from, to, 1, [get_rid()])
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()

func _update_combat(delta: float, dist: float) -> void:
	# turret tracks player with lead
	var flight_t := dist / 62.0
	var predicted := player.global_position + player.velocity * flight_t * 0.85
	var local := to_local(predicted)
	var want := atan2(-local.x, -local.z)
	var cur := turret.rotation.y
	var dy := wrapf(want - cur, -PI, PI)
	turret.rotation.y = cur + clampf(dy, -0.8 * delta, 0.8 * delta)
	fire_timer -= delta
	if fire_timer <= 0.0 and absf(dy) < 0.06 and Game.alive:
		fire_timer = cadence + Game.rng.randf_range(-1.0, 1.5)
		_fire(predicted)

func _fire(target: Vector3) -> void:
	var muzzle_pos := turret.to_global(Vector3(0, 0.3, -4.2))
	var to := target - muzzle_pos
	var flat_dist := Vector2(to.x, to.z).length()
	var v := 70.0
	var g := 9.8
	var sin2 := clampf(g * flat_dist / (v * v), 0.0, 1.0)
	var ang := 0.5 * asin(sin2) + atan2(to.y, flat_dist) * 0.5
	var dir_flat := Vector3(to.x, 0, to.z).normalized()
	dir_flat = dir_flat.rotated(Vector3.UP, Game.rng.randf_range(-accuracy, accuracy))
	var vel := dir_flat * cos(ang) * v + Vector3.UP * sin(ang) * v
	projectiles.fire(Projectiles.Kind.ENEMY_SHELL, muzzle_pos, vel, [get_rid()], false)
	fx.muzzle_flash(muzzle_pos, 1.4)
	Sfx.play_at("cannon", muzzle_pos, -2.0, 0.9)

func take_damage(amount: float, at: Vector3) -> void:
	if state == State.DEAD:
		return
	hp -= amount
	Sfx.play_at("hit", at, -4.0)
	if hp <= 0.0:
		_die()

func _die() -> void:
	state = State.DEAD
	_dead_t = 0.0
	remove_from_group("enemies")
	collision_layer = 0
	fx.explosion(global_position + Vector3(0, 1.5, 0), true, player.global_position)
	fx.smoke_column(global_position + Vector3(0, 1.8, 0), 20.0)
	Game.add_score(100)
	# turret pop
	turret.top_level = true
	_turret_vel = Vector3(Game.rng.randf_range(-2, 2), Game.rng.randf_range(9, 13), Game.rng.randf_range(-2, 2))
	_turret_spin = Vector3(Game.rng.randf_range(-4, 4), Game.rng.randf_range(-6, 6), Game.rng.randf_range(-4, 4))
	# char the hull
	for child in get_children():
		if child is MeshInstance3D and child != blob:
			var m := StandardMaterial3D.new()
			m.albedo_color = Color(0.09, 0.085, 0.08)
			m.roughness = 1.0
			child.material_override = m

func _dead_update(delta: float) -> void:
	_dead_t += delta
	if _dead_t < 3.0:
		_turret_vel.y -= 9.8 * delta
		turret.global_position += _turret_vel * delta
		turret.rotation += _turret_spin * delta
		var ty := terrain.height(turret.global_position.x, turret.global_position.z)
		if turret.global_position.y < ty + 0.3 and _turret_vel.y < 0:
			_turret_vel = Vector3.ZERO
			_turret_spin = Vector3.ZERO
			turret.global_position.y = ty + 0.3
			var m := StandardMaterial3D.new()
			m.albedo_color = Color(0.1, 0.095, 0.09)
			turret.get_child(0).material_override = m
	if _dead_t > 25.0:
		blob.queue_free()
		turret.queue_free()
		queue_free()

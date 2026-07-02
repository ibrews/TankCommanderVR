# Pooled projectile system. Terrain hits are analytic (y vs terrain.height),
# body hits via segment raycast per frame. Player rockets get mild homing.
class_name Projectiles
extends Node3D

enum Kind { SHELL, ROCKET, MG, ENEMY_SHELL, PLANE_ROCKET }

const POOL := 48
const GRAV := {Kind.SHELL: 3.0, Kind.ROCKET: 0.0, Kind.MG: 0.0, Kind.ENEMY_SHELL: 9.8, Kind.PLANE_ROCKET: 1.0}
const TTL := {Kind.SHELL: 7.0, Kind.ROCKET: 7.0, Kind.MG: 1.4, Kind.ENEMY_SHELL: 9.0, Kind.PLANE_ROCKET: 6.0}
const DIRECT := {Kind.SHELL: 34.0, Kind.ROCKET: 26.0, Kind.MG: 4.0, Kind.ENEMY_SHELL: 16.0, Kind.PLANE_ROCKET: 11.0}
const SPLASH_R := {Kind.SHELL: 4.5, Kind.ROCKET: 6.0, Kind.MG: 0.0, Kind.ENEMY_SHELL: 3.5, Kind.PLANE_ROCKET: 5.0}
const SPLASH_DMG := {Kind.SHELL: 20.0, Kind.ROCKET: 22.0, Kind.MG: 0.0, Kind.ENEMY_SHELL: 10.0, Kind.PLANE_ROCKET: 8.0}

var terrain: Terrain
var fx: FxPool
var cam: Node3D  # for explosion sound distance

var _active: Array[Dictionary] = []
var _free_meshes := {}
var _trail_pool: Array[GPUParticles3D] = []

func _init(t: Terrain, f: FxPool) -> void:
	terrain = t
	fx = f
	name = "Projectiles"

func _ready() -> void:
	_free_meshes = {
		Kind.SHELL: _make_pool(_tracer_mesh(0.5, 0.09, Color(1.0, 0.65, 0.25)), 10),
		Kind.ROCKET: _make_pool(_rocket_mesh(), 10),
		Kind.MG: _make_pool(_tracer_mesh(0.65, 0.035, Color(1.0, 0.9, 0.4)), 16),
		Kind.ENEMY_SHELL: _make_pool(_tracer_mesh(0.5, 0.09, Color(1.0, 0.35, 0.2)), 8),
		Kind.PLANE_ROCKET: _make_pool(_tracer_mesh(0.5, 0.06, Color(1.0, 0.5, 0.3)), 8),
	}
	for i in 10:
		var p := _make_trail()
		_trail_pool.append(p)

func _tracer_mesh(length: float, r: float, col: Color) -> ArrayMesh:
	var st := MeshKit.begin()
	MeshKit.box(st, Transform3D(), Vector3(r, r, length), col)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 2.0
	return MeshKit.commit(st, m)

func _rocket_mesh() -> ArrayMesh:
	var st := MeshKit.begin()
	var body := Color(0.85, 0.85, 0.82)
	MeshKit.cyl(st, Transform3D(Basis(Vector3.RIGHT, PI / 2)), 0.07, 0.07, 0.55, 6, body)
	MeshKit.cyl(st, Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(0, 0, -0.35)), 0.07, 0.0, 0.15, 6, Color(0.9, 0.3, 0.2))
	return MeshKit.commit(st, MeshKit.mat_vcol(0.5))

func _make_pool(mesh: ArrayMesh, count: int) -> Array:
	var arr := []
	for i in count:
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.visible = false
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		arr.append(mi)
	return arr

func _make_trail() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 30
	p.lifetime = 0.7
	p.emitting = false
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 0, 1)
	pm.spread = 8.0
	pm.initial_velocity_min = 0.5
	pm.initial_velocity_max = 1.5
	pm.gravity = Vector3(0, 0.6, 0)
	pm.scale_min = 0.25
	pm.scale_max = 0.5
	var grad := Gradient.new()
	grad.set_color(0, Color(0.9, 0.85, 0.8, 0.8))
	grad.set_color(1, Color(0.7, 0.7, 0.7, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = load("res://assets/tex/smoke.png")
	m.vertex_color_use_as_albedo = true
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	quad.material = m
	p.draw_pass_1 = quad
	add_child(p)
	return p

func fire(kind: int, pos: Vector3, vel: Vector3, exclude: Array = [], from_player := false) -> void:
	var pool: Array = _free_meshes[kind]
	var mesh: MeshInstance3D = null
	for mi in pool:
		if not mi.visible:
			mesh = mi
			break
	if mesh == null:
		mesh = pool[0]
	mesh.visible = true
	mesh.global_position = pos
	var trail: GPUParticles3D = null
	if kind == Kind.ROCKET or kind == Kind.PLANE_ROCKET:
		for t in _trail_pool:
			if not t.emitting:
				trail = t
				break
		if trail:
			trail.global_position = pos
			trail.emitting = true
	_active.append({
		"kind": kind, "pos": pos, "vel": vel, "ttl": TTL[kind], "mesh": mesh,
		"exclude": exclude, "player": from_player, "trail": trail, "age": 0.0,
	})

func _physics_process(delta: float) -> void:
	if _active.is_empty():
		return
	var space := get_world_3d().direct_space_state
	var i := _active.size() - 1
	while i >= 0:
		var p := _active[i]
		p.age += delta
		p.ttl -= delta
		var kind: int = p.kind
		# rocket thrust + homing
		if kind == Kind.ROCKET:
			var speed: float = p.vel.length()
			if speed < 120.0:
				p.vel = p.vel.normalized() * (speed + 60.0 * delta)
			var tgt := _seek_target(p.pos, p.vel)
			if tgt != Vector3.INF:
				var want: Vector3 = (tgt - p.pos).normalized()
				var cur: Vector3 = p.vel.normalized()
				p.vel = cur.slerp(want, clampf(1.6 * delta, 0.0, 1.0)) * p.vel.length()
		p.vel.y -= GRAV[kind] * delta
		var new_pos: Vector3 = p.pos + p.vel * delta
		var hit := false
		# body hit
		var mask := (1 | 4) if p.player else (1 | 2)
		var q := PhysicsRayQueryParameters3D.create(p.pos, new_pos, mask, p.exclude)
		var res := space.intersect_ray(q)
		if res:
			hit = true
			_impact(p, res.position, res.collider)
		elif new_pos.y < terrain.height(new_pos.x, new_pos.z):
			hit = true
			var gp := new_pos
			gp.y = terrain.height(new_pos.x, new_pos.z)
			_impact(p, gp, null)
		if hit or p.ttl <= 0.0:
			p.mesh.visible = false
			if p.trail:
				p.trail.emitting = false
			_active.remove_at(i)
		else:
			p.pos = new_pos
			p.mesh.global_position = new_pos
			if p.vel.length_squared() > 0.01:
				p.mesh.look_at(new_pos + p.vel)
			if p.trail:
				p.trail.global_position = new_pos
		i -= 1

func _seek_target(pos: Vector3, vel: Vector3) -> Vector3:
	var dir := vel.normalized()
	var best := Vector3.INF
	var best_score := -1.0
	for grp in ["planes", "enemies"]:
		var cone := 0.55 if grp == "planes" else 0.92  # wider cone for planes (cos)
		for n in get_tree().get_nodes_in_group(grp):
			var node := n as Node3D
			if node == null:
				continue
			var to := node.global_position - pos
			var d := to.length()
			if d > 300.0 or d < 6.0:
				continue
			var c := dir.dot(to / d)
			if c < cone:
				continue
			var score := c * 2.0 - d / 300.0 + (1.0 if grp == "planes" else 0.0)
			if score > best_score:
				best_score = score
				best = node.global_position
	return best

func _impact(p: Dictionary, at: Vector3, collider: Object) -> void:
	var kind: int = p.kind
	if collider and collider.has_method("take_damage"):
		collider.take_damage(DIRECT[kind], at)
	if kind == Kind.MG:
		if collider == null:
			Sfx.play_at("ricochet", at, -10.0)
		return
	var cam_pos := cam.global_position if cam else Vector3.ZERO
	fx.explosion(at, kind == Kind.ROCKET or kind == Kind.SHELL, cam_pos)
	# splash
	var r: float = SPLASH_R[kind]
	if r <= 0.0:
		return
	var groups := ["enemies", "planes"] if p.player else ["player"]
	for grp in groups:
		for n in get_tree().get_nodes_in_group(grp):
			var node := n as Node3D
			if node == null or not node.has_method("take_damage"):
				continue
			var d := node.global_position.distance_to(at)
			if d < r + 2.5 and not (collider == node):
				node.take_damage(SPLASH_DMG[kind] * clampf(1.0 - d / (r + 2.5), 0.2, 1.0), at)

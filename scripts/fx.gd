# Pooled visual effects v2: multi-stage explosions (core flash, shockwave
# ring, ballistic debris, fire), spark bursts, dust, smoke columns + fire
# columns for burning wrecks. All one-shot, pooled, mobile-budget friendly.
class_name FxPool
extends Node3D

var _explosions: Array = []
var _flashes: Array = []
var _columns: Array = []
var _debris: Array = []
var _rings: Array = []
var _dusts: Array = []
var _splats: Array = []
var _confetti: Array = []

func _init() -> void:
	name = "Fx"

func _ready() -> void:
	add_to_group("fx")
	for i in 8:
		_explosions.append(_make_explosion())
	for i in 6:
		_flashes.append(_make_flash())
	for i in 5:
		_columns.append(_make_column())
	for i in 24:
		_debris.append(_make_debris_chunk())
	for i in 6:
		_rings.append(_make_ring())
	for i in 6:
		_dusts.append(_make_dust())
	for i in 40:
		_splats.append(_make_splat())
	for i in 4:
		_confetti.append(_make_confetti())

func _smoke_mat(tex_path: String, additive := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = load(tex_path)
	m.vertex_color_use_as_albedo = true
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.disable_receive_shadows = true
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	return m

func _particles(amount: int, lifetime: float, vel_min: float, vel_max: float,
		scale_min: float, scale_max: float, gravity: Vector3, tex: String,
		ramp_from: Color, ramp_to: Color, additive := false) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.one_shot = true
	p.explosiveness = 1.0
	p.emitting = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 70.0
	pm.initial_velocity_min = vel_min
	pm.initial_velocity_max = vel_max
	pm.gravity = gravity
	pm.scale_min = scale_min
	pm.scale_max = scale_max
	pm.damping_min = 1.0
	pm.damping_max = 2.5
	var grad := Gradient.new()
	grad.set_color(0, ramp_from)
	grad.set_color(1, ramp_to)
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	quad.material = _smoke_mat(tex, additive)
	p.draw_pass_1 = quad
	return p

# ---------------- factories
func _make_explosion() -> Dictionary:
	var root := Node3D.new()
	root.visible = false
	add_child(root)
	var smoke := _particles(20, 1.7, 3.0, 10.0, 1.8, 3.8, Vector3(0, 1.5, 0),
		"res://assets/tex/smoke.png", Color(0.30, 0.28, 0.26, 1.0), Color(0.5, 0.5, 0.5, 0.0))
	root.add_child(smoke)
	var fire := _particles(14, 0.6, 4.0, 13.0, 1.2, 2.6, Vector3(0, 3.0, 0),
		"res://assets/tex/flash.png", Color(1.0, 0.78, 0.3, 1.0), Color(1.0, 0.22, 0.04, 0.0), true)
	root.add_child(fire)
	var sparks := _particles(16, 0.9, 10.0, 22.0, 0.12, 0.3, Vector3(0, -14.0, 0),
		"res://assets/tex/flash.png", Color(1.0, 0.9, 0.5, 1.0), Color(1.0, 0.5, 0.1, 0.0), true)
	root.add_child(sparks)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.7, 0.35)
	light.omni_range = 22.0
	light.light_energy = 0.0
	light.shadow_enabled = false
	root.add_child(light)
	return {"root": root, "smoke": smoke, "fire": fire, "sparks": sparks, "light": light, "t": 99.0}

func _make_flash() -> Dictionary:
	var root := Node3D.new()
	root.visible = false
	add_child(root)
	var quad := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(1.6, 1.6)
	quad.mesh = qm
	var m := _smoke_mat("res://assets/tex/flash.png", true)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	quad.material_override = m
	root.add_child(quad)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.8, 0.4)
	light.omni_range = 9.0
	light.shadow_enabled = false
	root.add_child(light)
	return {"root": root, "quad": quad, "light": light, "t": 99.0}

func _make_column() -> Dictionary:
	var root := Node3D.new()
	add_child(root)
	var p := _particles(26, 3.5, 1.5, 3.0, 1.8, 3.4, Vector3(0, 1.2, 0),
		"res://assets/tex/smoke.png", Color(0.10, 0.095, 0.09, 0.9), Color(0.32, 0.32, 0.32, 0.0))
	p.one_shot = false
	p.explosiveness = 0.0
	root.add_child(p)
	var fire := _particles(10, 0.8, 1.0, 2.5, 0.7, 1.5, Vector3(0, 2.5, 0),
		"res://assets/tex/flash.png", Color(1.0, 0.6, 0.15, 0.9), Color(1.0, 0.2, 0.05, 0.0), true)
	fire.one_shot = false
	fire.explosiveness = 0.0
	root.add_child(fire)
	return {"root": root, "p": p, "fire": fire, "t": 99.0, "duration": 18.0}

func _make_debris_chunk() -> Dictionary:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.28, 0.22, 0.3)
	mi.mesh = bm
	mi.material_override = MeshKit.mat_vcol()
	mi.visible = false
	add_child(mi)
	return {"mesh": mi, "vel": Vector3.ZERO, "spin": Vector3.ZERO, "t": 99.0}

func _make_ring() -> Dictionary:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.85
	tm.outer_radius = 1.0
	tm.rings = 4
	tm.ring_segments = 20
	mi.mesh = tm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1.0, 0.85, 0.6, 0.55)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mi.material_override = m
	mi.visible = false
	add_child(mi)
	return {"mesh": mi, "mat": m, "t": 99.0}

func _make_dust() -> Dictionary:
	var p := _particles(14, 1.4, 2.0, 5.0, 1.2, 2.6, Vector3(0, 0.6, 0),
		"res://assets/tex/smoke.png", Color(0.55, 0.48, 0.38, 0.7), Color(0.6, 0.55, 0.45, 0.0))
	add_child(p)
	return {"p": p, "t": 99.0}

func _make_splat() -> Dictionary:
	var mi := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(1, 1)
	mi.mesh = qm
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = load("res://assets/tex/blob_shadow.png")  # radial mask, tinted
	m.albedo_color = Color(1, 0, 0, 0.9)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	mi.visible = false
	add_child(mi)
	return {"mesh": mi, "mat": m, "t": 999.0}

func _make_confetti() -> Dictionary:
	var p := _particles(26, 1.6, 5.0, 11.0, 0.18, 0.4, Vector3(0, -9.0, 0),
		"res://assets/tex/flash.png", Color(1, 1, 1, 1), Color(1, 1, 1, 0.0), false)
	# rainbow ramp
	var grad := Gradient.new()
	grad.add_point(0.0, Color(1, 0.3, 0.3))
	grad.add_point(0.33, Color(1, 0.9, 0.2))
	grad.add_point(0.66, Color(0.3, 0.9, 1.0))
	grad.add_point(1.0, Color(1, 0.4, 1.0, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	(p.process_material as ParticleProcessMaterial).color_ramp = gt
	add_child(p)
	return {"p": p, "t": 99.0}

# ---------------- public API
func explosion(pos: Vector3, big := false, cam_pos := Vector3.ZERO) -> void:
	if Game.mutator == "balloon":
		balloon_pop(pos)   # total conversion: every boom is a pop
		return
	var paint := Game.mutator == "paintball"
	var best: Dictionary = _explosions[0]
	for e in _explosions:
		if e.t > best.t:
			best = e
	best.t = 0.0
	best.root.visible = true
	best.root.global_position = pos
	var s := 1.7 if big else 1.0
	best.root.scale = Vector3.ONE * s
	if paint:
		var pc := Game.paint_color()
		_tint_particles(best.fire, pc, Color(pc, 0.0))
		_tint_particles(best.smoke, pc.lightened(0.2), Color(pc.lightened(0.4), 0.0))
		paint_splat(pos, pc, s * 2.2)
		Sfx.play_at("splat", pos, 2.0)
	else:
		_tint_particles(best.fire, Color(1.0, 0.78, 0.3), Color(1.0, 0.22, 0.04, 0.0))
		_tint_particles(best.smoke, Color(0.30, 0.28, 0.26), Color(0.5, 0.5, 0.5, 0.0))
	best.smoke.restart()
	best.fire.restart()
	best.sparks.restart()
	best.light.light_energy = 7.0 * s
	shockwave(pos, s)
	debris_burst(pos, 8 if big else 5, Color(0.2, 0.18, 0.16))
	var d := cam_pos.distance_to(pos)
	if paint:
		Sfx.play_at("splat", pos, 0.0, 0.8)
	else:
		Sfx.play_at("explosion_far" if d > 110.0 else "explosion", pos, 3.0 if big else 0.0)

func _tint_particles(p: GPUParticles3D, from: Color, to: Color) -> void:
	var pm := p.process_material as ParticleProcessMaterial
	var grad := Gradient.new()
	grad.set_color(0, from)
	grad.set_color(1, to)
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt

func paint_splat(pos: Vector3, color: Color, size := 1.6) -> void:
	var best: Dictionary = _splats[0]
	for sp in _splats:
		if sp.t > best.t:
			best = sp
	best.t = 0.0
	best.mesh.visible = true
	var terrain: Terrain = get_tree().get_first_node_in_group("main").terrain
	var gy: float = terrain.height(pos.x, pos.z) if terrain else pos.y
	best.mesh.global_position = Vector3(pos.x, gy + 0.04 + Game.rng.randf() * 0.02, pos.z)
	best.mesh.rotation = Vector3(-PI / 2, Game.rng.randf() * TAU, 0)
	best.mesh.scale = Vector3.ONE * size * Game.rng.randf_range(0.8, 1.4)
	best.mat.albedo_color = Color(color.r, color.g, color.b, 0.85)

func balloon_pop(pos: Vector3) -> void:
	var best: Dictionary = _confetti[0]
	for c in _confetti:
		if c.t > best.t:
			best = c
	best.t = 0.0
	best.p.global_position = pos
	best.p.restart()
	Sfx.play_at("pop", pos, 2.0)
	Sfx.play_at("squeak", pos, -4.0, Game.rng.randf_range(0.8, 1.3))
	shockwave(pos, 0.7)

func shockwave(pos: Vector3, s := 1.0) -> void:
	var best: Dictionary = _rings[0]
	for r in _rings:
		if r.t > best.t:
			best = r
	best.t = 0.0
	best.mesh.visible = true
	best.mesh.global_position = pos + Vector3(0, 0.4, 0)
	best.mesh.scale = Vector3.ONE * 0.5 * s
	best.mesh.set_meta("s", s)

func debris_burst(pos: Vector3, count: int, _col: Color) -> void:
	var used := 0
	for d in _debris:
		if d.t > 10.0 and used < count:
			used += 1
			d.t = 0.0
			d.mesh.visible = true
			d.mesh.global_position = pos
			d.mesh.scale = Vector3.ONE * Game.rng.randf_range(0.6, 1.8)
			d.vel = Vector3(Game.rng.randf_range(-7, 7), Game.rng.randf_range(6, 15), Game.rng.randf_range(-7, 7))
			d.spin = Vector3(Game.rng.randf_range(-8, 8), Game.rng.randf_range(-8, 8), Game.rng.randf_range(-8, 8))

func spark_burst(pos: Vector3) -> void:
	var best: Dictionary = _explosions[0]
	for e in _explosions:
		if e.t > best.t:
			best = e
	# reuse sparks pass only
	best.sparks.global_position = pos
	best.sparks.restart()

func dust(pos: Vector3, s := 1.0) -> void:
	var best: Dictionary = _dusts[0]
	for d in _dusts:
		if d.t > best.t:
			best = d
	best.t = 0.0
	best.p.global_position = pos
	best.p.scale = Vector3.ONE * s
	best.p.restart()

func muzzle_flash(pos: Vector3, scale := 1.0) -> void:
	var best: Dictionary = _flashes[0]
	for f in _flashes:
		if f.t > best.t:
			best = f
	best.t = 0.0
	best.root.visible = true
	best.root.global_position = pos
	best.root.scale = Vector3.ONE * scale
	best.light.light_energy = 4.0 * scale

func smoke_column(pos: Vector3, duration := 18.0) -> void:
	var best: Dictionary = _columns[0]
	for c in _columns:
		if c.t > best.t:
			best = c
	best.t = 0.0
	best.duration = duration
	best.root.global_position = pos
	best.p.emitting = true
	best.fire.emitting = true

# ---------------- animation
func _process(delta: float) -> void:
	for e in _explosions:
		if e.t < 10.0:
			e.t += delta
			e.light.light_energy = maxf(0.0, e.light.light_energy - delta * 24.0)
			if e.t > 2.4:
				e.root.visible = false
				e.t = 99.0
	for f in _flashes:
		if f.t < 10.0:
			f.t += delta
			var k := clampf(1.0 - f.t / 0.09, 0.0, 1.0)
			f.light.light_energy = 4.0 * k
			f.quad.scale = Vector3.ONE * (0.7 + 0.9 * (1.0 - k))
			if f.t > 0.1:
				f.root.visible = false
				f.t = 99.0
	for c in _columns:
		if c.t < 90.0:
			c.t += delta
			if c.t > c.get("duration", 18.0):
				c.p.emitting = false
				c.fire.emitting = false
				c.t = 99.0
	for r in _rings:
		if r.t < 10.0:
			r.t += delta
			var life := 0.45
			var k := clampf(r.t / life, 0.0, 1.0)
			var s: float = r.mesh.get_meta("s", 1.0)
			r.mesh.scale = Vector3.ONE * lerpf(0.5, 11.0, k) * s
			r.mat.albedo_color.a = 0.55 * (1.0 - k)
			if k >= 1.0:
				r.mesh.visible = false
				r.t = 99.0
	for d in _debris:
		if d.t < 10.0:
			d.t += delta
			d.vel.y -= 22.0 * delta
			d.mesh.global_position += d.vel * delta
			d.mesh.rotation += d.spin * delta
			if d.t > 1.6:
				d.mesh.visible = false
				d.t = 99.0
	for du in _dusts:
		if du.t < 10.0:
			du.t += delta
			if du.t > 1.6:
				du.t = 99.0
	for sp in _splats:
		if sp.t < 990.0:
			sp.t += delta
			if sp.t > 25.0:
				sp.mat.albedo_color.a = maxf(0.0, 0.85 - (sp.t - 25.0) * 0.2)
				if sp.t > 30.0:
					sp.mesh.visible = false
					sp.t = 999.0
	for c in _confetti:
		if c.t < 10.0:
			c.t += delta
			if c.t > 2.0:
				c.t = 99.0

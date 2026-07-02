# Pooled visual effects: explosions (flash + smoke + brief light), muzzle
# flashes, dust puffs, smoke columns for wrecks. All one-shot, reused.
class_name FxPool
extends Node3D

var _explosions: Array = []
var _flashes: Array = []
var _columns: Array = []

func _init() -> void:
	name = "Fx"

func _ready() -> void:
	for i in 8:
		_explosions.append(_make_explosion())
	for i in 6:
		_flashes.append(_make_flash())
	for i in 5:
		_columns.append(_make_column())

func _smoke_mat(tex_path: String, emissive := false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_texture = load(tex_path)
	m.vertex_color_use_as_albedo = true
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.disable_receive_shadows = true
	if emissive:
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

func _make_explosion() -> Dictionary:
	var root := Node3D.new()
	root.visible = false
	add_child(root)
	var smoke := _particles(18, 1.5, 3.0, 9.0, 1.6, 3.4, Vector3(0, 1.5, 0),
		"res://assets/tex/smoke.png", Color(0.32, 0.30, 0.28, 1.0), Color(0.5, 0.5, 0.5, 0.0))
	root.add_child(smoke)
	var fire := _particles(10, 0.5, 4.0, 11.0, 1.0, 2.2, Vector3(0, 3.0, 0),
		"res://assets/tex/flash.png", Color(1.0, 0.75, 0.3, 1.0), Color(1.0, 0.25, 0.05, 0.0), true)
	root.add_child(fire)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.7, 0.35)
	light.omni_range = 18.0
	light.light_energy = 0.0
	light.shadow_enabled = false
	root.add_child(light)
	return {"root": root, "smoke": smoke, "fire": fire, "light": light, "t": 99.0}

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
	var p := _particles(24, 3.5, 1.5, 3.0, 1.8, 3.2, Vector3(0, 1.2, 0),
		"res://assets/tex/smoke.png", Color(0.12, 0.11, 0.10, 0.9), Color(0.35, 0.35, 0.35, 0.0))
	p.one_shot = false
	p.explosiveness = 0.0
	add_child(p)
	return {"p": p, "t": 99.0}

func explosion(pos: Vector3, big := false, cam_pos := Vector3.ZERO) -> void:
	var best: Dictionary = _explosions[0]
	for e in _explosions:
		if e.t > best.t:
			best = e
		if e.t > 10.0:
			best = e
			break
	best.t = 0.0
	best.root.visible = true
	best.root.global_position = pos
	var s := 1.6 if big else 1.0
	best.root.scale = Vector3.ONE * s
	best.smoke.restart()
	best.fire.restart()
	best.light.light_energy = 6.0 * s
	var d := cam_pos.distance_to(pos)
	Sfx.play_at("explosion_far" if d > 110.0 else "explosion", pos, 2.0 if big else 0.0)

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
	best.p.global_position = pos
	best.p.emitting = true

func _process(delta: float) -> void:
	for e in _explosions:
		if e.t < 10.0:
			e.t += delta
			e.light.light_energy = maxf(0.0, e.light.light_energy - delta * 22.0)
			if e.t > 2.2:
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
				c.t = 99.0

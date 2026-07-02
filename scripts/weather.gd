# Weather + sky events: random rainstorms (rain particles follow the player,
# thunder + lightning flashes, wind gusts, darkened ambience) and the
# natural-disaster easter egg payloads (tornado / volcano / hurricane).
class_name Weather
extends Node3D

enum SkyState { CLEAR, BUILDING, STORM, CLEARING }

var terrain: Terrain
var fx: FxPool
var player: Node3D
var env: Environment
var sun: DirectionalLight3D

var state: int = SkyState.CLEAR
var _t := 0.0
var _next_check := 25.0
var _storm_len := 80.0
var _intensity := 1.0     # hurricane = 2.0
var _forced := false

var rain: GPUParticles3D
var rain_p: AudioStreamPlayer
var _thunder_t := 8.0
var _gust_t := 15.0
var wind_push := Vector3.ZERO   # sampled by the tank

# disaster state
var disaster := ""            # "", "tornado", "volcano", "hurricane"
var _dis_t := 0.0
var tornado_root: Node3D
var _tor_angle := 0.0
var _volcano_pos := Vector3.ZERO
var _dis_audio: AudioStreamPlayer3D
var _lava_t := 0.0

func _init(t: Terrain, f: FxPool, p: Node3D, e: Environment, s: DirectionalLight3D) -> void:
	terrain = t
	fx = f
	player = p
	env = e
	sun = s
	name = "Weather"

func _ready() -> void:
	add_to_group("weather")
	rain = _make_rain()
	add_child(rain)
	rain_p = AudioStreamPlayer.new()
	rain_p.stream = Sfx.streams.get("rain_loop")
	rain_p.volume_db = -80.0
	rain_p.autoplay = true
	add_child(rain_p)

func _make_rain() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 420
	p.lifetime = 1.1
	p.emitting = false
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(26, 1, 26)
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 3.0
	pm.initial_velocity_min = 18.0
	pm.initial_velocity_max = 24.0
	pm.gravity = Vector3(0, -6, 0)
	pm.scale_min = 0.8
	pm.scale_max = 1.2
	p.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.03, 0.6)
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.7, 0.78, 0.9, 0.35)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	quad.material = m
	p.draw_pass_1 = quad
	return p

func force_storm(intensity: float, dur: float) -> void:
	_intensity = intensity
	_storm_len = dur
	_forced = true
	state = SkyState.BUILDING
	_t = 0.0

func _process(delta: float) -> void:
	_t += delta
	match state:
		SkyState.CLEAR:
			_gusts(delta)
			if _t > _next_check:
				_t = 0.0
				_next_check = Game.rng.randf_range(20.0, 45.0)
				if Game.rng.randf() < 0.22:
					_intensity = 1.0
					_storm_len = Game.rng.randf_range(55.0, 110.0)
					state = SkyState.BUILDING
					_t = 0.0
		SkyState.BUILDING:
			var k := clampf(_t / 12.0, 0.0, 1.0)
			_apply_gloom(k * 0.6 * _intensity)
			if _t > 12.0:
				state = SkyState.STORM
				_t = 0.0
				rain.emitting = true
				Sfx.play_ui("wind_gust", -6.0)
		SkyState.STORM:
			_apply_gloom((0.6 + 0.4 * clampf(_t / 8.0, 0.0, 1.0)) * _intensity)
			rain_p.volume_db = move_toward(rain_p.volume_db, -8.0 + (_intensity - 1.0) * 6.0, delta * 20.0)
			rain.global_position = player.global_position + Vector3(0, 17, 0)
			_thunder_t -= delta
			if _thunder_t <= 0.0:
				_thunder_t = Game.rng.randf_range(4.0, 14.0) / _intensity
				_lightning()
			# hurricane-force wind shoves the tank around
			if _intensity > 1.5:
				var a := _t * 0.35
				wind_push = Vector3(cos(a), 0, sin(a)) * 3.2
				_gust_t -= delta
				if _gust_t <= 0.0:
					_gust_t = 2.0
					fx.debris_burst(player.global_position + Vector3(Game.rng.randf_range(-15, 15), 6, Game.rng.randf_range(-15, 15)), 3, Color(0.4, 0.35, 0.3))
			if _t > _storm_len:
				state = SkyState.CLEARING
				_t = 0.0
				rain.emitting = false
				wind_push = Vector3.ZERO
		SkyState.CLEARING:
			_apply_gloom((1.0 - clampf(_t / 10.0, 0.0, 1.0)) * 0.6 * _intensity)
			rain_p.volume_db = move_toward(rain_p.volume_db, -80.0, delta * 8.0)
			if _t > 10.0:
				state = SkyState.CLEAR
				_t = 0.0
				_forced = false
	_update_disaster(delta)

func _gusts(delta: float) -> void:
	_gust_t -= delta
	if _gust_t <= 0.0:
		_gust_t = Game.rng.randf_range(14.0, 30.0)
		Sfx.play_at("wind_gust", player.global_position + Vector3(Game.rng.randf_range(-20, 20), 8, Game.rng.randf_range(-20, 20)), -10.0)

func _apply_gloom(k: float) -> void:
	if env == null or sun == null:
		return
	var base: float = Levels.current.get("sun_energy", 1.25)
	sun.light_energy = base * (1.0 - 0.72 * clampf(k, 0.0, 1.0))
	env.ambient_light_energy = 0.85 * (1.0 - 0.45 * clampf(k, 0.0, 1.0))
	env.fog_density = 0.0005 + 0.0022 * clampf(k, 0.0, 1.0)

func _lightning() -> void:
	if sun == null:
		return
	var orig := sun.light_energy
	sun.light_energy = 3.2
	Sfx.play_ui("thunder1" if Game.rng.randf() > 0.5 else "thunder2", -2.0)
	get_tree().create_timer(0.12).timeout.connect(func():
		if sun:
			sun.light_energy = orig)

# ================================================================ disasters
func start_disaster(kind: String) -> void:
	if disaster != "":
		return
	disaster = kind
	_dis_t = 0.0
	match kind:
		"tornado":
			Sfx.vo("vo_tornado", 4, 5.0)
			_spawn_tornado()
		"volcano":
			Sfx.vo("vo_volcano", 4, 5.0)
			_spawn_volcano()
		"hurricane":
			Sfx.vo("vo_hurricane", 4, 5.0)
			force_storm(2.0, 55.0)
			_dis_audio = Sfx.make_loop_player("wind_gust", self, -4.0, 20.0)
			_dis_audio.play()

func _spawn_tornado() -> void:
	tornado_root = Node3D.new()
	add_child(tornado_root)
	var grey := Color(0.35, 0.33, 0.32, 0.55)
	for i in 7:
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		var r := 2.0 + i * 2.6
		cm.top_radius = r * 1.15
		cm.bottom_radius = r * 0.7
		cm.height = 9.0
		cm.radial_segments = 10
		mi.mesh = cm
		var m := StandardMaterial3D.new()
		m.albedo_color = grey
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mi.material_override = m
		mi.position = Vector3(Game.rng.randf_range(-1.5, 1.5), 4.0 + i * 8.0, Game.rng.randf_range(-1.5, 1.5))
		tornado_root.add_child(mi)
	var p := player.global_position
	tornado_root.global_position = p + Vector3(Game.rng.randf_range(-80, 80), 0, Game.rng.randf_range(-80, 80))
	_dis_audio = Sfx.make_loop_player("tornado_loop", tornado_root, 6.0, 26.0)
	_dis_audio.max_distance = 500.0
	_dis_audio.play()

func _spawn_volcano() -> void:
	# erupts from the rim, north of the arena
	_volcano_pos = Vector3(0, 0, -215)
	_volcano_pos.y = terrain.height(_volcano_pos.x, _volcano_pos.z)
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.4, 0.1)
	glow.omni_range = 90.0
	glow.light_energy = 2.5
	glow.shadow_enabled = false
	glow.position = _volcano_pos + Vector3(0, 20, 0)
	add_child(glow)
	get_tree().create_timer(42.0).timeout.connect(glow.queue_free)
	_dis_audio = Sfx.make_loop_player("volcano_loop", self, 4.0, 30.0)
	_dis_audio.max_distance = 600.0
	_dis_audio.position = _volcano_pos
	_dis_audio.play()
	Sfx.play_at("eruption", _volcano_pos + Vector3(0, 10, 0), 6.0, 1.0, 600.0)
	fx.explosion(_volcano_pos + Vector3(0, 8, 0), true, player.global_position)
	fx.smoke_column(_volcano_pos + Vector3(0, 12, 0), 45.0)

func _update_disaster(delta: float) -> void:
	if disaster == "":
		return
	_dis_t += delta
	match disaster:
		"tornado":
			_tor_angle += delta * 0.25
			var center := Vector3(cos(_tor_angle) * 60.0, 0, sin(_tor_angle) * 60.0)
			center.y = terrain.height(center.x, center.z)
			tornado_root.global_position = tornado_root.global_position.lerp(center, delta * 0.4)
			for i in tornado_root.get_child_count():
				var c := tornado_root.get_child(i) as MeshInstance3D
				if c:
					c.rotate_y((2.4 - i * 0.2) * delta * 6.0)
			# fling nearby enemies, shove the player
			var tp := tornado_root.global_position
			for n in get_tree().get_nodes_in_group("enemies"):
				if n is Node3D and n.global_position.distance_to(tp) < 22.0 and n.has_method("take_damage"):
					n.take_damage(60.0, n.global_position)
					fx.debris_burst(n.global_position + Vector3(0, 3, 0), 6, Color(0.3, 0.3, 0.3))
			var pd := player.global_position.distance_to(tp)
			if pd < 30.0:
				wind_push = (player.global_position - tp).normalized() * -4.0  # pulled in!
				if pd < 14.0 and player.has_method("take_damage"):
					player.take_damage(4.0 * delta, player.global_position)
			else:
				wind_push = Vector3.ZERO
			if _dis_t > 45.0:
				tornado_root.queue_free()
				_end_disaster()
		"volcano":
			_lava_t -= delta
			if _lava_t <= 0.0 and _dis_t < 38.0:
				_lava_t = Game.rng.randf_range(0.5, 1.4)
				var target := Vector3(Game.rng.randf_range(-160, 160), 0, Game.rng.randf_range(-160, 120))
				var from := _volcano_pos + Vector3(Game.rng.randf_range(-4, 4), 14, 0)
				var to := target - from
				var flat := Vector2(to.x, to.z).length()
				var v := 55.0
				var ang := (PI - asin(clampf(9.8 * flat / (v * v), 0, 1))) / 2.0
				var dirf := Vector3(to.x, 0, to.z).normalized()
				var proj: Projectiles = get_tree().get_first_node_in_group("main").projectiles
				# alternate sides so lava bombs threaten everyone equally
				var as_player := Game.rng.randf() > 0.5
				proj.fire(Projectiles.Kind.MORTAR, from, dirf * cos(ang) * v + Vector3.UP * sin(ang) * v, [], as_player)
			if _dis_t > 42.0:
				_end_disaster()
		"hurricane":
			if _dis_t > 55.0:
				_end_disaster()

func _end_disaster() -> void:
	disaster = ""
	wind_push = Vector3.ZERO
	if _dis_audio:
		_dis_audio.queue_free()
		_dis_audio = null

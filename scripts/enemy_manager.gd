# Wave spawner v2: escalating mixed waves (tanks, jeeps, gunner squads,
# mortars, planes), difficulty scaling, music threat reporting, VO callouts.
class_name EnemyManager
extends Node3D

var terrain: Terrain
var projectiles: Projectiles
var fx: FxPool
var player: CharacterBody3D   # PlayerTank or PlayerPlane

var wave := 0
var _between := 4.0
var _running := true

func _init(t: Terrain, p: Projectiles, f: FxPool, pl: CharacterBody3D) -> void:
	terrain = t
	projectiles = p
	fx = f
	player = pl
	name = "EnemyManager"

func _ready() -> void:
	Game.game_over.connect(func(): _running = false)
	Game.game_restarted.connect(_on_restart)
	if Game.mode == Game.Mode.VERSUS:
		_running = false  # pure duel: no AI waves

func _on_restart() -> void:
	for n in get_tree().get_nodes_in_group("enemies") + get_tree().get_nodes_in_group("planes"):
		n.queue_free()
	for c in get_children():
		c.queue_free()
	wave = 0
	_between = 5.0
	_running = Game.mode != Game.Mode.VERSUS

func _process(delta: float) -> void:
	if not _running:
		Sfx.set_threat(0.0)
		return
	var alive := 0
	var near := 0
	for c in get_children():
		if not is_instance_valid(c) or c.is_queued_for_deletion():
			continue
		var ok := true
		if c is EnemyTank and c.state == EnemyTank.State.DEAD:
			ok = false
		elif c is EnemyPlane and c.state == EnemyPlane.State.SPIRAL:
			ok = false
		elif c.get("_dead") == true:
			ok = false
		if ok:
			alive += 1
			if c is Node3D and c.global_position.distance_to(player.global_position) < 140.0:
				near += 1
	Sfx.set_threat(clampf(near / 2.0, 0.0, 1.0))
	if alive == 0:
		_between -= delta
		if _between <= 0.0:
			_spawn_wave()
	elif wave > 0:
		_between = 8.0

func _ring_pos(r_min: float, r_max: float) -> Vector3:
	var ring: Array = Levels.current.get("spawn_ring", [])
	if ring.size() == 2:
		r_min = ring[0]
		r_max = ring[1]
	var a := Game.rng.randf() * TAU
	var r := Game.rng.randf_range(r_min, r_max)
	var pos := Vector3(cos(a) * r, 0, sin(a) * r)
	pos.y = terrain.height(pos.x, pos.z) + 0.1
	return pos

func _spawn_wave() -> void:
	wave += 1
	Game.set_wave(wave)
	if wave > 1:
		Game.add_score(250)
		Sfx.sting("sting_wave")
		Sfx.vo("vo_wave_clear", 2, 15.0)
	else:
		Sfx.vo("vo_wave", 2, 4.0)
	if wave == 3:
		Sfx.vo("vo_wave2", 1, 20.0)

	if Levels.current.get("gym", false):
		Sfx.play_ui("whistle", -4.0)
		Sfx.vo("vo_gym_wave", 2, 25.0)
	var dm := Game.diff(0.6, 1.0, 1.5) * Tune.v("wave_size_scale")
	var tanks := mini(int((1 + wave * 0.8) * dm), 6)
	var jeeps := mini(int((wave - 1) * 0.8 * dm) + (1 if wave >= 2 else 0), 4)
	var squads := 1 if wave >= 2 else 0
	if wave >= 4:
		squads = 2
	var planes := 0
	if wave >= 2:
		planes = 1
	if wave >= 4:
		planes = mini(int(2 * dm), 3)
	var mortars: Array = Levels.current.get("mortars", []) if wave >= 2 else []

	for i in maxi(tanks, 1):
		var e := EnemyTank.new(terrain, projectiles, fx, player)
		e.hp = Tune.v("enemy_tank_hp")
		e.accuracy = maxf(0.10 - wave * 0.012, 0.03) / (Game.diff(0.75, 1.0, 1.4) * Tune.v("enemy_accuracy_scale"))
		e.cadence = maxf(6.5 - wave * 0.4, 3.5) * Tune.v("enemy_cadence_scale") / Game.diff(0.8, 1.0, 1.3)
		add_child(e)
		e.global_position = _ring_pos(150.0, 200.0)
	for i in jeeps:
		var j := EnemyLight.Jeep.new(terrain, projectiles, fx, player)
		add_child(j)
		j.global_position = _ring_pos(120.0, 170.0)
	for s in squads:
		var center := _ring_pos(80.0, 130.0)
		for k in 3:
			var g := EnemyLight.Gunner.new(terrain, projectiles, player)
			add_child(g)
			var off := Vector3(Game.rng.randf_range(-6, 6), 0, Game.rng.randf_range(-6, 6))
			g.global_position = center + off
			g.global_position.y = terrain.height(g.global_position.x, g.global_position.z) + 0.05
	for mp in mortars:
		var m := EnemyLight.Mortar.new(terrain, projectiles, fx, player)
		add_child(m)
		m.global_position = Vector3(mp.x, terrain.height(mp.x, mp.y) + 0.1, mp.y)
	for i in planes:
		var p := EnemyPlane.new(terrain, projectiles, fx, player)
		add_child(p)
		var a := Game.rng.randf() * TAU
		p.global_position = Vector3(cos(a) * 300.0, 70.0, sin(a) * 300.0)
	_between = 8.0

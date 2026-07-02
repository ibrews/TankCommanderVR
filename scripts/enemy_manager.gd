# Wave spawner: escalating tank + plane waves, wave-clear bonuses, restart handling.
class_name EnemyManager
extends Node3D

var terrain: Terrain
var projectiles: Projectiles
var fx: FxPool
var player: PlayerTank

var wave := 0
var _between := 4.0   # countdown to next wave
var _running := true

func _init(t: Terrain, p: Projectiles, f: FxPool, pl: PlayerTank) -> void:
	terrain = t
	projectiles = p
	fx = f
	player = pl
	name = "EnemyManager"

func _ready() -> void:
	Game.game_over.connect(func(): _running = false)
	Game.game_restarted.connect(_on_restart)

func _on_restart() -> void:
	for n in get_tree().get_nodes_in_group("enemies") + get_tree().get_nodes_in_group("planes"):
		n.queue_free()
	for c in get_children():
		c.queue_free()
	wave = 0
	_between = 5.0
	_running = true

func _process(delta: float) -> void:
	if not _running:
		return
	var alive := 0
	for c in get_children():
		if is_instance_valid(c) and not c.is_queued_for_deletion():
			if c is EnemyTank and c.state != EnemyTank.State.DEAD:
				alive += 1
			elif c is EnemyPlane and c.state != EnemyPlane.State.SPIRAL:
				alive += 1
	if alive == 0:
		_between -= delta
		if _between <= 0.0:
			_spawn_wave()
	elif wave > 0:
		_between = 8.0

func _spawn_wave() -> void:
	wave += 1
	Game.set_wave(wave)
	if wave > 1:
		Game.add_score(250)  # wave-clear bonus
		Sfx.play_at("wave", player.global_position + Vector3(0, 3, 0), 2.0)
	var tanks := mini(1 + wave, 6)
	var planes := 0
	if wave >= 2:
		planes = 1
	if wave >= 4:
		planes = 2
	for i in tanks:
		var e := EnemyTank.new(terrain, projectiles, fx, player)
		e.accuracy = maxf(0.10 - wave * 0.012, 0.03)
		e.cadence = maxf(6.5 - wave * 0.4, 3.5)
		add_child(e)
		var a := Game.rng.randf() * TAU
		var r := Game.rng.randf_range(150.0, 200.0)
		var pos := Vector3(cos(a) * r, 0, sin(a) * r)
		pos.y = terrain.height(pos.x, pos.z) + 0.1
		e.global_position = pos
	for i in planes:
		var p := EnemyPlane.new(terrain, projectiles, fx, player)
		add_child(p)
		var a := Game.rng.randf() * TAU
		p.global_position = Vector3(cos(a) * 300.0, 70.0, sin(a) * 300.0)
	_between = 8.0

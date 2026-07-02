# Autoload: audio streams + pooled 3D one-shot players + loop player factory.
extends Node

const NAMES := [
	"engine_loop", "tracks_loop", "turret_loop", "cannon", "reload", "click",
	"switch", "rocket", "explosion", "explosion_far", "mg", "hit", "ricochet",
	"alarm", "wind_loop", "plane_loop", "ignition", "gameover", "wave",
]
const POOL_SIZE := 14

var streams := {}
var _pool: Array[AudioStreamPlayer3D] = []
var _pool_i := 0

func _ready() -> void:
	for n in NAMES:
		var s: AudioStream = load("res://assets/audio/%s.wav" % n)
		if s == null:
			push_warning("missing audio: " + n)
			continue
		if n.ends_with("_loop") or n == "alarm":
			_make_looping(s)
		streams[n] = s
	for i in POOL_SIZE:
		var p := AudioStreamPlayer3D.new()
		p.max_distance = 260.0
		p.unit_size = 9.0
		add_child(p)
		_pool.append(p)

func _make_looping(s: AudioStream) -> void:
	if s is AudioStreamWAV:
		var w := s as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = w.data.size() / 2  # 16-bit mono frames

func play_at(name: String, pos: Vector3, vol_db := 0.0, pitch := 1.0, max_dist := 260.0) -> void:
	if not streams.has(name):
		return
	var p := _pool[_pool_i]
	_pool_i = (_pool_i + 1) % POOL_SIZE
	p.stream = streams[name]
	p.global_position = pos
	p.volume_db = vol_db
	p.pitch_scale = pitch * Game.rng.randf_range(0.96, 1.04)
	p.max_distance = max_dist
	p.play()

# A dedicated player attached to a parent (engine loops, alarms, etc).
func make_loop_player(name: String, parent: Node3D, vol_db := 0.0, unit := 6.0) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = streams.get(name)
	p.volume_db = vol_db
	p.unit_size = unit
	p.max_distance = 200.0
	parent.add_child(p)
	return p

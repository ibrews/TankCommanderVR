# Autoload: audio streams, pooled 3D one-shots, loop players, layered music
# (calm/combat crossfade, phase-locked), and the Alex-voice VO queue.
extends Node

const NAMES := [
	"engine_loop", "tracks_loop", "turret_loop", "cannon", "reload", "click",
	"switch", "rocket", "explosion", "explosion_far", "mg", "hit", "ricochet",
	"alarm", "wind_loop", "plane_loop", "ignition", "gameover", "wave",
	"music_menu", "music_calm", "music_combat", "sting_wave", "sting_over",
	"mortar_whistle", "mortar_launch", "jeep_loop", "rifle", "debris",
	"wall_crumble", "horn", "bomb_whistle", "shifter", "crash", "ui_select", "knob",
]
const VO_NAMES := [
	"vo_title", "vo_welcome", "vo_menu_pick", "vo_howto1", "vo_howto2",
	"vo_howto3", "vo_howto4", "vo_start", "vo_wave", "vo_wave2",
	"vo_wave_clear", "vo_kill", "vo_plane_down", "vo_hull_low", "vo_hit",
	"vo_armed", "vo_gameover", "vo_coop", "vo_versus", "vo_easy", "vo_hard",
	"vo_plane",
]
const POOL_SIZE := 14

var streams := {}
var _pool: Array[AudioStreamPlayer3D] = []
var _pool_i := 0

# music
var _m_menu: AudioStreamPlayer
var _m_calm: AudioStreamPlayer
var _m_combat: AudioStreamPlayer
var _threat := 0.0
var _threat_target := 0.0
var _music_mode := ""  # "menu" | "game" | "off"
var music_gain := 1.0  # radio volume knob

# VO
var _vo_player: AudioStreamPlayer
var _vo_cooldowns := {}
var _vo_prio := -1

func _ready() -> void:
	for n in NAMES:
		var s: AudioStream = load("res://assets/audio/%s.wav" % n)
		if s == null:
			push_warning("missing audio: " + n)
			continue
		if n.ends_with("_loop") or n == "alarm" or n.begins_with("music_"):
			_make_looping(s)
		streams[n] = s
	for n in VO_NAMES:
		var s: AudioStream = load("res://assets/audio/vo/%s.wav" % n)
		if s:
			streams[n] = s
	for i in POOL_SIZE:
		var p := AudioStreamPlayer3D.new()
		p.max_distance = 260.0
		p.unit_size = 9.0
		add_child(p)
		_pool.append(p)
	_m_menu = _mk_music("music_menu")
	_m_calm = _mk_music("music_calm")
	_m_combat = _mk_music("music_combat")
	_vo_player = AudioStreamPlayer.new()
	_vo_player.volume_db = 2.0
	add_child(_vo_player)

func _mk_music(name: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = streams.get(name)
	p.volume_db = -80.0
	add_child(p)
	return p

func _make_looping(s: AudioStream) -> void:
	if s is AudioStreamWAV:
		var w := s as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = w.data.size() / 2

# ---------------- one-shots
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

func play_ui(name: String, vol_db := 0.0) -> void:
	if not streams.has(name):
		return
	var p := AudioStreamPlayer.new()
	p.stream = streams[name]
	p.volume_db = vol_db
	add_child(p)
	p.play()
	p.finished.connect(p.queue_free)

func make_loop_player(name: String, parent: Node3D, vol_db := 0.0, unit := 6.0) -> AudioStreamPlayer3D:
	var p := AudioStreamPlayer3D.new()
	p.stream = streams.get(name)
	p.volume_db = vol_db
	p.unit_size = unit
	p.max_distance = 200.0
	parent.add_child(p)
	return p

# ---------------- music
func music_menu() -> void:
	_music_mode = "menu"
	_m_menu.play()

func music_game() -> void:
	_music_mode = "game"
	_threat = 0.0
	# start both layers together so they stay phase-locked for crossfades
	_m_calm.play()
	_m_combat.play()

func music_off() -> void:
	_music_mode = "off"

func set_threat(t: float) -> void:
	_threat_target = clampf(t, 0.0, 1.0)

func sting(name: String) -> void:
	play_ui(name, -4.0)

func _process(delta: float) -> void:
	_threat = move_toward(_threat, _threat_target, delta * 0.4)
	var gain_db := linear_to_db(clampf(music_gain, 0.03, 2.0))
	var menu_target := (-10.0 + gain_db) if _music_mode == "menu" else -80.0
	var calm_target := (-14.0 - _threat * 18.0 + gain_db) if _music_mode == "game" else -80.0
	var combat_target := (-34.0 + _threat * 24.0 + gain_db) if _music_mode == "game" else -80.0
	_m_menu.volume_db = move_toward(_m_menu.volume_db, menu_target, delta * 30.0)
	_m_calm.volume_db = move_toward(_m_calm.volume_db, calm_target, delta * 20.0)
	_m_combat.volume_db = move_toward(_m_combat.volume_db, combat_target, delta * 20.0)
	if _music_mode == "menu" and not _m_menu.playing:
		_m_menu.play()
	if _music_mode == "game" and not _m_calm.playing:
		_m_calm.play()
		_m_combat.play()
	if not _vo_player.playing:
		_vo_prio = -1

# ---------------- VO (the tank computer is Dad)
func vo(name: String, prio := 1, cooldown := 6.0) -> void:
	if not streams.has(name):
		return
	var now := Time.get_ticks_msec() / 1000.0
	if _vo_cooldowns.has(name) and now - _vo_cooldowns[name] < cooldown:
		return
	if _vo_player.playing and prio <= _vo_prio:
		return
	_vo_cooldowns[name] = now
	_vo_prio = prio
	_vo_player.stream = streams[name]
	_vo_player.play()

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
	"rain_loop", "thunder1", "thunder2", "wind_gust", "tornado_loop",
	"volcano_loop", "eruption", "bubbles_loop", "squeak", "pop", "splat",
	"static_loop", "whistle", "sneaker", "boing", "thud", "jingle",
	"music_beach", "music_toy", "lava_loop", "waves_loop",
	"music_city", "music_city_b", "music_town", "music_town_b",
	"music_mudpit", "music_mudpit_b", "music_castle", "music_castle_b",
	"music_gym", "music_gym_b", "music_island", "music_island_b",
	"music_volcano", "music_volcano_b",
	"gulp", "fizz", "can_crush", "sip", "steam",
]
const VO_NAMES := [
	"vo_title", "vo_welcome", "vo_menu_pick", "vo_howto1", "vo_howto2",
	"vo_howto3", "vo_howto4", "vo_start", "vo_wave", "vo_wave2",
	"vo_wave_clear", "vo_kill", "vo_plane_down", "vo_hull_low", "vo_hit",
	"vo_armed", "vo_gameover", "vo_coop", "vo_versus", "vo_easy", "vo_hard",
	"vo_plane",
	"radio_1", "radio_2", "radio_3", "radio_4", "radio_5", "radio_6",
	"radio_7", "radio_8", "radio_9", "radio_10", "radio_11", "radio_12",
	"vo_lowg", "vo_underwater", "vo_balloon", "vo_paintball",
	"vo_tornado", "vo_volcano", "vo_hurricane", "vo_gym", "vo_gym_wave",
]
const POOL_SIZE := 14

var streams := {}
var _pool: Array[AudioStreamPlayer3D] = []
var _pool_i := 0

# music
var _m_menu: AudioStreamPlayer
var _m_calm: AudioStreamPlayer
var _m_calm_b: AudioStreamPlayer     # variation crossfade partner
var _m_combat: AudioStreamPlayer
var _calm_variants: Array = []
var _calm_active := 0                # 0 = _m_calm, 1 = _m_calm_b
var _variation_t := 60.0
var _threat := 0.0
var _threat_target := 0.0
var _music_mode := ""  # "menu" | "game" | "off"
var music_gain := 1.0  # radio volume knob

# VO
var _vo_player: AudioStreamPlayer
var _vo_cooldowns := {}
var _vo_prio := -1
var _vo_pools := {}       # prefix -> [variant names]
var _vo_last := {}        # pool -> last variant played (no repeats)
var _idle_t := 30.0

# radio (the channel knob in the cockpit)
const STATIONS := ["AUTO", "DAD FM", "CALM FM", "BATTLE FM", "OFF"]
var radio_station := 0
var _radio_talk: AudioStreamPlayer3D = null
var _radio_next := 4.0
var _radio_queue: Array = []

func _ready() -> void:
	for n in NAMES:
		var s: AudioStream = load("res://assets/audio/%s.wav" % n)
		if s == null:
			push_warning("missing audio: " + n)
			continue
		if n.ends_with("_loop") or n == "alarm" or n.begins_with("music_"):
			_make_looping(s)
		streams[n] = s
	# VO: load everything in the manifest (variant pools), fall back to the
	# hardcoded list for pre-manifest builds.
	var vo_names: Array = VO_NAMES.duplicate()
	var mf := FileAccess.open("res://assets/audio/vo/manifest.txt", FileAccess.READ)
	if mf:
		vo_names = []
		while not mf.eof_reached():
			var line := mf.get_line().strip_edges()
			if line != "":
				vo_names.append(line)
	for n in vo_names:
		var s: AudioStream = load("res://assets/audio/vo/%s.wav" % n)
		if s:
			streams[n] = s
			# pool by prefix: "vo_kill_3" joins pool "vo_kill"
			var parts: PackedStringArray = String(n).rsplit("_", true, 1)
			if parts.size() == 2 and parts[1].is_valid_int():
				var pool: String = parts[0]
				if not _vo_pools.has(pool):
					_vo_pools[pool] = []
				_vo_pools[pool].append(n)
	# exact-named singles join their pool too (vo_kill.wav joins "vo_kill")
	for pool in _vo_pools.keys():
		if streams.has(pool) and not _vo_pools[pool].has(pool):
			_vo_pools[pool].append(pool)
	for i in POOL_SIZE:
		var p := AudioStreamPlayer3D.new()
		p.max_distance = 260.0
		p.unit_size = 9.0
		add_child(p)
		_pool.append(p)
	_m_menu = _mk_music("music_menu")
	_m_calm = _mk_music("music_calm")
	_m_calm_b = _mk_music("music_calm")
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
	# per-level calm track + its variation ("_b") — the game alternates
	# between them on a randomized timer so the loop never wears out
	var calm_name: String = Levels.current.get("calm_track", "music_calm")
	_calm_variants = [calm_name]
	if streams.has(calm_name + "_b"):
		_calm_variants.append(calm_name + "_b")
	_calm_active = 0
	_variation_t = Game.rng.randf_range(40.0, 70.0)
	_m_calm.stream = streams.get(calm_name, streams.get("music_calm"))
	_m_calm_b.stream = streams.get(_calm_variants[1] if _calm_variants.size() > 1 else calm_name)
	_m_calm.play()
	_m_combat.play()

func _variation_tick(delta: float) -> void:
	if _music_mode != "game" or _calm_variants.size() < 2:
		return
	_variation_t -= delta
	if _variation_t <= 0.0:
		_variation_t = Game.rng.randf_range(40.0, 75.0)
		_calm_active = 1 - _calm_active
		if _calm_active == 1 and not _m_calm_b.playing:
			_m_calm_b.play()

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
	var calm_target := -80.0
	var combat_target := -80.0
	if _music_mode == "game":
		match radio_station:
			0:  # AUTO — adaptive score
				# calm baseline lifted +6dB (was -14): at rest it was ~13dB
				# under the engine loop's effective level and read as "no
				# music" to players during ordinary driving, which is most
				# of actual playtime. Combat crossfade math is unchanged.
				calm_target = -8.0 - _threat * 18.0 + gain_db
				combat_target = -34.0 + _threat * 24.0 + gain_db
			1:  # DAD FM — talk over a quiet bed
				calm_target = -26.0 + gain_db
			2:  # CALM FM
				calm_target = -12.0 + gain_db
			3:  # BATTLE FM
				combat_target = -12.0 + gain_db
			4:  # OFF
				pass
	# split the calm target across the two variation players
	var calm_a := calm_target if _calm_active == 0 else -80.0
	var calm_b := calm_target if _calm_active == 1 else -80.0
	_m_calm_b.volume_db = move_toward(_m_calm_b.volume_db, calm_b, delta * 10.0)
	calm_target = calm_a
	_variation_tick(delta)
	_radio_tick(delta)
	_vo_idle_tick(delta)
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

# ---------------- radio
func radio_attach(node: Node3D) -> void:
	_radio_talk = AudioStreamPlayer3D.new()
	_radio_talk.unit_size = 2.2
	_radio_talk.max_distance = 30.0
	_radio_talk.volume_db = 2.0
	node.add_child(_radio_talk)
	_radio_next = 4.0

func set_radio_station(i: int) -> void:
	var s := clampi(i, 0, STATIONS.size() - 1)
	if s == radio_station:
		return
	radio_station = s
	if _radio_talk:
		_radio_talk.stop()
		_radio_talk.stream = streams.get("static_loop")
		_radio_talk.volume_db = -8.0
		_radio_talk.play()
		get_tree().create_timer(0.35).timeout.connect(func():
			if _radio_talk and _radio_talk.stream == streams.get("static_loop"):
				_radio_talk.stop()
				_radio_talk.volume_db = 2.0)
	if s == 1:
		_radio_next = 1.2
		if _radio_talk:
			get_tree().create_timer(0.4).timeout.connect(func():
				if radio_station == 1 and _radio_talk:
					_radio_talk.stream = streams.get("jingle")
					_radio_talk.play())

func _radio_tick(delta: float) -> void:
	if radio_station != 1 or _radio_talk == null or _music_mode != "game":
		return
	if _radio_talk.playing:
		return
	_radio_next -= delta
	if _radio_next > 0.0:
		return
	_radio_next = Game.rng.randf_range(7.0, 16.0)
	if _radio_queue.is_empty():
		for i in range(1, 13):
			_radio_queue.append("radio_%d" % i)
		for n in _vo_pools.get("radio_x", []):
			_radio_queue.append(n)
		_radio_queue.shuffle()
	var line: String = _radio_queue.pop_back()
	if streams.has(line):
		_radio_talk.stream = streams[line]
		_radio_talk.play()

# coaching VO: tutorial/guidance lines a veteran can silence from the menu
# (HELP: OFF). Flavor/combat callouts stay on vo() and always play.
func coach(name: String, prio := 1, cooldown := 6.0) -> void:
	if Game.help_on:
		vo(name, prio, cooldown)

# ---------------- VO (the tank computer is Dad)
# `name` can be a pool prefix ("vo_kill") — a random non-repeating variant
# plays. Cooldowns apply to the whole pool so dad doesn't get chatty.
func vo(name: String, prio := 1, cooldown := 6.0) -> void:
	cooldown *= Tune.v("vo_cooldown_scale")
	var pick := name
	if _vo_pools.has(name):
		var pool: Array = _vo_pools[name]
		if pool.size() > 1:
			var last: String = _vo_last.get(name, "")
			pick = pool[Game.rng.randi() % pool.size()]
			while pick == last and pool.size() > 1:
				pick = pool[Game.rng.randi() % pool.size()]
		else:
			pick = pool[0]
	if not streams.has(pick):
		return
	var now := Time.get_ticks_msec() / 1000.0
	if _vo_cooldowns.has(name) and now - _vo_cooldowns[name] < cooldown:
		return
	if _vo_player.playing and prio <= _vo_prio:
		return
	_vo_cooldowns[name] = now
	_vo_last[name] = pick
	_vo_prio = prio
	_vo_player.stream = streams[pick]
	_vo_player.play()

# idle chatter while things are calm
func _vo_idle_tick(delta: float) -> void:
	if Game.state != Game.GState.PLAYING or not Game.alive or _threat > 0.3:
		return
	_idle_t -= delta
	if _idle_t <= 0.0:
		_idle_t = Tune.v("vo_idle_period") * Game.rng.randf_range(0.7, 1.5)
		vo("vo_idle", 0, 10.0)

# Autoload: global game state, mode/level/difficulty selection, scoring,
# player HP, restart flow.
extends Node

signal hp_changed(hp: float)
signal score_changed(score: int)
signal wave_changed(wave: int)
signal game_over
signal game_restarted
signal kills_changed  # versus scoreboard

const MAX_HP := 100.0

enum Mode { SOLO, COOP, VERSUS, PLANE }
enum GState { MENU, PLAYING }
enum PlayerMode { SEATED, ON_FOOT }

var mode: int = Mode.SOLO
var level_id := "outdoor"
var difficulty := 1        # 0 easy, 1 medium, 2 hard
var mutator := ""          # "", "lowg", "underwater", "balloon", "paintball"
var vehicle := "tank"      # "tank", "plane", "biplane", "heli", "runner"
var time_of_day := 0       # 0 day, 1 golden hour, 2 night
var time_night: bool:
	get:
		return time_of_day == 2
	set(v):
		time_of_day = 2 if v else 0
var player_lights := false
var noise_t := 0.0         # seconds since the player made big noise (reveals you)
var state: int = GState.MENU
var endless := false       # cycle to a random new level every few waves
var travel_carry := {}     # score/hp/wave preserved across an endless travel
var help_on := true        # coaching VO + written hints (menu-toggleable)
var third_person := false  # false = in-cockpit first person (default), true = chase cam
var player_mode: int = PlayerMode.SEATED  # SEATED = in a vehicle cockpit, ON_FOOT = walking around
var paused := false  # mid-mission pause (menu button) — world/level stays alive, unlike GState.MENU

signal camera_mode_changed(third: bool)
signal pause_changed(is_paused: bool)

func toggle_camera_mode() -> void:
	third_person = not third_person
	camera_mode_changed.emit(third_person)

# Menu button while PLAYING pauses in place rather than tearing down the level
# (Alex: "going back to the menu shouldn't kick you out of your current
# level... pressing it again puts you back in your current game"). Only
# actually stops the clock in SOLO — pausing SceneTree time in COOP/VERSUS
# would desync the other peer, who has no way to know we've stopped, so
# multiplayer just shows the panel without freezing anything.
func toggle_pause() -> void:
	if state != GState.PLAYING:
		return
	paused = not paused
	get_tree().paused = paused and mode == Mode.SOLO
	pause_changed.emit(paused)

func set_paused(v: bool) -> void:
	if paused == v or state != GState.PLAYING:
		return
	paused = v
	get_tree().paused = paused and mode == Mode.SOLO
	pause_changed.emit(paused)

func make_noise() -> void:
	noise_t = Tune.v("noise_reveal_time")

# stealth: how far enemies can spot the player right now (fraction of day range)
func detect_scale() -> float:
	if noise_t > 0.0:
		return 1.2
	if not time_night:
		return 1.0
	return Tune.v("detect_night_lit") if player_lights else Tune.v("detect_night_dark")

const PAINT_COLORS := [
	Color(1.0, 0.2, 0.3), Color(0.2, 0.6, 1.0), Color(0.3, 1.0, 0.3),
	Color(1.0, 0.85, 0.1), Color(1.0, 0.4, 0.9), Color(0.5, 0.3, 1.0),
	Color(1.0, 0.55, 0.1),
]

func grav_scale() -> float:
	match mutator:
		"lowg": return 0.15
		"underwater": return 0.45
		_: return 1.0

func speed_scale() -> float:
	return 0.55 if mutator == "underwater" else 1.0

func fall_g() -> float:
	match mutator:
		"lowg": return 2.4
		"underwater": return 5.0
		_: return 26.0

func bounce() -> float:
	return 0.5 if mutator == "lowg" else 0.05

func paint_color() -> Color:
	return PAINT_COLORS[rng.randi() % PAINT_COLORS.size()]

# balloon mode: repaint every mesh under a node in bright party colors
func balloonize(node: Node) -> void:
	if node is MeshInstance3D:
		var m := StandardMaterial3D.new()
		m.albedo_color = Color.from_hsv(rng.randf(), 0.85, 1.0)
		m.roughness = 0.12
		m.metallic = 0.05
		m.metallic_specular = 0.9
		node.material_override = m
	for c in node.get_children():
		balloonize(c)

var hp := MAX_HP
var score := 0
var wave := 0
var alive := true
var time_since_damage := 999.0
var rng := RandomNumberGenerator.new()

# versus
var my_kills := 0
var their_kills := 0

func _ready() -> void:
	rng.seed = 20260702
	var cf := ConfigFile.new()
	if cf.load("user://prefs.cfg") == OK:
		help_on = cf.get_value("prefs", "help_on", true)

func save_prefs() -> void:
	var cf := ConfigFile.new()
	cf.set_value("prefs", "help_on", help_on)
	cf.save("user://prefs.cfg")

func diff(easy: float, med: float, hard: float) -> float:
	return [easy, med, hard][clampi(difficulty, 0, 2)]

func diff_name() -> String:
	return ["EASY", "MEDIUM", "HARD"][clampi(difficulty, 0, 2)]

func _process(delta: float) -> void:
	noise_t = maxf(0.0, noise_t - delta)
	if alive and state == GState.PLAYING:
		time_since_damage += delta
		if time_since_damage > 8.0 and hp < MAX_HP:
			hp = minf(hp + diff(4.0, 3.0, 2.0) * delta, MAX_HP)
			hp_changed.emit(hp)

func damage_player(amount: float) -> void:
	if not alive or state != GState.PLAYING:
		return
	hp -= amount * diff(0.6, 1.0, 1.35)
	time_since_damage = 0.0
	hp_changed.emit(hp)
	if hp <= 0.0:
		hp = 0.0
		alive = false
		game_over.emit()

func add_score(points: int) -> void:
	score += points
	score_changed.emit(score)

func set_wave(w: int) -> void:
	wave = w
	wave_changed.emit(w)

func restart() -> void:
	hp = MAX_HP
	score = 0
	wave = 0
	alive = true
	time_since_damage = 999.0
	player_mode = PlayerMode.SEATED
	if not travel_carry.is_empty():
		# endless travel: the fight continues on a new battlefield
		score = travel_carry.score
		wave = travel_carry.wave
		hp = maxf(travel_carry.hp, 45.0)   # arriving patches you up a bit
		travel_carry = {}
	hp_changed.emit(hp)
	score_changed.emit(score)
	game_restarted.emit()

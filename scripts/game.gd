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

var mode: int = Mode.SOLO
var level_id := "outdoor"
var difficulty := 1        # 0 easy, 1 medium, 2 hard
var mutator := ""          # "", "lowg", "underwater", "balloon", "paintball"
var vehicle := "tank"      # "tank", "plane", "biplane", "heli", "runner"
var time_night := false
var player_lights := false
var noise_t := 0.0         # seconds since the player made big noise (reveals you)
var state: int = GState.MENU

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
	hp_changed.emit(hp)
	score_changed.emit(score)
	game_restarted.emit()

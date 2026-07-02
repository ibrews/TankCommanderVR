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
var state: int = GState.MENU

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

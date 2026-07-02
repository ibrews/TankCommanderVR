# Autoload: global game state, scoring, player HP, restart flow.
extends Node

signal hp_changed(hp: float)
signal score_changed(score: int)
signal wave_changed(wave: int)
signal game_over
signal game_restarted

const MAX_HP := 100.0

var hp := MAX_HP
var score := 0
var wave := 0
var alive := true
var time_since_damage := 999.0
var rng := RandomNumberGenerator.new()

func _ready() -> void:
	rng.seed = 20260702

func _process(delta: float) -> void:
	if alive:
		time_since_damage += delta
		if time_since_damage > 8.0 and hp < MAX_HP:
			hp = minf(hp + 3.0 * delta, MAX_HP)
			hp_changed.emit(hp)

func damage_player(amount: float) -> void:
	if not alive:
		return
	hp -= amount
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

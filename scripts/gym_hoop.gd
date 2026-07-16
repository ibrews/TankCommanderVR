# Nothing But Net — the gym's basketballs and hoops existed for two weeks
# with no payoff (modeled, bouncy, and completely scoreless). Sink a ball
# down through a rim — bonk it with the tank, throw it on foot, ricochet a
# shell off it, whatever works — and the arena celebrates. One scorer node
# per gym build, handed the ball bodies + world-space rim centers by
# world_dressing.gd's _build_gym().
class_name HoopScorer
extends Node3D

const RIM_R := 1.6          # matches the rim ring cylinder in _build_gym
const SCORE := 150
const BALL_COOLDOWN := 3.0  # one swish per ball per trip through the net

var rims: Array = []        # world-space rim centers (Vector3)
var balls: Array = []       # RigidBody3D refs

var _prev_y := {}           # ball -> its y last frame (crossing detection)
var _cool := {}             # ball -> remaining cooldown

func _physics_process(delta: float) -> void:
	for b in balls:
		if not is_instance_valid(b):
			continue
		if _cool.get(b, 0.0) > 0.0:
			_cool[b] = _cool[b] - delta
		var p: Vector3 = b.global_position
		var prev: float = _prev_y.get(b, p.y)
		if _cool.get(b, 0.0) <= 0.0 and b.linear_velocity.y < -0.5:
			for rim in rims:
				# crossed the rim plane downward this frame, inside the ring
				if prev > rim.y and p.y <= rim.y \
						and Vector2(p.x - rim.x, p.z - rim.z).length() < RIM_R * 0.75:
					_cool[b] = BALL_COOLDOWN
					_score(rim)
					break
		_prev_y[b] = p.y

func _score(rim: Vector3) -> void:
	Game.add_score(SCORE)
	Sfx.play_at("whistle", rim, 2.0)
	Sfx.play_at("jingle", rim + Vector3(0, 1, 0), 0.0)
	var fx: FxPool = get_tree().get_first_node_in_group("fx")
	if fx:
		fx.balloon_pop(rim)
		fx.sparkle_burst(rim, 2.0)
	Sfx.vo("vo_kill", 2, 8.0)   # Dad calls the bucket like a kill. It counts.

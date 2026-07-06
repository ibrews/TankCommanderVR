# On-foot player body: replaces PlayerAlt.Runner's hand-rolled capsule with
# godot-xr-tools' XRToolsPlayerBody, so the addon's movement providers
# (sprint/climb/grapple, wired up in xr_rig.gd alongside this node) can drive
# it directly — they're hard-wired against XRToolsPlayerBody's own API, not
# an arbitrary CharacterBody3D. This node owns only TCV-specific glue
# (damage, weapon, energy-drink boost, respawn, arena safety); locomotion
# itself is entirely the addon's job.
class_name OnFootBody
extends XRToolsPlayerBody

var terrain: Terrain
var projectiles: Projectiles
var fx: FxPool
var rocket_cool := 0.0
var _rumble_cb: Callable = Callable()
var _rig: Node3D = null
var _step_t := 0.0

# godot-xr-tools' own movement providers read/write these two exported
# XRToolsMovementDirect nodes' max_speed directly — see enter_on_foot() in
# xr_rig.gd, which instantiates and parents them under hand_l/hand_r.
var _direct_l: Node = null
var _direct_r: Node = null
var _base_speed := 0.0
var _boost_end_t := 0.0
# Two independent multiplier sources (energy-drink pickup, stick sprint) —
# tracked separately and combined multiplicatively in _apply_speed_multiplier()
# rather than one clobbering max_speed outright, so drinking an energy drink
# mid-sprint (or sprinting while already boosted) stacks instead of one
# silently overwriting the other's speed.
var _drink_mult := 1.0
var _sprint_mult := 1.0

func _init(t: Terrain, p: Projectiles, f: FxPool) -> void:
	terrain = t
	projectiles = p
	fx = f
	name = "OnFootBody"
	collision_layer = 1 << 6   # layer 7 "Player Body" (0-indexed bit 6)
	collision_mask = (1 << 0) | (1 << 3)  # layer 1 "Static World" + layer 4 "Enemies"
	add_to_group("player")

func _ready() -> void:
	super._ready()
	player_radius = 0.35
	Game.game_restarted.connect(_respawn)
	# This body lives under the rig (see xr_rig.gd's enter_on_foot()), and
	# main.gd marks that rig PROCESS_MODE_ALWAYS so its pause-menu laser
	# pointer survives get_tree().paused — INHERIT would otherwise carry
	# that down here too, leaving the player still falling/walking under
	# gravity while the game is supposedly frozen.
	process_mode = Node.PROCESS_MODE_PAUSABLE

func _respawn() -> void:
	global_position = Vector3(terrain.spawn.x, terrain.height(terrain.spawn.x, terrain.spawn.y) + 0.1, terrain.spawn.y)
	velocity = Vector3.ZERO

# arena-radius safety clamp + energy-drink boost timeout, layered on top of
# the addon's own physics solve (called first via super).
func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	rocket_cool -= delta
	if _boost_end_t > 0.0:
		_boost_end_t -= delta
		if _boost_end_t <= 0.0:
			_drink_mult = 1.0
			_apply_speed_multiplier()
	var spd := Vector2(velocity.x, velocity.z).length()
	_step_t -= delta * spd
	if _step_t <= 0.0 and spd > 2.0:
		_step_t = 3.0
		Sfx.play_at("sneaker", global_position, -14.0, Game.rng.randf_range(0.9, 1.2))
		fx.dust(global_position, 0.4)
	var flat := Vector2(global_position.x, global_position.z)
	if flat.length() > terrain.arena_radius:
		flat = flat.normalized() * terrain.arena_radius
		global_position.x = flat.x
		global_position.z = flat.y

# Called once by xr_rig.gd after the two XRToolsMovementDirect nodes exist,
# so drink_energy() has something to multiply.
func register_direct_movement(direct_l: Node, direct_r: Node) -> void:
	_direct_l = direct_l
	_direct_r = direct_r
	_base_speed = direct_l.max_speed if direct_l else 3.0

func _apply_speed_multiplier() -> void:
	var mult := _drink_mult * _sprint_mult
	if _direct_l:
		_direct_l.max_speed = _base_speed * mult
	if _direct_r:
		_direct_r.max_speed = _base_speed * mult

# Energy-drink pickup: temporary sprint-speed boost, not a permanent toggle
# (see scripts/pickables/energy_drink.gd).
func drink_energy(duration: float, multiplier: float = 1.8) -> void:
	_boost_end_t = duration
	_drink_mult = multiplier
	_apply_speed_multiplier()

# Stick-based sprint (Alex: add a stick option alongside the existing
# arm-swing sprint) — hold the left stick forward past a threshold, fed each
# frame from xr_rig.gd's _feed_stick_sprint(). Menu-toggleable
# (Game.sprint_stick); layered the same multiplicative way as the energy
# drink rather than replacing it outright.
const SPRINT_STICK_MULT := 1.7
func set_stick_sprint(active: bool) -> void:
	var want := SPRINT_STICK_MULT if active else 1.0
	if not is_equal_approx(want, _sprint_mult):
		_sprint_mult = want
		_apply_speed_multiplier()

func fire_bazooka() -> void:
	if rocket_cool > 0.0 or not Game.alive:
		return
	rocket_cool = 1.6
	Game.make_noise()
	var cam: Node3D = _rig.get("camera") if _rig else self
	var dir := -cam.global_transform.basis.z
	projectiles.fire(Projectiles.Kind.ROCKET, cam.global_position + dir * 0.5 + Vector3(0, -0.2, 0),
		dir * 55.0, [get_rid()], true)
	Sfx.play_at("rocket", global_position, 2.0)
	_rumble(0.6, 0.1)

func take_damage(amount: float, at: Vector3) -> void:
	if not Game.alive:
		return
	Game.damage_player(amount * 1.5)   # squishy on foot, same as the old Runner
	Sfx.play_at("hit", at, -4.0)
	_rumble(0.8, 0.15)

func _rumble(a: float, d: float) -> void:
	if _rumble_cb.is_valid():
		_rumble_cb.call(a, d)

# arm-swing locomotion (xr_rig._feed_arm_swing) still feeds this on foot,
# layered on top of stick/addon movement as a speed boost rather than the
# only way to move — same idiom as the old Runner had, just additive now.
var _arm_speed := 0.0
func set_arm_swing(speed: float) -> void:
	_arm_speed = speed
	if _arm_speed > 1.2 and _direct_r:
		ground_control_velocity += Vector2(0, clampf(_arm_speed * 0.35, 0.0, 1.4))

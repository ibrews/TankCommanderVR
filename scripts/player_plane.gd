# Flyable warplane: canopy cockpit with a grabbed control stick + throttle
# lever, nose MG, belly bombs. Arcade flight model tuned for fun, not FAA.
# Exposes the same input API as PlayerTank so the rigs don't care.
class_name PlayerPlane
extends CharacterBody3D

var terrain: Terrain
var projectiles: Projectiles
var fx: FxPool
var cockpit: Dictionary = {}

var biplane := false
var speed := 35.0
var throttle := 0.6
var stick := Vector2.ZERO       # x=roll, y=pitch (from grip or right thumbstick)
var stick_throttle := 0.0       # left thumbstick fallback
var mg_held := false
var mg_timer := 0.0
var bomb_cool := 0.0
var bombs := 12
var _crashed := false
var _rumble_cb: Callable = Callable()

var engine_p: AudioStreamPlayer3D
var prop: MeshInstance3D
var speed_label: Label3D
var alt_label: Label3D
var bomb_label: Label3D

func _init(t: Terrain, p: Projectiles, f: FxPool) -> void:
	terrain = t
	projectiles = p
	fx = f
	name = "PlayerPlane"
	collision_layer = 2
	collision_mask = 0
	add_to_group("player")

func _ready() -> void:
	_build()
	engine_p = Sfx.make_loop_player("plane_loop", self, -4.0, 10.0)
	engine_p.play()
	Game.game_restarted.connect(_respawn)
	_respawn()

func _respawn() -> void:
	_crashed = false
	speed = 35.0
	throttle = 0.6
	bombs = 12
	# Push the spawn out from terrain.spawn along its own direction from
	# center, same as before, but capped to the level's actual arena_radius
	# (some levels are much smaller than the old fixed +60 assumed — gym
	# radius=105/spawn.y=80 put the plane at 140, well past the edge, into
	# undefined terrain, triggering the ground-contact crash check within
	# seconds of spawning; same story on island/volcano/babyroom). Found
	# live 2026-07-06.
	var base_2d := Vector2(terrain.spawn.x, terrain.spawn.y)
	var out_dir := base_2d.normalized() if base_2d.length() > 0.01 else Vector2(0, 1)
	var max_dist := maxf(terrain.arena_radius - 20.0, 30.0)
	var spawn_2d := out_dir * minf(base_2d.length() + 60.0, max_dist)
	var gp := Vector3(spawn_2d.x, 90.0, spawn_2d.y)
	global_position = gp
	# Face the arena center (world origin), not a hardcoded PI — the old
	# fixed Basis(UP, PI) put the nose (local -Z, same fuselage convention as
	# enemy_plane.gd — tapered nose + prop both at -Z) pointing away from
	# play, since every level's terrain.spawn sits on the +Z side of center:
	# Basis(UP, PI) * (0,0,-1) = (0,0,1), straight out toward the map edge
	# (verified via a headless Basis probe, not just derivation — Alex, live
	# headset: "planes are still spawning right by the edge of the map
	# facing outward"). enemy_plane.gd already fixed this for AI planes by
	# computing heading toward a real target via atan2 instead of a
	# constant; mirrored here with the arena center as that target so the
	# player's nose points into the play area from the moment the mission
	# starts, on every level regardless of where terrain.spawn sits.
	var to_center := atan2(-(0.0 - gp.x), -(0.0 - gp.z))
	basis = Basis(Vector3.UP, to_center)
	visible = true

func _build() -> void:
	var col := Color(0.35, 0.42, 0.3)
	var st := MeshKit.begin()
	# fuselage + wings + tail (player livery: green with orange nose)
	MeshKit.cyl(st, Transform3D(Basis(Vector3.RIGHT, PI / 2)), 0.5, 0.35, 7.4, 8, col)
	MeshKit.cyl(st, Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(0, 0, -4.0)), 0.45, 0.18, 0.9, 8, Color(0.9, 0.5, 0.15))
	MeshKit.box(st, Transform3D(Basis(), Vector3(0, -0.15, -0.3)), Vector3(9.6, 0.14, 1.8), col)
	if biplane:
		# second wing + struts = 100% more aviation. Top wing's underside
		# went through two rounds: Y=1.08 (6cm clearance, "in a biplane I
		# can't see anything") raised to Y=1.22 (20cm, still crowding the
		# upward view per the next report: "in the plane and biplane I
		# can't see over the top of the front... doesn't feel like a
		# cockpit"). Raised again for real head clearance; struts stretched to
		# match the new span between the two wings.
		MeshKit.box(st, Transform3D(Basis(), Vector3(0, 1.65, -0.3)), Vector3(9.6, 0.14, 1.8), col)
		for sx in [-3.4, 3.4]:
			for sz in [-0.9, 0.3]:
				MeshKit.box(st, Transform3D(Basis(), Vector3(sx, 0.75, sz)), Vector3(0.09, 1.8, 0.09), col * 0.8)
	MeshKit.box(st, Transform3D(Basis(), Vector3(0, 0.1, 3.4)), Vector3(3.4, 0.12, 1.0), col)
	MeshKit.box(st, Transform3D(Basis(), Vector3(0, 0.75, 3.5)), Vector3(0.09, 1.4, 1.0), Color(0.9, 0.5, 0.15))
	var mi := MeshInstance3D.new()
	mi.mesh = MeshKit.commit(st, MeshKit.mat_vcol(0.7, 0.15))
	add_child(mi)
	prop = MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(2.8, 0.16)
	prop.mesh = qm
	prop.position = Vector3(0, 0, -4.5)
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.2, 0.2, 0.2, 0.45)
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	prop.material_override = pm
	add_child(prop)

	# ---- cockpit (open canopy with frame; seat at fuselage top)
	var root := Node3D.new()
	root.name = "PlaneCockpit"
	root.position = Vector3(0, 0.45, -0.8)
	add_child(root)
	var cst := MeshKit.begin()
	# tub
	MeshKit.box(cst, Transform3D(Basis(), Vector3(0, -0.1, 0.1)), Vector3(0.85, 0.5, 1.6), Color(0.2, 0.23, 0.19))
	MeshKit.box(cst, Transform3D(Basis(), Vector3(0, -0.34, 0.1)), Vector3(0.8, 0.06, 1.5), Color(0.13, 0.13, 0.14))
	# windshield frame — Alex, live headset: "in the plane and biplane I can't
	# see over the top of the front... this doesn't feel like a cockpit."
	# Root cause: this used to be ONE solid opaque box covering the entire
	# 0.8x0.5 windshield opening (same class of bug the tank had before its
	# own vision-slit widening — see cockpit_builder.gd's slit_y0/slit_y1).
	# The separate transparent "glass" quad sat in front of it, but the
	# opaque slab behind it blocked the view regardless. Now built as a thin
	# border (screen pillars + top/bottom rail only) so the whole windshield
	# opening is actually open, with just the glass quad across it — a real
	# forward sightline instead of a wall with a window painted on it.
	var wf_y := 0.42
	var wf_z := -0.62
	var wf_w := 0.8
	var wf_h := 0.5
	var wf_t := 0.05  # border thickness
	var wf_basis := Basis(Vector3.RIGHT, deg_to_rad(-35))
	# top rail
	MeshKit.box(cst, Transform3D(wf_basis, Vector3(0, wf_y + wf_h / 2 - wf_t / 2, wf_z)), Vector3(wf_w, wf_t, 0.035), Color(0.25, 0.27, 0.24))
	# bottom rail (low sill so it doesn't eat into the view band)
	MeshKit.box(cst, Transform3D(wf_basis, Vector3(0, wf_y - wf_h / 2 + wf_t / 2, wf_z)), Vector3(wf_w, wf_t, 0.035), Color(0.25, 0.27, 0.24))
	# side pillars
	for sx in [-wf_w / 2 + wf_t / 2, wf_w / 2 - wf_t / 2]:
		MeshKit.box(cst, Transform3D(wf_basis, Vector3(sx, wf_y, wf_z)), Vector3(wf_t, wf_h, 0.035), Color(0.25, 0.27, 0.24))
	# center windscreen post (thin — a real biplane/warplane canopy has one,
	# but it must not be wide enough to read as "the view is still blocked")
	MeshKit.box(cst, Transform3D(wf_basis, Vector3(0, wf_y, wf_z)), Vector3(0.025, wf_h, 0.035), Color(0.25, 0.27, 0.24))
	# seat
	MeshKit.box(cst, Transform3D(Basis(), Vector3(0, -0.15, 0.62)), Vector3(0.46, 0.08, 0.42), Color(0.24, 0.2, 0.15))
	MeshKit.box(cst, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-10)), Vector3(0, 0.18, 0.82)), Vector3(0.46, 0.6, 0.07), Color(0.24, 0.2, 0.15))
	# instrument panel — shrunk/lowered so its top edge (was y=0.22+0.15=0.37,
	# close enough to the eye at y=0.57 to crowd the lower half of the view)
	# clears well below the new open windshield band (wf_y - wf_h/2 = 0.17).
	MeshKit.box(cst, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-15)), Vector3(0, 0.10, -0.42)), Vector3(0.7, 0.2, 0.05), Color(0.15, 0.16, 0.15))
	var cmesh := MeshInstance3D.new()
	var cmat := MeshKit.mat_tex("res://assets/tex/metal.png", true, 0.85)
	cmat = cmat.duplicate()
	cmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	cmat.uv1_scale = Vector3(3, 3, 1)
	cmesh.mesh = MeshKit.commit(cst, cmat)
	root.add_child(cmesh)
	# windshield glass (unchanged placement — now actually visible as glass,
	# not backed by an opaque slab)
	var glass := MeshInstance3D.new()
	var gq := QuadMesh.new()
	gq.size = Vector2(0.74, 0.44)
	glass.mesh = gq
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.6, 0.8, 0.85, 0.12)
	gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gm.metallic_specular = 0.0
	gm.roughness = 0.9
	gm.cull_mode = BaseMaterial3D.CULL_DISABLED
	glass.material_override = gm
	glass.position = Vector3(0, 0.44, -0.60)
	glass.rotation.x = deg_to_rad(-35)
	root.add_child(glass)

	# control stick (center) + throttle (left) + bomb button — Alex, live
	# headset: "I only see a single yellow lever on the right... doesn't feel
	# like a cockpit." Root cause: the stick grip and throttle lever were both
	# dark near-black (0.1,0.1,0.1) — same tone as the tub/shadow around them
	# — with no captions, so only the bright yellow hatch lever actually read
	# as a distinct control. Recolored stick/throttle to stand out and
	# labeled every control the same way cockpit_builder.gd labels the tank.
	# Control heights: the cockpit tub is a SOLID box whose top face sits at
	# y=0.15 in this root's space (box center -0.1, height 0.5). The first
	# pass placed the stick pivot at y=-0.30 and throttle at y=-0.18 — their
	# entire meshes (stick knob tops out ~y=0.01, throttle knob ~0.04) were
	# buried INSIDE the tub, invisible; only the hatch lever at exactly
	# y=0.15 poked out (Alex, live headset 2026-07-06: "on the plane I see
	# no controls... maybe they're inside geometry"). Pivots now sit just
	# under the tub top so shafts emerge from the surface like real
	# console-mounted controls.
	var grip := VRControl.TwoAxisGrip.create()
	grip.position = Vector3(0, 0.10, -0.05)
	root.add_child(grip)
	grip.deflection_changed.connect(func(v): stick = v)
	_label(root, "STICK", Vector3(0, 0.52, -0.05), -20, 13)
	var thr := VRControl.Lever.create(0.22, Color(0.75, 0.42, 0.12), 40.0, false)
	thr.position = Vector3(-0.34, 0.10, -0.1)
	root.add_child(thr)
	thr.value_changed.connect(func(v): throttle = clampf((v + 1.0) / 2.0, 0.0, 1.0))
	thr.value = 0.2
	_label(root, "THROTTLE", Vector3(-0.34, 0.42, -0.24), -20, 13)
	var bomb := VRControl.PushButton.create(Color(0.85, 0.12, 0.1), 0.032)
	bomb.position = Vector3(-0.34, 0.17, -0.28)
	root.add_child(bomb)
	bomb.pressed.connect(drop_bomb)
	_label(root, "BOMB", Vector3(-0.34, 0.28, -0.34), -20, 13)
	_label(root, "MG TRIGGER", Vector3(0, 0.46, 0.10), -20, 13)
	# canopy-rail hatch lever — Alex, live headset: plane should get a cockpit
	# ejection then a parachute on hatch-pull (see _on_hatch_lever /
	# main.exit_vehicle_airborne); biplane just falls out, no ejection, and
	# the player deploys their own chute (trigger or a chest-pull gesture).
	var hatch := VRControl.Lever.create(0.18, Color(0.85, 0.72, 0.15), 42.0, false)
	hatch.position = Vector3(0.42, 0.15, 0.05)
	hatch.rotation.z = deg_to_rad(-90)
	root.add_child(hatch)
	hatch.value_changed.connect(_on_hatch_lever)
	_label(root, "EJECT" if not biplane else "BAIL OUT", Vector3(0.42, 0.30, 0.05), 0, 13)
	# instruments
	speed_label = _mk_label(root, Vector3(-0.18, 0.26, -0.415))
	alt_label = _mk_label(root, Vector3(0.05, 0.26, -0.415))
	bomb_label = _mk_label(root, Vector3(0.25, 0.26, -0.415))
	var hint := Label3D.new()
	hint.text = "THROTTLE LEFT OR RIGHT TRIGGER · STICK CENTER · GRIP STICK+TRIGGER = MG · GRIP BTN OR RED = BOMB"
	hint.font_size = 52
	hint.pixel_size = 0.0003
	hint.modulate = Color(1.0, 0.8, 0.35)
	hint.position = Vector3(0, 0.55, -0.7)
	hint.visible = Game.help_on
	root.add_child(hint)
	CockpitBuilder.set_interior_layer(root)

	var seat_anchor := Node3D.new()
	seat_anchor.position = Vector3(0, -0.15, 0.55)
	root.add_child(seat_anchor)
	cockpit = {"seat_anchor": seat_anchor, "eye_local": Vector3(0, 0.72, -0.1), "controls": {}}

func _label(root: Node3D, text: String, pos: Vector3, pitch_deg := 0.0, size := 20) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size * 4
	l.pixel_size = 0.0002
	l.modulate = Color(0.92, 0.94, 0.90)
	l.outline_size = 0
	l.position = pos
	l.rotation_degrees = Vector3(pitch_deg, 0, 0)
	root.add_child(l)
	return l

func _mk_label(root: Node3D, pos: Vector3) -> Label3D:
	var l := Label3D.new()
	l.text = "0"
	l.font_size = 60
	l.pixel_size = 0.00035
	l.modulate = Color(0.4, 0.95, 0.5)
	l.position = pos
	l.rotation.x = deg_to_rad(-15)
	root.add_child(l)
	return l

func _physics_process(delta: float) -> void:
	if _crashed:
		return
	prop.rotation.z += (20.0 + throttle * 45.0) * delta
	# thumbstick fallback: computed fresh every frame (mirrors player_tank.gd's
	# effective_turret_input() merge) instead of destructively overwriting
	# `stick` -- the old `stick = stick_fallback` assignment was a one-shot
	# latch: the very first frame the thumbstick exceeded the 0.08 deadzone,
	# `stick` got set to a non-zero value, which permanently failed the
	# `stick.length() < 0.05` re-entry check on every later frame (even after
	# releasing the stick back to neutral) -- so the plane locked onto
	# whatever roll/pitch was in effect on that first frame and never
	# responded to the thumbstick again for the rest of the flight ("planes
	# don't steer properly with the Quest controllers", Alex 2026-07-06).
	# Grip stick still wins outright whenever it's actually in use.
	var eff_stick := stick
	if stick.length() < 0.05 and stick_fallback.length() > 0.08:
		eff_stick = stick_fallback
	throttle = clampf(throttle + stick_throttle * delta * 0.5, 0.0, 1.0)
	# flight model (biplane: slower, nimbler)
	var vmax := Tune.v("plane_speed_max") * (0.72 if biplane else 1.0)
	var target_speed := 16.0 + throttle * (vmax - 16.0)
	speed = move_toward(speed, target_speed, 8.0 * delta)
	var pitch_rate := -eff_stick.y * 1.1
	var roll_rate := -eff_stick.x * 1.9
	basis = (basis
		* Basis(Vector3.RIGHT, pitch_rate * delta)
		* Basis(Vector3.BACK, roll_rate * delta)).orthonormalized()
	# bank-to-turn + gentle auto-level
	var bank := basis.x.y
	basis = Basis(Vector3.UP, -bank * 0.9 * delta) * basis
	if absf(eff_stick.x) < 0.1:
		var bank_angle := asin(clampf(basis.x.y, -1.0, 1.0))
		basis = (basis * Basis(Vector3.BACK, -bank_angle * 1.2 * delta)).orthonormalized()
	# stall sink
	var vel := -basis.z * speed
	if speed < 20.0:
		vel.y -= (20.0 - speed) * 0.9
	velocity = vel
	global_position += velocity * delta
	# arena + altitude clamps
	var flat := Vector2(global_position.x, global_position.z)
	if flat.length() > 300.0:
		var back := -flat.normalized()
		var want := atan2(back.x, back.y)
		basis = basis.slerp(Basis(Vector3.UP, PI - want), clampf(delta, 0, 1)).orthonormalized()
	global_position.y = minf(global_position.y, 160.0)
	# ground contact
	var gh := terrain.height(global_position.x, global_position.z)
	if global_position.y < gh + 2.2:
		if velocity.y < -6.0 or speed > 30.0:
			_crash()
		else:
			global_position.y = gh + 2.2
	# weapons
	mg_timer -= delta
	bomb_cool -= delta
	if mg_held and mg_timer <= 0.0 and Game.alive:
		mg_timer = 0.1
		_fire_mg()
	# audio + instruments
	engine_p.pitch_scale = 0.85 + throttle * 0.5
	speed_label.text = "SPD %d" % int(speed * 3.6)
	alt_label.text = "ALT %d" % int(global_position.y - gh)
	bomb_label.text = "BMB %d" % bombs

func _fire_mg() -> void:
	var dir := -global_transform.basis.z
	dir = dir.rotated(global_transform.basis.y, Game.rng.randf_range(-0.01, 0.01))
	projectiles.fire(Projectiles.Kind.MG, to_global(Vector3(0, -0.2, -4.6)), dir * 230.0 + velocity, [get_rid()], true)
	Sfx.play_at("mg", global_position, -6.0)
	_rumble(0.15, 0.03)

func drop_bomb() -> void:
	if bombs <= 0 or bomb_cool > 0.0 or not Game.alive:
		Sfx.play_at("click", global_position, -6.0)
		return
	bombs -= 1
	bomb_cool = 0.8
	projectiles.fire(Projectiles.Kind.BOMB, to_global(Vector3(0, -0.9, 0)), velocity * 0.95, [get_rid()], true)
	_rumble(0.4, 0.08)

func _crash() -> void:
	_crashed = true
	fx.explosion(global_position, true, global_position)
	Sfx.play_at("crash", global_position, 4.0)
	Game.damage_player(45.0)
	visible = false
	_rumble(1.0, 0.4)
	if Game.alive:
		get_tree().create_timer(3.0).timeout.connect(_respawn)

func take_damage(amount: float, at: Vector3) -> void:
	if not Game.alive or _crashed:
		return
	Game.damage_player(amount)
	Sfx.play_at("hit", at, 0.0)
	_rumble(0.7, 0.15)

func _rumble(amp: float, dur: float) -> void:
	if _rumble_cb.is_valid():
		_rumble_cb.call(amp, dur)

# ---- rig-facing input API (mirrors PlayerTank)
var stick_fallback := Vector2.ZERO

func set_stick_drive(v: Vector2) -> void:
	stick_throttle = v.y

func set_stick_turret(v: Vector2) -> void:
	stick_fallback = v

## Generic accessor read by net.gd's versus-mode state sync (same shape as
## player_tank.gd's) -- the plane has no separately-aimable part (nose MG
## fires straight, bombs drop straight down), so there's nothing to report.
func get_aim_yaw_pitch() -> Vector2:
	return Vector2.ZERO

func fire_primary() -> void:
	mg_held = true
	get_tree().create_timer(0.5).timeout.connect(func(): mg_held = false)

func stick_fire() -> void:
	drop_bomb()

func stick_rockets() -> void:
	drop_bomb()

func set_mg(held: bool) -> void:
	mg_held = held

func quick_start() -> void:
	pass  # engine is always running

func _on_hatch_lever(v: float) -> void:
	# Alex, live headset: "if I exit from a plane I should get a cockpit
	# ejection then a parachute. Biplane I should just be falling out and
	# then using parachute." Routes through main.exit_vehicle_airborne()
	# instead of the instant-teleport-to-ground exit_vehicle() every other
	# vehicle's hatch uses — plane gets the ejection pop, biplane free-falls
	# from the seat, both land in a PlayerParachute that the pilot deploys
	# themselves (trigger press or a chest-pull gesture while falling).
	if absf(v) > 0.8 and Game.player_mode == Game.PlayerMode.SEATED:
		var m := get_tree().get_first_node_in_group("main")
		if m:
			m.call_deferred("exit_vehicle_airborne", self, not biplane)

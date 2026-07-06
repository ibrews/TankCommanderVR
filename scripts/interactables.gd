# Lightweight VR cockpit controls — no external addon.
# The rig calls: try_grab(hand) / on_hand_update(hand_global_pos) / release().
# Poke-style controls (buttons, toggles) react to poke_check(tip_global_pos).
# Same code path works for controllers and (future) hand-interaction pinch,
# mirroring CrazyCar's "abstract drag, not joints" approach.
class_name VRControl
extends Node3D

signal value_changed(v: float)
signal pressed
signal toggled_on(on: bool)

var grab_radius := 0.11
var grabbed_by: Node = null   # the hand/controller node that holds us
var enabled := true
var handle: MeshInstance3D = null
var _handle_mat: StandardMaterial3D = null

func _ready() -> void:
	# THE missing line, found 2026-07-03: xr_rig.gd's grab loop
	# (_nearest_control()) and poke loop both discover controls exclusively
	# via get_tree().get_nodes_in_group("vrcontrols") — and nothing in the
	# repo's entire history ever joined that group, so physically grabbing/
	# poking any cockpit control (including the hatch lever that gates the
	# whole on-foot mode mid-mission) never worked on a real rig. Every
	# in-game/QA path that DID work reached controls directly through the
	# cockpit["controls"] dict instead. See
	# kb: godot-xr-controls-group-never-populated.
	add_to_group("vrcontrols")

func grab_point() -> Vector3:
	return handle.global_position if handle else global_position

func can_grab() -> bool:
	return enabled

func on_grab(hand: Node) -> void:
	grabbed_by = hand

func release() -> void:
	grabbed_by = null

func on_hand_update(_hand_pos: Vector3) -> void:
	pass

func poke_check(_tip: Vector3, _delta: float) -> void:
	pass

func set_highlight(on: bool) -> void:
	if _handle_mat:
		_handle_mat.emission_enabled = on
		if on:
			_handle_mat.emission = Color(0.9, 0.6, 0.2)
			_handle_mat.emission_energy_multiplier = 0.35

func _make_handle_mat(col: Color) -> StandardMaterial3D:
	_handle_mat = StandardMaterial3D.new()
	_handle_mat.albedo_color = col
	_handle_mat.roughness = 0.55
	_handle_mat.metallic = 0.25
	return _handle_mat

func _haptic(amp := 0.4, dur := 0.02) -> void:
	if grabbed_by and grabbed_by.has_method("pulse"):
		grabbed_by.pulse(amp, dur)


# ============================================================ Lever
# Rotates around local X axis: value -1 (pulled back, +angle) .. +1 (pushed fwd).
# Used for: driving tillers (soft auto-center), breech handle, restart handle.
class Lever:
	extends VRControl

	var max_angle := deg_to_rad(32.0)
	var auto_center := false
	var center_rate := 2.2
	var detent_center := true
	var pivot: Node3D
	var value := 0.0:
		set(v):
			var nv := clampf(v, -1.0, 1.0)
			if absf(nv - value) > 0.0005:
				value = nv
				pivot.rotation.x = value * max_angle
				value_changed.emit(value)
			else:
				value = nv

	var _was_center := true

	static func create(length: float, knob_col: Color, lever_max_deg: float, autocenter: bool) -> Lever:
		var lv := Lever.new()
		lv.max_angle = deg_to_rad(lever_max_deg)
		lv.auto_center = autocenter
		lv.pivot = Node3D.new()
		lv.add_child(lv.pivot)
		# shaft
		var st := MeshKit.begin()
		MeshKit.cyl(st, Transform3D(Basis(), Vector3(0, length * 0.5, 0)), 0.016, 0.014, length, 6, Color(0.35, 0.36, 0.35))
		var shaft := MeshInstance3D.new()
		shaft.mesh = MeshKit.commit(st, MeshKit.mat_vcol(0.5, 0.4))
		lv.pivot.add_child(shaft)
		# knob
		var knob := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.035
		sm.height = 0.07
		sm.radial_segments = 10
		sm.rings = 6
		knob.mesh = sm
		knob.material_override = lv._make_handle_mat(knob_col)
		knob.position = Vector3(0, length, 0)
		lv.pivot.add_child(knob)
		lv.handle = knob
		return lv

	func on_hand_update(hand_pos: Vector3) -> void:
		var local := to_local(hand_pos)
		# angle of hand around X axis in the Y/Z plane; lever up = 0
		var ang := atan2(-local.z, local.y)
		ang = clampf(ang, -max_angle, max_angle)
		var new_value := ang / max_angle
		var at_center := absf(new_value) < 0.08
		if detent_center and at_center and not _was_center:
			_haptic(0.3, 0.015)
			Sfx.play_at("click", global_position, -14.0)
		_was_center = at_center
		value = new_value

	func _process(delta: float) -> void:
		if auto_center and grabbed_by == null and absf(value) > 0.001:
			value = move_toward(value, 0.0, center_rate * delta)


# ============================================================ TwoAxisGrip
# Turret control joystick: returns Vector2 deflection (x = traverse, y = elevate),
# springs to zero when released. Rig reads .grabbed_by to route trigger = fire.
class TwoAxisGrip:
	extends VRControl

	signal deflection_changed(v: Vector2)
	var deflection := Vector2.ZERO
	var pivot: Node3D
	var _rest := Vector3.ZERO

	static func create() -> TwoAxisGrip:
		var g := TwoAxisGrip.new()
		g.grab_radius = 0.13
		g.pivot = Node3D.new()
		g.add_child(g.pivot)
		var st := MeshKit.begin()
		MeshKit.cyl(st, Transform3D(Basis(), Vector3(0, 0.09, 0)), 0.02, 0.018, 0.18, 6, Color(0.3, 0.3, 0.3))
		# pistol-style grip head
		MeshKit.box(st, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-15)), Vector3(0, 0.21, 0.01)), Vector3(0.045, 0.13, 0.055), Color(0.16, 0.16, 0.17))
		MeshKit.box(st, Transform3D(Basis(), Vector3(0, 0.28, -0.02)), Vector3(0.1, 0.03, 0.05), Color(0.16, 0.16, 0.17))
		var mesh := MeshInstance3D.new()
		mesh.mesh = MeshKit.commit(st, MeshKit.mat_vcol(0.6, 0.1))
		g.pivot.add_child(mesh)
		var knob := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.05, 0.06, 0.06)
		knob.mesh = bm
		knob.material_override = g._make_handle_mat(Color(0.75, 0.2, 0.15))
		knob.position = Vector3(0, 0.31, -0.02)
		g.pivot.add_child(knob)
		g.handle = knob
		return g

	func grab_point() -> Vector3:
		return to_global(Vector3(0, 0.24, 0))

	func on_grab(hand: Node) -> void:
		super.on_grab(hand)
		_rest = to_local(hand.global_position)
		_haptic(0.5, 0.03)

	func on_hand_update(hand_pos: Vector3) -> void:
		var local := to_local(hand_pos)
		var off := local - _rest
		var d := Vector2(clampf(off.x / 0.10, -1.0, 1.0), clampf(-off.z / 0.10, -1.0, 1.0))
		if d.distance_to(deflection) > 0.01:
			deflection = d
			pivot.rotation = Vector3(deflection.y * 0.28, 0, -deflection.x * 0.28)
			deflection_changed.emit(deflection)

	func release() -> void:
		super.release()
		deflection = Vector2.ZERO
		pivot.rotation = Vector3.ZERO
		deflection_changed.emit(deflection)


# ============================================================ SteeringWheel
# A real wheel prop (rim + spokes + hub, faces the driver along local -Z) —
# grab the rim and turn it like a car wheel, unlike TwoAxisGrip's pistol-grip
# stick (which the jeep used to reuse for steering — no wheel to visually
# grab/turn, per Alex). Tracks the grabbing hand's angle around the wheel's
# own forward axis rather than a linear offset, so twisting your wrist all
# the way around actually spins the rim. `value` -1..1 (left..right lock),
# springs back toward center like a real unweighted wheel when released.
class SteeringWheel:
	extends VRControl

	const RIM_RADIUS := 0.16
	const MAX_TURN := deg_to_rad(120.0)   # lock-to-lock authority either way

	var wheel_mesh: Node3D
	var value := 0.0
	var auto_center := true
	var center_rate := 1.6
	var _grab_ang := 0.0
	var _grab_value := 0.0

	static func create(rim_col := Color(0.16, 0.16, 0.17)) -> SteeringWheel:
		var w := SteeringWheel.new()
		w.grab_radius = RIM_RADIUS + 0.05
		w.wheel_mesh = Node3D.new()
		w.add_child(w.wheel_mesh)
		var st := MeshKit.begin()
		# rim: ring of short angled cylinder segments (same technique as the
		# parachute's suspension lines) — no torus primitive in MeshKit
		var segs := 16
		var tube_r := 0.014
		for i in segs:
			var a0 := TAU * i / segs
			var a1 := TAU * (i + 1) / segs
			var p0 := Vector3(cos(a0), sin(a0), 0) * RIM_RADIUS
			var p1 := Vector3(cos(a1), sin(a1), 0) * RIM_RADIUS
			var mid := (p0 + p1) * 0.5
			var seg_len: float = p0.distance_to(p1)
			var tf := Transform3D(Basis(Vector3.FORWARD, (a0 + a1) * 0.5 + PI / 2.0), mid)
			MeshKit.cyl(st, tf, tube_r, tube_r, seg_len * 1.05, 6, rim_col)
		# 3 spokes, hub
		for i in 3:
			var a := TAU * i / 3.0 + PI / 2.0
			var mid_s := Vector3(cos(a), sin(a), 0) * RIM_RADIUS * 0.52
			var tf_s := Transform3D(Basis(Vector3.FORWARD, a + PI / 2.0), mid_s)
			MeshKit.cyl(st, tf_s, 0.012, 0.012, RIM_RADIUS * 0.9, 6, rim_col * 0.9)
		MeshKit.cyl(st, Transform3D(Basis(Vector3.RIGHT, PI / 2.0)), 0.05, 0.045, 0.05, 10, rim_col * 0.85)
		var mesh := MeshInstance3D.new()
		mesh.mesh = MeshKit.commit(st, w._make_handle_mat(rim_col))
		mesh.material_override = w._handle_mat
		w.wheel_mesh.add_child(mesh)
		w.handle = mesh
		return w

	# Grabbable anywhere on the rim, not just dead-center top — same "rim, not
	# hub" feel as a real wheel. Rig picks the nearest control by grab_point()
	# distance; the rim-top point is close enough for that check everywhere a
	# hand would plausibly reach for it.
	func grab_point() -> Vector3:
		return to_global(Vector3(0, RIM_RADIUS, 0))

	func on_grab(hand: Node) -> void:
		super.on_grab(hand)
		var local := to_local(hand.global_position)
		_grab_ang = atan2(local.y, local.x)
		_grab_value = value
		_haptic(0.4, 0.02)

	func on_hand_update(hand_pos: Vector3) -> void:
		var local := to_local(hand_pos)
		var ang := atan2(local.y, local.x)
		# Negated: atan2 winds counter-clockwise in the wheel's own local
		# frame, but the wheel FACES the driver (its local +Z looks back at
		# them) — so a physically clockwise turn (right hand pulls down, as
		# in a real car turning right) is a DECREASING raw angle. Flipping
		# here makes `value` positive for a driver-clockwise/right turn,
		# matching every other steer signal in this game (positive = right).
		var d := -wrapf(ang - _grab_ang, -PI, PI)
		var nv := clampf(_grab_value + d / MAX_TURN, -1.0, 1.0)
		if absf(nv - value) > 0.001:
			value = nv
			wheel_mesh.rotation.z = -value * MAX_TURN
			value_changed.emit(value)

	func release() -> void:
		super.release()
		_haptic(0.2, 0.02)

	func _process(delta: float) -> void:
		if auto_center and grabbed_by == null and absf(value) > 0.001:
			value = move_toward(value, 0.0, center_rate * delta)
			wheel_mesh.rotation.z = -value * MAX_TURN
			value_changed.emit(value)


# ============================================================ PushButton
# Poke or grab to press. Fires `pressed` once per press; hold detected via is_down.
class PushButton:
	extends VRControl

	var is_down := false
	var momentary := true
	var btn_mesh: MeshInstance3D
	var _rest_y := 0.0
	var _cool := 0.0

	static func create(col: Color, radius := 0.032) -> PushButton:
		var b := PushButton.new()
		b.grab_radius = 0.055
		var st := MeshKit.begin()
		MeshKit.cyl(st, Transform3D(Basis(), Vector3(0, 0.008, 0)), radius * 1.5, radius * 1.4, 0.016, 10, Color(0.2, 0.2, 0.2))
		var base := MeshInstance3D.new()
		base.mesh = MeshKit.commit(st, MeshKit.mat_vcol(0.6, 0.3))
		b.add_child(base)
		var st2 := MeshKit.begin()
		MeshKit.cyl(st2, Transform3D(Basis(), Vector3(0, 0.0, 0)), radius, radius * 0.92, 0.022, 10, Color.WHITE)
		var btn := MeshInstance3D.new()
		btn.mesh = MeshKit.commit(st2, b._make_handle_mat(col))
		btn.material_override = b._handle_mat
		btn.position = Vector3(0, 0.026, 0)
		b.add_child(btn)
		b.btn_mesh = btn
		b._rest_y = 0.026
		b.handle = btn
		return b

	func can_grab() -> bool:
		return false  # poke only, but rig may still route trigger-press

	func poke_check(tip: Vector3, delta: float) -> void:
		_cool = maxf(0.0, _cool - delta)
		var local := to_local(tip)
		var in_zone: bool = Vector2(local.x, local.z).length() < grab_radius and local.y > -0.02 and local.y < 0.09
		var press: bool = in_zone and local.y < 0.045
		if press and not is_down and _cool <= 0.0:
			is_down = true
			_cool = 0.15
			btn_mesh.position.y = _rest_y - 0.012
			Sfx.play_at("click", global_position, -8.0)
			pressed.emit()
		elif not press and is_down:
			is_down = false
			btn_mesh.position.y = _rest_y

	func force_press() -> void:
		if _cool <= 0.0:
			_cool = 0.15
			pressed.emit()


# ============================================================ ToggleSwitch
# Small two-position switch. Poke to flip.
class ToggleSwitch:
	extends VRControl

	var on := false
	var bat: MeshInstance3D
	var _cool := 0.0

	static func create(col := Color(0.85, 0.85, 0.8)) -> ToggleSwitch:
		var t := ToggleSwitch.new()
		t.grab_radius = 0.05
		var st := MeshKit.begin()
		MeshKit.box(st, Transform3D(), Vector3(0.035, 0.012, 0.055), Color(0.22, 0.22, 0.22))
		var base := MeshInstance3D.new()
		base.mesh = MeshKit.commit(st, MeshKit.mat_vcol(0.6, 0.3))
		t.add_child(base)
		var st2 := MeshKit.begin()
		MeshKit.cyl(st2, Transform3D(Basis(), Vector3(0, 0.019, 0)), 0.007, 0.009, 0.038, 6, Color.WHITE)
		t.bat = MeshInstance3D.new()
		t.bat.mesh = MeshKit.commit(st2, t._make_handle_mat(col))
		t.bat.material_override = t._handle_mat
		t.add_child(t.bat)
		t.bat.rotation.x = deg_to_rad(24)
		t.handle = t.bat
		return t

	func can_grab() -> bool:
		return false

	func poke_check(tip: Vector3, delta: float) -> void:
		_cool = maxf(0.0, _cool - delta)
		if _cool > 0.0:
			return
		if to_local(tip).length() < grab_radius:
			flip()

	func flip() -> void:
		_cool = 0.4
		on = not on
		bat.rotation.x = deg_to_rad(-24 if on else 24)
		Sfx.play_at("switch", global_position, -6.0)
		toggled_on.emit(on)


# ============================================================ Knob
# Rotary knob (radio volume, channel...). Grab and drag sideways to turn —
# same "abstract the drag" trick as the levers. value 0..1 with detent ticks.
class Knob:
	extends VRControl

	var value := 0.5
	var detents := 12
	var knob_mesh: MeshInstance3D
	var _grab_x := 0.0
	var _grab_value := 0.5
	var _last_detent := -1

	static func create(col := Color(0.15, 0.15, 0.16), radius := 0.028) -> Knob:
		var k := Knob.new()
		k.grab_radius = 0.06
		var st := MeshKit.begin()
		MeshKit.cyl(st, Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(0, 0, 0.012)), radius, radius * 0.9, 0.028, 10, Color.WHITE)
		MeshKit.box(st, Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(0, 0.0, 0.027)), Vector3(0.006, 0.02, radius * 1.5), Color(0.9, 0.9, 0.85))
		k.knob_mesh = MeshInstance3D.new()
		k.knob_mesh.mesh = MeshKit.commit(st, k._make_handle_mat(col))
		k.knob_mesh.material_override = k._handle_mat
		k.add_child(k.knob_mesh)
		k.handle = k.knob_mesh
		k._apply()
		return k

	func on_grab(hand: Node) -> void:
		super.on_grab(hand)
		_grab_x = to_local(hand.global_position).x
		_grab_value = value

	func on_hand_update(hand_pos: Vector3) -> void:
		var dx := to_local(hand_pos).x - _grab_x
		var nv := clampf(_grab_value + dx * 2.4, 0.0, 1.0)
		if absf(nv - value) > 0.002:
			value = nv
			_apply()
			var det := int(value * detents)
			if det != _last_detent:
				_last_detent = det
				_haptic(0.25, 0.01)
				Sfx.play_at("knob", global_position, -10.0)
			value_changed.emit(value)

	func _apply() -> void:
		knob_mesh.rotation.z = lerpf(deg_to_rad(135), deg_to_rad(-135), value)


# ============================================================ SafetyCover
# Red flip cover guarding a switch/button. Poke to open/close.
class SafetyCover:
	extends VRControl

	var open := false
	var lid: Node3D
	var _cool := 0.0

	static func create() -> SafetyCover:
		var c := SafetyCover.new()
		c.grab_radius = 0.06
		c.lid = Node3D.new()
		c.lid.position = Vector3(0, 0.004, -0.045)  # hinge at back edge
		c.add_child(c.lid)
		var st := MeshKit.begin()
		MeshKit.box(st, Transform3D(Basis(), Vector3(0, 0.020, 0.045)), Vector3(0.075, 0.036, 0.09), Color.WHITE)
		var mesh := MeshInstance3D.new()
		mesh.mesh = MeshKit.commit(st, c._make_handle_mat(Color(0.8, 0.15, 0.1)))
		mesh.material_override = c._handle_mat
		c.lid.add_child(mesh)
		c.handle = mesh
		return c

	func can_grab() -> bool:
		return false

	func poke_check(tip: Vector3, delta: float) -> void:
		_cool = maxf(0.0, _cool - delta)
		if _cool > 0.0:
			return
		if to_local(tip).length() < (0.09 if open else grab_radius):
			_cool = 0.5
			open = not open
			var tw := create_tween()
			tw.tween_property(lid, "rotation:x", deg_to_rad(-115.0) if open else 0.0, 0.15)
			Sfx.play_at("switch", global_position, -4.0, 0.8)
			toggled_on.emit(open)

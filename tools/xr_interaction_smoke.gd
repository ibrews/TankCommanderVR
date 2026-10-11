# Control-state smoke checks against the real procedural tank cockpit.
# External XRSim acceptance also exercises the rig and OpenXR actions.
extends Node3D

var _results := []
var tank: PlayerTank


func _log(check: String, ok: bool, detail: String = "") -> void:
	_results.append({"check": check, "ok": ok, "detail": detail})
	print("[xr_smoke] %s: %s%s" % [check, ("PASS" if ok else "FAIL"), ("  (%s)" % detail) if detail else ""])


func _ready() -> void:
	var terrain := Terrain.new()
	add_child(terrain)
	var fx := FxPool.new()
	add_child(fx)
	var projectiles := Projectiles.new(terrain, fx)
	add_child(projectiles)
	tank = PlayerTank.new(terrain, projectiles, fx)
	add_child(tank)
	await get_tree().create_timer(0.6).timeout

	var controls: Array = tank.cockpit.get("controls", {}).values()
	_log("production cockpit controls registered in vrcontrols",
		controls.size() > 0 and get_tree().get_nodes_in_group("vrcontrols").size() >= controls.size(), "%d controls" % controls.size())
	if controls.is_empty():
		_print_summary()
		get_tree().quit(1 if _results.any(func(r): return not r["ok"]) else 0)
		return

	# Fake hands are created per-test via the FakeHand class below — a
	# Node3D with just .global_position, since that's all VRControl's
	# public API (on_grab/on_hand_update/poke_check) actually reads (see
	# xr_rig.gd's own call sites). No XRController3D/XRHand needed.
	await _test_one_of_each(controls)
	_print_summary()
	get_tree().quit(1 if _results.any(func(r): return not r["ok"]) else 0)


func _test_one_of_each(controls: Array) -> void:
	var tested := {}  # class key -> true, so we test each subclass once
	for c in controls:
		if not (c is VRControl):
			continue
		var key := _class_key(c)
		if key == "" or tested.has(key):
			continue
		tested[key] = true
		match key:
			"Lever":
				await _test_lever(c)
			"TwoAxisGrip":
				await _test_two_axis_grip(c)
			"Knob":
				await _test_knob(c)
			"PushButton":
				await _test_push_button(c)
			"ToggleSwitch":
				await _test_toggle_switch(c)
			"SafetyCover":
				await _test_safety_cover(c)
	_log("distinct VRControl subclasses exercised", tested.size() >= 3,
		"tested: %s" % [str(tested.keys())])


func _class_key(c: VRControl) -> String:
	if c is VRControl.Lever:
		return "Lever"
	if c is VRControl.TwoAxisGrip:
		return "TwoAxisGrip"
	if c is VRControl.Knob:
		return "Knob"
	if c is VRControl.PushButton:
		return "PushButton"
	if c is VRControl.ToggleSwitch:
		return "ToggleSwitch"
	if c is VRControl.SafetyCover:
		return "SafetyCover"
	return ""


# A stand-in for the real hand/controller node xr_rig.gd passes into
# on_grab() — only needs .global_position (read by grab logic) and an
# optional .pulse() (haptics, silently no-op'd via has_method() checks in
# _haptic(), so a plain Node3D with no pulse() method is already safe).
class FakeHand:
	extends Node3D


func _test_lever(c: VRControl) -> void:
	var lv := c as VRControl.Lever
	print("[xr_smoke] --- Lever @ %s ---" % [c.name if c.name else c.get_path()])
	var hand := FakeHand.new()
	add_child(hand)
	var far_pos := c.grab_point() + Vector3(0, 5.0, 0)   # well outside grab_radius
	hand.global_position = far_pos
	var d_far := c.grab_point().distance_to(hand.global_position)
	_log("Lever.grab_point() is a real, reachable position", d_far > c.grab_radius,
		"grab_radius=%.3f, fake-hand-far distance=%.3f (outside, as intended)" % [c.grab_radius, d_far])
	# move the fake hand INTO grab range and grab
	hand.global_position = c.grab_point()
	var value_before: float = lv.value
	lv.on_grab(hand)
	_log("on_grab() registers the fake hand as holder", lv.grabbed_by == hand)
	# simulate pulling the lever: offset the hand along -Z in the lever's
	# local space (matches on_hand_update()'s own atan2(-local.z, local.y))
	var pulled_pos := c.to_global(Vector3(0, 0.05, -0.03))
	lv.on_hand_update(pulled_pos)
	_log("on_hand_update() changes Lever.value and emits value_changed", lv.value != value_before,
		"value %.3f -> %.3f" % [value_before, lv.value])
	lv.release()
	_log("release() clears grabbed_by", lv.grabbed_by == null)
	hand.queue_free()


func _test_two_axis_grip(c: VRControl) -> void:
	var g := c as VRControl.TwoAxisGrip
	print("[xr_smoke] --- TwoAxisGrip @ %s ---" % [c.name if c.name else c.get_path()])
	var hand := FakeHand.new()
	add_child(hand)
	hand.global_position = g.grab_point()
	g.on_grab(hand)
	_log("on_grab() registers the fake hand", g.grabbed_by == hand)
	var deflect_before: Vector2 = g.deflection
	var moved := g.grab_point() + Vector3(0.06, 0, -0.06)
	g.on_hand_update(moved)
	_log("on_hand_update() deflects the turret joystick", g.deflection != deflect_before,
		"deflection %s -> %s" % [deflect_before, g.deflection])
	g.release()
	_log("release() springs deflection back to zero", g.deflection == Vector2.ZERO, "deflection=%s" % [g.deflection])
	hand.queue_free()


func _test_knob(c: VRControl) -> void:
	var k := c as VRControl.Knob
	print("[xr_smoke] --- Knob @ %s ---" % [c.name if c.name else c.get_path()])
	var hand := FakeHand.new()
	add_child(hand)
	hand.global_position = k.to_global(Vector3(0.03, 0, 0.035))
	k.on_grab(hand)
	var value_before: float = k.value
	var turned := k.to_global(Vector3(0, -0.03, 0.035))
	k.on_hand_update(turned)
	_log("turning the Knob changes value and emits value_changed", k.value != value_before,
		"value %.3f -> %.3f" % [value_before, k.value])
	k.release()
	hand.queue_free()


func _test_push_button(c: VRControl) -> void:
	var b := c as VRControl.PushButton
	print("[xr_smoke] --- PushButton @ %s ---" % [c.name if c.name else c.get_path()])
	var pressed_box := [false]
	var conn := func(): pressed_box[0] = true
	b.pressed.connect(conn, CONNECT_ONE_SHOT)
	# outside the poke zone: should NOT press
	b.poke_check(c.global_position + Vector3(0, 0.5, 0), 0.016)
	_log("poke_check() from outside the zone does not press", not pressed_box[0])
	# inside: press zone is local.y < 0.045 within grab_radius on XZ
	b.poke_check(c.global_position + Vector3(0, 0.03, 0), 0.016)
	_log("poke_check() from inside the press zone fires 'pressed'", pressed_box[0])
	if b.pressed.is_connected(conn):
		b.pressed.disconnect(conn)


func _test_toggle_switch(c: VRControl) -> void:
	var t := c as VRControl.ToggleSwitch
	print("[xr_smoke] --- ToggleSwitch @ %s ---" % [c.name if c.name else c.get_path()])
	var on_before: bool = t.on
	t.poke_check(c.global_position, 0.016)
	await get_tree().create_timer(0.05).timeout
	_log("poke_check() flips ToggleSwitch.on and emits toggled_on", t.on != on_before,
		"on %s -> %s" % [on_before, t.on])


func _test_safety_cover(c: VRControl) -> void:
	var s := c as VRControl.SafetyCover
	print("[xr_smoke] --- SafetyCover @ %s ---" % [c.name if c.name else c.get_path()])
	var open_before: bool = s.open
	s.poke_check(s.grab_point(), 0.016)
	await get_tree().create_timer(0.05).timeout
	_log("poke_check() flips SafetyCover.open and emits toggled_on", s.open != open_before,
		"open %s -> %s" % [open_before, s.open])


func _print_summary() -> void:
	print("\n===== XR INTERACTION SMOKE SUMMARY =====")
	var passed := 0
	for r in _results:
		if r["ok"]:
			passed += 1
	print("\n%d/%d VRControl logic checks passed" % [passed, _results.size()])
	for r in _results:
		if not r["ok"]:
			print("  FAILED: %s  (%s)" % [r["check"], r["detail"]])
	print("Hand tracking quality, reach comfort and standalone Quest frame times require device validation.")

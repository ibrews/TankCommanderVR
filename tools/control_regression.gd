extends Node3D

var failures := 0
var checks := 0

class TestHand:
	extends XRRig.XRHand
	var tracked := true
	var squeeze := 0.0
	func _init() -> void:
		super("right_hand")
	func _ready() -> void:
		super()
		set_physics_process(false)
	func uses_controller() -> bool:
		return true
	func interaction_tracked() -> bool:
		return tracked
	func hand_pos() -> Vector3:
		return global_position
	func effective_grip() -> float:
		return squeeze
	func effective_trigger() -> float:
		return 0.0

func check(label: String, ok: bool) -> void:
	checks += 1
	if not ok:
		failures += 1
	print("[control_regression] %s: %s" % [label, "PASS" if ok else "FAIL"])

func _ready() -> void:
	var toggle := VRControl.ToggleSwitch.create()
	add_child(toggle)
	toggle.poke_check(toggle.global_position, 0.01)
	for i in 120:
		toggle.poke_check(toggle.global_position, 1.0 / 72.0)
	check("held contact flips switch only once", toggle.on)
	toggle.poke_check(Vector3(0, 5, 0), 0.1)
	toggle.poke_check(toggle.global_position, 0.1)
	check("withdraw and touch flips again", not toggle.on)
	var button := VRControl.PushButton.create(Color.GREEN)
	add_child(button)
	button.poke_check(button.to_global(Vector3(0, 0.02, 0)), 0.2)
	check("starter stays down during contact", button.is_down)
	button.reset_touch()
	check("leaving coarse range clears starter", not button.is_down)
	var cover := VRControl.SafetyCover.create()
	add_child(cover)
	cover.poke_check(cover.grab_point(), 0.01)
	await get_tree().create_timer(0.2).timeout
	for i in 100:
		cover.poke_check(cover.global_position, 1.0 / 72.0)
	check("open cover does not retrigger over guarded switch", cover.open)
	var wheel := VRControl.SteeringWheel.create()
	add_child(wheel)
	for angle in [0.0, PI / 2, PI, PI * 1.5]:
		var point := wheel.to_global(Vector3(cos(angle), sin(angle), 0) * wheel.RIM_RADIUS)
		check("wheel rim reachable at %.0f degrees" % rad_to_deg(angle), wheel.grab_distance(point) < 0.001)
	check("wheel hub not mistaken for rim", wheel.grab_distance(wheel.global_position) > wheel.grab_radius)
	var rig := XRRig.new()
	var tank := Node3D.new()
	add_child(tank)
	rig.tank = tank
	var lever := VRControl.Lever.create(0.3, Color.WHITE, 30, true)
	tank.add_child(lever)
	var hand := TestHand.new()
	hand.rig = rig
	add_child(hand)
	Game.state = Game.GState.PLAYING
	Game.player_mode = Game.PlayerMode.SEATED
	hand.global_position = lever.grab_point()
	hand.squeeze = 0.7
	hand._physics_process(1.0 / 72.0)
	check("real dispatch grabs nearest vehicle control", hand.holding == lever)
	hand.squeeze = 0.45
	hand._physics_process(1.0 / 72.0)
	check("grip noise retains held lever", hand.holding == lever)
	hand.tracked = false
	hand._physics_process(1.0 / 72.0)
	check("tracking loss releases control", hand.holding == null and lever.grabbed_by == null)
	hand.tracked = true
	hand.squeeze = 0.7
	hand._physics_process(1.0 / 72.0)
	Game.paused = true
	hand._physics_process(1.0 / 72.0)
	check("pause releases control", hand.holding == null and lever.grabbed_by == null)
	Game.paused = false
	var other := Node3D.new()
	add_child(other)
	lever.on_grab(other)
	check("second hand cannot steal control", hand._nearest_control() == null)
	lever.release()
	rig.free()
	print("[control_regression] SUMMARY %d/%d passed" % [checks - failures, checks])
	get_tree().quit(1 if failures else 0)

# XR rig: origin + camera + two hands. Drives the VRControl interaction system
# (grip = grab levers/grips, poke tip = buttons/switches) plus thumbstick
# fallbacks. Auto seat-height calibration so seated/standing both land at the
# design eye point.
class_name XRRig
extends XROrigin3D

var tank: PlayerTank
var camera: XRCamera3D
var hand_l: XRHand
var hand_r: XRHand
var _calibrated := false
var _calib_t := 0.0

class XRHand:
	extends XRController3D

	var rig: XRRig
	var holding: VRControl = null
	var _last_near: VRControl = null
	var _grip_was := false
	var poke_tip: Node3D

	func _init(tracker_name: String) -> void:
		tracker = tracker_name
		pose = "aim_pose" if false else "grip_pose"

	func _ready() -> void:
		poke_tip = Node3D.new()
		poke_tip.position = Vector3(0, -0.01, -0.06)
		add_child(poke_tip)
		# simple glove visual
		var st := MeshKit.begin()
		MeshKit.box(st, Transform3D(Basis(), Vector3(0, -0.01, 0.02)), Vector3(0.07, 0.05, 0.11), Color(0.35, 0.32, 0.25))
		MeshKit.box(st, Transform3D(Basis(), Vector3(0, -0.015, -0.045)), Vector3(0.062, 0.038, 0.05), Color(0.42, 0.38, 0.30))
		var mi := MeshInstance3D.new()
		mi.mesh = MeshKit.commit(st, MeshKit.mat_vcol(0.9))
		add_child(mi)

	func pulse(amp: float, dur: float) -> void:
		trigger_haptic_pulse("haptic", 0.0, amp, dur, 0.0)

	func hand_pos() -> Vector3:
		return global_position

	func _physics_process(delta: float) -> void:
		if rig == null or rig.tank == null:
			return
		var gripping := get_float("grip") > 0.55
		# --- grab lifecycle
		if holding == null:
			var near := _nearest_control()
			if near != _last_near:
				if _last_near:
					_last_near.set_highlight(false)
				if near:
					near.set_highlight(true)
				_last_near = near
			if gripping and not _grip_was and near:
				holding = near
				holding.set_highlight(false)
				holding.on_grab(self)
				pulse(0.45, 0.02)
		else:
			if gripping:
				holding.on_hand_update(hand_pos())
			else:
				holding.release()
				holding = null
		_grip_was = gripping
		# --- poke buttons/switches
		var tip := poke_tip.global_position
		for c in get_tree().get_nodes_in_group("vrcontrols"):
			var vc := c as VRControl
			if vc and not vc.can_grab() and vc.enabled and vc.global_position.distance_to(tip) < 0.25:
				vc.poke_check(tip, delta)
		# --- trigger while holding the turret grip fires
		if holding is VRControl.TwoAxisGrip:
			if get_float("trigger") > 0.6 and not get_meta("trig_was", false):
				rig.tank.fire_cannon(false)
			set_meta("trig_was", get_float("trigger") > 0.6)
			rig.tank.set_mg(is_button_pressed("ax_button"))

	func _nearest_control() -> VRControl:
		var best: VRControl = null
		var best_d := 1e9
		var hp := hand_pos()
		for c in get_tree().get_nodes_in_group("vrcontrols"):
			var vc := c as VRControl
			if vc == null or not vc.can_grab() or not vc.enabled:
				continue
			var d := vc.grab_point().distance_to(hp)
			if d < vc.grab_radius and d < best_d:
				best_d = d
				best = vc
		return best

func _init(t: PlayerTank) -> void:
	tank = t
	name = "XRRig"

func _ready() -> void:
	camera = XRCamera3D.new()
	add_child(camera)
	hand_l = XRHand.new("left_hand")
	hand_l.rig = self
	add_child(hand_l)
	hand_r = XRHand.new("right_hand")
	hand_r.rig = self
	add_child(hand_r)
	tank.cockpit["seat_anchor"].add_child(self)
	tank._rumble_cb = func(amp, dur):
		hand_l.pulse(amp, dur)
		hand_r.pulse(amp, dur)
	# ambient wind (non-positional)
	var wind := AudioStreamPlayer.new()
	wind.stream = Sfx.streams.get("wind_loop")
	wind.volume_db = -22.0
	wind.autoplay = true
	add_child(wind)
	# recalibrate on runtime recenter (defensive: signal presence varies by fork)
	var xr := XRServer.find_interface("OpenXR")
	if xr and xr.has_signal("pose_recentered"):
		xr.pose_recentered.connect(func(): _calibrated = false; _calib_t = 0.3)

func _physics_process(delta: float) -> void:
	if not _calibrated:
		_calib_t += delta
		if _calib_t > 1.2 and camera.transform.origin.length() > 0.01:
			_calibrate()
	# thumbstick fallbacks
	var ls := hand_l.get_vector2("primary")
	var rs := hand_r.get_vector2("primary")
	tank.set_stick_drive(Vector2(_dz(ls.x), _dz(ls.y)))
	tank.set_stick_turret(Vector2(_dz(rs.x), _dz(rs.y)))
	# right trigger fires when not holding the physical grip
	if not (hand_r.holding is VRControl.TwoAxisGrip):
		var trig := hand_r.get_float("trigger") > 0.6
		if trig and not get_meta("rtrig_was", false):
			tank.stick_fire()
		set_meta("rtrig_was", trig)
		if not (hand_l.holding is VRControl.TwoAxisGrip):
			tank.set_mg(hand_r.is_button_pressed("ax_button") and hand_r.holding == null)
	# B = rockets, Y = recalibrate, X = quick start, L-stick click = quick start
	if hand_r.is_button_pressed("by_button") and not get_meta("b_was", false):
		tank.stick_rockets()
	set_meta("b_was", hand_r.is_button_pressed("by_button"))
	if hand_l.is_button_pressed("by_button") and not get_meta("y_was", false):
		_calibrated = false
		_calib_t = 1.0
	set_meta("y_was", hand_l.is_button_pressed("by_button"))
	if hand_l.is_button_pressed("ax_button") and not get_meta("x_was", false):
		tank.quick_start()
	set_meta("x_was", hand_l.is_button_pressed("ax_button"))
	if hand_l.is_button_pressed("primary_click") and not get_meta("lsc_was", false):
		tank.quick_start()
	set_meta("lsc_was", hand_l.is_button_pressed("primary_click"))

func _dz(v: float) -> float:
	return v if absf(v) > 0.12 else 0.0

func _calibrate() -> void:
	# place the rig so the physical head lands on the design eye point,
	# facing the cockpit front.
	var eye_local: Vector3 = tank.cockpit["eye_local"]
	var cam_t := camera.transform
	var cam_fwd := -cam_t.basis.z
	var cam_yaw := atan2(-cam_fwd.x, -cam_fwd.z)
	rotation = Vector3(0, -cam_yaw, 0)
	position = Vector3.ZERO
	position = eye_local - (basis * cam_t.origin)
	_calibrated = true
	Sfx.play_at("click", global_position, -8.0)

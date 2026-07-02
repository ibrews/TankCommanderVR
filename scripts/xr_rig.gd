# XR rig v2: origin + camera + two hands. Menu laser pointers, vehicle
# seat attach/detach, VRControl grab/poke driving, thumbstick fallbacks,
# seat auto-calibration.
class_name XRRig
extends XROrigin3D

var tank: Node3D = null    # PlayerTank or PlayerPlane (same input API)
var camera: XRCamera3D
var hand_l: XRHand
var hand_r: XRHand
var _calibrated := true
var _calib_t := 0.0

class XRHand:
	extends XRController3D

	var rig: XRRig
	var holding: VRControl = null
	var _last_near: VRControl = null
	var _grip_was := false
	var poke_tip: Node3D
	var laser: MeshInstance3D

	func _init(tracker_name: String) -> void:
		tracker = tracker_name
		pose = "grip_pose"

	func _ready() -> void:
		poke_tip = Node3D.new()
		poke_tip.position = Vector3(0, -0.01, -0.06)
		add_child(poke_tip)
		var st := MeshKit.begin()
		MeshKit.box(st, Transform3D(Basis(), Vector3(0, -0.01, 0.02)), Vector3(0.07, 0.05, 0.11), Color(0.35, 0.32, 0.25))
		MeshKit.box(st, Transform3D(Basis(), Vector3(0, -0.015, -0.045)), Vector3(0.062, 0.038, 0.05), Color(0.42, 0.38, 0.30))
		var mi := MeshInstance3D.new()
		mi.mesh = MeshKit.commit(st, MeshKit.mat_vcol(0.9))
		mi.layers = 2
		add_child(mi)
		# menu laser
		laser = MeshInstance3D.new()
		var lb := BoxMesh.new()
		lb.size = Vector3(0.004, 0.004, 1.0)
		laser.mesh = lb
		var lm := StandardMaterial3D.new()
		lm.albedo_color = Color(1.0, 0.6, 0.2, 0.7)
		lm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		laser.material_override = lm
		laser.visible = false
		add_child(laser)

	func pulse(amp: float, dur: float) -> void:
		trigger_haptic_pulse("haptic", 0.0, amp, dur, 0.0)

	func hand_pos() -> Vector3:
		return global_position

	func _physics_process(delta: float) -> void:
		if rig == null:
			return
		if Game.state == Game.GState.MENU:
			_menu_pointer()
			return
		laser.visible = false
		if rig.tank == null:
			return
		var gripping := get_float("grip") > 0.55
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
		var tip := poke_tip.global_position
		for c in get_tree().get_nodes_in_group("vrcontrols"):
			var vc := c as VRControl
			if vc and not vc.can_grab() and vc.enabled and vc.global_position.distance_to(tip) < 0.25:
				vc.poke_check(tip, delta)
		if holding is VRControl.TwoAxisGrip:
			if get_float("trigger") > 0.6 and not get_meta("trig_was", false):
				rig.tank.call("fire_primary")
			set_meta("trig_was", get_float("trigger") > 0.6)
			rig.tank.call("set_mg", is_button_pressed("ax_button"))

	func _menu_pointer() -> void:
		var m: MainMenu = get_tree().get_first_node_in_group("menu")
		if m == null:
			laser.visible = false
			return
		var from := global_position
		var dir := -global_transform.basis.z
		var trig := get_float("trigger") > 0.6
		var clicked: bool = trig and not get_meta("mtrig_was", false)
		set_meta("mtrig_was", trig)
		var res := m.pointer(from, dir, clicked)
		if res.is_empty():
			laser.visible = false
		else:
			laser.visible = true
			var d: float = res.dist
			laser.position = Vector3(0, 0, -d / 2)
			laser.scale = Vector3(1, 1, d)
			if clicked:
				pulse(0.4, 0.02)

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

func _init() -> void:
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
	var wind := AudioStreamPlayer.new()
	wind.stream = Sfx.streams.get("wind_loop")
	wind.volume_db = -22.0
	wind.autoplay = true
	add_child(wind)
	var xr := XRServer.find_interface("OpenXR")
	if xr and xr.has_signal("pose_recentered"):
		xr.pose_recentered.connect(func(): _calibrated = false; _calib_t = 0.3)

func to_menu_anchor(parent: Node3D) -> void:
	tank = null
	if get_parent() != parent:
		get_parent().remove_child(self)
		parent.add_child(self)
	transform = Transform3D()
	_calibrated = true  # natural floor height at the menu

func attach_to_vehicle(v: Node3D) -> void:
	tank = v
	var anchor: Node3D = v.cockpit["seat_anchor"]
	if get_parent() != anchor:
		get_parent().remove_child(self)
		anchor.add_child(self)
	transform = Transform3D()
	_calibrated = false
	_calib_t = 0.0
	v.set("_rumble_cb", func(amp, dur):
		hand_l.pulse(amp, dur)
		hand_r.pulse(amp, dur))

func _physics_process(delta: float) -> void:
	if Game.state == Game.GState.MENU or tank == null:
		return
	if not _calibrated:
		_calib_t += delta
		if _calib_t > 1.2 and camera.transform.origin.length() > 0.01:
			_calibrate()
	var ls := hand_l.get_vector2("primary")
	var rs := hand_r.get_vector2("primary")
	tank.call("set_stick_drive", Vector2(_dz(ls.x), _dz(ls.y)))
	tank.call("set_stick_turret", Vector2(_dz(rs.x), _dz(rs.y)))
	if not (hand_r.holding is VRControl.TwoAxisGrip):
		var trig := hand_r.get_float("trigger") > 0.6
		if trig and not get_meta("rtrig_was", false):
			tank.call("stick_fire")
		set_meta("rtrig_was", trig)
		if not (hand_l.holding is VRControl.TwoAxisGrip):
			tank.call("set_mg", hand_r.is_button_pressed("ax_button") and hand_r.holding == null)
	if hand_r.is_button_pressed("by_button") and not get_meta("b_was", false):
		tank.call("stick_rockets")
	set_meta("b_was", hand_r.is_button_pressed("by_button"))
	if hand_l.is_button_pressed("by_button") and not get_meta("y_was", false):
		_calibrated = false
		_calib_t = 1.0
	set_meta("y_was", hand_l.is_button_pressed("by_button"))
	if hand_l.is_button_pressed("ax_button") and not get_meta("x_was", false):
		tank.call("quick_start")
	set_meta("x_was", hand_l.is_button_pressed("ax_button"))
	if hand_l.is_button_pressed("primary_click") and not get_meta("lsc_was", false):
		tank.call("quick_start")
	set_meta("lsc_was", hand_l.is_button_pressed("primary_click"))
	_check_easter_egg(delta)

# squeeze EVERYTHING (both grips + both triggers) + A for 1.5 s → chaos
var _egg_t := 0.0
var _egg_cool := 0.0
func _check_easter_egg(delta: float) -> void:
	_egg_cool = maxf(0.0, _egg_cool - delta)
	var all_in := hand_l.get_float("grip") > 0.8 and hand_r.get_float("grip") > 0.8 \
		and hand_l.get_float("trigger") > 0.8 and hand_r.get_float("trigger") > 0.8 \
		and hand_r.is_button_pressed("ax_button")
	if all_in and _egg_cool <= 0.0:
		_egg_t += delta
		if fmod(_egg_t, 0.25) < delta:
			hand_l.pulse(0.3, 0.05)
			hand_r.pulse(0.3, 0.05)
		if _egg_t > 1.5:
			_egg_t = 0.0
			_egg_cool = 180.0
			var w: Weather = get_tree().get_first_node_in_group("weather")
			if w:
				w.start_disaster(["tornado", "volcano", "hurricane"][Game.rng.randi() % 3])
				hand_l.pulse(1.0, 0.3)
				hand_r.pulse(1.0, 0.3)
	else:
		_egg_t = 0.0

func _dz(v: float) -> float:
	return v if absf(v) > 0.12 else 0.0

func _calibrate() -> void:
	var eye_local: Vector3 = tank.cockpit["eye_local"]
	var cam_t := camera.transform
	var cam_fwd := -cam_t.basis.z
	var cam_yaw := atan2(-cam_fwd.x, -cam_fwd.z)
	rotation = Vector3(0, -cam_yaw, 0)
	position = Vector3.ZERO
	position = eye_local - (basis * cam_t.origin)
	_calibrated = true
	Sfx.play_at("click", global_position, -8.0)

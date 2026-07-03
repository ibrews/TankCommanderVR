# XR rig v2: origin + camera + two hands. Menu laser pointers, vehicle
# seat attach/detach, VRControl grab/poke driving, thumbstick fallbacks,
# seat auto-calibration.
class_name XRRig
extends XROrigin3D

var tank: Node3D = null    # PlayerTank or PlayerPlane (same input API)
var camera: XRCamera3D
var hand_l: XRHand
var hand_r: XRHand
var hand_l_mesh: XRNode3D
var hand_r_mesh: XRNode3D
var _calibrated := true
var _calib_t := 0.0
var _fp_pos := Vector3.ZERO   # calibrated first-person eye position

class XRHand:
	extends XRController3D

	var rig: XRRig
	var holding: VRControl = null
	var _last_near: VRControl = null
	var _grip_was := false
	var poke_tip: Node3D
	var laser: MeshInstance3D
	var controller_model: ControllerVisual
	# Separate node tracking the AIM pose (the natural pointing ray). The hand
	# itself tracks the GRIP pose, which is right for grabbing but points up and
	# back — using it as a laser ray made the menu impossible to point at. The
	# aim pose also maps to hand-tracking's pinch-point ray, so one path serves
	# controllers and bare hands alike.
	var aim: XRController3D
	# Bare-hand equivalents, assigned by XRRig alongside `aim`. `hand_mesh` is
	# the hand-tracker-bound sibling (XRRig.hand_l_mesh/hand_r_mesh) — used as
	# this hand's effective position whenever the controller itself isn't
	# tracked, since this node's own transform (bound to the controller
	# tracker) goes stale/frozen once the controller is set down. `hand_aim` is
	# XR_FB_hand_tracking_aim's per-finger pinch data (tracker
	# /user/fbhandaim/left|right) — the source for effective_trigger()/
	# effective_grip() below.
	var hand_mesh: XRNode3D
	var hand_aim: XRController3D
	var _interact_mat: StandardMaterial3D

	func _init(tracker_name: String) -> void:
		tracker = tracker_name
		pose = "grip_pose"

	func _ready() -> void:
		poke_tip = Node3D.new()
		poke_tip.position = Vector3(0, -0.01, -0.06)
		add_child(poke_tip)
		# Interaction-state indicator: neutral/dim normally, yellow when near
		# something grabbable or pokeable, green while actively holding it.
		# Unshaded so it's always clearly visible regardless of cockpit
		# lighting (unlike the controller model — see the layer/lighting note
		# on ControllerVisual).
		_interact_mat = StandardMaterial3D.new()
		_interact_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_interact_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_interact_mat.albedo_color = Color(1, 1, 1, 0.25)
		var indicator := MeshInstance3D.new()
		var ism := SphereMesh.new()
		ism.radius = 0.018
		ism.height = 0.036
		indicator.mesh = ism
		indicator.material_override = _interact_mat
		poke_tip.add_child(indicator)
		# Real Touch controller model. OpenXRFbRenderModel (XR_FB_render_model)
		# would be the zero-asset way to do this, but it's confirmed NOT
		# supported on Quest 3S specifically (Khronos runtime extension matrix,
		# corroborated by an invisible controller on-device 2026-07-02) even
		# though it works on Quest 1/2/3/Pro — so this uses a bundled
		# MIT-licensed model instead (assets/controllers/, see SOURCE.md),
		# mechanically animated by real input in controller_visual.gd. Hidden
		# whenever this hand's controller isn't tracked (see _physics_process).
		controller_model = ControllerVisual.new()
		controller_model.is_left = (tracker == "left_hand")
		controller_model.hand = self
		controller_model.visible = false
		add_child(controller_model)
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
		if not get_has_tracking_data() and hand_mesh and hand_mesh.get_has_tracking_data():
			return hand_mesh.global_position
		return global_position

	# get_float("trigger")/("grip") only ever have data while the physical
	# controller is tracked. XR_FB_hand_tracking_aim gives the bare-hand
	# equivalents as continuous per-finger pinch strengths (0..1) — index
	# finger stands in for the trigger (natural "point and pinch"), the other
	# three together stand in for the grip squeeze (natural fist-close). Both
	# fold in cleanly: whichever source is actually live wins, since the
	# untracked source always reads 0.
	func effective_trigger() -> float:
		var t := get_float("trigger")
		if hand_aim:
			t = maxf(t, hand_aim.get_float("index_pinch_strength"))
		return t

	func effective_grip() -> float:
		var g := get_float("grip")
		if hand_aim:
			var squeeze := (hand_aim.get_float("middle_pinch_strength")
				+ hand_aim.get_float("ring_pinch_strength")
				+ hand_aim.get_float("little_pinch_strength")) / 3.0
			g = maxf(g, squeeze)
		return g

	func _physics_process(delta: float) -> void:
		if rig == null:
			return
		# Controller model only shows while this hand's physical controller is
		# actually tracked — bare-hand play (hand_l_mesh/hand_r_mesh in XRRig)
		# takes over via its own show_when_tracked when this goes false.
		controller_model.visible = get_has_tracking_data()
		if Game.state == Game.GState.MENU:
			_menu_pointer()
			_interact_mat.albedo_color = Color(1, 1, 1, 0.25)
			return
		laser.visible = false
		if rig.tank == null:
			return
		var gripping := effective_grip() > 0.55
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
		# poke_tip is a rigid child offset in controller-grip space — meaningless
		# once the controller's untracked and this node's own transform has gone
		# stale, so fall back to the live hand-tracking position instead.
		var tip := poke_tip.global_position if get_has_tracking_data() else hand_pos()
		var poke_near := false
		for c in get_tree().get_nodes_in_group("vrcontrols"):
			var vc := c as VRControl
			if vc and not vc.can_grab() and vc.enabled and vc.global_position.distance_to(tip) < 0.25:
				vc.poke_check(tip, delta)
				poke_near = true
		if holding != null:
			_interact_mat.albedo_color = Color(0.3, 1.0, 0.3, 0.9)
		elif _last_near != null or poke_near:
			_interact_mat.albedo_color = Color(1.0, 0.85, 0.15, 0.75)
		else:
			_interact_mat.albedo_color = Color(1, 1, 1, 0.25)
		if holding is VRControl.TwoAxisGrip:
			if effective_trigger() > 0.6 and not get_meta("trig_was", false):
				rig.tank.call("fire_primary")
			set_meta("trig_was", effective_trigger() > 0.6)
			rig.tank.call("set_mg", is_button_pressed("ax_button"))

	func _menu_pointer() -> void:
		var m: MainMenu = get_tree().get_first_node_in_group("menu")
		if m == null:
			laser.visible = false
			return
		# Ray origin/direction: prefer this hand's aim pose; if the controller
		# isn't tracked (set down, or hand-tracking lost), fall back to the head
		# so the menu is always pointable by gaze.
		var from: Vector3
		var dir: Vector3
		var head := false
		if aim and aim.get_has_tracking_data():
			from = aim.global_position
			dir = -aim.global_transform.basis.z
		elif get_has_tracking_data():
			from = global_position
			dir = -global_transform.basis.z
		elif hand_mesh and hand_mesh.get_has_tracking_data():
			from = hand_mesh.global_position
			dir = -hand_mesh.global_transform.basis.z
		elif rig and rig.camera and tracker == "right_hand":
			# only one hand drives the gaze fallback, else both double-click it
			from = rig.camera.global_position
			dir = -rig.camera.global_transform.basis.z
			head = true
		else:
			laser.visible = false
			return
		# Click via trigger, A/X, the menu button, or (bare hands) an index
		# pinch — no single dead binding should be able to lock the player out
		# of the menu.
		var pressed := effective_trigger() > 0.6 or is_button_pressed("ax_button") \
			or is_button_pressed("menu_button")
		var clicked: bool = pressed and not get_meta("mtrig_was", false)
		set_meta("mtrig_was", pressed)
		var res := m.pointer(from, dir, clicked)
		# Only the head-gaze ray hides the hand laser; a tracked hand always
		# shows its beam even when it's off the panel, so aiming has feedback.
		if head or res.is_empty():
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

var _debug_label: Label3D

func _ready() -> void:
	camera = XRCamera3D.new()
	add_child(camera)
	# Temporary on-device diagnostic readout (2026-07-02) — pinned to the
	# camera so it's always in view. Two rounds of "still doesn't work"
	# reports with no way to tell WHY from here; this gives real numbers
	# instead of another guess. Remove once hand-tracking interaction is
	# confirmed solid on-device.
	_debug_label = Label3D.new()
	_debug_label.font_size = 24
	_debug_label.pixel_size = 0.0012
	_debug_label.position = Vector3(0, -0.12, -0.5)
	_debug_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_debug_label.no_depth_test = true
	_debug_label.modulate = Color(1, 1, 0.6)
	camera.add_child(_debug_label)
	hand_l = XRHand.new("left_hand")
	hand_l.rig = self
	add_child(hand_l)
	hand_r = XRHand.new("right_hand")
	hand_r.rig = self
	add_child(hand_r)
	# aim-pose siblings (menu laser rays). Direct children of the origin so they
	# read the aim pose in origin space, not compounded with the grip pose.
	hand_l.aim = _make_aim("left_hand")
	hand_r.aim = _make_aim("right_hand")
	# Bare-hand visuals: Meta's own runtime-supplied skinned hand mesh
	# (XR_FB_hand_tracking_mesh via OpenXRFbHandTrackingMesh — zero bundled
	# assets, same "fetch it live from the OS" trick as the controller model),
	# posed by the stock XRHandModifier3D from the same hand tracker. Each root
	# auto-hides via show_when_tracked whenever this hand isn't optically
	# tracked, so it and the controller model never show at once.
	hand_l_mesh = _make_hand_mesh("/user/hand_tracker/left", OpenXRFbHandTrackingMesh.HAND_LEFT)
	hand_r_mesh = _make_hand_mesh("/user/hand_tracker/right", OpenXRFbHandTrackingMesh.HAND_RIGHT)
	hand_l.hand_mesh = hand_l_mesh
	hand_r.hand_mesh = hand_r_mesh
	# Pinch-gesture siblings (XR_FB_hand_tracking_aim) — give grab/trigger a
	# bare-hand equivalent. Populated directly by the extension, same as the
	# hand trackers above: no action-map bindings needed.
	hand_l.hand_aim = _make_hand_aim("/user/fbhandaim/left")
	hand_r.hand_aim = _make_hand_aim("/user/fbhandaim/right")
	var wind := AudioStreamPlayer.new()
	wind.stream = Sfx.streams.get("wind_loop")
	wind.volume_db = -22.0
	wind.autoplay = true
	add_child(wind)
	var xr := XRServer.find_interface("OpenXR")
	if xr and xr.has_signal("pose_recentered"):
		xr.pose_recentered.connect(func(): _calibrated = false; _calib_t = 0.3)
	Game.camera_mode_changed.connect(func(_t: bool): _apply_camera_mode())
	# Defensive: if nothing is tracking a few seconds in, the OpenXR runtime or
	# action map is misconfigured — surface it rather than leaving the player
	# with a dead, unexplained menu. (If this ever fires again: check
	# get_tracker_profile() on XRServer.get_tracker("left_hand"/"right_hand") —
	# "/interaction_profiles/none" means no profile bound at all; see the
	# hand_interaction_profile project-setting note above _ready().)
	get_tree().create_timer(5.0).timeout.connect(func() -> void:
		var any := hand_r.get_has_tracking_data() or hand_l.get_has_tracking_data() \
			or (hand_r.aim and hand_r.aim.get_has_tracking_data()) \
			or (hand_l.aim and hand_l.aim.get_has_tracking_data())
		if not any:
			push_warning("[xr] no controller/hand tracking 5s after start — pick up the controllers, or check the OpenXR action map"))

func _make_aim(tracker_name: String) -> XRController3D:
	var c := XRController3D.new()
	c.tracker = tracker_name
	c.pose = "aim_pose"
	add_child(c)
	return c

# hand_tracker_path: "/user/hand_tracker/left" or "/user/hand_tracker/right".
# hand_side: OpenXRFbHandTrackingMesh.HAND_LEFT or HAND_RIGHT.
func _make_hand_mesh(hand_tracker_path: String, hand_side: int) -> XRNode3D:
	var root := XRNode3D.new()
	root.tracker = hand_tracker_path
	root.show_when_tracked = true
	var mesh := OpenXRFbHandTrackingMesh.new()
	mesh.hand = hand_side
	mesh.openxr_fb_hand_tracking_mesh_ready.connect(func() -> void:
		var mi := mesh.get_mesh_instance()
		if mi:
			mi.layers = 2)
	mesh.openxr_fb_hand_tracking_mesh_unavailable.connect(func() -> void:
		push_warning("[xr] hand tracking mesh unavailable for " + hand_tracker_path \
			+ " — runtime/permission may not support XR_FB_hand_tracking_mesh"))
	root.add_child(mesh)
	var modifier := XRHandModifier3D.new()
	modifier.hand_tracker = hand_tracker_path
	mesh.add_child(modifier)
	add_child(root)
	return root

# fbhandaim_path: "/user/fbhandaim/left" or "/user/fbhandaim/right".
func _make_hand_aim(fbhandaim_path: String) -> XRController3D:
	var c := XRController3D.new()
	c.tracker = fbhandaim_path
	add_child(c)
	return c

func to_menu_anchor(parent: Node3D) -> void:
	tank = null
	if get_parent() != parent:
		get_parent().remove_child(self)
		parent.add_child(self)
	transform = Transform3D()
	_calibrated = true  # natural floor height at the menu
	# reparenting knocks the camera out of the tree and clears `current` —
	# without this the XR viewport renders NOTHING (black, draws=0)
	camera.current = true
	camera.make_current()

func attach_to_vehicle(v: Node3D) -> void:
	tank = v
	var anchor: Node3D = v.cockpit["seat_anchor"]
	if get_parent() != anchor:
		get_parent().remove_child(self)
		anchor.add_child(self)
	transform = Transform3D()
	_calibrated = false
	_calib_t = 0.0
	camera.current = true
	camera.make_current()
	v.set("_rumble_cb", func(amp, dur):
		hand_l.pulse(amp, dur)
		hand_r.pulse(amp, dur))

# Third person in VR pulls the whole rig back and up in the vehicle frame so
# you view it like a drone — the headset still drives look, which keeps it
# comfortable (no forced camera motion). First person seats you in the cockpit.
func _apply_camera_mode() -> void:
	_apply_view_offset()

func _apply_view_offset() -> void:
	position = _fp_pos + (Vector3(0, 3.0, 8.0) if Game.third_person else Vector3.ZERO)

func _update_debug_label() -> void:
	_debug_label.text = "%s\n%s" % [_hand_debug_line("L", hand_l), _hand_debug_line("R", hand_r)]

func _hand_debug_line(tag: String, h: XRHand) -> String:
	var ctl := "Y" if h.get_has_tracking_data() else "n"
	var hnd := "Y" if (h.hand_mesh and h.hand_mesh.get_has_tracking_data()) else "n"
	var aim_ok := "Y" if (h.hand_aim != null) else "n"
	return "%s ctl=%s hnd=%s aim=%s grp=%.2f trg=%.2f near=%s hold=%s" % [
		tag, ctl, hnd, aim_ok, h.effective_grip(), h.effective_trigger(),
		"Y" if h._last_near else "n", "Y" if h.holding else "n"]

func _physics_process(delta: float) -> void:
	_update_debug_label()
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
		var trig := hand_r.effective_trigger() > 0.6
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
	_feed_arm_swing(delta)

# squeeze EVERYTHING (both grips + both triggers) + A for 1.5 s → chaos.
# Bare hands have no A: squeezing everything alone works after 3.5 s.
var _egg_t := 0.0
var _egg_cool := 0.0
func _check_easter_egg(delta: float) -> void:
	_egg_cool = maxf(0.0, _egg_cool - delta)
	var squeeze := hand_l.effective_grip() > 0.8 and hand_r.effective_grip() > 0.8 \
		and hand_l.effective_trigger() > 0.8 and hand_r.effective_trigger() > 0.8
	var with_a := squeeze and hand_r.is_button_pressed("ax_button")
	if squeeze and _egg_cool <= 0.0:
		_egg_t += delta
		if fmod(_egg_t, 0.25) < delta:
			hand_l.pulse(0.3, 0.05)
			hand_r.pulse(0.3, 0.05)
		if _egg_t > (1.5 if with_a else 3.5):
			_egg_t = 0.0
			_egg_cool = Tune.v("disaster_cooldown")
			var w: Weather = get_tree().get_first_node_in_group("weather")
			if w:
				w.start_disaster(["tornado", "volcano", "hurricane"][Game.rng.randi() % 3])
				hand_l.pulse(1.0, 0.3)
				hand_r.pulse(1.0, 0.3)
	else:
		_egg_t = 0.0

# arm-swing speed for the runner (works with controllers AND bare hands)
var _prev_hl := Vector3.ZERO
var _prev_hr := Vector3.ZERO
var _swing := 0.0
func _feed_arm_swing(delta: float) -> void:
	if tank == null or not tank.has_method("set_arm_swing"):
		return
	var vl := (hand_l.position - _prev_hl).length() / maxf(delta, 0.001)
	var vr := (hand_r.position - _prev_hr).length() / maxf(delta, 0.001)
	_prev_hl = hand_l.position
	_prev_hr = hand_r.position
	_swing = lerpf(_swing, (vl + vr) * 0.5, 6.0 * delta)
	tank.call("set_arm_swing", _swing)

func _dz(v: float) -> float:
	return v if absf(v) > 0.12 else 0.0

func _calibrate() -> void:
	var eye_local: Vector3 = tank.cockpit["eye_local"]
	var cam_t := camera.transform
	var cam_fwd := -cam_t.basis.z
	var cam_yaw := atan2(-cam_fwd.x, -cam_fwd.z)
	rotation = Vector3(0, -cam_yaw, 0)
	position = Vector3.ZERO
	_fp_pos = eye_local - (basis * cam_t.origin)
	_apply_view_offset()
	_calibrated = true
	Sfx.play_at("click", global_position, -8.0)

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
var _use_establishing_shot := false  # true only for the fresh level-start attach_to_vehicle() call
var _fp_pos := Vector3.ZERO   # calibrated first-person eye position

# On-foot mode (godot-xr-tools): built once here, enabled/disabled as the
# player enters/leaves a vehicle. See enter_on_foot()/_set_on_foot_active().
# on_foot_body itself is NOT built here — it's freshly instantiated per
# game session (needs terrain/projectiles/fx, like every other vehicle) and
# handed in by main.gd via enter_on_foot(). These provider/pickup nodes ARE
# permanent — they don't need level state, and XRToolsPlayerBody._ready()
# scans the "movement_providers" group once, so they must already exist in
# the tree before any on_foot_body is added.
var on_foot_body: OnFootBody = null
var _pickup_l: XRToolsFunctionPickup
var _pickup_r: XRToolsFunctionPickup
var _direct_l: XRToolsMovementDirect
var _direct_r: XRToolsMovementDirect
var _sprint: XRToolsMovementSprint
var _turn: XRToolsMovementTurn
var _climb: XRToolsMovementClimb
var _grapple_l: XRToolsMovementGrapple
var _grapple_r: XRToolsMovementGrapple
# Item-gated powers (Alex: grapple/climb were ALWAYS on — they must be earned).
# Set true the first time the matching pickable is grabbed (grapple_hook.gd /
# climbing_gloves.gd via acquire_grapple()/acquire_climb()); from then on the
# provider is allowed to enable in on-foot mode. Rig-lived, so it persists
# across vehicle enter/exit for the whole playthrough; a restart rebuilds the
# rig and re-clears these, which is the intended "start fresh" behavior. NOT a
# hold check: once found the power is yours (drop the prop, keep the ability —
# Spider-Man doesn't lose his webs by setting down a can).
var _grapple_acquired := false
var _climb_acquired := false

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
	# Curl-driven first-person hand (godot-xr-tools XRToolsHand, lowpoly
	# scene) shown while the physical controller is tracked — grip/trigger
	# curl the fingers automatically (the addon reads them from this node,
	# its ancestor XRController3D). Exists because the bundled controller
	# MODEL confirmed doesn't render on Quest 3S, leaving controller players
	# with literally invisible hands (Alex: "I can't really play the game
	# with controllers if I can't see where the controllers are"). Hidden
	# whenever bare-hand tracking takes over — hand_mesh (Meta's skinned
	# runtime hand) owns that case, so the two never double-render.
	var glove: Node3D
	var _interact_mat: StandardMaterial3D
	var _indicator: MeshInstance3D

	func _init(tracker_name: String) -> void:
		tracker = tracker_name
		# Pose name must be the ENGINE-side name, not the action-map action
		# name: OpenXRInterface::create_action renames default_pose->default,
		# aim_pose->aim, grip_pose->grip before registering the pose on the
		# tracker. "grip_pose" matched nothing, so this node NEVER received a
		# pose and get_has_tracking_data() was permanently false in controller
		# mode — the shared root cause behind the invisible glove, dead hatch
		# grabs, and frozen on-foot movement (XRToolsMovementDirect gates on
		# get_is_active()). Buttons/sticks kept working because they don't
		# depend on the pose binding, which is why only pose-side features died.
		pose = "grip"
		# Alex: hand mesh (curl-driven glove) still "nothing at all" while
		# holding controllers, despite the visibility code looking
		# structurally sound. Gemini flagged a real candidate: XRNode3D
		# (XRController3D's parent class) has a native show_when_tracked
		# property that, if true, makes the ENGINE itself force this whole
		# node's visible false whenever ITS OWN tracked-check disagrees with
		# our manual get_has_tracking_data() one in _physics_process below --
		# which would silently override glove.visible = true since glove is
		# a child of this node. Never set explicitly anywhere before, so it
		# was whatever XRNode3D's own default is. Take back manual control.
		show_when_tracked = false

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
		_indicator = MeshInstance3D.new()
		var ism := SphereMesh.new()
		ism.radius = 0.018
		ism.height = 0.036
		_indicator.mesh = ism
		_indicator.material_override = _interact_mat
		# top_level: this ball is the ACTUAL hitbox used for grab/poke, not a
		# decoration — it must track wherever `tip` really is every frame
		# (see _physics_process below), which differs from this node's own
		# rigid-child transform during hand-tracking. Before this fix the
		# ball stayed rigidly parented to poke_tip (itself rigid in
		# controller-grip space), so it visibly froze wherever the
		# controller was last held instead of following the real tracked
		# hand — Alex: "highlight[s] a weird part... outside my thumb,"
		# because the ball he saw and the real check position were two
		# different places.
		_indicator.top_level = true
		add_child(_indicator)
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
		# Prefer the hand-tracking-mesh position whenever it's actually tracked,
		# not just when the controller ISN'T — XR_EXT_hand_interaction (enabled
		# for bare-hand pinch/grasp) synthesizes a grip pose on this SAME
		# left_hand/right_hand tracker while hand-tracking is active, so
		# get_has_tracking_data() alone can read true with no controller in
		# hand. That synthesized pose is fine for pinch/grasp button values but
		# isn't guaranteed to track the real hand position accurately — the
		# hand tracker's own position (feeding the visible hand mesh) is the
		# authoritative source whenever it has data.
		if hand_mesh and hand_mesh.get_has_tracking_data():
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
		# Controller model + curl-driven glove show while this hand's physical
		# controller is tracked AND bare-hand tracking isn't active — the
		# bare-hand mesh (hand_l_mesh/hand_r_mesh, Meta's runtime skinned
		# hand) owns the bare-hand case via its own show_when_tracked. The
		# extra bare-hand check matters: XR_EXT_hand_interaction synthesizes
		# a pose on this SAME tracker during bare-hand play (see hand_pos()),
		# so get_has_tracking_data() alone can read true with no controller
		# in hand.
		var bare := hand_mesh != null and hand_mesh.get_has_tracking_data()
		var controllers := get_has_tracking_data() and not bare
		# "four arms" fix: the licensed Touch GLB (controller_model) and the
		# godot-xr-tools lowpoly glove BOTH used to render at the same hand
		# point whenever a controller was tracked — two hand-props per hand,
		# reading as four across both hands. The GLB is the intended real
		# controller visual (it DOES render on 3S — it's a bundled asset, not
		# XR_FB_render_model), so it wins; the glove only fills in when the GLB
		# isn't up (defensive — should be never once loaded, but the glove was
		# originally the fallback for exactly that case).
		var glb_ok := controller_model.get_child_count() > 0
		controller_model.visible = controllers
		if glove:
			glove.visible = controllers and not glb_ok
		# Same laser-pointer path drives both the hangar MainMenu
		# (GState.MENU) and the mid-mission pause panel (Game.paused) --
		# both join group "menu" and implement the same pointer()
		# contract, and the two states are mutually exclusive so there is
		# never more than one to route to.
		if Game.state == Game.GState.MENU or Game.paused:
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
		_indicator.global_position = tip   # ball now always shows the REAL hitbox, not a rigid guess
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
		# Ray origin/direction: prefer the hand-tracking-mesh position whenever
		# it's actually tracked (authoritative — see hand_pos()'s comment on
		# why get_has_tracking_data() alone on the controller tracker isn't
		# enough during bare-hand play), then this hand's real controller aim
		# pose, then its grip pose; if nothing is tracked (controller set
		# down, hand-tracking lost), fall back to the head so the menu is
		# always pointable by gaze.
		var from: Vector3
		var dir: Vector3
		var head := false
		# Priority order matters and was wrong twice. Quest 3S runs hand
		# tracking CONCURRENTLY with controllers (Alex sees "controllers
		# embedded in the hands"), so a bare-hand tracker reporting data does
		# NOT mean the player has no controller. Rule: if the CONTROLLER is
		# tracked, its aim pose wins, full stop — that is what the sample
		# project does and what works. fbhandaim only drives the ray when the
		# controller itself is untracked (true bare-hand play); its aim pose
		# is garbage while a controller is held (ray "pointed up instead of
		# out", live report 2026-07-04).
		if get_has_tracking_data() and aim and aim.get_has_tracking_data():
			from = aim.global_position
			dir = -aim.global_transform.basis.z
		elif get_has_tracking_data():
			from = global_position
			dir = -global_transform.basis.z
		elif hand_aim and hand_aim.get_has_tracking_data():
			from = hand_aim.global_position
			dir = -hand_aim.global_transform.basis.z
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
			# Draw the beam along the ACTUAL ray (from/dir above), not down
			# this node's own -Z: this node is the GRIP pose, which tilts
			# steeply up from the aim pose the ray really uses — the beam
			# read as "big yellow lines pointing up, not mimicking the
			# raycast" (Alex, live headset 2026-07-06) while clicks still
			# landed fine. Global transform set every frame while pointing,
			# so the parent's grip motion can't skew it.
			var up := Vector3.UP if absf(dir.y) < 0.99 else Vector3.FORWARD
			laser.global_transform = Transform3D(
				Basis.looking_at(dir, up) * Basis.from_scale(Vector3(1, 1, d)),
				from + dir * (d * 0.5))
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
var _mp_board: Label3D

func _ready() -> void:
	camera = XRCamera3D.new()
	# XRHelpers.get_xr_camera() (used by XRToolsPlayerBody) looks up
	# origin.get_node_or_null("Camera") first, falling back to an
	# owner-filtered child search otherwise — and nothing in this rig has an
	# `owner` set (it's all built at runtime, never instantiated from a
	# .tscn), so that fallback always misses. Naming it "Camera" is required,
	# not cosmetic — without it XRToolsPlayerBody.camera_node stays null and
	# OnFootBody crashes every physics frame.
	camera.name = "Camera"
	add_child(camera)
	# On-device diagnostic readout (2026-07-02) — pinned to the camera so
	# it's always in view. Confirmed hand-tracking/controller input is
	# reading correctly on-device (2026-07-03), so hidden by default now —
	# left in place (and still updated each frame in _update_debug_label())
	# rather than ripped out, in case a future input regression needs the
	# same quick on-device readout again. Flip `visible = true` to bring it
	# back.
	_debug_label = Label3D.new()
	_debug_label.font_size = 24
	_debug_label.pixel_size = 0.0012
	_debug_label.position = Vector3(0, -0.12, -0.5)
	_debug_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_debug_label.no_depth_test = true
	_debug_label.modulate = Color(1, 1, 0.6)
	_debug_label.visible = false
	camera.add_child(_debug_label)
	# Multiplayer scoreboard: a small always-on readout pinned to the top of
	# view (the "pause menu" ask reframed for VR — a persistent lobby/score
	# panel beats a modal you'd have to open one-handed mid-fight). Shows the
	# other player's name + the current score/round; hidden in solo. Toggled
	# off/on by holding the LEFT menu button isn't needed — it's unobtrusive.
	_mp_board = Label3D.new()
	_mp_board.font_size = 28
	_mp_board.pixel_size = 0.0011
	_mp_board.position = Vector3(0, 0.16, -0.55)
	_mp_board.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_mp_board.no_depth_test = true
	_mp_board.modulate = Color(0.95, 0.95, 1.0)
	_mp_board.visible = false
	camera.add_child(_mp_board)
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
	# Curl-driven first-person hands for controller play (see XRHand.glove).
	# The addon's XRToolsHand._physics_process finds this ancestor
	# XRController3D and reads grip/trigger from it — no wiring needed.
	# .owner set per the addon convention documented at _build_on_foot_nodes.
	hand_l.glove = _make_glove(hand_l, "res://addons/godot-xr-tools/hands/scenes/lowpoly/left_hand_low.tscn")
	hand_r.glove = _make_glove(hand_r, "res://addons/godot-xr-tools/hands/scenes/lowpoly/right_hand_low.tscn")
	_build_on_foot_nodes()
	var wind := AudioStreamPlayer.new()
	wind.stream = Sfx.streams.get("wind_loop")
	wind.volume_db = -22.0
	wind.autoplay = true
	add_child(wind)
	var xr := XRServer.find_interface("OpenXR")
	if xr and xr.has_signal("pose_recentered"):
		xr.pose_recentered.connect(func(): _calibrated = false; _calib_t = 0.3; _use_establishing_shot = false)
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
	c.pose = "aim"  # engine pose name; "aim_pose" (the action name) never matches
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

func _make_glove(hand: XRHand, scene_path: String) -> Node3D:
	var glove: Node3D = load(scene_path).instantiate()
	glove.visible = false   # visibility driven per-frame in XRHand._physics_process
	hand.add_child(glove)
	glove.owner = self
	# Alex, live headset: hand mesh is "nothing at all" while holding
	# controllers, despite the glove code itself looking structurally sound.
	# Found a real asymmetry investigating this: the glove was the ONLY
	# controller-adjacent visual put on layer 2 alone (cockpit interior,
	# `sun.light_cull_mask` explicitly EXCLUDES it, and dome_light starts at
	# energy 0.0 "off until battery on" — cockpit_builder.gd) — the
	# controller_model it sits right next to uses default layer 1, lit
	# normally. On foot there's no cockpit/dome light at all, and even
	# seated before quick-starting the engine the glove would be lit by
	# ambient only. Adding layer 1 so it's ALSO lit like everything else
	# (sun/ambient) — dome light on layer 2 still tints it extra when
	# seated with the engine running, it's just no longer the ONLY source.
	MeshKit.set_layer_recursive(glove, 1 | 2)
	return glove

func to_menu_anchor(parent: Node3D) -> void:
	tank = null
	Game.player_mode = Game.PlayerMode.SEATED
	_set_on_foot_active(false)
	if get_parent() != parent:
		get_parent().remove_child(self)
		parent.add_child(self)
	transform = Transform3D()
	# Alex, live headset: "when we toggle to third person the menu needs to
	# come with us or we're too far away." Root cause: Game.third_person
	# carried over from the last mission, never reset here — any later
	# _apply_view_offset() call (camera_mode_changed re-firing, etc.) then
	# applies the seated third-person chase offset (+3,+8 local) on top of
	# the menu's own transform, displacing the rig away from the hangar UI.
	# The menu has no vehicle to orbit, so third-person has no meaning here.
	Game.third_person = false
	_calibrated = true  # natural floor height at the menu
	# reparenting knocks the camera out of the tree and clears `current` —
	# without this the XR viewport renders NOTHING (black, draws=0)
	camera.current = true
	camera.make_current()

# Wide establishing shot held during the ~1.2s pre-calibration window (see
# _calibrate() below) when entering a fresh level. Alex, live headset:
# "when we first begin in first person mode, for about a second we
# quickly see an 'almost' third person view. I actually quite like that...
# start with a nice wide shot... at a good 45 degree angle, with your
# vehicle dead center, before you pop into control." That glimpse was
# actually an ACCIDENT of timing -- before _calibrate() runs, `position`
# is whatever the raw pre-offset state happens to be, and it looked wide/
# elevated because a real standing headset height differs from the
# eventual seated eye position (so it varies with however tall the player
# is / however they're standing at that exact moment). Made it a
# deliberate, consistent offset instead. Rotation stays identity (matches
# the seat's own forward, same as third-person's existing offset) --
# empirically the player's natural head orientation already frames the
# vehicle fine without forcing a look-at, exactly like third person
# already does.
#
# Alex, 2026-07-06: hold this shot for 2s LONGER before cutting to the
# selected view mode, and make sure it never looks like just a preview of
# one of the chase-cam distances -- a real 3/4 angle (genuine X/side
# offset, not just straight-behind-and-above) at a distance clear of both
# THIRD (~8.5m) and the new FAR (~14.6m, THIRD + 20') chase distances.
const ESTABLISHING_SHOT_OFFSET := Vector3(9.0, 13.0, 10.0)  # dist ~18.7m, side+above -- distinct from both chase cams
const ESTABLISHING_SHOT_EXTRA_HOLD := 2.0  # on top of the normal ~1.2s calibration wait

# Chase-cam offsets, expressed in the seat_anchor's own rotating local frame
# (SEATED only -- see _apply_view_offset()). FAR is THIRD_OFFSET plus 20'
# (6.096m) of extra distance straight back, per Alex's ask -- literally
# "another 20' further back," not a different angle.
const THIRD_OFFSET := Vector3(0, 3.0, 8.0)
const FAR_EXTRA_BACK := 6.096  # 20 feet
const FAR_OFFSET := Vector3(0, 3.0, 8.0 + FAR_EXTRA_BACK)

func attach_to_vehicle(v: Node3D, show_establishing_shot: bool = false) -> void:
	tank = v
	Game.player_mode = Game.PlayerMode.SEATED
	_set_on_foot_active(false)
	if on_foot_body and is_instance_valid(on_foot_body):
		on_foot_body.enabled = false
	var anchor: Node3D = v.cockpit["seat_anchor"]
	if get_parent() != anchor:
		get_parent().remove_child(self)
		anchor.add_child(self)
	transform = Transform3D()
	if show_establishing_shot:
		position = ESTABLISHING_SHOT_OFFSET
	_calibrated = false
	_calib_t = 0.0
	_use_establishing_shot = show_establishing_shot
	camera.current = true
	camera.make_current()
	v.set("_rumble_cb", func(amp, dur):
		hand_l.pulse(amp, dur)
		hand_r.pulse(amp, dur))

# ---------------------------------------------------------------- on-foot mode
# Movement-provider/pickup nodes: built ONCE here (permanent, enabled=false)
# since XRToolsPlayerBody._ready() scans the "movement_providers" group a
# single time — they must already exist in the tree before any OnFootBody is
# added. Instantiated from the addon's own .tscn files (not .new()) because
# movement_grapple.gd expects pre-built child nodes (Grapple_RayCast,
# Grapple_Target, LineHelper/Line) that only exist via its packed scene, and
# every provider .tscn already carries the "movement_providers" group tag.
# Build order matters: movement_climb.gd's _ready() calls a method directly
# on XRToolsFunctionPickup.find_left/right(self) with no null-check, and
# movement_sprint.gd resolves XRToolsMovementDirect.find_left/right(self) via
# @onready — so pickups and direct-movement nodes must exist under hand_l/
# hand_r before climb/sprint are added.
# XRTools.find_xr_child() (used by the find_left()/find_right() helpers that
# XRToolsMovementClimb/Sprint call from their own @onready vars) defaults to
# owned=true — i.e. it skips any node whose `owner` is null. Every node below
# was built at runtime (never instantiated as part of a .tscn scene tree), so
# none of them have an owner unless set explicitly, and it must be set
# BEFORE the next node's add_child() (whose @onready vars resolve
# synchronously, during that same call) — not batched at the end. Without
# this, movement_climb.gd's _ready() calls .connect() on a null
# _left_pickup_node and crashes on the first frame.
func _build_on_foot_nodes() -> void:
	var pickup_scene: PackedScene = load("res://addons/godot-xr-tools/functions/function_pickup.tscn")
	_pickup_l = pickup_scene.instantiate()
	_pickup_l.enabled = false
	# Default direct-grab reach is 0.3m -- fine for something at hand height,
	# but ground-level pickables (the three on-foot power items, dropped
	# weapons) needed a full crouch to actually reach. Alex, 2026-07-07:
	# "make sure I can grab objects from a short distance... so I don't need
	# to bend all the way to the ground." Doubled, not maxed out -- still a
	# real reach-for-it gesture, not a magnetic full-room grab (the addon's
	# own ranged_enable=true/ranged_distance=5.0 already covers genuine
	# across-the-room pointing separately).
	_pickup_l.grab_distance = 0.6
	hand_l.add_child(_pickup_l)
	_pickup_l.owner = self
	_pickup_r = pickup_scene.instantiate()
	_pickup_r.enabled = false
	_pickup_r.grab_distance = 0.6
	hand_r.add_child(_pickup_r)
	_pickup_r.owner = self

	var direct_scene: PackedScene = load("res://addons/godot-xr-tools/functions/movement_direct.tscn")
	_direct_l = direct_scene.instantiate()
	_direct_l.strafe = true
	_direct_l.enabled = false
	hand_l.add_child(_direct_l)
	_direct_l.owner = self
	# Right stick is turning's slot (see _turn below), not movement — strafe
	# left OFF here so both axes are free. Was strafe=true on both hands,
	# meaning right-stick X did double duty (strafe AND, if a turn provider
	# were ever added, turn) with no way to add snap/smooth turning without
	# the two fighting over the same input.
	_direct_r = direct_scene.instantiate()
	_direct_r.strafe = false
	_direct_r.enabled = false
	hand_r.add_child(_direct_r)
	_direct_r.owner = self

	var sprint_scene: PackedScene = load("res://addons/godot-xr-tools/functions/movement_sprint.tscn")
	_sprint = sprint_scene.instantiate()
	_sprint.enabled = false
	add_child(_sprint)
	_sprint.owner = self

	# Snap/smooth turning (Alex: on-foot needs both as selectable options) —
	# the addon ships XRToolsMovementTurn already, just never wired up: on
	# foot previously had no turn binding at all beyond physically rotating
	# in place, since both direct-movement nodes claimed the full stick on
	# each hand for translation. Right stick X, mirroring the seated rigs'
	# left-stick-drives/right-stick-aims split. turn_mode is read fresh each
	# time on-foot goes active (_set_on_foot_active) so the pause-menu
	# toggle takes effect immediately without needing a fresh session.
	var turn_scene: PackedScene = load("res://addons/godot-xr-tools/functions/movement_turn.tscn")
	_turn = turn_scene.instantiate()
	_turn.enabled = false
	hand_r.add_child(_turn)
	_turn.owner = self

	var climb_scene: PackedScene = load("res://addons/godot-xr-tools/functions/movement_climb.tscn")
	_climb = climb_scene.instantiate()
	_climb.enabled = false
	add_child(_climb)
	_climb.owner = self

	var grapple_scene: PackedScene = load("res://addons/godot-xr-tools/functions/movement_grapple.tscn")
	# Spider-Man rule (Alex): ANY solid world surface is a valid grapple anchor,
	# not just the dedicated layer-6 "Grapple Target" bodies nobody ever placed.
	# RAYCAST mask = world (layers 1-5, DEFAULT) + climb handles (19): lets the
	# rope actually strike terrain, buildings, walls, vehicles, and climb-only
	# handles. ENABLE mask = which of those hits count: world floor/walls (1),
	# player vehicle hulls (2), enemy vehicle hulls (4), climbable handles (19)
	# — anything solid. Excluding pickables (layer 3) keeps the rope from
	# anchoring to a grenade in mid-air.
	# (1 << 5) = legacy layer 6 "Grapple Target" — nobody ever placed one, but
	# keeping it in the raycast mask costs nothing and can't break anything.
	var grapple_ray_mask := XRToolsMovementGrapple.DEFAULT_COLLISION_MASK | MeshKit.CLIMB_LAYER | (1 << 5)
	var grapple_anchor_mask := 1 | (1 << 1) | (1 << 2) | MeshKit.CLIMB_LAYER | (1 << 5)
	_grapple_l = grapple_scene.instantiate()
	_grapple_l.enabled = false
	_grapple_l.grapple_collision_mask = grapple_ray_mask
	_grapple_l.grapple_enable_mask = grapple_anchor_mask
	hand_l.add_child(_grapple_l)
	_grapple_l.owner = self
	_grapple_r = grapple_scene.instantiate()
	_grapple_r.enabled = false
	_grapple_r.grapple_collision_mask = grapple_ray_mask
	_grapple_r.grapple_enable_mask = grapple_anchor_mask
	hand_r.add_child(_grapple_r)
	_grapple_r.owner = self

	# main.gd marks THIS rig PROCESS_MODE_ALWAYS so the pause-menu laser
	# pointer keeps working while get_tree().paused freezes the level (see
	# Game.toggle_pause()) — but PROCESS_MODE_INHERIT would carry that
	# ALWAYS down to every child, letting sprint/climb/grapple/pickup keep
	# reading grip input and moving the player mid-pause. Pin them back to
	# the normal pausable behavior explicitly.
	for n in [_pickup_l, _pickup_r, _direct_l, _direct_r, _sprint, _turn, _climb, _grapple_l, _grapple_r]:
		n.process_mode = Node.PROCESS_MODE_PAUSABLE

	_wire_on_foot_haptics()

# The addon's own movement providers have zero haptic feedback wired in —
# grappling, climbing, and sprinting all currently feel silent/numb on a
# real controller. Both hands pulse together for simplicity (matches the
# existing easter-egg pattern below) rather than tracking exactly which
# hand triggered each provider.
func _wire_on_foot_haptics() -> void:
	_grapple_l.grapple_started.connect(_pulse_both.bind(0.55, 0.08))
	_grapple_r.grapple_started.connect(_pulse_both.bind(0.55, 0.08))
	_climb.player_climb_start.connect(_pulse_both.bind(0.3, 0.05))
	_sprint.sprinting_started.connect(_pulse_both.bind(0.2, 0.1))

func _pulse_both(amp: float, dur: float) -> void:
	hand_l.pulse(amp, dur)
	hand_r.pulse(amp, dur)

# Called once by main.gd right after constructing a fresh OnFootBody (it needs
# terrain/projectiles/fx, so unlike the nodes above it can't be built here).
func set_on_foot_body(body: OnFootBody) -> void:
	on_foot_body = body
	body._rig = self
	body.register_direct_movement(_direct_l, _direct_r)
	body._rumble_cb = func(amp, dur):
		hand_l.pulse(amp, dur)
		hand_r.pulse(amp, dur)

# Belt-and-suspenders: flips enabled on every on-foot pickup/movement-provider
# node together, called from both enter_on_foot() and attach_to_vehicle() so
# the two interaction systems (VRControl cockpit grab vs. addon pickup) never
# run at the same time even if something else fails to gate correctly.
func _set_on_foot_active(active: bool) -> void:
	_pickup_l.enabled = active
	_pickup_r.enabled = active
	_direct_l.enabled = active
	_direct_r.enabled = active
	_sprint.enabled = active
	_turn.enabled = active
	if active:
		# Re-read the menu preference on every on-foot entry rather than once
		# at build time, so picking SNAP vs SMOOTH in the pause menu takes
		# effect the next time you're on foot without needing a fresh session.
		_turn.turn_mode = XRToolsMovementTurn.TurnMode.SMOOTH if Game.smooth_turn \
			else XRToolsMovementTurn.TurnMode.SNAP
	# Climb/grapple are gated by pickups: even on foot they stay off until the
	# player has found the gloves / hook. _refresh_power_gates() (also called
	# by acquire_*() the instant a pickable is grabbed) is the single place
	# that resolves "on foot AND acquired".
	_refresh_power_gates()

# Re-derive climb/grapple provider enabled-state from mode + acquisition. The
# pickups themselves stay on whenever on-foot so the props can be grabbed in
# the first place — only the powers they unlock are gated.
func _refresh_power_gates() -> void:
	var on_foot := Game.player_mode == Game.PlayerMode.ON_FOOT
	_climb.enabled = on_foot and _climb_acquired
	_grapple_l.enabled = on_foot and _grapple_acquired
	_grapple_r.enabled = on_foot and _grapple_acquired

# Called by the pickables the first time they're grabbed. Permanent for the
# playthrough (see the _*_acquired notes above).
func acquire_grapple() -> void:
	_grapple_acquired = true
	_refresh_power_gates()

func acquire_climb() -> void:
	_climb_acquired = true
	_refresh_power_gates()

# Mid-mission vehicle exit (main.exit_vehicle()) and the menu-selectable
# "runner" vehicle both route through here. Reparents the rig to world_parent
# (same parent every vehicle lives under) at dismount_transform, then adds
# on_foot_body (already registered via set_on_foot_body()) as a direct child
# of the rig — required so XRHelpers.get_xr_origin() (walks up from the body
# looking for an XROrigin3D) finds this rig, not `world`.
func enter_on_foot(world_parent: Node3D, dismount_transform: Transform3D) -> void:
	tank = null
	if get_parent() != world_parent:
		get_parent().remove_child(self)
		world_parent.add_child(self)
	transform = dismount_transform
	camera.current = true
	camera.make_current()
	if on_foot_body.get_parent() != self:
		add_child(on_foot_body)
	on_foot_body.enabled = true
	# Set mode BEFORE _set_on_foot_active — _refresh_power_gates() reads
	# Game.player_mode to decide whether the (acquired) climb/grapple providers
	# may turn on.
	Game.player_mode = Game.PlayerMode.ON_FOOT
	_set_on_foot_active(true)
	_apply_view_offset()   # re-apply whatever camera-mode preference is current

# Third person in VR pulls the whole rig back and up in the vehicle frame so
# you view it like a drone — the headset still drives look, which keeps it
# comfortable (no forced camera motion). First person seats you in the cockpit.
func _apply_camera_mode() -> void:
	_apply_view_offset()

func _apply_view_offset() -> void:
	# Alex: "when I go to third person mode in the lobby we still need the
	# menu to come closer to me (or get bigger)". Game.third_person is a
	# persisted PREFERENCE for the next mission (MainMenu's own "viewtoggle"
	# button lets you set it while still in the hangar) -- it shouldn't
	# physically pull the camera away from the hangar's menu board, which
	# never resizes/repositions to compensate. Only apply the chase offset
	# once actually PLAYING (there's a real vehicle to orbit at that point).
	var third := Game.third_person and Game.state != Game.GState.MENU
	if Game.player_mode == Game.PlayerMode.ON_FOOT:
		# On-foot: the origin's position is fully addon-managed
		# (XRToolsPlayerBody.rotate_player()/move_body() etc. increment
		# origin_node.global_transform.origin every frame to track real+
		# virtual walking/turning) -- writing a baked local offset here the
		# way SEATED does below fights that and strands the origin at a
		# stale, disconnected spot (this used to reuse _fp_pos, which is
		# only ever computed by the SEATED _calibrate() and never touched on
		# foot). Root cause of "I still don't seem to see my avatar in third
		# person mode when I'm a runner" (Alex, 2026-07-06): the camera never
		# actually pulled back at all on foot, so the local AvatarRig (built
		# correctly -- see main.gd's _update_local_avatar()) sat right on top
		# of the camera the whole time, same as first person. Detach the
		# camera instead and chase it off the on-foot body's own live
		# position every frame -- see _update_on_foot_chase_cam(), called
		# from _physics_process().
		#
		# THE ACTUAL BLACK-SCREEN BUG (found 2026-07-07 from real device
		# logs): this used to also do `position = Vector3.ZERO` here, which
		# is correct for SEATED (there `position` is a LOCAL offset from a
		# seat_anchor parent, always meant to reset to identity) but WRONG
		# here -- on foot, the rig is parented directly to the level's
		# static world node, so `position` IS the origin's actual
		# world-relevant placement. enter_on_foot() sets `transform =
		# dismount_transform` a few lines before calling this function;
		# zeroing `position` right after threw that away and teleported the
		# WHOLE RIG to world origin (0,0,0) instead -- almost certainly
		# inside solid terrain or off in empty void on every level, which
		# reads as exactly "black screen... often when trying to use my
		# runner avatar." Confirmed via Cloudflare-pulled device logs: many
		# independent play sessions ALL ended abruptly within a couple
		# seconds of the "on-foot" log line, in plain FIRST person (not just
		# third/far, which is what the earlier top_level-snap hardening
		# targeted and didn't actually fix) -- consistent with the player
		# hard-quitting after landing inside geometry, not a script crash
		# (draws stayed non-zero right up to the cutoff in every capture).
		camera.top_level = third
		if third:
			# Snap immediately instead of leaving whatever stale local
			# transform the camera had before top_level flipped true --
			# top_level reinterprets that SAME transform as a world-space
			# one, which could be anywhere (still inside a vehicle's
			# rotating cockpit frame, mid-headset-tracking-update, etc.).
			# Left un-snapped, that's a real candidate for "I still see a
			# black screen often when trying to use my runner avatar" (Alex,
			# 2026-07-07) -- a degenerate/miles-away camera transform for
			# however many frames it took _update_on_foot_chase_cam() to
			# first correct it, or forever if on_foot_body wasn't valid yet.
			_update_on_foot_chase_cam(0.0, true)
		else:
			camera.transform = Transform3D()
		print("[camera] mode=", Game.CamMode.keys()[Game.cam_mode], " state=", Game.GState.keys()[Game.state], " on-foot")
		return
	camera.top_level = false
	var offset := Vector3.ZERO
	if third:
		offset = FAR_OFFSET if Game.cam_mode == Game.CamMode.FAR else THIRD_OFFSET
	position = _fp_pos + offset
	print("[camera] mode=", Game.CamMode.keys()[Game.cam_mode], " state=", Game.GState.keys()[Game.state], " pos=", position)

## On-foot equivalent of the SEATED chase offset above -- see
## _apply_view_offset()'s on-foot branch for why this can't just bake a
## local position offset the way seated vehicles do. Recomputed every
## physics frame from the on-foot body's actual position/facing (this rig's
## own basis already tracks snap/smooth turning -- XRToolsPlayerBody.
## rotate_player() rotates origin_node, i.e. this rig, around the camera on
## every turn, so -global_transform.basis.z is a live facing direction).
## snap=true jumps straight to the target instead of lerping -- used right
## after top_level flips true so there's never a frame with a stale/garbage
## transform (see the call site's comment).
func _update_on_foot_chase_cam(delta: float, snap: bool = false) -> void:
	if not camera.top_level or Game.player_mode != Game.PlayerMode.ON_FOOT:
		return
	if on_foot_body == null or not is_instance_valid(on_foot_body):
		# Nothing valid to chase -- fall back to a state that's guaranteed to
		# render something (identity, non-detached) rather than leave the
		# camera stuck detached with no target to correct toward.
		camera.top_level = false
		camera.transform = Transform3D()
		return
	var body_pos: Vector3 = on_foot_body.global_position
	if not (is_finite(body_pos.x) and is_finite(body_pos.y) and is_finite(body_pos.z)):
		return
	var facing := -global_transform.basis.z
	facing.y = 0.0
	if facing.length() < 0.01:
		facing = Vector3.FORWARD
	facing = facing.normalized()
	var back_dist := 3.2 + (FAR_EXTRA_BACK if Game.cam_mode == Game.CamMode.FAR else 0.0)
	var eye := body_pos - facing * back_dist + Vector3(0, 2.0, 0)
	var look := body_pos + Vector3(0, 1.0, 0)
	if eye.distance_to(look) < 0.05:
		return  # degenerate looking_at() input -- skip this tick rather than risk an invalid basis
	var target := Transform3D(Basis(), eye).looking_at(look, Vector3.UP)
	if snap:
		camera.global_transform = target
	else:
		camera.global_transform = camera.global_transform.interpolate_with(target, clampf(6.0 * delta, 0.0, 1.0))

## First-person head/hand pose relative to `relative_to`, ignoring any current
## third-person chase offset (_apply_view_offset() adds it straight to
## `position`, and hand_l/hand_r are children of this rig too so they'd drift
## by the same amount) — used to drive the local player's own AvatarRig so it
## stays anchored to the seat instead of floating off with the chase camera.
func local_body_pose(relative_to: Node3D) -> Dictionary:
	var origin_parent := get_parent()
	var base: Transform3D = (origin_parent.global_transform if origin_parent else Transform3D()) \
		* Transform3D(basis, _fp_pos)
	var inv := relative_to.global_transform.affine_inverse()
	return {
		"head": inv * (base * camera.transform),
		"hand_l": inv * (base * hand_l.transform),
		"hand_r": inv * (base * hand_r.transform),
	}

func _update_debug_label() -> void:
	_debug_label.text = "%s\n%s" % [_hand_debug_line("L", hand_l), _hand_debug_line("R", hand_r)]
	_update_mp_board()

# Persistent MP scoreboard/lobby panel (see _ready). Names the other player,
# shows the live score/round clock, plus host-only hints for the god-mode
# gestures so they're discoverable without docs.
func _update_mp_board() -> void:
	if _mp_board == null:
		return
	_mp_board.visible = NetManager.active()
	if not _mp_board.visible:
		return
	var me := Game.display_name if Game.display_name != "" else "You"
	var them := Game.peer_name if Game.peer_name != "" else "(waiting for player...)"
	var score := ""
	if Game.mode == Game.Mode.VERSUS:
		if Game.team_mode:
			score = "RED %d   BLUE %d" % [int(Game.team_score.get(Game.Team.RED, 0)), int(Game.team_score.get(Game.Team.BLUE, 0))]
		else:
			score = "YOU %d   THEM %d" % [Game.my_kills, Game.their_kills]
	else:
		score = "SCORE %d   WAVE %d" % [Game.score, maxi(Game.wave, 1)]
	if Game.round_active:
		score += "   %d:%02d" % [int(Game.round_left) / 60, int(Game.round_left) % 60]
	var seat := ""
	if Game.mode == Game.Mode.COOP:
		seat = "  [%s]" % ("DRIVER" if NetManager.i_am_driver() else "GUNNER")
	var txt := "%s  vs  %s%s\n%s" % [me, them, seat, score]
	if NetManager.hosting:
		txt += "\n(host: grips+B bots · grips+X diff · grips+A teams)"
	if Game.mode == Game.Mode.COOP:
		txt += "\n(grips+Y swap seats)"
	_mp_board.text = txt

func _hand_debug_line(tag: String, h: XRHand) -> String:
	var ctl := "Y" if h.get_has_tracking_data() else "n"
	var hnd := "Y" if (h.hand_mesh and h.hand_mesh.get_has_tracking_data()) else "n"
	var aim_ok := "Y" if (h.hand_aim != null) else "n"
	return "%s ctl=%s hnd=%s aim=%s grp=%.2f trg=%.2f near=%s hold=%s" % [
		tag, ctl, hnd, aim_ok, h.effective_grip(), h.effective_trigger(),
		"Y" if h._last_near else "n", "Y" if h.holding else "n"]

# Multiplayer gesture bindings (co-op/versus only). Two-hand grip gestures so
# they can't fire by accident during normal one-handed driving/gunning:
#   both grips + LEFT Y      → swap driver/gunner seats (co-op, either peer)
#   both grips + RIGHT B     → HOST god-mode: add 3 bots (host only)
#   both grips + LEFT X      → HOST god-mode: cycle difficulty (host only)
#   both grips + RIGHT A     → HOST god-mode: toggle 2-team mode (host only)
# All edge-triggered with a shared cooldown so one squeeze = one action.
var _mp_cool := 0.0
func _mp_hotkeys(delta: float) -> void:
	_mp_cool = maxf(0.0, _mp_cool - delta)
	var both_grip := hand_l.effective_grip() > 0.8 and hand_r.effective_grip() > 0.8
	# NOT while both triggers are also squeezed — that's the disaster easter
	# egg's gesture (grips+triggers+A), which must not double-fire god-mode.
	var triggers := hand_l.effective_trigger() > 0.6 or hand_r.effective_trigger() > 0.6
	if not both_grip or triggers or _mp_cool > 0.0:
		return
	# Solo driver<->gunner seat swap — same grips+Y gesture co-op already uses
	# for NetManager.request_seat_swap(), but purely local (no peer to swap
	# with). Checked before the NetManager.active() gate below so it still
	# fires in solo, where NetManager is never active.
	if hand_l.is_button_pressed("by_button") and Game.mode == Game.Mode.SOLO and tank is PlayerTank:
		_mp_cool = 0.6
		tank.call("toggle_seat")
		_pulse_both(0.4, 0.06)
		return
	if not NetManager.active():
		return
	if hand_l.is_button_pressed("by_button") and Game.mode == Game.Mode.COOP:
		_mp_cool = 0.6
		NetManager.request_seat_swap()
		_pulse_both(0.4, 0.06)
	elif NetManager.hosting and hand_r.is_button_pressed("by_button"):
		_mp_cool = 0.6
		NetManager.host_add_bots(3)
		_pulse_both(0.5, 0.08)
	elif NetManager.hosting and hand_l.is_button_pressed("ax_button"):
		_mp_cool = 0.6
		var d := (Game.difficulty + 1) % 3
		NetManager.host_change_session(Game.mode, Game.level_id, d, Game.mutator)
		_pulse_both(0.4, 0.06)
	elif NetManager.hosting and hand_r.is_button_pressed("ax_button"):
		_mp_cool = 0.6
		NetManager.host_set_team_mode(not Game.team_mode)
		_pulse_both(0.4, 0.06)

func _physics_process(delta: float) -> void:
	_update_debug_label()
	if Game.state == Game.GState.MENU:
		return
	# Menu button now PAUSES in place instead of tearing the level down
	# (Alex: "going back to the menu shouldn't kick you out of your current
	# level... pressing it again puts you back in your current game" —
	# quitting to the hangar is now a deliberate click on the pause panel
	# itself, see pause_menu.gd). Checked first, before the pause early-return
	# below, so the SAME button un-pauses too. _menu_pointer() (used for
	# both the hangar MainMenu AND this pause panel) reads menu_button for UI
	# clicks while Game.state == MENU or Game.paused, so this and that never
	# fight over the same press.
	var menu_pressed := hand_l.is_button_pressed("menu_button") or hand_r.is_button_pressed("menu_button")
	if menu_pressed and not get_meta("menu_btn_was", false):
		Game.toggle_pause()
		# Alex: "pause menu cannot be navigated" -- root cause: _menu_pointer()
		# (below, per-hand) treats menu_button as a CLICK too, and it's still
		# physically held down this same frame from the very press that just
		# opened the panel. Without this, that residual hold immediately
		# "clicks" whatever the laser happens to be resting on the instant
		# the panel appears (usually RESUME, since it's dead ahead) -- looked
		# like the panel couldn't be interacted with at all. Seed both hands'
		# debounce state so this press doesn't count as a NEW click until the
		# button is released and pressed again.
		hand_l.set_meta("mtrig_was", true)
		hand_r.set_meta("mtrig_was", true)
	set_meta("menu_btn_was", menu_pressed)
	if Game.paused:
		return
	# Global bindings — active whether seated or on-foot, per Alex's
	# explicit ask (2026-07-03): right-stick click toggles 1st/3rd person,
	# left-stick click resets the level (or leaves to the menu in
	# multiplayer, same as a networked player quitting out). Placed before
	# the on-foot/no-vehicle early returns below so they always work,
	# unlike the seated-only bindings further down.
	var r_click := hand_r.is_button_pressed("primary_click")
	if r_click and not get_meta("rsc_was", false):
		# Ignore while seated-but-uncalibrated (the establishing-shot window):
		# _apply_view_offset would compute from a still-zero _fp_pos and yank
		# the camera to a chase offset around the seat origin, cutting the
		# establishing shot short with a wrong-looking jump (2026-07-16 audit).
		if _calibrated or tank == null:
			Game.toggle_camera_mode()
	set_meta("rsc_was", r_click)
	var l_click := hand_l.is_button_pressed("primary_click")
	if l_click and not get_meta("lsc2_was", false):
		if Game.mode == Game.Mode.COOP or Game.mode == Game.Mode.VERSUS:
			var m_leave := get_tree().get_first_node_in_group("main")
			if m_leave:
				m_leave.call_deferred("to_menu")
		else:
			Game.restart()
	set_meta("lsc2_was", l_click)
	# Y/B/A each carry two actions, deconflicted by TAP vs HOLD. The 2026-07-16
	# release-prep audit found three genuine double-bindings here: bare left-Y
	# ran respawn AND seat-recalibrate on the same press (one accidental tap
	# wiped the whole run via Game.restart()), bare right-B ran rockets AND the
	# HUD toggle, bare right-A cycled the radio on every coax-MG burst — and
	# the grips+Y/B/X/A chords leaked into all of them too.
	#   LEFT Y   tap = seat recalibrate (seated) | hold 1s = respawn/reset run
	#   RIGHT B  tap = rockets | hold 0.8s = HUD toggle   (both seated-only;
	#            on-foot B stays the vehicle-entry input via _check_reentry)
	#   RIGHT A  hold = coax MG (unchanged) | quick tap = cycle radio station
	# Destructive/rare actions live on the HOLD with haptic charge ticks (same
	# telegraph idiom as the left-trigger exit hold); combat actions stay on
	# tap. A two-hand grip chord cancels any in-flight tap/hold outright so
	# seat-swap/god-mode presses can never leak.
	var seated_now := Game.player_mode == Game.PlayerMode.SEATED and tank != null
	if hand_l.effective_grip() > 0.8 and hand_r.effective_grip() > 0.8:
		_y_hold = -1.0
		_b_hold = -1.0
		_a_hold = -1.0
	if hand_l.is_button_pressed("by_button"):
		if _y_hold >= 0.0:
			_y_hold += delta
			if fmod(_y_hold, 0.25) < delta:
				hand_l.pulse(0.2, 0.03)
			if _y_hold > 1.0:
				_y_hold = -1.0
				if Game.alive:
					Game.restart()
					hand_l.pulse(0.6, 0.08)
	else:
		if _y_hold > 0.0 and _y_hold < 0.35 and seated_now:
			_calibrated = false
			_calib_t = 1.0
			_use_establishing_shot = false
			hand_l.pulse(0.3, 0.04)
		_y_hold = 0.0
	if hand_r.is_button_pressed("by_button"):
		if not get_meta("b_down_was", false) and not seated_now:
			# Press began OUTSIDE a cockpit — B doubles as the on-foot
			# enter-vehicle input (_check_reentry), so swallow the whole
			# press: entering with B must never fire rockets or toggle the
			# HUD on release once you land in the seat.
			_b_hold = -1.0
		elif _b_hold >= 0.0 and seated_now:
			_b_hold += delta
			if fmod(_b_hold, 0.25) < delta:
				hand_r.pulse(0.15, 0.03)
			if _b_hold > 0.8:
				_b_hold = -1.0
				Game.toggle_ui()
				hand_r.pulse(0.25, 0.03)
		set_meta("b_down_was", true)
	else:
		if _b_hold > 0.0 and _b_hold < 0.35 and seated_now:
			tank.call("stick_rockets")
		_b_hold = 0.0
		set_meta("b_down_was", false)
	if hand_r.is_button_pressed("ax_button"):
		if _a_hold >= 0.0:
			_a_hold += delta
	else:
		if _a_hold > 0.0 and _a_hold < 0.3 and hand_r.holding == null:
			Sfx.set_radio_station((Sfx.radio_station + 1) % Sfx.STATIONS.size())
			hand_r.pulse(0.3, 0.03)
		_a_hold = 0.0
	_mp_hotkeys(delta)
	if Game.player_mode == Game.PlayerMode.ON_FOOT:
		_feed_arm_swing(delta)
		_feed_stick_sprint()
		_check_reentry()
		_update_on_foot_chase_cam(delta)
		return
	if tank == null:
		return
	if not _calibrated:
		_calib_t += delta
		var _calib_threshold := 1.2 + (ESTABLISHING_SHOT_EXTRA_HOLD if _use_establishing_shot else 0.0)
		if _calib_t > _calib_threshold and camera.transform.origin.length() > 0.01:
			_calibrate()
	# Dedicated exit-vehicle binding (Alex: "we should absolutely have a
	# button to exit/enter vehicles!"): hold LEFT trigger ~1s while seated.
	# Left trigger was the one unused input in the seated map. Guards: not
	# while holding a physical control, not while the RIGHT trigger is also
	# in (that's the easter-egg / firing hand), and never on the parachute
	# (its trigger deploys the chute). Haptic ticks during the hold telegraph
	# that something is charging; negative reset debounces until release.
	if hand_l.effective_trigger() > 0.7 and hand_l.holding == null \
			and hand_r.effective_trigger() < 0.5 and not (tank is PlayerParachute):
		if _exit_hold >= 0.0:
			_exit_hold += delta
			if fmod(_exit_hold, 0.25) < delta:
				hand_l.pulse(0.25, 0.04)
			if _exit_hold > 1.0:
				_exit_hold = -1.0
				var m_exit := get_tree().get_first_node_in_group("main")
				if m_exit:
					m_exit.call_deferred("request_exit_vehicle")
	else:
		_exit_hold = 0.0
	var ls := hand_l.get_vector2("primary")
	var rs := hand_r.get_vector2("primary")
	# Left/right (X) confirmed fine on both sticks per the latest report.
	# Drive Y went through two rounds: originally raw (+ls.y) read as
	# backwards, negating it "fixed" that but the NEXT live pass reported
	# it backwards again in the other direction ("down drives forward, up
	# drives backward") — i.e. the negation itself was the bug, not the
	# fix. Reverted to raw. Turret Y stays as the (separately confirmed
	# correct) non-negated value from the previous round.
	# RIGHT TRIGGER = throttle/forward, standardized across every ground/water/
	# air vehicle (Alex: right trigger should drive every vehicle forward) —
	# folded additively into the stick's Y so the left stick still reverses
	# (trigger only ever pushes forward) and still steers via its X axis.
	# Heli and the parachute keep their own distinct schemes (collective/
	# cyclic, drift) where "forward throttle" doesn't apply.
	var drive_y := _dz(ls.y)
	if not (tank is PlayerAlt.Heli or tank is PlayerParachute):
		drive_y = maxf(drive_y, hand_r.effective_trigger())
	tank.call("set_stick_drive", Vector2(-_dz(ls.x), drive_y))
	tank.call("set_stick_turret", Vector2(_dz(rs.x), _dz(rs.y)))
	# Firing moved off the bare right trigger (now throttle) onto the grip
	# button — squeezing empty-handed fires, same "empty hand" guard the
	# exit-vehicle hold uses, so grabbing the wheel/turret stick/tillers to
	# actually steer never fires by accident. Grabbing a TwoAxisGrip control
	# still fires on trigger while held (unchanged — that hand is already
	# committed to aiming, not throttling). Parachute is the one exception:
	# it has no throttle at all, so its trigger keeps its documented
	# "pull to deploy" behavior instead of moving to the grip.
	if not (hand_r.holding is VRControl.TwoAxisGrip):
		var trig := (hand_r.effective_trigger() > 0.6 if tank is PlayerParachute \
			else hand_r.is_button_pressed("grip_click")) and hand_r.holding == null
		if trig and not get_meta("rtrig_was", false):
			tank.call("stick_fire")
		set_meta("rtrig_was", trig)
		if not (hand_l.holding is VRControl.TwoAxisGrip):
			tank.call("set_mg", hand_r.is_button_pressed("ax_button") and hand_r.holding == null)
	# Rockets (B tap), seat recalibrate (Y tap), and radio cycle (A tap) all
	# moved to the tap-vs-hold deconflict block earlier in this function —
	# they were double-bound here (2026-07-16 audit). Only X quick-start
	# remains a bare seated edge-trigger.
	if hand_l.is_button_pressed("ax_button") and not get_meta("x_was", false):
		tank.call("quick_start")
	set_meta("x_was", hand_l.is_button_pressed("ax_button"))
	# primary_click (left-stick click) used to also trigger quick_start here
	# — now repurposed for the global reset-level binding above (X button
	# alone still starts the engine), per Alex's explicit ask.
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

# arm-swing speed, feeding whichever body is currently active (works with
# controllers AND bare hands)
var _prev_hl := Vector3.ZERO
var _prev_hr := Vector3.ZERO
var _swing := 0.0
func _feed_arm_swing(delta: float) -> void:
	var target: Object = on_foot_body if Game.player_mode == Game.PlayerMode.ON_FOOT else tank
	if target == null or not target.has_method("set_arm_swing"):
		return
	# hand_pos() (rig-local), NOT hand_l.position: the controller tracker's
	# transform freezes when the controllers are set down, so bare-hand play
	# read as zero swing — "swinging my arms in hand tracking mode doesn't do
	# anything" (Alex, live headset 2026-07-06). hand_pos() prefers the live
	# hand-tracking mesh and falls back to the controller transform, so one
	# path serves both input styles. Rig-local so vehicle/world motion of the
	# rig itself never counts as swing.
	var pl := to_local(hand_l.hand_pos())
	var pr := to_local(hand_r.hand_pos())
	var vl := (pl - _prev_hl).length() / maxf(delta, 0.001)
	var vr := (pr - _prev_hr).length() / maxf(delta, 0.001)
	_prev_hl = pl
	_prev_hr = pr
	_swing = lerpf(_swing, (vl + vr) * 0.5, 6.0 * delta)
	target.call("set_arm_swing", _swing)

# Stick-based sprint option (Alex: alongside the existing arm-swing sprint) —
# hold the LEFT stick forward (the same stick that drives on-foot movement,
# via _direct_l) past SPRINT_THRESHOLD. Menu-toggleable (Game.sprint_stick);
# purely additive with arm-swing, since OnFootBody composes the two through
# separate multiplier/velocity paths (see on_foot_body.gd).
const SPRINT_STICK_THRESHOLD := 0.85
func _feed_stick_sprint() -> void:
	if on_foot_body == null or not is_instance_valid(on_foot_body):
		return
	var active := Game.sprint_stick and hand_l.get_vector2("primary").y > SPRINT_STICK_THRESHOLD
	on_foot_body.call("set_stick_sprint", active)

# Entry/re-entry: walk near ANY vehicle's seat and squeeze a grip, hold the
# left trigger, or press B to climb in. Originally this only targeted
# main.current_vehicle (the specific vehicle you last exited), which made
# fresh runner-mode starts entirely dependent on physically grabbing the
# hatch lever — impossible to discover, and unusable in third person where
# you can't even see your own hands (Alex, live headset 2026-07-06: "it
# doesn't make sense to have to grab things to get into a vehicle...
# just being close + holding left trigger or B should be enough").
# current_vehicle keeps priority (it's the seat you bailed from mid-mission)
# but any cockpit-bearing vehicle in range works now.
const ENTRY_RADIUS := 2.5
var _reentry_grip_was := false
var _exit_hold := 0.0
# Tap-vs-hold state for the three multiplexed face buttons (see the
# deconflict block in _physics_process): >=0 accumulating, -1 latched
# (action fired or press disqualified; ignore until release).
var _y_hold := 0.0
var _b_hold := 0.0
var _a_hold := 0.0
func _check_reentry() -> void:
	if on_foot_body == null or not is_instance_valid(on_foot_body):
		return
	var m := get_tree().get_first_node_in_group("main")
	if m == null:
		return
	var v: Node3D = m.get("current_vehicle")
	if v == null or not is_instance_valid(v):
		v = _nearest_enterable_vehicle()
	# grip, the left-trigger hold-gesture family shared with the exit
	# binding, or a plain B press — one input vocabulary for enter and exit
	var gripping := hand_l.effective_grip() > 0.55 or hand_r.effective_grip() > 0.55 \
		or hand_l.effective_trigger() > 0.7 or hand_r.is_button_pressed("by_button")
	if v and is_instance_valid(v):
		var anchor: Node3D = v.cockpit["seat_anchor"]
		if on_foot_body.global_position.distance_to(anchor.global_position) < ENTRY_RADIUS \
				and gripping and not _reentry_grip_was:
			m.call_deferred("enter_vehicle", v)
	_reentry_grip_was = gripping

# Nearest vehicle with a real cockpit (seat_anchor) within entry range of the
# on-foot body. Group "player" holds the player-side vehicles; the cockpit
# check filters out the on-foot body itself and any non-vehicle members.
func _nearest_enterable_vehicle() -> Node3D:
	var best: Node3D = null
	var best_d := ENTRY_RADIUS
	for p in get_tree().get_nodes_in_group("player"):
		var cand := p as Node3D
		if cand == null or not ("cockpit" in cand) or not cand.visible:
			continue
		var ck: Dictionary = cand.get("cockpit")
		if ck.is_empty() or not ck.has("seat_anchor"):
			continue
		var d := on_foot_body.global_position.distance_to(
			(ck["seat_anchor"] as Node3D).global_position)
		if d < best_d:
			best_d = d
			best = cand
	return best

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

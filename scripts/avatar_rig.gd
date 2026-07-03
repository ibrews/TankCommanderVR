# Procedural, transform-driven Rec-Room-style avatar body. No Skeleton3D —
# TCV has zero imported skeletal assets anywhere (every character is rigid
# MeshKit-built primitives repositioned per frame), so this rig is the same
# idiom applied to a body: fixed-shape mesh pieces whose per-frame transforms
# are computed from head/hand tracking data (or, for NPCs/remote players,
# from replicated/authored pose state). Absorbs and supersedes net.gd's old
# build_avatar() — SEATED mode is that same legless bean, now with arms.
class_name AvatarRig
extends Node3D

enum Mode { SEATED, ON_FOOT }

const HIP_DROP := 0.52          # hip origin below the head, local Y
const HIP_YAW_HEAD_WEIGHT := 0.7  # vs. 0.3 hand-implied yaw — damped blend
const HIP_YAW_DAMP := 4.0
const SHOULDER_Y := 0.22         # shoulder height above hip, local
const SHOULDER_X := 0.15         # shoulder half-width
const UPPER_ARM_LEN := 0.27
const FOREARM_LEN := 0.25
const ARM_RADIUS := 0.042
const HAND_RADIUS := 0.052

var mode: int = Mode.SEATED
var tint: Color = Color.WHITE

var _head: MeshInstance3D
var _hip: Node3D
var _torso: MeshInstance3D
var _skirt: MeshInstance3D
var _shoulder_l: Node3D
var _shoulder_r: Node3D
var _arm_l_upper: MeshInstance3D
var _arm_l_fore: MeshInstance3D
var _arm_r_upper: MeshInstance3D
var _arm_r_fore: MeshInstance3D
var _hand_l: MeshInstance3D
var _hand_r: MeshInstance3D

var _hip_yaw := 0.0
var _configured := false

# Interpolation state for update_net() (remote/NPC — see net.gd's
# _apply_crew_head() fix for why a continuous per-frame lerp beats the old
# one-shot-per-packet lerp at 15 Hz, especially for fast hand motion).
var _net_driven := false
var _net_head_target := Transform3D()
var _net_hand_l_target := Transform3D()
var _net_hand_r_target := Transform3D()
var _net_head_cur := Transform3D()
var _net_hand_l_cur := Transform3D()
var _net_hand_r_cur := Transform3D()
var _net_move_flags := 0

func _init() -> void:
	name = "AvatarRig"

## (Re)builds the rig for the given mode/tint. Safe to call again later (e.g.
## a player climbing out of their tank keeps the same AvatarRig instance —
## "one code path preserves player identity across the seated<->on-foot
## transition" — configure() just changes which body parts exist).
func configure(p_mode: int, p_tint: Color) -> void:
	mode = p_mode
	tint = p_tint
	_rebuild()
	_configured = true

## Stable attachment points for props that need to ride along with a hand
## (e.g. an NPC's rifle-shouldered pose) — valid only after configure().
func hand_l_node() -> Node3D:
	return _hand_l

func hand_r_node() -> Node3D:
	return _hand_r

func _rebuild() -> void:
	for c in get_children():
		c.queue_free()
	_head = _mk_sphere(0.135, tint.lightened(0.25))
	_head.name = "Head"
	add_child(_head)
	var visor := MeshInstance3D.new()
	var vb := BoxMesh.new()
	vb.size = Vector3(0.19, 0.085, 0.09)
	visor.mesh = vb
	var vm := StandardMaterial3D.new()
	vm.albedo_color = Color(0.08, 0.08, 0.1)
	vm.roughness = 0.15
	vm.metallic = 0.4
	visor.material_override = vm
	visor.position = Vector3(0, 0.02, -0.105)
	_head.add_child(visor)

	_hip = Node3D.new()
	_hip.name = "Hip"
	add_child(_hip)
	var torso_h := 0.30 if mode == Mode.SEATED else 0.40
	_torso = _mk_cyl(0.13, 0.17, torso_h, tint)
	_torso.position = Vector3(0, -torso_h * 0.5, 0)
	_hip.add_child(_torso)
	if mode == Mode.ON_FOOT:
		# "legs, v1: no per-frame foot IK" — hide them below a short skirt
		# panel, Rec Room's own long-standing default. Revisit only if bare
		# floating-torso reads badly once players are visibly walking.
		_skirt = _mk_cyl(0.21, 0.05, 0.26, tint.darkened(0.15))
		_skirt.position = Vector3(0, -torso_h - 0.10, 0)
		_hip.add_child(_skirt)

	_shoulder_l = Node3D.new()
	_shoulder_l.position = Vector3(-SHOULDER_X, SHOULDER_Y, 0)
	_hip.add_child(_shoulder_l)
	_shoulder_r = Node3D.new()
	_shoulder_r.position = Vector3(SHOULDER_X, SHOULDER_Y, 0)
	_hip.add_child(_shoulder_r)

	_arm_l_upper = _mk_limb(tint.darkened(0.05))
	add_child(_arm_l_upper)
	_arm_l_fore = _mk_limb(tint.lightened(0.05), 0.85)
	add_child(_arm_l_fore)
	_hand_l = _mk_sphere(HAND_RADIUS, tint.lightened(0.3))
	add_child(_hand_l)

	_arm_r_upper = _mk_limb(tint.darkened(0.05))
	add_child(_arm_r_upper)
	_arm_r_fore = _mk_limb(tint.lightened(0.05), 0.85)
	add_child(_arm_r_fore)
	_hand_r = _mk_sphere(HAND_RADIUS, tint.lightened(0.3))
	add_child(_hand_r)

## Local player / live-tracked path — head_t/hand_l_t/hand_r_t are transforms
## in this AvatarRig's parent space (same convention as the old
## _apply_crew_head: "head relative to the tank"), refreshed every frame.
## move_state: {moving, sprinting, climbing, grappling} bools, used for
## lean/reach-up poses. delta is needed for the damped hip-yaw blend.
func update_live(delta: float, head_t: Transform3D, hand_l_t: Transform3D, hand_r_t: Transform3D, move_state: Dictionary = {}) -> void:
	if not _configured:
		return
	_head.global_transform = global_transform * head_t
	var head_yaw := head_t.basis.get_euler().y
	var hands_tangent: Vector3 = hand_r_t.origin - hand_l_t.origin
	hands_tangent.y = 0.0
	var hand_yaw := head_yaw
	if hands_tangent.length() > 0.05:
		hand_yaw = atan2(-hands_tangent.x, -hands_tangent.z) + PI / 2.0
	var want_yaw := lerp_angle(head_yaw, hand_yaw, 1.0 - HIP_YAW_HEAD_WEIGHT)
	_hip_yaw = lerp_angle(_hip_yaw, want_yaw, clampf(HIP_YAW_DAMP * delta, 0.0, 1.0))
	_hip.transform = Transform3D(Basis(Vector3.UP, _hip_yaw), head_t.origin - Vector3(0, HIP_DROP, 0))
	if move_state.get("sprinting", false):
		_hip.rotation.x = lerpf(_hip.rotation.x, deg_to_rad(12), clampf(6.0 * delta, 0, 1))
	elif move_state.get("climbing", false):
		_hip.rotation.x = lerpf(_hip.rotation.x, deg_to_rad(-6), clampf(6.0 * delta, 0, 1))
	else:
		_hip.rotation.x = lerpf(_hip.rotation.x, 0.0, clampf(6.0 * delta, 0, 1))
	_solve_arm(true, hand_l_t.origin)
	_solve_arm(false, hand_r_t.origin)
	_hand_l.global_transform = global_transform * hand_l_t
	_hand_r.global_transform = global_transform * hand_r_t

## Remote player / NPC path — called on RPC/state receipt to set where the
## avatar is heading; the actual pose only updates once _process() below
## calls process_net() every frame, interpolating continuously rather than
## snapping per-packet.
func set_net_target(head_t: Transform3D, hand_l_t: Transform3D, hand_r_t: Transform3D, move_flags: int) -> void:
	if not _net_driven:
		# first packet: snap instead of lerping in from a zeroed pose
		_net_head_cur = head_t
		_net_hand_l_cur = hand_l_t
		_net_hand_r_cur = hand_r_t
	_net_driven = true
	_net_head_target = head_t
	_net_hand_l_target = hand_l_t
	_net_hand_r_target = hand_r_t
	_net_move_flags = move_flags

func _process(delta: float) -> void:
	if _net_driven:
		process_net(delta)

## Continuous per-frame interpolation toward the last set_net_target() call.
func process_net(delta: float, rate: float = 10.0) -> void:
	var t := clampf(rate * delta, 0.0, 1.0)
	_net_head_cur = _net_head_cur.interpolate_with(_net_head_target, t)
	_net_hand_l_cur = _net_hand_l_cur.interpolate_with(_net_hand_l_target, t)
	_net_hand_r_cur = _net_hand_r_cur.interpolate_with(_net_hand_r_target, t)
	var move_state := {
		"moving": (_net_move_flags & 1) != 0,
		"sprinting": (_net_move_flags & 2) != 0,
		"climbing": (_net_move_flags & 4) != 0,
		"grappling": (_net_move_flags & 8) != 0,
	}
	update_live(delta, _net_head_cur, _net_hand_l_cur, _net_hand_r_cur, move_state)

func _solve_arm(is_left: bool, hand_pos: Vector3) -> void:
	var shoulder := _shoulder_l if is_left else _shoulder_r
	var upper: MeshInstance3D = _arm_l_upper if is_left else _arm_r_upper
	var fore: MeshInstance3D = _arm_l_fore if is_left else _arm_r_fore
	var s := shoulder.global_position
	var h := hand_pos
	var d := h - s
	var dist := clampf(d.length(), absf(UPPER_ARM_LEN - FOREARM_LEN) + 0.01, UPPER_ARM_LEN + FOREARM_LEN - 0.01)
	if d.length() < 0.001:
		return
	var dir := d.normalized()
	# law of cosines: angle at the shoulder between the upper-arm bone and
	# the straight shoulder->hand line
	var cos_a := clampf((UPPER_ARM_LEN * UPPER_ARM_LEN + dist * dist - FOREARM_LEN * FOREARM_LEN)
		/ (2.0 * UPPER_ARM_LEN * dist), -1.0, 1.0)
	var shoulder_angle := acos(cos_a)
	# pole hint: elbow bends toward "down and slightly out" (outward = away
	# from body midline) rather than flipping inside-out
	var out := Vector3.LEFT if is_left else Vector3.RIGHT
	var pole := (Vector3.DOWN + out * 0.6).normalized()
	var bend_axis := dir.cross(pole)
	if bend_axis.length() < 0.001:
		bend_axis = dir.cross(Vector3.FORWARD)
	bend_axis = bend_axis.normalized()
	var elbow_dir := dir.rotated(bend_axis, shoulder_angle)
	var elbow := s + elbow_dir * UPPER_ARM_LEN
	upper.transform = _segment_local(upper.get_parent(), s, elbow, UPPER_ARM_LEN)
	fore.transform = _segment_local(fore.get_parent(), elbow, h, FOREARM_LEN)

# Positions/orients a bone mesh (its CylinderMesh runs along local +Y) so it
# spans world-space points a->b, expressed in `relative_to`'s local space
# (upper/forearm meshes are direct children of this AvatarRig, not of the
# shoulder socket, since the socket only defines the *rest* pose — the
# solved elbow position can be anywhere).
func _segment_local(relative_to: Node, a: Vector3, b: Vector3, rest_len: float) -> Transform3D:
	var parent_xform: Transform3D = (relative_to as Node3D).global_transform if relative_to is Node3D else global_transform
	var inv := parent_xform.affine_inverse()
	var la := inv * a
	var lb := inv * b
	var dir := lb - la
	var len := dir.length()
	if len < 0.001:
		return Transform3D(Basis(), la)
	dir /= len
	var up := Vector3.FORWARD
	if absf(dir.dot(up)) > 0.98:
		up = Vector3.RIGHT
	var x := up.cross(dir).normalized()
	var z := dir.cross(x).normalized()
	var basis := Basis(x, dir, z).scaled(Vector3(1, len / rest_len, 1))
	return Transform3D(basis, (la + lb) * 0.5)

func _mk_sphere(radius: float, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = 10
	sm.rings = 6
	mi.mesh = sm
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.5
	mi.material_override = m
	return mi

func _mk_cyl(top_r: float, bottom_r: float, height: float, col: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = top_r
	cm.bottom_radius = bottom_r
	cm.height = height
	cm.radial_segments = 10
	mi.mesh = cm
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.6
	mi.material_override = m
	return mi

func _mk_limb(col: Color, radius_scale: float = 1.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = ARM_RADIUS * radius_scale
	cm.bottom_radius = ARM_RADIUS * radius_scale * 0.85
	cm.height = 1.0   # rescaled per-frame by _segment_local()
	cm.radial_segments = 8
	mi.mesh = cm
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.6
	mi.material_override = m
	return mi

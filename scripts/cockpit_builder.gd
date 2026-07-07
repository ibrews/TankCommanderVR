# Builds the tank interior: a one-man turret basket inspired by a T-72 gunner
# station (centerline gun, crew seated left of the breech) crossed with a
# driver's tiller station. All static geometry merges into ONE mesh (one draw
# call, double-sided). Interactive controls are VRControl instances.
#
# Cockpit space = turret space. Seat faces -Z. Design eye: (-0.28, 0.30, 0.30).
class_name CockpitBuilder
extends Object

const EYE := Vector3(-0.28, 0.33, 0.30)
const STEEL := Color(0.36, 0.40, 0.33)      # military interior green, kept dark (no AO on Mobile)
const STEEL_DARK := Color(0.22, 0.24, 0.21)
const FLOOR_COL := Color(0.13, 0.13, 0.14)
const SEAT_COL := Color(0.24, 0.20, 0.15)
const BRASS := Color(0.72, 0.58, 0.28)

# Wall extents
const X0 := -0.78
const X1 := 0.58
const Z0 := -0.58   # front wall
const Z1 := 0.58    # rear wall
const YF := -1.10   # basket floor
const YR := 0.72    # roof

static func build(parent: Node3D) -> Dictionary:
	var out := {"controls": {}, "needles": {}, "lamps": {}, "labels": {}}
	# Declutch: an extra hinge between the turret and the whole crew basket
	# (walls/seat/tillers/grip — everything below). Identity by default, so
	# nothing about today's geometry/positions changes. player_tank.gd drives
	# its rotation.y each frame: 0 while gunner-seated (basket follows the
	# turret exactly, same as this cockpit has ALWAYS behaved — "cockpit
	# space = turret space" per the file header), or -turret.rotation.y while
	# driver-seated (cancels the turret's spin so the driver's whole basket,
	# camera included since seat_anchor lives inside it, stays hull-fixed).
	# Camera+controls both live under this one node, so nothing drifts out of
	# hand-reach as it rotates — Alex's gunner-seat ask (2026-07-06): "swap to
	# a gunner position where you physically steer/aim the turret and your
	# first-person view yaws with it," without the driver's view spinning
	# along whenever someone else aims. Known trade-off: the gun's own breech
	# (mounted on gun_pivot/recoil, a sibling of this node under `turret`, not
	# a child of it) still visually follows the true turret rotation — so
	# while declutched (driver-seated) during active aiming, the breech prop
	# can visually drift relative to these now-static walls. Cosmetic only;
	# a real hull-fixed driver's compartment (separate geometry, no shared
	# room with the gun at all) would remove it but is real added art scope.
	var declutch := Node3D.new()
	declutch.name = "SeatDeclutch"
	parent.add_child(declutch)
	out["declutch"] = declutch

	var root := Node3D.new()
	root.name = "Cockpit"
	declutch.add_child(root)
	out["root"] = root

	_build_static(root)
	_build_controls(root, out)
	_build_panel(root, out)
	_build_extra(root, out)
	_build_lighting(root, out)
	set_interior_layer(root)

	var seat_anchor := Node3D.new()
	seat_anchor.name = "SeatAnchor"
	seat_anchor.position = Vector3(EYE.x, -0.55, EYE.z)
	root.add_child(seat_anchor)
	out["seat_anchor"] = seat_anchor
	out["eye_local"] = Vector3(0, EYE.y + 0.55, 0)  # eye relative to seat anchor
	return out

# ------------------------------------------------------------------ static shell
# The whole interior renders on layer 2, which the sun's cull mask excludes —
# a closed steel room must not be lit by a shadowless directional light.
static func set_interior_layer(node: Node) -> void:
	if node is VisualInstance3D:
		node.layers = 2
	for c in node.get_children():
		set_interior_layer(c)

static func _build_static(root: Node3D) -> void:
	var st := MeshKit.begin()
	var w := 0.035  # wall thickness

	# floor + seat platform
	MeshKit.box(st, Transform3D(Basis(), Vector3((X0 + X1) / 2, YF, (Z0 + Z1) / 2)), Vector3(X1 - X0, 0.04, Z1 - Z0), FLOOR_COL)
	# seat: pan, back, headrest
	MeshKit.box(st, Transform3D(Basis(), Vector3(EYE.x, -0.58, EYE.z + 0.06)), Vector3(0.46, 0.07, 0.42), SEAT_COL)
	MeshKit.box(st, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-8)), Vector3(EYE.x, -0.28, EYE.z + 0.30)), Vector3(0.46, 0.55, 0.08), SEAT_COL)
	MeshKit.box(st, Transform3D(Basis(), Vector3(EYE.x, -0.86, EYE.z + 0.02)), Vector3(0.36, 0.5, 0.3), STEEL_DARK)

	# ---- front wall with 3 vision-slit gaps (eye sits just above slit center
	# so the natural sightline through the periscopes is slightly downward)
	# Widened 0.15m -> 0.34m (v0.6.13's release note claimed this was done;
	# the code never actually changed — Alex: "still no front view out of
	# the tank" was literally true). Eye y=0.33 sits just above band center.
	var slit_y0 := 0.16
	var slit_y1 := 0.50
	# below band
	MeshKit.box(st, Transform3D(Basis(), Vector3((X0 + X1) / 2, (YF + slit_y0) / 2, Z0)), Vector3(X1 - X0, slit_y0 - YF, w), STEEL)
	# above band
	MeshKit.box(st, Transform3D(Basis(), Vector3((X0 + X1) / 2, (slit_y1 + YR) / 2, Z0)), Vector3(X1 - X0, YR - slit_y1, w), STEEL)
	# columns between slits: left+center gaps merged into one wide driver's
	# window [-0.71,-0.06] (eye x=-0.28 centers on it), right gap [0.00,0.20]
	var band_y := (slit_y0 + slit_y1) / 2.0
	var band_h := slit_y1 - slit_y0
	for seg in [[X0, -0.71], [-0.06, 0.00], [0.20, X1]]:
		var cx: float = (seg[0] + seg[1]) / 2.0
		var cw: float = seg[1] - seg[0]
		if cw > 0.005:
			MeshKit.box(st, Transform3D(Basis(), Vector3(cx, band_y, Z0)), Vector3(cw, band_h, w), STEEL)
	# periscope housings (protrude out through turret front armor)
	for slit in [[-0.71, -0.06], [0.00, 0.20]]:
		var cx: float = (slit[0] + slit[1]) / 2.0
		var cw: float = slit[1] - slit[0]
		var tunnel_len := 0.28
		var zc: float = Z0 - tunnel_len / 2.0
		MeshKit.box(st, Transform3D(Basis(), Vector3(cx, slit_y1 + 0.012, zc)), Vector3(cw + 0.05, 0.025, tunnel_len), STEEL_DARK)
		MeshKit.box(st, Transform3D(Basis(), Vector3(cx, slit_y0 - 0.012, zc)), Vector3(cw + 0.05, 0.025, tunnel_len), STEEL_DARK)
		MeshKit.box(st, Transform3D(Basis(), Vector3(cx - cw / 2 - 0.012, band_y, zc)), Vector3(0.025, band_h + 0.05, tunnel_len), STEEL_DARK)
		MeshKit.box(st, Transform3D(Basis(), Vector3(cx + cw / 2 + 0.012, band_y, zc)), Vector3(0.025, band_h + 0.05, tunnel_len), STEEL_DARK)

	# ---- side walls with one small slit each. Deliberately NOT the same
	# widened band as the front wall -- a render-test screenshot after
	# widening the shared band_y/band_h showed a large, ugly dark slab
	# filling a third of the forward view: the side slits shared those
	# same variables, so widening the front (the actual reported problem)
	# also blew the side windows open to ~4x their area, exposing nearby
	# exterior hull geometry that was never visible (or a problem) through
	# the old narrow side slit. Side windows keep the original band size.
	var side_band_y := (0.24 + 0.39) / 2.0
	var side_band_h := 0.39 - 0.24
	var side_slit_y0 := 0.24
	var side_slit_y1 := 0.39
	for side in [[X0, 1.0], [X1, -1.0]]:
		var wx: float = side[0]
		# front-of-slit and rear-of-slit wall parts (slit z -0.15..0.10)
		MeshKit.box(st, Transform3D(Basis(), Vector3(wx, side_band_y, (Z0 + -0.15) / 2)), Vector3(w, side_band_h, -0.15 - Z0), STEEL)
		MeshKit.box(st, Transform3D(Basis(), Vector3(wx, side_band_y, (0.10 + Z1) / 2)), Vector3(w, side_band_h, Z1 - 0.10), STEEL)
		MeshKit.box(st, Transform3D(Basis(), Vector3(wx, (YF + side_slit_y0) / 2, 0)), Vector3(w, side_slit_y0 - YF, Z1 - Z0), STEEL)
		MeshKit.box(st, Transform3D(Basis(), Vector3(wx, (side_slit_y1 + YR) / 2, 0)), Vector3(w, YR - side_slit_y1, Z1 - Z0), STEEL)
		# housing
		var sx: float = wx + side[1] * -0.15
		MeshKit.box(st, Transform3D(Basis(), Vector3(sx + side[1] * 0.15, side_slit_y1 + 0.012, -0.025)), Vector3(0.3, 0.025, 0.30), STEEL_DARK)
		MeshKit.box(st, Transform3D(Basis(), Vector3(sx + side[1] * 0.15, side_slit_y0 - 0.012, -0.025)), Vector3(0.3, 0.025, 0.30), STEEL_DARK)
		MeshKit.box(st, Transform3D(Basis(), Vector3(sx + side[1] * 0.15, side_band_y, -0.165)), Vector3(0.3, side_band_h + 0.05, 0.025), STEEL_DARK)
		MeshKit.box(st, Transform3D(Basis(), Vector3(sx + side[1] * 0.15, side_band_y, 0.115)), Vector3(0.3, side_band_h + 0.05, 0.025), STEEL_DARK)

	# rear wall + roof
	MeshKit.box(st, Transform3D(Basis(), Vector3((X0 + X1) / 2, (YF + YR) / 2, Z1)), Vector3(X1 - X0, YR - YF, w), STEEL)
	MeshKit.box(st, Transform3D(Basis(), Vector3((X0 + X1) / 2, YR, (Z0 + Z1) / 2)), Vector3(X1 - X0, w, Z1 - Z0), STEEL)
	# hatch ring detail on roof above seat
	MeshKit.cyl(st, Transform3D(Basis(), Vector3(EYE.x, YR - 0.03, EYE.z)), 0.30, 0.30, 0.03, 12, STEEL_DARK, false, false)
	# restart-lever mounting bracket — the lever itself hangs from this exact
	# roof point (see `restart` in _build_controls()) with no visible anchor
	# otherwise, reading as a bare handle floating in space. Small hinge
	# plate + eyebolt ring, same idea as the hatch ring above but sized for
	# a hand lever rather than a hatch.
	MeshKit.box(st, Transform3D(Basis(), Vector3(EYE.x - 0.33, YR - 0.015, 0.12)), Vector3(0.08, 0.03, 0.08), STEEL_DARK)
	MeshKit.cyl(st, Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(EYE.x - 0.33, YR - 0.045, 0.12)), 0.018, 0.018, 0.03, 8, STEEL_DARK)

	# ---- wall dressing: a fighting compartment is BUSY — bare walls read as
	# unfinished geometry in-headset. Same merged mesh, zero extra draw calls.
	# rear wall right: shell ready-rack (backplate, two rows of brass, straps)
	MeshKit.box(st, Transform3D(Basis(), Vector3(0.26, 0.02, Z1 - 0.055)), Vector3(0.52, 0.66, 0.045), STEEL_DARK)
	for row in 2:
		for i in 4:
			MeshKit.cyl(st, Transform3D(Basis(Vector3.RIGHT, PI / 2),
				Vector3(0.08 + i * 0.12, 0.24 - row * 0.44, Z1 - 0.25)), 0.034, 0.043, 0.34, 6, BRASS)
	for i in 2:
		MeshKit.box(st, Transform3D(Basis(), Vector3(0.26, 0.24 - i * 0.44, Z1 - 0.28)), Vector3(0.52, 0.03, 0.05), STEEL)
	# rear wall left: first-aid box (white, red cross) + canvas stowage sacks
	MeshKit.box(st, Transform3D(Basis(), Vector3(-0.52, 0.34, Z1 - 0.08)), Vector3(0.22, 0.16, 0.10), Color(0.88, 0.88, 0.86))
	MeshKit.box(st, Transform3D(Basis(), Vector3(-0.52, 0.34, Z1 - 0.137)), Vector3(0.10, 0.03, 0.012), Color(0.75, 0.12, 0.10))
	MeshKit.box(st, Transform3D(Basis(), Vector3(-0.52, 0.34, Z1 - 0.137)), Vector3(0.03, 0.10, 0.012), Color(0.75, 0.12, 0.10))
	MeshKit.box(st, Transform3D(Basis(Vector3.UP, 0.2), Vector3(-0.60, -0.02, Z1 - 0.12)), Vector3(0.22, 0.28, 0.14), Color(0.45, 0.40, 0.28))
	MeshKit.box(st, Transform3D(Basis(Vector3.UP, -0.15), Vector3(-0.34, -0.06, Z1 - 0.10)), Vector3(0.18, 0.20, 0.12), Color(0.40, 0.36, 0.26))
	# left wall: overhead pipe run with junction boxes
	MeshKit.cyl(st, Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(X0 + 0.05, 0.55, 0.0)), 0.022, 0.022, 1.05, 6, STEEL_DARK)
	for zc in [-0.30, 0.10, 0.40]:
		MeshKit.box(st, Transform3D(Basis(), Vector3(X0 + 0.05, 0.55, zc)), Vector3(0.07, 0.10, 0.09), STEEL_DARK)
	# right wall: fire extinguisher on a bracket + wire conduit
	MeshKit.cyl(st, Transform3D(Basis(), Vector3(X1 - 0.08, 0.06, 0.42)), 0.055, 0.055, 0.30, 8, Color(0.72, 0.14, 0.10))
	MeshKit.cyl(st, Transform3D(Basis(), Vector3(X1 - 0.08, 0.245, 0.42)), 0.02, 0.02, 0.07, 6, STEEL_DARK)
	MeshKit.box(st, Transform3D(Basis(), Vector3(X1 - 0.045, 0.08, 0.42)), Vector3(0.02, 0.06, 0.12), STEEL_DARK)
	MeshKit.cyl(st, Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(X1 - 0.04, 0.58, -0.05)), 0.016, 0.016, 0.9, 6, STEEL_DARK)
	# roof stiffener ribs (forward of the hatch ring)
	for zc in [-0.35, -0.02]:
		MeshKit.box(st, Transform3D(Basis(), Vector3((X0 + X1) / 2, YR - 0.035, zc)), Vector3(X1 - X0, 0.05, 0.06), STEEL_DARK)
	# floor: ammo cans stacked in the rear-left corner
	MeshKit.box(st, Transform3D(Basis(Vector3.UP, 0.3), Vector3(-0.64, YF + 0.09, 0.40)), Vector3(0.16, 0.14, 0.24), Color(0.30, 0.34, 0.26))
	MeshKit.box(st, Transform3D(Basis(Vector3.UP, -0.1), Vector3(-0.64, YF + 0.23, 0.36)), Vector3(0.14, 0.12, 0.20), Color(0.33, 0.36, 0.28))

	# ---- consoles
	# front panel slab (gauges mount here), tilted toward player
	MeshKit.box(st, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-18)), Vector3(EYE.x, 0.02, Z0 + 0.10)), Vector3(0.62, 0.34, 0.05), STEEL_DARK)
	# left console (rockets)
	MeshKit.box(st, Transform3D(Basis(), Vector3(X0 + 0.17, -0.18, -0.05)), Vector3(0.30, 0.06, 0.55), STEEL_DARK)
	MeshKit.box(st, Transform3D(Basis(), Vector3(X0 + 0.17, -0.50, -0.05)), Vector3(0.26, 0.58, 0.50), STEEL)
	# right console pedestal (turret grip) — Alex, live headset: "a big
	# metal box blocking half the tank." Confirmed via debug-facing render
	# (2026-07-03) NOT a winding bug (correctly front-facing) — it's a
	# plain untextured box close enough to the eye (was 0.5 tall, top edge
	# near EYE.y=0.33) to dominate the view at typical FOV. Shrunk and
	# pulled down/right/back so its top sits well below the sightline.
	# Original box's near face sat only 0.17m from the eye (Z=-0.02, half-
	# depth 0.15, eye Z=0.30) — close enough on its own to dominate the
	# frame regardless of the box's absolute size. Pushed forward and
	# thinned in depth so its near face clears the eye by ~0.35m.
	MeshKit.box(st, Transform3D(Basis(), Vector3(0.10, -0.30, -0.16)), Vector3(0.20, 0.34, 0.20), STEEL)
	# tiller floor mounts
	for tx in [EYE.x - 0.20, EYE.x + 0.20]:
		MeshKit.box(st, Transform3D(Basis(), Vector3(tx, -0.72, -0.16)), Vector3(0.09, 0.10, 0.16), STEEL_DARK)

	# ---- ammo rack (brass shells) on rear-right wall, decor
	for i in 5:
		MeshKit.cyl(st, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(90)), Vector3(0.34, -0.25 - i * 0.13, Z1 - 0.17)), 0.055, 0.055, 0.62, 8, BRASS)
		MeshKit.cyl(st, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(90)), Vector3(0.34, -0.25 - i * 0.13, Z1 - 0.52)), 0.055, 0.02, 0.10, 8, Color(0.5, 0.48, 0.44))
	MeshKit.box(st, Transform3D(Basis(), Vector3(0.34, -0.5, Z1 - 0.30)), Vector3(0.03, 0.75, 0.5), STEEL_DARK)

	# greebles: junction boxes, conduit
	MeshKit.box(st, Transform3D(Basis(), Vector3(X0 + 0.10, 0.45, 0.25)), Vector3(0.14, 0.20, 0.10), STEEL_DARK)
	MeshKit.cyl(st, Transform3D(Basis(Vector3.FORWARD, deg_to_rad(90)), Vector3((X0 + X1) / 2, YR - 0.09, 0.35)), 0.02, 0.02, X1 - X0 - 0.1, 6, STEEL_DARK)

	var mesh := MeshInstance3D.new()
	var mat := MeshKit.mat_tex("res://assets/tex/metal.png", true, 0.85)
	mat = mat.duplicate()
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.uv1_scale = Vector3(3.0, 3.0, 1.0)
	mesh.mesh = MeshKit.commit(st, mat)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mesh)

	# Periscope glass pane REMOVED (was here 2026-07-03, dropped 2026-07-04).
	# Alex reported "a white plane on top of the viewer holes out the tank"
	# earlier the same day; the fix at the time (dropping cull_disabled,
	# since cull_disabled + transparency is a documented Godot Mobile/
	# Compatibility-renderer bug) did NOT actually resolve it — same
	# complaint came back verbatim on the next headset pass ("something
	# white blocking both of the windows out of the tank"). Rather than
	# chase Mobile-renderer alpha-blend correctness a third time, removed
	# the separate glass mesh entirely: the periscope slit is just an open
	# view now, same as a real periscope reads visually anyway, and it
	# permanently eliminates this whole recurring bug class instead of
	# tuning parameters against it again.

# ------------------------------------------------------------------ controls
static func _build_controls(root: Node3D, out: Dictionary) -> void:
	var c: Dictionary = out["controls"]

	# driving tillers — knee height in front of seat
	var tiller_l := VRControl.Lever.create(0.34, Color(0.15, 0.15, 0.16), 32.0, true)
	tiller_l.position = Vector3(EYE.x - 0.20, -0.66, -0.16)
	root.add_child(tiller_l)
	c["tiller_l"] = tiller_l
	var tiller_r := VRControl.Lever.create(0.34, Color(0.15, 0.15, 0.16), 32.0, true)
	tiller_r.position = Vector3(EYE.x + 0.20, -0.66, -0.16)
	root.add_child(tiller_r)
	c["tiller_r"] = tiller_r

	# turret grip on right pedestal
	var grip := VRControl.TwoAxisGrip.create()
	grip.position = Vector3(0.10, -0.07, -0.02)
	root.add_child(grip)
	c["grip"] = grip

	# rocket console (left): safety cover + arm switch under it + fire button
	var cover := VRControl.SafetyCover.create()
	cover.position = Vector3(X0 + 0.11, -0.145, -0.18)
	root.add_child(cover)
	c["rocket_cover"] = cover
	var arm := VRControl.ToggleSwitch.create(Color(0.9, 0.25, 0.2))
	arm.position = Vector3(X0 + 0.11, -0.145, -0.18)
	arm.enabled = false
	root.add_child(arm)
	c["rocket_arm"] = arm
	var rfire := VRControl.PushButton.create(Color(0.85, 0.12, 0.1), 0.036)
	rfire.position = Vector3(X0 + 0.11, -0.145, 0.02)
	root.add_child(rfire)
	c["rocket_fire"] = rfire

	# battery, starter, lights on left console rear section
	var battery := VRControl.ToggleSwitch.create()
	battery.position = Vector3(X0 + 0.22, -0.145, 0.16)
	root.add_child(battery)
	c["battery"] = battery
	var starter := VRControl.PushButton.create(Color(0.2, 0.5, 0.2), 0.03)
	starter.position = Vector3(X0 + 0.13, -0.145, 0.16)
	root.add_child(starter)
	c["starter"] = starter
	var lights := VRControl.ToggleSwitch.create(Color(0.9, 0.85, 0.5))
	lights.position = Vector3(X0 + 0.22, -0.145, 0.28)
	root.add_child(lights)
	c["lights"] = lights

	# restart handle — roof, yellow/black, only enabled at game over
	var restart := VRControl.Lever.create(0.26, Color(0.95, 0.8, 0.1), 50.0, false)
	restart.position = Vector3(EYE.x - 0.33, YR - 0.05, 0.12)
	restart.rotation.z = deg_to_rad(180)  # hangs down from roof
	restart.enabled = false
	root.add_child(restart)
	c["restart"] = restart

	# hatch lever — hangs from the roof ring (see the hatch-ring detail in
	# _build_static), pull down to bail out and go on-foot mid-mission
	var hatch := VRControl.Lever.create(0.20, Color(0.85, 0.72, 0.15), 46.0, false)
	hatch.position = Vector3(EYE.x, YR - 0.05, EYE.z)
	hatch.rotation.z = deg_to_rad(180)
	root.add_child(hatch)
	c["hatch"] = hatch
	_label(root, "HATCH", Vector3(EYE.x + 0.20, YR - 0.14, EYE.z), 90, 12)

	# console labels — flat on the console, rotated to read naturally from the seat
	_label(root, "BATTERY", Vector3(X0 + 0.22, -0.135, 0.115), -90, 20, 90)
	_label(root, "STARTER", Vector3(X0 + 0.13, -0.135, 0.115), -90, 20, 90)
	_label(root, "LIGHTS", Vector3(X0 + 0.22, -0.135, 0.235), -90, 20, 90)
	_label(root, "ROCKETS ARM", Vector3(X0 + 0.11, -0.135, -0.255), -90, 20, 90)
	_label(root, "ROCKET FIRE", Vector3(X0 + 0.11, -0.135, -0.05), -90, 20, 90)
	_label(root, "TURRET", Vector3(0.10, -0.135, 0.145), -90, 20, 90)

static func _label(root: Node3D, text: String, pos: Vector3, pitch_deg := 0.0, size := 20, yaw_deg := 0.0) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size * 4
	l.pixel_size = 0.0002
	l.modulate = Color(0.92, 0.94, 0.90)
	l.outline_size = 0
	l.position = pos
	l.rotation_degrees = Vector3(pitch_deg, yaw_deg, 0)
	root.add_child(l)
	return l

# ------------------------------------------------------------------ instrument panel
static func _build_panel(root: Node3D, out: Dictionary) -> void:
	# gauges sit on the tilted front slab: local frame tilted 18 deg
	var slab := Node3D.new()
	# sits just proud of the static slab face (static slab center Z0+0.10, half-depth 0.025)
	slab.position = Vector3(EYE.x, 0.02, Z0 + 0.13)
	slab.rotation.x = deg_to_rad(-18)
	root.add_child(slab)

	var gauges := [
		["gauge_speed", Vector2(-0.22, 0.075), "speed"],
		["gauge_rpm", Vector2(-0.075, 0.075), "rpm"],
		["gauge_fuel", Vector2(0.075, 0.075), "fuel"],
		["gauge_temp", Vector2(0.22, 0.075), "temp"],
	]
	for g in gauges:
		var face := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(0.11, 0.11)
		face.mesh = qm
		var m := StandardMaterial3D.new()
		m.albedo_texture = load("res://assets/tex/%s.png" % g[0])
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		face.material_override = m
		face.position = Vector3(g[1].x, g[1].y, 0.002)
		slab.add_child(face)
		# needle
		var pivot := Node3D.new()
		pivot.position = Vector3(g[1].x, g[1].y, 0.006)
		slab.add_child(pivot)
		var nd := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.0045, 0.042, 0.002)
		nd.mesh = bm
		nd.position = Vector3(0, 0.017, 0)
		var nm := StandardMaterial3D.new()
		nm.albedo_color = Color(0.95, 0.4, 0.2)
		nm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		nd.material_override = nm
		pivot.add_child(nd)
		out["needles"][g[2]] = pivot

	# hull azimuth dial (shows hull heading relative to turret)
	var az_pivot := Node3D.new()
	az_pivot.position = Vector3(0.0, -0.065, 0.006)
	slab.add_child(az_pivot)
	var az := MeshInstance3D.new()
	var am := BoxMesh.new()
	am.size = Vector3(0.008, 0.05, 0.002)
	az.mesh = am
	az.position = Vector3(0, 0.012, 0)
	var azm := StandardMaterial3D.new()
	azm.albedo_color = Color(0.3, 0.9, 0.4)
	azm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	az.material_override = azm
	az_pivot.add_child(az)
	var az_face := MeshInstance3D.new()
	var acm := CylinderMesh.new()
	acm.top_radius = 0.038
	acm.bottom_radius = 0.038
	acm.height = 0.004
	acm.radial_segments = 16
	az_face.mesh = acm
	az_face.rotation.x = deg_to_rad(90)
	az_face.position = Vector3(0, -0.065, 0.002)
	var afm := StandardMaterial3D.new()
	afm.albedo_color = Color(0.1, 0.12, 0.1)
	az_face.material_override = afm
	slab.add_child(az_face)
	out["needles"]["azimuth"] = az_pivot
	_label(slab, "HULL", Vector3(0.0, -0.115, 0.004), 0, 14)

	# warning lamps row
	var lamp_defs := [["low_hull", Color(1, 0.15, 0.1)], ["reload", Color(1, 0.6, 0.1)], ["armed", Color(1, 0.2, 0.15)], ["engine", Color(0.2, 0.9, 0.3)]]
	for i in lamp_defs.size():
		var lm := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.011
		cm.bottom_radius = 0.013
		cm.height = 0.008
		cm.radial_segments = 10
		lm.mesh = cm
		lm.rotation.x = deg_to_rad(90)
		lm.position = Vector3(-0.14 + i * 0.055, -0.065, 0.004)
		var mm := StandardMaterial3D.new()
		mm.albedo_color = lamp_defs[i][1] * 0.22
		mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		lm.material_override = mm
		slab.add_child(lm)
		out["lamps"][lamp_defs[i][0]] = {"mat": mm, "color": lamp_defs[i][1]}
	_label(slab, "HULL  LOAD  ARM  ENG", Vector3(-0.065, -0.105, 0.004), 0, 11)

	# ammo counters + score plaque above slits
	var ammo := _label(root, "AP 40", Vector3(0.30, 0.18, 0.35), 0, 26)
	ammo.rotation.y = deg_to_rad(-90)
	out["labels"]["ammo"] = ammo
	var rockets := _label(root, "RKT 12", Vector3(X0 + 0.11, -0.135, -0.34), -90, 18, 90)
	out["labels"]["rockets"] = rockets
	var plaque := _label(root, "WAVE 1    SCORE 0", Vector3(EYE.x, 0.50, Z0 + 0.02), 0, 30)
	out["labels"]["plaque"] = plaque
	var hint := _label(root, "", Vector3(EYE.x, 0.445, Z0 + 0.02), 0, 16)
	hint.modulate = Color(1.0, 0.8, 0.35)
	out["labels"]["hint"] = hint

# ------------------------------------------------------------------ extra console detail (v2)
# Modeled after a real APC driver's station: gear quadrant, guarded switches,
# radio set with working knobs, thermal display, breaker rows, placards.
static func _build_extra(root: Node3D, out: Dictionary) -> void:
	var c: Dictionary = out["controls"]

	# gear quadrant — front of the right pedestal: R / N / D
	var gear := VRControl.Lever.create(0.17, Color(0.08, 0.08, 0.08), 26.0, false)
	gear.position = Vector3(0.10, -0.10, -0.22)
	root.add_child(gear)
	c["gear"] = gear
	_label(root, "R", Vector3(0.155, -0.06, -0.28), 0, 13).rotation.y = deg_to_rad(0)
	_label(root, "N", Vector3(0.155, -0.06, -0.22), 0, 13)
	_label(root, "D", Vector3(0.155, -0.06, -0.16), 0, 13)
	_label(root, "GEAR", Vector3(0.10, -0.135, -0.30), -90, 16, 90)

	# fuel pump — guarded switch beside battery (part of the start ritual)
	var fuel_cover := VRControl.SafetyCover.create()
	fuel_cover.position = Vector3(X0 + 0.13, -0.145, 0.28)
	root.add_child(fuel_cover)
	c["fuel_cover"] = fuel_cover
	var fuel := VRControl.ToggleSwitch.create(Color(0.9, 0.7, 0.2))
	fuel.position = Vector3(X0 + 0.13, -0.145, 0.28)
	fuel.enabled = false
	root.add_child(fuel)
	c["fuel_pump"] = fuel
	fuel_cover.toggled_on.connect(func(open): fuel.enabled = open)
	_label(root, "FUEL PUMP", Vector3(X0 + 0.13, -0.135, 0.345), -90, 14, 90)

	# radio set — left wall above console: box, two knobs (volume works!)
	var rst := MeshKit.begin()
	MeshKit.box(rst, Transform3D(Basis(), Vector3(0, 0, -0.045)), Vector3(0.26, 0.16, 0.09), Color(0.30, 0.33, 0.28))
	MeshKit.box(rst, Transform3D(Basis(), Vector3(0, 0.045, 0.002)), Vector3(0.2, 0.03, 0.004), Color(0.1, 0.1, 0.1))
	var radio := MeshInstance3D.new()
	radio.mesh = MeshKit.commit(rst, MeshKit.mat_vcol(0.7, 0.2))
	radio.position = Vector3(X0 + 0.045, 0.16, -0.05)
	radio.rotation.y = deg_to_rad(90)
	root.add_child(radio)
	var vol := VRControl.Knob.create()
	vol.position = Vector3(X0 + 0.05, 0.12, -0.11)
	vol.rotation.y = deg_to_rad(90)
	root.add_child(vol)
	c["radio_volume"] = vol
	var chan := VRControl.Knob.create(Color(0.3, 0.15, 0.1))
	chan.detents = 4
	chan.value = 0.0
	chan.position = Vector3(X0 + 0.05, 0.12, 0.01)
	chan.rotation.y = deg_to_rad(90)
	root.add_child(chan)
	c["radio_channel"] = chan
	var rl := _label(root, "R-123 RADIO   VOL      CHAN", Vector3(X0 + 0.052, 0.205, -0.05), 0, 12)
	rl.rotation.y = deg_to_rad(90)
	var station_l := _label(root, "AUTO", Vector3(X0 + 0.052, 0.175, -0.05), 0, 14)
	station_l.rotation.y = deg_to_rad(90)
	station_l.modulate = Color(0.4, 0.95, 0.5)
	out["labels"]["radio_station"] = station_l
	out["radio_node"] = radio

	# thermal display — right wall above the grip: a REAL live camera feed
	# (Alex, 2026-07-06: "would be really cool if we can do that" — this used
	# to be a fixed rock.png texture tinted green, never actually reading the
	# world at all). A SubViewport with its own Camera3D renders the scene;
	# a false-color luminance ramp (unshaded spatial shader, see
	# _make_thermal_shader()) gives it the familiar cold-blue/hot-white FLIR
	# look without any real heat simulation. The camera itself gets
	# reparented to gun_pivot by player_tank.gd (cockpit_builder.gd has no
	# access to the gun rig, which is built separately) so it points wherever
	# the gun is aimed — a genuine sighting aid, not just decoration.
	# Moved rearward (z -0.12 -> 0.20) and down (y 0.18 -> 0.10): the old spot
	# sat squarely inside the side vision-slit's own opening (window gap is
	# z=[-0.15,0.10], band y=[0.24,0.39] -- the display box's y=[0.09,0.27]
	# clipped 0.03 into the bottom of that band, and its z sat mid-window).
	# Alex, 2026-07-07: "the location needs to adjust so it's not interfering
	# with the window."
	const THERMAL_Y := 0.10
	const THERMAL_Z := 0.20
	var tst := MeshKit.begin()
	MeshKit.box(tst, Transform3D(Basis(), Vector3(0, 0, -0.03)), Vector3(0.22, 0.18, 0.06), Color(0.16, 0.17, 0.16))
	var tbox := MeshInstance3D.new()
	tbox.mesh = MeshKit.commit(tst, MeshKit.mat_vcol(0.6, 0.3))
	tbox.position = Vector3(X1 - 0.04, THERMAL_Y, THERMAL_Z)
	tbox.rotation.y = deg_to_rad(-90)
	root.add_child(tbox)

	var thermal_vp := SubViewport.new()
	thermal_vp.size = Vector2i(256, 192)
	thermal_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED  # off until the IR switch is flipped on
	thermal_vp.own_world_3d = false  # shares the main World3D -- sees the same terrain/enemies/vehicles
	root.add_child(thermal_vp)
	var thermal_cam := Camera3D.new()
	thermal_cam.fov = 35.0  # narrow — a sight, not a wide establishing view
	thermal_cam.current = true  # a Camera3D inside a SubViewport still needs
	# this to actually be the one that viewport renders through -- without it
	# the viewport had no active camera at all, so the feed just never
	# updated no matter what render_target_update_mode said. Root cause of
	# "thermal overlay image doesn't change" (Alex, 2026-07-07). Safe to set
	# unconditionally: this camera only ever lives inside its own private
	# SubViewport, so it can't steal "current" from the real seat/rig camera.
	thermal_vp.add_child(thermal_cam)
	out["thermal_cam"] = thermal_cam
	out["thermal_vp"] = thermal_vp

	var screen := MeshInstance3D.new()
	var sq := QuadMesh.new()
	sq.size = Vector2(0.17, 0.13)
	screen.mesh = sq
	var sm := ShaderMaterial.new()
	sm.shader = _make_thermal_shader()
	sm.set_shader_parameter("screen_tex", thermal_vp.get_texture())
	screen.material_override = sm
	screen.position = Vector3(X1 - 0.043, THERMAL_Y, THERMAL_Z)
	screen.rotation.y = deg_to_rad(-90)
	screen.visible = false
	root.add_child(screen)
	out["thermal_screen"] = screen
	var ir := VRControl.ToggleSwitch.create(Color(0.3, 0.8, 0.4))
	ir.position = Vector3(X1 - 0.05, THERMAL_Y - 0.125, THERMAL_Z)
	ir.rotation.z = deg_to_rad(90)
	root.add_child(ir)
	c["ir"] = ir
	ir.toggled_on.connect(func(on):
		screen.visible = on
		thermal_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED)
	var tl := _label(root, "THERMAL", Vector3(X1 - 0.045, THERMAL_Y + 0.185, THERMAL_Z), 0, 13)
	tl.rotation.y = deg_to_rad(-90)

	# MG trigger button beside the turret grip (hands have no A button)
	var mg := VRControl.PushButton.create(Color(0.85, 0.55, 0.1), 0.028)
	mg.position = Vector3(-0.03, -0.07, -0.13)
	root.add_child(mg)
	c["mg_btn"] = mg
	_label(root, "MG", Vector3(-0.03, -0.06, -0.185), -90, 13, 90)

	# seat recalibrate (hands have no Y button)
	var seat_btn := VRControl.PushButton.create(Color(0.4, 0.6, 0.9), 0.026)
	seat_btn.position = Vector3(X0 + 0.13, -0.145, 0.40)
	root.add_child(seat_btn)
	c["seat_btn"] = seat_btn
	_label(root, "SEAT", Vector3(X0 + 0.13, -0.135, 0.455), -90, 12, 90)

	# horn — big button on the left tiller mount (mandatory fun)
	var horn := VRControl.PushButton.create(Color(0.9, 0.75, 0.2), 0.03)
	horn.position = Vector3(EYE.x - 0.20, -0.66, -0.245)
	horn.rotation.x = deg_to_rad(-50)
	root.add_child(horn)
	c["horn"] = horn
	_label(root, "HORN", Vector3(EYE.x - 0.20, -0.60, -0.29), -40, 13)

	# return-to-menu — guarded switch, rear of left console
	var menu_cover := VRControl.SafetyCover.create()
	menu_cover.position = Vector3(X0 + 0.22, -0.145, 0.40)
	root.add_child(menu_cover)
	c["menu_cover"] = menu_cover
	var menu_sw := VRControl.ToggleSwitch.create(Color(0.4, 0.6, 0.9))
	menu_sw.position = Vector3(X0 + 0.22, -0.145, 0.40)
	menu_sw.enabled = false
	root.add_child(menu_sw)
	c["menu_switch"] = menu_sw
	menu_cover.toggled_on.connect(func(open): menu_sw.enabled = open)
	_label(root, "MENU", Vector3(X0 + 0.22, -0.135, 0.455), -90, 13, 90)

	# decor: breaker rows + placards + wiring conduit (single merged mesh)
	var dst := MeshKit.begin()
	for row in 2:
		for i in 6:
			MeshKit.box(dst, Transform3D(Basis(), Vector3(X1 - 0.045, -0.02 - row * 0.06, 0.10 + i * 0.045)),
				Vector3(0.02, 0.035, 0.02), Color(0.12, 0.12, 0.12) if (i + row) % 3 else Color(0.6, 0.15, 0.1))
	MeshKit.box(dst, Transform3D(Basis(), Vector3(X1 - 0.05, 0.02, 0.21)), Vector3(0.015, 0.20, 0.36), Color(0.28, 0.30, 0.27))
	# conduit runs
	MeshKit.cyl(dst, Transform3D(Basis(Vector3.FORWARD, deg_to_rad(90)), Vector3(0, YR - 0.14, -0.25)), 0.015, 0.015, X1 - X0 - 0.2, 6, Color(0.1, 0.1, 0.1))
	MeshKit.cyl(dst, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(14)), Vector3(X0 + 0.06, 0.35, 0.30)), 0.018, 0.018, 0.5, 6, Color(0.1, 0.1, 0.1))
	MeshKit.box(dst, Transform3D(Basis(), Vector3(X0 + 0.05, 0.42, -0.30)), Vector3(0.08, 0.12, 0.16), Color(0.25, 0.27, 0.24))
	var dm := MeshInstance3D.new()
	dm.mesh = MeshKit.commit(dst, MeshKit.mat_vcol(0.85, 0.1))
	root.add_child(dm)
	_label(root, "CAUTION\nTRAVERSE", Vector3(0.10, 0.10, -0.35), 0, 10)
	var pl2 := _label(root, "MAX 40 KMH", Vector3(EYE.x + 0.24, 0.13, Z0 + 0.03), 0, 10)
	pl2.modulate = Color(0.9, 0.8, 0.5)

# False-color FLIR-style ramp over the thermal SubViewport's own render --
# luminance in, cold-blue/hot-white out. No real heat simulation (nothing in
# this game tracks temperature), just the recognizable video-game "thermal
# camera" look layered over an otherwise-normal render of the same world.
static func _make_thermal_shader() -> Shader:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, cull_back;
uniform sampler2D screen_tex : source_color;

void fragment() {
	vec4 src = texture(screen_tex, UV);
	float lum = dot(src.rgb, vec3(0.299, 0.587, 0.114));
	vec3 c;
	if (lum < 0.2) {
		c = mix(vec3(0.02, 0.0, 0.08), vec3(0.1, 0.0, 0.35), lum / 0.2);
	} else if (lum < 0.4) {
		c = mix(vec3(0.1, 0.0, 0.35), vec3(0.0, 0.3, 0.6), (lum - 0.2) / 0.2);
	} else if (lum < 0.6) {
		c = mix(vec3(0.0, 0.3, 0.6), vec3(0.9, 0.85, 0.1), (lum - 0.4) / 0.2);
	} else if (lum < 0.8) {
		c = mix(vec3(0.9, 0.85, 0.1), vec3(0.95, 0.25, 0.05), (lum - 0.6) / 0.2);
	} else {
		c = mix(vec3(0.95, 0.25, 0.05), vec3(1.0, 1.0, 1.0), (lum - 0.8) / 0.2);
	}
	ALBEDO = c;
}
"""
	return sh

# ------------------------------------------------------------------ lighting
static func _build_lighting(root: Node3D, out: Dictionary) -> void:
	var dome := OmniLight3D.new()
	dome.position = Vector3(EYE.x + 0.3, YR - 0.12, 0.1)
	dome.light_color = Color(1.0, 0.82, 0.58)
	dome.omni_range = 1.7
	dome.omni_attenuation = 1.4
	dome.light_energy = 0.0   # off until battery on
	dome.shadow_enabled = false
	root.add_child(dome)
	out["dome_light"] = dome
	var bulb := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.025
	sm.height = 0.05
	sm.radial_segments = 8
	sm.rings = 4
	bulb.mesh = sm
	bulb.position = dome.position + Vector3(0, 0.03, 0)
	var bm := StandardMaterial3D.new()
	bm.albedo_color = Color(0.9, 0.85, 0.7)
	bm.emission_enabled = true
	bm.emission = Color(1.0, 0.9, 0.7)
	bm.emission_energy_multiplier = 0.0
	bulb.material_override = bm
	root.add_child(bulb)
	out["dome_bulb"] = bm

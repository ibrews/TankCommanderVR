# Builds the tank interior: a one-man turret basket inspired by a T-72 gunner
# station (centerline gun, crew seated left of the breech) crossed with a
# driver's tiller station. All static geometry merges into ONE mesh (one draw
# call, double-sided). Interactive controls are VRControl instances.
#
# Cockpit space = turret space. Seat faces -Z. Design eye: (-0.28, 0.30, 0.30).
class_name CockpitBuilder
extends Object

const EYE := Vector3(-0.28, 0.30, 0.30)
const STEEL := Color(0.62, 0.66, 0.58)      # pale military interior green
const STEEL_DARK := Color(0.42, 0.45, 0.40)
const FLOOR_COL := Color(0.25, 0.25, 0.26)
const SEAT_COL := Color(0.30, 0.26, 0.20)
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
	var root := Node3D.new()
	root.name = "Cockpit"
	parent.add_child(root)
	out["root"] = root

	_build_static(root)
	_build_controls(root, out)
	_build_panel(root, out)
	_build_lighting(root, out)

	var seat_anchor := Node3D.new()
	seat_anchor.name = "SeatAnchor"
	seat_anchor.position = Vector3(EYE.x, -0.55, EYE.z)
	root.add_child(seat_anchor)
	out["seat_anchor"] = seat_anchor
	out["eye_local"] = Vector3(0, EYE.y + 0.55, 0)  # eye relative to seat anchor
	return out

# ------------------------------------------------------------------ static shell
static func _build_static(root: Node3D) -> void:
	var st := MeshKit.begin()
	var w := 0.035  # wall thickness

	# floor + seat platform
	MeshKit.box(st, Transform3D(Basis(), Vector3((X0 + X1) / 2, YF, (Z0 + Z1) / 2)), Vector3(X1 - X0, 0.04, Z1 - Z0), FLOOR_COL)
	# seat: pan, back, headrest
	MeshKit.box(st, Transform3D(Basis(), Vector3(EYE.x, -0.58, EYE.z + 0.06)), Vector3(0.46, 0.07, 0.42), SEAT_COL)
	MeshKit.box(st, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-8)), Vector3(EYE.x, -0.28, EYE.z + 0.30)), Vector3(0.46, 0.55, 0.08), SEAT_COL)
	MeshKit.box(st, Transform3D(Basis(), Vector3(EYE.x, -0.86, EYE.z + 0.02)), Vector3(0.36, 0.5, 0.3), STEEL_DARK)

	# ---- front wall with 3 vision-slit gaps at y 0.255..0.385
	var slit_y0 := 0.255
	var slit_y1 := 0.385
	# below band
	MeshKit.box(st, Transform3D(Basis(), Vector3((X0 + X1) / 2, (YF + slit_y0) / 2, Z0)), Vector3(X1 - X0, slit_y0 - YF, w), STEEL)
	# above band
	MeshKit.box(st, Transform3D(Basis(), Vector3((X0 + X1) / 2, (slit_y1 + YR) / 2, Z0)), Vector3(X1 - X0, YR - slit_y1, w), STEEL)
	# columns between slits: gaps at [-0.46,-0.13] (center), [-0.71,-0.51] (left), [0.00,0.20] (right)
	var band_y := (slit_y0 + slit_y1) / 2.0
	var band_h := slit_y1 - slit_y0
	for seg in [[X0, -0.71], [-0.51, -0.46], [-0.13, 0.00], [0.20, X1]]:
		var cx: float = (seg[0] + seg[1]) / 2.0
		var cw: float = seg[1] - seg[0]
		if cw > 0.005:
			MeshKit.box(st, Transform3D(Basis(), Vector3(cx, band_y, Z0)), Vector3(cw, band_h, w), STEEL)
	# periscope housings (protrude out through turret front armor)
	for slit in [[-0.71, -0.51], [-0.46, -0.13], [0.00, 0.20]]:
		var cx: float = (slit[0] + slit[1]) / 2.0
		var cw: float = slit[1] - slit[0]
		var tunnel_len := 0.40
		var zc: float = Z0 - tunnel_len / 2.0
		MeshKit.box(st, Transform3D(Basis(), Vector3(cx, slit_y1 + 0.012, zc)), Vector3(cw + 0.05, 0.025, tunnel_len), STEEL_DARK)
		MeshKit.box(st, Transform3D(Basis(), Vector3(cx, slit_y0 - 0.012, zc)), Vector3(cw + 0.05, 0.025, tunnel_len), STEEL_DARK)
		MeshKit.box(st, Transform3D(Basis(), Vector3(cx - cw / 2 - 0.012, band_y, zc)), Vector3(0.025, band_h + 0.05, tunnel_len), STEEL_DARK)
		MeshKit.box(st, Transform3D(Basis(), Vector3(cx + cw / 2 + 0.012, band_y, zc)), Vector3(0.025, band_h + 0.05, tunnel_len), STEEL_DARK)

	# ---- side walls with one small slit each at same band
	for side in [[X0, 1.0], [X1, -1.0]]:
		var wx: float = side[0]
		# front-of-slit and rear-of-slit wall parts (slit z -0.15..0.10)
		MeshKit.box(st, Transform3D(Basis(), Vector3(wx, band_y, (Z0 + -0.15) / 2)), Vector3(w, band_h, -0.15 - Z0), STEEL)
		MeshKit.box(st, Transform3D(Basis(), Vector3(wx, band_y, (0.10 + Z1) / 2)), Vector3(w, band_h, Z1 - 0.10), STEEL)
		MeshKit.box(st, Transform3D(Basis(), Vector3(wx, (YF + slit_y0) / 2, 0)), Vector3(w, slit_y0 - YF, Z1 - Z0), STEEL)
		MeshKit.box(st, Transform3D(Basis(), Vector3(wx, (slit_y1 + YR) / 2, 0)), Vector3(w, YR - slit_y1, Z1 - Z0), STEEL)
		# housing
		var sx: float = wx + side[1] * -0.15
		MeshKit.box(st, Transform3D(Basis(), Vector3(sx + side[1] * 0.15, slit_y1 + 0.012, -0.025)), Vector3(0.3, 0.025, 0.30), STEEL_DARK)
		MeshKit.box(st, Transform3D(Basis(), Vector3(sx + side[1] * 0.15, slit_y0 - 0.012, -0.025)), Vector3(0.3, 0.025, 0.30), STEEL_DARK)
		MeshKit.box(st, Transform3D(Basis(), Vector3(sx + side[1] * 0.15, band_y, -0.165)), Vector3(0.3, band_h + 0.05, 0.025), STEEL_DARK)
		MeshKit.box(st, Transform3D(Basis(), Vector3(sx + side[1] * 0.15, band_y, 0.115)), Vector3(0.3, band_h + 0.05, 0.025), STEEL_DARK)

	# rear wall + roof
	MeshKit.box(st, Transform3D(Basis(), Vector3((X0 + X1) / 2, (YF + YR) / 2, Z1)), Vector3(X1 - X0, YR - YF, w), STEEL)
	MeshKit.box(st, Transform3D(Basis(), Vector3((X0 + X1) / 2, YR, (Z0 + Z1) / 2)), Vector3(X1 - X0, w, Z1 - Z0), STEEL)
	# hatch ring detail on roof above seat
	MeshKit.cyl(st, Transform3D(Basis(), Vector3(EYE.x, YR - 0.03, EYE.z)), 0.30, 0.30, 0.03, 12, STEEL_DARK, false, false)

	# ---- consoles
	# front panel slab (gauges mount here), tilted toward player
	MeshKit.box(st, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(18)), Vector3(EYE.x, 0.02, Z0 + 0.10)), Vector3(0.62, 0.34, 0.05), STEEL_DARK)
	# left console (rockets)
	MeshKit.box(st, Transform3D(Basis(), Vector3(X0 + 0.17, -0.18, -0.05)), Vector3(0.30, 0.06, 0.55), STEEL_DARK)
	MeshKit.box(st, Transform3D(Basis(), Vector3(X0 + 0.17, -0.50, -0.05)), Vector3(0.26, 0.58, 0.50), STEEL)
	# right console pedestal (turret grip)
	MeshKit.box(st, Transform3D(Basis(), Vector3(0.10, -0.32, -0.02)), Vector3(0.22, 0.5, 0.30), STEEL)
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
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.mesh = MeshKit.commit(st, mat)
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mesh)

	# glass in the periscopes (separate, translucent)
	var gst := MeshKit.begin()
	for slit in [[-0.71, -0.51], [-0.46, -0.13], [0.00, 0.20]]:
		var cx: float = (slit[0] + slit[1]) / 2.0
		var cw: float = slit[1] - slit[0]
		MeshKit.box(gst, Transform3D(Basis(), Vector3(cx, band_y, Z0 - 0.18)), Vector3(cw, band_h, 0.006), Color.WHITE)
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.55, 0.75, 0.70, 0.13)
	gmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gmat.roughness = 0.05
	gmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var glass := MeshInstance3D.new()
	glass.mesh = MeshKit.commit(gst, gmat)
	root.add_child(glass)

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

	# console labels
	_label(root, "BATTERY", Vector3(X0 + 0.22, -0.135, 0.115), -90)
	_label(root, "STARTER", Vector3(X0 + 0.13, -0.135, 0.115), -90)
	_label(root, "LIGHTS", Vector3(X0 + 0.22, -0.135, 0.235), -90)
	_label(root, "ROCKETS ARM", Vector3(X0 + 0.11, -0.135, -0.255), -90)
	_label(root, "ROCKET FIRE", Vector3(X0 + 0.11, -0.135, -0.05), -90)
	_label(root, "TURRET", Vector3(0.10, -0.135, 0.145), -90)

static func _label(root: Node3D, text: String, pos: Vector3, pitch_deg := 0.0, size := 20) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size * 4
	l.pixel_size = 0.0002
	l.modulate = Color(0.92, 0.94, 0.90)
	l.outline_size = 0
	l.position = pos
	l.rotation.x = deg_to_rad(pitch_deg)
	root.add_child(l)
	return l

# ------------------------------------------------------------------ instrument panel
static func _build_panel(root: Node3D, out: Dictionary) -> void:
	# gauges sit on the tilted front slab: local frame tilted 18 deg
	var slab := Node3D.new()
	slab.position = Vector3(EYE.x, 0.02, Z0 + 0.072)
	slab.rotation.x = deg_to_rad(18)
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
		m.emission_enabled = true
		m.emission = Color(0.25, 0.25, 0.22)
		m.emission_energy_multiplier = 0.0
		m.roughness = 0.4
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
		nm.emission_enabled = true
		nm.emission = Color(0.95, 0.4, 0.2)
		nm.emission_energy_multiplier = 0.3
		nd.material_override = nm
		pivot.add_child(nd)
		out["needles"][g[2]] = pivot
		out["lamps"]["gauge_face_" + str(g[2])] = m

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
	azm.emission_enabled = true
	azm.emission = Color(0.3, 0.9, 0.4)
	azm.emission_energy_multiplier = 0.3
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
		mm.albedo_color = lamp_defs[i][1] * 0.25
		lm.material_override = mm
		slab.add_child(lm)
		out["lamps"][lamp_defs[i][0]] = {"mat": mm, "color": lamp_defs[i][1]}
	_label(slab, "HULL  LOAD  ARM  ENG", Vector3(-0.065, -0.105, 0.004), 0, 11)

	# ammo counters + score plaque above slits
	var ammo := _label(root, "AP 40", Vector3(0.30, 0.18, 0.35), 0, 26)
	ammo.rotation.y = deg_to_rad(-90)
	out["labels"]["ammo"] = ammo
	var rockets := _label(root, "RKT 12", Vector3(X0 + 0.11, -0.135, -0.34), -90, 18)
	out["labels"]["rockets"] = rockets
	var plaque := _label(root, "WAVE 1    SCORE 0", Vector3(EYE.x, 0.47, Z0 + 0.02), 0, 30)
	out["labels"]["plaque"] = plaque
	var hint := _label(root, "", Vector3(EYE.x, 0.42, Z0 + 0.02), 0, 16)
	hint.modulate = Color(1.0, 0.8, 0.35)
	out["labels"]["hint"] = hint

# ------------------------------------------------------------------ lighting
static func _build_lighting(root: Node3D, out: Dictionary) -> void:
	var dome := OmniLight3D.new()
	dome.position = Vector3(EYE.x + 0.3, YR - 0.12, 0.1)
	dome.light_color = Color(1.0, 0.9, 0.75)
	dome.omni_range = 2.2
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

# Alternate player vehicle: helicopter (collective + cyclic). Exposes the
# PlayerTank input API. The old hand-rolled "Runner" (arm-swing locomotion)
# has been retired in favor of OnFootBody (scripts/on_foot_body.gd), which
# uses godot-xr-tools' XRToolsPlayerBody + movement providers instead.
class_name PlayerAlt
extends Object


# ============================================================ Helicopter
class Heli:
	extends CharacterBody3D

	var terrain: Terrain
	var projectiles: Projectiles
	var fx: FxPool
	var cockpit: Dictionary = {}
	var collective := 0.35     # 0..1 lift
	var cyclic := Vector2.ZERO
	var yaw_pedal := 0.0       # -1..1 from the PHYSICAL foot pedals only
	var stick_yaw := 0.0       # -1..1 left-stick-X fallback (kept separate — see set_stick_drive)
	var stick_fallback := Vector2.ZERO
	var stick_coll := 0.0
	var mg_held := false
	var mg_timer := 0.0
	var rocket_cool := 0.0
	var _crashed := false
	var _rumble_cb: Callable = Callable()
	var rotor: MeshInstance3D
	var tail_rotor: MeshInstance3D
	var engine_p: AudioStreamPlayer3D
	var alt_label: Label3D
	var _needles: Dictionary = {}

	func _init(t: Terrain, p: Projectiles, f: FxPool) -> void:
		terrain = t
		projectiles = p
		fx = f
		name = "PlayerHeli"
		collision_layer = 2
		collision_mask = 0
		add_to_group("player")

	func _ready() -> void:
		_build()
		engine_p = Sfx.make_loop_player("jeep_loop", self, -2.0, 12.0)
		engine_p.pitch_scale = 1.6
		engine_p.play()
		Game.game_restarted.connect(_respawn)
		_respawn()

	func _respawn() -> void:
		_crashed = false
		collective = 0.5
		global_position = Vector3(terrain.spawn.x, terrain.height(terrain.spawn.x, terrain.spawn.y) + 14.0, terrain.spawn.y)
		basis = Basis(Vector3.UP, PI)
		visible = true

	func _build() -> void:
		var col := Color(0.32, 0.4, 0.35)
		var st := MeshKit.begin()
		MeshKit.cyl(st, Transform3D(Basis(Vector3.RIGHT, PI / 2)), 0.75, 0.55, 3.4, 8, col)
		MeshKit.cyl(st, Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(0, 0.3, 3.2)), 0.28, 0.14, 3.4, 6, col)
		MeshKit.box(st, Transform3D(Basis(), Vector3(0, 1.05, 0)), Vector3(0.5, 0.5, 1.2), col * 0.9)
		for sx in [-0.9, 0.9]:
			MeshKit.box(st, Transform3D(Basis(), Vector3(sx, -1.05, 0)), Vector3(0.12, 0.12, 2.6), Color(0.2, 0.2, 0.2))
			MeshKit.box(st, Transform3D(Basis(Vector3.BACK, sx * 0.5), Vector3(sx * 0.5, -0.7, 0)), Vector3(0.08, 0.7, 0.08), Color(0.2, 0.2, 0.2))
		var mi := MeshInstance3D.new()
		mi.mesh = MeshKit.commit(st, MeshKit.mat_vcol(0.6, 0.2))
		add_child(mi)
		rotor = MeshInstance3D.new()
		var rq := QuadMesh.new()
		rq.size = Vector2(9.4, 0.5)
		rotor.mesh = rq
		rotor.rotation.x = -PI / 2
		rotor.position = Vector3(0, 1.42, 0)
		var rm := StandardMaterial3D.new()
		rm.albedo_color = Color(0.15, 0.15, 0.15, 0.5)
		rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		rm.cull_mode = BaseMaterial3D.CULL_DISABLED
		rotor.material_override = rm
		add_child(rotor)
		tail_rotor = MeshInstance3D.new()
		var tq := QuadMesh.new()
		tq.size = Vector2(1.6, 0.2)
		tail_rotor.mesh = tq
		tail_rotor.position = Vector3(0.2, 0.3, 4.7)
		tail_rotor.material_override = rm
		add_child(tail_rotor)

		# ---- cockpit: real bubble-canopy interior with a full control set.
		# Alex, live headset: "In the helicopter I don't have a good view and
		# don't feel like I'm in a cockpit." Two compounding root causes,
		# found by screenshotting the actual seat-anchor eye transform
		# (tools/heli_cockpit_view_check.gd, same recipe as the tank's
		# cockpit_view_check.gd):
		#   1) the OLD root position (heli-local Z=-0.9) sat the pilot's eye
		#      INSIDE the main fuselage cylinder (a solid capped tube
		#      spanning Z -1.7..+1.7) — the "good view" was actually looking
		#      at the inside of the opaque nose cap a few inches away. Fixed
		#      by moving the whole cockpit assembly forward past Z=-1.7, out
		#      into the open nose, the way a real bubble-canopy heli's
		#      cockpit pokes out ahead of the main cabin.
		#   2) the dash/glass were also badly proportioned: a solid dash box
		#      sat almost at eye height directly ahead, and the "glass" was
		#      alpha 0.10 — visually almost nothing there — so even with #1
		#      fixed the cabin would still read as a bare seat, not a
		#      cockpit (2 unlabeled controls, no panel, no pedals, no light).
		# Same fix family as the tank's front-slit widening earlier today:
		# push obstructions below/aside the sightline, make the open view
		# band generous, and dress the interior so it reads as a cockpit.
		var root := Node3D.new()
		root.position = Vector3(0, -0.35, -2.55)
		add_child(root)
		var EYE_L := Vector3(0, 0.62, -0.05)  # eye relative to seat anchor
		var SEAT_POS := Vector3(0, -0.05, 0.68)

		var cst := MeshKit.begin()
		# floor tub — kept low, well under the eye/sightline
		MeshKit.box(cst, Transform3D(Basis(), Vector3(0, -0.42, 0.25)), Vector3(1.05, 0.36, 1.55), Color(0.18, 0.2, 0.19))
		# low chin dash — top edge sits well BELOW eye height (eye local y
		# ~0.57) and its near face is pulled back from the eye so it can't
		# dominate the frame the way the tank's turret pedestal box briefly
		# did; gauges mount on its tilted top face, tank-panel style.
		var dash_y := 0.20
		var dash_z := 0.62
		MeshKit.box(cst, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-22)), Vector3(0, dash_y, dash_z)), Vector3(0.62, 0.09, 0.34), Color(0.20, 0.21, 0.20))
		# side consoles (low, at/below armrest height) instead of a tall
		# center obstruction — collective sits on the left one
		MeshKit.box(cst, Transform3D(Basis(), Vector3(-0.46, -0.10, 0.30)), Vector3(0.16, 0.30, 0.55), Color(0.20, 0.21, 0.20))
		MeshKit.box(cst, Transform3D(Basis(), Vector3(0.46, -0.10, 0.30)), Vector3(0.16, 0.30, 0.55), Color(0.20, 0.21, 0.20))
		# canopy frame pillars (thin — a real bubble canopy reads as glass
		# with a light frame, not a boxed-in room). A-pillars only; no
		# horizontal cross-brace at eye height.
		for sx in [-0.52, 0.52]:
			MeshKit.box(cst, Transform3D(Basis(), Vector3(sx, 0.55, 0.05)), Vector3(0.05, 0.85, 0.05), Color(0.16, 0.17, 0.16))
		var cmesh := MeshInstance3D.new()
		var cmat := MeshKit.mat_tex("res://assets/tex/metal.png", true, 0.85)
		cmat = cmat.duplicate()
		cmat.cull_mode = BaseMaterial3D.CULL_DISABLED
		cmesh.mesh = MeshKit.commit(cst, cmat)
		root.add_child(cmesh)

		# bubble canopy glass: large forward pane raked back (so it reads as
		# glass, catches light, but never sits flat-on in front of the eye)
		# PLUS a floor-facing chin pane so the pilot can look down at the
		# ground — the actual "good view" a helicopter needs. Both panes are
		# real visible glass now (was 0.10 alpha, effectively invisible; a
		# tinted-but-legible 0.28 reads as glass without hiding the outside).
		var gm := StandardMaterial3D.new()
		gm.albedo_color = Color(0.65, 0.85, 0.9, 0.28)
		gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		gm.metallic_specular = 0.0
		gm.cull_mode = BaseMaterial3D.CULL_DISABLED
		gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var glass_fwd := MeshInstance3D.new()
		var gq := QuadMesh.new()
		gq.size = Vector2(1.0, 1.15)
		glass_fwd.mesh = gq
		glass_fwd.material_override = gm
		glass_fwd.position = Vector3(0, 0.85, -0.55)
		glass_fwd.rotation.x = deg_to_rad(-18)  # gentle rake, stays well clear of the eye's forward+down sightline
		root.add_child(glass_fwd)
		var glass_chin := MeshInstance3D.new()
		var gq2 := QuadMesh.new()
		gq2.size = Vector2(0.9, 0.6)
		glass_chin.mesh = gq2
		glass_chin.material_override = gm
		glass_chin.position = Vector3(0, 0.02, -0.15)
		glass_chin.rotation.x = deg_to_rad(90)  # near-horizontal chin bubble, looks straight down/forward-down
		root.add_child(glass_chin)

		# ---- instrument panel on the dash top (same recipe as CockpitBuilder
		# ._build_panel(): tilted slab, gauge-face quad from the shared
		# assets/tex/gauge_*.png textures, a needle pivot per gauge). Only
		# ONE physical dial (speed, from gauge_speed.png which is correctly
		# labeled "KM/H") — the other three gauge textures have "TEMP"/
		# "FUEL"/"RPM x100" baked into the art, none of which read as
		# altitude, so pairing one with an "ALT" caption would show a dial
		# contradicting its own label. Altitude stays on the alt_label
		# Label3D readout instead (exact digits, no mismatched dial face).
		var panel := Node3D.new()
		panel.position = Vector3(0, dash_y + 0.048, dash_z - 0.11)
		panel.rotation.x = deg_to_rad(-22)
		root.add_child(panel)
		var needles := {}
		var face := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(0.15, 0.15)
		face.mesh = qm
		var m := StandardMaterial3D.new()
		m.albedo_texture = load("res://assets/tex/gauge_speed.png")
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		face.material_override = m
		face.position = Vector3(0, 0.0, 0.002)
		panel.add_child(face)
		var pivot := Node3D.new()
		pivot.position = Vector3(0, 0.0, 0.006)
		panel.add_child(pivot)
		var nd := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.0055, 0.055, 0.002)
		nd.mesh = bm
		nd.position = Vector3(0, 0.022, 0)
		var nm := StandardMaterial3D.new()
		nm.albedo_color = Color(0.95, 0.4, 0.2)
		nm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		nd.material_override = nm
		pivot.add_child(nd)
		needles["speed"] = pivot

		# ---- controls: collective (left lever, up/down = lift), cyclic
		# (center two-axis grip, tilt = pitch/roll), yaw pedals (foot level,
		# a lever pair like the tank's tillers but driving rotation.y via
		# tail-rotor authority), throttle twist-grip on the collective head,
		# rocket fire button, and an avionics switch that gates the interior
		# light + panel backlight (same "not pitch dark" principle as the
		# tank's battery-gated dome light).
		var cyc := VRControl.TwoAxisGrip.create()
		cyc.position = Vector3(0.15, -0.12, 0.15)
		root.add_child(cyc)
		cyc.deflection_changed.connect(func(v): cyclic = v)

		var coll := VRControl.Lever.create(0.3, Color(0.1, 0.1, 0.1), 38.0, false)
		coll.position = Vector3(-0.46, -0.22, 0.30)
		coll.rotation.z = deg_to_rad(-14)
		root.add_child(coll)
		coll.value_changed.connect(func(v): collective = clampf((v + 1.0) / 2.0, 0.0, 1.0))

		var throttle := VRControl.Knob.create(Color(0.15, 0.15, 0.16))
		throttle.position = Vector3(-0.46, -0.10, 0.02)
		throttle.rotation.y = deg_to_rad(90)
		throttle.value = 0.85
		root.add_child(throttle)

		# yaw pedals — floor-level, feet position, push-left/push-right like
		# real tail-rotor pedals; reuse the tank's tiller Lever recipe
		var ped_l := VRControl.Lever.create(0.16, Color(0.15, 0.15, 0.16), 24.0, true)
		ped_l.position = Vector3(-0.18, -0.62, 0.0)
		ped_l.rotation.x = deg_to_rad(78)  # lies near-flat, pressed forward with a foot
		root.add_child(ped_l)
		var ped_r := VRControl.Lever.create(0.16, Color(0.15, 0.15, 0.16), 24.0, true)
		ped_r.position = Vector3(0.18, -0.62, 0.0)
		ped_r.rotation.x = deg_to_rad(78)
		root.add_child(ped_r)
		ped_l.value_changed.connect(func(v): yaw_pedal = clampf((ped_r.value - v) * 0.5, -1.0, 1.0))
		ped_r.value_changed.connect(func(v): yaw_pedal = clampf((v - ped_l.value) * 0.5, -1.0, 1.0))

		var rkt := VRControl.PushButton.create(Color(0.85, 0.12, 0.1), 0.03)
		rkt.position = Vector3(-0.46, -0.06, 0.02)
		root.add_child(rkt)
		rkt.pressed.connect(fire_rockets)

		var avionics := VRControl.ToggleSwitch.create(Color(0.9, 0.85, 0.5))
		avionics.position = Vector3(0.46, -0.06, 0.02)
		root.add_child(avionics)

		# ---- captions — every control gets a Label3D, same as CockpitBuilder
		_heli_label(root, "COLLECTIVE", Vector3(-0.46, -0.22, 0.50), -90, 12)
		_heli_label(root, "THROTTLE", Vector3(-0.46, -0.10, -0.10), 0, 12)
		_heli_label(root, "ROCKETS", Vector3(-0.46, -0.06, 0.10), 0, 12)
		_heli_label(root, "CYCLIC", Vector3(0.15, -0.12, 0.36), -90, 12)
		_heli_label(root, "AVIONICS", Vector3(0.46, -0.06, 0.10), 0, 12)
		_heli_label(root, "PEDALS", Vector3(0.0, -0.60, 0.22), 0, 12)

		# ---- interior lighting: OmniLight3D on render layer 2 (excluded from
		# the exterior sun's cull mask — see main.gd's `~2` masks), gated on
		# the avionics switch so the canopy isn't pitch dark once avionics is
		# on, matching CockpitBuilder._build_lighting()'s pattern. Kept off
		# to the side/up-and-behind the pilot's head, NOT dead ahead in the
		# forward sightline — an early version placed it centered in front
		# and it bloomed out the whole view through the (now-visible) glass.
		var dome := OmniLight3D.new()
		dome.position = Vector3(0.35, 0.85, 0.45)
		dome.light_color = Color(1.0, 0.85, 0.6)
		dome.omni_range = 1.3
		dome.omni_attenuation = 1.4
		dome.light_energy = 0.9  # heli has no separate start ritual; default on with avionics
		dome.shadow_enabled = false
		root.add_child(dome)
		avionics.toggled_on.connect(func(on): dome.light_energy = 0.9 if on else 0.0)
		avionics.on = true

		alt_label = Label3D.new()
		alt_label.text = "ALT 0"
		alt_label.font_size = 56
		alt_label.pixel_size = 0.00035
		alt_label.modulate = Color(0.4, 0.95, 0.5)
		alt_label.position = Vector3(0, dash_y + 0.14, dash_z - 0.11)
		alt_label.rotation.x = deg_to_rad(-22)
		root.add_child(alt_label)

		CockpitBuilder.set_interior_layer(root)
		var seat := Node3D.new()
		seat.position = SEAT_POS
		root.add_child(seat)
		_needles = needles
		cockpit = {
			"seat_anchor": seat, "eye_local": EYE_L,
			"controls": {"cyclic": cyc, "collective": coll, "throttle": throttle,
				"pedal_l": ped_l, "pedal_r": ped_r, "rockets": rkt, "avionics": avionics},
			"needles": needles, "dome_light": dome,
		}

	static func _heli_label(root: Node3D, text: String, pos: Vector3, pitch_deg := 0.0, size := 12) -> Label3D:
		var l := Label3D.new()
		l.text = text
		l.font_size = size * 4
		l.pixel_size = 0.0002
		l.modulate = Color(0.92, 0.94, 0.90)
		l.outline_size = 0
		l.position = pos
		l.rotation_degrees = Vector3(pitch_deg, 0, 0)
		root.add_child(l)
		return l

	func _physics_process(delta: float) -> void:
		if _crashed:
			return
		rotor.rotation.z += (8.0 + collective * 22.0) * delta
		tail_rotor.rotation.x += 30.0 * delta
		var cyc := cyclic if cyclic.length() > 0.05 else stick_fallback
		collective = clampf(collective + stick_coll * delta * 0.5, 0.0, 1.0)
		# arcade heli: collective lifts, cyclic tilts + translates
		var lift := (collective - 0.42) * Tune.v("heli_lift")
		velocity.y = move_toward(velocity.y, lift, 12.0 * delta)
		var fwd := -basis.z
		var right := basis.x
		var target_h := (fwd * cyc.y + right * cyc.x) * Tune.v("heli_speed")
		velocity.x = move_toward(velocity.x, target_h.x, 14.0 * delta)
		velocity.z = move_toward(velocity.z, target_h.z, 14.0 * delta)
		# yaw follows horizontal motion; visual tilt. Pedals add direct yaw
		# authority on top of the auto-yaw (real tail-rotor pedals let you
		# yaw independent of travel direction, e.g. hovering pirouettes).
		if Vector2(velocity.x, velocity.z).length() > 3.0 and absf(cyc.y) > 0.1:
			var want := atan2(-velocity.x, -velocity.z)
			rotation.y = lerp_angle(rotation.y, want, 0.8 * delta)
		# Physical pedals win while deflected, else the stick fallback — same
		# live per-frame merge as `cyc` above (see set_stick_drive's note on
		# why the stick must not write yaw_pedal directly).
		var yaw_in := yaw_pedal if absf(yaw_pedal) > 0.05 else stick_yaw
		if absf(yaw_in) > 0.05:
			rotation.y -= yaw_in * 1.1 * delta
		rotation.x = lerpf(rotation.x, -cyc.y * 0.22, 3.0 * delta)
		rotation.z = lerpf(rotation.z, -cyc.x * 0.22 - yaw_in * 0.05, 3.0 * delta)
		global_position += velocity * delta
		global_position.y = minf(global_position.y, 130.0)
		var gh := terrain.height(global_position.x, global_position.z)
		if global_position.y < gh + 1.6:
			if velocity.y < -7.0:
				_crash()
			else:
				global_position.y = gh + 1.6
				velocity.y = maxf(velocity.y, 0.0)
		engine_p.pitch_scale = 1.3 + collective * 0.6
		var alt := global_position.y - gh
		var spd_kmh := Vector2(velocity.x, velocity.z).length() * 3.6
		alt_label.text = "ALT %d   LIFT %d%%" % [int(alt), int(collective * 100)]
		if _needles.has("speed"):
			# gauge_speed.png reads 0..40 KM/H; needle convention matches
			# player_tank.gd's _needle(): rotation.z = -(225 + 270*frac) deg
			var frac := clampf(spd_kmh / 40.0, 0.0, 1.0)
			_needles["speed"].rotation.z = lerp_angle(_needles["speed"].rotation.z, deg_to_rad(-(225.0 + 270.0 * frac)), 6.0 * delta)
		mg_timer -= delta
		rocket_cool -= delta
		if mg_held and mg_timer <= 0.0 and Game.alive:
			mg_timer = 0.1
			var dir := -global_transform.basis.z
			projectiles.fire(Projectiles.Kind.MG, to_global(Vector3(0, -0.5, -2.2)), dir * 220.0 + velocity, [get_rid()], true)
			Sfx.play_at("mg", global_position, -6.0)
			_rumble(0.15, 0.03)

	func fire_rockets() -> void:
		if rocket_cool > 0.0 or not Game.alive:
			return
		rocket_cool = 1.2
		Game.make_noise()
		for sx in [-1.0, 1.0]:
			var pos := to_global(Vector3(sx * 1.0, -0.6, -0.5))
			var dir := -global_transform.basis.z
			projectiles.fire(Projectiles.Kind.ROCKET, pos, dir * 50.0 + velocity, [get_rid()], true)
		Sfx.play_at("rocket", global_position, 2.0)
		_rumble(0.4, 0.08)

	func _crash() -> void:
		_crashed = true
		fx.explosion(global_position, true, global_position)
		Sfx.play_at("crash", global_position, 4.0)
		Game.damage_player(40.0)
		visible = false
		_rumble(1.0, 0.4)
		if Game.alive:
			get_tree().create_timer(3.0).timeout.connect(_respawn)

	func take_damage(amount: float, at: Vector3) -> void:
		if not Game.alive or _crashed:
			return
		Game.damage_player(amount)
		Sfx.play_at("hit", at, 0.0)
		_rumble(0.7, 0.15)

	func _rumble(a: float, d: float) -> void:
		if _rumble_cb.is_valid():
			_rumble_cb.call(a, d)

	# rig-facing API. Left stick: Y -> collective rate (unchanged), X -> yaw
	# fallback. NOTE this must NOT write yaw_pedal directly: xr_rig calls
	# set_stick_drive EVERY physics frame, so assigning yaw_pedal here
	# clobbered the physical pedal levers' value with 0 whenever the stick
	# was centered — the pedals were effectively dead (2026-07-16 audit:
	# "assignment-vs-fallback flavor of the overwrite family", same bug
	# class as the plane's old stick latch). stick_yaw is stored separately
	# and _physics_process picks pedals-when-deflected, else stick — the
	# same live-fallback pattern the cyclic grip already uses.
	func set_stick_drive(v: Vector2) -> void:
		stick_coll = v.y
		# v.x arrives PRE-NEGATED by xr_rig (tank convention); `rotation.y -=
		# yaw` means positive yaws right, so un-negate here or stick-right
		# yaws left (Alex: "helicopter mode, left thumbstick rotate (X) is
		# backwards")
		stick_yaw = clampf(-v.x, -1.0, 1.0)
	func set_stick_turret(v: Vector2) -> void: stick_fallback = v
	func fire_primary() -> void: mg_held = true; get_tree().create_timer(0.4).timeout.connect(func(): mg_held = false)
	func stick_fire() -> void: fire_rockets()
	func stick_rockets() -> void: fire_rockets()
	func set_mg(h: bool) -> void: mg_held = h
	func quick_start() -> void: pass

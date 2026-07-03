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
		# ---- cockpit: canopy + collective (left) + cyclic (center)
		var root := Node3D.new()
		root.position = Vector3(0, 0.15, -0.9)
		add_child(root)
		var cst := MeshKit.begin()
		MeshKit.box(cst, Transform3D(Basis(), Vector3(0, -0.35, 0.2)), Vector3(1.1, 0.5, 1.6), Color(0.18, 0.2, 0.19))
		MeshKit.box(cst, Transform3D(Basis(), Vector3(0, -0.05, 0.75)), Vector3(0.5, 0.1, 0.45), Color(0.24, 0.2, 0.15))
		MeshKit.box(cst, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-12)), Vector3(0, 0.28, -0.5)), Vector3(0.85, 0.35, 0.05), Color(0.15, 0.16, 0.15))
		var cmesh := MeshInstance3D.new()
		var cmat := MeshKit.mat_tex("res://assets/tex/metal.png", true, 0.85)
		cmat = cmat.duplicate()
		cmat.cull_mode = BaseMaterial3D.CULL_DISABLED
		cmesh.mesh = MeshKit.commit(cst, cmat)
		root.add_child(cmesh)
		var glass := MeshInstance3D.new()
		var gq := QuadMesh.new()
		gq.size = Vector2(1.05, 0.8)
		glass.mesh = gq
		var gm := StandardMaterial3D.new()
		gm.albedo_color = Color(0.6, 0.8, 0.85, 0.10)
		gm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		gm.metallic_specular = 0.0
		gm.cull_mode = BaseMaterial3D.CULL_DISABLED
		glass.material_override = gm
		glass.position = Vector3(0, 0.5, -0.75)
		glass.rotation.x = deg_to_rad(-32)
		root.add_child(glass)
		var cyc := VRControl.TwoAxisGrip.create()
		cyc.position = Vector3(0.15, -0.12, 0.15)
		root.add_child(cyc)
		cyc.deflection_changed.connect(func(v): cyclic = v)
		var coll := VRControl.Lever.create(0.3, Color(0.1, 0.1, 0.1), 38.0, false)
		coll.position = Vector3(-0.42, -0.25, 0.35)
		coll.rotation.z = deg_to_rad(-14)
		root.add_child(coll)
		coll.value_changed.connect(func(v): collective = clampf((v + 1.0) / 2.0, 0.0, 1.0))
		var rkt := VRControl.PushButton.create(Color(0.85, 0.12, 0.1), 0.03)
		rkt.position = Vector3(-0.42, -0.14, 0.14)
		root.add_child(rkt)
		rkt.pressed.connect(fire_rockets)
		alt_label = Label3D.new()
		alt_label.text = "ALT 0"
		alt_label.font_size = 56
		alt_label.pixel_size = 0.00035
		alt_label.modulate = Color(0.4, 0.95, 0.5)
		alt_label.position = Vector3(0, 0.32, -0.48)
		alt_label.rotation.x = deg_to_rad(-12)
		root.add_child(alt_label)
		CockpitBuilder.set_interior_layer(root)
		var seat := Node3D.new()
		seat.position = Vector3(0, -0.05, 0.68)
		root.add_child(seat)
		cockpit = {"seat_anchor": seat, "eye_local": Vector3(0, 0.62, -0.05), "controls": {}}

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
		# yaw follows horizontal motion; visual tilt
		if Vector2(velocity.x, velocity.z).length() > 3.0 and absf(cyc.y) > 0.1:
			var want := atan2(-velocity.x, -velocity.z)
			rotation.y = lerp_angle(rotation.y, want, 0.8 * delta)
		rotation.x = lerpf(rotation.x, -cyc.y * 0.22, 3.0 * delta)
		rotation.z = lerpf(rotation.z, -cyc.x * 0.22, 3.0 * delta)
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
		alt_label.text = "ALT %d   LIFT %d%%" % [int(global_position.y - gh), int(collective * 100)]
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

	# rig-facing API
	func set_stick_drive(v: Vector2) -> void: stick_coll = v.y
	func set_stick_turret(v: Vector2) -> void: stick_fallback = v
	func fire_primary() -> void: mg_held = true; get_tree().create_timer(0.4).timeout.connect(func(): mg_held = false)
	func stick_fire() -> void: fire_rockets()
	func stick_rockets() -> void: fire_rockets()
	func set_mg(h: bool) -> void: mg_held = h
	func quick_start() -> void: pass

# Light enemy types: fast MG jeeps, infantry gunners (squads), and static
# mortar emplacements with high-arc whistling shells.
class_name EnemyLight
extends Object


# ============================================================ Jeep
class Jeep:
	extends CharacterBody3D

	static var _mesh: ArrayMesh
	var terrain: Terrain
	var projectiles: Projectiles
	var fx: FxPool
	var player: Node3D
	var hp := 14.0
	var yaw := 0.0
	var spd := 0.0
	var orbit_dir := 1.0
	var burst := 0
	var shot_t := 0.0
	var engine_p: AudioStreamPlayer3D
	var _dead := false

	func _init(t: Terrain, p: Projectiles, f: FxPool, pl: Node3D) -> void:
		terrain = t
		projectiles = p
		fx = f
		player = pl
		collision_layer = 4
		collision_mask = 1
		add_to_group("enemies")

	static func _build() -> void:
		if _mesh:
			return
		var st := MeshKit.begin()
		var body := Color(0.42, 0.4, 0.3)
		MeshKit.box(st, Transform3D(Basis(), Vector3(0, 0.75, 0)), Vector3(1.7, 0.55, 3.2), body)
		MeshKit.box(st, Transform3D(Basis(), Vector3(0, 1.15, 0.5)), Vector3(1.5, 0.35, 1.6), body * 0.9)
		MeshKit.box(st, Transform3D(Basis(Vector3.RIGHT, -0.4), Vector3(0, 1.15, -0.7)), Vector3(1.4, 0.5, 0.1), Color(0.25, 0.3, 0.35))
		for sx in [-0.8, 0.8]:
			for sz in [-1.05, 1.05]:
				MeshKit.cyl(st, Transform3D(Basis(Vector3(0, 0, 1), PI / 2), Vector3(sx, 0.4, sz)), 0.38, 0.38, 0.3, 8, Color(0.12, 0.12, 0.12))
		# gunner + MG on the back
		MeshKit.cyl(st, Transform3D(Basis(), Vector3(0, 1.55, 0.9)), 0.16, 0.14, 0.5, 6, Color(0.35, 0.32, 0.25))
		MeshKit.cyl(st, Transform3D(Basis(), Vector3(0, 1.95, 0.9)), 0.11, 0.11, 0.24, 6, Color(0.75, 0.6, 0.45))
		MeshKit.cyl(st, Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(0, 1.7, 0.2)), 0.05, 0.04, 1.2, 6, Color(0.1, 0.1, 0.1))
		_mesh = MeshKit.commit(st, MeshKit.mat_vcol(0.85))

	func _ready() -> void:
		_build()
		var mi := MeshInstance3D.new()
		mi.mesh = _mesh
		add_child(mi)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(1.8, 1.6, 3.4)
		shape.shape = box
		shape.position = Vector3(0, 0.9, 0)
		add_child(shape)
		yaw = Game.rng.randf() * TAU
		orbit_dir = 1.0 if Game.rng.randf() > 0.5 else -1.0
		engine_p = Sfx.make_loop_player("jeep_loop", self, -6.0)
		engine_p.play()
		shot_t = Game.rng.randf_range(2.0, 5.0)
		if Game.mutator == "balloon":
			Game.balloonize(self)
		elif Levels.cardboard:
			for c in get_children():
				if c is MeshInstance3D:
					c.material_override = MeshKit.mat_tex("res://assets/tex/cardboard.png", false, 0.95)

	func _physics_process(delta: float) -> void:
		if _dead:
			return
		var gp := global_position
		var to_p := player.global_position - gp
		var flat_d := Vector2(to_p.x, to_p.z).length()
		# orbit at ~45 m, faster than the tank
		var want := atan2(-to_p.x, -to_p.z) + orbit_dir * (PI / 2.0 + clampf((48.0 - flat_d) / 70.0, -0.6, 0.6))
		var dy := wrapf(want - yaw, -PI, PI)
		yaw += clampf(dy, -1.4 * delta, 1.4 * delta)
		spd = move_toward(spd, 11.0 * Game.diff(0.8, 1.0, 1.2) * Levels.mud_factor(gp), 6.0 * delta)
		var fwd := Vector3(-sin(yaw), 0, -cos(yaw))
		var target_y := terrain.height(gp.x, gp.z) + 0.05
		velocity = fwd * spd + Vector3(0, clampf((target_y - gp.y) / delta, -12.0, 12.0), 0)
		move_and_slide()
		var n := terrain.normal(global_position.x, global_position.z)
		var right := fwd.cross(n).normalized() * -1.0
		var fdir := n.cross(right).normalized() * -1.0
		basis = basis.slerp(Basis(right * -1.0, n, fdir * -1.0).orthonormalized(), clampf(6.0 * delta, 0.0, 1.0)).orthonormalized()
		engine_p.pitch_scale = 0.9 + spd / 22.0
		# MG bursts
		shot_t -= delta
		if shot_t <= 0.0 and Game.alive and flat_d < 110.0:
			if burst <= 0:
				burst = Game.rng.randi_range(3, 6)
			burst -= 1
			shot_t = 0.12 if burst > 0 else Game.rng.randf_range(1.8, 4.0) / Game.diff(0.7, 1.0, 1.4)
			var mpos := to_global(Vector3(0, 1.7, -0.4))
			var dir := (player.global_position + Vector3(0, 1.6, 0) - mpos).normalized()
			dir = dir.rotated(Vector3.UP, Game.rng.randf_range(-0.05, 0.05) / Game.diff(0.6, 1.0, 1.6))
			projectiles.fire(Projectiles.Kind.ENEMY_MG, mpos, dir * 190.0, [get_rid()], false)
			Sfx.play_at("mg", mpos, -6.0, 1.15)

	func take_damage(amount: float, at: Vector3) -> void:
		if _dead:
			return
		hp -= amount
		Sfx.play_at("hit", at, -8.0)
		if hp <= 0.0:
			_dead = true
			remove_from_group("enemies")
			collision_layer = 0
			engine_p.stop()
			var fxp: FxPool = get_tree().get_first_node_in_group("fx")
			if fxp:
				fxp.explosion(global_position + Vector3(0, 1, 0), false, player.global_position)
			Game.add_score(50)
			var vo_ok := Game.rng.randf() < 0.4
			if vo_ok:
				Sfx.vo("vo_kill", 1, 10.0)
			# flip the wreck
			rotation.z = PI * 0.9
			position.y += 0.6
			set_physics_process(false)
			get_tree().create_timer(14.0).timeout.connect(queue_free)


# ============================================================ Gunner (infantry)
class Gunner:
	extends CharacterBody3D

	static var _mesh: ArrayMesh
	var terrain: Terrain
	var projectiles: Projectiles
	var player: Node3D
	var hp := 6.0
	var shot_t := 2.0
	var wander := Vector2.ZERO
	var _dead := false

	func _init(t: Terrain, p: Projectiles, pl: Node3D) -> void:
		terrain = t
		projectiles = p
		player = pl
		collision_layer = 4
		collision_mask = 1
		add_to_group("enemies")

	static func _build() -> void:
		if _mesh:
			return
		var st := MeshKit.begin()
		var uniform := Color(0.35, 0.36, 0.28)
		MeshKit.box(st, Transform3D(Basis(), Vector3(0, 0.95, 0)), Vector3(0.42, 0.7, 0.26), uniform)
		MeshKit.box(st, Transform3D(Basis(), Vector3(-0.12, 0.35, 0)), Vector3(0.16, 0.7, 0.2), uniform * 0.9)
		MeshKit.box(st, Transform3D(Basis(), Vector3(0.12, 0.35, 0)), Vector3(0.16, 0.7, 0.2), uniform * 0.9)
		MeshKit.cyl(st, Transform3D(Basis(), Vector3(0, 1.45, 0)), 0.13, 0.12, 0.22, 6, Color(0.75, 0.6, 0.45))
		MeshKit.cyl(st, Transform3D(Basis(), Vector3(0, 1.6, 0)), 0.16, 0.13, 0.1, 6, uniform * 0.8)
		MeshKit.cyl(st, Transform3D(Basis(Vector3.RIGHT, PI / 2), Vector3(0.18, 1.1, -0.3)), 0.03, 0.025, 0.8, 5, Color(0.12, 0.1, 0.08))
		_mesh = MeshKit.commit(st, MeshKit.mat_vcol(0.9))

	func _ready() -> void:
		_build()
		var mi := MeshInstance3D.new()
		mi.mesh = _mesh
		add_child(mi)
		var shape := CollisionShape3D.new()
		var cap := BoxShape3D.new()
		cap.size = Vector3(0.6, 1.7, 0.6)
		shape.shape = cap
		shape.position = Vector3(0, 0.85, 0)
		add_child(shape)
		shot_t = Game.rng.randf_range(1.5, 4.0)
		wander = Vector2(Game.rng.randf_range(-1, 1), Game.rng.randf_range(-1, 1)).normalized()

	func _physics_process(delta: float) -> void:
		if _dead:
			return
		var gp := global_position
		var to_p := player.global_position - gp
		var flat_d := Vector2(to_p.x, to_p.z).length()
		look_at(Vector3(player.global_position.x, gp.y, player.global_position.z), Vector3.UP, true)
		# shuffle sideways a bit, keep ~50 m
		var mv := Vector3.ZERO
		if flat_d > 70.0:
			mv = Vector3(to_p.x, 0, to_p.z).normalized() * 2.2
		elif flat_d < 35.0:
			mv = -Vector3(to_p.x, 0, to_p.z).normalized() * 2.4
		var target_y := terrain.height(gp.x, gp.z) + 0.02
		velocity = mv + Vector3(0, clampf((target_y - gp.y) / delta, -10.0, 10.0), 0)
		move_and_slide()
		shot_t -= delta
		if shot_t <= 0.0 and Game.alive and flat_d < 90.0:
			shot_t = Game.rng.randf_range(1.6, 3.2) / Game.diff(0.7, 1.0, 1.4)
			var mpos := to_global(Vector3(0.18, 1.1, -0.6))
			var dir := (player.global_position + Vector3(0, 1.7, 0) - mpos).normalized()
			dir = dir.rotated(Vector3.UP, Game.rng.randf_range(-0.04, 0.04))
			projectiles.fire(Projectiles.Kind.ENEMY_MG, mpos, dir * 170.0, [get_rid()], false)
			Sfx.play_at("rifle", mpos, -4.0)

	func take_damage(amount: float, at: Vector3) -> void:
		if _dead:
			return
		hp -= amount
		if hp <= 0.0:
			_dead = true
			remove_from_group("enemies")
			collision_layer = 0
			Game.add_score(25)
			Sfx.play_at("hit", at, -12.0, 0.8)
			var tw := create_tween()
			tw.tween_property(self, "rotation:x", PI / 2 * (1 if Game.rng.randf() > 0.5 else -1), 0.4).set_ease(Tween.EASE_IN)
			set_physics_process(false)
			get_tree().create_timer(10.0).timeout.connect(queue_free)


# ============================================================ Mortar emplacement
class Mortar:
	extends CharacterBody3D

	static var _mesh: ArrayMesh
	var terrain: Terrain
	var projectiles: Projectiles
	var fx: FxPool
	var player: Node3D
	var hp := 22.0
	var fire_t := 6.0
	var _dead := false

	func _init(t: Terrain, p: Projectiles, f: FxPool, pl: Node3D) -> void:
		terrain = t
		projectiles = p
		fx = f
		player = pl
		collision_layer = 4
		collision_mask = 0
		add_to_group("enemies")

	static func _build() -> void:
		if _mesh:
			return
		var st := MeshKit.begin()
		MeshKit.cyl(st, Transform3D(Basis(), Vector3(0, 0.15, 0)), 1.5, 1.3, 0.3, 10, Color(0.4, 0.38, 0.3))
		MeshKit.cyl(st, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-65)), Vector3(0, 0.9, 0.2)), 0.14, 0.16, 1.6, 8, Color(0.2, 0.2, 0.2))
		MeshKit.box(st, Transform3D(Basis(), Vector3(0.7, 0.5, -0.5)), Vector3(0.5, 0.6, 0.7), Color(0.3, 0.3, 0.24))
		# sandbags ring
		for i in 8:
			var a := TAU * i / 8.0
			MeshKit.box(st, Transform3D(Basis(Vector3.UP, a), Vector3(cos(a) * 2.0, 0.3, sin(a) * 2.0)), Vector3(1.1, 0.55, 0.5), Color(0.62, 0.55, 0.4))
		_mesh = MeshKit.commit(st, MeshKit.mat_vcol(0.95))

	func _ready() -> void:
		_build()
		var mi := MeshInstance3D.new()
		mi.mesh = _mesh
		add_child(mi)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(4.0, 1.6, 4.0)
		shape.shape = box
		shape.position = Vector3(0, 0.8, 0)
		add_child(shape)
		fire_t = Game.rng.randf_range(4.0, 8.0)

	func _physics_process(delta: float) -> void:
		if _dead:
			return
		fire_t -= delta
		var to_p := player.global_position - global_position
		var flat_d := Vector2(to_p.x, to_p.z).length()
		if fire_t <= 0.0 and Game.alive and flat_d < 220.0 and flat_d > 25.0:
			fire_t = Game.rng.randf_range(7.0, 11.0) / Game.diff(0.7, 1.0, 1.35)
			_lob()

	func _lob() -> void:
		# high-arc solution (the "mortar branch"): theta = (PI - asin(gR/v^2)) / 2
		var target: Vector3 = player.global_position
		var pvel = player.get("velocity")
		if pvel is Vector3:
			target += pvel * 2.5
		var mpos := global_position + Vector3(0, 1.5, 0)
		var to := target - mpos
		var flat := Vector2(to.x, to.z).length()
		var v := 52.0
		var g := 9.8
		var sin2 := clampf(g * flat / (v * v), 0.0, 1.0)
		var ang := (PI - asin(sin2)) / 2.0
		var dir_flat := Vector3(to.x, 0, to.z).normalized()
		dir_flat = dir_flat.rotated(Vector3.UP, Game.rng.randf_range(-0.05, 0.05) / Game.diff(0.6, 1.0, 1.5))
		var vel := dir_flat * cos(ang) * v + Vector3.UP * sin(ang) * v
		projectiles.fire(Projectiles.Kind.MORTAR, mpos, vel, [get_rid()], false)
		fx.muzzle_flash(mpos, 1.0)
		Sfx.play_at("mortar_launch", mpos, 2.0)

	func take_damage(amount: float, at: Vector3) -> void:
		if _dead:
			return
		hp -= amount
		Sfx.play_at("hit", at, -8.0)
		if hp <= 0.0:
			_dead = true
			remove_from_group("enemies")
			collision_layer = 0
			Game.add_score(75)
			var fxp: FxPool = get_tree().get_first_node_in_group("fx")
			if fxp:
				fxp.explosion(global_position + Vector3(0, 0.8, 0), true, player.global_position)
			for c in get_children():
				if c is MeshInstance3D:
					var m := StandardMaterial3D.new()
					m.albedo_color = Color(0.1, 0.09, 0.08)
					c.material_override = m
			set_physics_process(false)
			get_tree().create_timer(20.0).timeout.connect(queue_free)

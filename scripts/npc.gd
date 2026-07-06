# Non-combat characters: the cabbage merchant (every level, indestructible,
# extremely destructible stand), a suspicious green hissing critter, and the
# giant baby who owns the baby-room level.
class_name Npc
extends Object


# ============================================================ Cabbage merchant
class CabbageMan:
	extends Node3D

	var stand: StaticBody3D
	var arms_l: Node3D
	var arms_r: Node3D
	var destroyed := false
	var _greeted := false
	var player: Node3D

	static func spawn(parent: Node3D, terrain: Terrain, pl: Node3D) -> CabbageMan:
		var c := CabbageMan.new()
		c.player = pl
		var s := terrain.spawn
		var rng := Game.rng
		for attempt in 12:
			var a := rng.randf() * TAU
			var p := Vector2(s.x + cos(a) * 34.0, s.y + sin(a) * 34.0)
			if p.length() < terrain.arena_radius - 10.0:
				c.position = Vector3(p.x, terrain.height(p.x, p.y), p.y)
				break
		parent.add_child(c)
		return c

	func _ready() -> void:
		# the stand (this is the part kids will absolutely destroy)
		stand = StaticBody3D.new()
		stand.collision_layer = 1
		stand.set_script(null)
		add_child(stand)
		var st := MeshKit.begin()
		var wood := Color(0.5, 0.36, 0.2)
		MeshKit.box(st, Transform3D(Basis(), Vector3(0, 0.75, 0)), Vector3(2.2, 0.1, 1.1), wood)
		for sx in [-1.0, 1.0]:
			MeshKit.box(st, Transform3D(Basis(), Vector3(sx, 0.38, 0)), Vector3(0.12, 0.76, 1.0), wood * 0.85)
		MeshKit.box(st, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-14)), Vector3(0, 1.9, -0.2)), Vector3(2.4, 0.06, 1.4), Color(0.75, 0.3, 0.25))
		for px in [-1.15, 1.15]:
			MeshKit.cyl(st, Transform3D(Basis(), Vector3(px, 1.3, -0.5)), 0.05, 0.05, 1.4, 6, wood * 0.9)
		var mesh := MeshInstance3D.new()
		mesh.mesh = MeshKit.commit(st, MeshKit.mat_vcol())
		stand.add_child(mesh)
		var cabbages := MeshKit.begin()
		var rng := Game.rng
		for i in 12:
			var green := Color(0.45, 0.68, 0.3).lerp(Color(0.6, 0.8, 0.45), rng.randf())
			MeshKit.cyl(cabbages, Transform3D(Basis(),
				Vector3(rng.randf_range(-0.9, 0.9), 0.94 + (0.18 if i > 7 else 0.0), rng.randf_range(-0.35, 0.35))),
				0.16, 0.13, 0.24, 7, green)
		var cm := MeshInstance3D.new()
		cm.mesh = MeshKit.commit(cabbages, MeshKit.mat_vcol(0.7))
		cm.name = "Cabbages"
		stand.add_child(cm)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(2.3, 2.0, 1.2)
		shape.shape = box
		shape.position = Vector3(0, 1.0, 0)
		stand.add_child(shape)
		# route damage from the stand body to us
		stand.set_meta("cabbage_owner", self)
		# the merchant himself (unkillable: no collider at all)
		var mst := MeshKit.begin()
		MeshKit.cyl(mst, Transform3D(Basis(), Vector3(0, 0.75, 0)), 0.3, 0.36, 1.5, 8, Color(0.45, 0.32, 0.2))
		MeshKit.cyl(mst, Transform3D(Basis(), Vector3(0, 1.68, 0)), 0.16, 0.14, 0.3, 8, Color(0.8, 0.62, 0.45))
		MeshKit.cyl(mst, Transform3D(Basis(), Vector3(0, 1.9, 0)), 0.34, 0.05, 0.16, 8, Color(0.75, 0.65, 0.35))
		var body := MeshInstance3D.new()
		body.mesh = MeshKit.commit(mst, MeshKit.mat_vcol())
		body.position = Vector3(0, 0, 0.9)
		add_child(body)
		arms_l = _arm(body, -1)
		arms_r = _arm(body, 1)
		set_meta("is_cabbage_man", true)

	func _arm(body: Node3D, side: int) -> Node3D:
		var pivot := Node3D.new()
		pivot.position = Vector3(side * 0.32, 1.45, 0)
		body.add_child(pivot)
		var st := MeshKit.begin()
		MeshKit.cyl(st, Transform3D(Basis(), Vector3(0, -0.3, 0)), 0.06, 0.05, 0.6, 6, Color(0.45, 0.32, 0.2))
		var m := MeshInstance3D.new()
		m.mesh = MeshKit.commit(st, MeshKit.mat_vcol())
		pivot.add_child(m)
		pivot.rotation.z = side * 0.25
		return pivot

	func _process(_delta: float) -> void:
		if not _greeted and player and global_position.distance_to(player.global_position) < 16.0:
			_greeted = true
			Sfx.play_at("char_cabbage_hello", global_position + Vector3(0, 1.7, 0.9), 4.0, 1.0, 40.0)

	func tragedy() -> void:
		if destroyed:
			return
		destroyed = true
		var cb := stand.get_node_or_null("Cabbages")
		if cb:
			cb.queue_free()
		var fx: FxPool = get_tree().get_first_node_in_group("fx")
		if fx:
			fx.debris_burst(stand.global_position + Vector3(0, 1.2, 0), 12, Color(0.5, 0.75, 0.35))
			fx.dust(stand.global_position + Vector3(0, 0.8, 0), 1.4)
		Sfx.play_at("debris", stand.global_position, 0.0)
		Sfx.play_at("char_cabbage_%d" % (1 + Game.rng.randi() % 3),
			global_position + Vector3(0, 1.7, 0.9), 6.0, 1.0, 120.0)
		# arms up + anguished hops
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(arms_l, "rotation:z", -2.6, 0.25)
		tw.tween_property(arms_r, "rotation:z", 2.6, 0.25)
		var hop := create_tween()
		hop.set_loops(6)
		hop.tween_property(self, "position:y", position.y + 0.35, 0.18)
		hop.tween_property(self, "position:y", position.y, 0.18)
		get_tree().create_timer(2.2).timeout.connect(func(): Sfx.vo("vo_cabbage", 1, 120.0))
		Game.add_score(-50)  # shame.


# ============================================================ Green critter
# A suspicious green cube-creature. Waddles at you, flashes, and explodes.
# It is definitely not from anywhere. No sir.
class Creeper:
	extends CharacterBody3D

	var terrain: Terrain
	var player: Node3D
	var _fuse := -1.0
	var _mat: StandardMaterial3D

	static func maybe_spawn(parent: Node3D, t: Terrain, pl: Node3D) -> void:
		if Game.rng.randf() > 0.5:
			return
		var c := Creeper.new()
		c.terrain = t
		c.player = pl
		parent.add_child(c)
		var a := Game.rng.randf() * TAU
		var s := t.spawn
		var p := Vector2(s.x + cos(a) * 60.0, s.y + sin(a) * 60.0)
		c.global_position = Vector3(p.x, t.height(p.x, p.y) + 0.1, p.y)

	func _init() -> void:
		collision_layer = 4
		collision_mask = 1
		add_to_group("enemies")

	func _ready() -> void:
		var st := MeshKit.begin()
		var green := Color(0.28, 0.62, 0.25)
		MeshKit.box(st, Transform3D(Basis(), Vector3(0, 0.55, 0)), Vector3(0.5, 1.1, 0.5), green)
		MeshKit.box(st, Transform3D(Basis(), Vector3(0, 1.35, 0)), Vector3(0.5, 0.5, 0.5), green * 1.1)
		for f in [[-0.12, 1.42], [0.12, 1.42]]:
			MeshKit.box(st, Transform3D(Basis(), Vector3(f[0], f[1], -0.26)), Vector3(0.1, 0.1, 0.02), Color(0.05, 0.1, 0.05))
		MeshKit.box(st, Transform3D(Basis(), Vector3(0, 1.28, -0.26)), Vector3(0.08, 0.16, 0.02), Color(0.05, 0.1, 0.05))
		var mi := MeshInstance3D.new()
		mi.mesh = MeshKit.commit(st, MeshKit.mat_vcol())
		_mat = StandardMaterial3D.new()
		_mat.vertex_color_use_as_albedo = true
		mi.material_override = _mat
		add_child(mi)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(0.6, 1.7, 0.6)
		shape.shape = box
		shape.position = Vector3(0, 0.85, 0)
		add_child(shape)

	func _physics_process(delta: float) -> void:
		var gp := global_position
		var to_p := player.global_position - gp
		var d := Vector2(to_p.x, to_p.z).length()
		if _fuse >= 0.0:
			_fuse -= delta
			_mat.albedo_color = Color(3, 3, 3) if fmod(_fuse, 0.24) < 0.12 else Color(1, 1, 1)
			if _fuse <= 0.0:
				var fx: FxPool = get_tree().get_first_node_in_group("fx")
				if fx:
					fx.explosion(gp + Vector3(0, 0.8, 0), true, player.global_position)
				if player.has_method("take_damage") and d < 9.0:
					player.take_damage(20.0, gp)
				queue_free()
			return
		if d < 60.0:
			look_at(Vector3(player.global_position.x, gp.y, player.global_position.z), Vector3.UP, true)
			var dir := Vector3(to_p.x, 0, to_p.z).normalized()
			var ty := terrain.height(gp.x, gp.z) + 0.05
			velocity = dir * 3.4 + Vector3(0, clampf((ty - gp.y) / delta, -10, 10), 0)
			move_and_slide()
		if d < 6.0:
			_fuse = 1.5
			Sfx.play_at("static_loop", gp, 2.0, 2.2, 60.0)  # the hiss
			Sfx.vo("vo_creeper", 2, 60.0)

	func take_damage(_a: float, at: Vector3) -> void:
		Sfx.play_at("hit", at, -8.0)
		var fx: FxPool = get_tree().get_first_node_in_group("fx")
		if fx:
			fx.debris_burst(global_position + Vector3(0, 1, 0), 5, Color(0.3, 0.6, 0.3))
		queue_free()


# ============================================================ Giant baby
# The apex predator of the baby-room level. Wanders. Squashes. Giggles.
# Attackable like any other enemy_light.gd body (hp/take_damage/"enemies"
# group) — was pure decoration with no collider at all, so shells/rockets/MG
# had nothing to raycast against and it never took damage.
class GiantBaby:
	extends CharacterBody3D

	var terrain: Terrain
	var player: Node3D
	var hp := 1.0
	var _step_t := 0.0
	var _wander := Vector2.ZERO
	var _retarget := 6.0
	var _legs: Array = []
	var _phase := 0.0
	var _dead := false

	static func spawn(parent: Node3D, t: Terrain, pl: Node3D) -> GiantBaby:
		var b := GiantBaby.new()
		b.terrain = t
		b.player = pl
		parent.add_child(b)
		b.global_position = Vector3(60, 0, -60)
		return b

	func _init() -> void:
		collision_layer = 4
		collision_mask = 1
		add_to_group("enemies")

	func _ready() -> void:
		hp = Tune.v("baby_hp")
		var skin := Color(0.95, 0.78, 0.65)
		var onesie := Color(0.65, 0.8, 0.95)
		var st := MeshKit.begin()
		MeshKit.cyl(st, Transform3D(Basis(), Vector3(0, 26.0, 0)), 11.0, 9.0, 20.0, 12, onesie)
		MeshKit.cyl(st, Transform3D(Basis(), Vector3(0, 42.0, 0)), 8.0, 7.5, 13.0, 12, skin)
		# face
		for e in [[-2.6, 44.0], [2.6, 44.0]]:
			MeshKit.box(st, Transform3D(Basis(), Vector3(e[0], e[1], -7.2)), Vector3(1.2, 1.6, 0.4), Color(0.15, 0.12, 0.1))
		MeshKit.box(st, Transform3D(Basis(), Vector3(0, 40.5, -7.4)), Vector3(3.2, 0.8, 0.4), Color(0.7, 0.35, 0.3))
		MeshKit.cyl(st, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(90)), Vector3(0, 47.5, -3.0)), 0.6, 0.4, 4.0, 6, Color(0.5, 0.35, 0.25))
		# arms
		for sx in [-1.0, 1.0]:
			MeshKit.cyl(st, Transform3D(Basis(Vector3.BACK, sx * deg_to_rad(30)), Vector3(sx * 11.0, 30.0, 0)), 2.6, 2.2, 12.0, 8, skin)
		var body := MeshInstance3D.new()
		body.mesh = MeshKit.commit(st, MeshKit.mat_vcol(0.85))
		add_child(body)
		for sx in [-1.0, 1.0]:
			var leg := Node3D.new()
			leg.position = Vector3(sx * 5.0, 16.0, 0)
			var lst := MeshKit.begin()
			MeshKit.cyl(lst, Transform3D(Basis(), Vector3(0, -8.0, 0)), 3.4, 3.0, 16.0, 10, skin)
			MeshKit.box(lst, Transform3D(Basis(), Vector3(0, -16.5, -1.8)), Vector3(6.0, 2.6, 9.5), skin)
			var lm := MeshInstance3D.new()
			lm.mesh = MeshKit.commit(lst, MeshKit.mat_vcol(0.85))
			leg.add_child(lm)
			add_child(leg)
			_legs.append(leg)
		# single tall capsule for the whole body — good enough for a
		# stationary-ish 50m target, matches the "one hitbox" idiom the
		# other light enemies use for their whole mesh
		var shape := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = 9.0
		cap.height = 44.0
		shape.shape = cap
		shape.position = Vector3(0, 24.0, 0)
		add_child(shape)
		_pick_wander()

	func _pick_wander() -> void:
		_wander = Vector2(Game.rng.randf_range(-70, 70), Game.rng.randf_range(-70, 70))
		_retarget = Game.rng.randf_range(8.0, 16.0)

	func _process(delta: float) -> void:
		if _dead:
			return
		_retarget -= delta
		if _retarget <= 0.0:
			_pick_wander()
		var gp := global_position
		var to := Vector3(_wander.x - gp.x, 0, _wander.y - gp.y)
		if to.length() > 3.0:
			var dir := to.normalized()
			var spd := Tune.v("baby_speed")
			global_position += dir * spd * delta
			look_at(gp + dir, Vector3.UP, true)
			_phase += delta * 2.2
			for i in _legs.size():
				_legs[i].position.z = sin(_phase + i * PI) * 3.0
				_legs[i].position.y = 16.0 + maxf(0.0, sin(_phase + i * PI)) * 2.2
			# footfalls: BOOM boom, haptics, dust, squash check
			_step_t -= delta
			if _step_t <= 0.0:
				_step_t = 1.45
				_stomp()
		global_position.y = terrain.height(global_position.x, global_position.z)

	func _stomp() -> void:
		var gp := global_position
		Sfx.play_at("thud", gp, 8.0, 0.6, 500.0)
		var fx: FxPool = get_tree().get_first_node_in_group("fx")
		if fx:
			fx.dust(gp + Vector3(Game.rng.randf_range(-4, 4), 1.0, Game.rng.randf_range(-4, 4)), 3.0)
			fx.shockwave(gp, 1.4)
		var d := gp.distance_to(player.global_position)
		if player.has_method("_rumble"):
			player._rumble(clampf(1.0 - d / 120.0, 0.1, 1.0), 0.15)
		if d < 12.0 and player.has_method("take_damage"):
			player.take_damage(Tune.v("baby_step_dmg"), gp)
			Sfx.play_at("char_baby_2", gp + Vector3(0, 40, 0), 8.0, 1.0, 400.0)
		elif Game.rng.randf() < 0.25:
			Sfx.play_at("char_baby_%d" % (1 + Game.rng.randi() % 3), gp + Vector3(0, 40, 0), 6.0, 1.0, 400.0)

	func take_damage(amount: float, at: Vector3) -> void:
		if _dead:
			return
		hp -= amount
		Sfx.play_at("hit", at, -4.0)
		var fx: FxPool = get_tree().get_first_node_in_group("fx")
		if fx:
			fx.debris_burst(at, 3, Color(0.9, 0.8, 0.7))
		if hp <= 0.0:
			_die()

	func _die() -> void:
		_dead = true
		remove_from_group("enemies")
		collision_layer = 0
		Sfx.play_at("char_baby_1", global_position + Vector3(0, 40, 0), 8.0, 0.6, 400.0)
		Sfx.vo("vo_kill", 1, 10.0)
		var fx: FxPool = get_tree().get_first_node_in_group("fx")
		if fx:
			fx.explosion(global_position + Vector3(0, 8, 0), false, player.global_position)
			fx.dust(global_position + Vector3(0, 2, 0), 6.0)
			fx.shockwave(global_position, 3.0)
		Sfx.play_at("thud", global_position, 10.0, 0.4, 600.0)
		Game.add_score(300)
		# topple and go still — same "one big fall" beat as the tank's
		# turret pop, scaled to a giant: tips onto its back over ~1s, then
		# a ground-shake thud when it lands
		var tw := create_tween()
		tw.tween_property(self, "rotation:x", -PI / 2.0, 1.0).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_callback(func():
			var lf: FxPool = get_tree().get_first_node_in_group("fx")
			if lf:
				lf.shockwave(global_position, 4.0)
				lf.dust(global_position + Vector3(0, 1, 0), 8.0)
			Sfx.play_at("thud", global_position, 10.0, 0.3, 600.0))

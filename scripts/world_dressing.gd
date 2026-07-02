# Level dressing, parameterized by the Levels config: vegetation/rocks
# (MultiMesh), village, city blocks, castle, mud pools, berms, wrecks.
class_name WorldDressing
extends Node3D

var terrain: Terrain
var cfg: Dictionary

func _init(t: Terrain) -> void:
	terrain = t
	cfg = t.cfg
	name = "WorldDressing"

func _ready() -> void:
	Levels.mud_pools = cfg.get("mud", [])
	if cfg.get("trees", 0) > 0:
		_scatter_trees(cfg["trees"])
	if cfg.get("rocks", 0) > 0:
		_scatter_rocks(cfg["rocks"])
	var vil: Dictionary = cfg.get("village", {})
	if not vil.is_empty():
		_build_village(vil)
	var city: Dictionary = cfg.get("city", {})
	if not city.is_empty():
		_build_city(city)
	var cas: Dictionary = cfg.get("castle", {})
	if not cas.is_empty():
		_build_castle(cas["center"])
	if not Levels.mud_pools.is_empty():
		_build_mud()
	_build_wrecks(cfg.get("wrecks", 3))

func _avoid(p: Vector2, margin := 0.0) -> bool:
	# true if p is inside a reserved gameplay area
	if p.distance_to(terrain.spawn) < 50.0 + margin: return true
	var vil: Dictionary = cfg.get("village", {})
	if not vil.is_empty() and p.distance_to(vil["center"]) < vil["spread"] + 12.0 + margin: return true
	var city: Dictionary = cfg.get("city", {})
	if not city.is_empty():
		var half: float = (maxf(city["rows"], city["cols"]) * city["spacing"]) * 0.5 + 14.0
		if p.distance_to(city["center"]) < half + margin: return true
	var cas: Dictionary = cfg.get("castle", {})
	if not cas.is_empty() and p.distance_to(cas["center"]) < 78.0 + margin: return true
	if cfg.get("pond", false) and p.distance_to(Terrain.POND_CENTER) < 40.0 + margin: return true
	for mp in Levels.mud_pools:
		if p.distance_to(mp) < 34.0 + margin: return true
	return false

func _tree_mesh() -> ArrayMesh:
	var st := MeshKit.begin()
	var trunk := Color(0.28, 0.19, 0.11)
	MeshKit.cyl(st, Transform3D(Basis(), Vector3(0, 1.1, 0)), 0.22, 0.16, 2.2, 6, trunk, false, false)
	var g1 := Color(0.10, 0.22, 0.09)
	var g2 := Color(0.14, 0.28, 0.12)
	MeshKit.cyl(st, Transform3D(Basis(), Vector3(0, 3.0, 0)), 1.7, 0.0, 2.8, 7, g1, true, false)
	MeshKit.cyl(st, Transform3D(Basis(), Vector3(0, 4.8, 0)), 1.15, 0.0, 2.2, 7, g2, true, false)
	return MeshKit.commit(st, MeshKit.mat_vcol())

func _scatter_trees(count: int) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _tree_mesh()
	var placed: Array[Transform3D] = []
	var cols: Array[Color] = []
	var rng := RandomNumberGenerator.new()
	rng.seed = 314
	var tries := 0
	while placed.size() < count and tries < count * 22:
		tries += 1
		var x := rng.randf_range(-210.0, 210.0)
		var z := rng.randf_range(-210.0, 110.0)
		var p := Vector2(x, z)
		if _avoid(p) or p.length() > 205.0: continue
		var h := terrain.height(x, z)
		if h < 0.2 or h > 13.0: continue
		if terrain.normal(x, z).y < 0.86: continue
		var s := rng.randf_range(0.8, 1.6)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.9, 1.25), s))
		placed.append(Transform3D(basis, Vector3(x, h - 0.1, z)))
		cols.append(Color(0.75, 0.8, 0.7).lerp(Color(1.05, 1.1, 0.95), rng.randf()))
	mm.instance_count = placed.size()
	for i in placed.size():
		mm.set_instance_transform(i, placed[i])
		mm.set_instance_color(i, cols[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)

func _rock_mesh() -> ArrayMesh:
	var st := MeshKit.begin()
	var c := Color(0.52, 0.50, 0.47)
	MeshKit.box(st, Transform3D(Basis(Vector3.UP, 0.5), Vector3.ZERO), Vector3(1.6, 1.0, 1.3), c)
	MeshKit.box(st, Transform3D(Basis(Vector3.UP, 1.3).rotated(Vector3.RIGHT, 0.3), Vector3(0.4, 0.3, 0)), Vector3(1.1, 1.1, 1.0), c * 1.1)
	MeshKit.box(st, Transform3D(Basis(Vector3.UP, 2.2).rotated(Vector3.FORWARD, 0.25), Vector3(-0.45, 0.1, 0.2)), Vector3(1.0, 0.7, 1.2), c * 0.9)
	return MeshKit.commit(st, MeshKit.mat_vcol())

func _scatter_rocks(count: int) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _rock_mesh()
	var rng := RandomNumberGenerator.new()
	rng.seed = 217
	var placed: Array[Transform3D] = []
	var cols: Array[Color] = []
	var big: Array[Vector3] = []
	var big_scale: Array[float] = []
	var tries := 0
	while placed.size() < count and tries < count * 30:
		tries += 1
		var x := rng.randf_range(-215.0, 215.0)
		var z := rng.randf_range(-215.0, 215.0)
		var p := Vector2(x, z)
		if _avoid(p) or p.length() > 220.0: continue
		var h := terrain.height(x, z)
		if h < -0.5: continue
		var s := rng.randf_range(0.5, 3.4)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.6, 1.0), s))
		placed.append(Transform3D(basis, Vector3(x, h + 0.1, z)))
		var tint := rng.randf_range(0.75, 1.15)
		cols.append(Color(tint, tint, tint * rng.randf_range(0.92, 1.0)))
		if s > 2.2:
			big.append(Vector3(x, h + 0.5, z))
			big_scale.append(s)
	mm.instance_count = placed.size()
	for i in placed.size():
		mm.set_instance_transform(i, placed[i])
		mm.set_instance_color(i, cols[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	for i in big.size():
		MeshKit.add_static_box_collider(self, big[i], Vector3(1.9, 1.4, 1.6) * big_scale[i])

func _building(x: float, z: float, w: float, d: float, hgt: float, yaw: float,
		mat_wall: Material, mat_roof: Material, rng: RandomNumberGenerator, tall := false) -> void:
	var gy := terrain.height(x, z)
	var b := Node3D.new()
	b.position = Vector3(x, gy, z)
	b.rotation.y = yaw
	add_child(b)
	var st := MeshKit.begin()
	MeshKit.box(st, Transform3D(Basis(), Vector3(0, hgt / 2.0, 0)), Vector3(w, hgt, d), Color.WHITE,
		0.12 if tall else -1.0)
	var walls := MeshInstance3D.new()
	walls.mesh = MeshKit.commit(st, mat_wall)
	b.add_child(walls)
	var st2 := MeshKit.begin()
	if tall:
		MeshKit.box(st2, Transform3D(Basis(), Vector3(0, hgt + 0.25, 0)), Vector3(w + 0.5, 0.5, d + 0.5),
			Color(0.55, 0.52, 0.5))
	else:
		MeshKit.prism(st2, Transform3D(Basis(), Vector3(0, hgt, 0)), w + 0.7, d + 0.7,
			rng.randf_range(1.0, 1.6), Color(1, 1, 1).lerp(Color(0.85, 0.75, 0.7), rng.randf()))
	var roof := MeshInstance3D.new()
	roof.mesh = MeshKit.commit(st2, mat_roof)
	b.add_child(roof)
	MeshKit.add_static_box_collider(self, Vector3(x, gy + hgt / 2.0, z), Vector3(w, hgt, d), yaw)

func _build_village(vil: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var vc: Vector2 = vil["center"]
	var mat_wall := MeshKit.mat_tex("res://assets/tex/building.png")
	var mat_roof := MeshKit.mat_tex("res://assets/tex/roof.png", true)
	var count: int = vil["count"]
	for i in count:
		var ang := TAU * i / count + rng.randf_range(-0.18, 0.18)
		var rad := rng.randf_range(12.0, vil["spread"])
		_building(vc.x + cos(ang) * rad, vc.y + sin(ang) * rad,
			rng.randf_range(4.5, 7.5), rng.randf_range(4.0, 6.0), rng.randf_range(2.8, 3.9),
			rng.randf() * TAU, mat_wall, mat_roof, rng)
	# well
	var st3 := MeshKit.begin()
	MeshKit.cyl(st3, Transform3D(Basis(), Vector3(0, 0.5, 0)), 1.2, 1.2, 1.0, 10, Color(0.55, 0.53, 0.5), false, false)
	MeshKit.cyl(st3, Transform3D(Basis(), Vector3(0, 2.2, 0)), 0.08, 0.08, 2.4, 5, Color(0.4, 0.3, 0.2))
	var wy := terrain.height(vc.x, vc.y)
	var well := MeshInstance3D.new()
	well.mesh = MeshKit.commit(st3, MeshKit.mat_vcol())
	well.position = Vector3(vc.x, wy, vc.y)
	add_child(well)
	MeshKit.add_static_box_collider(self, Vector3(vc.x, wy + 0.5, vc.y), Vector3(2.4, 1.2, 2.4))

func _build_city(city: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 88
	var c: Vector2 = city["center"]
	var rows: int = city["rows"]
	var cols: int = city["cols"]
	var sp: float = city["spacing"]
	var mat_wall := MeshKit.mat_tex("res://assets/tex/building.png")
	var mat_roof := MeshKit.mat_vcol(0.9)
	for r in rows:
		for q in cols:
			if rng.randf() < 0.12:
				continue  # empty lot
			var x := c.x + (q - (cols - 1) / 2.0) * sp + rng.randf_range(-2, 2)
			var z := c.y + (r - (rows - 1) / 2.0) * sp + rng.randf_range(-2, 2)
			var hgt := rng.randf_range(city["h_min"], city["h_max"])
			var w: float = sp - city["street"] + rng.randf_range(-2, 2)
			_building(x, z, w, w * rng.randf_range(0.8, 1.0), hgt, 0.0, mat_wall, mat_roof, rng, true)

func _build_mud() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.23, 0.16, 0.11)
	mat.roughness = 0.25
	mat.metallic = 0.1
	for mp in Levels.mud_pools:
		var mi := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = Levels.mud_radius
		cyl.bottom_radius = Levels.mud_radius
		cyl.height = 0.12
		cyl.radial_segments = 20
		mi.mesh = cyl
		mi.material_override = mat
		var h := terrain.height(mp.x, mp.y)
		mi.position = Vector3(mp.x, h + 0.25, mp.y)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	# berm ring around the pit
	var rng := RandomNumberGenerator.new()
	rng.seed = 55
	var st := MeshKit.begin()
	for i in 26:
		var a := TAU * i / 26.0
		var r := 118.0 + rng.randf_range(-6, 6)
		var x := cos(a) * r
		var z := sin(a) * r
		var h := terrain.height(x, z)
		MeshKit.box(st, Transform3D(Basis(Vector3.UP, a + rng.randf_range(-0.2, 0.2)), Vector3(x, h + 0.8, z)),
			Vector3(rng.randf_range(8, 14), rng.randf_range(1.6, 2.6), 4.0), Color(0.35, 0.27, 0.2))
	var mi := MeshInstance3D.new()
	mi.mesh = MeshKit.commit(st, MeshKit.mat_vcol())
	add_child(mi)

func _build_castle(center: Vector2) -> void:
	var cy := terrain.height(center.x, center.y)
	var root := Node3D.new()
	root.position = Vector3(center.x, cy, center.y)
	add_child(root)
	var stone := MeshKit.mat_tex("res://assets/tex/rock.png", true, 0.95)
	const W := 62.0   # wall half-extent
	const SEG := 10   # segments per side
	# walls (destructible segments), gate gap on south side center
	for side in 4:
		for s in SEG:
			if side == 2 and (s == 4 or s == 5):
				continue  # gate opening (south)
			var frac := (s + 0.5) / SEG
			var pos: Vector3
			var yaw := 0.0
			match side:
				0: pos = Vector3(-W + frac * 2 * W, 0, -W)
				1: pos = Vector3(W, 0, -W + frac * 2 * W); yaw = PI / 2
				2: pos = Vector3(-W + frac * 2 * W, 0, W)
				3: pos = Vector3(-W, 0, -W + frac * 2 * W); yaw = PI / 2
			var wall := CastleWall.new(stone, 2 * W / SEG)
			wall.position = pos
			wall.rotation.y = yaw
			root.add_child(wall)
	# corner towers
	for corner in [Vector3(-W, 0, -W), Vector3(W, 0, -W), Vector3(W, 0, W), Vector3(-W, 0, W)]:
		var st := MeshKit.begin()
		MeshKit.cyl(st, Transform3D(Basis(), Vector3(0, 4.5, 0)), 4.2, 3.8, 9.0, 10, Color(0.75, 0.73, 0.70))
		for i in 8:
			var a := TAU * i / 8.0
			MeshKit.box(st, Transform3D(Basis(), Vector3(cos(a) * 3.6, 9.6, sin(a) * 3.6)), Vector3(1.2, 1.2, 1.2), Color(0.7, 0.68, 0.65))
		var mi := MeshInstance3D.new()
		mi.mesh = MeshKit.commit(st, stone)
		mi.position = corner
		root.add_child(mi)
		MeshKit.add_static_box_collider(root, corner + Vector3(0, 4.5, 0), Vector3(8.0, 9.0, 8.0))
	# central keep + banner
	var st := MeshKit.begin()
	MeshKit.box(st, Transform3D(Basis(), Vector3(0, 5.5, 0)), Vector3(14, 11, 14), Color(0.78, 0.76, 0.72), 0.1)
	MeshKit.prism(st, Transform3D(Basis(), Vector3(0, 11, 0)), 15.0, 15.0, 3.0, Color(0.5, 0.3, 0.25))
	MeshKit.cyl(st, Transform3D(Basis(), Vector3(0, 15.5, 0)), 0.12, 0.1, 6.0, 6, Color(0.4, 0.35, 0.3))
	MeshKit.box(st, Transform3D(Basis(), Vector3(1.1, 17.6, 0)), Vector3(2.2, 1.3, 0.06), Color(0.85, 0.25, 0.2))
	var keep := MeshInstance3D.new()
	keep.mesh = MeshKit.commit(st, stone)
	root.add_child(keep)
	MeshKit.add_static_box_collider(root, Vector3(0, 5.5, 0), Vector3(14, 11, 14))

func _build_wrecks(count: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var dark := Color(0.16, 0.15, 0.14)
	var rust := Color(0.35, 0.22, 0.14)
	for i in count:
		var x := rng.randf_range(-150.0, 150.0)
		var z := rng.randf_range(-150.0, 150.0)
		if _avoid(Vector2(x, z), 6.0): continue
		var h := terrain.height(x, z)
		var st := MeshKit.begin()
		MeshKit.box(st, Transform3D(Basis(), Vector3(0, 0.65, 0)), Vector3(3.2, 0.9, 6.4), dark)
		MeshKit.box(st, Transform3D(Basis(Vector3.UP, rng.randf_range(-0.8, 0.8)), Vector3(0.3, 1.35, 0.4)), Vector3(2.0, 0.7, 2.4), rust)
		MeshKit.cyl(st, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(75.0)), Vector3(0.3, 1.5, -2.2)), 0.09, 0.07, 3.4, 6, dark)
		var mi := MeshInstance3D.new()
		mi.mesh = MeshKit.commit(st, MeshKit.mat_vcol())
		mi.position = Vector3(x, h, z)
		mi.rotation = Vector3(rng.randf_range(-0.06, 0.06), rng.randf() * TAU, rng.randf_range(-0.1, 0.1))
		add_child(mi)
		MeshKit.add_static_box_collider(self, Vector3(x, h + 0.8, z), Vector3(3.4, 1.6, 6.6), mi.rotation.y)

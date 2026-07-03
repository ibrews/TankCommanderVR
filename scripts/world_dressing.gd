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
	Levels.cardboard = cfg.get("cardboard", false)
	Levels.army_green = cfg.get("army_green", false)
	if cfg.get("gym", false):
		_build_gym()
	if cfg.get("palms", 0) > 0:
		_scatter_palms(cfg["palms"])
	if cfg.get("coast", false) or cfg.get("island", false):
		_build_sea()
	if cfg.get("coast", false):
		_build_beach_props()
	if cfg.get("volcano", false):
		_build_lava()
	if cfg.get("babyroom", false):
		_build_babyroom()
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

func _ground_min(x: float, z: float, r: float) -> float:
	# Lowest terrain point under a footprint of radius r. Instances must sink
	# to this, not the center sample — on slopes the downhill edge floats
	# otherwise (v0.5.0 headset bug: floating trees/props on coast + hills).
	var h := terrain.height(x, z)
	h = minf(h, terrain.height(x + r, z))
	h = minf(h, terrain.height(x - r, z))
	h = minf(h, terrain.height(x, z + r))
	h = minf(h, terrain.height(x, z - r))
	return h

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
		if terrain.normal(x, z).y < 0.90: continue
		var s := rng.randf_range(0.8, 1.6)
		var basis := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.9, 1.25), s))
		var gy := _ground_min(x, z, 0.3 * s)
		placed.append(Transform3D(basis, Vector3(x, gy - 0.12 * s, z)))
		cols.append(Color(0.75, 0.8, 0.7).lerp(Color(1.05, 1.1, 0.95), rng.randf()))
	mm.instance_count = placed.size()
	for i in placed.size():
		mm.set_instance_transform(i, placed[i])
		mm.set_instance_color(i, cols[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Trees"
	mmi.set_meta("xforms", placed)
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
		var gy := _ground_min(x, z, 0.7 * s)
		placed.append(Transform3D(basis, Vector3(x, gy, z)))
		var tint := rng.randf_range(0.75, 1.15)
		cols.append(Color(tint, tint, tint * rng.randf_range(0.92, 1.0)))
		if s > 2.2:
			big.append(Vector3(x, gy + 0.5, z))
			big_scale.append(s)
	mm.instance_count = placed.size()
	for i in placed.size():
		mm.set_instance_transform(i, placed[i])
		mm.set_instance_color(i, cols[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Rocks"
	mmi.set_meta("xforms", placed)
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)
	for i in big.size():
		MeshKit.add_static_box_collider(self, big[i], Vector3(1.9, 1.4, 1.6) * big_scale[i])

func _building(x: float, z: float, w: float, d: float, hgt: float, yaw: float,
		mat_wall: Material, mat_roof: Material, rng: RandomNumberGenerator, tall := false) -> void:
	# foundation at the LOWEST of the 4 corners, sunk slightly — a center
	# sample leaves the downhill corner hanging in the air on any slope
	var gy := terrain.height(x, z)
	var ca := cos(yaw)
	var sa := sin(yaw)
	for cx in [-0.5, 0.5]:
		for cz in [-0.5, 0.5]:
			var lx: float = cx * w
			var lz: float = cz * d
			gy = minf(gy, terrain.height(x + lx * ca + lz * sa, z - lx * sa + lz * ca))
	gy -= 0.12
	var b := Node3D.new()
	b.name = "Building"
	b.set_meta("cat", "building")
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
	var wy := _ground_min(vc.x, vc.y, 1.2) - 0.08
	var well := MeshInstance3D.new()
	well.name = "Well"
	well.set_meta("cat", "prop")
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
		var yawb := a + rng.randf_range(-0.2, 0.2)
		var blen := rng.randf_range(8, 14)
		var bh := rng.randf_range(1.6, 2.6)
		# berm boxes are long — sample both ends so neither hangs over a dip
		var ex := cos(yawb) * blen * 0.5
		var ez := -sin(yawb) * blen * 0.5
		var gy := minf(terrain.height(x, z), minf(terrain.height(x + ex, z + ez), terrain.height(x - ex, z - ez)))
		MeshKit.box(st, Transform3D(Basis(Vector3.UP, yawb), Vector3(x, gy + bh * 0.5 - 0.5, z)),
			Vector3(blen, bh, 4.0), Color(0.35, 0.27, 0.2))
	var mi := MeshInstance3D.new()
	mi.mesh = MeshKit.commit(st, MeshKit.mat_vcol())
	add_child(mi)

func _build_castle(center: Vector2) -> void:
	var cy := terrain.height(center.x, center.y)
	var root := Node3D.new()
	root.name = "Castle"
	root.set_meta("cat", "castle")
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
			# conform each segment to the terrain under it (walls step with
			# the ground like real fortifications; center-height left segments
			# floating over dips 60+ m from the castle center) — sample both
			# segment ends too, the ground can dip within one 12 m span
			var ex := W / SEG if yaw == 0.0 else 0.0
			var ez := 0.0 if yaw == 0.0 else W / SEG
			var wg := terrain.height(center.x + pos.x, center.y + pos.z)
			wg = minf(wg, terrain.height(center.x + pos.x + ex, center.y + pos.z + ez))
			wg = minf(wg, terrain.height(center.x + pos.x - ex, center.y + pos.z - ez))
			wall.position.y = wg - cy - 0.35
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
		var ty := _ground_min(center.x + corner.x, center.y + corner.z, 3.8) - cy - 0.4
		mi.position = Vector3(corner.x, ty, corner.z)
		root.add_child(mi)
		MeshKit.add_static_box_collider(root, Vector3(corner.x, ty + 4.5, corner.z), Vector3(8.0, 9.0, 8.0))
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

# A giant school gymnasium: court floor (terrain texture), padded walls,
# bleachers, basketball hoops, roof trusses, cardboard forts, bouncy balls.
func _build_gym() -> void:
	var W := 118.0
	var wall_mat := MeshKit.mat_vcol(0.9)
	var card := MeshKit.mat_tex("res://assets/tex/cardboard.png", true, 0.95)
	var st := MeshKit.begin()
	var wall_col := Color(0.82, 0.78, 0.70)
	var pad_col := Color(0.25, 0.35, 0.65)
	for side in 4:
		var yaw := side * PI / 2.0
		var b := Basis(Vector3.UP, yaw)
		# wall slab + padded lower stripe + high windows
		MeshKit.box(st, Transform3D(b, b * Vector3(0, 14.0, -W)), Vector3(2 * W + 8, 28.0, 1.5), wall_col)
		MeshKit.box(st, Transform3D(b, b * Vector3(0, 2.2, -W + 0.9)), Vector3(2 * W + 6, 4.4, 0.4), pad_col)
		for i in 9:
			MeshKit.box(st, Transform3D(b, b * Vector3(-W + 24 + i * 24, 21.0, -W + 0.9)), Vector3(10, 6, 0.5), Color(0.65, 0.78, 0.9))
	# roof trusses + hanging lights
	for i in 5:
		var z := -W + 40 + i * 40
		MeshKit.box(st, Transform3D(Basis(), Vector3(0, 27.0, z)), Vector3(2 * W, 1.6, 1.6), Color(0.45, 0.48, 0.52))
		for lx in [-60.0, 0.0, 60.0]:
			MeshKit.box(st, Transform3D(Basis(), Vector3(lx, 24.5, z)), Vector3(3.5, 1.2, 3.5), Color(0.95, 0.93, 0.82))
	var walls := MeshInstance3D.new()
	walls.mesh = MeshKit.commit(st, wall_mat)
	add_child(walls)
	for side in 4:
		var yaw := side * PI / 2.0
		var n := Vector3(0, 0, -1).rotated(Vector3.UP, yaw)
		MeshKit.add_static_box_collider(self, n * W + Vector3(0, 14, 0), Vector3(2 * W + 8, 28, 1.5), yaw)
	# bleachers on east/west
	var bst := MeshKit.begin()
	for side in [-1.0, 1.0]:
		for step in 6:
			MeshKit.box(bst, Transform3D(Basis(), Vector3(side * (W - 8.0 - step * 3.0), 1.5 + step * 1.5, 0)),
				Vector3(3.0, 3.0 + step * 3.0 * 0.0 + 1.5, 150.0), Color(0.75, 0.55, 0.3) if step % 2 == 0 else Color(0.65, 0.47, 0.25))
	var bl := MeshInstance3D.new()
	bl.mesh = MeshKit.commit(bst, wall_mat)
	add_child(bl)
	for side in [-1.0, 1.0]:
		MeshKit.add_static_box_collider(self, Vector3(side * (W - 15.0), 5.0, 0), Vector3(20.0, 10.0, 150.0))
	# hoops north/south
	for side in [-1.0, 1.0]:
		var hst := MeshKit.begin()
		MeshKit.cyl(hst, Transform3D(Basis(), Vector3(0, 6.0, 0)), 0.35, 0.3, 12.0, 8, Color(0.4, 0.42, 0.45))
		MeshKit.box(hst, Transform3D(Basis(), Vector3(0, 11.2, side * 1.2)), Vector3(6.5, 4.0, 0.3), Color(0.92, 0.92, 0.92))
		MeshKit.cyl(hst, Transform3D(Basis(), Vector3(0, 9.6, side * 2.6)), 1.6, 1.6, 0.18, 12, Color(0.9, 0.4, 0.1), false, false)
		var hoop := MeshInstance3D.new()
		hoop.mesh = MeshKit.commit(hst, wall_mat)
		hoop.position = Vector3(0, 0, -side * (W - 18.0))
		add_child(hoop)
		MeshKit.add_static_box_collider(self, hoop.position + Vector3(0, 6, 0), Vector3(1.2, 12.0, 1.2))
	# cardboard forts (cover)
	var rng := RandomNumberGenerator.new()
	rng.seed = 66
	for i in 10:
		var x := rng.randf_range(-80.0, 80.0)
		var z := rng.randf_range(-80.0, 80.0)
		if Vector2(x, z).distance_to(terrain.spawn) < 30.0:
			continue
		var fst := MeshKit.begin()
		for k in rng.randi_range(2, 4):
			var s := rng.randf_range(2.4, 4.5)
			MeshKit.box(fst, Transform3D(Basis(Vector3.UP, rng.randf() * 0.5), Vector3(rng.randf_range(-2, 2), s / 2.0 + k * s * 0.85, rng.randf_range(-2, 2))),
				Vector3(s, s, s), Color.WHITE, -1.0)
		var fort := MeshInstance3D.new()
		fort.name = "Fort"
		fort.set_meta("cat", "prop")
		fort.mesh = MeshKit.commit(fst, card)
		fort.position = Vector3(x, _ground_min(x, z, 2.5) - 0.06, z)
		add_child(fort)
		MeshKit.add_static_box_collider(self, Vector3(x, 4.0, z), Vector3(6.5, 8.0, 6.5))
	# bouncy basketballs
	for i in 3:
		var ball := RigidBody3D.new()
		ball.mass = 14.0
		var pm := PhysicsMaterial.new()
		pm.bounce = 0.75
		pm.friction = 0.6
		ball.physics_material_override = pm
		ball.collision_layer = 1
		ball.collision_mask = 1 | 2 | 4
		var cs := CollisionShape3D.new()
		var sph := SphereShape3D.new()
		sph.radius = 1.5
		cs.shape = sph
		ball.add_child(cs)
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 1.5
		sm.height = 3.0
		sm.radial_segments = 16
		sm.rings = 8
		mi.mesh = sm
		var bm := StandardMaterial3D.new()
		bm.albedo_color = Color(0.85, 0.4, 0.12)
		bm.roughness = 0.7
		mi.material_override = bm
		ball.add_child(mi)
		ball.position = Vector3(-20.0 + i * 20.0, 6.0, 20.0)
		add_child(ball)

func _palm_mesh() -> ArrayMesh:
	var st := MeshKit.begin()
	var trunk := Color(0.45, 0.33, 0.2)
	# gently bent trunk: three tilted segments
	for i in 3:
		MeshKit.cyl(st, Transform3D(Basis(Vector3.RIGHT, 0.1 + i * 0.09),
			Vector3(0, 1.0 + i * 1.9, -0.15 - i * 0.45)), 0.2 - i * 0.04, 0.16 - i * 0.04, 2.0, 6, trunk)
	# fronds
	for k in 6:
		var a := TAU * k / 6.0
		var b := Basis(Vector3.UP, a).rotated(Vector3(cos(a), 0, sin(a)).cross(Vector3.UP).normalized(), -0.5)
		MeshKit.box(st, Transform3D(b, Vector3(cos(a) * 1.1, 6.1, sin(a) * 1.1 - 1.2)),
			Vector3(0.5, 0.05, 2.6), Color(0.15, 0.42, 0.18))
	MeshKit.cyl(st, Transform3D(Basis(), Vector3(0.2, 5.8, -1.2)), 0.14, 0.14, 0.25, 6, Color(0.55, 0.4, 0.15))
	return MeshKit.commit(st, MeshKit.mat_vcol())

func _scatter_palms(count: int) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _palm_mesh()
	var rng := RandomNumberGenerator.new()
	rng.seed = 404
	var placed: Array[Transform3D] = []
	var tries := 0
	while placed.size() < count and tries < count * 30:
		tries += 1
		var x := rng.randf_range(-terrain.arena_radius, terrain.arena_radius)
		var z := rng.randf_range(-terrain.arena_radius, terrain.arena_radius)
		var h := terrain.height(x, z)
		if h < 0.3 or h > 6.0 or _avoid(Vector2(x, z)):
			continue
		if terrain.normal(x, z).y < 0.88:
			continue
		var s := rng.randf_range(0.8, 1.4)
		var gy := _ground_min(x, z, 0.3 * s)
		if gy < 0.15:
			continue   # base would poke out of the waterline
		placed.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s, s)), Vector3(x, gy - 0.15 * s, z)))
	mm.instance_count = placed.size()
	for i in placed.size():
		mm.set_instance_transform(i, placed[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.name = "Palms"
	mmi.set_meta("xforms", placed)
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)

func _build_sea() -> void:
	if OS.get_environment("TC_NO_SEA") != "":
		return   # visual bisection aid
	# Water INSIDE the map is painted into the terrain shader (world-y
	# threshold) — any separate flat plane depth-fights the terrain on the
	# Mobile renderer (verified by bisection; even ArrayMesh quads at y=-3
	# occluded terrain at +1.5). Here we only add a horizon skirt of quads
	# FULLY OUTSIDE the terrain square, where overlap is impossible.
	const CELL := 64.0
	const EXT := 448.0
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cells := 0
	for cz in range(int(-EXT / CELL), int(EXT / CELL)):
		for cx in range(int(-EXT / CELL), int(EXT / CELL)):
			var x0 := cx * CELL
			var z0 := cz * CELL
			if absf(x0 + CELL * 0.5) < Terrain.HALF + CELL * 0.5 					and absf(z0 + CELL * 0.5) < Terrain.HALF + CELL * 0.5:
				continue
			cells += 1
			# Winding was inverted (verified 2026-07-03 by the same
			# geometric-winding-vs-stored-normal audit that caught the
			# MeshKit.cyl() bug — cross product of the original vertex order
			# pointed DOWN, opposite the Vector3.UP stored below; with the
			# engine's default CULL_BACK material, this made the entire sea
			# horizon skirt back-face-culled/invisible from above). Fix:
			# swap the last two vertices of each triangle.
			for v: Vector3 in [
				Vector3(x0, 0, z0), Vector3(x0 + CELL, 0, z0 + CELL), Vector3(x0 + CELL, 0, z0),
				Vector3(x0, 0, z0), Vector3(x0, 0, z0 + CELL), Vector3(x0 + CELL, 0, z0 + CELL)]:
				st.set_normal(Vector3.UP)
				st.add_vertex(v)
	var mi := MeshInstance3D.new()
	mi.name = "Sea"
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.09, 0.30, 0.42)
	m.roughness = 0.25
	m.metallic = 0.2
	mi.material_override = m
	mi.position = Vector3(0, -0.75, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	print("[sea] %d horizon-skirt cells" % cells)

func _build_beach_props() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 88
	var brights := [Color(0.95, 0.35, 0.3), Color(0.3, 0.6, 0.95), Color(0.98, 0.8, 0.2), Color(0.4, 0.85, 0.5)]
	for i in 10:
		var x := rng.randf_range(-150.0, 150.0)
		var z := rng.randf_range(-22.0, 8.0)   # the sand strip by the water
		var h := terrain.height(x, z)
		if h < 0.2 or terrain.normal(x, z).y < 0.85:
			continue
		if _ground_min(x, z, 2.0) < 0.1:
			continue   # towel corner would sit in the water
		var st := MeshKit.begin()
		var col: Color = brights[rng.randi() % brights.size()]
		MeshKit.cyl(st, Transform3D(Basis(), Vector3(0, 1.35, 0)), 0.05, 0.05, 2.8, 6, Color(0.8, 0.8, 0.78))
		MeshKit.cyl(st, Transform3D(Basis(), Vector3(0, 2.7, 0)), 2.2, 0.15, 0.8, 10, col)
		# towel — 1.8 m from the pole, so sample the sand under ITS footprint
		var towel_y := _ground_min(x + 1.8, z + 0.5, 0.9) - h + 0.05
		MeshKit.box(st, Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(1.8, towel_y, 0.5)),
			Vector3(1.2, 0.04, 2.2), brights[(rng.randi() + 1) % brights.size()])
		var mi := MeshInstance3D.new()
		mi.name = "Umbrella"
		mi.set_meta("cat", "umbrella")
		mi.mesh = MeshKit.commit(st, MeshKit.mat_vcol(0.8))
		mi.position = Vector3(x, h, z)
		add_child(mi)

func _build_lava() -> void:
	# quad grid like the sea — giant primitive cylinders render at the wrong
	# height on the Mobile renderer (see _build_sea)
	var ly: float = cfg.get("lava_y", -3.2) - 0.3
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for cz in range(-4, 4):
		for cx in range(-4, 4):
			var x0 := cx * 32.0
			var z0 := cz * 32.0
			var wet := false
			for sz in 5:
				for sx in 5:
					if terrain.height(x0 + sx * 8.0, z0 + sz * 8.0) < ly + 0.5:
						wet = true
						break
				if wet:
					break
			if not wet:
				continue
			# Same inverted-winding bug as _build_sea() (identical copy-pasted
			# quad-triangulation pattern) — same fix, verified the same way.
			for v: Vector3 in [
				Vector3(x0, 0, z0), Vector3(x0 + 32, 0, z0 + 32), Vector3(x0 + 32, 0, z0),
				Vector3(x0, 0, z0), Vector3(x0, 0, z0 + 32), Vector3(x0 + 32, 0, z0 + 32)]:
				st.set_normal(Vector3.UP)
				st.set_uv(Vector2(v.x, v.z) * 0.07)
				st.add_vertex(v)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.9, 0.25, 0.05)
	m.emission_enabled = true
	m.emission = Color(1.0, 0.35, 0.05)
	m.emission_energy_multiplier = 1.6
	m.albedo_texture = load("res://assets/tex/rock.png")
	m.uv1_scale = Vector3(1, 1, 1)   # UVs baked into the quad grid
	mi.material_override = m
	mi.position = Vector3(0, cfg.get("lava_y", -3.2) - 0.3, 0)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.4, 0.1)
	glow.omni_range = 130.0
	glow.light_energy = 0.8
	glow.shadow_enabled = false
	glow.position = Vector3(0, 2.0, 0)
	add_child(glow)
	var fxp: FxPool = get_tree().get_first_node_in_group("fx") if is_inside_tree() else null
	if fxp:
		for p in [Vector3(30, -2, 20), Vector3(-35, -2, -15)]:
			fxp.smoke_column(p, 9999.0)

func _build_babyroom() -> void:
	var W := 118.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 12
	# wallpapered walls + skirting
	var st := MeshKit.begin()
	for side in 4:
		var yaw := side * PI / 2.0
		var b := Basis(Vector3.UP, yaw)
		MeshKit.box(st, Transform3D(b, b * Vector3(0, 20.0, -W)), Vector3(2 * W + 8, 40.0, 1.5), Color.WHITE, -1.0)
		MeshKit.box(st, Transform3D(b, b * Vector3(0, 1.5, -W + 0.9)), Vector3(2 * W + 6, 3.0, 0.4), Color(0.9, 0.88, 0.85))
	var walls := MeshInstance3D.new()
	walls.mesh = MeshKit.commit(st, MeshKit.mat_tex("res://assets/tex/wallpaper.png"))
	add_child(walls)
	for side in 4:
		var yaw := side * PI / 2.0
		var n := Vector3(0, 0, -1).rotated(Vector3.UP, yaw)
		MeshKit.add_static_box_collider(self, n * W + Vector3(0, 20, 0), Vector3(2 * W + 8, 40, 1.5), yaw)
	# giant crib in a corner
	var cst := MeshKit.begin()
	var wood := Color(0.85, 0.82, 0.78)
	for px in [-14.0, 14.0]:
		for pz in [-9.0, 9.0]:
			MeshKit.cyl(cst, Transform3D(Basis(), Vector3(px, 9.0, pz)), 0.8, 0.8, 18.0, 8, wood)
	for i in 12:
		MeshKit.cyl(cst, Transform3D(Basis(), Vector3(-12.0 + i * 2.2, 10.0, -9.0)), 0.3, 0.3, 12.0, 6, wood)
	MeshKit.box(cst, Transform3D(Basis(), Vector3(0, 16.5, 0)), Vector3(30.0, 1.0, 19.5), wood * 0.95)
	var crib := MeshInstance3D.new()
	crib.name = "Crib"
	crib.set_meta("cat", "prop")
	crib.mesh = MeshKit.commit(cst, MeshKit.mat_vcol(0.8))
	var crib_y := minf(minf(terrain.height(-94, -89), terrain.height(-66, -89)),
		minf(terrain.height(-94, -71), terrain.height(-66, -71))) - 0.1
	crib.position = Vector3(-80, crib_y, -80)
	add_child(crib)
	MeshKit.add_static_box_collider(self, Vector3(-80, crib_y + 9, -80), Vector3(30, 18, 20))
	# alphabet blocks + not-lego bricks + books + ball (cover!)
	var brights := [Color(0.9, 0.3, 0.3), Color(0.3, 0.5, 0.9), Color(0.95, 0.8, 0.2), Color(0.4, 0.8, 0.4), Color(0.8, 0.4, 0.9)]
	for i in 7:
		var x := rng.randf_range(-85.0, 85.0)
		var z := rng.randf_range(-85.0, 85.0)
		if Vector2(x, z).distance_to(terrain.spawn) < 25.0:
			continue
		var s := rng.randf_range(4.0, 7.0)
		var col: Color = brights[rng.randi() % brights.size()]
		var bst := MeshKit.begin()
		MeshKit.box(bst, Transform3D(Basis(Vector3.UP, rng.randf() * 0.6), Vector3(0, s / 2, 0)), Vector3(s, s, s), col)
		var bmesh := MeshInstance3D.new()
		bmesh.name = "Block"
		bmesh.set_meta("cat", "prop")
		bmesh.mesh = MeshKit.commit(bst, MeshKit.mat_vcol(0.5))
		bmesh.position = Vector3(x, _ground_min(x, z, s * 0.5) - 0.06, z)
		add_child(bmesh)
		var letter := Label3D.new()
		letter.text = char(65 + rng.randi() % 26)
		letter.font_size = 620
		letter.pixel_size = 0.01
		letter.modulate = Color(1, 1, 1, 0.92)
		letter.position = bmesh.position + Vector3(0, s / 2, -s / 2 - 0.05)
		add_child(letter)
		MeshKit.add_static_box_collider(self, bmesh.position + Vector3(0, s / 2, 0), Vector3(s, s, s))
	for i in 5:
		var x := rng.randf_range(-85.0, 85.0)
		var z := rng.randf_range(-85.0, 85.0)
		if Vector2(x, z).distance_to(terrain.spawn) < 25.0:
			continue
		var col: Color = brights[rng.randi() % brights.size()]
		var lst := MeshKit.begin()
		MeshKit.box(lst, Transform3D(Basis(), Vector3(0, 1.6, 0)), Vector3(8.0, 3.2, 4.0), col)
		for sx in 4:
			for sz in 2:
				MeshKit.cyl(lst, Transform3D(Basis(), Vector3(-3.0 + sx * 2.0, 3.7, -1.0 + sz * 2.0)), 0.8, 0.8, 1.0, 10, col * 1.1)
		var brick := MeshInstance3D.new()
		brick.name = "Brick"
		brick.set_meta("cat", "prop")
		brick.mesh = MeshKit.commit(lst, MeshKit.mat_vcol(0.35))
		brick.position = Vector3(x, _ground_min(x, z, 3.0) - 0.06, z)
		brick.rotation.y = rng.randf() * TAU
		add_child(brick)
		MeshKit.add_static_box_collider(self, brick.position + Vector3(0, 1.6, 0), Vector3(8, 4.4, 4), brick.rotation.y)
	# rubber ball
	var ball := RigidBody3D.new()
	ball.mass = 30.0
	var pmat := PhysicsMaterial.new()
	pmat.bounce = 0.8
	ball.physics_material_override = pmat
	ball.collision_layer = 1
	ball.collision_mask = 1 | 2 | 4
	var cs := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 4.0
	cs.shape = sph
	ball.add_child(cs)
	var bmi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 4.0
	sm.height = 8.0
	bmi.mesh = sm
	var ballmat := StandardMaterial3D.new()
	ballmat.albedo_color = Color(0.9, 0.25, 0.35)
	bmi.material_override = ballmat
	ball.add_child(bmi)
	ball.position = Vector3(30, 8, 30)
	add_child(ball)

func _build_wrecks(count: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var dark := Color(0.16, 0.15, 0.14)
	var rust := Color(0.35, 0.22, 0.14)
	for i in count:
		var x := rng.randf_range(-150.0, 150.0)
		var z := rng.randf_range(-150.0, 150.0)
		if _avoid(Vector2(x, z), 6.0): continue
		if terrain.normal(x, z).y < 0.90: continue
		var yaw := rng.randf() * TAU
		# hull box floor is +0.2 in mesh space — sample the 4 track corners
		# and sink 0.35 below the lowest so tracks bed into the dirt
		var gy := terrain.height(x, z)
		var cw := cos(yaw)
		var sw := sin(yaw)
		for cx in [-1.6, 1.6]:
			for cz in [-3.2, 3.2]:
				gy = minf(gy, terrain.height(x + cx * cw + cz * sw, z - cx * sw + cz * cw))
		gy -= 0.35
		var st := MeshKit.begin()
		MeshKit.box(st, Transform3D(Basis(), Vector3(0, 0.65, 0)), Vector3(3.2, 0.9, 6.4), dark)
		MeshKit.box(st, Transform3D(Basis(Vector3.UP, rng.randf_range(-0.8, 0.8)), Vector3(0.3, 1.35, 0.4)), Vector3(2.0, 0.7, 2.4), rust)
		MeshKit.cyl(st, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(75.0)), Vector3(0.3, 1.5, -2.2)), 0.09, 0.07, 3.4, 6, dark)
		var mi := MeshInstance3D.new()
		mi.name = "Wreck"
		mi.set_meta("cat", "wreck")
		mi.mesh = MeshKit.commit(st, MeshKit.mat_vcol())
		mi.position = Vector3(x, gy, z)
		mi.rotation = Vector3(rng.randf_range(-0.04, 0.04), yaw, rng.randf_range(-0.06, 0.06))
		add_child(mi)
		MeshKit.add_static_box_collider(self, Vector3(x, gy + 0.8, z), Vector3(3.4, 1.6, 6.6), yaw)

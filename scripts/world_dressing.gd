# Scatters vegetation/rocks (MultiMesh, 2 draw calls), builds the village and
# decorative wrecks. Only large objects get colliders (layer 1).
class_name WorldDressing
extends Node3D

var terrain: Terrain

func _init(t: Terrain) -> void:
	terrain = t
	name = "WorldDressing"

func _ready() -> void:
	_scatter_trees()
	_scatter_rocks()
	_build_village()
	_build_wrecks()

func _tree_mesh() -> ArrayMesh:
	var st := MeshKit.begin()
	var trunk := Color(0.28, 0.19, 0.11)
	MeshKit.cyl(st, Transform3D(Basis(), Vector3(0, 1.1, 0)), 0.22, 0.16, 2.2, 6, trunk, false, false)
	var g1 := Color(0.10, 0.22, 0.09)
	var g2 := Color(0.14, 0.28, 0.12)
	MeshKit.cyl(st, Transform3D(Basis(), Vector3(0, 3.0, 0)), 1.7, 0.0, 2.8, 7, g1, true, false)
	MeshKit.cyl(st, Transform3D(Basis(), Vector3(0, 4.8, 0)), 1.15, 0.0, 2.2, 7, g2, true, false)
	return MeshKit.commit(st, MeshKit.mat_vcol())

func _scatter_trees() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _tree_mesh()
	var placed: Array[Transform3D] = []
	var cols: Array[Color] = []
	var rng := Game.rng
	var tries := 0
	while placed.size() < 230 and tries < 4000:
		tries += 1
		var x := rng.randf_range(-210.0, 210.0)
		var z := rng.randf_range(-210.0, 60.0)  # forest belt north/center
		var p := Vector2(x, z)
		if p.distance_to(Terrain.VILLAGE_CENTER) < 66.0: continue
		if p.distance_to(Terrain.POND_CENTER) < 40.0: continue
		if p.distance_to(Terrain.SPAWN_CENTER) < 50.0: continue
		if p.length() > 205.0: continue
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
	# irregular boulder from 3 overlapping boxes
	MeshKit.box(st, Transform3D(Basis(Vector3.UP, 0.5), Vector3.ZERO), Vector3(1.6, 1.0, 1.3), c)
	MeshKit.box(st, Transform3D(Basis(Vector3.UP, 1.3).rotated(Vector3.RIGHT, 0.3), Vector3(0.4, 0.3, 0)), Vector3(1.1, 1.1, 1.0), c * 1.1)
	MeshKit.box(st, Transform3D(Basis(Vector3.UP, 2.2).rotated(Vector3.FORWARD, 0.25), Vector3(-0.45, 0.1, 0.2)), Vector3(1.0, 0.7, 1.2), c * 0.9)
	return MeshKit.commit(st, MeshKit.mat_vcol())

func _scatter_rocks() -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _rock_mesh()
	var rng := Game.rng
	var placed: Array[Transform3D] = []
	var cols: Array[Color] = []
	var big: Array[Vector3] = []
	var big_scale: Array[float] = []
	var tries := 0
	while placed.size() < 90 and tries < 3000:
		tries += 1
		var x := rng.randf_range(-215.0, 215.0)
		var z := rng.randf_range(-215.0, 215.0)
		var p := Vector2(x, z)
		if p.distance_to(Terrain.VILLAGE_CENTER) < 60.0: continue
		if p.distance_to(Terrain.POND_CENTER) < 34.0: continue
		if p.distance_to(Terrain.SPAWN_CENTER) < 46.0: continue
		if p.length() > 220.0: continue
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

func _build_village() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	var vc := Terrain.VILLAGE_CENTER
	var mat_wall := MeshKit.mat_tex("res://assets/tex/building.png")
	var mat_roof := MeshKit.mat_tex("res://assets/tex/roof.png", true)
	for i in 12:
		var ang := TAU * i / 12.0 + rng.randf_range(-0.18, 0.18)
		var rad := rng.randf_range(14.0, 42.0)
		var x := vc.x + cos(ang) * rad
		var z := vc.y + sin(ang) * rad
		var w := rng.randf_range(4.5, 7.5)
		var d := rng.randf_range(4.0, 6.0)
		var hgt := rng.randf_range(2.8, 3.9)
		var yaw := rng.randf() * TAU
		var gy := terrain.height(x, z)
		var b := Node3D.new()
		b.position = Vector3(x, gy, z)
		b.rotation.y = yaw
		add_child(b)
		# walls
		var st := MeshKit.begin()
		MeshKit.box(st, Transform3D(Basis(), Vector3(0, hgt / 2.0, 0)), Vector3(w, hgt, d), Color.WHITE, -1.0)
		var walls := MeshInstance3D.new()
		walls.mesh = MeshKit.commit(st, mat_wall)
		b.add_child(walls)
		# roof
		var st2 := MeshKit.begin()
		MeshKit.prism(st2, Transform3D(Basis(), Vector3(0, hgt, 0)), w + 0.7, d + 0.7, rng.randf_range(1.0, 1.6),
			Color(1, 1, 1).lerp(Color(0.85, 0.75, 0.7), rng.randf()))
		var roof := MeshInstance3D.new()
		roof.mesh = MeshKit.commit(st2, mat_roof)
		b.add_child(roof)
		MeshKit.add_static_box_collider(self, Vector3(x, gy + hgt / 2.0, z), Vector3(w, hgt, d), yaw)
	# well in the middle
	var st3 := MeshKit.begin()
	MeshKit.cyl(st3, Transform3D(Basis(), Vector3(0, 0.5, 0)), 1.2, 1.2, 1.0, 10, Color(0.55, 0.53, 0.5), false, false)
	MeshKit.cyl(st3, Transform3D(Basis(), Vector3(0, 2.2, 0)), 0.08, 0.08, 2.4, 5, Color(0.4, 0.3, 0.2))
	var wy := terrain.height(vc.x, vc.y)
	var well := MeshInstance3D.new()
	well.mesh = MeshKit.commit(st3, MeshKit.mat_vcol())
	well.position = Vector3(vc.x, wy, vc.y)
	add_child(well)
	MeshKit.add_static_box_collider(self, Vector3(vc.x, wy + 0.5, vc.y), Vector3(2.4, 1.2, 2.4))

func _build_wrecks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var dark := Color(0.16, 0.15, 0.14)
	var rust := Color(0.35, 0.22, 0.14)
	for i in 3:
		var x := rng.randf_range(-140.0, 140.0)
		var z := rng.randf_range(-140.0, 140.0)
		if Vector2(x, z).distance_to(Terrain.SPAWN_CENTER) < 55.0: continue
		if Vector2(x, z).distance_to(Terrain.VILLAGE_CENTER) < 60.0: continue
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

# Static helpers for building merged ArrayMeshes out of primitive parts.
# Everything gets vertex colors so one vertex-color material can draw a whole
# merged mesh in a single draw call (Quest draw-call budget).
class_name MeshKit
extends Object

static var _mat_cache := {}

static func begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st

# Axis-aligned box in local space, transformed by tf. uv_scale <= 0 -> 0..1 per face.
static func box(st: SurfaceTool, tf: Transform3D, size: Vector3, col: Color, uv_scale := 0.35) -> void:
	var h := size * 0.5
	# faces: +X -X +Y -Y +Z -Z ; each as (normal, u_axis, v_axis)
	var faces := [
		[Vector3(1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0)],
		[Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)],
		[Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, -1)],
		[Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)],
		[Vector3(0, 0, 1), Vector3(1, 0, 0), Vector3(0, 1, 0)],
		[Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0)],
	]
	for f in faces:
		var nrm: Vector3 = f[0]
		var ua: Vector3 = f[1]
		var va: Vector3 = f[2]
		var c := Vector3(nrm.x * h.x, nrm.y * h.y, nrm.z * h.z)
		var ue := ua * Vector3(h.x * absf(ua.x), h.y * absf(ua.y), h.z * absf(ua.z)).length()
		var ve := va * Vector3(h.x * absf(va.x), h.y * absf(va.y), h.z * absf(va.z)).length()
		var u_len := ue.length()
		var v_len := ve.length()
		var corners := [c - ue - ve, c + ue - ve, c + ue + ve, c - ue + ve]
		var uvs: Array
		if uv_scale <= 0.0:
			uvs = [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
		else:
			uvs = [
				Vector2(0, v_len * 2.0 * uv_scale), Vector2(u_len * 2.0 * uv_scale, v_len * 2.0 * uv_scale),
				Vector2(u_len * 2.0 * uv_scale, 0), Vector2(0, 0),
			]
		var w_nrm := (tf.basis * nrm).normalized()
		for idx in [0, 1, 2, 0, 2, 3]:
			st.set_color(col)
			st.set_normal(w_nrm)
			st.set_uv(uvs[idx])
			st.add_vertex(tf * (corners[idx]))

# Y-axis cylinder / cone (top_r = 0 for cone) centered at tf origin.
static func cyl(st: SurfaceTool, tf: Transform3D, bottom_r: float, top_r: float, height: float,
		sides: int, col: Color, cap_bottom := true, cap_top := true) -> void:
	var hh := height * 0.5
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var b0 := d0 * bottom_r + Vector3(0, -hh, 0)
		var b1 := d1 * bottom_r + Vector3(0, -hh, 0)
		var t0 := d0 * top_r + Vector3(0, hh, 0)
		var t1 := d1 * top_r + Vector3(0, hh, 0)
		var slope := (bottom_r - top_r) / maxf(height, 0.001)
		var n0 := (tf.basis * Vector3(d0.x, slope, d0.z)).normalized()
		var n1 := (tf.basis * Vector3(d1.x, slope, d1.z)).normalized()
		var u0 := float(i) / sides
		var u1 := float(i + 1) / sides
		# Side-wall winding: (b0,b1,t1)+(b0,t1,t0) computes INWARD-facing
		# triangles (verified analytically — cross product of the actual
		# vertex order points toward the Y axis, opposite the correct
		# outward per-vertex normal below) — swapping each triangle's last
		# two vertices flips it outward. Confirmed 2026-07-03 via a headless
		# winding-vs-stored-normal audit across every cylinder-based mesh in
		# the game (tank turret, planes, wheels, tree/palm trunks, ship
		# funnel/mast/barrels, mortar tube...) — this was the actual cause
		# of the "flipped normals" Alex saw, not the mountain terrain or a
		# camera-angle illusion.
		var quad_v := [b0, t1, b1, b0, t0, t1]
		var quad_n := [n0, n1, n1, n0, n0, n1]
		var quad_uv := [Vector2(u0, 1), Vector2(u1, 0), Vector2(u1, 1), Vector2(u0, 1), Vector2(u0, 0), Vector2(u1, 0)]
		for k in 6:
			st.set_color(col)
			st.set_normal(quad_n[k])
			st.set_uv(quad_uv[k])
			st.add_vertex(tf * quad_v[k])
		# Caps: wound so the CCW-front face points OUTWARD (down for the bottom,
		# up for the top). The earlier [center, b1, b0] / [center, t0, t1] order
		# was reversed, so caps were back-face culled from outside — barrels and
		# funnels read as hollow tubes. Order below matches the outward normal.
		if cap_bottom and bottom_r > 0.0:
			var nb := (tf.basis * Vector3.DOWN).normalized()
			for v in [Vector3(0, -hh, 0), b0, b1]:
				st.set_color(col)
				st.set_normal(nb)
				st.set_uv(Vector2(0.5 + v.x * 0.1, 0.5 + v.z * 0.1))
				st.add_vertex(tf * v)
		if cap_top and top_r > 0.0:
			var nt := (tf.basis * Vector3.UP).normalized()
			for v in [Vector3(0, hh, 0), t1, t0]:
				st.set_color(col)
				st.set_normal(nt)
				st.set_uv(Vector2(0.5 + v.x * 0.1, 0.5 + v.z * 0.1))
				st.add_vertex(tf * v)

# Triangular prism (gable roof) along local X. width=X span, depth=Z span, height=ridge.
static func prism(st: SurfaceTool, tf: Transform3D, width: float, depth: float, height: float, col: Color) -> void:
	var hw := width * 0.5
	var hd := depth * 0.5
	var a := Vector3(-hw, 0, -hd)
	var b := Vector3(hw, 0, -hd)
	var c := Vector3(hw, 0, hd)
	var d := Vector3(-hw, 0, hd)
	var r0 := Vector3(-hw, height, 0)
	var r1 := Vector3(hw, height, 0)
	var tris := [
		# roof slope -Z
		[a, b, r1], [a, r1, r0],
		# roof slope +Z
		[c, d, r0], [c, r0, r1],
		# gable ends
		[d, a, r0], [b, c, r1],
	]
	for t in tris:
		var nrm: Vector3 = ((t[1] - t[0]).cross(t[2] - t[0])).normalized()
		nrm = (tf.basis * nrm).normalized()
		for v in t:
			st.set_color(col)
			st.set_normal(nrm)
			st.set_uv(Vector2(v.x * 0.25, (v.z + v.y) * 0.25))
			st.add_vertex(tf * v)

static func commit(st: SurfaceTool, mat: Material) -> ArrayMesh:
	var mesh := st.commit()
	if mesh.get_surface_count() > 0:
		mesh.surface_set_material(0, mat)
	return mesh

# ---- shared materials ----
static func mat_vcol(rough := 0.92, metal := 0.0) -> StandardMaterial3D:
	var key := "vcol_%f_%f" % [rough, metal]
	if not _mat_cache.has(key):
		var m := StandardMaterial3D.new()
		m.vertex_color_use_as_albedo = true
		m.roughness = rough
		m.metallic = metal
		_mat_cache[key] = m
	return _mat_cache[key]

static func mat_tex(path: String, vcol := false, rough := 0.92, metal := 0.0) -> StandardMaterial3D:
	var key := "tex_%s_%s_%f_%f" % [path, vcol, rough, metal]
	if not _mat_cache.has(key):
		var m := StandardMaterial3D.new()
		m.albedo_texture = load(path)
		m.vertex_color_use_as_albedo = vcol
		m.roughness = rough
		m.metallic = metal
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		_mat_cache[key] = m
	return _mat_cache[key]

static func set_layer_recursive(node: Node, layer_mask: int) -> void:
	if node is VisualInstance3D:
		node.layers = layer_mask
	for c in node.get_children():
		set_layer_recursive(c, layer_mask)

static func add_static_box_collider(parent: Node3D, pos: Vector3, size: Vector3, yaw := 0.0) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	body.add_child(cs)
	body.position = pos
	body.rotation.y = yaw
	parent.add_child(body)

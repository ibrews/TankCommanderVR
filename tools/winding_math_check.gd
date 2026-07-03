# Pure-math winding truth table for MeshKit primitives — no rendering, no
# shaders, no audit reuse. For every triangle of a unit box()/cyl()/prism():
#   geo  = normalized cross(v1-v0, v2-v0)   (the GPU's actual front-face basis)
#   sto  = the stored per-vertex normal MeshKit wrote
#   out  = direction from primitive center to triangle centroid (true outward)
# Prints dot(geo,sto) and dot(geo,out) per triangle. For a correct mesh BOTH
# dots are +1 on every row. dot(geo,out) = -1 rows are faces wound inward —
# the definitive per-face list of what's flipped, no interpretation involved.
#
# Run: godot --headless --path . -s tools/winding_math_check.gd
# (mesh_kit.gd references no autoloads, so -s mode is safe here.)
extends SceneTree

func _init() -> void:
	_check_box()
	_check_cyl()
	_check_prism()
	quit(0)

func _tris(mesh: ArrayMesh) -> Array:
	var arrays := mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var out := []
	var idx_v: Variant = arrays[Mesh.ARRAY_INDEX]   # Nil for non-indexed meshes
	if idx_v == null or (idx_v as PackedInt32Array).is_empty():
		for i in range(0, verts.size(), 3):
			out.append([verts[i], verts[i + 1], verts[i + 2], norms[i]])
	else:
		var idx: PackedInt32Array = idx_v
		for i in range(0, idx.size(), 3):
			out.append([verts[idx[i]], verts[idx[i + 1]], verts[idx[i + 2]], norms[idx[i]]])
	return out

func _report(label: String, mesh: ArrayMesh, center: Vector3) -> void:
	print("\n=== %s ===" % label)
	print("%-4s %-28s %-10s %-10s %s" % ["tri", "centroid", "geo.sto", "geo.out", "verdict"])
	var flipped := 0
	var tris := _tris(mesh)
	for i in tris.size():
		var t: Array = tris[i]
		var geo: Vector3 = (t[1] - t[0]).cross(t[2] - t[0])
		if geo.length() < 1e-9:
			continue
		geo = geo.normalized()
		var cen: Vector3 = (t[0] + t[1] + t[2]) / 3.0
		var outward: Vector3 = (cen - center)
		if outward.length() < 1e-6:
			continue
		outward = outward.normalized()
		var d_sto: float = geo.dot(t[3])
		var d_out: float = geo.dot(outward)
		# Godot front faces are CLOCKWISE (tools/convention_test.gd, verified
		# empirically 2026-07-03): correct outward-facing geometry has its
		# RHR cross product pointing INWARD (d_out < 0) and its stored
		# lighting normal outward (d_sto < 0 vs the RHR cross). The first
		# version of this script had the verdict backwards.
		var verdict := "ok" if d_out < 0.0 else "FLIPPED (CCW = Godot backface)"
		if d_out >= 0.0:
			flipped += 1
		print("%-4d %-28s %+.2f      %+.2f      %s" % [i, str(cen), d_sto, d_out, verdict])
	print("--- %s: %d/%d triangles wound inward" % [label, flipped, tris.size()])

func _check_box() -> void:
	var st := MeshKit.begin()
	MeshKit.box(st, Transform3D(), Vector3(2, 2, 2), Color.WHITE)
	_report("MeshKit.box(2x2x2 at origin)", st.commit(), Vector3.ZERO)

func _check_cyl() -> void:
	var st := MeshKit.begin()
	MeshKit.cyl(st, Transform3D(), 1.0, 1.0, 2.0, 6, Color.WHITE)
	_report("MeshKit.cyl(r=1 h=2, 6 sides)", st.commit(), Vector3.ZERO)

func _check_prism() -> void:
	var st := MeshKit.begin()
	MeshKit.prism(st, Transform3D(), 2.0, 2.0, 1.0, Color.WHITE)
	# prism base sits at y=0, ridge at y=height — centroid of the solid ~ (0, 0.4, 0)
	_report("MeshKit.prism(2x2 h=1)", st.commit(), Vector3(0, 0.4, 0))

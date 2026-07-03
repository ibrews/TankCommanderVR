# Headless, analytical, no-rendering check: does the "tall" building wall
# box (CITY BUILDING) actually have inverted triangle winding vs the
# regular ("village house") wall box, or is that a rendering/material
# artifact instead? Compares real vertex/index arrays' geometric winding
# against the mathematically-expected outward-from-center direction — no
# GPU, no editor, no screenshot ambiguity.
#
# Replicates ONLY the wall-box construction from WorldDressing._building()
# directly via MeshKit (not by instantiating WorldDressing itself) — that
# class's _build_lava() has a type-annotated `FxPool` local var, which pulls
# fx.gd into the compile graph, which references bare `Game`/`Sfx`
# identifiers that don't resolve in headless -s tool mode (same class of
# gotcha documented in castle_wall.gd's own comment).
#
# Run: godot --headless --xr-mode off -s tools/inspect_building_winding.gd
extends SceneTree

func _init() -> void:
	var mat_wall := MeshKit.mat_tex("res://assets/tex/building.png")
	_check("SMALL (village house shape, tall=false)", 6.0, 5.0, 3.3, mat_wall, -1.0)
	_check("LARGE (city building shape, tall=true)", 9.0, 9.0, 14.0, mat_wall, 0.12)
	quit(0)

# Mirrors world_dressing.gd's _building() wall construction exactly:
#   MeshKit.box(st, Transform3D(Basis(), Vector3(0, hgt/2.0, 0)), Vector3(w, hgt, d), Color.WHITE, uv_scale)
func _check(label: String, w: float, d: float, hgt: float, mat: Material, uv_scale: float) -> void:
	var st := MeshKit.begin()
	MeshKit.box(st, Transform3D(Basis(), Vector3(0, hgt / 2.0, 0)), Vector3(w, hgt, d), Color.WHITE, uv_scale)
	var mesh := MeshKit.commit(st, mat)
	var center := Vector3(0, hgt / 2.0, 0)

	print("=== %s ===" % label)
	for s in mesh.get_surface_count():
		var surf_mat := mesh.surface_get_material(s)
		var cull_mode := (surf_mat as BaseMaterial3D).cull_mode if surf_mat else -1
		var arrays := mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var idx = arrays[Mesh.ARRAY_INDEX]  # untyped — non-indexed SurfaceTool output is null here
		var tri_count: int = (idx.size() / 3) if idx != null else (verts.size() / 3)
		var outward := 0
		var inward := 0
		for i in tri_count:
			var i0: int; var i1: int; var i2: int
			if idx != null:
				i0 = idx[i * 3]; i1 = idx[i * 3 + 1]; i2 = idx[i * 3 + 2]
			else:
				i0 = i * 3; i1 = i * 3 + 1; i2 = i * 3 + 2
			var v0: Vector3 = verts[i0]
			var v1: Vector3 = verts[i1]
			var v2: Vector3 = verts[i2]
			var face_normal := (v1 - v0).cross(v2 - v0).normalized()
			var centroid := (v0 + v1 + v2) / 3.0
			var expected_outward := (centroid - center).normalized()
			if face_normal.dot(expected_outward) > 0.0:
				outward += 1
			else:
				inward += 1
		print("  surface %d: cull_mode=%d tris=%d outward=%d inward=%d%s" % [
			s, cull_mode, tri_count, outward, inward,
			"  <<< MOSTLY/ALL INVERTED" if inward > outward else ""])

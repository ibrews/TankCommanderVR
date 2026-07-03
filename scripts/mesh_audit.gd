# Headless-ish analytical mesh-winding audit — NOT interactive, prints a
# report and quits. Unlike tools/*.gd (`-s` mode), this runs through a
# normal scene boot (`godot --path . scenes/mesh_audit.tscn`) specifically
# because enemy_tank.gd/enemy_plane.gd/enemy_light.gd/enemy_ship.gd/
# world_dressing.gd all fail to COMPILE in `-s` tool mode (bare Game/Sfx
# references elsewhere in those files never resolve there — confirmed
# 2026-07-03, same class of gotcha documented in castle_wall.gd's own
# comment) even though none of their code paths actually need those
# autoloads for pure mesh construction. Normal scene boot has working
# autoloads, so this sidesteps the problem entirely — same reason
# TC_SHOWCASE_SHOT mode works via `godot --path . scenes/X.tscn` and not
# `-s`.
#
# For each triangle: does the GEOMETRIC winding (right-hand-rule cross
# product of actual vertex order) agree with the STORED per-vertex normal
# MeshKit wrote via st.set_normal()? Godot's backface culling decides
# visibility from winding; lighting shades from the stored normal. A
# mismatch is exactly the "flipped normal" symptom — real, not a
# screenshot-angle illusion.
#
# Run: godot --path . scenes/mesh_audit.tscn  (auto-quits when done)
extends Node3D


func _ready() -> void:
	var terrain := Terrain.new()  # never add_child()'d — only .height()/.cfg needed, not the actual mesh
	var wd := WorldDressing.new(terrain)  # never add_child()'d — avoid its auto-scatter _ready()

	print("\n========== MESH WINDING AUDIT ==========")

	EnemyTank._build_meshes()
	_check("EnemyTank hull", EnemyTank._hull_mesh)
	_check("EnemyTank turret", EnemyTank._turret_mesh)

	EnemyPlane._build_mesh()
	_check("EnemyPlane", EnemyPlane._mesh)

	EnemyLight.Jeep._build()
	_check("EnemyLight.Jeep", EnemyLight.Jeep._mesh)
	EnemyLight.Gunner._build()
	_check("EnemyLight.Gunner", EnemyLight.Gunner._mesh)
	EnemyLight.Mortar._build()
	_check("EnemyLight.Mortar", EnemyLight.Mortar._mesh)

	EnemyShip._build()
	_check("EnemyShip (prism bow + many cylinders)", EnemyShip._mesh)

	_check("WorldDressing tree", wd._tree_mesh())
	_check("WorldDressing rock", wd._rock_mesh())
	_check("WorldDressing palm (bent trunk cylinders + fronds)", wd._palm_mesh())

	# Broader box()/prism() coverage — the first pass only sampled 2 box
	# meshes (tank hull, rock) and never isolated prism() at all. Do NOT
	# assume those primitives are clean from that alone.
	var stone := MeshKit.mat_tex("res://assets/tex/rock.png", true, 0.95)
	var wall := CastleWall.new(stone, 12.0)
	_check("CastleWall wall+crenellations (many rotated boxes)", wall._wall_mesh())
	wall.position = Vector3(5, 0, 5)  # give _rubble_mesh() a deterministic, non-origin hash seed
	_check("CastleWall rubble (compound-rotated boxes)", wall._rubble_mesh())

	var st_prism := MeshKit.begin()
	MeshKit.prism(st_prism, Transform3D(Basis(), Vector3(0, 3, 0)), 6.0, 5.0, 1.4, Color(0.6, 0.3, 0.2))
	_check("MeshKit.prism() isolated (gable roof shape)", MeshKit.commit(st_prism, MeshKit.mat_vcol()))

	print("========== DONE ==========\n")
	print("NOT tested here: SphereMesh usage (cockpit_builder.gd, interactables.gd,")
	print("net.gd, world_dressing.gd gym/babyroom balls, xr_rig.gd) — those are all")
	print("Godot's own built-in SphereMesh primitive, a completely different code")
	print("path from MeshKit, not custom-wound. Also not exhaustively covered: every")
	print("individual box()/cyl()/prism() call site in world_dressing.gd (buildings,")
	print("umbrellas, wrecks, lava/sea grids, gym, babyroom) and npc.gd (cabbage")
	print("stand, creeper, giant baby) — this audit samples representative cases,")
	print("it does not prove every call site in the codebase is correct.")
	get_tree().quit()


func _check(label: String, mesh: ArrayMesh) -> void:
	if mesh == null:
		print("=== %s === SKIPPED (mesh is null)" % label)
		return
	print("=== %s ===" % label)
	for s in mesh.get_surface_count():
		var mat := mesh.surface_get_material(s)
		var cull_mode := (mat as BaseMaterial3D).cull_mode if mat else -1
		var arrays := mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var idx = arrays[Mesh.ARRAY_INDEX]
		var tri_count: int = (idx.size() / 3) if idx != null else (verts.size() / 3)
		var agree := 0
		var mismatch := 0
		var first_bad := -1
		for i in tri_count:
			var i0: int; var i1: int; var i2: int
			if idx != null:
				i0 = idx[i * 3]; i1 = idx[i * 3 + 1]; i2 = idx[i * 3 + 2]
			else:
				i0 = i * 3; i1 = i * 3 + 1; i2 = i * 3 + 2
			var v0: Vector3 = verts[i0]
			var v1: Vector3 = verts[i1]
			var v2: Vector3 = verts[i2]
			var cross := (v1 - v0).cross(v2 - v0)
			var area := cross.length() * 0.5
			if area < 0.0001:
				continue  # degenerate (zero-area) triangle — e.g. a cone apex where two verts coincide; winding is undefined/meaningless, not a real visual bug
			var winding_normal := cross.normalized()
			var stored_normal: Vector3 = norms[i0]
			if winding_normal.dot(stored_normal) > 0.0:
				agree += 1
			else:
				mismatch += 1
				if first_bad < 0:
					first_bad = i
		print("  surface %d: cull_mode=%d tris=%d agree=%d mismatch=%d%s" % [
			s, cull_mode, tri_count, agree, mismatch,
			("  <<< MISMATCH (first bad tri #%d, centroid %s) — REAL BUG" % [
				first_bad, (verts[idx[first_bad*3]] if idx != null else verts[first_bad*3])]
			) if mismatch > 0 else ""])

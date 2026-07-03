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
	# EnemyLight.Gunner no longer has a static merged mesh (2026-07-03: its
	# visual body became an AvatarRig instance, scripts/avatar_rig.gd, built
	# from Godot's own CylinderMesh/SphereMesh/BoxMesh primitives — not
	# MeshKit-authored triangle soup, so it isn't in this audit's risk
	# category). Nothing to check here anymore.
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

	# ---- ROUND 2 (2026-07-03, responding to Alex: "it's not just cylinders —
	# it's boxes and sphere and all sorts of other shapes too... inconsistent.
	# don't lie and say this is only cylinders.") Round 1 was representative
	# sampling, explicitly NOT proof of universal correctness. This closes
	# every gap the old disclaimer below used to list: every remaining
	# world_dressing.gd box()/cyl()/prism() call site, all 3 NPCs, all 6
	# player vehicles (round 1 only covered enemies), and — via
	# _check_node_tree()'s NEW second check — every built-in-primitive
	# MeshInstance3D (SphereMesh/BoxMesh/CylinderMesh/QuadMesh) reachable from
	# the real production object graph. The winding-vs-normal test can't see
	# SphereMesh at all (it's Godot's own well-tested built-in, not
	# MeshKit-authored) — the mechanism that COULD flip it without any
	# mesh-authoring bug is a mirrored (negative-determinant) transform, so
	# that's the new check, applied to every MeshInstance3D found regardless
	# of mesh type. A grep for negative-scale literals across scripts/ found
	# none, but that only rules out STATIC cases — this checks the live,
	# fully-constructed transform of every real specimen instead of assuming.
	print("\n---------- ROUND 2: closing all previously-listed gaps ----------")

	var fx := FxPool.new()
	add_child(fx)
	var projectiles := Projectiles.new(terrain, fx)
	add_child(projectiles)

	# player vehicles — round 1 only covered enemies
	var tank := PlayerTank.new(terrain, projectiles, fx)
	add_child(tank)
	_check_node_tree("PlayerTank", tank)

	var plane := PlayerPlane.new(terrain, projectiles, fx)
	add_child(plane)
	_check_node_tree("PlayerPlane", plane)

	var biplane := PlayerPlane.new(terrain, projectiles, fx)
	biplane.biplane = true
	add_child(biplane)
	_check_node_tree("PlayerPlane (biplane=true)", biplane)

	var heli := PlayerAlt.Heli.new(terrain, projectiles, fx)
	add_child(heli)
	_check_node_tree("PlayerAlt.Heli", heli)

	var boat := PlayerBoat.new(terrain, projectiles, fx)
	add_child(boat)
	_check_node_tree("PlayerBoat (prism bow, untested standalone until now)", boat)

	# NPCs — explicitly flagged as untested in round 1
	var cabbage := Npc.CabbageMan.spawn(self, terrain, tank)
	_check_node_tree("Npc.CabbageMan", cabbage)

	var creeper := Npc.Creeper.new()
	creeper.terrain = terrain
	creeper.player = tank
	add_child(creeper)
	_check_node_tree("Npc.Creeper", creeper)

	var baby := Npc.GiantBaby.spawn(self, terrain, tank)
	_check_node_tree("Npc.GiantBaby", baby)

	# imported (non-MeshKit) controller model — determinant check still
	# applies even though there's no custom winding to test
	var ctrl := ControllerVisual.new()
	ctrl.is_left = true
	add_child(ctrl)
	_check_node_tree("ControllerVisual (imported .glb, transform-only check)", ctrl)

	# every remaining world_dressing.gd box()/cyl()/prism() call site
	_building_via_wd(wd, 6.0, 5.0, 3.3, false, "WorldDressing._building() VILLAGE HOUSE (tall=false)")
	_building_via_wd(wd, 9.0, 9.0, 14.0, true, "WorldDressing._building() CITY BUILDING (tall=true)")

	var before := wd.get_child_count()
	wd._build_wrecks(1)
	_reparent_new(wd, before, "WorldDressing._build_wrecks() (real fn — not the showcase's inline mirror)")

	before = wd.get_child_count()
	wd._build_beach_props()
	_reparent_new(wd, before, "WorldDressing._build_beach_props() (10 umbrellas, real fn)")

	before = wd.get_child_count()
	wd._build_gym()
	_reparent_new(wd, before, "WorldDressing._build_gym() (walls/bleachers/hoops/forts)")

	before = wd.get_child_count()
	wd._build_babyroom()
	_reparent_new(wd, before, "WorldDressing._build_babyroom() (crib/blocks/bricks/balls)")

	before = wd.get_child_count()
	wd._build_sea()
	_reparent_new(wd, before, "WorldDressing._build_sea() (horizon quad grid)")

	before = wd.get_child_count()
	wd._build_lava()
	_reparent_new(wd, before, "WorldDressing._build_lava() (quad grid)")

	print("\n========== DONE ==========\n")
	print("Still NOT covered by anything above: runtime-only geometry (VR hand")
	print("poses, cockpit control state-dependent visuals, net.gd/xr_rig.gd/")
	print("cockpit_builder.gd/player_alt.gd/main.gd content — deliberately")
	print("untouched, belongs to a sibling session's in-progress on-foot feature)")
	print("and any bug class other than winding-vs-normal-mismatch or negative-")
	print("determinant-transform — e.g. a wrong-but-SELF-CONSISTENT normal")
	print("(shades wrong, no mismatch — this test structurally cannot see that)")
	print("or a material/lighting issue that only LOOKS like flipped geometry.")
	print("If Alex reports something specific after this, get the exact object +")
	print("viewing angle before assuming it's already covered here.")
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



# Mirrors WorldDressing._building()'s real call signature exactly — position
# doesn't matter for a geometry-only check, so (0,0) is fine. mat_roof
# matches asset_showcase.gd's own choice per tall/not-tall (village uses a
# textured roof material, city uses a plain vcol material — same as the
# real showcase, so any material-dependent behavior is also exercised).
func _building_via_wd(wd: WorldDressing, w: float, d: float, hgt: float, tall: bool, label: String) -> void:
	var mat_wall := MeshKit.mat_tex("res://assets/tex/building.png")
	var mat_roof := MeshKit.mat_vcol(0.9) if tall else MeshKit.mat_tex("res://assets/tex/roof.png", true)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var before := wd.get_child_count()
	wd._building(0.0, 0.0, w, d, hgt, 0.0, mat_wall, mat_roof, rng, tall)
	_reparent_new(wd, before, label)


# WorldDressing instance methods add_child() their output directly onto
# `wd` (never itself add_child()'d into the tree, deliberately, to avoid its
# auto-scatter _ready()) — pull the newly-created children out into `self`
# (which IS in the tree) so _check_node_tree()'s global_transform reads are
# well-defined, then audit each.
func _reparent_new(from: Node, before_count: int, label: String) -> void:
	var moved := []
	while from.get_child_count() > before_count:
		var c := from.get_child(from.get_child_count() - 1)
		from.remove_child(c)
		add_child(c)
		moved.append(c)
	if moved.is_empty():
		print("=== %s === SKIPPED (produced no children — check preconditions)" % label)
		return
	for c in moved:
		_check_node_tree(label, c)


# Walks every MeshInstance3D in a subtree and runs BOTH checks:
# 1. (ArrayMesh only) geometric winding vs stored normal — same test as
#    _check(), catches a MeshKit authoring bug like the cyl() one.
# 2. (EVERY MeshInstance3D, including Godot's own built-in primitives like
#    SphereMesh/BoxMesh/CylinderMesh/QuadMesh that MeshKit never touches)
#    negative-determinant transform — catches a MIRRORED instance, which
#    flips apparent winding/facing without any mesh-data bug at all. This is
#    the check that can actually see a "sphere looks flipped" report, since
#    SphereMesh's own triangle data is a well-tested Godot built-in and
#    essentially never wrong on its own.
func _check_node_tree(prefix: String, root: Node) -> void:
	if root == null:
		print("=== %s === SKIPPED (root is null)" % prefix)
		return
	var stack := [root]
	var found := 0
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is MeshInstance3D:
			var mi: MeshInstance3D = n
			if mi.mesh == null:
				continue
			found += 1
			var label := "%s > %s (%s)" % [prefix, String(mi.name), mi.mesh.get_class()]
			if mi.mesh is ArrayMesh:
				_check(label, mi.mesh)
			else:
				print("=== %s === (built-in %s — geometry itself not winding-audited, transform-only)" % [label, mi.mesh.get_class()])
			var det := mi.global_transform.basis.determinant()
			if det < 0.0:
				print("  <<< MIRRORED TRANSFORM (determinant=%.3f) — REAL BUG, flips apparent winding regardless of mesh data" % det)
	if found == 0:
		print("=== %s === SKIPPED (no MeshInstance3D found under this node)" % prefix)

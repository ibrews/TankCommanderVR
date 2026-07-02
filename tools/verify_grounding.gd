# Headless grounding verifier: rebuilds every level's WorldDressing off-tree
# and measures the gap between each prop's contact points and the terrain.
# Any positive gap beyond tolerance = floating geometry (the v0.5.0 headset
# bug: floating trees / incomplete-looking geometry on slopes and coasts).
# Run from the project root:
#   godot --headless -s tools/verify_grounding.gd
# Exits 0 when every level is clean, 1 with a FLOAT line per offender.
extends SceneTree

var fails := 0
var report: Array[String] = []

func _init() -> void:
	for id in Levels.ORDER:
		_check_level(id)
	if fails == 0:
		_say("[ground] ALL LEVELS OK")
	else:
		_say("[ground] FAIL — %d floating props" % fails)
	# artifact file — Windows buffers redirected Godot stdout, poll this instead
	var f := FileAccess.open("res://out/ground_report.txt", FileAccess.WRITE)
	f.store_string("\n".join(report) + "\n")
	f.close()
	quit(0 if fails == 0 else 1)

func _say(line: String) -> void:
	print(line)
	report.append(line)

func _min5(t: Terrain, x: float, z: float, r: float) -> float:
	var h := t.height(x, z)
	h = minf(h, t.height(x + r, z))
	h = minf(h, t.height(x - r, z))
	h = minf(h, t.height(x, z + r))
	h = minf(h, t.height(x, z - r))
	return h

# worst gap over the 4 bottom corners of an AABB under a transform
func _aabb_gap(t: Terrain, xf: Transform3D, aabb: AABB) -> float:
	var g := -99.0
	for cx in [aabb.position.x, aabb.end.x]:
		for cz in [aabb.position.z, aabb.end.z]:
			var wp := xf * Vector3(cx, aabb.position.y, cz)
			g = maxf(g, wp.y - t.height(wp.x, wp.z))
	return g

# worst gap over 4 explicit local-space contact corners
func _corners_gap(t: Terrain, xf: Transform3D, lo: Vector3, hi: Vector3) -> float:
	var g := -99.0
	for cx in [lo.x, hi.x]:
		for cz in [lo.z, hi.z]:
			var wp := xf * Vector3(cx, lo.y, cz)
			g = maxf(g, wp.y - t.height(wp.x, wp.z))
	return g

func _flag(level: String, cat: String, pos: Vector3, gap: float, tol: float) -> void:
	if gap > tol:
		fails += 1
		_say("[ground] FLOAT %s %s at (%.1f, %.1f) gap=%.2f" % [level, cat, pos.x, pos.z, gap])

func _track(worst: Dictionary, cat: String, gap: float) -> void:
	if not worst.has(cat):
		worst[cat] = {"g": -99.0, "n": 0}
	worst[cat].n += 1
	if gap > worst[cat].g:
		worst[cat].g = gap

func _check_level(id: String) -> void:
	var cfg := Levels.get_config(id)
	var t := Terrain.new(cfg)
	var d := WorldDressing.new(t)
	d._ready()
	var worst := {}
	for child in d.get_children():
		var n := String(child.name)
		var cat: String = child.get_meta("cat", "")
		if child is MultiMeshInstance3D:
			# read placements from metadata — MultiMesh.get_instance_transform
			# returns identity under --headless (dummy RenderingServer)
			var xforms: Array = child.get_meta("xforms", [])
			for xf: Transform3D in xforms:
				var s := xf.basis.get_scale()
				if n.contains("Trees") or n.contains("Palms"):
					var g := xf.origin.y - _min5(t, xf.origin.x, xf.origin.z, 0.35 * s.x)
					_flag(id, "tree/palm", xf.origin, g, 0.03)
					_track(worst, "tree/palm", g)
				elif n.contains("Rocks"):
					var g := (xf.origin.y - 0.5 * s.y) - _min5(t, xf.origin.x, xf.origin.z, 0.7 * s.x)
					_flag(id, "rock", xf.origin, g, 0.05)
					_track(worst, "rock", g)
		elif cat == "building":
			var walls: MeshInstance3D = child.get_child(0)
			var g := _aabb_gap(t, child.transform, walls.mesh.get_aabb())
			_flag(id, "building", child.position, g, 0.05)
			_track(worst, "building", g)
		elif cat == "wreck":
			var g := _corners_gap(t, child.transform, Vector3(-1.6, 0.2, -3.2), Vector3(1.6, 0.2, 3.2))
			_flag(id, "wreck", child.position, g, 0.15)
			_track(worst, "wreck", g)
		elif cat == "castle":
			for cc in child.get_children():
				if cc is CastleWall:
					var wt: Transform3D = child.transform * cc.transform
					var hl: float = cc.seg_len * 0.5
					var g := _corners_gap(t, wt, Vector3(-hl, 0, -0.7), Vector3(hl, 0, 0.7))
					_flag(id, "castle-wall", wt.origin, g, 0.08)
					_track(worst, "castle-wall", g)
				elif cc is MeshInstance3D:
					# tower/keep base: 4 compass points at the base radius
					var wt: Transform3D = child.transform * cc.transform
					var aabb: AABB = cc.mesh.get_aabb()
					var r: float = minf(aabb.size.x, aabb.size.z) * 0.45
					var g := -99.0
					for off in [Vector3(r, 0, 0), Vector3(-r, 0, 0), Vector3(0, 0, r), Vector3(0, 0, -r)]:
						var wp: Vector3 = wt * (off + Vector3(0, aabb.position.y, 0))
						g = maxf(g, wp.y - t.height(wp.x, wp.z))
					_flag(id, "castle-struct", wt.origin, g, 0.12)
					_track(worst, "castle-struct", g)
		elif cat == "umbrella":
			var g: float = (child.position.y - 0.05) - t.height(child.position.x, child.position.z)
			_flag(id, "umbrella", child.position, g, 0.08)
			_track(worst, "umbrella", g)
		elif cat == "prop":
			var mi := child as MeshInstance3D
			if mi == null or mi.mesh == null:
				continue
			var g := _aabb_gap(t, child.transform, mi.mesh.get_aabb())
			_flag(id, "prop", child.position, g, 0.08)
			_track(worst, "prop", g)
	var summary := "[ground] %s:" % id
	var keys := worst.keys()
	keys.sort()
	for k in keys:
		summary += "  %s worst=%.2f n=%d" % [k, worst[k].g, worst[k].n]
	_say(summary)
	d.free()
	t.free()

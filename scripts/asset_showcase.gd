# Editor-only diagnostic scene: instantiates one real example of every
# procedurally-built model in the game (scripts/mesh_kit.gd + friends) on a
# flat patch of the REAL Terrain class, each labeled, so pivot/origin/
# grounding/rotation bugs are visible at a glance without a Quest headset.
#
# Open scenes/asset_showcase.tscn in the Godot editor and press F6 (Run
# Current Scene) to fly around with scripts/showcase_free_cam.gd.
#
# Does NOT touch any gameplay file — it only calls existing classes
# (PlayerTank, EnemyTank, WorldDressing, CastleWall, Npc.*, ...) exactly as
# main.gd does, then freezes + repositions the results into a grid. A couple
# of "private" (underscore-prefixed) WorldDressing methods are called
# directly to get ONE controlled-position specimen instead of a whole
# level's random scatter — GDScript doesn't enforce privacy, and this is the
# only way to reuse the real mesh-building code without dragging in hundreds
# of randomly-placed trees/rocks/buildings.
extends Node3D

const ROW_PLAYER := -50.0
const ROW_ENEMY := -30.0
const ROW_PROPS := -10.0
const ROW_STRUCT := 10.0
const ROW_NPC := 30.0
const ROW_BABY := 65.0

var terrain: Terrain
var fx: FxPool
var projectiles: Projectiles
var wd: WorldDressing         # never added to the tree — see _building_at()/_tree_at() etc.
var _dummy_player: Node3D     # any live vehicle works as the "player" ref enemies/NPCs need
var _ctrl_l: Node3D
var _ctrl_r: Node3D


func _ready() -> void:
	# This is a visual-inspection tool, not a playable demo — mute the half
	# dozen simultaneous engine-idle loops every frozen vehicle/enemy still
	# starts on _ready().
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), true)

	_build_lighting()
	_build_terrain()

	fx = FxPool.new()
	add_child(fx)
	projectiles = Projectiles.new(terrain, fx)
	add_child(projectiles)
	wd = WorldDressing.new(terrain)   # deliberately never add_child()'d, see header

	_place_player_vehicles()
	_place_enemy_vehicles()
	_place_props_row()
	_place_structures_row()
	_place_npc_row()
	_place_giant_baby()
	_place_mountain_signpost()
	_place_ground_labels()

	var cam := ShowcaseFreeCam.new()
	add_child(cam)
	cam.global_position = Vector3(0, 45, -125)
	cam.point_at(Vector3(0, 4, ROW_STRUCT))
	_cam = cam

	print("[showcase] ready — %d top-level nodes" % get_child_count())

	# Opt-in verification aid, same convention as main.gd's SHOT_* env vars:
	# TC_SHOWCASE_SHOT=1 godot --path . scenes/asset_showcase.tscn flies the
	# cam through a few waypoints and dumps PNGs to out/, then quits. No-op
	# (and no cost) for the normal editor-interactive use case.
	if OS.get_environment("TC_SHOWCASE_SHOT") != "":
		get_tree().create_timer(0.6).timeout.connect(_debug_shot_sequence)

	# TC_FACING_TOUR=1 -- whole-project version of the single-object
	# DEBUG_FACING check below. Applies the same front/back-face debug
	# material to EVERY specimen in the showcase at once, then reuses the
	# existing 17-waypoint tour (already covers nearly every model in the
	# game) instead of writing bespoke close-ups per object. This is the
	# scaled-up, cheap-to-rerun-forever version: no vision tokens spent by
	# anyone, human or model, to inspect the output -- pair with
	# tools/analyze_facing_debug.py (plain ImageMagick pixel-color
	# threshold, zero AI/model involvement) to flag which shots have real
	# red before a human or a frontier session looks at any of them.
	if OS.get_environment("TC_FACING_TOUR") != "":
		get_tree().create_timer(0.6).timeout.connect(func():
			_apply_debug_facing(self)
			_debug_shot_sequence())

	# DEBUG_FACING=1 -- objective, viewpoint-relative front/back-face check.
	# mesh_audit.gd only tests whether stored mesh DATA is self-consistent
	# (winding vs. normal); it can't tell you what a specific vantage point
	# actually sees, and it can't catch "camera/eye is inside a thin
	# double-sided mesh's silhouette" (very plausible in a tight VR cockpit
	# at close range) or a material with cull_disabled showing an interior
	# surface on purpose. This colors every real GPU-computed backface
	# bright red and every front face green, from the exact eye position a
	# seated player uses -- removes all interpretation.
	if OS.get_environment("DEBUG_FACING") != "":
		get_tree().create_timer(0.6).timeout.connect(_debug_facing_shot)


var _cam: Camera3D
const _DEBUG_WAYPOINTS := [
	{"name": "overview_with_mountains", "pos": Vector3(0, 220, -180), "look": Vector3(0, 0, 30)},
	{"name": "players_row", "pos": Vector3(0, 14, -58), "look": Vector3(0, 3, -50)},
	{"name": "enemies_row", "pos": Vector3(0, 14, -38), "look": Vector3(0, 2, -30)},
	{"name": "props_row", "pos": Vector3(0, 10, -18), "look": Vector3(0, 2, -10)},
	{"name": "structures_row", "pos": Vector3(0, 12, 2), "look": Vector3(0, 3, 10)},
	{"name": "npc_row", "pos": Vector3(0, 10, 22), "look": Vector3(0, 2, 30)},
	{"name": "giant_baby", "pos": Vector3(20, 55, 20), "look": Vector3(0, 8, 65)},
	{"name": "mountains_groundlevel", "pos": Vector3(0, 8, 100), "look": Vector3(0, 40, 220)},
	{"name": "mountains_heli_vantage", "pos": Vector3(0, 30, 0), "look": Vector3(140, 70, 140)},
	# Close-ups on the prism-roof / cylinder-cap primitives that historically
	# had winding-order bugs (MeshKit.prism + cyl caps, fixed 2026-07-02
	# "checkpoint ~14:40" per the KB daily log) — re-checking they hold.
	{"name": "closeup_village_house_roof", "pos": Vector3(-38, 8, 4), "look": Vector3(-28, 4, 10)},
	{"name": "closeup_castle_keep_roof", "pos": Vector3(28, 22, -4), "look": Vector3(28, 12, 10)},
	{"name": "closeup_castle_tower", "pos": Vector3(24, 10, 0), "look": Vector3(14, 8, 10)},
	{"name": "closeup_enemy_ship_bow", "pos": Vector3(28, 4, -38), "look": Vector3(35, 2, -30)},
	{"name": "closeup_player_boat_bow", "pos": Vector3(28, 4, -58), "look": Vector3(35, 1, -50)},
	{"name": "closeup_city_building", "pos": Vector3(-22, 10, 4), "look": Vector3(-14, 8, 10)},
	{"name": "ship_broadside_clean", "pos": Vector3(35, 6, -18), "look": Vector3(35, 2, -30)},
	{"name": "city_building_exterior_clean", "pos": Vector3(-14, 9, -14), "look": Vector3(-14, 7, 10)},
]
var _debug_step := 0

func _debug_shot_sequence() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://out"))
	if _debug_step >= _DEBUG_WAYPOINTS.size():
		print("[showcase] debug shot sequence done")
		get_tree().quit(0)
		return
	var wp: Dictionary = _DEBUG_WAYPOINTS[_debug_step]
	_cam.global_position = wp["pos"]
	_cam.point_at(wp["look"])
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("res://out/showcase_%02d_%s.png" % [_debug_step, wp["name"]]))
	print("[showcase] shot ", wp["name"])
	_debug_step += 1
	get_tree().create_timer(0.15).timeout.connect(_debug_shot_sequence)


# Front/back-face debug material: unshaded, double-sided, colors purely by
# the GPU's own real-time FRONT_FACING determination for the current camera
# — green means this triangle is genuinely front-facing from wherever the
# camera is right now, red means it's genuinely back-facing. No lighting,
# no interpretation, no "maybe it's just dim in here."
func _debug_facing_mat() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode cull_disabled, unshaded;

void fragment() {
	if (FRONT_FACING) {
		ALBEDO = vec3(0.15, 0.95, 0.15);
	} else {
		ALBEDO = vec3(1.0, 0.05, 0.05);
	}
}
"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	return mat


func _apply_debug_facing(root: Node) -> void:
	if root is MeshInstance3D:
		root.material_override = _debug_facing_mat()
	for c in root.get_children():
		_apply_debug_facing(c)


# DEBUG_FACING=1 companion to _debug_shot_sequence() — targets specifically
# the cockpit interior (restart lever + roof stiffener ribs, the two things
# flagged as looking wrong in a live screenshot) from the real seated-eye
# position, using the actual resolved node transforms rather than guessed
# world coordinates.
func _debug_facing_shot() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://out"))
	var tank: PlayerTank = _dummy_player
	_apply_debug_facing(tank.cockpit["root"])
	var seat: Node3D = tank.cockpit["seat_anchor"]
	var eye_local: Vector3 = tank.cockpit["eye_local"]
	var eye_pos: Vector3 = seat.to_global(eye_local)
	var restart: Node3D = tank.cockpit["controls"]["restart"]
	var rib_pos: Vector3 = tank.cockpit["root"].to_global(
		Vector3((CockpitBuilder.X0 + CockpitBuilder.X1) / 2.0, CockpitBuilder.YR - 0.035, -0.02))

	_cam.global_position = eye_pos
	_cam.look_at(restart.global_position, Vector3.UP)
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(
		ProjectSettings.globalize_path("res://out/debug_facing_restart_lever.png"))
	print("[showcase] debug_facing shot: restart_lever")

	# First attempt at this shot looked from the seat, which sent the ray
	# through the front periscope glass and picked up the tank's exterior
	# hull instead (a framing mistake, not a finding). Shoot from close
	# beneath the rib instead, short enough that the ray can't leave the
	# cockpit through any wall opening.
	_cam.global_position = rib_pos + Vector3(0, -0.5, 0.15)
	_cam.look_at(rib_pos, Vector3.UP)
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(
		ProjectSettings.globalize_path("res://out/debug_facing_roof_rib.png"))
	print("[showcase] debug_facing shot: roof_rib")

	# Pull back for a wider reference shot of the whole cockpit in facing-debug mode
	_cam.global_position = eye_pos + Vector3(0.6, 0.3, 0.6)
	_cam.look_at(seat.global_position, Vector3.UP)
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(
		ProjectSettings.globalize_path("res://out/debug_facing_cockpit_wide.png"))
	print("[showcase] debug_facing shot: cockpit_wide")

	# Controller model — mesh_audit.gd reported 100% inverted winding across
	# every submesh (y_button/trigger/thumbstick/squeeze/x_button/
	# controller_mesh, all cull_mode=2/CULL_BACK), an unusually total result
	# for an imported, previously-visually-confirmed-working asset. Close,
	# well-framed shot first (normal materials, is it actually invisible or
	# just badly framed in the wide row shot?), then the same vantage with
	# the debug facing material applied (ground truth either way).
	_cam.global_position = _ctrl_l.global_position + Vector3(0, 0.3, 1.2)
	_cam.look_at(_ctrl_l.global_position, Vector3.UP)
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(
		ProjectSettings.globalize_path("res://out/debug_controller_normal.png"))
	print("[showcase] debug_facing shot: controller_normal")

	_apply_debug_facing(_ctrl_l)
	await get_tree().process_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png(
		ProjectSettings.globalize_path("res://out/debug_controller_facing.png"))
	print("[showcase] debug_facing shot: controller_facing")

	print("[showcase] debug_facing sequence done")
	get_tree().quit(0)


# ------------------------------------------------------------- environment
func _build_lighting() -> void:
	var env := Environment.new()
	# Flat neutral color ambient (not sky-tinted) so nothing is mysteriously
	# dark or blue-tinted — this is the opposite of the game's real
	# restricted cockpit-interior light_cull_mask=~2 scheme on purpose.
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.5, 0.55, 0.6)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = false
	env.glow_enabled = false
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-52), deg_to_rad(35), 0)
	sun.light_color = Color(1, 1, 0.98)
	sun.light_energy = 0.85
	sun.shadow_enabled = true
	# NOTE: no light_cull_mask restriction — layer-2 cockpit-interior meshes
	# (see CockpitBuilder.set_interior_layer) get lit here too, unlike in the
	# real game where they're deliberately excluded from sun/fill.
	add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(deg_to_rad(-20), deg_to_rad(35 + 180), 0)
	fill.light_color = Color(0.85, 0.9, 1.0)
	fill.light_energy = 0.25
	fill.shadow_enabled = false
	add_child(fill)


# ------------------------------------------------------------- terrain
func _build_terrain() -> void:
	# Real Terrain class, real height()/rim-mountain math — just a custom
	# config so the middle ~140m is dead flat (a uniform y=0 reference plane
	# to place the grid on) while leaving the rim mountains at r>158.7
	# completely untouched and visible in the distance. See
	# _place_mountain_signpost() and the KB writeup for why the mountains
	# themselves are NOT a separate object you can instance here.
	var cfg := {
		"rolling": 9.0, "detail": 1.0, "rim": true,
		"dunes": false, "pond": false, "coast": false, "island": false,
		"archipelago": false, "volcano": false,
		"flatten": [[Vector2(0, 0), 130.0, 0.0]],
		"spawn": Vector2(0, 0), "spawn_h": 0.0,
		"village": {}, "city": {}, "castle": {}, "mud": [],
		"arena_radius": 232.0,
		"tint": Color(1, 1, 1),
	}
	terrain = Terrain.new(cfg)
	add_child(terrain)


func _gy(x: float, z: float) -> float:
	return terrain.height(x, z)


# ------------------------------------------------------------- labels
func _label(text: String, pos: Vector3, size := 48) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.018
	l.modulate = Color(1.0, 0.95, 0.4)
	l.outline_modulate = Color(0, 0, 0)
	l.outline_size = 14
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.position = pos
	add_child(l)


func _freeze(n: Node) -> void:
	# Static grid, not a live battlefield: stop AI/physics/audio-timer churn
	# on every instance so it stays exactly where we put it.
	if n.has_method("set_physics_process"):
		n.set_physics_process(false)
	if n.has_method("set_process"):
		n.set_process(false)
	if n.has_method("set_process_unhandled_input"):
		n.set_process_unhandled_input(false)
	if n.has_method("set_process_input"):
		n.set_process_input(false)


# ------------------------------------------------------------- player vehicles
func _place_player_vehicles() -> void:
	var xs := [-35.0, -21.0, -7.0, 7.0, 21.0, 35.0]

	var tank := PlayerTank.new(terrain, projectiles, fx)
	add_child(tank)
	_freeze(tank)
	tank.global_position = Vector3(xs[0], _gy(xs[0], ROW_PLAYER) + 0.04, ROW_PLAYER)
	tank.rotation.y = 0.0
	if tank.blob:
		tank.blob.global_position = tank.global_position + Vector3(0, 0.06, 0)
	if tank.reticle:
		# top_level, only repositioned in the (frozen) per-frame update —
		# would otherwise sit at true world origin (0,0,0) as a stray
		# floating diamond. Not a gameplay bug, just a frozen-showcase artifact.
		tank.reticle.visible = false
	_dummy_player = tank
	_label("PLAYER TANK", tank.global_position + Vector3(0, 4.4, 0))

	var plane := PlayerPlane.new(terrain, projectiles, fx)
	add_child(plane)
	_freeze(plane)
	plane.global_position = Vector3(xs[1], _gy(xs[1], ROW_PLAYER) + 2.2, ROW_PLAYER)
	_label("PLAYER PLANE", plane.global_position + Vector3(0, 3.6, 0))

	var biplane := PlayerPlane.new(terrain, projectiles, fx)
	biplane.biplane = true
	add_child(biplane)
	_freeze(biplane)
	biplane.global_position = Vector3(xs[2], _gy(xs[2], ROW_PLAYER) + 2.2, ROW_PLAYER)
	_label("PLAYER BIPLANE", biplane.global_position + Vector3(0, 4.2, 0))

	var heli := PlayerAlt.Heli.new(terrain, projectiles, fx)
	add_child(heli)
	_freeze(heli)
	heli.global_position = Vector3(xs[3], _gy(xs[3], ROW_PLAYER) + 1.6, ROW_PLAYER)
	_label("PLAYER HELICOPTER", heli.global_position + Vector3(0, 3.2, 0))

	var runner := OnFootBody.new(terrain, projectiles, fx)
	add_child(runner)
	_freeze(runner)
	runner.global_position = Vector3(xs[4], _gy(xs[4], ROW_PLAYER) + 0.1, ROW_PLAYER)
	_label("PLAYER ON-FOOT\n(no visible mesh — VR hands/arms only)", runner.global_position + Vector3(0, 2.6, 0), 36)

	var boat := PlayerBoat.new(terrain, projectiles, fx)
	add_child(boat)
	_freeze(boat)
	boat.global_position = Vector3(xs[5], _gy(xs[5], ROW_PLAYER) + 0.3, ROW_PLAYER)
	_label("PLAYER GUNBOAT\n(beached — normally floats)", boat.global_position + Vector3(0, 3.4, 0), 36)


# ------------------------------------------------------------- enemy vehicles
func _place_enemy_vehicles() -> void:
	var xs := [-35.0, -21.0, -7.0, 7.0, 21.0, 35.0]
	var pl := _dummy_player

	var etank := EnemyTank.new(terrain, projectiles, fx, pl)
	add_child(etank)
	_freeze(etank)
	etank.global_position = Vector3(xs[0], _gy(xs[0], ROW_ENEMY) + 0.04, ROW_ENEMY)
	if etank.blob:
		etank.blob.global_position = etank.global_position + Vector3(0, 0.05, 0)
	_label("ENEMY TANK", etank.global_position + Vector3(0, 3.8, 0))

	var eplane := EnemyPlane.new(terrain, projectiles, fx, pl)
	add_child(eplane)
	_freeze(eplane)
	eplane.global_position = Vector3(xs[1], _gy(xs[1], ROW_ENEMY) + 7.0, ROW_ENEMY)
	_label("ENEMY PLANE\n(orbits high — shown hovering)", eplane.global_position + Vector3(0, 3.2, 0), 36)

	var jeep := EnemyLight.Jeep.new(terrain, projectiles, fx, pl)
	add_child(jeep)
	_freeze(jeep)
	jeep.global_position = Vector3(xs[2], _gy(xs[2], ROW_ENEMY) + 0.05, ROW_ENEMY)
	_label("ENEMY JEEP", jeep.global_position + Vector3(0, 3.0, 0))

	var gunner := EnemyLight.Gunner.new(terrain, projectiles, pl)
	add_child(gunner)
	_freeze(gunner)
	gunner.global_position = Vector3(xs[3], _gy(xs[3], ROW_ENEMY) + 0.02, ROW_ENEMY)
	_label("ENEMY GUNNER\n(infantry)", gunner.global_position + Vector3(0, 2.2, 0), 36)

	var mortar := EnemyLight.Mortar.new(terrain, projectiles, fx, pl)
	add_child(mortar)
	_freeze(mortar)
	mortar.global_position = Vector3(xs[4], _gy(xs[4], ROW_ENEMY), ROW_ENEMY)
	_label("ENEMY MORTAR\nEMPLACEMENT", mortar.global_position + Vector3(0, 2.6, 0), 36)

	var ship := EnemyShip.new(terrain, projectiles, fx, pl)
	add_child(ship)
	_freeze(ship)
	ship.global_position = Vector3(xs[5], _gy(xs[5], ROW_ENEMY) + 0.1, ROW_ENEMY)
	_label("ENEMY WARSHIP\n(beached — normally floats)", ship.global_position + Vector3(0, 5.6, 0), 36)


# ------------------------------------------------------------- nature + misc props
func _place_props_row() -> void:
	var xs := [-28.0, -14.0, 0.0, 14.0, 28.0]

	# Tree/rock/palm reuse WorldDressing's real mesh-building functions
	# (pure ArrayMesh factories, no add_child side effects) and the same
	# ground-sink math _scatter_trees()/_scatter_rocks()/_scatter_palms() use.
	var tree_mi := MeshInstance3D.new()
	tree_mi.mesh = wd._tree_mesh()
	var s := 1.2
	var tgy: float = wd._ground_min(xs[0], ROW_PROPS, 0.3 * s)
	tree_mi.position = Vector3(xs[0], tgy - 0.12 * s, ROW_PROPS)
	tree_mi.scale = Vector3(s, s, s)
	add_child(tree_mi)
	_label("PINE TREE", tree_mi.position + Vector3(0, 6.5 * s, 0))

	var rock_mi := MeshInstance3D.new()
	rock_mi.mesh = wd._rock_mesh()
	var rs := 1.6
	var rgy: float = wd._ground_min(xs[1], ROW_PROPS, 0.7 * rs)
	rock_mi.position = Vector3(xs[1], rgy, ROW_PROPS)
	rock_mi.scale = Vector3(rs, rs, rs)
	add_child(rock_mi)
	_label("ROCK CLUSTER", rock_mi.position + Vector3(0, 2.2 * rs, 0))

	var palm_mi := MeshInstance3D.new()
	palm_mi.mesh = wd._palm_mesh()
	var ps := 1.1
	var pgy: float = wd._ground_min(xs[2], ROW_PROPS, 0.3 * ps)
	palm_mi.position = Vector3(xs[2], pgy - 0.15 * ps, ROW_PROPS)
	palm_mi.scale = Vector3(ps, ps, ps)
	add_child(palm_mi)
	_label("PALM TREE", palm_mi.position + Vector3(0, 7.0 * ps, 0))

	_wreck_at(xs[3], ROW_PROPS)
	_umbrella_at(xs[4], ROW_PROPS)


# Mirrors WorldDressing._build_wrecks() body exactly (that function only
# takes a random count, not an explicit position) so this shows one specimen
# at a controlled grid slot.
func _wreck_at(x: float, z: float) -> void:
	var dark := Color(0.16, 0.15, 0.14)
	var rust := Color(0.35, 0.22, 0.14)
	var yaw := 0.4
	var gy := terrain.height(x, z)
	var cw := cos(yaw)
	var sw := sin(yaw)
	for cx in [-1.6, 1.6]:
		for cz in [-3.2, 3.2]:
			gy = minf(gy, terrain.height(x + cx * cw + cz * sw, z - cx * sw + cz * cw))
	gy -= 0.35
	var st := MeshKit.begin()
	MeshKit.box(st, Transform3D(Basis(), Vector3(0, 0.65, 0)), Vector3(3.2, 0.9, 6.4), dark)
	MeshKit.box(st, Transform3D(Basis(Vector3.UP, 0.3), Vector3(0.3, 1.35, 0.4)), Vector3(2.0, 0.7, 2.4), rust)
	MeshKit.cyl(st, Transform3D(Basis(Vector3.RIGHT, deg_to_rad(75.0)), Vector3(0.3, 1.5, -2.2)), 0.09, 0.07, 3.4, 6, dark)
	var mi := MeshInstance3D.new()
	mi.mesh = MeshKit.commit(st, MeshKit.mat_vcol())
	mi.position = Vector3(x, gy, z)
	mi.rotation.y = yaw
	add_child(mi)
	_label("DESTROYED TANK WRECK", mi.position + Vector3(0, 2.6, 0))


# Mirrors WorldDressing._build_beach_props() body (also random-position-only
# in the source) at one controlled grid slot.
func _umbrella_at(x: float, z: float) -> void:
	var h := terrain.height(x, z)
	var st := MeshKit.begin()
	var col := Color(0.95, 0.35, 0.3)
	MeshKit.cyl(st, Transform3D(Basis(), Vector3(0, 1.35, 0)), 0.05, 0.05, 2.8, 6, Color(0.8, 0.8, 0.78))
	MeshKit.cyl(st, Transform3D(Basis(), Vector3(0, 2.7, 0)), 2.2, 0.15, 0.8, 10, col)
	var towel_y: float = wd._ground_min(x + 1.8, z + 0.5, 0.9) - h + 0.05
	MeshKit.box(st, Transform3D(Basis(Vector3.UP, 0.4), Vector3(1.8, towel_y, 0.5)), Vector3(1.2, 0.04, 2.2), Color(0.3, 0.6, 0.95))
	var mi := MeshInstance3D.new()
	mi.mesh = MeshKit.commit(st, MeshKit.mat_vcol(0.8))
	mi.position = Vector3(x, h, z)
	add_child(mi)
	_label("BEACH UMBRELLA + TOWEL", mi.position + Vector3(0, 4.2, 0))


# ------------------------------------------------------------- structures row
func _place_structures_row() -> void:
	var xs := [-28.0, -14.0, 0.0, 14.0, 28.0]
	var rng := RandomNumberGenerator.new()
	rng.seed = 1

	var mat_wall := MeshKit.mat_tex("res://assets/tex/building.png")
	var mat_roof := MeshKit.mat_tex("res://assets/tex/roof.png", true)
	_building_at(xs[0], ROW_STRUCT, 6.0, 5.0, 3.3, 0.0, mat_wall, mat_roof, rng, false, "VILLAGE HOUSE")
	_building_at(xs[1], ROW_STRUCT, 9.0, 9.0, 14.0, 0.0, mat_wall, MeshKit.mat_vcol(0.9), rng, true, "CITY BUILDING (tall)")

	var stone := MeshKit.mat_tex("res://assets/tex/rock.png", true, 0.95)

	var wall := CastleWall.new(stone, 8.0)
	add_child(wall)
	_freeze(wall)
	wall.global_position = Vector3(xs[2], terrain.height(xs[2], ROW_STRUCT) - 0.35, ROW_STRUCT)
	_label("CASTLE WALL SEGMENT", wall.global_position + Vector3(0, 6.4, 0))

	_castle_tower_at(xs[3], ROW_STRUCT)
	_castle_keep_at(xs[4], ROW_STRUCT)


func _building_at(x: float, z: float, w: float, d: float, hgt: float, yaw: float,
		mat_wall: Material, mat_roof: Material, rng: RandomNumberGenerator, tall: bool, label: String) -> void:
	var before := wd.get_child_count()
	wd._building(x, z, w, d, hgt, yaw, mat_wall, mat_roof, rng, tall)
	# _building() adds "Building" + a static collider StaticBody3D to wd —
	# reparent both into the showcase tree since wd itself is never added.
	while wd.get_child_count() > before:
		var c := wd.get_child(wd.get_child_count() - 1)
		wd.remove_child(c)
		add_child(c)
	_label(label, Vector3(x, terrain.height(x, z) + hgt + 2.0, z))


func _castle_tower_at(x: float, z: float) -> void:
	var stone := MeshKit.mat_tex("res://assets/tex/rock.png", true, 0.95)
	var st := MeshKit.begin()
	MeshKit.cyl(st, Transform3D(Basis(), Vector3(0, 4.5, 0)), 4.2, 3.8, 9.0, 10, Color(0.75, 0.73, 0.70))
	for i in 8:
		var a := TAU * i / 8.0
		MeshKit.box(st, Transform3D(Basis(), Vector3(cos(a) * 3.6, 9.6, sin(a) * 3.6)), Vector3(1.2, 1.2, 1.2), Color(0.7, 0.68, 0.65))
	var mi := MeshInstance3D.new()
	mi.mesh = MeshKit.commit(st, stone)
	var ty: float = wd._ground_min(x, z, 3.8) - 0.4
	mi.position = Vector3(x, ty, z)
	add_child(mi)
	_label("CASTLE CORNER TOWER", mi.position + Vector3(0, 11.0, 0))


func _castle_keep_at(x: float, z: float) -> void:
	var stone := MeshKit.mat_tex("res://assets/tex/rock.png", true, 0.95)
	var st := MeshKit.begin()
	MeshKit.box(st, Transform3D(Basis(), Vector3(0, 5.5, 0)), Vector3(14, 11, 14), Color(0.78, 0.76, 0.72), 0.1)
	MeshKit.prism(st, Transform3D(Basis(), Vector3(0, 11, 0)), 15.0, 15.0, 3.0, Color(0.5, 0.3, 0.25))
	MeshKit.cyl(st, Transform3D(Basis(), Vector3(0, 15.5, 0)), 0.12, 0.1, 6.0, 6, Color(0.4, 0.35, 0.3))
	MeshKit.box(st, Transform3D(Basis(), Vector3(1.1, 17.6, 0)), Vector3(2.2, 1.3, 0.06), Color(0.85, 0.25, 0.2))
	var mi := MeshInstance3D.new()
	mi.mesh = MeshKit.commit(st, stone)
	mi.position = Vector3(x, terrain.height(x, z), z)
	add_child(mi)
	_label("CASTLE KEEP", mi.position + Vector3(0, 20.0, 0))


# ------------------------------------------------------------- NPCs + controller models
func _place_npc_row() -> void:
	var xs := [-21.0, -7.0, 7.0, 21.0]

	var cabbage: Npc.CabbageMan = Npc.CabbageMan.spawn(self, terrain, _dummy_player)
	_freeze(cabbage)
	cabbage.position = Vector3(xs[0], terrain.height(xs[0], ROW_NPC), ROW_NPC)
	_label("CABBAGE MERCHANT STALL", cabbage.position + Vector3(0, 3.6, 0))

	# Direct construction, not Creeper.maybe_spawn() — that wrapper is a 50%
	# coin-flip + random position, unsuitable for a deterministic showcase.
	var creeper := Npc.Creeper.new()
	creeper.terrain = terrain
	creeper.player = _dummy_player
	add_child(creeper)
	_freeze(creeper)
	creeper.global_position = Vector3(xs[1], terrain.height(xs[1], ROW_NPC) + 0.1, ROW_NPC)
	_label("GREEN CREEPER\n(hostile critter)", creeper.global_position + Vector3(0, 2.3, 0), 36)

	var ctrl_l := ControllerVisual.new()
	ctrl_l.is_left = true
	add_child(ctrl_l)
	_freeze(ctrl_l)
	ctrl_l.global_position = Vector3(xs[2], terrain.height(xs[2], ROW_NPC) + 1.0, ROW_NPC)
	ctrl_l.scale = Vector3.ONE * 6.0   # controllers are hand-sized — scaled up so the grid label reads clearly
	_label("TOUCH CONTROLLER (L)\n(MIT-licensed glb asset)", ctrl_l.global_position + Vector3(0, 1.4, 0), 36)
	_ctrl_l = ctrl_l

	var ctrl_r := ControllerVisual.new()
	ctrl_r.is_left = false
	add_child(ctrl_r)
	_freeze(ctrl_r)
	ctrl_r.global_position = Vector3(xs[3], terrain.height(xs[3], ROW_NPC) + 1.0, ROW_NPC)
	ctrl_r.scale = Vector3.ONE * 6.0
	_ctrl_r = ctrl_r
	_label("TOUCH CONTROLLER (R)\n(MIT-licensed glb asset)", ctrl_r.global_position + Vector3(0, 1.4, 0), 36)


func _place_giant_baby() -> void:
	var baby: Npc.GiantBaby = Npc.GiantBaby.spawn(self, terrain, _dummy_player)
	_freeze(baby)
	baby.global_position = Vector3(0, terrain.height(0, ROW_BABY), ROW_BABY)
	_label("GIANT BABY (baby-room boss)", baby.global_position + Vector3(0, 54.0, 0), 64)


# ------------------------------------------------------------- row headers
func _place_ground_labels() -> void:
	var hx := -46.0
	_label("< PLAYER VEHICLES", Vector3(hx, 1.5, ROW_PLAYER), 40)
	_label("< ENEMY VEHICLES", Vector3(hx, 1.5, ROW_ENEMY), 40)
	_label("< TERRAIN PROPS", Vector3(hx, 1.5, ROW_PROPS), 40)
	_label("< STRUCTURES", Vector3(hx, 1.5, ROW_STRUCT), 40)
	_label("< NPCs / CONTROLLERS", Vector3(hx, 1.5, ROW_NPC), 40)


# ------------------------------------------------------------- mountain signpost
func _place_mountain_signpost() -> void:
	# terrain.gd's height() adds a "rim" bump (lines ~55-60) starting at
	# r > 0.62 * HALF (~158.7 units from center) and ramping up to ~99 units
	# tall by r ~ 251 — that IS the game's "mountains". It's baked into the
	# same continuous heightfield as the ground under your feet, generated
	# from the same analytic height(x,z) the vehicles use to place
	# themselves — there is no separate "Mountain" node/mesh/scene anywhere
	# in the codebase to instance here. See the KB writeup for why this
	# makes a literal detached-floating-rock bug structurally unlikely and
	# what's more probably going on instead.
	var z := -95.0
	_label("MOUNTAINS start ~160m outward in EVERY\ndirection (part of the terrain itself —\nsee terrain.gd height(), the 'rim' term).\nFly there with the free-cam to inspect.",
		Vector3(0, _gy(0, z) + 6.0, z), 40)

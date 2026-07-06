# Procedural heightfield terrain, parameterized by a Levels config.
# Height is analytic — gameplay queries height()/normal() directly; there is
# deliberately NO terrain physics body. Only buildings/rocks get colliders.
class_name Terrain
extends Node3D

const SIZE := 512.0
const HALF := SIZE / 2.0
const CHUNKS := 4
const QUADS := 44
const ARENA_RADIUS := 232.0   # default; instances use arena_radius

var arena_radius := 232.0

const VILLAGE_CENTER := Vector2(120, -120)   # legacy default (outdoor)
const POND_CENTER := Vector2(-150, -20)
const SPAWN_CENTER := Vector2(0, 90)

var cfg: Dictionary
var spawn: Vector2

var _noise := FastNoiseLite.new()
var _dune := FastNoiseLite.new()
var _detail := FastNoiseLite.new()

func _init(config: Dictionary = {}) -> void:
	name = "Terrain"
	cfg = config if not config.is_empty() else Levels.get_config("outdoor")
	spawn = cfg.get("spawn", Vector2(0, 90))
	arena_radius = cfg.get("arena_radius", 232.0)
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_noise.frequency = 0.006
	_noise.fractal_octaves = 4
	_noise.seed = 1337
	_dune.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_dune.frequency = 0.045
	_dune.seed = 99
	_detail.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_detail.frequency = 0.15
	_detail.seed = 5

func _ready() -> void:
	_build_chunks()
	if cfg.get("pond", false):
		_build_water()

func height(x: float, z: float) -> float:
	var h := _noise.get_noise_2d(x, z) * float(cfg.get("rolling", 9.0))
	# detail bumps scale per level: indoor floors (gym court, carpet) must be
	# dead flat or every wall/prop base shows a gap
	h += _detail.get_noise_2d(x, z) * 0.35 * float(cfg.get("detail", 1.0))
	if cfg.get("dunes", false):
		var dune_mask: float = clampf((z - 40.0) / 90.0, 0.0, 1.0)
		h += _dune.get_noise_2d(x, z) * 2.2 * dune_mask
	# rim mountains fence the arena (gym has walls instead)
	if cfg.get("rim", true):
		var r: float = Vector2(x, z).length() / HALF
		var rim: float = smoothstep(0.62, 0.98, r)
		h += rim * rim * 85.0
		h += _noise.get_noise_2d(x * 3.0, z * 3.0) * 14.0 * rim
	# level shapes
	if cfg.get("coast", false):
		# ocean along the north: seafloor drops past z = -30. Lift the inland
		# side clear of the sea plane — raw rolling noise dipped below it and
		# flooded half the beach with accidental lagoons
		var coast_t: float = smoothstep(-30.0, -85.0, z)
		h = lerpf(h + float(cfg.get("inland_lift", 0.0)), -6.0, coast_t)
	if cfg.get("island", false):
		var r_i: float = Vector2(x, z).length()
		h = lerpf(h + float(cfg.get("inland_lift", 0.0)), -7.0, smoothstep(125.0, 165.0, r_i))
	if cfg.get("archipelago", false):
		# island chain: max of radial bumps; channels drop to a real seafloor
		var best := -6.5
		for b in [[0.0, 90.0, 85.0, 6.0], [-125.0, -35.0, 55.0, 5.0], [115.0, -75.0, 50.0, 4.5],
				[-10.0, -165.0, 48.0, 5.5], [155.0, 75.0, 40.0, 4.0], [-150.0, 115.0, 42.0, 4.5]]:
			var t: float = smoothstep(b[2] * 0.45, b[2], Vector2(x, z).distance_to(Vector2(b[0], b[1])))
			best = maxf(best, lerpf(b[3], -6.5, t))
		h = h * 0.3 + best
	if cfg.get("volcano", false):
		# caldera bowl with a ring ridge + three spoke bridges over the lava
		var rv: float = Vector2(x, z).length()
		var bowl: float = -8.0 + smoothstep(95.0, 130.0, rv) * 16.0
		var ring: float = 1.2 - absf(rv - 58.0) * 0.55
		var spoke := -99.0
		for a in [0.0, TAU / 3.0, 2.0 * TAU / 3.0]:
			var dirv := Vector2(cos(a), sin(a))
			var d_line: float = absf(Vector2(x, z).dot(Vector2(-dirv.y, dirv.x)))
			if Vector2(x, z).dot(dirv) > -6.0:
				spoke = maxf(spoke, 1.0 - d_line * 0.45)
		var hub: float = 1.5 - rv * 0.14
		h = maxf(maxf(bowl, ring), maxf(spoke, hub))
	# config flatten zones
	for f in cfg.get("flatten", []):
		h = _flatten(h, Vector2(x, z), f[0], f[1], f[2])
	# defaults: spawn + village area (indoor levels set spawn_h 0 — a 1.0
	# target raised a smooth mound in the middle of the gym court)
	h = _flatten(h, Vector2(x, z), spawn, 45.0, float(cfg.get("spawn_h", 1.0)))
	var vil: Dictionary = cfg.get("village", {})
	if not vil.is_empty():
		h = _flatten(h, Vector2(x, z), vil["center"], vil["spread"] + 14.0, float(cfg.get("village_h", 1.5)))
	if cfg.get("pond", false):
		var pd: float = Vector2(x, z).distance_to(POND_CENTER)
		if pd < 34.0:
			h = lerpf(h, -2.6, smoothstep(34.0, 12.0, pd))
	# mud pools sink slightly
	for mp in cfg.get("mud", []):
		var md: float = Vector2(x, z).distance_to(mp)
		if md < 30.0:
			h = lerpf(h, h - 1.2, smoothstep(30.0, 10.0, md))
	return h

func _flatten(h: float, p: Vector2, center: Vector2, radius: float, target: float) -> float:
	var d := p.distance_to(center)
	if d < radius:
		return lerpf(target, h, smoothstep(radius * 0.55, radius, d))
	return h

func normal(x: float, z: float) -> Vector3:
	const E := 0.8
	var hx := height(x + E, z) - height(x - E, z)
	var hz := height(x, z + E) - height(x, z - E)
	return Vector3(-hx, 2.0 * E, -hz).normalized()

func _build_chunks() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = _make_shader()
	mat.set_shader_parameter("tex_sand", load("res://assets/tex/sand.png"))
	mat.set_shader_parameter("tex_grass", load("res://assets/tex/grass.png"))
	mat.set_shader_parameter("tex_rock", load("res://assets/tex/rock.png"))
	var tint: Color = cfg.get("tint", Color(1, 1, 1))
	mat.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
	if cfg.get("coast", false) or cfg.get("island", false) or cfg.get("archipelago", false):
		mat.set_shader_parameter("water_y", -0.55)
	elif cfg.get("volcano", false):
		mat.set_shader_parameter("water_y", float(cfg.get("lava_y", -3.2)))
		mat.set_shader_parameter("water_col", Vector3(1.0, 0.38, 0.05))
		mat.set_shader_parameter("water_emiss", 1.0)
	if cfg.has("floor_tex"):
		var ft := load("res://assets/tex/%s.png" % cfg["floor_tex"])
		mat.set_shader_parameter("tex_floor", ft)
		mat.set_shader_parameter("use_floor", 1.0)
		print("[terrain] floor tex applied: ", cfg["floor_tex"], " loaded=", ft != null,
			" param=", mat.get_shader_parameter("use_floor"))
	var chunk_size := SIZE / CHUNKS
	# quad_div: coarsen the grid by N (menu diorama / preview use — the full
	# 44x44-per-chunk grid x16 chunks is mission-grade, not lobby-grade)
	var qd := int(cfg.get("quad_div", 1))
	for cy in CHUNKS:
		for cx in CHUNKS:
			var x0 := -HALF + cx * chunk_size
			var z0 := -HALF + cy * chunk_size
			var mi := MeshInstance3D.new()
			mi.mesh = _chunk_mesh(x0, z0, chunk_size, maxi(QUADS / qd, 4))
			mi.material_override = mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
			# Terrain has NEVER had real collision — vehicles (tank/plane/
			# boat) never needed it, they sample height() analytically every
			# frame for their own grounding. On-foot mode's
			# XRToolsPlayerBody is a genuine CharacterBody3D that needs a
			# real floor to move_and_slide() against; with nothing here it
			# falls through the world forever the instant physics runs —
			# Alex, live headset, DEBUG level: "I just fall through the
			# ground and fall forever." Not level-specific — every level's
			# terrain was missing this; DEBUG was just where on-foot mode
			# happened to get tested first. create_trimesh_collision() reuses
			# this exact chunk's own geometry, so it can't drift out of sync
			# with the visual mesh or with terrain.height()'s analytic value.
			# no_collision: hangar preview/diorama terrains are scenery — a
			# full trimesh collider per chunk is pure physics-broadphase cost
			if not cfg.get("no_collision", false):
				mi.create_trimesh_collision()
				# Make the WORLD climbable, Spider-Man-style: movement_climb hard-
				# casts the grabbed body to XRToolsClimbable, so the script goes
				# directly on the generated collision StaticBody. Layer 1 stays (it's
				# still the walkable/drivable floor and a grapple anchor); adding
				# CLIMB_LAYER puts it in function_pickup's grab mask so a gripped
				# hand latches onto it. Every cliff and hillside is now climbable
				# without per-mesh tagging.
				for cch in mi.get_children():
					if cch is StaticBody3D:
						cch.set_script(load("res://addons/godot-xr-tools/objects/climbable.gd"))
						cch.collision_layer |= MeshKit.CLIMB_LAYER

func _chunk_mesh(x0: float, z0: float, size: float, quads: int = QUADS) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := size / quads
	var n := quads + 1
	var verts: Array[Vector3] = []
	var cols: Array[Color] = []
	verts.resize(n * n)
	cols.resize(n * n)
	for iz in n:
		for ix in n:
			var x := x0 + ix * step
			var z := z0 + iz * step
			var h := height(x, z)
			verts[iz * n + ix] = Vector3(x, h, z)
			cols[iz * n + ix] = _splat(x, z, h)
	for iz in n:
		for ix in n:
			var i := iz * n + ix
			st.set_color(cols[i])
			st.set_uv(Vector2(verts[i].x, verts[i].z) * 0.22)
			st.set_normal(normal(verts[i].x, verts[i].z))
			st.add_vertex(verts[i])
	for iz in quads:
		for ix in quads:
			var a := iz * n + ix
			var b := a + 1
			var c := a + n
			var d := c + 1
			# Was (a,c,b)/(b,c,d) — confirmed backwards by direct render test
			# 2026-07-03 (tools/terrain_winding_test.gd: ground genuinely
			# invisible from directly overhead, visible from below) — the
			# same never-fixed instance of the MeshKit box/cyl winding bug,
			# just less obvious at typical shallow driving angles than
			# looking straight down from a plane/helicopter. Swapped to
			# match Godot's clockwise-front convention (see
			# godot-winding-convention-clockwise KB doc).
			st.add_index(a); st.add_index(b); st.add_index(c)
			st.add_index(b); st.add_index(d); st.add_index(c)
	return st.commit()

func _splat(x: float, z: float, h: float) -> Color:
	# r=sand g=grass b=rock weights
	var slope := 1.0 - normal(x, z).y
	var rock: float = clampf((slope - 0.18) * 5.0, 0.0, 1.0) + clampf((h - 14.0) / 20.0, 0.0, 1.0)
	rock = clampf(rock, 0.0, 1.0)
	var sand: float
	if cfg.get("dunes", false):
		var dune_mask: float = clampf((z - 40.0) / 90.0, 0.0, 1.0)
		var low_mask: float = clampf((2.0 - h) / 3.0, 0.0, 1.0)
		sand = clampf(maxf(dune_mask, low_mask) - rock, 0.0, 1.0)
	else:
		sand = clampf(clampf((1.5 - h) / 3.0, 0.0, 0.55) - rock, 0.0, 1.0)
	# mud pools force dark sand
	for mp in cfg.get("mud", []):
		if Vector2(x, z).distance_to(mp) < 30.0:
			sand = 1.0 - rock
	var grass: float = clampf(1.0 - rock - sand, 0.0, 1.0)
	return Color(sand, grass, rock)

func _make_shader() -> Shader:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled;
uniform sampler2D tex_sand : source_color, filter_linear_mipmap;
uniform sampler2D tex_grass : source_color, filter_linear_mipmap;
uniform sampler2D tex_rock : source_color, filter_linear_mipmap;
uniform sampler2D tex_floor : source_color, filter_linear_mipmap;
uniform float use_floor = 0.0;
uniform vec3 tint = vec3(1.0);
// water/lava painted INTO the terrain (world-y threshold): separate flat
// planes depth-fight this mesh on the Mobile renderer, painting cannot
uniform float water_y = -9999.0;
uniform vec3 water_col : source_color = vec3(0.10, 0.33, 0.45);
uniform float water_emiss = 0.0;
varying vec3 wpos;
void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	if (wpos.y < water_y) {
		float depth_t = clamp((water_y - wpos.y) / 3.0, 0.0, 1.0);
		vec3 wc = mix(water_col * 1.5, water_col * 0.85, depth_t);
		ALBEDO = wc;
		ROUGHNESS = 0.12;
		if (water_emiss > 0.5) {
			EMISSION = wc * 1.5;
		}
	} else {
	if (use_floor > 0.5) {
		// one giant non-tiling texture across the whole arena (gym court)
		vec2 fuv = UV / (0.22 * 512.0) + 0.5;
		ALBEDO = texture(tex_floor, fuv).rgb * tint;
		ROUGHNESS = 0.55;
	} else {
	vec3 s = texture(tex_sand, UV).rgb;
	vec3 g = texture(tex_grass, UV).rgb;
	vec3 r = texture(tex_rock, UV).rgb;
	float n = texture(tex_rock, UV * 0.037).g;
	vec3 w = COLOR.rgb;
	float shift = (n - 0.5) * 0.9;
	w.r = clamp(w.r + shift * min(w.r, w.g) * 2.0, 0.0, 1.0);
	w.g = clamp(w.g - shift * min(w.r, w.g) * 2.0, 0.0, 1.0);
	float tot = max(w.r + w.g + w.b, 0.001);
	vec3 alb = (s * w.r + g * w.g + r * w.b) / tot * tint;
	// macro patchiness: low-freq brightness variation survives mipping, so
	// the ground reads varied from any distance instead of one flat color.
	// Alex: "some basic macrotexturing across the environments to cut down
	// on the sense of tiling" -- brightness alone still reads as "the same
	// texture, dimmer/brighter" once you notice the base grain repeating,
	// so added a SECOND, decorrelated sample (different texture, frequency,
	// AND offset so it doesn't just double up the same pattern) driving a
	// warm/cool hue drift instead of just luminance. Two independent low-
	// freq axes break up repetition much more convincingly than one.
	float macro = texture(tex_rock, UV * 0.006).g;
	float macro2 = texture(tex_sand, UV * 0.0021 + vec2(37.0, 12.0)).r;
	alb *= mix(0.78, 1.22, macro);
	vec3 cool_shift = vec3(0.94, 1.0, 1.08);
	vec3 warm_shift = vec3(1.06, 1.0, 0.92);
	alb *= mix(cool_shift, warm_shift, macro2);
	float dist = length(VERTEX);
	alb *= mix(1.0, 0.60, clamp((dist - 100.0) / 180.0, 0.0, 1.0));
	ALBEDO = alb;
	ROUGHNESS = 0.95;
	}
	}
}
"""
	return sh

func _build_water() -> void:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 27.0
	cyl.bottom_radius = 27.0
	cyl.height = 0.1
	cyl.radial_segments = 24
	mi.mesh = cyl
	var m := StandardMaterial3D.new()
	# opaque, like the sea — transparent planes depth-fight terrain on Mobile
	m.albedo_color = Color(0.16, 0.32, 0.38)
	m.roughness = 0.05
	m.metallic = 0.45
	mi.material_override = m
	mi.position = Vector3(POND_CENTER.x, -0.85, POND_CENTER.y)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

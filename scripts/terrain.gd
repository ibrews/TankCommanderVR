# Procedural heightfield terrain. 512x512 m arena ringed by mountains.
# Height is analytic (FastNoiseLite + shaping) — gameplay queries height()/normal()
# directly; there is deliberately NO terrain physics body (tanks ground-follow the
# math, projectiles compare y against height()). Only buildings/rocks get colliders.
class_name Terrain
extends Node3D

const SIZE := 512.0
const HALF := SIZE / 2.0
const CHUNKS := 4
const QUADS := 44          # per chunk side
const ARENA_RADIUS := 232.0

const VILLAGE_CENTER := Vector2(120, -120)
const POND_CENTER := Vector2(-150, -20)
const SPAWN_CENTER := Vector2(0, 90)

var _noise := FastNoiseLite.new()
var _dune := FastNoiseLite.new()
var _detail := FastNoiseLite.new()

func _init() -> void:
	name = "Terrain"
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
	_build_water()

func height(x: float, z: float) -> float:
	# rolling base
	var h := _noise.get_noise_2d(x, z) * 9.0
	h += _detail.get_noise_2d(x, z) * 0.35
	# southern dunes
	var dune_mask: float = clampf((z - 40.0) / 90.0, 0.0, 1.0)
	h += _dune.get_noise_2d(x, z) * 2.2 * dune_mask
	# rim mountains fence the arena (start close enough to read as connected walls)
	var r: float = Vector2(x, z).length() / HALF
	var rim: float = smoothstep(0.62, 0.98, r)
	h += rim * rim * 85.0
	h += _noise.get_noise_2d(x * 3.0, z * 3.0) * 14.0 * rim
	# flatten gameplay areas
	h = _flatten(h, Vector2(x, z), VILLAGE_CENTER, 55.0, 1.5)
	h = _flatten(h, Vector2(x, z), SPAWN_CENTER, 45.0, 1.0)
	# pond depression
	var pd: float = Vector2(x, z).distance_to(POND_CENTER)
	if pd < 34.0:
		var t: float = smoothstep(34.0, 12.0, pd)
		h = lerpf(h, -2.6, t)
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
	var chunk_size := SIZE / CHUNKS
	for cy in CHUNKS:
		for cx in CHUNKS:
			var x0 := -HALF + cx * chunk_size
			var z0 := -HALF + cy * chunk_size
			var mi := MeshInstance3D.new()
			mi.mesh = _chunk_mesh(x0, z0, chunk_size)
			mi.material_override = mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)

func _chunk_mesh(x0: float, z0: float, size: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var step := size / QUADS
	var n := QUADS + 1
	# vertex grid
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
	for iz in QUADS:
		for ix in QUADS:
			var a := iz * n + ix
			var b := a + 1
			var c := a + n
			var d := c + 1
			st.add_index(a); st.add_index(c); st.add_index(b)
			st.add_index(b); st.add_index(c); st.add_index(d)
	return st.commit()

func _splat(x: float, z: float, h: float) -> Color:
	# r=sand g=grass b=rock weights
	var slope := 1.0 - normal(x, z).y
	var rock: float = clampf((slope - 0.18) * 5.0, 0.0, 1.0) + clampf((h - 14.0) / 20.0, 0.0, 1.0)
	rock = clampf(rock, 0.0, 1.0)
	var dune_mask: float = clampf((z - 40.0) / 90.0, 0.0, 1.0)
	var low_mask: float = clampf((2.0 - h) / 3.0, 0.0, 1.0)
	var sand: float = clampf(maxf(dune_mask, low_mask) - rock, 0.0, 1.0)
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
void fragment() {
	vec3 s = texture(tex_sand, UV).rgb;
	vec3 g = texture(tex_grass, UV).rgb;
	vec3 r = texture(tex_rock, UV).rgb;
	// low-frequency noise breaks the smooth sand<->grass transition into patches
	float n = texture(tex_rock, UV * 0.037).g;
	vec3 w = COLOR.rgb;
	float shift = (n - 0.5) * 0.9;
	w.r = clamp(w.r + shift * min(w.r, w.g) * 2.0, 0.0, 1.0);
	w.g = clamp(w.g - shift * min(w.r, w.g) * 2.0, 0.0, 1.0);
	float tot = max(w.r + w.g + w.b, 0.001);
	vec3 alb = (s * w.r + g * w.g + r * w.b) / tot;
	// darken with distance so far slopes separate from the pale horizon sky
	float dist = length(VERTEX);
	alb *= mix(1.0, 0.72, clamp((dist - 120.0) / 160.0, 0.0, 1.0));
	ALBEDO = alb;
	ROUGHNESS = 0.95;
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
	m.albedo_color = Color(0.16, 0.32, 0.38, 0.82)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.05
	m.metallic = 0.4
	mi.material_override = m
	mi.position = Vector3(POND_CENTER.x, -0.85, POND_CENTER.y)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

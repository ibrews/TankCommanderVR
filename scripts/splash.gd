# Pre-lobby splash: brief branded panel shown before the hangar/menu builds.
# Everything in this project is procedural (no imported assets), and every
# autoload + to_menu()'s hangar/menu construction is plain synchronous
# GDScript — there is no heavy resource/scene to ResourceLoader-thread-load,
# so this just holds a minimum visible duration while that cheap setup runs,
# same physical "board the rig looks at" shape as MainMenu (see menu.gd) so
# it reads correctly in stereo instead of looking like a flat 2D overlay
# glued in front of the camera.
class_name Splash
extends Node3D

signal finished

const PANEL_W := 2.3
const PANEL_H := 1.2
const ACCENT := Color(1.0, 0.55, 0.15)
const MIN_SECONDS := 1.8

var _t := 0.0
var _bar_fill: MeshInstance3D
var _bar_w := 1.6

func _ready() -> void:
	var back := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(PANEL_W, PANEL_H)
	back.mesh = qm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.05, 0.06, 0.06, 0.96)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	back.material_override = m
	add_child(back)
	var title := Label3D.new()
	title.text = "TANK COMMANDER VR"
	title.font_size = 44 * 4
	title.pixel_size = 0.0004
	title.modulate = ACCENT
	title.position = Vector3(0, 0.28, 0.01)
	add_child(title)
	var sub := Label3D.new()
	sub.text = "Made for Ani"
	sub.font_size = 18 * 4
	sub.pixel_size = 0.0004
	sub.modulate = Color(1.0, 0.75, 0.75)
	sub.position = Vector3(0, 0.10, 0.01)
	add_child(sub)
	# loading bar: dark track + accent fill that scales up on the X axis —
	# cheap "spinner" stand-in that also visibly reflects real elapsed time
	# rather than an infinite un-anchored spin.
	var track := MeshInstance3D.new()
	var tqm := QuadMesh.new()
	tqm.size = Vector2(_bar_w + 0.06, 0.10)
	track.mesh = tqm
	var tm := StandardMaterial3D.new()
	tm.albedo_color = Color(0.16, 0.17, 0.16)
	tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	track.material_override = tm
	track.position = Vector3(0, -0.18, 0.008)
	add_child(track)
	_bar_fill = MeshInstance3D.new()
	var fqm := QuadMesh.new()
	fqm.size = Vector2(_bar_w, 0.06)
	_bar_fill.mesh = fqm
	var fm := StandardMaterial3D.new()
	fm.albedo_color = ACCENT
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_bar_fill.material_override = fm
	_bar_fill.position = Vector3(-_bar_w / 2.0, -0.18, 0.012)
	_bar_fill.scale.x = 0.001
	add_child(_bar_fill)
	var ver := Label3D.new()
	ver.text = "v%s (%d)" % [BuildInfo.VERSION, BuildInfo.CODE]
	ver.font_size = 10 * 4
	ver.pixel_size = 0.0004
	ver.modulate = Color(0.4, 0.42, 0.4)
	ver.position = Vector3(0, -0.34, 0.01)
	add_child(ver)

func _process(delta: float) -> void:
	_t += delta
	var frac := clampf(_t / MIN_SECONDS, 0.0, 1.0)
	# pivot the fill from its left edge so it grows left-to-right, not from center
	_bar_fill.scale.x = maxf(0.001, frac)
	_bar_fill.position.x = -_bar_w / 2.0 + (_bar_w * frac) / 2.0
	if frac >= 1.0:
		set_process(false)
		finished.emit()

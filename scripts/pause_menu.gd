# Minimal in-mission pause panel — RESUME / QUIT TO HANGAR. Reuses MainMenu's
# own laser-pointer contract (pointer(from, dir, clicked) -> Dictionary with
# "dist"/"hit", group "menu") so xr_rig.gd's existing hand-laser plumbing
# drives it for free; no new input wiring needed. Head-locked (parented to
# rig.camera by main.gd) so it's always in view wherever you're looking when
# you pause, seated or on-foot.
class_name PauseMenu
extends Node3D

signal resume_requested
signal quit_requested

const PANEL_W := 0.7
const PANEL_H := 0.42
const BTN_COL := Color(0.16, 0.19, 0.16)
const BTN_HOVER := Color(0.45, 0.30, 0.10)

var _buttons: Array[Dictionary] = []
var _hovered: Dictionary = {}

func _init() -> void:
	name = "PauseMenu"
	process_mode = Node.PROCESS_MODE_ALWAYS   # must still respond while get_tree().paused

func _ready() -> void:
	add_to_group("menu")
	var back := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(PANEL_W, PANEL_H)
	back.mesh = qm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.07, 0.09, 0.08, 0.94)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	back.material_override = m
	add_child(back)
	var title := Label3D.new()
	title.text = "PAUSED"
	title.font_size = 30 * 4
	title.pixel_size = 0.0004
	title.position = Vector3(0, 0.13, 0.012)
	add_child(title)
	_button("resume", "RESUME", Vector2(0, 0.0), Vector2(0.56, 0.11))
	_button("quit", "QUIT TO HANGAR", Vector2(0, -0.14), Vector2(0.56, 0.11))

func _button(id: String, txt: String, pos: Vector2, size: Vector2) -> void:
	var mi := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = size
	mi.mesh = qm
	var m := StandardMaterial3D.new()
	m.albedo_color = BTN_COL
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = m
	mi.position = Vector3(pos.x, pos.y, 0.008)
	add_child(mi)
	var l := Label3D.new()
	l.text = txt
	l.font_size = 18 * 4
	l.pixel_size = 0.0004
	l.position = Vector3(pos.x, pos.y, 0.014)
	add_child(l)
	_buttons.append({"id": id, "pos": pos, "size": size, "mat": m})

func pointer(from: Vector3, dir: Vector3, clicked: bool) -> Dictionary:
	var plane_n := global_transform.basis.z
	var denom := dir.dot(plane_n)
	if absf(denom) < 0.001:
		return {}
	var t := (global_position - from).dot(plane_n) / denom
	if t < 0.05 or t > 12.0:
		return {}
	var hit_world := from + dir * t
	var local := to_local(hit_world)
	if absf(local.x) > PANEL_W / 2 + 0.05 or absf(local.y) > PANEL_H / 2 + 0.05:
		return {}
	var over: Dictionary = {}
	for b in _buttons:
		if absf(local.x - b.pos.x) < b.size.x / 2 and absf(local.y - b.pos.y) < b.size.y / 2:
			over = b
			break
	if over != _hovered:
		if not _hovered.is_empty():
			(_hovered.mat as StandardMaterial3D).albedo_color = BTN_COL
		_hovered = over
		if not over.is_empty():
			(over.mat as StandardMaterial3D).albedo_color = BTN_HOVER
			Sfx.play_ui("click", -18.0)
	if clicked and not over.is_empty():
		match over.id:
			"resume":
				resume_requested.emit()
			"quit":
				quit_requested.emit()
	return {"dist": t, "hit": true}

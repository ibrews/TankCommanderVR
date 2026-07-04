# VR main menu: floating board selected with controller lasers (trigger to
# click). Mode / level / difficulty rows, multi-page How to Play, and the
# dedication. Desktop fallback keys for development.
class_name MainMenu
extends Node3D

signal start_requested(mode: int, level_id: String, difficulty: int, mutator: String)
signal join_requested

const PANEL_W := 2.3
const PANEL_H := 1.78
const ACCENT := Color(1.0, 0.55, 0.15)
const BTN_COL := Color(0.16, 0.19, 0.16)
const BTN_HOVER := Color(0.28, 0.33, 0.28)
const BTN_SEL := Color(0.45, 0.30, 0.10)

var sel_mode: int = Game.Mode.SOLO
var sel_endless := false
var sel_level := "outdoor"
var sel_diff := 1
var sel_mut := ""
var sel_vehicle := 0
var sel_time := 0   # 0 day, 1 golden hour, 2 night
const TIMES := ["TIME: DAY", "TIME: GOLDEN HOUR", "TIME: NIGHT OPS"]
var page := 0   # 0 main, 1..4 how-to

const MUTATORS := [["", "NORMAL"], ["lowg", "LOW-G"], ["underwater", "WATER"], ["balloon", "BALLOON"], ["paintball", "PAINT"]]
const VEHICLES := [["tank", "TANK"], ["plane", "PLANE"], ["biplane", "BIPLANE"], ["heli", "HELI"], ["runner", "RUNNER"], ["boat", "GUNBOAT"]]

var _buttons: Array[Dictionary] = []
var _labels_to_clear: Array[Node] = []
var _hovered: Dictionary = {}

const HOWTO := [
	"",  # page 0 unused
	"STARTING THE TANK\n\n1. Flip BATTERY (left console)\n2. Open FUEL PUMP cover, flip switch\n3. HOLD green STARTER until the engine catches\n4. Shift GEAR to D (right pedestal)\n\nOr press X / click left stick for auto-start.",
	"DRIVING\n\nGrab the two floor TILLERS with your grips.\nPush both forward = drive. Pull one back = turn.\nOpposite directions = spin in place!\n\nOr just use the LEFT STICK.\nWatch the mud — it slows you down.\n\nGETTING OUT: grab the yellow HATCH lever\nabove your head and pull. To climb back in,\nwalk up to your abandoned vehicle and\nsqueeze either grip near the seat.",
	"FIGHTING\n\nGrab the turret STICK (right pedestal).\nMove it to aim. TRIGGER = cannon.\nAfter each shot pull the red BREECH LEVER to reload.\nA (while gripping) = machine gun.\n\nROCKETS: left console — open the red cover,\nflip ARM, press the big red button.",
	"CO-OP + VERSUS (same Wi-Fi)\n\nCO-OP: one headset hosts, the other joins.\nHost DRIVES + machine gun. Friend runs the\nTURRET: cannon, breech, and the heavy rockets.\n\nVERSUS: tank vs tank duel. First to 5 wins.\n\nPLANE MODE: stick + throttle. Bombs away!",
]

func _ready() -> void:
	add_to_group("menu")
	_build_board()
	_show_main()
	Sfx.music_menu()
	Sfx.coach("vo_welcome", 4, 2.0)
	get_tree().create_timer(6.5).timeout.connect(func():
		if page == 0 and is_inside_tree():
			Sfx.coach("vo_menu_pick", 1, 60.0))

func _build_board() -> void:
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
	# frame
	var st := MeshKit.begin()
	MeshKit.box(st, Transform3D(Basis(), Vector3(0, PANEL_H / 2 + 0.03, -0.01)), Vector3(PANEL_W + 0.1, 0.06, 0.04), Color(0.5, 0.35, 0.12))
	MeshKit.box(st, Transform3D(Basis(), Vector3(0, -PANEL_H / 2 - 0.03, -0.01)), Vector3(PANEL_W + 0.1, 0.06, 0.04), Color(0.5, 0.35, 0.12))
	var frame := MeshInstance3D.new()
	frame.mesh = MeshKit.commit(st, MeshKit.mat_vcol(0.6))
	add_child(frame)

func _clear_page() -> void:
	for b in _buttons:
		b.mesh.queue_free()
		b.label.queue_free()
	_buttons.clear()
	for l in _labels_to_clear:
		l.queue_free()
	_labels_to_clear.clear()
	_hovered = {}

func _text(txt: String, pos: Vector2, size := 24, col := Color(0.92, 0.94, 0.90), align_left := false) -> Label3D:
	var l := Label3D.new()
	l.text = txt
	l.font_size = size * 4
	l.pixel_size = 0.0004
	l.modulate = col
	if align_left:
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	l.position = Vector3(pos.x, pos.y, 0.012)
	add_child(l)
	_labels_to_clear.append(l)
	return l

func _button(id: String, txt: String, pos: Vector2, size: Vector2, font := 20) -> void:
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
	l.font_size = font * 4
	l.pixel_size = 0.0004
	l.position = Vector3(pos.x, pos.y, 0.014)
	add_child(l)
	_buttons.append({"id": id, "pos": pos, "size": size, "mesh": mi, "mat": m, "label": l})

func _show_main() -> void:
	_clear_page()
	page = 0
	_text("TANK COMMANDER VR", Vector2(0, 0.74), 44, ACCENT)
	_text("Made for Ani", Vector2(0, 0.63), 22, Color(1.0, 0.75, 0.75))
	_text("MODE", Vector2(-1.0, 0.52), 15, Color(0.7, 0.75, 0.7))
	var modes := [["solo", "SOLO"], ["endless", "ENDLESS"], ["coop", "CO-OP HOST"], ["versus", "VERSUS HOST"], ["join", "JOIN GAME"]]
	for i in modes.size():
		_button("mode:" + modes[i][0], modes[i][1], Vector2(-0.84 + i * 0.435, 0.45), Vector2(0.41, 0.12), 12)
	_text("BATTLEFIELD", Vector2(-0.93, 0.33), 15, Color(0.7, 0.75, 0.7))
	for i in Levels.ORDER.size():
		var id: String = Levels.ORDER[i]
		var row := i / 6
		var col := i % 6
		_button("level:" + id, Levels.CONFIGS[id]["title"],
			Vector2(-0.915 + col * 0.365, 0.26 - row * 0.135), Vector2(0.335, 0.12), 11)
	_text("DIFFICULTY", Vector2(-0.94, 0.02), 15, Color(0.7, 0.75, 0.7))
	for i in 3:
		_button("diff:%d" % i, ["EASY", "MEDIUM", "HARD"][i], Vector2(-0.80 + i * 0.42, -0.05), Vector2(0.38, 0.12), 14)
	_button("timecycle", TIMES[sel_time], Vector2(0.72, -0.05), Vector2(0.62, 0.12), 12)
	_text("SILLY MODE", Vector2(-0.94, -0.17), 15, Color(0.7, 0.75, 0.7))
	for i in MUTATORS.size():
		_button("mut:" + MUTATORS[i][0], MUTATORS[i][1], Vector2(-0.86 + i * 0.44, -0.24), Vector2(0.41, 0.12), 14)
	_button("vehcycle", "VEHICLE: " + VEHICLES[sel_vehicle][1], Vector2(-0.72, -0.42), Vector2(0.85, 0.14), 15)
	_button("howto", "HOW TO PLAY", Vector2(0.22, -0.42), Vector2(0.62, 0.14), 16)
	_button("helptoggle", "HELP: ON" if Game.help_on else "HELP: OFF", Vector2(0.72, -0.42), Vector2(0.42, 0.14), 12)
	_button("viewtoggle", "VIEW: 3RD" if Game.third_person else "VIEW: 1ST", Vector2(1.14, -0.42), Vector2(0.42, 0.14), 12)
	_button("start", "START!", Vector2(0.55, -0.62), Vector2(0.9, 0.20), 28)
	_text("point + trigger · hands work too: pinch = trigger, squeeze = grab", Vector2(-0.45, -0.62), 11, Color(0.55, 0.6, 0.55))
	_text("secret: squeeze EVERYTHING + A...", Vector2(0, -0.78), 11, Color(0.45, 0.5, 0.45))
	# Alex: "we need to list the build number and date on the lobby menu" --
	# this line already existed but at font size 9 in near-invisible dim
	# gray, easy to miss entirely. Made it actually readable.
	_text("BUILD v%s (%d) · %s" % [BuildInfo.VERSION, BuildInfo.CODE, BuildInfo.BUILT],
		Vector2(-1.02, -0.855), 13, Color(0.75, 0.78, 0.72), true)
	_refresh_selection()

func _show_howto(p: int) -> void:
	_clear_page()
	page = p
	_text("HOW TO PLAY  %d/4" % p, Vector2(0, 0.60), 30, ACCENT)
	var body := _text(HOWTO[p], Vector2(-1.02, 0.05), 17, Color(0.92, 0.94, 0.9), true)
	body.position.x = -1.02
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	if p > 1:
		_button("howto_prev", "< BACK", Vector2(-0.8, -0.55), Vector2(0.5, 0.16), 18)
	if p < 4:
		_button("howto_next", "NEXT >", Vector2(0.0, -0.55), Vector2(0.5, 0.16), 18)
	_button("howto_close", "DONE", Vector2(0.8, -0.55), Vector2(0.5, 0.16), 18)
	Sfx.vo("vo_howto%d" % mini(p, 4), 3, 3.0)

func _refresh_selection() -> void:
	for b in _buttons:
		var sel := false
		var id: String = b.id
		if id.begins_with("mode:"):
			sel = _mode_id() == id
		elif id.begins_with("level:"):
			sel = id == "level:" + sel_level
		elif id.begins_with("diff:"):
			sel = id == "diff:%d" % sel_diff
		elif id.begins_with("mut:"):
			sel = id == "mut:" + sel_mut
		b.mat.albedo_color = BTN_SEL if sel else (BTN_HOVER if b == _hovered else BTN_COL)

func _mode_index(m: int) -> int:
	return [Game.Mode.SOLO, Game.Mode.COOP, Game.Mode.VERSUS, Game.Mode.PLANE].find(m)

func _mode_id() -> String:
	if sel_endless:
		return "mode:endless"
	match sel_mode:
		Game.Mode.COOP: return "mode:coop"
		Game.Mode.VERSUS: return "mode:versus"
		Game.Mode.PLANE: return "mode:plane"
		_: return "mode:solo"

# ---------------- pointer interface (called by the rigs)
# Returns true if the ray hits the panel (for laser length/visuals).
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
	if absf(local.x) > PANEL_W / 2 + 0.1 or absf(local.y) > PANEL_H / 2 + 0.1:
		return {}
	var over: Dictionary = {}
	for b in _buttons:
		if absf(local.x - b.pos.x) < b.size.x / 2 and absf(local.y - b.pos.y) < b.size.y / 2:
			over = b
			break
	if over != _hovered:
		_hovered = over
		if not over.is_empty():
			Sfx.play_ui("click", -18.0)
		_refresh_selection()
	if clicked and not over.is_empty():
		_press(over.id)
	return {"dist": t, "hit": true}

func _press(id: String) -> void:
	Sfx.play_ui("ui_select", -6.0)
	match id:
		"howto":
			_show_howto(1)
		"howto_prev":
			_show_howto(page - 1)
		"howto_next":
			_show_howto(page + 1)
		"howto_close":
			_show_main()
		"start":
			Game.vehicle = VEHICLES[sel_vehicle][0]
			Game.time_of_day = sel_time
			start_requested.emit(sel_mode, "endless" if sel_endless else sel_level, sel_diff, sel_mut)
		"helptoggle":
			Game.help_on = not Game.help_on
			Game.save_prefs()
			if Game.help_on:
				Sfx.vo("vo_help_on", 3, 1.0)
			_show_main()
		"viewtoggle":
			Game.toggle_camera_mode()
			_show_main()
		"vehcycle":
			sel_vehicle = (sel_vehicle + 1) % VEHICLES.size()
			match VEHICLES[sel_vehicle][0]:
				"heli": Sfx.vo("vo_heli", 2, 30.0)
				"runner": Sfx.vo("vo_runner", 2, 30.0)
				"biplane": Sfx.vo("vo_biplane", 2, 30.0)
				"plane": Sfx.vo("vo_plane", 2, 30.0)
				"boat": Sfx.vo("vo_boat", 2, 30.0)
			_show_main()
		"timecycle":
			sel_time = (sel_time + 1) % 3
			if sel_time == 2:
				Sfx.vo("vo_night", 2, 30.0)
			_show_main()
		_:
			if id.begins_with("mode:"):
				sel_endless = false
				match id.trim_prefix("mode:"):
					"solo": sel_mode = Game.Mode.SOLO
					"endless":
						sel_mode = Game.Mode.SOLO
						sel_endless = true
						Sfx.vo("vo_endless", 2, 30.0)
					"coop":
						sel_mode = Game.Mode.COOP
						Sfx.vo("vo_coop", 2, 20.0)
					"versus":
						sel_mode = Game.Mode.VERSUS
						Sfx.vo("vo_versus", 2, 20.0)
					"plane":
						sel_mode = Game.Mode.PLANE
						Sfx.vo("vo_plane", 2, 20.0)
					"join":
						join_requested.emit()
			elif id.begins_with("level:"):
				sel_level = id.trim_prefix("level:")
				if sel_level == "gym":
					Sfx.vo("vo_gym", 2, 30.0)
			elif id.begins_with("mut:"):
				sel_mut = id.trim_prefix("mut:")
				match sel_mut:
					"lowg": Sfx.vo("vo_lowg", 2, 30.0)
					"underwater": Sfx.vo("vo_underwater", 2, 30.0)
					"balloon": Sfx.vo("vo_balloon", 2, 30.0)
					"paintball": Sfx.vo("vo_paintball", 2, 30.0)
			elif id.begins_with("diff:"):
				sel_diff = int(id.trim_prefix("diff:"))
				if sel_diff == 0:
					Sfx.vo("vo_easy", 2, 20.0)
				elif sel_diff == 2:
					Sfx.vo("vo_hard", 2, 20.0)
			_refresh_selection()

# desktop keys for development
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_1, KEY_2, KEY_3, KEY_4, KEY_5:
				sel_level = Levels.ORDER[event.keycode - KEY_1]
				_refresh_selection()
			KEY_M:
				sel_mode = (sel_mode + 1) % 4
				_refresh_selection()
			KEY_D:
				sel_diff = (sel_diff + 1) % 3
				_refresh_selection()
			KEY_H:
				_show_howto(1)
			KEY_ENTER:
				start_requested.emit(sel_mode, sel_level, sel_diff, sel_mut)

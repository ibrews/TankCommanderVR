# VR main menu: floating board selected with controller lasers (trigger to
# click). Mode / level / difficulty rows, multi-page How to Play, and the
# dedication. Desktop fallback keys for development.
class_name MainMenu
extends Node3D

signal start_requested(mode: int, level_id: String, difficulty: int, mutator: String)
signal join_requested
# hangar live previews (main.gd): vehicle model, level diorama, TOD lighting
signal vehicle_changed(vehicle_id: String)
signal level_changed(level_id: String)
signal time_changed(t: int)

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
const VEHICLES := [["tank", "TANK"], ["jeep", "JEEP"], ["plane", "PLANE"], ["biplane", "BIPLANE"], ["heli", "HELI"], ["runner", "RUNNER"], ["boat", "GUNBOAT"]]

var _buttons: Array[Dictionary] = []
var _labels_to_clear: Array[Node] = []
var _hovered: Dictionary = {}

# persistent status line (join/relay progress) — survives page rebuilds so it
# doesn't leak a fresh Label3D on every relay_status tick.
var _status: Label3D = null
# log upload plumbing
const LOG_URL := "https://tank-commander.alexcoulombe.workers.dev/logs"
const LOG_PATH := "user://logs/godot.log"
const LOGS_DIR := "user://logs"
# Marks the last ROTATED (previous-run) log we already auto-shipped, so a
# crash log doesn't get re-uploaded on every subsequent boot forever.
const AUTO_MARKER_PATH := "user://logs/.last_auto_uploaded"
var _http: HTTPRequest = null
var _auto_http: HTTPRequest = null
var _upload_btn: Dictionary = {}

const HOWTO := [
	"",  # page 0 unused
	"STARTING THE TANK\n\n1. Flip BATTERY (left console)\n2. Open FUEL PUMP cover, flip switch\n3. HOLD green STARTER until the engine catches\n4. Shift GEAR to D (right pedestal)\n\nOr press X for auto-start.\nTap A anytime to change the radio station.",
	"DRIVING\n\nGrab the two floor TILLERS with your grips.\nPush both forward = drive. Pull one back = turn.\nOpposite directions = spin in place!\n\nOr use the LEFT STICK to steer and hold the\nRIGHT TRIGGER for throttle — works in every\nvehicle (tank, jeep, boat, plane).\nWatch the mud — it slows you down.\n\nGETTING OUT: hold the LEFT TRIGGER for one\nsecond (or pull the yellow HATCH lever).\nTo climb back in, walk up to your vehicle\nand squeeze a grip (or hold LEFT TRIGGER).",
	"FIGHTING\n\nGrab the turret STICK (right pedestal).\nMove it to aim. TRIGGER (while gripping) = cannon.\nEmpty-handed, squeeze GRIP to fire instead —\nthe trigger is busy driving.\nAfter each shot pull the red BREECH LEVER to reload.\nA (while gripping) = machine gun.\n\nROCKETS: left console — open the red cover,\nflip ARM, press the big red button.",
	"CO-OP + VERSUS (same Wi-Fi or online)\n\nCO-OP: one headset hosts, the other joins.\nHost DRIVES + machine gun. Friend runs the\nTURRET: cannon, breech, and the heavy rockets.\nSwap seats anytime: squeeze both grips + Y.\n\nVERSUS: pick your vehicle — tank, jeep, boat\nor plane — and duel. First to 5 wins.\n\nPLANE MODE: stick + throttle. Bombs away!",
]

# Set true (before add_child, so it's already true by the time _ready()
# runs) when main.gd instantiates this board as the mid-mission pause
# overlay rather than the real hangar menu -- skips the welcome VO/menu
# music, which would otherwise replay every time the player pauses.
var is_pause_overlay := false

func _ready() -> void:
	add_to_group("menu")
	_http = HTTPRequest.new()
	add_child(_http)
	_http.request_completed.connect(_on_log_uploaded)
	_build_board()
	_show_main()
	if is_pause_overlay:
		return
	# One-shot per real hangar visit (not the pause overlay, which builds a
	# fresh MainMenu every time you pause) — see _maybe_auto_upload_stale_log().
	_maybe_auto_upload_stale_log()
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
	# self-reported display name (Meta username API needs a GDExtension that
	# doesn't exist for Godot yet — auto-gen a fun default, click to re-roll)
	if Game.display_name == "":
		Game.display_name = Game.default_name()
	_button("namereroll", Game.display_name, Vector2(0.88, 0.63), Vector2(0.5, 0.11), 11)
	_button("helptoggle", "HELP: ON" if Game.help_on else "HELP: OFF", Vector2(0.72, -0.42), Vector2(0.42, 0.14), 12)
	_button("viewtoggle", ["VIEW: 1ST", "VIEW: 3RD", "VIEW: FAR"][Game.cam_mode], Vector2(1.14, -0.42), Vector2(0.42, 0.14), 12)
	# Runner (on-foot) locomotion prefs — only meaningful once you're walking,
	# but kept on the main page (not buried in HOWTO, which is read-only text)
	# same as help/view above so they're reachable without a dedicated menu.
	_text("RUNNER", Vector2(-1.0, -0.545), 13, Color(0.7, 0.75, 0.7))
	_button("turntoggle", "TURN: SMOOTH" if Game.smooth_turn else "TURN: SNAP", Vector2(-0.78, -0.58), Vector2(0.5, 0.13), 12)
	_button("sprinttoggle", "STICK SPRINT: ON" if Game.sprint_stick else "STICK SPRINT: OFF", Vector2(-0.19, -0.58), Vector2(0.62, 0.13), 12)
	_button("start", "START!", Vector2(0.62, -0.58), Vector2(0.58, 0.19), 26)
	# help/support: ship this session's log to the relay for triage
	_button("uploadlog", "UPLOAD LOG", Vector2(-0.85, -0.70), Vector2(0.42, 0.11), 11)
	_upload_btn = _buttons.back()
	_text("point + trigger · hands work too: pinch = trigger, squeeze = grab", Vector2(-0.15, -0.70), 11, Color(0.55, 0.6, 0.55))
	_text("secret: squeeze EVERYTHING + A...", Vector2(0.55, -0.80), 10, Color(0.45, 0.5, 0.45))
	# Alex: "we need to list the build number and date on the lobby menu" --
	# this line already existed but at font size 9 in near-invisible dim
	# gray, easy to miss entirely. Made it actually readable.
	_text("BUILD v%s (%d) · %s" % [BuildInfo.VERSION, BuildInfo.CODE, BuildInfo.BUILT],
		Vector2(-1.02, -0.80), 13, Color(0.75, 0.78, 0.72), true)
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

# ---------------- status line (join / relay progress)
# One reusable label near the board's foot; safe to call from signals.
func set_status(txt: String) -> void:
	if _status == null or not is_instance_valid(_status):
		_status = Label3D.new()
		_status.font_size = 14 * 4
		_status.pixel_size = 0.0004
		_status.modulate = Color(1.0, 0.85, 0.55)
		_status.position = Vector3(0, -0.80, 0.014)
		add_child(_status)
	_status.text = txt

# ---------------- log upload (plain HTTP POST, not the websocket relay)
func _upload_log() -> void:
	_set_upload_label("Uploading...")
	if not FileAccess.file_exists(LOG_PATH):
		_set_upload_label("No log yet")
		return
	var f := FileAccess.open(LOG_PATH, FileAccess.READ)
	if f == null:
		_set_upload_label("Read failed")
		return
	var body := f.get_as_text()
	f.close()
	if _post_log(_http, body, "manual") != OK:
		_set_upload_label("Failed")

func _on_log_uploaded(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	if result == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300:
		_set_upload_label("Uploaded!")
	else:
		_set_upload_label("Failed (%d)" % code)

func _set_upload_label(txt: String) -> void:
	if _upload_btn.has("label") and is_instance_valid(_upload_btn["label"]):
		_upload_btn["label"].text = txt

func _post_log(http: HTTPRequest, body: String, kind: String) -> Error:
	var dev := OS.get_unique_id()
	if dev.is_empty():
		dev = OS.get_model_name()
	var url := "%s?device=%s&kind=%s" % [LOG_URL, dev.uri_encode(), kind]
	return http.request(url, ["Content-Type: text/plain"], HTTPClient.METHOD_POST, body)

# Crash-safety net for "we kept crashing"/"I kept getting disconnected"
# debugging (Alex, 2026-07-06): the manual UPLOAD LOG button only ever reads
# the CURRENT run's user://logs/godot.log — but Godot's own file-logging
# rotation (project.godot's file_logging/*) renames the PREVIOUS run's log to
# a timestamped file the instant a new run starts. If the app crashed and
# relaunched, that previous (crashed) session's log is already rotated away
# by the time anyone thinks to press the button, and there's no way to pick a
# specific rotated file from the menu UI — so exactly the session you'd most
# want data from was unreachable. Silently ships the most recent ROTATED log
# once per hangar visit (not the pause overlay — that rebuilds every pause)
# if it hasn't already been sent, tagged kind=auto so it's distinguishable
# from a deliberate manual click in the /logs/list view.
func _maybe_auto_upload_stale_log() -> void:
	# Devices only: desktop dev runs rotate a new log every headless test
	# invocation, which flooded the KV sink with near-identical auto uploads
	# (2026-07-16 audit). Fort-side logs are on local disk anyway.
	if OS.get_name() != "Android":
		return
	var dir := DirAccess.open(LOGS_DIR)
	if dir == null:
		return
	var last_marker := ""
	if FileAccess.file_exists(AUTO_MARKER_PATH):
		var mf := FileAccess.open(AUTO_MARKER_PATH, FileAccess.READ)
		if mf:
			last_marker = mf.get_as_text().strip_edges()
			mf.close()
	var best_name := ""
	var best_time := 0
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname != "godot.log" and fname.begins_with("godot") and fname.ends_with(".log"):
			var t := FileAccess.get_modified_time(LOGS_DIR.path_join(fname))
			if t > best_time:
				best_time = t
				best_name = fname
		fname = dir.get_next()
	dir.list_dir_end()
	if best_name == "" or best_name == last_marker:
		return
	var f := FileAccess.open(LOGS_DIR.path_join(best_name), FileAccess.READ)
	if f == null:
		return
	var body := f.get_as_text()
	f.close()
	if body.is_empty():
		return
	# Separate HTTPRequest node from the manual button's _http: this can fire
	# while the player is already mid-click on the real button, and one node
	# can't run two requests at once. Doesn't touch _upload_btn's label —
	# nobody asked for this one, so no on-screen feedback for it either way.
	#
	# Marker written OPTIMISTICALLY before the request and rolled back on
	# failure — the old written-only-on-success ordering meant every fresh
	# hangar visit while the first attempt was still in flight (or after a
	# quiet failure) re-POSTed the same log, duplicating entries in the KV
	# sink (2026-07-16 audit; the sink showed the same 554-byte log 7+ times).
	var wf := FileAccess.open(AUTO_MARKER_PATH, FileAccess.WRITE)
	if wf:
		wf.store_string(best_name)
		wf.close()
	_auto_http = HTTPRequest.new()
	add_child(_auto_http)
	_auto_http.request_completed.connect(func(result: int, code: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
		if not (result == HTTPRequest.RESULT_SUCCESS and code >= 200 and code < 300):
			# roll back so the next hangar visit retries (e.g. no Wi-Fi yet)
			var rb := FileAccess.open(AUTO_MARKER_PATH, FileAccess.WRITE)
			if rb:
				rb.store_string(last_marker)
				rb.close()
		_auto_http.queue_free())
	_post_log(_auto_http, body, "auto")

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
		"namereroll":
			Game.display_name = Game.default_name()
			_show_main()
		"helptoggle":
			Game.help_on = not Game.help_on
			Game.save_prefs()
			if Game.help_on:
				Sfx.vo("vo_help_on", 3, 1.0)
			_show_main()
		"viewtoggle":
			Game.toggle_camera_mode()
			_show_main()
		"turntoggle":
			Game.smooth_turn = not Game.smooth_turn
			Game.save_prefs()
			_show_main()
		"sprinttoggle":
			Game.sprint_stick = not Game.sprint_stick
			Game.save_prefs()
			_show_main()
		"uploadlog":
			_upload_log()
		"vehcycle":
			sel_vehicle = (sel_vehicle + 1) % VEHICLES.size()
			vehicle_changed.emit(VEHICLES[sel_vehicle][0])
			match VEHICLES[sel_vehicle][0]:
				"heli": Sfx.vo("vo_heli", 2, 30.0)
				"runner": Sfx.vo("vo_runner", 2, 30.0)
				"biplane": Sfx.vo("vo_biplane", 2, 30.0)
				"plane": Sfx.vo("vo_plane", 2, 30.0)
				"boat": Sfx.vo("vo_boat", 2, 30.0)
			_show_main()
		"timecycle":
			sel_time = (sel_time + 1) % 3
			time_changed.emit(sel_time)
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
				level_changed.emit(sel_level)
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

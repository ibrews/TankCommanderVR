# Autoload "EventLog": lightweight structured play-session log, written to
# user://events.jsonl (on Quest: /sdcard/Android/data/com.agilelens.tankcommander/
# files/events.jsonl — same user:// convention as tune.gd's tuning.cfg). Exists
# because Alex plays solo with nobody watching; this is what lets a future
# session see "what actually happened" without live narration. Deliberately
# NOT a network upload — embedding any upload credential (GitHub token, etc.)
# in a shipped, MIT-licensed public-repo APK is extractable by anyone who
# pulls the .apk, so this stays a local file pulled via adb/HzOSDevMCP
# (`pull_file` / `list_device_files`) instead. One JSON object per line, so a
# partially-written last line from a hard kill never corrupts earlier history.
extends Node

const PATH := "user://events.jsonl"
const MAX_LINES := 2000   # rotate before this grows unbounded across months of play

func _ready() -> void:
	log_event("app_start", {"version": BuildInfo.VERSION, "code": BuildInfo.CODE, "built": BuildInfo.BUILT})

func log_event(kind: String, data: Dictionary = {}) -> void:
	var entry := {"t": Time.get_datetime_string_from_system(true), "kind": kind}
	for k in data:
		entry[k] = data[k]
	_append_line(JSON.stringify(entry))

func _append_line(line: String) -> void:
	var lines: Array[String] = []
	if FileAccess.file_exists(PATH):
		var rf := FileAccess.open(PATH, FileAccess.READ)
		if rf:
			while not rf.eof_reached():
				var l := rf.get_line()
				if l != "":
					lines.append(l)
			rf.close()
	lines.append(line)
	if lines.size() > MAX_LINES:
		lines = lines.slice(lines.size() - MAX_LINES)
	var wf := FileAccess.open(PATH, FileAccess.WRITE)
	if wf:
		for l in lines:
			wf.store_line(l)
		wf.close()
	else:
		push_warning("[event_log] could not open " + PATH + " for writing")

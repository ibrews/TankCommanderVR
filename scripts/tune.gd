# Autoload "Tune": every gameplay dial in one place, overridable without a
# rebuild for playtesting. Priority: user://tuning.cfg > defaults below.
# On first run a commented template is written to user://tuning.cfg —
# on Quest that's /sdcard/Android/data/com.agilelens.tankcommander/files/
# (adb pull it, edit numbers, adb push it back, restart the game).
extends Node

const DEFAULTS := {
	# --- tank
	"tank_max_speed": 7.0,        # m/s per track
	"tank_accel": 3.2,
	"turret_slew": 0.85,          # rad/s
	"shell_speed": 150.0,
	"hp_regen_delay": 8.0,
	"hp_regen_rate": 3.0,         # scaled by difficulty
	"mud_slow": 0.5,
	"reverse_scale": 0.6,
	# --- damage (player weapons)
	"shell_dmg": 34.0,
	"rocket_dmg": 26.0,
	"mg_dmg": 4.0,
	"bomb_dmg": 45.0,
	# --- damage (enemy weapons)
	"enemy_shell_dmg": 16.0,
	"enemy_mg_dmg": 2.0,
	"mortar_dmg": 22.0,
	"plane_rocket_dmg": 11.0,
	# --- enemies
	"enemy_tank_hp": 55.0,
	"jeep_hp": 14.0,
	"gunner_hp": 6.0,
	"mortar_hp": 22.0,
	"plane_hp": 30.0,
	"enemy_cadence_scale": 1.0,   # >1 = slower enemy fire
	"enemy_accuracy_scale": 1.0,  # >1 = more accurate
	# 1.0 made wave 1 a single tank and every level feel empty (Alex, live
	# headset: "we have far too few enemies-- the levels all feel sparse").
	# 1.8 puts ~3 tanks + the usual jeep/squad/plane ramp on the board from
	# the first wave instead of a lone tank.
	"wave_size_scale": 1.8,
	# --- stealth / night
	"detect_range_day": 150.0,
	"detect_night_dark": 0.35,    # fraction of day range, lights OFF
	"detect_night_lit": 1.3,      # fraction of day range, lights ON
	"noise_reveal_time": 6.0,     # seconds enemies stay alerted after you fire
	# --- weather / events
	"storm_chance": 0.22,
	"fog_chance": 0.15,   # rolled right after the storm check on the same CLEAR-state timer, so the two never overlap
	"disaster_cooldown": 180.0,
	"baby_step_dmg": 30.0,
	"baby_speed": 3.0,
	"baby_hp": 400.0,   # big damage sponge — one boss, not a wave regular
	"volcano_eruption_dmg": 85.0,   # heavy/lethal — most of a full-hp tank in one geyser
	"volcano_eruption_radius": 6.5,
	# --- silly modes
	"lowg_gravity": 2.4,
	"bounce_restitution": 0.5,
	"underwater_speed": 0.55,
	# --- vehicles
	"heli_lift": 14.0,
	"heli_speed": 28.0,
	"runner_speed": 16.0,
	"plane_speed_max": 62.0,
	# --- VO
	"vo_idle_period": 45.0,
	"vo_cooldown_scale": 1.0,     # >1 = dad talks less
	# --- pretty
	"glow_enabled": 1.0,
	"glow_intensity": 0.55,
	"enemy_ship_hp": 30.0,
	"boat_speed": 14.0,
	"foveation_level": 2.0,   # 0-3; lower = sharper periphery, more GPU
	                          # A/B on Quest 3S: 2 vs 3 = 9.17 vs 9.20 ms — free
}

var _values := {}

func _ready() -> void:
	_values = DEFAULTS.duplicate()
	var cfg := ConfigFile.new()
	var path := "user://tuning.cfg"
	# adb-pushable external override wins (Android playtesting)
	var ext := "/sdcard/Android/data/com.agilelens.tankcommander/files/tuning.cfg"
	if FileAccess.file_exists(ext):
		path = ext
	if cfg.load(path) == OK:
		var overridden := 0
		for key in cfg.get_section_keys("tuning") if cfg.has_section("tuning") else []:
			if _values.has(key):
				var raw: Variant = cfg.get_value("tuning", key)
				if typeof(raw) == TYPE_STRING and not String(raw).is_valid_float():
					push_warning("[tune] ignoring non-numeric %s=%s" % [key, raw])
					continue
				_values[key] = float(raw)
				overridden += 1
		print("[tune] loaded %d overrides from tuning.cfg" % overridden)
	elif not FileAccess.file_exists(path):
		_write_template(path)
	else:
		# parse error: keep defaults but NEVER overwrite the player's edits
		push_warning("[tune] tuning.cfg failed to parse — using defaults, file untouched")

func v(key: String) -> float:
	return _values.get(key, 0.0)

func _write_template(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return
	f.store_line("; Tank Commander VR — playtest tuning. Edit numbers, restart the game.")
	f.store_line("; Quest path: /sdcard/Android/data/com.agilelens.tankcommander/files/tuning.cfg")
	f.store_line("[tuning]")
	for key in DEFAULTS:
		f.store_line("%s=%s" % [key, DEFAULTS[key]])
	f.close()
	print("[tune] wrote template tuning.cfg")

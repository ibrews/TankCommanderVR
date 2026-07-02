# Headless probe: print terrain height along a radial line.
# Run: godot --headless -s tools/probe.gd
extends SceneTree

func _init() -> void:
	var t := Terrain.new()
	for r in [0, 60, 120, 150, 170, 184, 200, 210, 220, 230, 240, 248, 252, 255]:
		var h := t.height(float(r), 0.0)
		var h2 := t.height(0.0, float(r))
		var hd := t.height(float(r) * 0.7071, float(r) * 0.7071)
		print("r=%d  x-axis=%.1f  z-axis=%.1f  diag=%.1f" % [r, h, h2, hd])
	quit(0)

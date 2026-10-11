# Geometric design check, not a claim about every player's anatomy/comfort.
extends Node3D

func _ready() -> void:
	var terrain := Terrain.new()
	add_child(terrain)
	var fx := FxPool.new()
	add_child(fx)
	var projectiles := Projectiles.new(terrain, fx)
	add_child(projectiles)
	var tank := PlayerTank.new(terrain, projectiles, fx)
	add_child(tank)
	var cockpit: Node3D = tank.cockpit["root"]
	var shoulders: Array[Vector3] = [CockpitBuilder.EYE + Vector3(-0.18, -0.15, 0.05), CockpitBuilder.EYE + Vector3(0.18, -0.15, 0.05)]
	var result := {}
	for key: String in tank.cockpit["controls"]:
		var control: VRControl = tank.cockpit["controls"][key]
		var point := cockpit.to_local(control.grab_point())
		result[key] = {"point": [point.x, point.y, point.z], "shoulder_m": _distance(point, shoulders)}
		print("[reach] %s %.3fm" % [key, result[key]["shoulder_m"]])
	var maximum := 0.0
	for angle in [0.0, PI / 2, PI, PI * 1.5]:
		tank.turret.rotation.y = angle
		tank.cockpit["declutch"].rotation.y = -angle
		maximum = maxf(maximum, _distance(cockpit.to_local(tank.breech_lever.grab_point()), shoulders))
	result["breech_full_traverse_max_m"] = maximum
	print("[reach] breech_full_traverse_max %.3fm" % maximum)
	Game.alive = true
	Game.help_on = true
	tank.loaded = false
	tank.auto_reload = false
	tank._update_hints()
	var reload_coached := tank.breech_lever.coached
	print("[reach] reload coaching %s" % reload_coached)
	var file := FileAccess.open("user://reach_audit.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(result, "\t"))
	get_tree().quit(0 if reload_coached else 1)

func _distance(point: Vector3, shoulders: Array[Vector3]) -> float:
	return minf(point.distance_to(shoulders[0]), point.distance_to(shoulders[1]))

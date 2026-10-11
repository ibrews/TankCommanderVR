# Readback for external XRSim input. Never synthesizes gameplay hand input.
# Run this scene with -- --xr-audit --simshot. Isolate APPDATA for each run.
extends Node3D

var main: Node3D
var elapsed := 0.0
var samples := 0

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	main = load("res://scenes/main.tscn").instantiate()
	main.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(main)

func _process(delta: float) -> void:
	elapsed += delta
	if elapsed < 0.2:
		return
	elapsed = 0.0
	samples += 1
	var state := {"sample": samples, "state": Game.state, "paused": Game.paused,
		"fps": Engine.get_frames_per_second(), "draws": Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)}
	if main.rig is XRRig:
		var rig: XRRig = main.rig
		state["eye"] = _vec(rig.camera.global_position)
		state["calibrated"] = rig._calibrated
		state["hands"] = {}
		for hand: XRRig.XRHand in [rig.hand_l, rig.hand_r]:
			state["hands"][String(hand.tracker)] = {"position": _vec(hand.hand_pos()),
				"controller": hand.uses_controller(), "tracked": hand.interaction_tracked(),
				"grip": hand.effective_grip(), "trigger": hand.effective_trigger(),
				"holding": str(hand.holding.get_path()) if is_instance_valid(hand.holding) else ""}
	if is_instance_valid(main.player):
		var tank: PlayerTank = main.player
		state["tank"] = {"battery": tank.battery_on, "fuel": tank.fuel_on,
			"engine": tank.engine_on, "gear": tank.gear, "ammo": tank.ammo, "loaded": tank.loaded,
			"speed": tank._spd, "turret": tank.turret.rotation.y, "thermal_updates": tank._thermal_updates,
			"physics_frames": Engine.get_physics_frames()}
		state["controls"] = {}
		for key: String in tank.cockpit["controls"]:
			var control: VRControl = tank.cockpit["controls"][key]
			var point := control.grab_point()
			var entry := {"point": _vec(point), "enabled": control.enabled, "path": str(control.get_path())}
			if main.rig is XRRig:
				entry["view"] = _vec(main.rig.camera.to_local(point))
			if control is VRControl.Lever or control is VRControl.Knob or control is VRControl.SteeringWheel:
				entry["value"] = control.value
			elif control is VRControl.TwoAxisGrip:
				entry["deflection"] = [control.deflection.x, control.deflection.y]
			elif control is VRControl.ToggleSwitch:
				entry["on"] = control.on
			elif control is VRControl.SafetyCover:
				entry["open"] = control.open
			elif control is VRControl.PushButton:
				entry["down"] = control.is_down
			state["controls"][key] = entry
	var file := FileAccess.open("user://xr_audit.json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(state))

func _vec(v: Vector3) -> Array[float]:
	return [v.x, v.y, v.z]

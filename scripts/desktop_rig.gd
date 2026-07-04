# Desktop fallback v2: menu-aware mouse-look camera, vehicle attach/detach,
# keyboard drive/turret/fire. Powers headless smoke tests and screenshots.
class_name DesktopRig
extends Node3D

var tank: Node3D = null
var camera: Camera3D
var _yaw := 0.0
var _pitch := 0.0
var _prev_drive := Vector2.ZERO
var _prev_tur := Vector2.ZERO
var _prev_mg := false

func _init() -> void:
	name = "DesktopRig"

func _ready() -> void:
	camera = Camera3D.new()
	camera.near = 0.03
	camera.fov = 80
	add_child(camera)
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func to_menu_anchor(parent: Node3D) -> void:
	tank = null
	if get_parent() != parent:
		get_parent().remove_child(self)
		parent.add_child(self)
	transform = Transform3D()
	position = Vector3(0, 1.5, 0.4)
	camera.rotation = Vector3.ZERO
	camera.top_level = false
	camera.current = true

func attach_to_vehicle(v: Node3D) -> void:
	tank = v
	var anchor: Node3D = v.cockpit["seat_anchor"]
	if get_parent() != anchor:
		get_parent().remove_child(self)
		anchor.add_child(self)
	transform = Transform3D()
	position = v.cockpit["eye_local"]
	camera.current = true
	_yaw = 0.0
	_pitch = 0.0
	_apply_camera_mode()

# First person seats the camera at the cockpit eye; third person detaches it to
# a chase position behind the vehicle. Mouse-look still steers the view in both.
func _apply_camera_mode() -> void:
	if tank == null:
		return
	if Game.third_person:
		camera.top_level = true
	else:
		camera.top_level = false
		camera.transform = Transform3D()

## Mirrors XRRig.local_body_pose() for desktop testing/smoke-shots — no real
## hand tracking here, so hand_l/hand_r both fall back to the head pose
## (matches net.gd's _my_hand_rel() precedent of an identity/head fallback
## when a rig has no hands, harmless since desktop is test-only).
func local_body_pose(relative_to: Node3D) -> Dictionary:
	var origin_parent := get_parent()
	var fp_local := Transform3D(Basis.from_euler(Vector3(_pitch, _yaw, 0)), position)
	var base: Transform3D = (origin_parent.global_transform if origin_parent else Transform3D()) * fp_local
	var inv := relative_to.global_transform.affine_inverse()
	var head: Transform3D = inv * base
	return {"head": head, "hand_l": head, "hand_r": head}

func _chase_target() -> Transform3D:
	# behind + above the vehicle, looking at it, orbited by the mouse-look yaw
	var back := tank.global_transform.basis.rotated(Vector3.UP, _yaw).z.normalized()
	var eye := tank.global_position + back * 9.0 + Vector3(0, 4.0, 0)
	var look := tank.global_position + Vector3(0, 1.2, 0)
	return Transform3D(Basis(), eye).looking_at(look, Vector3.UP)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and tank:
		_yaw -= event.relative.x * 0.0025
		_pitch = clampf(_pitch - event.relative.y * 0.0025, -1.2, 1.2)
		camera.rotation = Vector3(_pitch, _yaw, 0)
	if event is InputEventKey and event.pressed and not event.echo and tank:
		match event.keycode:
			KEY_F:
				tank.call("quick_start")
			KEY_SPACE:
				tank.call("stick_fire")
			KEY_R:
				if tank is PlayerTank and not tank.loaded:
					tank._chamber()
			KEY_B:
				tank.call("stick_rockets")
			KEY_T:
				if tank is PlayerTank:
					tank.cockpit["controls"]["battery"].flip()
			KEY_V, KEY_C:
				Game.toggle_camera_mode()
				_apply_camera_mode()
			KEY_ESCAPE:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			KEY_BACKSPACE:
				# Return to menu — same gap as XRRig's menu_button fallback:
				# the physical "menu_switch" cockpit toggle depends on the
				# currently-broken vrcontrols discovery, so there was
				# otherwise no keyboard path back to the menu mid-level.
				var m := get_tree().get_first_node_in_group("main")
				if m:
					m.call_deferred("to_menu")

func _physics_process(_delta: float) -> void:
	if tank == null:
		return
	var drive := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W): drive.y += 1
	if Input.is_physical_key_pressed(KEY_S): drive.y -= 1
	if Input.is_physical_key_pressed(KEY_A): drive.x -= 1
	if Input.is_physical_key_pressed(KEY_D): drive.x += 1
	if drive != _prev_drive:
		tank.call("set_stick_drive", drive)
		_prev_drive = drive
	var tur := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_J): tur.x -= 1
	if Input.is_physical_key_pressed(KEY_L): tur.x += 1
	if Input.is_physical_key_pressed(KEY_I): tur.y += 1
	if Input.is_physical_key_pressed(KEY_K): tur.y -= 1
	if tur != _prev_tur:
		tank.call("set_stick_turret", tur)
		_prev_tur = tur
	var mg := Input.is_physical_key_pressed(KEY_M)
	if mg != _prev_mg:
		tank.call("set_mg", mg)
		_prev_mg = mg
	if Game.third_person:
		camera.global_transform = camera.global_transform.interpolate_with(_chase_target(), 0.25)

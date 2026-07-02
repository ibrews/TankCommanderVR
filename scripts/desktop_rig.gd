# Desktop fallback for development on PC: mouse-look camera at the design eye
# point, keyboard drive/turret/fire. Also powers headless smoke tests.
class_name DesktopRig
extends Node3D

var tank: PlayerTank
var camera: Camera3D
var _yaw := 0.0
var _pitch := 0.0
var _shot_i := 0

func _init(t: PlayerTank) -> void:
	tank = t
	name = "DesktopRig"

func _ready() -> void:
	camera = Camera3D.new()
	camera.near = 0.03
	camera.fov = 80
	add_child(camera)
	tank.cockpit["seat_anchor"].add_child(self)
	position = tank.cockpit["eye_local"]
	if DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_yaw -= event.relative.x * 0.0025
		_pitch = clampf(_pitch - event.relative.y * 0.0025, -1.2, 1.2)
		camera.rotation = Vector3(_pitch, _yaw, 0)
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F:
				tank.quick_start()
			KEY_SPACE:
				tank.stick_fire()
			KEY_R:
				if not tank.loaded:
					tank._chamber()
			KEY_B:
				tank.stick_rockets()
			KEY_T:
				tank.cockpit["controls"]["battery"].flip()
			KEY_H:
				tank.cockpit["controls"]["lights"].flip()
			KEY_ENTER:
				if not Game.alive:
					Game.restart()
			KEY_F10:
				_screenshot()
			KEY_ESCAPE:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _physics_process(_delta: float) -> void:
	var drive := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W): drive.y += 1
	if Input.is_physical_key_pressed(KEY_S): drive.y -= 1
	if Input.is_physical_key_pressed(KEY_A): drive.x -= 1
	if Input.is_physical_key_pressed(KEY_D): drive.x += 1
	tank.set_stick_drive(drive)
	var tur := Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_J): tur.x -= 1
	if Input.is_physical_key_pressed(KEY_L): tur.x += 1
	if Input.is_physical_key_pressed(KEY_I): tur.y += 1
	if Input.is_physical_key_pressed(KEY_K): tur.y -= 1
	tank.set_stick_turret(tur)
	tank.set_mg(Input.is_physical_key_pressed(KEY_M))

func _screenshot() -> void:
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("user://shots")
	var path := "user://shots/shot_%d.png" % _shot_i
	img.save_png(path)
	print("screenshot saved: ", ProjectSettings.globalize_path(path))
	_shot_i += 1

# No-clip fly camera for the editor-only asset showcase scene (see
# scripts/asset_showcase.gd). Not used by the real game — desktop_rig.gd's
# mouse-look is vehicle-attached and drives controls; this one just flies.
# WASD = move, mouse = look, Space/E = up, Shift/Ctrl or Q = down/slow,
# Shift = speed boost, Esc = release the mouse, click = recapture it.
class_name ShowcaseFreeCam
extends Camera3D

var speed := 20.0
var _yaw := 0.0
var _pitch := 0.0

func _ready() -> void:
	fov = 72.0
	near = 0.05
	far = 2000.0
	current = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

# Point the camera at a target and sync _yaw/_pitch so the next mouse-move
# doesn't snap the view back to whatever look_at() computed.
func point_at(target: Vector3) -> void:
	look_at(target, Vector3.UP)
	_yaw = rotation.y
	_pitch = rotation.x

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * 0.0028
		_pitch = clampf(_pitch - event.relative.y * 0.0028, -1.5, 1.5)
		rotation = Vector3(_pitch, _yaw, 0.0)
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _process(delta: float) -> void:
	var dir := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		dir -= transform.basis.z
	if Input.is_physical_key_pressed(KEY_S):
		dir += transform.basis.z
	if Input.is_physical_key_pressed(KEY_A):
		dir -= transform.basis.x
	if Input.is_physical_key_pressed(KEY_D):
		dir += transform.basis.x
	if Input.is_physical_key_pressed(KEY_E) or Input.is_physical_key_pressed(KEY_SPACE):
		dir += Vector3.UP
	if Input.is_physical_key_pressed(KEY_Q):
		dir -= Vector3.UP
	var mult := 4.0 if Input.is_physical_key_pressed(KEY_SHIFT) else 1.0
	if dir.length() > 0.0:
		global_position += dir.normalized() * speed * mult * delta

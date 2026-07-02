# MIT-licensed Touch Plus controller model (assets/controllers/), animated
# mechanically per the node-naming-triplet scheme in profile.json — ported
# from immersive-web/webxr-input-profiles' motionController.js/visualResponse.js.
# Used instead of OpenXRFbRenderModel: XR_FB_render_model is confirmed NOT
# supported on Quest 3S specifically (Khronos runtime extension matrix, and a
# blank/invisible controller on-device 2026-07-02) even though it works on
# Quest 1/2/3/Pro. See assets/controllers/SOURCE.md.
class_name ControllerVisual
extends Node3D

# Set by the owner (XRHand) before adding this to the tree.
var hand: XRController3D
var is_left := true

# response key -> {value: Node3D, min: Transform3D, max: Transform3D}
var _responses := {}

func _ready() -> void:
	var scene: PackedScene = load("res://assets/controllers/%s.glb" % ("left" if is_left else "right"))
	var root := scene.instantiate()
	add_child(root)
	_bind("xr_standard_trigger_pressed", root)
	_bind("xr_standard_squeeze_pressed", root)
	_bind("xr_standard_thumbstick_pressed", root)
	_bind("xr_standard_thumbstick_xaxis_pressed", root)
	_bind("xr_standard_thumbstick_yaxis_pressed", root)
	_bind(("x" if is_left else "a") + "_button_pressed", root)
	_bind(("y" if is_left else "b") + "_button_pressed", root)
	if is_left:
		_bind("menu_pressed", root)
	else:
		_bind("thumbrest_pressed", root)
	# cockpit-interior lighting group (layer 2, excluded from the sun/fill
	# cull masks) — same as everything else in the cabin. Two-sidedness is
	# handled automatically and separately by RenderFixups (SceneTree.node_added).
	MeshKit.set_layer_recursive(root, 2)

func _bind(base_name: String, root: Node) -> void:
	var value_node := root.find_child(base_name + "_value", true, false) as Node3D
	var min_node := root.find_child(base_name + "_min", true, false) as Node3D
	var max_node := root.find_child(base_name + "_max", true, false) as Node3D
	if value_node and min_node and max_node:
		_responses[base_name] = {"value": value_node, "min": min_node.transform, "max": max_node.transform}
	else:
		push_warning("[controller-visual] missing anim node(s) for " + base_name + " — leaving at rest pose")

func _process(_delta: float) -> void:
	if not hand:
		return
	_apply("xr_standard_trigger_pressed", hand.effective_trigger())
	_apply("xr_standard_squeeze_pressed", hand.effective_grip())
	var stick := hand.get_vector2("primary")
	var norm := _normalize_axes(stick.x, stick.y)
	_apply("xr_standard_thumbstick_xaxis_pressed", norm.x)
	_apply("xr_standard_thumbstick_yaxis_pressed", norm.y)
	_apply("xr_standard_thumbstick_pressed", 1.0 if hand.is_button_pressed("primary_click") else 0.0)
	_apply((("x" if is_left else "a") + "_button_pressed"), 1.0 if hand.is_button_pressed("ax_button") else 0.0)
	_apply((("y" if is_left else "b") + "_button_pressed"), 1.0 if hand.is_button_pressed("by_button") else 0.0)
	if is_left:
		_apply("menu_pressed", 1.0 if hand.is_button_pressed("menu_button") else 0.0)

func _apply(key: String, weight: float) -> void:
	if not _responses.has(key):
		return
	var r: Dictionary = _responses[key]
	var node: Node3D = r.value
	node.transform = (r.min as Transform3D).interpolate_with(r.max, clampf(weight, 0.0, 1.0))

# Gamepad-API-style axis normalization: -1..1 (clamped to the unit circle) -> 0..1,
# matching visualResponse.js's normalizeAxes() exactly.
static func _normalize_axes(x: float, y: float) -> Vector2:
	var h := sqrt(x * x + y * y)
	if h > 1.0:
		var theta := atan2(y, x)
		x = cos(theta)
		y = sin(theta)
	return Vector2(x * 0.5 + 0.5, y * 0.5 + 0.5)

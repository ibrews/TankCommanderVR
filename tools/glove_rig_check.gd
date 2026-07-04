# Diagnostic for the 2026-07-03/07-04 "curl-driven glove completely invisible
# while holding physical Touch controllers" bug. No headset is attached this
# session, so real controller tracking can't be exercised — this instead
# builds the SAME minimal shape as the working reference project
# (D:\Projects\GodotXRControllerTest\scenes\basic_movement_demo\basic_movement_demo.tscn):
#   XROrigin3D -> XRController3D (tracker=left_hand, pose=grip_pose,
#   show_when_tracked=true set NATIVELY, NO custom _physics_process) ->
#   left_hand_low.tscn as a plain child.
# Then, separately, instantiates our OWN production XRRig (scripts/xr_rig.gd)
# so the two hierarchies can be diffed side by side in one run: node paths,
# visible/show_when_tracked state, layers, and glove.get_parent() identity.
#
# This does NOT prove or disprove real on-device tracking behavior — it only
# proves (or disproves) that the node graph parses/loads/instantiates
# correctly and that nothing about layers/materials/addon version/owner
# assignment differs from the reference project in a way that's checkable
# without a live headset.
#
# Run: godot --headless --path . scenes/glove_rig_check.tscn
extends Node3D

var _results := []


func _log(check: String, ok: bool, detail: String = "") -> void:
	_results.append({"check": check, "ok": ok, "detail": detail})
	print("[glove_check] %s: %s%s" % [check, ("PASS" if ok else "FAIL"), ("  (%s)" % detail) if detail else ""])


func _ready() -> void:
	_build_reference_style_rig()
	_build_our_rig()
	await get_tree().process_frame
	await get_tree().process_frame
	_inspect_reference_rig()
	_inspect_our_rig()
	_print_summary()
	get_tree().quit(0)


# ---------------------------------------------------------------- reference-style rig
var _ref_origin: XROrigin3D
var _ref_hand: XRController3D
var _ref_glove: Node3D

func _build_reference_style_rig() -> void:
	_ref_origin = XROrigin3D.new()
	_ref_origin.name = "RefXROrigin3D"
	add_child(_ref_origin)

	# Exactly what basic_movement_demo.tscn's LeftHand node overrides look
	# like as scene properties: a plain XRController3D, no script, no custom
	# per-frame visibility logic. show_when_tracked=true is the ENGINE's own
	# native XRNode3D property (XRController3D's parent class) — it alone
	# drives show/hide in the reference project.
	_ref_hand = XRController3D.new()
	_ref_hand.name = "LeftHand"
	_ref_hand.tracker = "left_hand"
	_ref_hand.pose = "grip_pose"
	_ref_hand.show_when_tracked = true
	_ref_origin.add_child(_ref_hand)

	# Same hand scene our project uses, added as a plain child with no
	# wrapping/visibility script of our own — XRToolsHand (hand.gd, bundled
	# with the scene) is the ONLY script involved, same as the reference.
	_ref_glove = load("res://addons/godot-xr-tools/hands/scenes/lowpoly/left_hand_low.tscn").instantiate()
	_ref_hand.add_child(_ref_glove)
	_ref_glove.owner = self


# ---------------------------------------------------------------- our production rig
var _our_rig: XRRig

func _build_our_rig() -> void:
	_our_rig = XRRig.new()
	add_child(_our_rig)


func _inspect_reference_rig() -> void:
	_log("RefXROrigin3D -> LeftHand -> left_hand_low.tscn parses and is in the tree",
		is_instance_valid(_ref_glove) and _ref_glove.is_inside_tree(),
		"path=%s" % [str(_ref_glove.get_path()) if is_instance_valid(_ref_glove) else "n/a"])
	_log("reference LeftHand.show_when_tracked reads back true (native XRNode3D property)",
		_ref_hand.show_when_tracked == true)
	_log("reference LeftHand has NO custom script (native XRController3D only)",
		_ref_hand.get_script() == null,
		"get_script()=%s" % [str(_ref_hand.get_script())])
	_log("reference glove root has XRToolsHand script attached (hand.gd)",
		_ref_glove.get_script() != null and _ref_glove.get_script().resource_path.ends_with("hands/hand.gd"),
		"script=%s" % [str(_ref_glove.get_script())])
	var ref_mesh := _find_mesh_instance(_ref_glove)
	_log("reference glove has a findable MeshInstance3D (XRToolsHand._ready() requirement)",
		ref_mesh != null,
		"mesh=%s" % [str(ref_mesh.get_path()) if ref_mesh else "none"])
	if ref_mesh:
		_log("reference glove mesh default layers == 1 (untouched, matches stock addon)",
			ref_mesh.layers == 1, "layers=%d" % ref_mesh.layers)


func _inspect_our_rig() -> void:
	var hand_l: XRRig.XRHand = _our_rig.hand_l
	_log("our XRRig.hand_l constructed", hand_l != null)
	if hand_l == null:
		return
	_log("our hand_l is an XRController3D (native base class, satisfies is_class() checks)",
		hand_l.is_class("XRController3D"))
	_log("our hand_l.tracker == 'left_hand'", hand_l.tracker == "left_hand", "tracker=%s" % hand_l.tracker)
	_log("our hand_l.pose == 'grip_pose' (matches reference's grip_pose, NOT the old bare 'grip' string)",
		hand_l.pose == "grip_pose", "pose=%s" % hand_l.pose)
	_log("our hand_l.show_when_tracked == false (today's fix — manual visibility owns it instead)",
		hand_l.show_when_tracked == false, "show_when_tracked=%s" % hand_l.show_when_tracked)

	var glove: Node3D = hand_l.glove
	_log("our hand_l.glove constructed and non-null", glove != null)
	if glove == null:
		return
	_log("our glove is a direct child of hand_l (same shape as reference's LeftHand->left_hand_low.tscn)",
		glove.get_parent() == hand_l,
		"glove.get_parent()=%s" % [str(glove.get_parent())])
	_log("our glove.owner == XRRig (self) -- required for XRTools.find_xr_child(owned=true) scans",
		glove.owner == _our_rig,
		"owner=%s" % [str(glove.owner)])
	_log("our glove has XRToolsHand script attached (same hand.gd as reference)",
		glove.get_script() != null and glove.get_script().resource_path.ends_with("hands/hand.gd"),
		"script=%s" % [str(glove.get_script())])
	var our_mesh := _find_mesh_instance(glove)
	_log("our glove has a findable MeshInstance3D",
		our_mesh != null, "mesh=%s" % [str(our_mesh.get_path()) if our_mesh else "none"])
	if our_mesh:
		# xr_rig.gd's _make_glove() deliberately sets layers 1|2 (see comment
		# at that function) to fix a real lighting asymmetry found 2026-07-03.
		# Confirming it lands as 1|2 = 3, not accidentally 2-only (which would
		# put it on the SAME layer restriction sun.light_cull_mask excludes
		# for the *lighting* pass, but would NOT itself cause invisibility --
		# camera cull_mask is never restricted anywhere in this project, see
		# main.gd / player_tank.gd / xr_rig.gd grep, so layer 2 alone would
		# still RENDER, just under different lighting).
		_log("our glove mesh layers == 3 (1|2, per _make_glove()'s deliberate lighting fix)",
			our_mesh.layers == 3, "layers=%d" % our_mesh.layers)
	_log("our glove.visible == false at rest (no physics ticked yet in this diagnostic -- driven per-frame by XRHand._physics_process, not a static default)",
		glove.visible == false, "visible=%s" % glove.visible)

	# XRToolsHand._ready() sets top_level = true on ITSELF (hand.gd line
	# ~119) once not in the editor. This detaches TRANSFORM inheritance from
	# hand_l, but Godot's visibility propagation (Node3D::_propagate_visibility_changed)
	# is a SEPARATE mechanism that still walks the real scene-tree parent
	# chain regardless of top_level -- so glove.visible=false/true (set
	# directly on the glove's own property every frame in
	# XRHand._physics_process) is unaffected by top_level either way, AND is
	# not overridden by any ancestor: neither hand_l nor XRRig itself is ever
	# set to visible=false anywhere in scripts/ (confirmed via grep across
	# scripts/*.gd -- only controller_model/laser/_debug_label/indicator get
	# explicit visibility toggles, never hand_l/hand_r/XRRig).
	_log("our glove has top_level set (XRToolsHand._ready() runtime behavior, non-editor)",
		glove.top_level == true, "top_level=%s" % glove.top_level)
	_log("neither hand_l nor XRRig ancestor is itself hidden (would mask glove regardless of top_level)",
		hand_l.visible and _our_rig.visible,
		"hand_l.visible=%s rig.visible=%s" % [hand_l.visible, _our_rig.visible])


func _find_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for c in node.get_children():
		var found := _find_mesh_instance(c)
		if found:
			return found
	return null


func _print_summary() -> void:
	print("\n===== GLOVE RIG CHECK SUMMARY =====")
	var passed := 0
	for r in _results:
		if r["ok"]:
			passed += 1
	print("%d/%d checks passed" % [passed, _results.size()])
	for r in _results:
		if not r["ok"]:
			print("  FAILED: %s  (%s)" % [r["check"], r["detail"]])
	print("\nNOT verifiable without a real headset:")
	print("  - whether OpenXR actually reports get_has_tracking_data()==true for a")
	print("    held Touch controller on Quest 3S at runtime")
	print("  - whether XRToolsHand's top_level positioning (global_transform =")
	print("    target_transform * _transform, driven by _target=get_parent()) actually")
	print("    lands the glove mesh in front of the camera instead of off-screen/behind")
	print("    it -- this check only confirms the node graph and static properties")
	print("    match the working reference project, not the live per-frame transform math")
	print("  - GPU-side occlusion/draw-order on real Quest 3S hardware")

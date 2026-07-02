# Autoload: global rendering stopgaps that are cheaper to patch centrally than
# to track down at each of the ~40 ad-hoc StandardMaterial3D call sites.
extends Node

# Blanket "every material is two-sided" fix for the flipped-normals backlog —
# catches MeshKit-built meshes, ad-hoc StandardMaterial3D sites, and imported
# glTF materials (controller model, hand-tracking mesh) alike. Cheap enough to
# leave on; revisit once the actual winding-order bugs get fixed one by one.
func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)

func _on_node_added(node: Node) -> void:
	if node is GeometryInstance3D:
		_force_two_sided.call_deferred(node)

func _force_two_sided(gi: GeometryInstance3D) -> void:
	if not is_instance_valid(gi):
		return
	_fix_mat(gi.material_override)
	_fix_mat(gi.material_overlay)
	if gi is MeshInstance3D and gi.mesh:
		for i in gi.mesh.get_surface_count():
			_fix_mat(gi.get_surface_override_material(i))
			_fix_mat(gi.mesh.surface_get_material(i))

func _fix_mat(mat: Material) -> void:
	if mat is BaseMaterial3D and mat.cull_mode != BaseMaterial3D.CULL_DISABLED:
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED

class_name ChassisModuleDefinition
extends Resource
## Visual-only module contract. The scene origin is the proximal mount.
@export var module_id: StringName
@export var category: StringName
@export var mounting_interface: StringName
@export var visual_scene: PackedScene
@export var attachment_sockets: Array[StringName]
@export var cosmetic_label: String

func instantiate_module() -> Node3D:
	if visual_scene == null:
		return null
	var module := visual_scene.instantiate() as Node3D
	if module == null:
		return null
	for socket in attachment_sockets:
		if not module.get_node_or_null(NodePath(socket)) is Marker3D:
			module.free()
			return null
	return module

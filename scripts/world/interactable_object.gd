class_name InteractableObject
extends StaticBody3D
@export var definition: ObjectDefinition

func query_actions() -> Array[StringName]:
	if definition == null:
		return []
	return definition.available_actions.duplicate()

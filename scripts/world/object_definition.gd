class_name ObjectDefinition
extends Resource
## Authoritative properties; never store actor knowledge on this resource.
enum Mobility { FIXED, MOVABLE, CARRYABLE }
@export var mobility: Mobility = Mobility.FIXED
@export var object_id: StringName
@export var display_name: String
@export_multiline var description: String
@export var mass_kg: float = 0.0
@export var condition: String = "Intact"
@export var available_actions: Array[StringName] = [&"inspect"]
@export var properties: Dictionary = {}

func inspection_information() -> Dictionary:
	return {"name": display_name, "description": description}

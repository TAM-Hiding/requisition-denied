class_name ContainerDefinition
extends Resource
@export var container_id: StringName
@export var container_type: StringName = &"personal_storage"
@export var capacity_m3 := 0.030
@export var maximum_mass_kg := 25.0
@export var insertion_dimensions := Vector3(0.60, 0.40, 0.25)
@export var physical_packing := false
@export var physical_interior: PackedScene

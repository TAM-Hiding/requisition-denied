class_name ContainerDefinition
extends Resource
@export var container_id: StringName
@export var container_type: StringName = &"personal_storage"
@export var capacity_m3 := 0.030
@export var maximum_mass_kg := 25.0
@export var insertion_dimensions := Vector3(0.60, 0.40, 0.25)
@export var physical_packing := false
@export var physical_interior: PackedScene

@export var expanded_capacity_m3 := 0.0
@export var expanded_dimensions := Vector3.ZERO

func effective_capacity_m3() -> float:
	return maxf(capacity_m3, expanded_capacity_m3)

func packing_dimensions() -> Vector3:
	return insertion_dimensions.max(expanded_dimensions) if expanded_capacity_m3 > capacity_m3 else insertion_dimensions

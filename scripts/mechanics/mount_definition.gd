class_name MountDefinition
extends Resource

@export var mount_id: StringName
@export var attachment := Transform3D.IDENTITY
@export var accepted_tags: Array[StringName] = []
@export_range(0.001, 0.5) var position_tolerance := 0.09
@export_range(0.1, 45.0) var angle_tolerance_degrees := 10.0
@export var requires_vacant: Array[StringName] = []
@export var removable := true
@export var required_for_operation := false
@export var release_offset := Vector3(0, 0, 0.2)
@export var connection: MechanicalConnection

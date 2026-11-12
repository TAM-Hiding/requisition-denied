class_name MountDefinition
extends Resource

@export var mount_id: StringName
@export var attachment := Transform3D.IDENTITY
@export var accepted_tags: Array[StringName] = []
@export_range(0.01, 1.0) var acquisition_distance := 0.26
@export_range(0.001, 0.5) var position_tolerance := 0.09
## Optional insertion reach along the mount's local +Z approach.
@export_range(0.0, 0.5) var approach_distance := 0.0
@export_range(0.1, 45.0) var angle_tolerance_degrees := 10.0
## A keyed mount uses the mating datum's +Z approach and +X roll reference.
@export var keyed := false
@export_range(1.0, 75.0) var key_tolerance_degrees := 35.0
@export var requires_vacant: Array[StringName] = []
@export var removable := true
@export var required_for_operation := false
@export var release_offset := Vector3(0, 0, 0.2)
@export var connection: MechanicalConnection

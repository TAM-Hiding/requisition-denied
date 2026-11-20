class_name LocomotionTuning
extends Resource
## Provisional gameplay values. Chassis hardware still supplies base walking speed.
@export_group("Movement")
@export var sprint_multiplier := 1.6
@export var crouch_multiplier := 0.6
@export var crawl_multiplier := 0.3
@export var jump_height := 0.75
@export var posture_hold_seconds := 0.4
@export var camera_response := 12.0
@export_group("Carried Load")
## Factors at 0%, 25%, 50%, 70%, 100% of the current chassis lift rating.
@export var jump_load_factors: Array[float] = [1.0, 0.85, 0.65, 0.45, 0.2]
@export var sprint_load_factors: Array[float] = [1.0, 0.95, 0.85, 0.75, 0.55]
@export_group("Postures")
@export var standing_height := 1.8
@export var crouch_height := 1.4
@export var upright_radius := 0.3
@export var prone_length := 2.3
@export var prone_height := 0.84
@export var prone_width := 0.96
@export var prone_center_z := -0.22
@export var standing_eye := Vector3(0, 1.65, 0)
@export var crouch_eye := Vector3(0, 1.25, 0)
@export var prone_eye := Vector3(0, 0.35, -0.86)
@export_group("Traversal")
@export var ledge_reach := 0.85
@export var minimum_ledge_rise := 0.25
@export var maximum_ledge_rise := 1.35
@export var climb_duration := 0.85
@export var support_motion_tolerance := 0.03

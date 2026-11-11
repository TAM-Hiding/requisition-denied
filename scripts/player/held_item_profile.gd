class_name HeldItemProfile
extends Resource
## Presentation occupancy data. Author this to conservatively enclose the model.
@export var envelope: Shape3D
@export var envelope_transform := Transform3D.IDENTITY
@export var retracted_camera_position := Vector3(0.1, -0.23, -0.15)
@export_range(0.0, 0.1) var clearance_margin: float = 0.025
@export_range(0.1, 20.0) var restore_speed: float = 3.5

class_name HeldItemProfile
extends Resource
## Presentation data, independent of equipment ownership and world physics.
@export var envelope: Shape3D
@export var envelope_transform := Transform3D.IDENTITY
## Camera-space elbow travel: primarily backward, preserving lateral position.
@export var retraction_offset := Vector3(0, -0.015, 0.48)
@export_range(0.0, 0.4) var lateral_clearance_limit: float = 0.22
@export var lowered_offset := Vector3(0.045, -0.16, 0.025)
@export_range(0.1, 30.0) var pose_transition_speed: float = 8.0
@export_range(0.0, 0.1) var clearance_margin: float = 0.025
@export_range(0.0, 0.25) var anticipation_margin: float = 0.08
@export_range(0.1, 30.0) var retract_speed: float = 14.0
@export_range(0.1, 20.0) var restore_speed: float = 3.5

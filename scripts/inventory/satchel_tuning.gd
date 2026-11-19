class_name SatchelTuning
extends Resource
@export_group("Attachment")
@export var vertical_offset := -0.31
@export var horizontal_offset := 0.08
@export var distance_from_back := 0.18
@export var pitch_degrees := 4.0
@export var yaw_degrees := -8.0
@export var roll_degrees := -12.0
@export_group("Input")
@export var plow_hold_seconds := 0.18
@export var plow_motion_pixels := 6.0
@export var height_step := 0.08
@export_group("Opening")
@export var exit_clearance := 0.025
@export_group("Inversion")
@export var inversion_degrees := 155.0
@export var inversion_dwell := 0.35

func attachment_transform() -> Transform3D:
	return Transform3D(Basis.from_euler(Vector3(deg_to_rad(pitch_degrees), deg_to_rad(yaw_degrees), deg_to_rad(roll_degrees))),
		Vector3(horizontal_offset, vertical_offset, distance_from_back))

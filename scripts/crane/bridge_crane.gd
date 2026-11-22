class_name BridgeCrane
extends Node3D
## OC-01, using the hall's local frame. Powered axes and the unloaded suspension are independent.

const NOMINAL_CAPACITY_KG := 50000

@export var rail_height := 9.52
@export var bridge_speed := 1.65
@export var bridge_acceleration := 0.90
@export var bridge_braking := 1.35
@export var trolley_speed := 1.30
@export var trolley_acceleration := 0.95
@export var trolley_braking := 1.50
@export var hoist_speed := 0.85
@export var hoist_acceleration := 1.25
@export var minimum_suspension_length := 0.78
@export var minimum_hook_height := 0.65
@export var precision_multiplier := 0.25
@export var hoist_step := 0.10
@export var precision_hoist_step := 0.01
@export var bridge_impact_speed := 1.25
@export var trolley_impact_speed := 0.98

var geometry: CraneGeometry
var maintenance: CraneMaintenance
var bridge: CraneTravelAxis
var trolley: CraneTravelAxis
var suspension: CraneSuspension

var _trolley_demand := 0.0
var _bridge_demand := 0.0
var _precise := false
var _hoist_precise := false
var _obstruction_time := 0.0
var _sweep := PhysicsShapeQueryParameters3D.new()
var _sweep_box := BoxShape3D.new()


func configure(hall: Node3D) -> void:
	geometry = CraneGeometry.new()
	geometry.name = "CraneGeometry"
	add_child(geometry)
	geometry.build(hall.get("width"), hall.get("depth"), rail_height)
	bridge = CraneTravelAxis.new(geometry.bridge_min, geometry.bridge_max, 8.0)
	trolley = CraneTravelAxis.new(geometry.trolley_min, geometry.trolley_max, -1.5)
	var outlet := geometry.suspension_origin_y
	suspension = CraneSuspension.new(outlet, minimum_suspension_length, outlet - minimum_hook_height, 5.75)
	_present()
	_sweep.shape = _sweep_box
	_sweep.collision_mask = 1
	_sweep.margin = 0.005

	maintenance = CraneMaintenance.new()
	maintenance.name = "Maintenance"
	add_child(maintenance)
	maintenance.configure(geometry.component_anchors)
	maintenance.install_service_access(hall)


func set_controls(trolley_axis: float, bridge_axis: float, precise: bool) -> void:
	_trolley_demand = clampf(trolley_axis, -1.0, 1.0)
	_bridge_demand = clampf(bridge_axis, -1.0, 1.0)
	_precise = precise


func adjust_hook_steps(steps: float, precise: bool) -> void:
	if is_zero_approx(steps) or not maintenance.motion_allowed(&"hoist", steps):
		return
	_hoist_precise = precise
	var increment := precision_hoist_step if precise else hoist_step
	suspension.request_height(suspension.target + steps * increment)


func clear_controls() -> void:
	set_controls(0.0, 0.0, false)
	suspension.stop(hoist_acceleration)


func hook_attachment() -> Transform3D:
	return geometry.hook_anchor.global_transform


func status_text() -> String:
	var text := "OC-01 / CONNECTED\nBRIDGE  %s    TROLLEY  %s\nHOOK TARGET  %.2f m    %s" % [
		_axis_status(bridge.velocity, "REAR", "ENTRY"),
		_axis_status(trolley.velocity, "+X", "−X"),
		suspension.target,
		"PRECISION" if _precise else "NORMAL",
	]
	if _obstruction_time > 0.0:
		text += "\nHOOK PATH OBSTRUCTED"
	var warning := maintenance.status_text()
	return text if warning.is_empty() else text + "\n" + warning


func _physics_process(delta: float) -> void:
	if suspension == null:
		return
	_obstruction_time = maxf(0.0, _obstruction_time - delta)
	var multiplier := precision_multiplier if _precise else 1.0
	var previous_velocity := Vector3(trolley.velocity, 0.0, bridge.velocity)
	_advance_horizontal(bridge, &"bridge", _bridge_demand, bridge_speed * multiplier,
		bridge_acceleration, bridge_braking, bridge_impact_speed, delta, _bridge_clear)
	_advance_horizontal(trolley, &"trolley", _trolley_demand, trolley_speed * multiplier,
		trolley_acceleration, trolley_braking, trolley_impact_speed, delta, _trolley_clear)
	suspension.react_to_carriage(Vector3(trolley.velocity, 0.0, bridge.velocity) - previous_velocity)

	var direction := signf(suspension.target - suspension.height)
	var can_raise := maintenance.motion_allowed(&"hoist", 1.0)
	var can_lower := maintenance.motion_allowed(&"hoist", -1.0)
	if (direction > 0.0 and not can_raise) or (direction < 0.0 and not can_lower):
		suspension.stop(hoist_acceleration)
	var vertical_speed := hoist_speed * (precision_multiplier if _hoist_precise else 1.0)
	var previous_height := suspension.height
	suspension.advance(delta, vertical_speed, hoist_acceleration, can_raise, can_lower)
	if suspension.height < previous_height and not _unloaded_path_clear(
			Vector3(trolley.position, previous_height - 0.12, bridge.position), 0.74,
			Vector3.UP * (suspension.height - previous_height)):
		suspension.height = previous_height
		suspension.velocity = 0.0
		suspension.request_height(previous_height)
	_present()


func _advance_horizontal(axis: CraneTravelAxis, id: StringName, demand: float, max_speed: float,
		acceleration: float, braking: float, impact_speed: float, delta: float, can_move: Callable) -> void:
	var command := demand if maintenance.motion_allowed(id, demand) else 0.0
	var impact := axis.advance(delta, command, max_speed, acceleration, braking, can_move)
	if absf(impact) >= impact_speed:
		maintenance.register_impact(id, 1 if impact > 0.0 else -1, absf(impact))


func _bridge_clear(next: float) -> bool:
	return _horizontal_clear(Vector3.BACK * (next - bridge.position))


func _trolley_clear(next: float) -> bool:
	return _horizontal_clear(Vector3.RIGHT * (next - trolley.position))


func _horizontal_clear(motion: Vector3) -> bool:
	var bottom := suspension.height - 0.49
	var center := (bottom + suspension.outlet_height) * 0.5
	return _unloaded_path_clear(Vector3(trolley.position, center, bridge.position),
		suspension.outlet_height - bottom, motion)


func _unloaded_path_clear(center: Vector3, probe_height: float, motion: Vector3) -> bool:
	# A conservative unloaded envelope avoids moving the hook or chain through solid fixtures.
	# This query exerts no force, excludes Otis, and never enters the end-stop incident path.
	_sweep_box.size = Vector3(0.64, probe_height, 0.64)
	_sweep.transform = global_transform * Transform3D(Basis.IDENTITY, center)
	_sweep.motion = global_basis * motion
	var travel := get_world_3d().direct_space_state.cast_motion(_sweep)
	if travel[0] >= 0.999 and not _enters_new_overlap():
		return true
	_obstruction_time = 0.8
	return false


func _enters_new_overlap() -> bool:
	# Tiny travel steps can begin inside the cast margin. Explicitly check the destination,
	# allowing escape if a moved object already overlaps the stationary envelope.
	var space := get_world_3d().direct_space_state
	var start := _sweep.transform
	_sweep.transform = start.translated(_sweep.motion)
	var destination := space.intersect_shape(_sweep)
	_sweep.transform = start
	if destination.is_empty():
		return false
	var existing := space.intersect_shape(_sweep)
	for hit in destination:
		var already_overlapping := false
		for original in existing:
			if hit.rid == original.rid and hit.shape == original.shape:
				already_overlapping = true
				break
		if not already_overlapping:
			return true
	return false


func _present() -> void:
	geometry.pose(bridge.position, trolley.position, suspension.height, suspension.swivel_yaw)


func _axis_status(speed: float, positive: String, negative: String) -> String:
	if absf(speed) < 0.025:
		return "IDLE"
	return positive if speed > 0.0 else negative

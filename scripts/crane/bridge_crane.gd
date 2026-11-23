class_name BridgeCrane
extends Node3D
## OC-01's original powered axes pay out a tension-only suspension in world space.

signal rig_disconnected(reason: String)

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
@export var minimum_hook_height := 0.44
@export var maximum_hook_slack := 0.50
@export_range(1.0, 40.0, 0.5) var normal_angle_degrees := 15.0
@export_range(1.0, 45.0, 0.5) var soft_angle_degrees := 25.0
@export_range(1.0, 50.0, 0.5) var maximum_angle_degrees := 30.0
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
var hook: CraneHook
var rigging: CraneRigging
var fastening_system: FasteningSystem
var mass_properties := LiftMassProperties.new()

var _trolley_demand := 0.0
var _bridge_demand := 0.0
var _precise := false
var _hoist_precise := false
var _obstruction_time := 0.0
var _rig_target: WeakRef
var _rig_point := Vector3.ZERO
var _rig_refresh_time := 0.0
var _rig_revision := -1

func configure(hall: Node3D) -> void:
	geometry = CraneGeometry.new()
	geometry.name = "CraneGeometry"
	add_child(geometry)
	geometry.build(hall.get("width"), hall.get("depth"), rail_height)
	bridge = CraneTravelAxis.new(geometry.bridge_min, geometry.bridge_max, 8.0)
	trolley = CraneTravelAxis.new(geometry.trolley_min, geometry.trolley_max, -1.5)
	var outlet := geometry.suspension_origin_y
	suspension = CraneSuspension.new(outlet, minimum_suspension_length, outlet - minimum_hook_height, 5.75)
	hook = CraneHook.new()
	hook.name = "PhysicalHook"
	hook.top_level = true
	hook.position = to_global(Vector3(trolley.position, suspension.height, bridge.position))
	add_child(hook)
	rigging = CraneRigging.new()
	rigging.name = "Rigging"
	add_child(rigging)
	_present()

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
	return hook.global_transform * Transform3D(Basis.IDENTITY, CraneHook.HOOK_EYE)


func hook_collision_body() -> RigidBody3D:
	return hook


func rigged_body() -> RigidBody3D:
	return rigging.load_body if rigging.is_attached() else null


func rig_candidate(body: RigidBody3D, world_point: Vector3) -> String:
	if not is_instance_valid(body) or body == hook or not world_point.is_finite():
		return "Choose a physical load and attachment point."
	var properties := mass_properties.resolve(body)
	if not properties.is_liftable():
		return "Load is fixed or its mass is unknown."
	if properties.mass_kg > NOMINAL_CAPACITY_KG:
		return "Load exceeds OC-01 rated capacity."
	return ""


func attach_load(body: RigidBody3D, world_point: Vector3) -> String:
	var issue := rig_candidate(body, world_point)
	if not issue.is_empty():
		return issue
	var info := mass_properties.resolve(body)
	issue = rigging.attach(hook, hook_attachment().origin, info.root, world_point, info.mass_kg, info.local_center)
	if issue.is_empty():
		_rig_target = weakref(body)
		_rig_point = body.to_local(world_point)
		_rig_refresh_time = 0.0
	return issue


func detach_load() -> String:
	if not rigging.is_attached():
		return "No strap is connected."
	rigging.detach()
	_rig_target = null
	return ""


func outlet_position() -> Vector3:
	return _outlet_at(trolley.position, bridge.position)


func swing_angle() -> float:
	return _swing_angle_at(outlet_position())


func status_text() -> String:
	var text := "OC-01 / CONNECTED\nBRIDGE  %s    TROLLEY  %s\nHOOK TARGET  %.2f m    %s" % [
		_axis_status(bridge.velocity, "REAR", "ENTRY"),
		_axis_status(trolley.velocity, "+X", "−X"),
		suspension.target,
		"PRECISION" if _precise else "NORMAL",
	]
	if _obstruction_time > 0.0:
		text += "\nHOOK PATH OBSTRUCTED"
	if swing_angle() >= deg_to_rad(normal_angle_degrees):
		text += "\nSWING  %.0f°" % rad_to_deg(swing_angle())
	if rigging.is_attached():
		text += "\nSTRAP  %s" % ("TAUT" if rigging.slack_m < 0.03 else "SLACK")
	var warning := maintenance.status_text()
	return text if warning.is_empty() else text + "\n" + warning


func _physics_process(delta: float) -> void:
	if suspension == null:
		return
	_obstruction_time = maxf(0.0, _obstruction_time - delta)
	if not hook.global_position.is_finite() or not hook.linear_velocity.is_finite():
		_recover_invalid_hook()
		return
	_refresh_rig(delta)
	var multiplier := precision_multiplier if _precise else 1.0
	var previous_velocity := Vector3(trolley.velocity, 0.0, bridge.velocity)
	_advance_horizontal(bridge, &"bridge", _bridge_demand, bridge_speed * multiplier,
		bridge_acceleration, bridge_braking, bridge_impact_speed, delta, _bridge_clear)
	_advance_horizontal(trolley, &"trolley", _trolley_demand, trolley_speed * multiplier,
		trolley_acceleration, trolley_braking, trolley_impact_speed, delta, _trolley_clear)
	hook.react_swivel(global_basis * (Vector3(trolley.velocity, 0.0, bridge.velocity) - previous_velocity), delta)

	var anchor := outlet_position()
	var distance := anchor.distance_to(hook.global_position)
	_step_motor(delta, distance)
	var cable_axis := (anchor - hook.global_position).normalized()
	if rigging.is_attached():
		var support_axis := cable_axis if distance >= suspension.length() - 0.02 else Vector3.ZERO
		rigging.step(delta, support_axis, hook.cable_inward_speed(suspension.length(), distance, delta))
	hook.enforce_cable(anchor, suspension.length(), delta, hook.mass + rigging.load_mass_kg)
	if hook.get_contact_count() > 0 and (absf(_bridge_demand) + absf(_trolley_demand) > 0.0
			or absf(suspension.target - suspension.height) > 0.01):
		_obstruction_time = 0.8
	_limit_outward_swing(anchor, delta)
	_present()


func _step_motor(delta: float, distance: float) -> void:
	var direction := signf(suspension.target - suspension.height)
	var can_raise := maintenance.motion_allowed(&"hoist", 1.0)
	var can_lower := maintenance.motion_allowed(&"hoist", -1.0)
	if (direction > 0.0 and not can_raise) or (direction < 0.0 and not can_lower):
		suspension.stop(hoist_acceleration)
	var vertical_speed := hoist_speed * (precision_multiplier if _hoist_precise else 1.0)
	var previous := suspension.height
	suspension.advance(delta, vertical_speed, hoist_acceleration, can_raise, can_lower)
	# A snag can stall the motor, and a supported hook must not feed unlimited slack.
	var pulling_against_obstruction := suspension.height > previous and distance - suspension.length() > 0.10
	var paying_excess_slack := suspension.height < previous and suspension.length() - distance > maximum_hook_slack
	if pulling_against_obstruction or paying_excess_slack:
		suspension.height = previous
		suspension.velocity = 0.0
		suspension.request_height(previous)
		_obstruction_time = 0.8


func _advance_horizontal(axis: CraneTravelAxis, id: StringName, demand: float, max_speed: float,
		acceleration: float, braking: float, impact_speed: float, delta: float, can_move: Callable) -> void:
	var command := demand if maintenance.motion_allowed(id, demand) else 0.0
	var direction := Vector3.RIGHT if id == &"trolley" else Vector3.BACK
	var anchor := outlet_position()
	if not is_zero_approx(command):
		var angle := _swing_angle_at(anchor)
		var ahead := _swing_angle_at(anchor + global_basis * direction * signf(command) * 0.02)
		if ahead > angle and angle > deg_to_rad(soft_angle_degrees):
			command *= 1.0 - smoothstep(deg_to_rad(soft_angle_degrees), deg_to_rad(maximum_angle_degrees), angle)
			_obstruction_time = 0.8
	var impact := axis.advance(delta, command, max_speed, acceleration, braking, can_move)
	if absf(impact) >= impact_speed:
		maintenance.register_impact(id, 1 if impact > 0.0 else -1, absf(impact))


func _outlet_at(x: float, z: float) -> Vector3:
	return to_global(Vector3(x, suspension.outlet_height, z))


func _bridge_clear(next: float) -> bool:
	return _outward_step_clear(_outlet_at(trolley.position, next))


func _trolley_clear(next: float) -> bool:
	return _outward_step_clear(_outlet_at(next, bridge.position))


func _outward_step_clear(next: Vector3) -> bool:
	var angle := _swing_angle_at(next)
	var moving_inward := angle < swing_angle()
	if (angle <= deg_to_rad(maximum_angle_degrees) or moving_inward) and _chain_path_clear(next, moving_inward):
		return true
	_obstruction_time = 0.8
	return false


func _chain_path_clear(next: Vector3, moving_inward: bool) -> bool:
	# The chain has no collision bodies and cannot wrap around structural steel.
	var eye := hook.to_global(Vector3.UP * 0.23)
	var query := PhysicsRayQueryParameters3D.create(next, eye, 1, [hook.get_rid()])
	var space := get_world_3d().direct_space_state
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return true
	if moving_inward:
		query.from = outlet_position()
		var current := space.intersect_ray(query)
		return not current.is_empty() and current.rid == hit.rid
	return false


func _swing_angle_at(anchor: Vector3) -> float:
	var drop := anchor - hook.global_position
	return atan2(Vector2(drop.x, drop.z).length(), maxf(drop.y, 0.001))


func _limit_outward_swing(anchor: Vector3, delta: float) -> void:
	var angle := _swing_angle_at(anchor)
	var soft := deg_to_rad(soft_angle_degrees)
	if angle <= soft or hook.slack_m > 0.04:
		return
	var arm := hook.global_position - anchor
	var tangent := (Vector3.UP - arm.normalized() * arm.normalized().y).normalized()
	var outward := hook.linear_velocity.dot(tangent)
	var strength := smoothstep(soft, deg_to_rad(maximum_angle_degrees), angle)
	# Ease outward velocity and use a bounded restorative impulse. Inward motion stays free.
	var deceleration := strength * (maxf(outward, 0.0) * 8.0 + 3.0)
	hook.apply_central_impulse(-tangent * hook.mass * minf(deceleration, 9.0) * delta)


func _refresh_rig(delta: float) -> void:
	if not rigging.is_attached():
		return
	_rig_refresh_time -= delta
	var revision := fastening_system.topology_revision if is_instance_valid(fastening_system) else -1
	if _rig_refresh_time > 0.0 and revision == _rig_revision:
		return
	_rig_revision = revision
	_rig_refresh_time = 0.15
	var member := _rig_target.get_ref() as RigidBody3D if _rig_target != null else null
	if member == null:
		_release_changed_load("Rigging released. The selected component is gone.")
		return
	var info := mass_properties.resolve(member)
	if not info.is_liftable() or info.mass_kg > NOMINAL_CAPACITY_KG:
		_release_changed_load("Rigging released. The assembly is now fixed or ineligible.")
		return
	if info.root != rigging.load_body:
		if not rigging.rebind_load(info.root, member.to_global(_rig_point), info.mass_kg, info.local_center):
			_release_changed_load("Rigging released. The selected point moved beyond the strap.")
		return
	rigging.update_load_properties(info.mass_kg, info.local_center)


func _release_changed_load(reason: String) -> void:
	detach_load()
	rig_disconnected.emit(reason)


func _recover_invalid_hook() -> void:
	if rigging.is_attached():
		detach_load()
	hook.global_transform = Transform3D(global_basis, outlet_position() - Vector3.UP * suspension.length())
	hook.linear_velocity = Vector3.ZERO
	hook.angular_velocity = Vector3.ZERO
	_obstruction_time = 0.8


func _present() -> void:
	geometry.pose_suspended(bridge.position, trolley.position, hook.global_transform)


func _axis_status(speed: float, positive: String, negative: String) -> String:
	if absf(speed) < 0.025:
		return "IDLE"
	return positive if speed > 0.0 else negative

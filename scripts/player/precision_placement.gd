class_name PrecisionPlacement
extends Node
## Both interaction lifecycles share the same camera-relative placement solver.
signal grab_feedback(message: String)
const HOLD_THRESHOLD_USEC := 200000
const MIN_RESPONSE := 0.30
@export var minimum_distance := 0.45
@export var maximum_distance := 3.0
@export var initial_distance := 1.35
@export var wheel_step := 0.15
@export var follow_speed := 20.0
@export_range(0.001, 0.03, 0.001) var rotation_sensitivity := 0.009
@export var invert_horizontal_rotation := false
@export var invert_vertical_rotation := false
const MAX_TRACKBALL_PACKET := 0.75
const MAX_PENDING_TURNS := 24
const MAX_ROTATION_STEP := 0.035

var distance := 1.35
var rotating := false
var valid := false
var _pressed_at := -1
var _hold_consumed := false
var _trackball_cursor := Vector2.ZERO
var _pending_turns: Array[Quaternion] = []
var pickup_debug := false
var mechanical_settings := MechanicalInteractionSettings.new()
var _seating_socket: MechanicalMount
var _seating_path: Array[Transform3D] = []
var _seating_elapsed := 0.0
var _seating_duration := 0.0
var _seating_turn_fraction := 0.0
var _grab_candidate: InteractableObject
var _grab: InteractableObject
var _supported := false
var _resting_pickup := false
var input_suspended := false
var _clearance: PlacementClearance
@onready var actor: OtisController = get_parent() as OtisController

func is_active() -> bool:
	return actor.equipment.placing or is_grabbing()

func is_grabbing() -> bool:
	return is_instance_valid(_grab)

func is_supported_grab() -> bool:
	return is_grabbing() and _supported

func suspended_mass_kg() -> float:
	if is_grabbing():
		return 0.0 if _supported else _grab.mass
	if actor.equipment.placing and is_instance_valid(actor.equipment.held_item()):
		return actor.equipment.held_item().mass
	return 0.0

func load_fraction() -> float:
	return clampf(suspended_mass_kg() / maxf(lift_capacity(), 0.001), 0.0, 1.0)

func lift_capacity() -> float:
	return actor.chassis.effective(AndroidChassis.Attribute.LIFT_KG)

static func response_factor(mass_kg: float, capacity_kg: float) -> float:
	return lerpf(1.0, MIN_RESPONSE, clampf(mass_kg / maxf(capacity_kg, 0.001), 0.0, 1.0))

func press_drop(now: int = -1) -> void:
	if input_suspended or is_seating():
		return
	_pressed_at = Time.get_ticks_usec() if now < 0 else now
	_hold_consumed = false
	_grab_candidate = null
	if not is_active() and actor.equipment.held_item() == null:
		var target := actor.target_hit().get("collider") as InteractableObject
		if is_instance_valid(target) and target.mobility() != ObjectDefinition.Mobility.FIXED:
			_grab_candidate = target

func advance_drop(now: int = -1) -> void:
	if now < 0:
		now = Time.get_ticks_usec()
	if _pressed_at < 0 or _hold_consumed or now - _pressed_at < HOLD_THRESHOLD_USEC:
		return
	_hold_consumed = true
	if is_instance_valid(_grab_candidate):
		begin_world(_grab_candidate)
	elif not is_active():
		begin()

func release_drop(now: int = -1) -> void:
	if _pressed_at < 0:
		return
	advance_drop(now)
	var tapped := not _hold_consumed
	clear_gesture()
	if tapped:
		if is_active():
			confirm()
		elif actor.equipment.held_item() != null:
			actor.equipment.drop()

func clear_gesture() -> void:
	_grab_candidate = null
	_pressed_at = -1
	_hold_consumed = false

func begin() -> bool:
	var item := actor.equipment.held_item()
	if input_suspended or item == null or is_active():
		return false
	var clearance := PlacementClearance.new()
	if not clearance.configure(item) or not clearance.clear(item.global_transform, 1):
		actor.equipment.result(false, "Move to clear space before placing.")
		return false
	if not actor.equipment.begin_placement():
		return false
	_clearance = clearance
	distance = clampf(initial_distance, minimum_distance, maximum_distance)
	set_rotating(false)
	valid = false
	return true

func begin_world(item: InteractableObject) -> bool:
	if (input_suspended or is_active() or not is_instance_valid(item)
			or item.mobility() == ObjectDefinition.Mobility.FIXED
			or item.state != InteractableObject.State.WORLD or item.freeze
			or actor.target_hit().get("collider") != item):
		return false
	var clearance := PlacementClearance.new()
	var supported := item.mass > lift_capacity()
	if not supported:
		if not clearance.configure(item):
			return false
		var pose := clearance.pickup_pose(item.global_transform, pickup_debug,
			actor.camera.global_position - item.global_position)
		_resting_pickup = not clearance.clear(pose)
		if _resting_pickup and not clearance.physically_clear(pose):
			_resting_pickup = false
			grab_feedback.emit("The load has no clear pickup path.")
			return false
		item.freeze = true
		item.global_transform = pose
		item.state = InteractableObject.State.CARRIED
		item.support_carrier = actor
		_clearance = clearance
	else:
		# The existing dynamic drag motor only drives the horizontal plane.
		item.move_goal = item.global_position
		item.move_speed_scale = MIN_RESPONSE
		item.state = InteractableObject.State.MOVING
		item.sleeping = false
	actor.equipment.presentation.request_pose(HeldItemPresentation.Pose.LOWERED)
	_grab = item
	_supported = supported
	distance = clampf((item.global_position - actor.camera.global_position).dot(-actor.camera.global_basis.z),
		minimum_distance, maximum_distance)
	set_rotating(false)
	valid = not _resting_pickup
	return true

func _release_grab() -> void:
	var item := _grab
	_grab = null
	item.state = InteractableObject.State.WORLD
	item.support_carrier = null
	item.move_speed_scale = 1.0
	if _supported:
		item.linear_velocity = Vector3(0, item.linear_velocity.y, 0)
	else:
		item.lock_rotation = false
		item.freeze = false
		item.linear_velocity = Vector3.ZERO
		item.angular_velocity = Vector3.ZERO
	item.sleeping = false
	_supported = false
	_resting_pickup = false
	actor.equipment.presentation.request_pose(HeldItemPresentation.Pose.NORMAL)

func cancel() -> void:
	clear_seating()
	clear_gesture()
	set_rotating(false)
	valid = false
	if is_grabbing():
		_release_grab()
	elif actor.equipment.placing:
		actor.equipment.cancel_placement()
	_clearance = null

func set_rotating(enabled: bool) -> void:
	rotating = enabled and not input_suspended and is_active() and not is_supported_grab() and not is_seating()
	_trackball_cursor = Vector2.ZERO
	_pending_turns.clear()

func adjust_distance(steps: float) -> void:
	distance = clampf(distance + steps * wheel_step, minimum_distance, maximum_distance)

func rotate_from_mouse(relative: Vector2) -> void:
	if not rotating or not is_active() or is_supported_grab():
		return
	var item := _grab if is_grabbing() else actor.equipment.held_item()
	if not is_instance_valid(item):
		return
	var response := response_factor(item.mass, lift_capacity())
	var horizontal := -relative.x if invert_horizontal_rotation else relative.x
	var vertical := relative.y if invert_vertical_rotation else -relative.y
	var travel := (Vector2(horizontal, vertical) * rotation_sensitivity * response).limit_length(MAX_TRACKBALL_PACKET)
	if travel.is_zero_approx() or _pending_turns.size() >= MAX_PENDING_TURNS:
		return
	# Recenter the virtual input surface gradually without rotating the body.
	# The next increment still has room to travel even during a long straight drag.
	var previous := _trackball_cursor * exp(-travel.length())
	_trackball_cursor = previous + travel
	var view_basis := actor.camera.global_basis.orthonormalized()
	var turn := Quaternion(view_basis * _project_trackball(previous),
		view_basis * _project_trackball(_trackball_cursor))
	# Preserve the order and direction of input, even across complete turns.
	_pending_turns.append(turn)

static func _project_trackball(cursor: Vector2) -> Vector3:
	# A hyperbolic continuation keeps the spherical arc smooth beyond its center.
	var radius_squared := cursor.length_squared()
	var depth := sqrt(1.0 - radius_squared) if radius_squared <= 0.5 else 0.5 / sqrt(radius_squared)
	return Vector3(cursor.x, cursor.y, depth).normalized()

func set_input_suspended(suspended: bool) -> void:
	input_suspended = suspended
	clear_gesture()
	set_rotating(false)
	if is_supported_grab():
		_grab.move_goal = _grab.global_position
		_grab.move_speed_scale = 0.0 if suspended else MIN_RESPONSE
		if suspended:
			_grab.linear_velocity = Vector3.UP * _grab.linear_velocity.y

func _physics_process(delta: float) -> void:
	if (is_active() or is_seating()) and not input_suspended:
		update_preview(delta)

func target_position() -> Vector3:
	return actor.camera.global_position - actor.camera.global_basis.z * distance

func update_preview(delta: float) -> void:
	if is_seating():
		advance_seating(delta)
		return
	if is_supported_grab():
		var goal := target_position()
		_grab.move_goal = Vector3(goal.x, _grab.global_position.y, goal.z)
		return
	var item := _grab if is_grabbing() else actor.equipment.held_item()
	if is_grabbing() and item.mass > lift_capacity():
		cancel()
		return
	var response := response_factor(item.mass, lift_capacity())
	var pose := item.global_transform
	var displacement := (target_position() - pose.origin) * (1.0 - exp(-follow_speed * response * delta))
	if _resting_pickup:
		if not _clearance.clear(pose):
			pose = _clearance.depart_resting_pose(pose, displacement)
			item.global_transform = pose
		valid = _clearance.clear(pose)
		_resting_pickup = not valid
		return
	# Let a preview that Otis has walked into escape along a clear world route.
	# The displayed pose still has to clear Otis before it can be released.
	var mask := 3 if is_grabbing() or _clearance.clear(pose) else 1
	pose = _clearance.slide(pose, displacement, mask)
	if mask == 3 and not rotating:
		pose = _clearance.accommodate_contact(pose, displacement)
	for increment in 8:
		if _pending_turns.is_empty():
			break
		var pending := _pending_turns[0]
		var remaining := pending.get_angle()
		if remaining < 0.0001:
			_pending_turns.pop_front()
			continue
		var step := minf(remaining, MAX_ROTATION_STEP * response)
		var turn := Quaternion.IDENTITY.slerp(pending, step / remaining)
		var candidate := pose
		var orientation := Basis(turn) * pose.basis.orthonormalized()
		candidate.basis = orientation.orthonormalized() * Basis.from_scale(pose.basis.get_scale())
		if not _clearance.rotation_clear(pose, candidate, step):
			_pending_turns.clear()
			break
		pose = candidate
		if step >= remaining:
			_pending_turns.pop_front()
		else:
			_pending_turns[0] = (turn.inverse() * pending).normalized()
	item.global_transform = pose
	valid = _clearance.clear(pose)

func installation_candidate() -> MechanicalMount:
	if input_suspended or is_seating() or not is_grabbing() or not _grab is MechanicalComponent or _supported:
		return null
	var closest: MechanicalMount
	var best_distance := INF
	for node in get_tree().get_nodes_in_group(&"mechanical_mounts"):
		var socket := node as MechanicalMount
		var gap := socket.mating_distance_squared(_grab)
		if gap < best_distance and socket.can_acquire(_grab, gap, mechanical_settings.values.installation):
			closest = socket
			best_distance = gap
	return closest

func installation_name() -> String:
	return _grab.definition.display_name

func installation_feedback(socket: MechanicalMount) -> String:
	return socket.installation_error(_grab, mechanical_settings.values.installation)

func alignment_diagnostics(socket: MechanicalMount, issue: String) -> String:
	var errors := socket.alignment(_grab, mechanical_settings.values.installation)
	var clearance := "CLEAR" if issue.is_empty() else "BLOCKED" if errors.issue.is_empty() else "NOT CHECKED"
	return "\nMOUNT  %s  %.3f m  AXIS %.1f°  KEY %.1f°\nPATH %s  ELIGIBLE %s" % [
		socket.definition.mount_id, errors.distance, errors.axis, errors.key, clearance, issue.is_empty()]

func is_seating() -> bool:
	return not _seating_path.is_empty()

func install_grab() -> bool:
	if is_seating():
		return false
	var socket := installation_candidate()
	if socket == null:
		grab_feedback.emit("Align with a clear compatible mount first.")
		return false
	var tuning: Dictionary = mechanical_settings.values.installation
	var issue: String = socket.alignment(_grab, tuning).issue
	if not issue.is_empty():
		grab_feedback.emit(issue)
		return false
	var path := socket.seating_path(_grab, _clearance)
	if path.is_empty():
		grab_feedback.emit("Installation path blocked.")
		return false
	if not socket.reserve(_grab):
		grab_feedback.emit("Mount no longer available.")
		return false
	set_rotating(false)
	clear_gesture()
	_seating_socket = socket
	_seating_path = path
	_seating_elapsed = 0.0
	_seating_duration = tuning.snap_duration_seconds
	var turn := path[0].basis.get_rotation_quaternion().angle_to(path[1].basis.get_rotation_quaternion())
	_seating_turn_fraction = 0.35 if turn > 0.0001 else 0.0
	return true

func advance_seating(delta: float) -> void:
	var socket := _seating_socket
	if (not is_instance_valid(socket) or not socket.is_inside_tree() or not is_instance_valid(_grab)
			or socket.pending != _grab or not socket.compatibility_error(_grab).is_empty()
			or socket.access_blocker() != &"" or _grab.mass > lift_capacity()):
		interrupt_seating("Installation interrupted.")
		return
	var seat := socket.global_transform * (_grab as MechanicalComponent).profile.mating_transform.affine_inverse()
	if not seat.is_equal_approx(_seating_path[2]):
		interrupt_seating("Mount moved during installation.")
		return
	var previous_progress := _seating_elapsed / _seating_duration
	_seating_elapsed = minf(_seating_elapsed + delta, _seating_duration)
	var progress := _seating_elapsed / _seating_duration
	var pose := _grab.global_transform
	if previous_progress < _seating_turn_fraction:
		var aligned := _seating_path[0].interpolate_with(_seating_path[1],
			smoothstep(0.0, _seating_turn_fraction, progress))
		if not _clearance.turn_path_clear(pose, aligned):
			interrupt_seating("Installation path blocked.")
			return
		pose = aligned
	if progress >= _seating_turn_fraction:
		var destination := _seating_path[1].interpolate_with(seat, smoothstep(_seating_turn_fraction, 1.0, progress))
		if not _clearance.translation_path_clear(pose, destination):
			interrupt_seating("Installation path blocked.")
			return
		pose = destination
	_grab.global_transform = pose
	if progress >= 1.0:
		if not socket.finish_seating(_grab):
			interrupt_seating("Mount no longer available.")
			return
		clear_seating()
		_grab = null
		actor.equipment.presentation.request_pose(HeldItemPresentation.Pose.NORMAL)
		cancel()
		grab_feedback.emit("Installed at %s." % socket.definition.mount_id)

func clear_seating() -> void:
	if is_instance_valid(_seating_socket):
		_seating_socket.cancel_seating(_grab)
	_seating_socket = null
	_seating_path.clear()

func interrupt_seating(message: String) -> void:
	clear_seating()
	if is_instance_valid(_grab):
		valid = _clearance.clear(_grab.global_transform)
	grab_feedback.emit(message)

func confirm() -> bool:
	if input_suspended or is_seating():
		return false
	if is_grabbing():
		if not _supported and not _clearance.clear(_grab.global_transform):
			valid = false
			grab_feedback.emit("Placement blocked.")
			return false
		cancel()
		return true
	var item := actor.equipment.held_item()
	if not actor.equipment.placing or item == null:
		return false
	# Recheck current geometry at the input event, including moving barriers.
	if not _clearance.clear(item.global_transform):
		valid = false
		actor.equipment.result(false, "Placement blocked.")
		return false
	actor.equipment.finish_placement(item.global_transform)
	set_rotating(false)
	_clearance = null
	valid = false
	return true

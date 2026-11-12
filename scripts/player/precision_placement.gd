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
@export var rotation_speed := 0.009
const AXES := [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
const AXIS_NAMES := ["X", "Y", "Z"]

var distance := 1.35
var axis := 0
var rotating := false
var valid := false
var _pressed_at := -1
var _hold_consumed := false
var _angle := 0.0
var _grab_candidate: InteractableObject
var _grab: InteractableObject
var _supported := false
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
	if item == null or is_active():
		return false
	var clearance := PlacementClearance.new()
	if not clearance.configure(item) or not clearance.clear(item.global_transform, 1):
		actor.equipment.result(false, "Move to clear space before placing.")
		return false
	if not actor.equipment.begin_placement():
		return false
	_clearance = clearance
	distance = clampf(initial_distance, minimum_distance, maximum_distance)
	axis = 0
	rotating = false
	_angle = 0
	valid = false
	return true

func begin_world(item: InteractableObject) -> bool:
	if (is_active() or not is_instance_valid(item)
			or item.mobility() == ObjectDefinition.Mobility.FIXED
			or item.state != InteractableObject.State.WORLD or item.freeze
			or actor.target_hit().get("collider") != item):
		return false
	var clearance := PlacementClearance.new()
	var supported := item.mass > lift_capacity()
	if not supported:
		if not clearance.configure(item):
			return false
		var pose := item.global_transform
		if not clearance.clear(pose):
			# Grounded bodies can rest within the release margin. Sweep out
			# of the contact before committing any state change.
			var rise := PhysicsTestMotionParameters3D.new()
			rise.from = pose
			rise.motion = Vector3.UP * 0.012
			pose.origin += rise.motion
			if PhysicsServer3D.body_test_motion(item.get_rid(), rise) or not clearance.clear(pose):
				grab_feedback.emit("There is not enough clearance to grab the load.")
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
	axis = 0
	rotating = false
	_angle = 0.0
	valid = true
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
	actor.equipment.presentation.request_pose(HeldItemPresentation.Pose.NORMAL)

func cancel() -> void:
	clear_gesture()
	rotating = false
	_angle = 0.0
	valid = false
	if is_grabbing():
		_release_grab()
	elif actor.equipment.placing:
		actor.equipment.cancel_placement()
	_clearance = null

func cycle_axis() -> void:
	axis = (axis + 1) % AXES.size()
	_angle = 0

func adjust_distance(steps: float) -> void:
	distance = clampf(distance + steps * wheel_step, minimum_distance, maximum_distance)

func rotate_from_mouse(horizontal: float) -> void:
	if is_supported_grab():
		return
	var item := _grab if is_grabbing() else actor.equipment.held_item()
	if item == null:
		return
	var response := response_factor(item.mass, lift_capacity())
	_angle = clampf(_angle + horizontal * rotation_speed * response, -PI, PI)

func _physics_process(delta: float) -> void:
	if is_active():
		update_preview(delta)

func target_position() -> Vector3:
	return actor.camera.global_position - actor.camera.global_basis.z * distance

func update_preview(delta: float) -> void:
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
	# Let a preview that Otis has walked into escape along a clear world route.
	# The displayed pose still has to clear Otis before it can be released.
	var mask := 3 if is_grabbing() or _clearance.clear(pose) else 1
	pose = _clearance.slide(pose, displacement, mask)
	if mask == 3 and not rotating and is_zero_approx(_angle):
		pose = _clearance.accommodate_contact(pose, displacement)
	for increment in 8:
		if is_zero_approx(_angle):
			break
		var step := clampf(_angle, -0.035 * response, 0.035 * response)
		_angle -= step
		var candidate := pose
		var orientation := pose.basis.orthonormalized() * Basis(AXES[axis], step)
		candidate.basis = orientation.orthonormalized() * Basis.from_scale(pose.basis.get_scale())
		if not _clearance.rotation_clear(pose, candidate, step):
			_angle = 0
			break
		pose = candidate
	item.global_transform = pose
	valid = _clearance.clear(pose)

func confirm() -> bool:
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
	rotating = false
	_clearance = null
	valid = false
	return true

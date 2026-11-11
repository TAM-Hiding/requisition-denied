class_name LargeObjectCarry
extends Node
## A suspended load stays a world collider. Only the validated carry poses are kinematic.
signal feedback(message: String)
const LOAD_SPEED_LOSS := 0.25
const LOAD_ACCELERATION_LOSS := 0.30
const TETHER_SLACK := 0.25
const FLOOR_CLEARANCE := 0.22
const TRACKING_SPEED := 5.0
const TURN_SPEED := 3.0
var item: InteractableObject
var _clearance: PlacementClearance
var _separation: float
var _distance: float
var _height: float
@onready var actor: OtisController = get_parent() as OtisController

func lift(target: InteractableObject) -> Dictionary:
	if is_instance_valid(item) or actor.placement.is_active() or actor.manipulation.moving_object() != null:
		return _result(false, "Release the current object first.")
	if (not is_instance_valid(target) or target.mobility() != ObjectDefinition.Mobility.MOVABLE
			or target.state != InteractableObject.State.WORLD or target.freeze):
		return _result(false, "That object cannot be lifted.")
	if target.mass > actor.chassis.effective(AndroidChassis.Attribute.LIFT_KG):
		return _result(false, "Load exceeds this unit’s lifting capacity.")
	if target.global_position.distance_to(actor.global_position) > actor.manipulation.manipulation_reach:
		return _result(false, "The load is out of reach.")
	var clearance := PlacementClearance.new()
	if not clearance.configure(target):
		return _result(false, "The load has no supported collision shape.")
	var pose := target.global_transform
	var bounds := clearance.collider.global_transform * clearance.collider.shape.get_debug_mesh().get_aabb()
	var half_height := pose.origin.y - bounds.position.y
	var lift_distance := maxf(0.0, actor.global_position.y + FLOOR_CLEARANCE + half_height - pose.origin.y)
	var raised := pose
	raised.origin.y += lift_distance
	var rise := PhysicsTestMotionParameters3D.new()
	rise.from = pose
	rise.motion = Vector3.UP * lift_distance
	# Start from ordinary floor contact. Recovery from the support alone
	# must not veto an otherwise clear upward sweep.
	if (not clearance.clear(raised) or (lift_distance > 0.0
			and PhysicsServer3D.body_test_motion(target.get_rid(), rise))):
		return _result(false, "There is not enough clearance to lift the load.")
	_separation = EnvironmentalManipulation.horizontal_radius(actor) + EnvironmentalManipulation.horizontal_radius(target) + 0.08
	_distance = _separation + 0.25
	_height = half_height + FLOOR_CLEARANCE
	target.freeze = true
	target.linear_velocity = Vector3.ZERO
	target.angular_velocity = Vector3.ZERO
	target.global_transform = raised
	target.state = InteractableObject.State.CARRIED
	target.support_carrier = actor
	item = target
	_clearance = clearance
	actor.equipment.presentation.request_pose(HeldItemPresentation.Pose.LOWERED)
	return _result(true, "Carrying %s. Tap E, G or Esc to release." % target.definition.display_name)

func release() -> Dictionary:
	if not is_instance_valid(item):
		return _result(false, "No carried object.")
	if not _clearance.clear(item.global_transform):
		return _result(false, "Move the load clear before releasing.")
	item.state = InteractableObject.State.WORLD
	item.support_carrier = null
	item.freeze = false
	item.sleeping = false
	item = null
	_clearance = null
	actor.equipment.presentation.request_pose(HeldItemPresentation.Pose.NORMAL)
	return _result(true, "Released object.")

func load_kg() -> float:
	return item.mass if is_instance_valid(item) else 0.0

func load_fraction() -> float:
	return clampf(load_kg() / maxf(actor.chassis.effective(AndroidChassis.Attribute.LIFT_KG), 0.001), 0.0, 1.0)

func speed_factor() -> float:
	return 1.0 - LOAD_SPEED_LOSS * load_fraction()

func acceleration_factor() -> float:
	return 1.0 - LOAD_ACCELERATION_LOSS * load_fraction()

func constrain_velocity(requested: Vector3, delta: float) -> Vector3:
	if not is_instance_valid(item):
		return requested
	var offset := _horizontal_offset()
	var distance := offset.length()
	var toward := offset.normalized()
	var radial := requested.dot(toward)
	var safe_inward := maxf(0.0, distance - _separation) / delta
	var safe_outward := maxf(0.0, _distance + TETHER_SLACK - distance) / delta
	return requested + toward * (clampf(radial, -safe_outward, safe_inward) - radial)

func update_goal(delta: float) -> void:
	if not is_instance_valid(item):
		return
	var direction := _horizontal_offset().normalized()
	var forward := -actor.global_basis.z
	var turn := direction.signed_angle_to(forward, Vector3.UP)
	var goal := actor.global_position + direction.rotated(Vector3.UP,
		clampf(turn, -TURN_SPEED * delta, TURN_SPEED * delta)) * _distance
	goal.y = actor.global_position.y + _height
	var pose := item.global_transform
	var motion := (goal - pose.origin).limit_length(TRACKING_SPEED * delta)
	item.global_transform = _clearance.slide(pose, motion)

func _horizontal_offset() -> Vector3:
	var offset := item.global_position - actor.global_position
	offset.y = 0.0
	return offset

func _result(ok: bool, message: String) -> Dictionary:
	feedback.emit(message)
	return {"ok": ok, "message": message}

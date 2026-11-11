class_name EnvironmentalManipulation
extends Node
## Independent of equipment ownership. Otis updates this before/after movement.
signal feedback(message: String)
signal changed
signal equipment_pose_requested(pose: HeldItemPresentation.Pose)
@export var manipulation_reach: float = 3.5
@export_range(0.1, 0.75) var movement_speed_ratio: float = 0.55
@export var separation_margin: float = 0.18
var _moving: InteractableObject
var _move_distance: float = 2.0
var _minimum_separation: float = 1.0
var _local_direction := Vector3.FORWARD
@onready var actor: OtisController = get_parent() as OtisController

func moving_object() -> InteractableObject:
	return _moving

func intended_distance() -> float:
	return _move_distance

func minimum_separation() -> float:
	return _minimum_separation

func result(ok: bool, message: String) -> Dictionary:
	feedback.emit(message)
	if ok:
		changed.emit()
	return {"ok": ok, "message": message}

func begin_move(item: InteractableObject) -> Dictionary:
	if not is_instance_valid(item) or item.mobility() != ObjectDefinition.Mobility.MOVABLE or item.state != InteractableObject.State.WORLD:
		return result(false, "That object cannot be moved.")
	if actor.controls_world_object() or actor.placement.is_active():
		return result(false, "Release the current object first.")
	_minimum_separation = horizontal_radius(actor) + horizontal_radius(item) + separation_margin
	var displacement := item.global_position - actor.global_position
	displacement.y = 0
	# Reserve tracking-error space; never grow this anchor due to body contacts.
	_move_distance = maxf(displacement.length(), _minimum_separation + 0.55)
	if _move_distance + 0.25 >= manipulation_reach:
		return result(false, "Object is too large or too far away to manipulate safely.")
	_local_direction = actor.global_basis.inverse() * displacement.normalized()
	_moving = item
	item.move_goal = item.global_position
	item.move_velocity = Vector3.ZERO
	item.state = InteractableObject.State.MOVING
	item.sleeping = false
	equipment_pose_requested.emit(HeldItemPresentation.Pose.LOWERED)
	return result(true, "Moving %s. Tap E, G or Esc to release." % item.definition.display_name)

func stop_move() -> Dictionary:
	if _moving == null:
		return result(false, "No environmental manipulation active.")
	_moving.state = InteractableObject.State.WORLD
	_moving.move_velocity = Vector3.ZERO
	_moving.linear_velocity.x = 0
	_moving.linear_velocity.z = 0
	_moving = null
	equipment_pose_requested.emit(HeldItemPresentation.Pose.NORMAL)
	return result(true, "Released object.")

func prepare_movement() -> void:
	if _moving == null:
		return
	if actor.global_position.distance_to(_moving.global_position) > manipulation_reach or not actor.controls_enabled or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		stop_move()
		return
	var ray := PhysicsRayQueryParameters3D.create(actor.camera.global_position, _moving.global_position, 1)
	ray.exclude = [actor.get_rid()]
	var hit := actor.get_world_3d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty() and hit.collider != _moving:
		stop_move()

func effective_speed(normal_speed: float) -> float:
	if _moving == null:
		return normal_speed
	return minf(normal_speed, _moving.move_speed * movement_speed_ratio)

func effective_acceleration(normal_acceleration: float) -> float:
	if _moving == null:
		return normal_acceleration
	return minf(normal_acceleration, _moving.move_acceleration * 0.3)

func constrain_velocity(requested: Vector3, delta: float) -> Vector3:
	if _moving == null:
		return requested
	var displacement := _moving.global_position - actor.global_position
	displacement.y = 0
	var distance := displacement.length()
	var toward := displacement.normalized()
	var horizontal := Vector3(requested.x, 0, requested.z).limit_length(effective_speed(actor.movement_speed))
	var radial := horizontal.dot(toward)
	var object_radial := _moving.linear_velocity.dot(toward)
	# Close in only as fast as current clearance allows. At an obstacle the
	# player comes to rest outside the object's collision radius, without pushes.
	var inward := maxf(0, object_radial + (distance - _minimum_separation) * 2.0)
	inward = minf(inward, maxf(0, distance - _minimum_separation) / maxf(delta, 0.001))
	# If dragging a blocked object, slow before walking beyond the stable anchor.
	var outward := maxf(0, -object_radial + (_move_distance + 0.35 - distance) * 2.0)
	horizontal += toward * (clampf(radial, -outward, inward) - radial)
	return Vector3(horizontal.x, requested.y, horizontal.z)

func update_goal() -> void:
	if _moving == null:
		return
	var desired_direction := (actor.global_basis * _local_direction).normalized()
	var current_direction := _moving.global_position - actor.global_position
	current_direction.y = 0
	current_direction = current_direction.normalized()
	# Follow turns around the actor, rather than pulling through their body.
	var turn := current_direction.signed_angle_to(desired_direction, Vector3.UP)
	var goal_direction := current_direction.rotated(Vector3.UP, clampf(turn, -0.35, 0.35))
	_moving.move_goal = actor.global_position + goal_direction * _move_distance
	_moving.move_goal.y = _moving.global_position.y
	var actual := actor.get_real_velocity()
	_moving.move_velocity = Vector3(actual.x, 0, actual.z)

static func horizontal_radius(body: Node3D) -> float:
	var radius: float = 0.0
	for child in body.get_children():
		if child is CollisionShape3D and child.shape != null and not child.disabled:
			if child.shape is CapsuleShape3D or child.shape is SphereShape3D:
				radius = maxf(radius, child.shape.radius + Vector2(child.position.x, child.position.z).length())
			else:
				var bounds: AABB = child.shape.get_debug_mesh().get_aabb()
				var half: Vector3 = bounds.position.abs().max(bounds.end.abs()) * child.scale.abs()
				radius = maxf(radius, Vector2(half.x, half.z).length() + Vector2(child.position.x, child.position.z).length())
	return radius

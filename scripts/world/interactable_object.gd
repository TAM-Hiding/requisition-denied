class_name InteractableObject
extends RigidBody3D
## Runtime body. Definitions describe the object; state belongs to this instance.
enum State { WORLD, HELD, STOWED, MOVING }
@export var definition: ObjectDefinition
var state: State = State.WORLD
var _mobility_override: int = -1
var move_goal: Vector3
var move_velocity: Vector3
@export var move_speed: float = 2.5
@export var move_acceleration: float = 20.0

func _ready() -> void:
	mass = maxf(definition.mass_kg, 0.1) if definition != null else 1.0
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	lock_rotation = true
	continuous_cd = true
	linear_damp = 1.5
	collision_layer = 1
	collision_mask = 3
	freeze = mobility() == ObjectDefinition.Mobility.FIXED

func mobility() -> int:
	if _mobility_override >= 0:
		return _mobility_override
	return definition.mobility if definition != null else ObjectDefinition.Mobility.FIXED

func set_mobility(value: ObjectDefinition.Mobility) -> bool:
	if state != State.WORLD:
		return false
	_mobility_override = value
	freeze = value == ObjectDefinition.Mobility.FIXED
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	sleeping = false
	return true

func mobility_name() -> String:
	return ObjectDefinition.Mobility.keys()[mobility()]

func state_name() -> String:
	return State.keys()[state]

func query_actions() -> Array[StringName]:
	var actions: Array[StringName] = []
	if definition == null or state not in [State.WORLD, State.MOVING]:
		return actions
	# Manipulation actions are derived, never trusted from static definition lists.
	for action in definition.available_actions:
		if action not in [&"pick_up", &"move", &"stow"]:
			actions.append(action)
	if state == State.WORLD:
		if mobility() == ObjectDefinition.Mobility.CARRYABLE:
			actions.append(&"pick_up")
		elif mobility() == ObjectDefinition.Mobility.MOVABLE:
			actions.append(&"move")
	return actions

func _integrate_forces(body: PhysicsDirectBodyState3D) -> void:
	if state != State.MOVING:
		return
	var error := move_goal - body.transform.origin
	error.y = 0
	var desired := (move_velocity + error * 4.0).limit_length(move_speed)
	var horizontal := Vector3(body.linear_velocity.x, 0, body.linear_velocity.z)
	horizontal = horizontal.move_toward(desired, move_acceleration * body.step)
	body.linear_velocity = Vector3(horizontal.x, body.linear_velocity.y, horizontal.z)

func inspection_information() -> Dictionary:
	return definition.inspection_information()

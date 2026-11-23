class_name InteractableObject
extends RigidBody3D
## Runtime body. Definitions describe the object; state belongs to this instance.
enum State { WORLD, HELD, STOWED, MOVING, CARRIED }
# Otis sweeps against world bodies and supplies his weight and deliberate pushes.
# Do not also let the rigid solver treat his kinematic collider as infinite mass.
const WORLD_COLLISION_MASK := 1
@export var definition: ObjectDefinition
var state: State = State.WORLD
var storage_owner: InventoryContainer
var equipment_owner: Node
var fastened := false
var fastening_system: FasteningSystem
var support_carrier: CharacterBody3D
var _mobility_override: int = -1
var move_goal: Vector3
var move_speed_scale := 1.0
@export var move_speed: float = 2.5
@export var move_acceleration: float = 20.0

func _ready() -> void:
	mass = maxf(definition.mass_kg, 0.1) if definition != null else 1.0
	freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
	lock_rotation = true
	continuous_cd = true
	linear_damp = 1.5
	collision_layer = 1
	collision_mask = WORLD_COLLISION_MASK
	freeze = mobility() == ObjectDefinition.Mobility.FIXED

func mobility() -> int:
	if _mobility_override >= 0:
		return _mobility_override
	return definition.mobility if definition != null else ObjectDefinition.Mobility.FIXED

func set_mobility(value: ObjectDefinition.Mobility) -> bool:
	if state != State.WORLD or fastened:
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

func assembly_root() -> PhysicsBody3D:
	if not fastened:
		return self
	if not is_instance_valid(fastening_system):
		return null
	return fastening_system.connected_root(self)

func compatible_equipment_slots() -> Array[StringName]:
	if not definition.equipment_slots.is_empty():
		return definition.equipment_slots.duplicate()
	return [&"tool"] if mobility() == ObjectDefinition.Mobility.CARRYABLE else []

func inventory_state() -> Dictionary:
	var metadata := {}
	for key in get_meta_list():
		metadata[key] = get_meta(key)
	return {"condition": definition.condition, "properties": definition.properties.duplicate(true), "metadata": metadata}

func query_actions() -> Array[StringName]:
	var actions: Array[StringName] = []
	if definition == null or state not in [State.WORLD, State.MOVING]:
		return actions
	# Manipulation actions are derived, never trusted from static definition lists.
	for action in definition.available_actions:
		if action not in [&"pick_up", &"move", &"stow", &"lift"]:
			actions.append(action)
	if state == State.WORLD and mobility() != ObjectDefinition.Mobility.FIXED:
		var root_body := assembly_root() as InteractableObject
		if not fastened and mobility() == ObjectDefinition.Mobility.CARRYABLE:
			actions.append(&"pick_up")
		if root_body != null and root_body.state == State.WORLD and root_body.mobility() != ObjectDefinition.Mobility.FIXED:
			actions.append(&"move")
			actions.append(&"store")
	return actions

func _integrate_forces(body: PhysicsDirectBodyState3D) -> void:
	if state != State.MOVING:
		return
	var error := move_goal - body.transform.origin
	error.y = 0
	var desired := (error * 4.0).limit_length(move_speed * move_speed_scale)
	var horizontal := Vector3(body.linear_velocity.x, 0, body.linear_velocity.z)
	horizontal = horizontal.move_toward(desired, move_acceleration * body.step)
	body.linear_velocity = Vector3(horizontal.x, body.linear_velocity.y, horizontal.z)

func inspection_information() -> Dictionary:
	var information := definition.inspection_information()
	if fastened or mobility() != ObjectDefinition.Mobility.FIXED:
		information.description += "\n\nFasteners: " + ("Connected assembly" if fastened else "Independent")
	return information

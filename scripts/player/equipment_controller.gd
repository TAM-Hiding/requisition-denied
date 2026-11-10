class_name EquipmentController
extends Node
## One active slot and a small storage container; references retain instance identity.
signal feedback(message: String)
signal changed
@export var storage_capacity: int = 1
@export var manipulation_reach: float = 3.5
var _held: InteractableObject
var _stored: Array[InteractableObject] = []
var _moving: InteractableObject
var _move_distance: float = 2.0
var _world_parent: Node3D
@onready var actor: OtisController = get_parent() as OtisController
@onready var anchor: Node3D = actor.get_node("Camera3D/EquipmentAnchor")

func held_item() -> InteractableObject:
	return _held

func stored_items() -> Array[InteractableObject]:
	return _stored.duplicate()

func moving_object() -> InteractableObject:
	return _moving

func result(ok: bool, message: String) -> Dictionary:
	feedback.emit(message)
	if ok:
		changed.emit()
	return {"ok": ok, "message": message}

func pick_up(item: InteractableObject) -> Dictionary:
	if not is_instance_valid(item) or item.mobility() != ObjectDefinition.Mobility.CARRYABLE or item.state != InteractableObject.State.WORLD:
		return result(false, "That object cannot be picked up.")
	if _held != null or _moving != null or _stored.has(item):
		return result(false, "Free your active equipment slot first.")
	_world_parent = actor.get_tree().current_scene as Node3D
	if _world_parent == null:
		return result(false, "No world available for equipment.")
	_held = item
	attach(item)
	return result(true, "Equipped %s. Hold E to stow; G to drop." % item.definition.display_name)

func attach(item: InteractableObject) -> void:
	item.freeze = true
	item.linear_velocity = Vector3.ZERO
	item.angular_velocity = Vector3.ZERO
	item.collision_layer = 0
	item.collision_mask = 0
	item.state = InteractableObject.State.HELD
	item.reparent(anchor)
	item.transform = Transform3D.IDENTITY
	item.show()

func stow() -> Dictionary:
	if _held == null:
		return result(false, "No held item to stow.")
	if _held.mobility() != ObjectDefinition.Mobility.CARRYABLE or _held.state != InteractableObject.State.HELD:
		return result(false, "This object cannot be stowed.")
	if _stored.size() >= storage_capacity or _stored.has(_held):
		return result(false, "Equipment storage is full.")
	var item := _held
	_stored.append(item)
	_held = null
	item.state = InteractableObject.State.STOWED
	item.reparent(self)
	item.hide()
	return result(true, "Stowed %s. Press 1 to retrieve." % item.definition.display_name)

func equip_first() -> Dictionary:
	if _held != null or _moving != null:
		return result(false, "Free your active equipment slot first.")
	if _stored.is_empty():
		return result(false, "No stored equipment.")
	var item := _stored[0]
	if item.state != InteractableObject.State.STOWED or item.mobility() != ObjectDefinition.Mobility.CARRYABLE:
		return result(false, "Stored item cannot be equipped.")
	_stored.remove_at(0)
	_held = item
	attach(item)
	return result(true, "Equipped %s." % item.definition.display_name)

func drop() -> Dictionary:
	if _held == null:
		return result(false, "No held item to drop.")
	var item := _held
	var collider := item.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collider == null or collider.shape == null:
		return result(false, "Item has no valid drop collision shape.")
	var space := actor.get_world_3d().direct_space_state
	# Test both the route and final volume, including the player's collider.
	# No safe candidate means no transition: the item remains held.
	for distance in [1.15, 0.9, 0.7]:
		var at: Vector3 = actor.camera.global_position - actor.camera.global_basis.z * distance
		var candidate := Transform3D(Basis.IDENTITY, at)
		var ray := PhysicsRayQueryParameters3D.create(actor.camera.global_position, at, 1)
		ray.exclude = [item.get_rid(), actor.get_rid()]
		if not space.intersect_ray(ray).is_empty():
			continue
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = collider.shape
		query.transform = candidate * collider.transform
		query.collision_mask = 3
		query.margin = 0.08
		query.exclude = [item.get_rid()]
		if not space.intersect_shape(query, 1).is_empty():
			continue
		item.reparent(_world_parent)
		item.global_transform = candidate
		item.state = InteractableObject.State.WORLD
		item.collision_layer = 1
		item.collision_mask = 3
		item.freeze = false
		item.sleeping = false
		item.linear_velocity = Vector3.ZERO
		item.angular_velocity = Vector3.ZERO
		_held = null
		return result(true, "Dropped %s." % item.definition.display_name)
	return result(false, "No clear space to drop. Step back or look elsewhere.")

func begin_move(item: InteractableObject) -> Dictionary:
	if not is_instance_valid(item) or item.mobility() != ObjectDefinition.Mobility.MOVABLE or item.state != InteractableObject.State.WORLD:
		return result(false, "That object cannot be moved.")
	if _held != null or _moving != null:
		return result(false, "Free your active equipment slot first.")
	_moving = item
	_move_distance = clampf(actor.global_position.distance_to(item.global_position), 1.5, 2.5)
	item.move_goal = item.global_position
	item.state = InteractableObject.State.MOVING
	item.sleeping = false
	return result(true, "Moving %s. Tap E, G or Esc to release." % item.definition.display_name)

func stop_move() -> Dictionary:
	if _moving == null:
		return result(false, "No environmental manipulation active.")
	_moving.state = InteractableObject.State.WORLD
	# Release without imparting a throw.
	_moving.linear_velocity.x = 0
	_moving.linear_velocity.z = 0
	_moving = null
	return result(true, "Released object.")

func _physics_process(_delta: float) -> void:
	if _moving == null:
		return
	var separation := actor.global_position.distance_to(_moving.global_position)
	if separation > manipulation_reach or not actor.controls_enabled or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		stop_move()
		return
	var ray := PhysicsRayQueryParameters3D.create(actor.camera.global_position, _moving.global_position, 1)
	ray.exclude = [actor.get_rid()]
	var hit := actor.get_world_3d().direct_space_state.intersect_ray(ray)
	if not hit.is_empty() and hit.collider != _moving:
		stop_move()
		return
	var forward := -actor.global_basis.z
	_moving.move_goal = actor.global_position + forward * _move_distance
	_moving.move_goal.y = _moving.global_position.y

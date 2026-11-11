class_name EquipmentController
extends Node
## One active slot and a small storage container; references retain instance identity.
signal feedback(message: String)
signal changed
@export var storage_capacity: int = 1
var _held: InteractableObject
var _stored: Array[InteractableObject] = []
var placing := false
var presentation: HeldItemPresentation
var _world_parent: Node3D
@onready var actor: OtisController = get_parent() as OtisController
@onready var anchor: Node3D = actor.get_node("Camera3D/EquipmentAnchor")

func held_item() -> InteractableObject:
	return _held

func stored_items() -> Array[InteractableObject]:
	return _stored.duplicate()

func _ready() -> void:
	presentation = HeldItemPresentation.new()
	presentation.name = "HeldPresentation"
	add_child(presentation)
	presentation.configure(actor, anchor)

func result(ok: bool, message: String) -> Dictionary:
	feedback.emit(message)
	if ok:
		changed.emit()
	return {"ok": ok, "message": message}

func pick_up(item: InteractableObject) -> Dictionary:
	if not is_instance_valid(item) or item.mobility() != ObjectDefinition.Mobility.CARRYABLE or item.state != InteractableObject.State.WORLD:
		return result(false, "That object cannot be picked up.")
	if _held != null or _stored.has(item):
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
	if item.get_parent() != anchor:
		item.reparent(anchor)
	item.transform = Transform3D.IDENTITY
	item.show()
	presentation.track(item)

func stow() -> Dictionary:
	if placing:
		return result(false, "Finish or cancel placement first.")
	if _held == null:
		return result(false, "No held item to stow.")
	if _held.mobility() != ObjectDefinition.Mobility.CARRYABLE or _held.state != InteractableObject.State.HELD:
		return result(false, "This object cannot be stowed.")
	if _stored.size() >= storage_capacity or _stored.has(_held):
		return result(false, "Equipment storage is full.")
	var item := _held
	_stored.append(item)
	_held = null
	presentation.clear()
	item.state = InteractableObject.State.STOWED
	item.reparent(self)
	item.hide()
	return result(true, "Stowed %s. Press 1 to retrieve." % item.definition.display_name)

func equip_first() -> Dictionary:
	if _held != null:
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
	if placing:
		return result(false, "Finish or cancel placement first.")
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
		return release_to_world(candidate, false)
	return result(false, "No clear space to drop. Step back or look elsewhere.")

func begin_placement() -> bool:
	if placing or _held == null:
		return false
	var pose := _held.global_transform
	placing = true
	presentation.clear()
	_held.top_level = true
	_held.global_transform = pose
	_held.show()
	return true

func cancel_placement() -> void:
	if placing and _held != null:
		placing = false
		_held.top_level = false
		attach(_held)

func finish_placement(pose: Transform3D) -> Dictionary:
	if not placing or _held == null:
		return result(false, "No object in placement mode.")
	return release_to_world(pose, true)

func release_to_world(pose: Transform3D, precision: bool) -> Dictionary:
	var item := _held
	item.reparent(_world_parent)
	item.top_level = false
	item.global_transform = pose
	item.state = InteractableObject.State.WORLD
	item.collision_layer = 1
	item.collision_mask = 3
	item.lock_rotation = not precision
	item.freeze = false
	item.sleeping = false
	item.linear_velocity = Vector3.ZERO
	item.angular_velocity = Vector3.ZERO
	_held = null
	placing = false
	presentation.clear()
	var verb := "Placed" if precision else "Dropped"
	return result(true, "%s %s." % [verb, item.definition.display_name])

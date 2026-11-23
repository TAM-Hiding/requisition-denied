class_name EquipmentController
extends Node
## The tool slot and container share the same live item instances.
signal feedback(message: String)
signal changed
var container: InventoryContainer
var world_drops := WorldDropPlacement.new()
var dumping := false
@export var dump_stagger_frames := 3
## Supported active sockets are explicit. Future categories register here.
var slot_interfaces: Dictionary = {&"tool": &"handheld"}
var _held: InteractableObject

var placing := false
var presentation: HeldItemPresentation
var _world_parent: Node3D
@onready var actor: OtisController = get_parent() as OtisController
@onready var anchor: Node3D = actor.get_node("Camera3D/EquipmentAnchor")

func held_item() -> InteractableObject:
	return _held

func stored_items() -> Array[InteractableObject]:
	return container.items()

func _ready() -> void:
	container = InventoryContainer.new()
	container.name = "PersonalStorage"
	container.definition = preload("res://data/inventory/personal_storage.tres").duplicate()
	add_child(container)
	container.changed.connect(func() -> void: changed.emit())
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
	if is_instance_valid(item) and item.has_meta(CraneRigging.ATTACHED_META):
		return result(false, "Release the crane strap before taking the load.")
	if dumping:
		return result(false, "Finish emptying the satchel first.")
	if not is_instance_valid(item) or item.fastened or item.mobility() != ObjectDefinition.Mobility.CARRYABLE or item.state != InteractableObject.State.WORLD or item.storage_owner != null or item.equipment_owner != null:
		return result(false, "That object cannot be picked up.")
	if _held != null or not item.compatible_equipment_slots().has(&"tool") or not slot_interfaces.has(&"tool"):
		return result(false, "Free your active equipment slot first.")
	_world_parent = actor.get_tree().current_scene as Node3D
	if _world_parent == null:
		return result(false, "No world available for equipment.")
	_held = item
	attach(item)
	return result(true, "Equipped %s. Hold E to stow; G to drop." % item.definition.display_name)

func attach(item: InteractableObject) -> void:
	item.equipment_owner = self
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

func inventory_mass_kg() -> float:
	return container.mass_kg()

func equipped_mass_kg() -> float:
	return _held.mass if is_instance_valid(_held) else 0.0

func store_world(item: InteractableObject) -> Dictionary:
	if is_instance_valid(item) and item.has_meta(CraneRigging.ATTACHED_META):
		return result(false, "Release the crane strap before taking the load.")
	if dumping:
		return result(false, "Finish emptying the satchel first.")
	if actor.placement.is_active():
		return result(false, "Place or cancel the manipulated object first.")
	var issue := container.insert(item)
	return result(issue.is_empty(), "Stored %s." % item.definition.display_name if issue.is_empty() else issue)

func stow() -> Dictionary:
	if dumping:
		return result(false, "Finish emptying the satchel first.")
	if placing:
		return result(false, "Finish or cancel placement first.")
	if _held == null:
		return result(false, "No held item to stow.")
	var item := _held
	if item.state != InteractableObject.State.HELD or item.equipment_owner != self:
		return result(false, "Equipment ownership unavailable.")
	var issue := container.admission(item)
	if not issue.is_empty():
		return result(false, issue)
	if item is FasteningTool:
		item.update_removal(0.0, false)
	_held = null
	item.equipment_owner = null
	presentation.clear()
	container.commit_insert(item)
	container.changed.emit()
	return result(true, "Stowed %s. Press 1 to retrieve." % item.definition.display_name)

func equipment_slot(item: InteractableObject) -> StringName:
	for slot in item.compatible_equipment_slots():
		if slot_interfaces.has(slot):
			return slot
	return &""

func equip_item(item: InteractableObject) -> Dictionary:
	if dumping:
		return result(false, "Finish emptying the satchel first.")
	if not actor.get_tree().current_scene is Node3D:
		return result(false, "World placement unavailable.")
	if placing or not container.accessible or not container.contains(item) or item.storage_owner != container \
			or item.state != InteractableObject.State.STOWED or item.equipment_owner != null:
		return result(false, "Stored equipment unavailable.")
	if equipment_slot(item) != &"tool" or item.mobility() != ObjectDefinition.Mobility.CARRYABLE:
		return result(false, "No compatible equipment slot.")
	if actor.placement.is_active() and (not actor.placement.is_grabbing() or not item is FasteningTool):
		return result(false, "Place or cancel the current object first.")
	if _held != null:
		var issue := container.admission(_held, item)
		if not issue.is_empty():
			return result(false, "Cannot store displaced equipment. " + issue)
	# All checks precede the transfer. No signal is emitted until both owners
	# and the scene hierarchy agree.
	var displaced := _held
	container.commit_remove(item)
	if displaced != null:
		if displaced is FasteningTool:
			displaced.update_removal(0.0, false)
		displaced.equipment_owner = null
		presentation.clear()
		container.commit_insert(displaced)
	_world_parent = actor.get_tree().current_scene as Node3D
	_held = item
	attach(item)
	container.changed.emit()
	return result(true, "Equipped %s." % item.definition.display_name)

func first_equippable() -> InteractableObject:
	for item in container.items():
		if equipment_slot(item) == &"tool":
			return item
	return null

func equip_first() -> Dictionary:
	if _held != null:
		return result(false, "Free your active equipment slot first.")
	var item := first_equippable()
	return equip_item(item) if item != null else result(false, "No stored equipment.")

func retrieve(item: InteractableObject) -> Dictionary:
	if dumping:
		return result(false, "Finish emptying the satchel first.")
	return retrieve_scattered(item)

func retrieve_scattered(item: InteractableObject, release_index := 0) -> Dictionary:
	if not actor.get_tree().current_scene is Node3D:
		return result(false, "World placement unavailable.")
	if not container.accessible or not container.contains(item) or item.storage_owner != container \
			or item.state != InteractableObject.State.STOWED or item.equipment_owner != null:
		return result(false, "Stored item unavailable.")
	var candidate: Variant = world_drops.find_pose(actor, item, release_index)
	if candidate == null:
		return result(false, "No clear space to retrieve. Step back or look elsewhere.")
	container.commit_remove(item)
	restore_world(item, candidate, true)
	world_drops.remember(item, candidate)
	container.changed.emit()
	return result(true, "Retrieved %s." % item.definition.display_name)

func dump_container() -> Dictionary:
	if dumping:
		return {"ok": false, "released": 0, "retained": container.items().size(), "message": "The satchel is already emptying."}
	if not container.accessible or not actor.get_tree().current_scene is Node3D:
		return {"ok": false, "released": 0, "retained": container.items().size(), "message": "Container or world placement unavailable."}
	dumping = true
	var pending := container.items()
	var released := 0
	for item in pending:
		if not is_instance_valid(item) or not container.contains(item):
			continue
		var transfer := retrieve_scattered(item, released)
		if transfer.ok:
			released += 1
		# Give Godot time to synchronize and settle the preceding release.
		# Each later item queries the current world and the resulting pile.
		for frame in maxi(1, dump_stagger_frames):
			await get_tree().physics_frame
	dumping = false
	var retained := container.items().size()
	var message := "Dropped %d item(s)." % released
	if retained > 0:
		message += " %d retained because no safe release was available." % retained
	feedback.emit(message)
	return {"ok": retained == 0, "released": released, "retained": retained, "message": message}

func drop_pose(item: InteractableObject) -> Variant:
	var clearance := PlacementClearance.new()
	if not clearance.configure(item):
		return null
	for distance in [1.15, 0.9, 0.7]:
		var at: Vector3 = actor.camera.global_position - actor.camera.global_basis.z * distance
		var candidate := Transform3D(Basis.IDENTITY, at)
		var ray := PhysicsRayQueryParameters3D.create(actor.camera.global_position, at, 1 | 16)
		ray.exclude = [item.get_rid(), actor.get_rid()]
		if not actor.get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
			continue
		if not clearance.clear(candidate, 3 | 16, 0.079):
			continue
		var start := Transform3D(Basis.IDENTITY, actor.camera.global_position)
		var route_clear := true
		for shape in clearance.shapes:
			var query := clearance.query(start, 1 | 16, 0.0, shape)
			query.exclude.append(actor.get_rid())
			query.motion = at - start.origin
			var space := actor.get_world_3d().direct_space_state
			if not space.intersect_shape(query, 1).is_empty() or space.cast_motion(query)[0] < 1.0:
				route_clear = false
				break
		if route_clear:
			return candidate
	return null

func drop() -> Dictionary:
	if dumping:
		return result(false, "Finish emptying the satchel first.")
	if not actor.get_tree().current_scene is Node3D:
		return result(false, "World placement unavailable.")
	if placing:
		return result(false, "Finish or cancel placement first.")
	if _held == null:
		return result(false, "No held item to drop.")
	var candidate: Variant = drop_pose(_held)
	if candidate == null:
		return result(false, "No clear space to drop. Step back or look elsewhere.")
	return release_to_world(candidate, false)

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
	if not actor.get_tree().current_scene is Node3D:
		return result(false, "World placement unavailable.")
	if not placing or _held == null:
		return result(false, "No object in placement mode.")
	return release_to_world(pose, true)

func restore_world(item: InteractableObject, pose: Transform3D, precision: bool) -> void:
	var parent := actor.get_tree().current_scene as Node3D
	item.reparent(parent)
	item.top_level = false
	item.global_transform = pose
	item.state = InteractableObject.State.WORLD
	item.equipment_owner = null
	item.collision_layer = 1
	item.collision_mask = 3
	item.lock_rotation = not precision
	item.freeze = false
	item.sleeping = false
	item.linear_velocity = Vector3.ZERO
	item.angular_velocity = Vector3.ZERO
	item.show()

func release_to_world(pose: Transform3D, precision: bool) -> Dictionary:
	var item := _held
	restore_world(item, pose, precision)
	_held = null
	placing = false
	presentation.clear()
	var verb := "Placed" if precision else "Dropped"
	return result(true, "%s %s." % [verb, item.definition.display_name])

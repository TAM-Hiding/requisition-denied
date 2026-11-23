class_name ScrapSupply
extends Node3D

const INDUSTRIAL_PAD := Vector3(0, 0, 9.5)
const INDUSTRIAL_PAD_WIDTH := 9.60
const INDUSTRIAL_PAD_DEPTH := 1.24
const DELIVERY_MASK := 1 | 2 | 16
const PROVENANCE := &"rd009_development_scrap"
var catalog := ScrapCatalog.entries()
var delivery := Vector3(-4.65, 0.18, 4.88)
var industrial_delivery_hall: Node3D
var finish: Material
var next_id := 1

func dispense(index: int) -> InteractableObject:
	if index < 0 or index >= catalog.size():
		return null
	var entry := catalog[index]
	var industrial: bool = entry.get("industrial", false)
	var pose := Transform3D(Basis.IDENTITY, delivery)
	if industrial:
		if not is_instance_valid(industrial_delivery_hall) or industrial_pad_occupied():
			return null
		var center := INDUSTRIAL_PAD + Vector3.UP * (float(entry.size.y) * 0.5 + 0.05)
		pose = industrial_delivery_hall.global_transform * Transform3D(Basis.IDENTITY, center)
	var space := get_world_3d().direct_space_state
	for component: Array in entry.shapes:
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = component[0]
		query.transform = pose * component[2]
		query.collision_mask = DELIVERY_MASK
		query.margin = 0.005
		if not space.intersect_shape(query, 1).is_empty():
			return null
	# Reserve the pad until the next physics frame can see the new shapes.
	if get_meta(&"last_dispense_frame", -1) == Engine.get_physics_frames():
		return null
	set_meta(&"last_dispense_frame", Engine.get_physics_frames())
	var part := InteractableObject.new()
	part.name = "Scrap_%d" % next_id
	part.definition = ObjectDefinition.new()
	part.definition.object_id = StringName("RD-SCRAP-%d" % next_id)
	part.definition.display_name = entry.title
	part.definition.mass_kg = entry.mass
	part.definition.properties["inventory_icon"] = entry.icon
	part.definition.properties[&"center_of_mass_local"] = entry.center_of_mass
	part.definition.mobility = ObjectDefinition.Mobility.MOVABLE
	part.definition.description = "%s %s." % [
		entry.get("description", "Rigid steel development stock."), dimensions(entry.size)]
	part.set_meta(PROVENANCE, true)
	next_id += 1
	for component: Array in entry.shapes:
		var collision := CollisionShape3D.new()
		collision.name = "CollisionShape3D" if part.get_child_count() == 0 else "StockCollider"
		collision.shape = component[0]
		collision.transform = component[2]
		part.add_child(collision, true)
		if component[1] != null:
			add_model(part, component[1], component[2])
	if entry.has("mesh"):
		add_model(part, entry.mesh, Transform3D.IDENTITY)
	# Use the same world parent as authored loose parts.
	part.transform = (get_parent() as Node3D).global_transform.affine_inverse() * pose
	get_parent().add_child(part)
	if industrial:
		# Industrial articles are free bodies on delivery, including roll around bar stock.
		part.lock_rotation = false
	return part

func industrial_pad_occupied() -> bool:
	# Reserve the floor footprint too, including stock thinner than the delivery gap.
	var occupancy := BoxShape3D.new()
	occupancy.size = Vector3(INDUSTRIAL_PAD_WIDTH, 0.90, INDUSTRIAL_PAD_DEPTH)
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = occupancy
	var center := INDUSTRIAL_PAD + Vector3.UP * 0.455
	query.transform = industrial_delivery_hall.global_transform * Transform3D(Basis.IDENTITY, center)
	query.collision_mask = DELIVERY_MASK
	query.margin = 0.001
	return not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()


func add_model(part: InteractableObject, mesh: Mesh, pose: Transform3D) -> void:
	var model := MeshInstance3D.new()
	model.mesh = mesh
	model.material_override = finish
	model.transform = pose
	part.add_child(model)

func clear_loose() -> int:
	var count := 0
	for part in get_parent().get_children():
		if part is InteractableObject and part.has_meta(PROVENANCE) and not part.is_queued_for_deletion() \
				and part.state == InteractableObject.State.WORLD and not part.fastened and not part.freeze:
			part.queue_free()
			count += 1
	return count

static func dimensions(size: Vector3) -> String:
	return "%.0f × %.0f × %.0f mm" % [size.x * 1000, size.y * 1000, size.z * 1000]

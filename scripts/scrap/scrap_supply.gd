class_name ScrapSupply
extends Node3D

const PROVENANCE := &"rd009_development_scrap"
var catalog := ScrapCatalog.entries()
var delivery := Vector3(-4.65, 0.18, 4.88)
var finish: Material
var next_id := 1

func dispense(index: int) -> InteractableObject:
	if index < 0 or index >= catalog.size():
		return null
	var entry := catalog[index]
	var pose := Transform3D(Basis.IDENTITY, delivery)
	var space := get_world_3d().direct_space_state
	for component: Array in entry.shapes:
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = component[0]
		query.transform = pose * component[2]
		query.collision_mask = 1 | 2 | 16
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
	part.definition.mobility = ObjectDefinition.Mobility.MOVABLE
	part.definition.description = "Rigid steel development stock. %s." % dimensions(entry.size)
	part.set_meta(PROVENANCE, true)
	next_id += 1
	for component: Array in entry.shapes:
		var collision := CollisionShape3D.new()
		collision.name = "CollisionShape3D" if part.get_child_count() == 0 else "StockCollider"
		collision.shape = component[0]
		collision.transform = component[2]
		part.add_child(collision, true)
		var model := MeshInstance3D.new()
		model.mesh = component[1]
		model.material_override = finish
		model.transform = component[2]
		part.add_child(model)
	# Use the same world parent as authored loose parts.
	part.transform = (get_parent() as Node3D).global_transform.affine_inverse() * pose
	get_parent().add_child(part)
	return part

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

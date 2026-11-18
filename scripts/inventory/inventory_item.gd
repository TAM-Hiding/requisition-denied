class_name InventoryItem
extends RefCounted
## A record references the live object. It never instantiates a replacement.
var body: InteractableObject
var internal_pose := Transform3D.IDENTITY

static func from_body(item: InteractableObject) -> InventoryItem:
	var record := InventoryItem.new()
	record.body = item
	return record

func dimensions() -> Vector3:
	var bounds := AABB()
	var initialized := false
	for child in body.get_children():
		if child is CollisionShape3D and not child.disabled and child.shape != null:
			var box: AABB = child.transform * child.shape.get_debug_mesh().get_aabb()
			bounds = bounds.merge(box) if initialized else box
			initialized = true
	return bounds.size * body.global_basis.get_scale().abs()

func volume_m3() -> float:
	var size := dimensions()
	return size.x * size.y * size.z

func snapshot() -> Dictionary:
	return {
		"item_id": String(body.definition.object_id), "definition_path": body.definition.resource_path,
		"name": body.definition.display_name, "mass_kg": body.mass,
		"dimensions_m": vector_array(dimensions()), "volume_m3": volume_m3(),
		"equipment_slots": Array(body.compatible_equipment_slots()),
		"gameplay": serialized_state(body), "internal_pose": transform_array(internal_pose)
	}

static func serialized_state(item: InteractableObject) -> Variant:
	# Native Variant tags retain numeric types, vectors and metadata keys in
	# a JSON-safe representation. Objects are intentionally not encoded.
	return JSON.parse_string(JSON.stringify(JSON.from_native(item.inventory_state())))

static func vector_array(vector: Vector3) -> Array:
	return [vector.x, vector.y, vector.z]

static func transform_array(pose: Transform3D) -> Array:
	return [vector_array(pose.basis.x), vector_array(pose.basis.y), vector_array(pose.basis.z), vector_array(pose.origin)]

static func parse_pose(value: Variant) -> Variant:
	if not value is Array or value.size() != 4:
		return null
	var vectors: Array[Vector3] = []
	for row in value:
		if not row is Array or row.size() != 3:
			return null
		for number in row:
			if typeof(number) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(number)):
				return null
		vectors.append(Vector3(row[0], row[1], row[2]))
	var pose := Transform3D(Basis(vectors[0], vectors[1], vectors[2]), vectors[3])
	return pose if absf(pose.basis.determinant() - 1.0) < 0.001 else null

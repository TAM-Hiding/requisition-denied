class_name ContainerPacking
extends RefCounted
## Bounded conservative packing. Bounds use the real shape offsets and scale.
const GAP := 0.003
const MAX_ATTEMPTS := 4096
const ROTATIONS := [
	Vector3(0, 0, 0), Vector3(0, PI / 2, 0), Vector3(PI / 2, 0, 0),
	Vector3(0, 0, PI / 2), Vector3(PI / 2, PI / 2, 0), Vector3(0, PI / 2, PI / 2)
]

static func local_bounds(item: InteractableObject) -> AABB:
	var bounds := AABB()
	var initialized := false
	var scale_basis := Basis.from_scale(item.global_basis.get_scale().abs())
	for child in item.get_children():
		if child is CollisionShape3D and not child.disabled and child.shape != null:
			var box: AABB = Transform3D(scale_basis, Vector3.ZERO) * child.transform * child.shape.get_debug_mesh().get_aabb()
			bounds = bounds.merge(box) if initialized else box
			initialized = true
	return bounds

static func bounds(record: InventoryItem, pose: Transform3D) -> AABB:
	return pose * local_bounds(record.body)

static func inside(box: AABB, envelope: Vector3, tolerance := 0.0) -> bool:
	var low := Vector3(-envelope.x / 2, 0, -envelope.z / 2)
	return box.position.x >= low.x - tolerance and box.position.y >= -tolerance and box.position.z >= low.z - tolerance \
		and box.end.x <= -low.x + tolerance and box.end.y <= envelope.y + tolerance and box.end.z <= -low.z + tolerance

static func clear(box: AABB, envelope: Vector3, occupied: Array[AABB]) -> bool:
	if not inside(box, envelope):
		return false
	for other in occupied:
		if box.grow(GAP * 0.5).intersects(other.grow(GAP * 0.5)):
			return false
	return true

static func find_pose(record: InventoryItem, envelope: Vector3, occupied: Array[AABB]) -> Variant:
	var low := Vector3(-envelope.x / 2 + GAP, GAP, -envelope.z / 2 + GAP)
	var xs: Array[float] = [low.x]
	var ys: Array[float] = [low.y]
	var zs: Array[float] = [low.z]
	for box in occupied:
		if not xs.has(box.end.x + GAP * 2):
			xs.append(box.end.x + GAP * 2)
		if not ys.has(box.end.y + GAP * 2):
			ys.append(box.end.y + GAP * 2)
		if not zs.has(box.end.z + GAP * 2):
			zs.append(box.end.z + GAP * 2)
	xs.sort()
	ys.sort()
	zs.sort()
	var attempts := 0
	for angles: Vector3 in ROTATIONS:
		var rotation := Basis.from_euler(angles)
		var rotated: AABB = Transform3D(rotation, Vector3.ZERO) * local_bounds(record.body)
		for y in ys:
			for z in zs:
				for x in xs:
					attempts += 1
					if attempts > MAX_ATTEMPTS:
						return null
					var pose := Transform3D(rotation, Vector3(x, y, z) - rotated.position)
					if clear(bounds(record, pose), envelope, occupied):
						return pose
	return null

## Existing poses are retained whenever valid. Legacy records are staged
## without mutating ownership; callers apply a complete successful plan.
static func plan(records: Array[InventoryItem], envelope: Vector3) -> Dictionary:
	var result := {}
	var occupied: Array[AABB] = []
	var pending: Array[InventoryItem] = []
	var space := PhysicsServer3D.space_create()
	PhysicsServer3D.space_set_active(space, true)
	var bodies: Array[RID] = []
	for record in records:
		var box := bounds(record, record.internal_pose)
		if record.packed and inside(box, envelope, 0.004) and exact_clear(record, record.internal_pose, space):
			result[record] = record.internal_pose
			occupied.append(box)
			bodies.append(add_query_body(record, record.internal_pose, space))
		else:
			pending.append(record)
	for record in pending:
		var pose: Variant = find_pose(record, envelope, occupied)
		if pose == null:
			for body in bodies:
				PhysicsServer3D.free_rid(body)
			PhysicsServer3D.free_rid(space)
			return {}
		result[record] = pose
		occupied.append(bounds(record, pose))
		bodies.append(add_query_body(record, pose, space))
	for body in bodies:
		PhysicsServer3D.free_rid(body)
	PhysicsServer3D.free_rid(space)
	return result

static func exact_clear(record: InventoryItem, pose: Transform3D, space: RID) -> bool:
	var state := PhysicsServer3D.space_get_direct_state(space)
	var scale_basis := Basis.from_scale(record.body.global_basis.get_scale().abs())
	for shape in record.body.get_children():
		if shape is CollisionShape3D and shape.shape != null and not shape.disabled:
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = shape.shape
			query.transform = pose * Transform3D(scale_basis, Vector3.ZERO) * shape.transform
			query.margin = -0.0005
			if not state.intersect_shape(query, 1).is_empty():
				return false
	return true

static func add_query_body(record: InventoryItem, pose: Transform3D, space: RID) -> RID:
	var body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_mode(body, PhysicsServer3D.BODY_MODE_STATIC)
	var scale_basis := Basis.from_scale(record.body.global_basis.get_scale().abs())
	for shape in record.body.get_children():
		if shape is CollisionShape3D and shape.shape != null and not shape.disabled:
			PhysicsServer3D.body_add_shape(body, shape.shape.get_rid(), Transform3D(scale_basis, Vector3.ZERO) * shape.transform)
	PhysicsServer3D.body_set_state(body, PhysicsServer3D.BODY_STATE_TRANSFORM, pose)
	PhysicsServer3D.body_set_space(body, space)
	return body

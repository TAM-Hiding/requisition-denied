class_name PlacementClearance
extends RefCounted
## Queries use the original collider and its local offset.
const MARGIN := 0.008

var collider: CollisionShape3D
var item: InteractableObject
var space: PhysicsDirectSpaceState3D
var radius: float

func configure(body: InteractableObject) -> bool:
	collider = body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collider == null or collider.disabled or collider.shape == null:
		return false
	if not (collider.shape is BoxShape3D or collider.shape is SphereShape3D
			or collider.shape is CapsuleShape3D or collider.shape is CylinderShape3D
			or collider.shape is ConvexPolygonShape3D):
		return false
	for owner in body.get_shape_owners():
		if not body.is_shape_owner_disabled(owner) and body.shape_owner_get_owner(owner) != collider:
			return false
	item = body
	space = body.get_world_3d().direct_space_state
	var bounds := collider.transform * collider.shape.get_debug_mesh().get_aabb()
	radius = bounds.position.abs().max(bounds.end.abs()).length()
	return true

func query(pose: Transform3D, mask: int, extra_margin: float = 0.0) -> PhysicsShapeQueryParameters3D:
	var parameters := PhysicsShapeQueryParameters3D.new()
	parameters.shape = collider.shape
	parameters.transform = pose * collider.transform
	parameters.collision_mask = mask
	parameters.exclude = [item.get_rid()]
	parameters.margin = MARGIN + extra_margin
	return parameters

func clear(pose: Transform3D, mask: int = 3, extra_margin: float = 0.0) -> bool:
	return space.intersect_shape(query(pose, mask, extra_margin), 1).is_empty()

func travel_fraction(pose: Transform3D, destination: Vector3, mask: int = 3) -> float:
	if not clear(pose, mask):
		return 0.0
	var motion := destination - pose.origin
	if motion.length_squared() < 0.00000001:
		return 1.0
	var parameters := query(pose, mask)
	parameters.motion = motion
	var safe := space.cast_motion(parameters)[0]
	return maxf(0.0, safe - 0.002 / motion.length()) if safe < 1.0 else 1.0

func rotation_clear(from: Transform3D, to: Transform3D, radians: float) -> bool:
	# Every point travels at most radius * angle over this increment.
	# Clearance at the start covers that arc, including thin obstacles.
	var scale := from.basis.get_scale().abs()
	var max_scale := maxf(scale.x, maxf(scale.y, scale.z))
	return clear(from, 3, radius * max_scale * absf(radians)) and clear(to)

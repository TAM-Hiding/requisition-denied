class_name WorldDropPlacement
extends RefCounted
## Inventory release searches a forward arc, then checks the full shape route.
## The held-item G drop keeps its existing aimed placement behavior.
var minimum_radius := 0.75
var maximum_radius := 1.70
var attempts := 48
var minimum_clearance := 0.025
var maximum_release_height := 0.24
var maximum_surface_drop := 2.0
var rng := RandomNumberGenerator.new()
var _reservation_frame := -1
var _reservations: Array[AABB] = []

func _init() -> void:
	rng.randomize()

func local_bounds(item: InteractableObject) -> AABB:
	var box := AABB()
	var initialized := false
	for child in item.get_children():
		if child is CollisionShape3D and child.shape != null and not child.disabled:
			var part: AABB = child.transform * child.shape.get_debug_mesh().get_aabb()
			box = box.merge(part) if initialized else part
			initialized = true
	return box

func refresh_reservations() -> void:
	var frame := Engine.get_physics_frames()
	if frame != _reservation_frame:
		_reservations.clear()
		_reservation_frame = frame

func remember(item: InteractableObject, pose: Transform3D) -> void:
	refresh_reservations()
	_reservations.append(pose * local_bounds(item))

func find_pose(actor: OtisController, item: InteractableObject, release_index := 0) -> Variant:
	var clearance := PlacementClearance.new()
	if not clearance.configure(item):
		return null
	refresh_reservations()
	var space := actor.get_world_3d().direct_space_state
	var forward := -actor.camera.global_basis.z
	forward.y = 0
	if forward.length_squared() < 0.001:
		forward = -actor.global_basis.z
	forward = forward.normalized()
	var right := forward.cross(Vector3.UP).normalized()
	var bounds := local_bounds(item)
	var scale := item.global_basis.get_scale().abs()
	for attempt in attempts:
		var angle := rng.randf_range(-PI * 0.49, PI * 0.49)
		var radius := rng.randf_range(minimum_radius, maximum_radius)
		var offset := (forward * cos(angle) + right * sin(angle)) * radius
		var ray_start := actor.global_position + offset
		ray_start.y = actor.camera.global_position.y + 0.45
		var ray_end := ray_start
		ray_end.y = actor.global_position.y - maximum_surface_drop
		var surface_query := PhysicsRayQueryParameters3D.create(ray_start, ray_end, 1 | 16)
		surface_query.exclude = [item.get_rid(), actor.get_rid()]
		var surface := space.intersect_ray(surface_query)
		if surface.is_empty() or surface.normal.y < 0.65 or surface.position.y > actor.camera.global_position.y - 0.15:
			continue
		var rotation := Basis.from_euler(Vector3(rng.randf_range(-0.07, 0.07),
			rng.randf_range(-PI, PI), rng.randf_range(-0.07, 0.07))) * Basis.from_scale(scale)
		var rotated: AABB = Transform3D(rotation, Vector3.ZERO) * bounds
		var candidate := Transform3D(rotation, surface.position)
		# Release just above the support. Additional bounded clearance lets a
		# batch form a pile without requiring a separate floor patch per item.
		var lift := rng.randf_range(minimum_clearance, 0.10)
		lift += minf(float(release_index) * 0.012, maximum_release_height - 0.10)
		candidate.origin.y -= rotated.position.y
		candidate.origin.y += lift
		if not clearance.clear(candidate, 3 | 16, 0.009):
			continue
		var world_box: AABB = candidate * bounds
		if _reservations.any(func(other: AABB) -> bool: return world_box.grow(0.006).intersects(other)):
			continue
		var start := Transform3D(rotation, actor.camera.global_position)
		var route_clear := true
		for shape in clearance.shapes:
			var query := clearance.query(start, 1 | 16, 0.0, shape)
			query.exclude.append(actor.get_rid())
			query.motion = candidate.origin - start.origin
			if not space.intersect_shape(query, 1).is_empty() or space.cast_motion(query)[0] < 1.0:
				route_clear = false
				break
		if route_clear:
			return candidate
	return null

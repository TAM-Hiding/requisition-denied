class_name LayoutWorkspace
extends Node3D
## Placement records use hall-local coordinates on marked horizontal supports.
const CONTACT_GAP := 0.006
const SUPPORT_EPSILON := 0.0001
const SUPPORT_NORMAL_MIN := 0.999
const SUPPORT_PROBE := 0.04
const SUPPORT_META := &"layout_support"
const ENTRY_CENTER := Vector2(0.0, 1.0)
const ENTRY_HALF_SIZE := Vector2(1.05, 1.0)
const STORAGE_APPROACHES := [
	[Vector2(-8.40, 2.75), Vector2(0.72, 0.60)],
	[Vector2(7.0, 23.65), Vector2(0.60, 0.72)],
]

var hall: Node3D
var actor: OtisController
var items: Dictionary[String, LayoutPlaceholder] = {}
var active_id := ""
var editing := false
var _random := Crypto.new()

func records() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item in items.values():
		result.append(item.get_meta("layout_record").duplicate(true))
	return result

func record(id: String) -> Dictionary:
	return items[id].get_meta("layout_record").duplicate(true) if items.has(id) else {}

func new_record(type: String) -> Dictionary:
	var spec := LayoutCatalog.definition(type)
	if spec.is_empty():
		return {}
	return {"id": _random.generate_random_bytes(16).hex_encode(), "type": type, "name": spec.name,
		"position": Vector3.ZERO, "yaw": 0.0, "size": spec.size, "properties": {}}

func select(id: String) -> void:
	if items.has(active_id):
		items[active_id].set_highlight(false)
	active_id = id if items.has(id) else ""
	if items.has(active_id):
		items[active_id].set_highlight(editing)

func set_editing(enabled: bool) -> void:
	editing = enabled
	for id in items:
		items[id].set_editing(enabled)
		items[id].set_highlight(enabled and id == active_id)

func upsert(candidate: Dictionary) -> String:
	var issue := validate_placement(candidate, records(), excluded_bodies())
	if not issue.is_empty():
		return issue
	remove(candidate.id)
	_add(candidate)
	select(candidate.id)
	return ""

func remove(id: String) -> void:
	if not items.has(id):
		return
	var item := items[id]
	items.erase(id)
	remove_child(item)
	item.queue_free()
	if active_id == id:
		active_id = ""

func replace_all(incoming: Array[Dictionary]) -> String:
	var accepted: Array[Dictionary] = []
	var ids := {}
	var exclude := excluded_bodies()
	for candidate in incoming:
		if ids.has(candidate.id):
			return "Duplicate equipment ID: %s." % candidate.id
		ids[candidate.id] = true
		var issue := validate_placement(candidate, accepted, exclude)
		if not issue.is_empty():
			return "%s: %s" % [candidate.name, issue]
		accepted.append(candidate)
	for id in items.keys():
		remove(id)
	for candidate in incoming:
		_add(candidate)
	return ""

func _add(candidate: Dictionary) -> void:
	var item := LayoutPlaceholder.new()
	item.name = "Equipment_" + candidate.id
	add_child(item)
	item.configure(candidate)
	item.set_meta("layout_record", candidate.duplicate(true))
	item.set_editing(editing)
	items[candidate.id] = item

func excluded_bodies() -> Array[RID]:
	var result: Array[RID] = []
	for item in items.values():
		for body in item.get_children():
			if body is StaticBody3D:
				result.append(body.get_rid())
	return result

func validate_placement(candidate: Dictionary, peers: Array[Dictionary], exclude: Array[RID]) -> String:
	var size: Vector3 = candidate.size
	var center: Vector3 = candidate.position
	var yaw: float = candidate.yaw
	var spec := LayoutCatalog.definition(candidate.type)
	if spec.is_empty() or not size.is_finite() or not center.is_finite() or not is_finite(yaw) \
			or center.y < 0.0 or minf(size.x, minf(size.y, size.z)) < 0.1 \
			or maxf(size.x, maxf(size.y, size.z)) > 40.0:
		return "Use finite dimensions from 0.10 to 40.00 m and a valid elevation."
	var basis := Basis(Vector3.UP, yaw)
	var occupied := occupied_box(candidate.type, size)
	var occupied_center := center + basis * occupied.get_center()
	var occupied_at := Vector2(occupied_center.x, occupied_center.z)
	var occupied_half := Vector2(occupied.size.x, occupied.size.z) * 0.5
	var axes := ground_axes(basis)
	var extents := axes[0].abs() * occupied_half.x + axes[1].abs() * occupied_half.y
	var half_width: float = hall.get("width") * 0.5
	var depth: float = hall.get("depth")
	if absf(occupied_at.x) + extents.x > half_width or occupied_at.y - extents.y < 0 or occupied_at.y + extents.y > depth:
		return "Footprint extends outside the hall."
	# Rack records retain the planning envelope. Only the physical footprint
	# needs support, so an inward-facing frame can sit against the wall.
	var support_center := Vector3(occupied_center.x, center.y, occupied_center.z)
	if not _footprint_supported(support_center, basis, occupied.size, exclude):
		return "Place the entire footprint on the hall floor or mezzanine."
	# Planning markers may overlap the future rooms, equipment and shell.
	if spec.marker:
		return ""

	var on_slab := center.y <= SUPPORT_EPSILON
	if on_slab and overlaps(occupied_at, occupied_half, axes, ENTRY_CENTER, ENTRY_HALF_SIZE, [Vector2.RIGHT, Vector2.DOWN]):
		return "Keep the personnel threshold clear."
	if on_slab:
		for approach: Array in STORAGE_APPROACHES:
			if overlaps(occupied_at, occupied_half, axes, approach[0], approach[1], [Vector2.RIGHT, Vector2.DOWN]):
				return "Keep the storage-cell doorway clear."
	var stair_top: float = depth - float(hall.get("deck_depth"))
	var stair_start: float = stair_top - float(hall.get("stair_run"))
	var stair_x: float = half_width - float(hall.get("stair_center_inset"))
	var landing := stair_start - 0.55 if on_slab else stair_top + 0.55
	if overlaps(occupied_at, occupied_half, axes, Vector2(stair_x, landing), Vector2(0.93, 0.55),
			[Vector2.RIGHT, Vector2.DOWN]):
		return "Keep the stair landing clear."

	var low := center.y + occupied.position.y
	var high := low + occupied.size.y
	for peer in peers:
		if peer.id == candidate.id or LayoutCatalog.definition(peer.type).marker:
			continue
		var peer_position: Vector3 = peer.position
		var peer_box := occupied_box(peer.type, peer.size)
		var peer_low := peer_position.y + peer_box.position.y
		if minf(high, peer_low + peer_box.size.y) <= maxf(low, peer_low) + CONTACT_GAP:
			continue
		var peer_basis := Basis(Vector3.UP, peer.yaw)
		var peer_center := peer_position + peer_basis * peer_box.get_center()
		if overlaps(occupied_at, occupied_half, axes, Vector2(peer_center.x, peer_center.z),
				Vector2(peer_box.size.x, peer_box.size.z) * 0.5, ground_axes(peer_basis)):
			return "Footprint overlaps %s." % peer.name
	var shape := BoxShape3D.new()
	shape.size = occupied.size - Vector3.ONE * 2.0 * CONTACT_GAP
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = hall.global_transform * Transform3D(basis, occupied_center)
	query.collision_mask = 1 | 2 | 16
	query.exclude = exclude
	if not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
		return "Blocked by the hall, Otis, or a world object."
	return ""

static func occupied_box(type: String, dimensions: Vector3) -> AABB:
	var normalized := LayoutCatalog.occupied_box(type)
	return AABB(normalized.position * dimensions, normalized.size * dimensions)

func has_support_near(point: Vector3) -> bool:
	return _valid_support(_sample_support(point, 0.15, []))

func _footprint_supported(center: Vector3, basis: Basis, dimensions: Vector3, exclude: Array[RID]) -> bool:
	var support := _sample_support(center, SUPPORT_PROBE, exclude)
	if not _valid_support(support) or absf(hall.to_local(support.position).y - center.y) > SUPPORT_EPSILON:
		return false
	for corner: Vector3 in [Vector3(-1, 0, -1), Vector3(-1, 0, 1), Vector3(1, 0, -1), Vector3(1, 0, 1)]:
		var point := center + basis * (dimensions * corner * 0.5)
		var sample := _sample_support(point, SUPPORT_PROBE, exclude)
		# Slab and deck are continuous convex boxes. All four corners on one
		# support guarantee the oriented rectangle is fully supported.
		if not _valid_support(sample) or sample.collider != support.collider \
				or absf(hall.to_local(sample.position).y - center.y) > SUPPORT_EPSILON:
			return false
	return true

func _sample_support(point: Vector3, distance: float, exclude: Array[RID]) -> Dictionary:
	var ray := PhysicsRayQueryParameters3D.create(hall.to_global(point + Vector3.UP * distance),
		hall.to_global(point - Vector3.UP * distance), 1 | 16, exclude)
	return get_world_3d().direct_space_state.intersect_ray(ray)

func _valid_support(hit: Dictionary) -> bool:
	return not hit.is_empty() and hit.collider is StaticBody3D and hit.collider.get_meta(SUPPORT_META, false) == true \
		and hall.global_basis.y.normalized().dot(hit.normal) >= SUPPORT_NORMAL_MIN

static func ground_axes(basis: Basis) -> Array[Vector2]:
	return [Vector2(basis.x.x, basis.x.z), Vector2(basis.z.x, basis.z.z)]

static func overlaps(a: Vector2, a_half: Vector2, a_axes: Array, b: Vector2, b_half: Vector2, b_axes: Array) -> bool:
	var offset := b - a
	for axis: Vector2 in a_axes + b_axes:
		var a_radius := absf(axis.dot(a_axes[0])) * a_half.x + absf(axis.dot(a_axes[1])) * a_half.y
		var b_radius := absf(axis.dot(b_axes[0])) * b_half.x + absf(axis.dot(b_axes[1])) * b_half.y
		if absf(offset.dot(axis)) >= a_radius + b_radius - CONTACT_GAP:
			return false
	return true

func cursor_pick(camera: Camera3D) -> String:
	var origin := camera.global_position
	var direction := -camera.global_basis.z
	var ray := PhysicsRayQueryParameters3D.create(origin, origin + direction * 22.0, 1, [actor.get_rid()])
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	var closest := 22.0
	var picked := ""
	if not hit.is_empty():
		closest = origin.distance_to(hit.position)
		if hit.collider.get_parent() is LayoutPlaceholder:
			picked = hit.collider.get_parent().get_meta("layout_record").id
	for id in items:
		var item := items[id]
		var value: Dictionary = item.get_meta("layout_record")
		if not LayoutCatalog.definition(value.type).marker:
			continue
		var size: Vector3 = value.size
		if value.type == "storage_room_marker":
			size.y = minf(size.y, 0.06)
		var bounds := AABB(Vector3(-size.x / 2, 0.0, -size.z / 2), size)
		var local_direction := item.global_basis.inverse() * direction
		var marker_hit: Variant = bounds.intersects_ray(item.to_local(origin), local_direction)
		if marker_hit is Vector3:
			var distance := origin.distance_to(item.to_global(marker_hit))
			if distance < closest:
				closest = distance
				picked = id
	return picked

func cursor_floor(camera: Camera3D) -> Variant:
	var direction := -camera.global_basis.z
	if hall.global_basis.y.normalized().dot(direction) >= -0.001:
		return null
	var start := camera.global_position
	var ray := PhysicsRayQueryParameters3D.create(start, start + direction * 22.0, 1 | 16, excluded_bodies())
	var hit := get_world_3d().direct_space_state.intersect_ray(ray)
	if not _valid_support(hit):
		return null
	var point := hall.to_local(hit.position)
	# Remove ray intersection noise from new placements without changing any
	# saved coordinates on import. The support plane itself is unchanged.
	point.y = snappedf(point.y, SUPPORT_EPSILON)
	return point

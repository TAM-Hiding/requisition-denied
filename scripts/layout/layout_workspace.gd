class_name LayoutWorkspace
extends Node3D
## Ground-floor planning records live in hall-local coordinates.
const CONTACT_GAP := 0.006
const ENTRY_CENTER := Vector2(0.0, 1.0)
const ENTRY_HALF_SIZE := Vector2(1.05, 1.0)

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
	var exclude := excluded_bodies()
	for candidate in incoming:
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
			or center.y != 0.0 or minf(size.x, minf(size.y, size.z)) < 0.1 \
			or maxf(size.x, maxf(size.y, size.z)) > 40.0:
		return "Use finite dimensions from 0.10 to 40.00 m on the hall floor."
	var basis := Basis(Vector3.UP, yaw)
	var footprint := Vector2(size.x, size.z) * 0.5
	var at := Vector2(center.x, center.z)
	var axes := ground_axes(basis)
	var extents := axes[0].abs() * footprint.x + axes[1].abs() * footprint.y
	var half_width: float = hall.get("width") * 0.5
	var depth: float = hall.get("depth")
	if absf(at.x) + extents.x > half_width or at.y - extents.y < 0 or at.y + extents.y > depth:
		return "Footprint extends outside the hall."
	# Planning markers may overlap the future rooms, equipment and shell.
	if spec.marker:
		return ""
	if overlaps(at, footprint, axes, ENTRY_CENTER, ENTRY_HALF_SIZE, [Vector2.RIGHT, Vector2.DOWN]):
		return "Keep the personnel threshold clear."
	var stair_top: float = depth - float(hall.get("deck_depth"))
	var stair_start: float = stair_top - float(hall.get("stair_run"))
	var stair_x: float = half_width - float(hall.get("stair_center_inset"))
	if overlaps(at, footprint, axes, Vector2(stair_x, stair_start - 0.55), Vector2(0.93, 0.55),
			[Vector2.RIGHT, Vector2.DOWN]):
		return "Keep the foot of the stair clear."
	for peer in peers:
		if peer.id == candidate.id or LayoutCatalog.definition(peer.type).marker:
			continue
		var peer_size: Vector3 = peer.size
		var peer_position: Vector3 = peer.position
		if overlaps(at, footprint, axes, Vector2(peer_position.x, peer_position.z),
				Vector2(peer_size.x, peer_size.z) * 0.5, ground_axes(Basis(Vector3.UP, peer.yaw))):
			return "Footprint overlaps %s." % peer.name
	var shape := BoxShape3D.new()
	shape.size = size - Vector3.ONE * 2.0 * CONTACT_GAP
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.transform = hall.global_transform * Transform3D(basis, center + Vector3.UP * size.y / 2)
	query.collision_mask = 1 | 2 | 16
	query.exclude = exclude
	if not get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty():
		return "Blocked by the hall, Otis, or a world object."
	return ""

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
	var eye := hall.to_local(camera.global_position)
	var direction := hall.global_basis.inverse() * -camera.global_basis.z
	var floor_distance := -eye.y / direction.y if direction.y < -0.001 else INF
	if floor_distance < 0.0 or floor_distance > 22.0:
		return null
	var point := eye + direction * floor_distance
	var start := camera.global_position
	var ray := PhysicsRayQueryParameters3D.create(start, hall.to_global(point + Vector3.UP * 0.015), 1,
		excluded_bodies())
	if not get_world_3d().direct_space_state.intersect_ray(ray).is_empty():
		return null
	point.y = 0.0
	return point

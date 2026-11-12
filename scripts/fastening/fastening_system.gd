class_name FasteningSystem
extends Node3D
## The logical graph owns fastener records. Each connected island has one
## simulated collider and no internal physics joints.
const REACH := 0.1524
const MAX_GAP := 0.025
const PROBE_LAYER := 8
var connections: Array[FastenerConnection] = []
var failed: Array[InstalledFastener] = []
var last_failed_group := 0
var last_load := 0.0
var _next_bolt := 1
var _next_group := 1
var _roots := {}
var _followers := {}
var _root_masses := {}
var _copies: Array[CollisionShape3D] = []
var _proxies: Array[StaticBody3D] = []

func create_round(grade: FastenerGrade) -> InstalledFastener:
	var bolt := InstalledFastener.new()
	bolt.id = _next_bolt
	bolt.grade = grade
	_next_bolt += 1
	return bolt

func compatible(body: PhysicsBody3D, actor: PhysicsBody3D = null) -> bool:
	if body is InteractableObject:
		return (body.state == InteractableObject.State.WORLD
			or (actor is OtisController and body.state == InteractableObject.State.CARRIED and body.support_carrier == actor)) 			and not body is FasteningTool \
			and (not body is MechanicalComponent or not is_instance_valid(body.seating_mount))
	return body is StaticBody3D and not body.has_meta(&"no_fasteners")

func anchored(body: PhysicsBody3D) -> bool:
	return body is StaticBody3D or (body is InteractableObject and body.mobility() == ObjectDefinition.Mobility.FIXED)

func cast(from: Vector3, to: Vector3, exclusions: Array[RID] = [], inside := false) -> Dictionary:
	var params := PhysicsRayQueryParameters3D.create(from, to, 1 | PROBE_LAYER, exclusions)
	params.hit_from_inside = inside
	return get_world_3d().direct_space_state.intersect_ray(params)

func probe(origin: Vector3, direction: Vector3, reach: float, actor: PhysicsBody3D = null) -> Dictionary:
	if not origin.is_finite() or not direction.is_finite() or direction.is_zero_approx() or not is_finite(reach) or reach <= 0.0:
		return {"issue": "NO TARGET SURFACE"}
	var exclude: Array[RID] = []
	if actor != null:
		exclude.append(actor.get_rid())
	for root in _roots.values():
		var rid: RID = root.get_rid()
		if not exclude.has(rid):
			exclude.append(rid)
	var forward := direction.normalized()
	var hit := cast(origin, origin + forward * reach, exclude)
	if hit.is_empty():
		return {"issue": "NO TARGET SURFACE"}
	var first := hit.collider as PhysicsBody3D
	var a := logical_body(first)
	var result := {"issue": "INVALID SURFACE", "a": a, "point": hit.position, "normal": hit.normal}
	if not is_instance_valid(a) or not compatible(a, actor) or hit.normal.dot(-forward) < 0.5:
		return result
	# The normal sets the drilling direction. Use the exit face and second hit
	# to enforce both usable length and proximity between the workpieces.
	var inward: Vector3 = -hit.normal
	exclude.append(first.get_rid())
	var entry: Vector3 = hit.position
	var backing := cast(entry + inward * 0.0005, entry + inward * 2.0, exclude, true)
	if backing.is_empty():
		result.issue = "NO SECONDARY MATERIAL"
		return result
	var b := logical_body(backing.collider)
	result.b = b
	result.depth = entry.distance_to(backing.position)
	if not is_instance_valid(b) or b == a or not compatible(b, actor):
		result.issue = "FASTENER OBSTRUCTED"
		return result
	if anchored(a) and anchored(b):
		result.issue = "INVALID SURFACE · BOTH BODIES FIXED"
		return result
	if result.depth < 0.002:
		result.issue = "FASTENER OBSTRUCTED"
		return result
	if result.depth > REACH - 0.006:
		result.issue = "FASTENER TOO SHORT"
		return result
	# Backcast with only the primary included. An inside hit also permits
	# slightly overlapping workpieces at their collision margins.
	var reverse_exclude := exclude.duplicate()
	reverse_exclude.erase(first.get_rid())
	reverse_exclude.append(backing.rid)
	var exit := cast(backing.position, entry - inward * 0.005, reverse_exclude, true)
	if exit.is_empty() or exit.rid != first.get_rid() or exit.position.distance_to(backing.position) > MAX_GAP:
		result.issue = "NO SECONDARY MATERIAL IN CONTACT"
		return result
	result.backing = backing.position
	if connections.any(func(group: FastenerConnection) -> bool:
		return group.bolts.any(func(bolt: InstalledFastener) -> bool:
			return bolt.head().distance_to(entry) < 0.025)):
		result.issue = "FASTENER OBSTRUCTED"
		return result
	result.issue = ""
	return result

static func logical_body(body: PhysicsBody3D, shape_index := -1) -> PhysicsBody3D:
	if not is_instance_valid(body):
		return null
	if body.has_meta(&"fastener_body"):
		return body.get_meta(&"fastener_body")
	if shape_index >= 0:
		var shape := body.shape_owner_get_owner(body.shape_find_owner(shape_index))
		if is_instance_valid(shape) and shape.has_meta(&"fastener_body"):
			return shape.get_meta(&"fastener_body")
	return body

func install(bolt: InstalledFastener, origin: Vector3, direction: Vector3, reach: float, actor: PhysicsBody3D = null) -> String:
	if (bolt == null or bolt.state != InstalledFastener.State.RECOVERED or bolt.grade == null
			or not is_finite(bolt.grade.strength) or bolt.grade.strength <= 0.0):
		return "INVALID FASTENER"
	var target := probe(origin, direction, reach, actor)
	if not target.issue.is_empty():
		return target.issue
	var a: PhysicsBody3D = target.a
	var b: PhysicsBody3D = target.b
	for body in [a, b]:
		if body is InteractableObject and body.state == InteractableObject.State.CARRIED:
			if not actor is OtisController or not actor.placement.handoff_workpiece(body):
				return "WORKPIECE NEEDS CLEARANCE"
	var group := between(a, b)
	var new_connection := group == null
	if new_connection:
		group = FastenerConnection.new()
		group.a = a
		group.b = b
		group.id = _next_group
		_next_group += 1
		connections.append(group)
	bolt.a = a
	bolt.b = b
	bolt.local_a = a.to_local(target.point)
	bolt.local_b = b.to_local(target.backing)
	var normal: Vector3 = target.normal
	var up := Vector3.RIGHT if absf(normal.dot(Vector3.UP)) > 0.95 else Vector3.UP
	bolt.local_orientation = a.global_basis.inverse() * Basis.looking_at(-normal, up)
	bolt.state = InstalledFastener.State.INSTALLED
	bolt.load_estimate = 0.0
	group.bolts.append(bolt)
	make_bolt_visual(bolt)
	if new_connection:
		rebuild()
	return ""

func between(a: PhysicsBody3D, b: PhysicsBody3D) -> FastenerConnection:
	for group in connections:
		if (group.a == a and group.b == b) or (group.a == b and group.b == a):
			return group
	return null

func target_bolt(origin: Vector3, direction: Vector3, reach: float, actor: PhysicsBody3D = null) -> InstalledFastener:
	var exclude: Array[RID] = []
	if actor != null:
		exclude.append(actor.get_rid())
	var dir := direction.normalized()
	var wall := cast(origin, origin + dir * reach, exclude)
	var limit: float = reach if wall.is_empty() else minf(reach, origin.distance_to(wall.position) + 0.004)
	var nearest: InstalledFastener
	for group in connections:
		for bolt in group.bolts:
			var normal := (bolt.a.global_basis * bolt.local_orientation.z).normalized()
			var offset := bolt.head() + normal * 0.008 - origin
			var depth := offset.dot(dir)
			if depth > 0.0 and depth < limit and (offset - dir * depth).length() < 0.014:
				limit = depth
				nearest = bolt
	return nearest

func remove(bolt: InstalledFastener) -> bool:
	if bolt == null or bolt.state != InstalledFastener.State.INSTALLED:
		return false
	var group := between(bolt.a, bolt.b)
	if group == null or not group.bolts.has(bolt):
		return false
	unlink(group, bolt, false)
	bolt.a = null
	bolt.b = null
	if group.bolts.is_empty():
		rebuild()
	return true

func unlink(group: FastenerConnection, bolt: InstalledFastener, broken: bool) -> void:
	group.bolts.erase(bolt)
	bolt.state = InstalledFastener.State.FAILED if broken else InstalledFastener.State.RECOVERED
	if broken:
		failed.append(bolt)
		last_failed_group = group.id
		# A short, dull remnant marks the failure location.
		if is_instance_valid(bolt.visual):
			bolt.visual.scale.z = 0.35
	else:
		bolt.visual.hide()
		bolt.visual.queue_free()
		bolt.visual = null
	if group.bolts.is_empty():
		connections.erase(group)

func physics_root(body: PhysicsBody3D) -> PhysicsBody3D:
	return _roots.get(body, body)

func incident(body: PhysicsBody3D) -> Array[FastenerConnection]:
	return connections.filter(func(edge: FastenerConnection) -> bool: return edge.a == body or edge.b == body)

func route(body: PhysicsBody3D) -> Array[FastenerConnection]:
	# Prefer the shortest route to a fixed support. On a free island, the
	# neighboring bodies provide the approximate inertial reaction.
	var queue: Array[PhysicsBody3D] = [body]
	var paths := {body: []}
	while not queue.is_empty():
		var current: PhysicsBody3D = queue.pop_front()
		if current != body and anchored(current):
			var path: Array[FastenerConnection] = []
			path.assign(paths[current])
			return path
		for group in incident(current):
			var next := group.other(current)
			if not paths.has(next):
				paths[next] = paths[current] + [group]
				queue.append(next)
	return incident(body)

func apply_structural_load(body: PhysicsBody3D, point: Vector3, force: Vector3) -> void:
	if not is_instance_valid(body) or not point.is_finite() or not force.is_finite():
		return
	last_load = force.length()
	var changed := false
	var processed: Array[FastenerConnection] = []
	# Re-route after a complete break, without loading unrelated branches of
	# a now-separated island. Each bolt can fail at most once per call.
	var path := route(body)
	while not path.is_empty():
		var group: FastenerConnection = path.pop_front()
		if processed.has(group):
			continue
		processed.append(group)
		while not group.bolts.is_empty():
			group.estimate(point, force)
			var weakest: InstalledFastener
			var worst_ratio := 1.0
			for bolt in group.bolts:
				var ratio := bolt.load_estimate / bolt.grade.strength
				if ratio > worst_ratio:
					weakest = bolt
					worst_ratio = ratio
			if weakest == null:
				break
			unlink(group, weakest, true)
		if group.bolts.is_empty():
			changed = true
			path = route(body)
	if changed:
		rebuild()

func installed_count() -> int:
	var count := 0
	for group in connections:
		count += group.bolts.size()
	return count

func make_bolt_visual(bolt: InstalledFastener) -> void:
	var visual := Node3D.new()
	bolt.a.add_child(visual)
	visual.transform = Transform3D(bolt.local_orientation, bolt.local_a)
	bolt.visual = visual
	make_cylinder(visual, 0.010, 0.005, 0.0035, 6, bolt.grade.finish)
	make_cylinder(visual, 0.008, 0.002, 0.007, 6, bolt.grade.finish, 0.010)
	var ring := MeshInstance3D.new()
	var mesh := TorusMesh.new()
	mesh.inner_radius = 0.0058
	mesh.outer_radius = 0.0074
	mesh.rings = 12
	mesh.ring_segments = 5
	ring.mesh = mesh
	ring.material_override = bolt.grade.accent
	ring.rotation.x = PI * 0.5
	ring.position.z = 0.008
	visual.add_child(ring)
	make_cylinder(visual, 0.00635, REACH - 0.006, -0.073, 8, bolt.grade.finish)
	make_cylinder(visual, 0.004, 0.006, -0.149, 8, bolt.grade.finish, 0.0)

func make_cylinder(parent: Node3D, radius: float, length: float, z: float, sides: int,
		material: Material, bottom := -1.0) -> void:
	var instance := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius if bottom < 0.0 else bottom
	mesh.height = length
	mesh.radial_segments = sides
	mesh.rings = 0
	instance.mesh = mesh
	instance.material_override = material
	instance.rotation.x = PI * 0.5
	instance.position.z = z
	parent.add_child(instance)

func rebuild() -> void:
	var velocities := {}
	for body in _roots:
		var old: PhysicsBody3D = _roots[body]
		if is_instance_valid(body) and is_instance_valid(old) and old is RigidBody3D:
			velocities[body] = [old.linear_velocity + old.angular_velocity.cross(body.global_position - old.global_position),
				old.angular_velocity]
	for collider in _copies:
		if is_instance_valid(collider):
			collider.get_parent().remove_child(collider)
			collider.queue_free()
	for proxy in _proxies:
		if is_instance_valid(proxy):
			proxy.get_parent().remove_child(proxy)
			proxy.queue_free()
	for body in _followers:
		if not is_instance_valid(body):
			continue
		var saved: Dictionary = _followers[body]
		var parent: Node = saved.parent if is_instance_valid(saved.parent) else get_parent()
		body.reparent(parent)
		body.collision_layer = saved.layer
		body.collision_mask = saved.mask
		body.freeze = saved.frozen
		body.sleeping = false
		if velocities.has(body):
			body.linear_velocity = velocities[body][0]
			body.angular_velocity = velocities[body][1]
	for body in _root_masses:
		if is_instance_valid(body):
			body.mass = _root_masses[body]
	for body in _roots:
		if is_instance_valid(body) and body is InteractableObject:
			body.fastened = false
	_followers.clear()
	_root_masses.clear()
	_roots.clear()
	_copies.clear()
	_proxies.clear()
	for edge in connections:
		if _roots.has(edge.a):
			continue
		var island: Array[PhysicsBody3D] = [edge.a]
		var index := 0
		while index < island.size():
			var member := island[index]
			for link in incident(member):
				var next := link.other(member)
				if not island.has(next):
					island.append(next)
			index += 1
		build_island(island)

func build_island(island: Array[PhysicsBody3D]) -> void:
	var root := island[0]
	for member in island:
		if anchored(member) and not anchored(root):
			root = member
		elif member is RigidBody3D and root is RigidBody3D and not anchored(root) and member.mass > root.mass:
			root = member
	if root is RigidBody3D and not anchored(root):
		_root_masses[root] = root.mass
	for member in island:
		_roots[member] = root
		if member is InteractableObject:
			member.fastened = true
	# Keep isolated query shapes to resolve material layers after compounding.
	make_probe(root)
	for member in island:
		if member == root or anchored(member):
			continue
		make_probe(member)
		_followers[member] = {"parent": member.get_parent(), "layer": member.collision_layer,
			"mask": member.collision_mask, "frozen": member.freeze}
		for shape_node in active_shapes(member):
			var copy := copy_shape(root, shape_node)
			copy.set_meta(&"fastener_body", member)
			_copies.append(copy)
		member.freeze = true
		member.collision_layer = 0
		member.collision_mask = 0
		member.reparent(root)
		if _root_masses.has(root):
			root.mass += member.mass

func active_shapes(body: PhysicsBody3D) -> Array[CollisionShape3D]:
	var shapes: Array[CollisionShape3D] = []
	for child in body.get_children():
		if child is CollisionShape3D and not child.disabled and child.shape != null:
			shapes.append(child)
	return shapes

func make_probe(body: PhysicsBody3D) -> void:
	var proxy := StaticBody3D.new()
	proxy.collision_layer = PROBE_LAYER
	proxy.collision_mask = 0
	proxy.set_meta(&"fastener_body", body)
	body.add_child(proxy)
	for source in active_shapes(body):
		copy_shape(proxy, source)
	_proxies.append(proxy)

func copy_shape(parent: PhysicsBody3D, source: CollisionShape3D) -> CollisionShape3D:
	var collider := CollisionShape3D.new()
	collider.shape = source.shape
	parent.add_child(collider)
	collider.global_transform = source.global_transform
	return collider

func diagnostics(aim: Dictionary) -> String:
	var a := aim.get("a") as PhysicsBody3D
	var b := aim.get("b") as PhysicsBody3D
	var group := between(a, b) if is_instance_valid(a) and is_instance_valid(b) else null
	var strengths := PackedStringArray()
	if group != null:
		for bolt in group.bolts:
			strengths.append("#%d %.0f/%.0f" % [bolt.id, bolt.load_estimate, bolt.grade.strength])
	var broken := PackedStringArray()
	for bolt in failed.slice(maxi(0, failed.size() - 6)):
		broken.append(str(bolt.id))
	return "\nFASTENER SURFACE %s → %s · DEPTH %.3f m\nCONNECTION %s · ACTIVE %d · LAST LOAD %.0f\nBOLTS %s · FAILED %s" % [
		a.name if is_instance_valid(a) else "—", b.name if is_instance_valid(b) else "—", aim.get("depth", 0.0),
		"#%d FIXED" % group.id if group != null else "—", installed_count(), last_load,
		", ".join(strengths), ", ".join(broken)]

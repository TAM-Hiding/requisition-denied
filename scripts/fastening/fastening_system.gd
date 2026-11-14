class_name FasteningSystem
extends Node3D

signal bolt_failed(bolt: InstalledFastener)
## The logical graph owns fastener records. Each connected island has one
## simulated collider and no internal physics joints.
const REACH := 0.1524
const EXPOSED_TIP := 0.010
const TIP_LENGTH := 0.006
const SHEARED_LENGTH := 0.015
const HEAD_FACE_OFFSET := 0.008
const MAX_GAP := 0.025
const PROBE_LAYER := 8
var connections: Array[FastenerConnection] = []
var failed: Array[InstalledFastener] = []
var last_failed_group := 0
var last_load := 0.0
var load_debug := false
var topology_revision := 0
var visual_scale := 1.0
var _next_bolt := 1
var _issued := {}
var _installed := {}
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
	_issued[bolt.id] = weakref(bolt)
	return bolt

func compatible(body: PhysicsBody3D, actor: PhysicsBody3D = null) -> bool:
	if not usable_body(body) or body.has_meta(&"no_fasteners"):
		return false
	if body is InteractableObject:
		var controlled: bool = actor is OtisController and body.state == InteractableObject.State.CARRIED \
			and body.support_carrier == actor
		return (body.state == InteractableObject.State.WORLD or controlled) and not body is FasteningTool \
			and (not body is MechanicalComponent or not is_instance_valid(body.seating_mount))
	return body is StaticBody3D

func usable_body(body: Variant) -> bool:
	return is_instance_valid(body) and body.is_inside_tree() and not body.is_queued_for_deletion()

func valid_round(bolt: InstalledFastener) -> bool:
	return bolt != null and _issued.has(bolt.id) and _issued[bolt.id].get_ref() == bolt \
		and bolt.grade != null and is_finite(bolt.grade.strength) and bolt.grade.strength > 0.0

func anchored(body: PhysicsBody3D) -> bool:
	return body is StaticBody3D or (body is InteractableObject and body.mobility() == ObjectDefinition.Mobility.FIXED)

func cast(from: Vector3, to: Vector3, exclusions: Array[RID] = [], inside := false,
		mask := 1 | PROBE_LAYER) -> Dictionary:
	var params := PhysicsRayQueryParameters3D.create(from, to, mask, exclusions)
	params.hit_from_inside = inside
	return get_world_3d().direct_space_state.intersect_ray(params)

func probe(origin: Vector3, direction: Vector3, reach: float, actor: PhysicsBody3D = null) -> Dictionary:
	if not origin.is_finite() or not direction.is_finite() or direction.is_zero_approx() or not is_finite(reach) or reach <= 0.0:
		return {"issue": "NO TARGET SURFACE"}
	sync_probes()
	var workpiece: InteractableObject = null
	if actor is OtisController:
		workpiece = actor.placement.fastening_workpiece()
		if is_instance_valid(workpiece):
			if workpiece.state != InteractableObject.State.CARRIED or workpiece.support_carrier != actor \
					or (workpiece.collision_layer & 1) == 0:
				return {"issue": "HELD WORKPIECE UNAVAILABLE"}
			# A carried rigid body is frozen, but precision placement can write
			# its pose before Godot flushes the transform to Jolt.
			sync_body_transform(workpiece)
	var exclude: Array[RID] = []
	if actor != null:
		exclude.append(actor.get_rid())
	for root in _roots.values():
		if not usable_body(root):
			continue
		var rid: RID = root.get_rid()
		if not exclude.has(rid):
			exclude.append(rid)
	var forward := direction.normalized()
	var hit := cast(origin, origin + forward * reach, exclude)
	if hit.is_empty():
		return {"issue": "NO PRIMARY SURFACE · AIM AT WORKPIECE"} if workpiece != null else {"issue": "NO TARGET SURFACE"}
	var first := hit.collider as PhysicsBody3D
	var a := logical_body(first)
	var result := {"issue": "INVALID SURFACE", "a": a, "point": hit.position, "normal": hit.normal}
	if not is_instance_valid(a) or not compatible(a, actor):
		return result
	if hit.normal.dot(-forward) < 0.5:
		result.issue = "INVALID APPROACH DIRECTION"
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
	result.backing_rid = backing.rid
	for body in [a, b]:
		if body is InteractableObject and body.state == InteractableObject.State.CARRIED:
			if not actor is OtisController or not actor.placement.can_handoff_workpiece(body):
				result.issue = "WORKPIECE NEEDS CLEARANCE"
				return result
	if connections.any(func(group: FastenerConnection) -> bool:
		return group.bolts.any(func(bolt: InstalledFastener) -> bool:
			return record_matches(group, bolt) and usable_body(bolt.a) and bolt.head().distance_to(entry) < 0.025)):
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
	reconcile()
	if not valid_round(bolt) or bolt.state != InstalledFastener.State.RECOVERED or bolt.group_id != 0:
		return "INVALID FASTENER"
	var target := probe(origin, direction, reach, actor)
	if not target.issue.is_empty():
		return target.issue
	var a: PhysicsBody3D = target.a
	var b: PhysicsBody3D = target.b
	var workpiece: InteractableObject = null
	for body in [a, b]:
		if active_shapes(body).is_empty():
			return "INVALID SURFACE"
		if body is InteractableObject and body.state == InteractableObject.State.CARRIED:
			if (workpiece != null or not actor is OtisController
					or not actor.placement.can_handoff_workpiece(body)):
				return "WORKPIECE NEEDS CLEARANCE"
			workpiece = body
	var local_a := a.to_local(target.point)
	var local_b := b.to_local(target.backing)
	var normal: Vector3 = target.normal
	var up := Vector3.RIGHT if absf(normal.dot(Vector3.UP)) > 0.95 else Vector3.UP
	var orientation := a.global_basis.inverse() * Basis.looking_at(-normal, up)
	if not local_a.is_finite() or not local_b.is_finite() or not orientation.is_finite():
		return "INVALID SURFACE"

	# Stage the visual before ownership changes. A rejected handoff has no
	# effect on the magazine, the original grab or the connection graph.
	var display_length := estimate_visual_length(target)
	var visual := make_bolt_visual(bolt, display_length)
	if workpiece != null and not actor.placement.handoff_workpiece(workpiece):
		visual.free()
		return "WORKPIECE NEEDS CLEARANCE"
	var group := between(a, b)
	var new_connection := group == null
	if new_connection:
		group = FastenerConnection.new()
		group.a = a
		group.b = b
		group.id = _next_group
		group.created_revision = topology_revision + 1
		_next_group += 1
	bolt.a = a
	bolt.b = b
	bolt.local_a = local_a
	bolt.local_b = local_b
	bolt.local_orientation = orientation
	bolt.group_id = group.id
	bolt.state = InstalledFastener.State.INSTALLED
	bolt.load_estimate = 0.0
	bolt.visual_length = display_length
	attach_visual(bolt, visual)
	_installed[bolt.id] = bolt
	group.bolts.append(bolt)
	if new_connection:
		connections.append(group)
		rebuild()
	return ""

func attach_visual(bolt: InstalledFastener, visual: Node3D) -> void:
	bolt.a.add_child(visual)
	bolt.visual = visual
	update_bolt_visual(bolt)

func record_matches(group: FastenerConnection, bolt: InstalledFastener) -> bool:
	return valid_round(bolt) and _installed.get(bolt.id) == bolt \
		and bolt.state == InstalledFastener.State.INSTALLED and bolt.group_id == group.id \
		and ((bolt.a == group.a and bolt.b == group.b) or (bolt.a == group.b and bolt.b == group.a)) \
		and bolt.local_a.is_finite() and bolt.local_b.is_finite() and bolt.local_orientation.is_finite()

func reconcile() -> void:
	var topology_changed := false
	var members := {}
	for group: FastenerConnection in connections.duplicate():
		var endpoints_valid := usable_body(group.a) and usable_body(group.b) and group.a != group.b
		var retained: Array[InstalledFastener] = []
		for bolt in group.bolts:
			if not endpoints_valid or not record_matches(group, bolt) or members.has(bolt.id):
				continue
			members[bolt.id] = true
			retained.append(bolt)
			if not is_instance_valid(bolt.visual) or bolt.visual.is_queued_for_deletion() or bolt.visual.get_parent() != bolt.a:
				discard_visual(bolt)
				attach_visual(bolt, make_bolt_visual(bolt))
			update_bolt_visual(bolt)
			bolt.visual.show()
		if retained.size() != group.bolts.size():
			group.bolts.assign(retained)
		if group.bolts.is_empty():
			connections.erase(group)
			topology_changed = true
	for id in _installed.keys():
		if members.has(id):
			continue
		var bolt: InstalledFastener = _installed[id]
		discard_visual(bolt)
		bolt.group_id = 0
		bolt.a = null
		bolt.b = null
		bolt.state = InstalledFastener.State.INVALIDATED
		_installed.erase(id)
	if topology_changed:
		rebuild()

func _physics_process(_delta: float) -> void:
	reconcile()

func sync_probes() -> void:
	for proxy in _proxies:
		if usable_body(proxy):
			var source := proxy.get_parent() as PhysicsBody3D
			if source != null and physics_root(source) == source and (not source is RigidBody3D or source.freeze):
				sync_body_transform(source)
			sync_body_transform(proxy)

func sync_body_transform(body: PhysicsBody3D) -> void:
	body.force_update_transform()
	var rid := body.get_rid()
	var current: Transform3D = PhysicsServer3D.body_get_state(rid, PhysicsServer3D.BODY_STATE_TRANSFORM)
	if not current.is_equal_approx(body.global_transform):
		PhysicsServer3D.body_set_state(rid, PhysicsServer3D.BODY_STATE_TRANSFORM, body.global_transform)

func set_visual_scale_percent(percent: int) -> void:
	visual_scale = clampi(percent, 75, 250) / 100.0
	for bolt: InstalledFastener in _installed.values():
		update_bolt_visual(bolt)
	for bolt in failed:
		update_bolt_visual(bolt)

## The backwards probe is presentation-only. A missing or ambiguous far
## face leaves a short shaft embedded near the entry into the backing.
func estimate_visual_length(target: Dictionary) -> float:
	var start: Vector3 = target.point
	var normal: Vector3 = target.normal
	var fallback := minf(REACH, float(target.depth) + EXPOSED_TIP)
	var far := cast(start - normal * (REACH + 0.002), target.backing, [], true)
	if far.is_empty() or far.rid != target.backing_rid or far.normal.dot(-normal) < 0.5:
		return fallback
	return clampf(start.distance_to(far.position) + EXPOSED_TIP, fallback, REACH)

func update_bolt_visual(bolt: InstalledFastener) -> void:
	if not is_instance_valid(bolt.visual):
		return
	bolt.visual.transform = Transform3D(
		bolt.local_orientation.scaled_local(Vector3(visual_scale, visual_scale, 1.0)), bolt.local_a)

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
	var wall := cast(origin, origin + dir * reach, exclude, false, 1)
	var limit: float = reach if wall.is_empty() else minf(reach, origin.distance_to(wall.position) + 0.004)
	var nearest: InstalledFastener = null
	for group in connections:
		for bolt in group.bolts:
			if (not record_matches(group, bolt) or not usable_body(bolt.a) or not usable_body(bolt.b)
					or not is_instance_valid(bolt.visual) or bolt.visual.is_queued_for_deletion()
					or not bolt.visual.is_visible_in_tree()):
				continue
			var normal := (bolt.a.global_basis * bolt.local_orientation.z).normalized()
			if normal.dot(dir) >= -0.1:
				continue
			var offset := bolt.head() + normal * HEAD_FACE_OFFSET - origin
			var depth := offset.dot(dir)
			if depth > 0.0 and depth < limit and (offset - dir * depth).length() < minf(0.014 * visual_scale, 0.035):
				limit = depth
				nearest = bolt
	return nearest

func remove(bolt: InstalledFastener) -> bool:
	reconcile()
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
	_installed.erase(bolt.id)
	bolt.state = InstalledFastener.State.FAILED if broken else InstalledFastener.State.RECOVERED
	if broken:
		failed.append(bolt)
		last_failed_group = group.id
		# A blunt nub replaces the tapered shaft and keeps the local datum.
		discard_visual(bolt)
		attach_visual(bolt, make_bolt_visual(bolt))
	else:
		discard_visual(bolt)
		bolt.group_id = 0
		bolt.load_estimate = 0.0
	if group.bolts.is_empty():
		connections.erase(group)

func discard_visual(bolt: InstalledFastener) -> void:
	if is_instance_valid(bolt.visual):
		bolt.visual.hide()
		bolt.visual.queue_free()
	bolt.visual = null

func physics_root(body: PhysicsBody3D) -> PhysicsBody3D:
	return _roots.get(body, body)

func incident(body: PhysicsBody3D) -> Array[FastenerConnection]:
	return connections.filter(func(edge: FastenerConnection) -> bool: return edge.a == body or edge.b == body)

func route(body: PhysicsBody3D, contact_support: PhysicsBody3D = null) -> Array[FastenerConnection]:
	# A full reaction exists only along a path to a fixed support.
	var queue: Array[PhysicsBody3D] = [body]
	var paths := {body: []}
	while not queue.is_empty():
		var current: PhysicsBody3D = queue.pop_front()
		if current != body and (current == contact_support or (contact_support == null and anchored(current))):
			var path: Array[FastenerConnection] = []
			path.assign(paths[current])
			return path
		for group in incident(current):
			var next := group.other(current)
			if not paths.has(next):
				paths[next] = paths[current] + [group]
				queue.append(next)
	return []

func apply_structural_load(body: PhysicsBody3D, point: Vector3, force: Vector3,
		ram_contact := false, contact_support: PhysicsBody3D = null) -> void:
	if not is_instance_valid(body) or not point.is_finite() or not force.is_finite():
		return
	reconcile()
	last_load = force.length()
	var changed := false
	var processed: Array[FastenerConnection] = []
	# Re-route after a complete break, without loading unrelated branches of
	# a now-separated island. Each bolt can fail at most once per call.
	var failures_before := failed.size()
	var path := route(body, contact_support)
	var source := "EXPLICIT LOAD"
	if ram_contact:
		source = "RAM SUPPORT PATH" if contact_support == null else "RAM CONTACT REACTION"
		if load_debug:
			print("RAM LOAD revision=", topology_revision, " driven=", body.name,
				" contact support=", contact_support, " force=", force, " route=", path.map(
					func(edge: FastenerConnection) -> int: return edge.id))
	if path.is_empty():
		if ram_contact:
			if contact_support == null:
				apply_ram_inertia(body, force)
			return
		path = incident(body)
	while not path.is_empty():
		var group: FastenerConnection = path.pop_front()
		if processed.has(group):
			continue
		processed.append(group)
		if overload_group(group, point, force, source):
			changed = true
			# Once the support path breaks, only another live support can
			# carry this same reaction. Free motion is evaluated separately.
			path = route(body, contact_support)
	if changed:
		rebuild()
	report_failures(failures_before)

func overload_group(group: FastenerConnection, point: Vector3, force: Vector3, source: String) -> bool:
	while not group.bolts.is_empty():
		group.estimate(point, force)
		var weakest: InstalledFastener = null
		var worst_ratio := 1.0
		for bolt in group.bolts:
			var ratio := bolt.load_estimate / bolt.grade.strength
			if load_debug:
				print("STRUCTURAL LOAD ", source, " revision=", topology_revision, " group=", group.id,
					" created=", group.created_revision, " bodies=", group.a.name, "/", group.b.name,
					" bolt=", bolt.id, " load=", bolt.load_estimate, " rating=", bolt.grade.strength)
			if ratio > worst_ratio:
				weakest = bolt
				worst_ratio = ratio
		if weakest == null:
			return false
		weakest.failure_source = source
		if load_debug:
			print("STRUCTURAL FAILURE group=", group.id, " bolt=", weakest.id, " reason=load exceeds rating")
		unlink(group, weakest, true)
	return true

## Free assemblies are accelerated by the ram. A branch transmits the
## inertia of its downstream bodies, rather than the full contact force.
## The centroid approximates the lever arm; cycles share no inferred load.
func apply_ram_inertia(body: PhysicsBody3D, force: Vector3) -> void:
	var root := physics_root(body) as RigidBody3D
	if root == null or root.freeze or force.is_zero_approx():
		return
	var failures_before := failed.size()
	var topology_changed := false
	var queue: Array[PhysicsBody3D] = [body]
	var visited := {body: true}
	while not queue.is_empty():
		var current: PhysicsBody3D = queue.pop_front()
		for group in incident(current):
			var next := group.other(current)
			if visited.has(next):
				continue
			var branch := branch_mass(next, current, group)
			visited[next] = true
			if branch.is_empty():
				continue
			if overload_group(group, branch.center, force * (float(branch.mass) / root.mass), "RAM INERTIA"):
				topology_changed = true
			else:
				queue.append(next)
	if topology_changed:
		rebuild()
	report_failures(failures_before)

func branch_mass(start: PhysicsBody3D, upstream: PhysicsBody3D, excluded: FastenerConnection) -> Dictionary:
	var queue: Array[PhysicsBody3D] = [start]
	var visited := {start: true}
	var total := 0.0
	var weighted := Vector3.ZERO
	while not queue.is_empty():
		var body: PhysicsBody3D = queue.pop_front()
		if body == upstream or not body is RigidBody3D:
			return {}
		var kilograms: float = _root_masses.get(body, body.mass)
		total += kilograms
		weighted += body.global_position * kilograms
		for group in incident(body):
			if group == excluded:
				continue
			var next := group.other(body)
			if not visited.has(next):
				visited[next] = true
				queue.append(next)
	return {"mass": total, "center": weighted / total}

func report_failures(previous_count: int) -> void:
	for index in range(previous_count, failed.size()):
		bolt_failed.emit(failed[index])

func installed_count() -> int:
	var count := 0
	for group in connections:
		count += group.bolts.size()
	return count

func make_bolt_visual(bolt: InstalledFastener, length_override := 0.0) -> Node3D:
	var visual := Node3D.new()
	visual.name = "Bolt_%d" % bolt.id
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
	ring.position.z = HEAD_FACE_OFFSET
	visual.add_child(ring)
	var length := length_override if length_override > 0.0 else bolt.visual_length
	if bolt.state == InstalledFastener.State.FAILED:
		make_cylinder(visual, 0.00635, SHEARED_LENGTH, -SHEARED_LENGTH * 0.5, 8, bolt.grade.finish).name = "ShearedNub"
	else:
		var shaft_length := length - TIP_LENGTH
		make_cylinder(visual, 0.00635, shaft_length, -shaft_length * 0.5, 8, bolt.grade.finish).name = "Shaft"
		make_cylinder(visual, 0.00635, TIP_LENGTH, -length + TIP_LENGTH * 0.5, 8, bolt.grade.finish, 0.002).name = "Tip"
	return visual

func make_cylinder(parent: Node3D, radius: float, length: float, z: float, sides: int,
		material: Material, bottom := -1.0) -> MeshInstance3D:
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
	return instance

func rebuild() -> void:
	topology_revision += 1
	var velocities := {}
	for body in _roots:
		var old: PhysicsBody3D = _roots[body]
		if is_instance_valid(body) and is_instance_valid(old) and old is RigidBody3D:
			velocities[body] = [old.linear_velocity + old.angular_velocity.cross(body.global_position - old.global_position),
				old.angular_velocity]
	for collider in _copies:
		if is_instance_valid(collider):
			if collider.get_parent() != null:
				collider.get_parent().remove_child(collider)
			collider.queue_free()
	for proxy in _proxies:
		if is_instance_valid(proxy):
			if proxy.get_parent() != null:
				proxy.get_parent().remove_child(proxy)
			proxy.queue_free()
	for body in _followers:
		if not is_instance_valid(body):
			continue
		var saved: Dictionary = _followers[body]
		var parent := get_parent()
		if is_instance_valid(saved.parent):
			parent = saved.parent
		if body.get_parent() != parent:
			body.reparent(parent)
		body.collision_layer = saved.layer
		body.collision_mask = saved.mask
		body.freeze = saved.frozen
		sync_body_transform(body)
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
	if root is RigidBody3D and not root.freeze:
		root.sleeping = false

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
	collider.transform = parent.global_transform.affine_inverse() * source.global_transform
	parent.add_child(collider)
	return collider

func diagnostics(aim: Dictionary) -> String:
	var a := aim.get("a") as PhysicsBody3D
	var b := aim.get("b") as PhysicsBody3D
	var group := between(a, b) if is_instance_valid(a) and is_instance_valid(b) else null
	var strengths := PackedStringArray()
	if group != null:
		for bolt in group.bolts:
			if record_matches(group, bolt):
				strengths.append("#%d LOAD %.0f / RATING %.0f" % [bolt.id, bolt.load_estimate, bolt.grade.strength])
	var broken := PackedStringArray()
	for bolt in failed.slice(maxi(0, failed.size() - 6)):
		broken.append(str(bolt.id))
	return "\nFASTENER SURFACE %s → %s · DEPTH %.3f m\nCONNECTION %s · ACTIVE %d · LAST LOAD %.0f\nBOLTS %s · FAILED %s" % [
		a.name if is_instance_valid(a) else "—", b.name if is_instance_valid(b) else "—", aim.get("depth", 0.0),
		"#%d FIXED" % group.id if group != null else "—", installed_count(), last_load,
		", ".join(strengths) if not strengths.is_empty() else "NONE", ", ".join(broken) if not broken.is_empty() else "NONE"]

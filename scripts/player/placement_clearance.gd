class_name PlacementClearance
extends RefCounted
## Queries use the original collider and its local offset.
const SWEEP_MARGIN := 0.008
const RELEASE_MARGIN := 0.001
const PICKUP_LIMIT := 0.025
const MAX_SLIDE_STEPS := 4
const MOTION_EPSILON := 0.00001
const CONTACT_PROBE := 0.018
const MAX_CONTACT_TURN := 0.025
const MIN_CONTACT_PROGRESS := 0.00005

var collider: CollisionShape3D
var shapes: Array[CollisionShape3D] = []
var item: InteractableObject
var space: PhysicsDirectSpaceState3D
var radius: float
var _contact_normal := Vector3.ZERO

func configure(body: InteractableObject) -> bool:
	collider = body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collider == null or collider.disabled or collider.shape == null:
		return false
	shapes.clear()
	radius = 0.0
	for owner in body.get_shape_owners():
		if body.is_shape_owner_disabled(owner):
			continue
		var part := body.shape_owner_get_owner(owner) as CollisionShape3D
		if part == null or not (part.shape is BoxShape3D or part.shape is SphereShape3D
				or part.shape is CapsuleShape3D or part.shape is CylinderShape3D
				or part.shape is ConvexPolygonShape3D):
			return false
		shapes.append(part)
		var bounds := part.transform * part.shape.get_debug_mesh().get_aabb()
		radius = maxf(radius, bounds.position.abs().max(bounds.end.abs()).length())
	item = body
	space = body.get_world_3d().direct_space_state
	return not shapes.is_empty()

func query(pose: Transform3D, mask: int, extra_margin: float = 0.0,
		part: CollisionShape3D = null) -> PhysicsShapeQueryParameters3D:
	if part == null:
		part = collider
	var parameters := PhysicsShapeQueryParameters3D.new()
	parameters.shape = part.shape
	parameters.transform = pose * part.transform
	parameters.collision_mask = mask
	parameters.exclude = [item.get_rid()]
	parameters.margin = RELEASE_MARGIN + extra_margin
	return parameters

func clear(pose: Transform3D, mask: int = 3, extra_margin: float = 0.0) -> bool:
	for part in shapes:
		if not space.intersect_shape(query(pose, mask, extra_margin, part), 1).is_empty():
			return false
	return true

func rest_contact(pose: Transform3D, mask := 3) -> Dictionary:
	for part in shapes:
		var contact := space.get_rest_info(query(pose, mask, 0.0, part))
		if not contact.is_empty():
			return contact
	return {}

func sweep_fractions(pose: Transform3D, motion: Vector3, margin: float) -> Vector2:
	var fractions := Vector2.ONE
	for part in shapes:
		var parameters := query(pose, 3, margin - RELEASE_MARGIN, part)
		parameters.motion = motion
		var hit := space.cast_motion(parameters)
		fractions = fractions.min(Vector2(hit[0], hit[1]))
	return fractions

## Check the real occupied volume without the manipulation margin.
func physically_clear(pose: Transform3D) -> bool:
	return clear(pose, 3, -RELEASE_MARGIN)

## Leave a resting contact using the physical shape before resuming padded placement.
func depart_resting_pose(pose: Transform3D, displacement: Vector3) -> Transform3D:
	if not physically_clear(pose):
		return pose
	var contact := rest_contact(pose)
	if not contact.is_empty():
		var normal: Vector3 = contact.normal
		displacement -= normal * minf(0.0, displacement.dot(normal))
	if displacement.length_squared() <= MOTION_EPSILON * MOTION_EPSILON:
		return pose
	var safe_fraction := sweep_fractions(pose, displacement, 0.0).x
	var candidate := pose.translated(displacement * safe_fraction)
	return candidate if physically_clear(candidate) else pose

## Recover only local resting contacts. Both sweeps include the player and world.
func pickup_pose(pose: Transform3D, debug_failure := false, preferred := Vector3.ZERO) -> Transform3D:
	if clear(pose):
		return pose
	var motion := PhysicsTestMotionParameters3D.new()
	motion.from = pose
	motion.margin = 0.003
	motion.max_collisions = 8
	motion.recovery_as_collision = true
	var result := PhysicsTestMotionResult3D.new()
	PhysicsServer3D.body_test_motion(item.get_rid(), motion, result)
	var recovery := result.get_travel()
	var recovered := pose
	recovered.origin += recovery
	if recovery.length() <= PICKUP_LIMIT and clear(recovered):
		return recovered

	var normals: Array[Vector3] = []
	var combined := Vector3.ZERO
	for index in result.get_collision_count():
		var normal := result.get_collision_normal(index)
		if not normals.any(func(existing: Vector3) -> bool: return existing.dot(normal) > 0.999):
			normals.append(normal)
			combined += normal
	var initial := query(pose, 3)
	var resting := rest_contact(pose)
	if not resting.is_empty() and not normals.any(func(normal: Vector3) -> bool: return normal.dot(resting.normal) > 0.999):
		normals.append(resting.normal)
		combined += resting.normal
	var directions := normals.duplicate()
	directions.push_front(combined.normalized())
	directions.append(Vector3.UP)
	directions.append(clip_motion(preferred.normalized(), normals).normalized())
	directions.append((combined.normalized() + preferred.normalized()).normalized())
	var starts_clear := physically_clear(pose)
	var attempts: Array[Dictionary] = []
	motion.recovery_as_collision = false
	# The backend recovers before sweeping. Short outward alternatives can
	# clear a second resting contact that the recovery result alone missed.
	for direction: Vector3 in directions:
		if direction.is_zero_approx() or normals.any(func(normal: Vector3) -> bool: return direction.dot(normal) < -0.001):
			continue
		for length in [0.006, 0.012, 0.018]:
			motion.motion = direction * length
			# A valid resting pose can touch the manipulation margin. Test an
			# extraction with actual geometry before asking for preview clearance.
			if starts_clear:
				var end := pose.translated(motion.motion)
				var safe := sweep_fractions(pose, motion.motion, 0.0)
				if safe[0] >= 1.0 and clear(end):
					return end
				if debug_failure:
					var sample := pose.translated(motion.motion * safe[1])
					var hits := space.intersect_shape(query(sample, 3), 1)
					attempts.append({"direction": direction, "destination": end.origin,
						"result": "exact sweep" if safe[0] < 1.0 else "preview margin",
						"blocker": _pickup_blocker(hits[0].collider) if not hits.is_empty() else "none"})
			var blocked := PhysicsServer3D.body_test_motion(item.get_rid(), motion, result)
			var candidate := pose
			candidate.origin += result.get_travel()
			if not blocked and result.get_travel().length() <= PICKUP_LIMIT and clear(candidate):
				return candidate
			if debug_failure:
				var body: Object = null
				if result.get_collision_count() > 0:
					body = result.get_collider()
				else:
					for part in shapes:
						var hits := space.intersect_shape(query(candidate, 3, 0.0, part), 1)
						if not hits.is_empty():
							body = hits[0].collider
							break
				attempts.append({"direction": direction, "destination": candidate.origin,
					"result": "path" if blocked else "destination" if is_instance_valid(body) else "recovery limit",
					"blocker": _pickup_blocker(body)})
	if debug_failure:
		var contacts := space.intersect_shape(initial, 8)
		var initial_state := "clearance margin" if starts_clear else "overlap"
		var blockers: Array[String] = []
		for contact in contacts:
			blockers.append(_pickup_blocker(contact.collider))
		print("PICKUP ", "WAITING FOR DEPARTURE " if starts_clear else "BLOCKED ",
			item.definition.object_id, " ", collider.shape.get_class(),
			" pose=", pose, " initial=", initial_state, " blockers=", blockers,
			" recovery_destination=", recovered.origin, " recovery=", recovery, " attempts=", attempts)
	return pose

static func _pickup_blocker(body: Object) -> String:
	if not is_instance_valid(body):
		return "none"
	var id := str(body.get_instance_id())
	if body is InteractableObject and body.definition != null:
		id = String(body.definition.object_id)
	elif body is Node:
		id = String(body.name)
	return "%s (%s #%d)" % [id, body.get_class(), body.get_instance_id()]

func slide(pose: Transform3D, displacement: Vector3, mask: int = 3) -> Transform3D:
	_contact_normal = Vector3.ZERO
	if not clear(pose, mask):
		return pose
	var parameters := PhysicsTestMotionParameters3D.new()
	parameters.margin = SWEEP_MARGIN
	parameters.max_collisions = MAX_SLIDE_STEPS
	var remaining := displacement
	var normals: Array[Vector3] = []
	var rid := item.get_rid()
	# Query the real collider with its preview layer still disabled. The mask is
	# restored synchronously before physics can step or anything can be released.
	var previous_mask := PhysicsServer3D.body_get_collision_mask(rid)
	PhysicsServer3D.body_set_collision_mask(rid, mask)
	for step in MAX_SLIDE_STEPS:
		if remaining.length_squared() <= MOTION_EPSILON * MOTION_EPSILON:
			break
		parameters.from = pose
		parameters.motion = remaining
		var result := PhysicsTestMotionResult3D.new()
		var hit := PhysicsServer3D.body_test_motion(rid, parameters, result)
		var safe := result.get_collision_safe_fraction() if hit else 1.0
		var fraction := maxf(0.0, safe - 0.001 / remaining.length()) if hit else 1.0
		var candidate := pose
		candidate.origin += remaining * fraction
		if not clear(candidate, mask):
			# The sweep and overlap query can disagree near contact. Keep a
			# verified pose and still resolve the tangential remainder.
			var contact := rest_contact(candidate, mask)
			if not contact.is_empty():
				normals.append(contact.normal)
			fraction = clear_fraction(pose, remaining, fraction, mask)
			candidate.origin = pose.origin + remaining * fraction
			hit = true
		pose = candidate
		if not hit:
			break
		for index in result.get_collision_count():
			var normal := result.get_collision_normal(index)
			if remaining.dot(normal) < -MOTION_EPSILON:
				normals.append(normal)
		var clipped := clip_motion(remaining * (1.0 - fraction), normals)
		if fraction <= MOTION_EPSILON and clipped.is_equal_approx(remaining):
			break
		remaining = clipped
	PhysicsServer3D.body_set_collision_mask(rid, previous_mask)
	for normal in normals:
		if displacement.dot(normal) < displacement.dot(_contact_normal):
			_contact_normal = normal
	return pose

func clear_fraction(pose: Transform3D, motion: Vector3, upper: float, mask: int) -> float:
	var lower := 0.0
	for step in 8:
		var fraction := (lower + upper) * 0.5
		var candidate := pose
		candidate.origin += motion * fraction
		if clear(candidate, mask):
			lower = fraction
		else:
			upper = fraction
	return lower

static func clip_motion(motion: Vector3, normals: Array[Vector3]) -> Vector3:
	var clipped := motion
	for index in normals.size():
		var normal := normals[index]
		var into := clipped.dot(normal)
		if into >= -MOTION_EPSILON:
			continue
		clipped -= normal * into
		for previous in index:
			if clipped.dot(normals[previous]) < -MOTION_EPSILON:
				var crease := normal.cross(normals[previous]).normalized()
				clipped = crease * motion.dot(crease)
				break
	# A third plane can close the crease entirely.
	for normal in normals:
		if clipped.dot(normal) < -MOTION_EPSILON:
			return Vector3.ZERO
	return clipped

func accommodate_contact(pose: Transform3D, displacement: Vector3) -> Transform3D:
	var pressure := -displacement.dot(_contact_normal)
	if pressure < 0.0002 or not clear(pose):
		return pose
	# Confirm that the contact still exists after tangential travel.
	var parameters := PhysicsTestMotionParameters3D.new()
	parameters.from = pose
	parameters.motion = -_contact_normal * CONTACT_PROBE
	parameters.margin = SWEEP_MARGIN
	parameters.max_collisions = 4
	parameters.recovery_as_collision = true
	var result := PhysicsTestMotionResult3D.new()
	var rid := item.get_rid()
	var previous_mask := PhysicsServer3D.body_get_collision_mask(rid)
	PhysicsServer3D.body_set_collision_mask(rid, 3)
	var hit := PhysicsServer3D.body_test_motion(rid, parameters, result)
	PhysicsServer3D.body_set_collision_mask(rid, previous_mask)
	if not hit:
		return pose

	var normal := result.get_collision_normal()
	pressure = -displacement.dot(normal)
	if pressure < 0.0002:
		return pose
	var pivot := Vector3.ZERO
	var contacts := 0
	for index in result.get_collision_count():
		if result.get_collision_normal(index).dot(normal) > 0.99:
			pivot += result.get_collision_point(index)
			contacts += 1
	if contacts == 0:
		return pose
	pivot /= contacts

	var reference := pose * collider.position
	var moment := (pivot - reference).cross(normal) * pressure
	var extent := scaled_radius(pose)
	var angle := minf(MAX_CONTACT_TURN, moment.length() / maxf(extent * extent, 0.0001))
	if angle < 0.0001:
		return pose

	for attempt in 5:
		var turn := Basis(moment.normalized(), angle)
		var candidate := Transform3D(turn * pose.basis, pivot + turn * (pose.origin - pivot))
		# Provide temporary room for the conservative swept envelope. Both
		# the outward step and the return toward contact use shape sweeps.
		var shift := candidate.origin - pose.origin
		var lift := (extent * angle + shift.length()) * 0.5 + maxf(0, -shift.dot(normal)) + 0.001
		var lifted := sweep_translation(pose, normal * lift)
		if lifted.origin.distance_to(pose.origin + normal * lift) < 0.00001:
			candidate.origin += normal * lift
			if rotation_clear(lifted, candidate, angle):
				var approach := minf(pressure, shift.length() + 0.002)
				var inward := -normal * (lift + approach)
				# Measure both orientations using the same sweep. The displayed
				# pose comes from body motion, which uses a different backoff.
				var baseline := sweep_translation(lifted, inward)
				var settled := sweep_translation(candidate, inward)
				var gain := (baseline.origin - settled.origin).dot(normal)
				var advance := (pose.origin - settled.origin).dot(normal)
				if (gain > MIN_CONTACT_PROGRESS and advance >= -RELEASE_MARGIN
						and advance <= pressure + MOTION_EPSILON):
					return settled
		angle *= 0.5
	return pose

func sweep_translation(pose: Transform3D, motion: Vector3) -> Transform3D:
	if motion.is_zero_approx():
		return pose
	var fraction := sweep_fractions(pose, motion, RELEASE_MARGIN).x
	if fraction < 1.0:
		fraction = maxf(0, fraction - 0.0002 / motion.length())
	var candidate := pose
	candidate.origin += motion * fraction
	if not clear(candidate):
		candidate.origin = pose.origin + motion * clear_fraction(pose, motion, fraction, 3)
	return candidate

func scaled_radius(pose: Transform3D) -> float:
	var scale := pose.basis.get_scale().abs()
	return radius * maxf(scale.x, maxf(scale.y, scale.z))

func rotation_clear(from: Transform3D, to: Transform3D, radians: float) -> bool:
	# Cover the arc and any concurrent motion of its reference point.
	var arc_margin := (scaled_radius(from) * absf(radians) + from.origin.distance_to(to.origin)) * 0.5
	return clear(from.interpolate_with(to, 0.5), 3, arc_margin) and clear(to)

## Check rotation in small increments so a clear arc can approach a socket.
func turn_path_clear(from: Transform3D, to: Transform3D) -> bool:
	var radians := from.basis.get_rotation_quaternion().angle_to(to.basis.get_rotation_quaternion())
	if radians < MOTION_EPSILON:
		return clear(to)
	var steps := maxi(1, ceili(radians / 0.035))
	var previous := from
	for index in range(1, steps + 1):
		var next := from.interpolate_with(to, float(index) / steps)
		if not rotation_clear(previous, next, radians / steps):
			return false
		previous = next
	return true

func translation_path_clear(from: Transform3D, to: Transform3D) -> bool:
	return clear(from) and sweep_translation(from, to.origin - from.origin).origin.is_equal_approx(to.origin)

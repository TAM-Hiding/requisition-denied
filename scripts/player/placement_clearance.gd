class_name PlacementClearance
extends RefCounted
## Queries use the original collider and its local offset.
const SWEEP_MARGIN := 0.008
const RELEASE_MARGIN := 0.001
const MAX_SLIDE_STEPS := 4
const MOTION_EPSILON := 0.00001
const CONTACT_PROBE := 0.018
const MAX_CONTACT_TURN := 0.025
const MIN_CONTACT_PROGRESS := 0.00005

var collider: CollisionShape3D
var item: InteractableObject
var space: PhysicsDirectSpaceState3D
var radius: float
var _contact_normal := Vector3.ZERO

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
	parameters.margin = RELEASE_MARGIN + extra_margin
	return parameters

func clear(pose: Transform3D, mask: int = 3, extra_margin: float = 0.0) -> bool:
	return space.intersect_shape(query(pose, mask, extra_margin), 1).is_empty()

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
			var contact := space.get_rest_info(query(candidate, mask))
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
				var settled := sweep_translation(candidate, -normal * (lift + approach))
				var advance := -(settled.origin - pose.origin).dot(normal)
				# A step must let the reference advance under the applied
				# pressure. A settled face cannot rock back and forth.
				if advance > MIN_CONTACT_PROGRESS and advance <= pressure + MOTION_EPSILON:
					return settled
		angle *= 0.5
	return pose

func sweep_translation(pose: Transform3D, motion: Vector3) -> Transform3D:
	var parameters := query(pose, 3)
	parameters.motion = motion
	var fraction := space.cast_motion(parameters)[0]
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

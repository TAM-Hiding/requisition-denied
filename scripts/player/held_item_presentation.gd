class_name HeldItemPresentation
extends Node
## Collision queries affect only a frozen held model, never the camera or player.
enum Pose { NORMAL, LOWERED }
var requested_pose: Pose = Pose.NORMAL
var pose_blend: float = 0.0
var aim_requested := false
var station_active := false
var aim_blend := 0.0
var lateral_shift: float = 0.0
var item: InteractableObject
var actor: OtisController
var anchor: Node3D
var profile: HeldItemProfile
var extension: float = 1.0
var obstructed: bool = false
var _previous_origin: Vector3
var _previous_valid: bool = false
var _sweep_envelope: SphereShape3D

func request_pose(pose: Pose) -> void:
	requested_pose = pose

func configure(owner_actor: OtisController, equipment_anchor: Node3D) -> void:
	actor = owner_actor
	anchor = equipment_anchor

func track(held: InteractableObject) -> void:
	item = held
	profile = held.definition.held_profile
	if profile == null:
		profile = HeldItemProfile.new()
		var collider := held.get_node_or_null("CollisionShape3D") as CollisionShape3D
		if collider != null:
			profile.envelope = collider.shape
			profile.envelope_transform = collider.transform
	extension = 1.0
	lateral_shift = 0
	_previous_valid = false
	_sweep_envelope = SphereShape3D.new()
	if profile.envelope != null:
		var bounds := profile.envelope.get_debug_mesh().get_aabb()
		var corner := bounds.position.abs().max(bounds.end.abs())
		_sweep_envelope.radius = (corner * profile.envelope_transform.basis.get_scale().abs()).length() + profile.envelope_transform.origin.length()
	update_pose(0)

func clear() -> void:
	item = null
	profile = null
	_previous_valid = false
	obstructed = false
	extension = 1.0

func _process(delta: float) -> void:
	# Runs after input and physics, before rendering: rotation is checked even
	# on render frames between physics ticks, including sudden camera turns.
	update_pose(delta)

func set_station_active(active: bool) -> void:
	station_active = active
	_previous_valid = false
	if active and is_instance_valid(item):
		item.hide()
	elif not active:
		update_pose(0.0)

func query(shape: Shape3D, transform: Transform3D, motion: Vector3 = Vector3.ZERO) -> PhysicsShapeQueryParameters3D:
	var parameters := PhysicsShapeQueryParameters3D.new()
	parameters.shape = shape
	parameters.transform = transform
	parameters.motion = motion
	parameters.margin = profile.clearance_margin
	parameters.collision_mask = 1
	parameters.exclude = [actor.get_rid(), item.get_rid()]
	return parameters

func pose_origin_camera() -> Vector3:
	var base := actor.camera.to_local(anchor.global_position)
	var normal := base + profile.lowered_offset * pose_blend
	if item is FasteningTool:
		var aim := Vector3(0, -FasteningTool.REAR_SIGHT_TIP.y, -0.48)
		return Vector3(0.27, -0.25, -0.56).lerp(aim, aim_blend)
	return normal

func sight_replaces_crosshair() -> bool:
	if not aim_requested or aim_blend < 0.999 or not is_instance_valid(item) or not item.visible:
		return false
	var tip := actor.camera.to_local(item.to_global(FasteningTool.REAR_SIGHT_TIP))
	return absf(tip.x) < 0.001 and absf(tip.y) < 0.001 and -tip.z > actor.camera.near + 0.01

func presentation_basis() -> Basis:
	return actor.camera.global_basis if item is FasteningTool else anchor.global_basis

func retraction_origin_camera(normal: Vector3, amount: float, depth: float = 1.0) -> Vector3:
	var direction := -1.0 if normal.x >= 0 else 1.0
	return normal + profile.retraction_offset * depth + Vector3(direction * amount, 0, 0)

func volume_clear(space: PhysicsDirectSpaceState3D, origin: Vector3) -> bool:
	var transform := Transform3D(presentation_basis(), origin) * profile.envelope_transform
	return space.intersect_shape(query(profile.envelope, transform), 1).is_empty()

func travel_limit(space: PhysicsDirectSpaceState3D, retracted: Vector3, normal: Vector3, extra_margin: float = 0) -> float:
	var start := Transform3D(presentation_basis(), retracted) * profile.envelope_transform
	var parameters := query(profile.envelope, start, normal - retracted)
	parameters.margin += extra_margin
	# An enlarged anticipation volume may overlap at the safe retracted end.
	if not space.intersect_shape(parameters, 1).is_empty():
		return 1.0 if extra_margin > 0 else 0.0
	var fraction: float = space.cast_motion(parameters)[0]
	var allowed := maxf(0, fraction - 0.015) if fraction < 1 else 1.0
	var sphere := query(_sweep_envelope, Transform3D(Basis.IDENTITY, retracted), normal - retracted)
	sphere.margin += extra_margin
	if space.intersect_shape(sphere, 1).is_empty():
		var sphere_fraction: float = space.cast_motion(sphere)[0]
		if sphere_fraction < 1:
			allowed = minf(allowed, maxf(0, sphere_fraction - 0.015))
	return allowed

func update_pose(delta: float) -> void:
	# Pose requests persist even while an item is stowed; ownership never changes.
	var speed: float = profile.pose_transition_speed if profile != null else 8.0
	var target := 1.0 if requested_pose == Pose.LOWERED else 0.0
	pose_blend = lerpf(pose_blend, target, 1.0 - exp(-speed * maxf(0, delta)))
	aim_blend = move_toward(aim_blend, 1.0 if aim_requested else 0.0, maxf(0.0, delta) * 8.0)
	if absf(pose_blend - target) < 0.0001:
		pose_blend = target
	if not is_instance_valid(item) or item.state != InteractableObject.State.HELD:
		return
	if station_active:
		item.hide()
		return
	if profile.envelope == null:
		item.hide()
		obstructed = true
		return
	var space := actor.get_world_3d().direct_space_state
	var normal_camera := pose_origin_camera()
	var normal := actor.camera.to_global(normal_camera)
	var required_shift: float = 0.0
	var depth: float = -1.0
	# Prefer backward-only travel. If an obstacle is behind the elbow, use a
	# shorter clear path rather than hiding a tool whose normal pose is clear.
	for candidate_depth in [1.0, 0.75, 0.5, 0.25, 0.0]:
		if volume_clear(space, actor.camera.to_global(retraction_origin_camera(normal_camera, 0, candidate_depth))):
			depth = candidate_depth
			break
	if depth < 0:
		for candidate_depth in [1.0, 0.75, 0.5, 0.25, 0.0]:
			var fallback := actor.camera.to_global(retraction_origin_camera(normal_camera, profile.lateral_clearance_limit, candidate_depth))
			if not volume_clear(space, fallback):
				continue
			depth = candidate_depth
			var low: float = 0
			var high := profile.lateral_clearance_limit
			for step in range(7):
				var middle := (low + high) * 0.5
				if volume_clear(space, actor.camera.to_global(retraction_origin_camera(normal_camera, middle, depth))):
					high = middle
				else:
					low = middle
			required_shift = high
			break
	if depth < 0:
		item.hide()
		extension = 0
		obstructed = true
		_previous_valid = false
		return
	# Ease lateral recovery, but never interpolate through a blocked volume.
	lateral_shift = maxf(required_shift, move_toward(lateral_shift, required_shift, delta * 0.8))
	var retracted := actor.camera.to_global(retraction_origin_camera(normal_camera, lateral_shift, depth))
	var allowed := travel_limit(space, retracted, normal)
	var anticipated := minf(allowed, travel_limit(space, retracted, normal, profile.anticipation_margin))
	var rate := profile.retract_speed if anticipated < extension else profile.restore_speed
	extension = minf(allowed, move_toward(extension, anticipated, rate * maxf(0, delta)))
	if absf(extension - anticipated) < 0.0001:
		extension = anticipated
	var position := retracted.lerp(normal, extension)
	if _previous_valid and position.distance_squared_to(_previous_origin) > 0.000001:
		# A conservative sphere covers rotation and travel between rendered poses.
		var sweep := query(_sweep_envelope, Transform3D(Basis.IDENTITY, _previous_origin), position - _previous_origin)
		if space.cast_motion(sweep)[0] < 1.0:
			extension = 0
			position = retracted
	if not volume_clear(space, position):
		item.hide()
		extension = 0
		obstructed = true
		_previous_valid = false
		return
	item.global_transform = Transform3D(presentation_basis(), position)
	item.show()
	obstructed = extension < 0.999 or lateral_shift > 0.001
	_previous_origin = position
	_previous_valid = true

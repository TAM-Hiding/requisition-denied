class_name HeldItemPresentation
extends Node
## Collision queries affect only a frozen held model, never the camera or player.
var item: InteractableObject
var actor: OtisController
var anchor: Node3D
var profile: HeldItemProfile
var extension: float = 1.0
var obstructed: bool = false
var _previous_origin: Vector3
var _previous_valid: bool = false
var _sweep_envelope: SphereShape3D

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

func query(shape: Shape3D, transform: Transform3D, motion: Vector3 = Vector3.ZERO) -> PhysicsShapeQueryParameters3D:
	var parameters := PhysicsShapeQueryParameters3D.new()
	parameters.shape = shape
	parameters.transform = transform
	parameters.motion = motion
	parameters.margin = profile.clearance_margin
	parameters.collision_mask = 1
	parameters.exclude = [actor.get_rid(), item.get_rid()]
	return parameters

func update_pose(delta: float) -> void:
	if not is_instance_valid(item) or item.state != InteractableObject.State.HELD:
		return
	if profile.envelope == null:
		item.hide()
		obstructed = true
		return
	var space := actor.get_world_3d().direct_space_state
	var retracted := actor.camera.to_global(profile.retracted_camera_position)
	var normal := anchor.global_position
	var start := Transform3D(anchor.global_basis, retracted) * profile.envelope_transform
	var parameters := query(profile.envelope, start, normal - retracted)
	# cast_motion ignores initial overlaps, so explicitly test the start volume.
	if not space.intersect_shape(parameters, 1).is_empty():
		item.hide()
		extension = 0
		obstructed = true
		_previous_valid = false
		return
	var fractions := space.cast_motion(parameters)
	var allowed := clampf(fractions[0] - 0.015, 0, 1) if fractions[0] < 1 else 1.0
	# Use the conservative rotation envelope for outward clearance too. This
	# prevents repeated restore/retract cycles caused by a wider sweep sphere.
	var sphere_start := query(_sweep_envelope, Transform3D(Basis.IDENTITY, retracted), normal - retracted)
	if space.intersect_shape(sphere_start, 1).is_empty():
		var sphere_fraction: float = space.cast_motion(sphere_start)[0]
		if sphere_fraction < 1:
			allowed = minf(allowed, maxf(0, sphere_fraction - 0.015))
	# Retraction is immediate for safety; only restoration is smoothed.
	extension = minf(allowed, move_toward(extension, 1.0, profile.restore_speed * delta))
	var position := retracted.lerp(normal, extension)
	if _previous_valid and position.distance_squared_to(_previous_origin) > 0.000001:
		# A conservative sphere covers orientation changes and sweeps between
		# rendered poses, avoiding jumps through thin obstacles on rapid turns.
		var sweep := query(_sweep_envelope, Transform3D(Basis.IDENTITY, _previous_origin), position - _previous_origin)
		if space.cast_motion(sweep)[0] < 1.0:
			extension = 0
			position = retracted
	var end := Transform3D(anchor.global_basis, position) * profile.envelope_transform
	if not space.intersect_shape(query(profile.envelope, end), 1).is_empty():
		item.hide()
		extension = 0
		obstructed = true
		_previous_valid = false
		return
	item.position = anchor.to_local(position)
	item.show()
	obstructed = extension < 0.999
	_previous_origin = position
	_previous_valid = true

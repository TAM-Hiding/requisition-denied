class_name ContactPush
extends RefCounted
## Pass traction-limited, horizontal contact impulses to the physical body
## reported by the sweep. A compounded assembly already has one effective mass.
const MIN_APPROACH_SPEED := 0.08
const MAX_PUSH_SPEED := 1.8
const TRACTION := 0.55
const MASS_RATIO_LIMIT := 1.6

static func apply(actor: OtisController, approach: Vector3, delta: float) -> void:
	approach.y = 0.0
	if approach.length_squared() < MIN_APPROACH_SPEED * MIN_APPROACH_SPEED:
		return
	var contacts := {}
	for index in actor.get_slide_collision_count():
		var slide := actor.get_slide_collision(index)
		for hit_index in slide.get_collision_count():
			var body := slide.get_collider(hit_index) as RigidBody3D
			if body == null or body.freeze or body.is_queued_for_deletion():
				continue
			var member := FasteningSystem.logical_body(body, slide.get_collider_shape_index(hit_index)) as InteractableObject
			if not eligible(body, member):
				continue
			var direction := -slide.get_normal(hit_index)
			# Ignore floors and slopes. Incidental contact cannot hoist a load.
			if absf(direction.y) > 0.985:
				continue
			direction.y = 0.0
			direction = direction.normalized()
			var speed_deficit := minf(approach.dot(direction), MAX_PUSH_SPEED) - body.linear_velocity.dot(direction)
			if approach.dot(direction) > MIN_APPROACH_SPEED and speed_deficit > 0.0:
				if not contacts.has(body) or speed_deficit > contacts[body].speed:
					contacts[body] = {"direction": direction, "speed": speed_deficit}

	# Spend one traction budget across all contacts. Never stack impulses per
	# shape, and never apply directly to a follower in a bolted island.
	var budget := actor.supporting_load_kg() * actor.gravity * TRACTION * delta
	var share := budget / maxf(1.0, float(contacts.size()))
	for body: RigidBody3D in contacts:
		var contact: Dictionary = contacts[body]
		if body.mass <= actor.body_mass_kg * MASS_RATIO_LIMIT:
			var impulse := minf(share, body.mass * contact.speed)
			body.apply_central_impulse(contact.direction * impulse)

static func eligible(body: RigidBody3D, member: InteractableObject) -> bool:
	if member == null or member.state != InteractableObject.State.WORLD or member.support_carrier != null:
		return false
	if member.fastened:
		return is_instance_valid(member.fastening_system) and member.assembly_root() == body \
			and member.fastening_system.assembly_available(body)
	return member == body and member.mobility() != ObjectDefinition.Mobility.FIXED

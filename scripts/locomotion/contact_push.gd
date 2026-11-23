class_name ContactPush
extends RefCounted
## Apply the player's weight and traction to the physical body hit by the sweep.
## A compounded assembly uses its canonical solver body.
const MIN_APPROACH_SPEED := 0.08
const MAX_PUSH_SPEED := 1.8
const TRACTION := 0.55
const MASS_RATIO_LIMIT := 1.6

static func apply(actor: OtisController, approach: Vector3, delta: float, platform_velocity := Vector3.ZERO) -> void:
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
			var at := slide.get_position(hit_index)
			var contact_velocity := point_velocity(body, at)
			var relative := approach + platform_velocity - contact_velocity
			var speed_deficit := minf(relative.dot(direction), MAX_PUSH_SPEED)
			if approach.dot(direction) > MIN_APPROACH_SPEED and speed_deficit > 0.0:
				if not contacts.has(body) or speed_deficit > contacts[body].speed:
					contacts[body] = {"direction": direction, "speed": speed_deficit, "point": at}

	# Spend one traction budget across all contacts. Never stack impulses per
	# shape, and never apply directly to a follower in a bolted island.
	var budget := actor.supporting_load_kg() * actor.gravity * TRACTION * delta
	var share := budget / maxf(1.0, float(contacts.size()))
	for body: RigidBody3D in contacts:
		var contact: Dictionary = contacts[body]
		if body.mass <= actor.body_mass_kg * MASS_RATIO_LIMIT:
			var impulse := minf(share, effective_mass(body, contact.point, contact.direction) * contact.speed)
			body.apply_impulse(contact.direction * impulse, contact.point - body.global_position)

static func apply_weight(actor: OtisController) -> void:
	var up := actor.up_direction
	var slope := cos(actor.floor_max_angle)
	# Route the load under the stance, so a capsule brushing a small loose
	# part at its rim doesn't put the rider's full weight onto that part.
	var origin := actor.global_position
	var query := PhysicsRayQueryParameters3D.new()
	query.from = origin + up * 0.08
	query.to = origin - up * (actor.floor_snap_length + 0.05)
	query.collision_mask = actor.collision_mask
	query.exclude = [actor.get_rid()]
	var hit := actor.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty() and hit.normal.dot(up) >= slope:
		apply_support_force(actor, hit.collider, hit.position)
		return
	# Use the reported floor contact when the stance center overhangs support.
	for index in actor.get_slide_collision_count():
		var slide := actor.get_slide_collision(index)
		for contact in slide.get_collision_count():
			if slide.get_normal(contact).dot(up) >= slope:
				apply_support_force(actor, slide.get_collider(contact), slide.get_position(contact))
				return


static func apply_support_force(actor: OtisController, support: Object, point: Vector3) -> void:
	var body := support as RigidBody3D
	if not is_instance_valid(body) or body.freeze or body.is_queued_for_deletion():
		return
	# Only supports that leave the solver's Otis layer out of their mask need
	# the character's weight here. Never double count a two-way contact.
	if (body.collision_mask & actor.collision_layer) != 0:
		return
	body.apply_force(-actor.up_direction * actor.supporting_load_kg() * actor.gravity, point - body.global_position)


static func point_velocity(body: RigidBody3D, point: Vector3) -> Vector3:
	var state := PhysicsServer3D.body_get_direct_state(body.get_rid())
	if state == null:
		return body.linear_velocity
	var center := state.transform * state.center_of_mass_local
	return state.linear_velocity + state.angular_velocity.cross(point - center)


static func effective_mass(body: RigidBody3D, point: Vector3, direction: Vector3) -> float:
	var state := PhysicsServer3D.body_get_direct_state(body.get_rid())
	if state == null or body.lock_rotation:
		return body.mass
	var center := state.transform * state.center_of_mass_local
	var axis := (point - center).cross(direction)
	var inverse_mass := state.inverse_mass + axis.dot(state.inverse_inertia_tensor * axis)
	return 1.0 / inverse_mass if inverse_mass > 0.0 else body.mass


static func eligible(body: RigidBody3D, member: InteractableObject) -> bool:
	if member == null or member.state != InteractableObject.State.WORLD or member.support_carrier != null:
		return false
	if member.fastened:
		return is_instance_valid(member.fastening_system) and member.assembly_root() == body \
			and member.fastening_system.assembly_available(body)
	return member == body and member.mobility() != ObjectDefinition.Mobility.FIXED

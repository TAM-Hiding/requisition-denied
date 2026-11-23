extends "res://tests/validate_industrial_lifts.gd"
## Isolate the catalog beam and crane from floor contact and the rider.


func run() -> void:
	facility = preload("res://scenes/facility.tscn").instantiate()
	root.add_child(facility)
	current_scene = facility
	hall = facility.get_node("EngineeringTestHall")
	crane = facility.overhead_crane
	supply = facility.scrap_supply
	await frames(12)
	var beam := dispense(BEAM)
	if beam != null:
		await test_centered_yaw(beam)
		await test_tension_torque(beam)
	facility.queue_free()
	await frames(2)
	print("RD-015D suspended beam response: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func test_centered_yaw(beam: InteractableObject) -> void:
	await frames(60)
	var height: float = supply.catalog[catalog_index(BEAM)].size.y
	var info := crane.mass_properties.resolve(beam)
	var properties := PhysicsServer3D.body_get_direct_state(beam.get_rid())
	var inverse_tensor := properties.inverse_inertia_tensor
	var basis := beam.global_basis
	var inertia := Vector3(1.0 / basis.x.dot(inverse_tensor * basis.x),
		1.0 / basis.y.dot(inverse_tensor * basis.y), 1.0 / basis.z.dot(inverse_tensor * basis.z))
	var span_term: float = info.mass_kg * pow(supply.catalog[catalog_index(BEAM)].size.x, 2.0) / 12.0
	check(info.is_liftable() and info.local_center.length() < 0.001
		and inertia.is_finite() and absf(inertia.y - span_term) < span_term * 0.03
		and absf(inertia.z - span_term) < span_term * 0.03 and inertia.x < inertia.y * 0.01,
		"W12×50 has the centered COM and separated axial/transverse moments of a long beam")

	var centerline := beam.to_global(Vector3.UP * height * 0.5)
	await stage_empty_hook(centerline)
	var issue := crane.attach_load(beam, centerline)
	check(issue.is_empty(), "Attach the beam at the top centerline: " + issue)
	if not issue.is_empty():
		return
	crane.adjust_hook_steps(25, false)
	await frames(275)
	check(beam.global_position.y > 2.0 and absf(beam.global_basis.x.y) < 0.03
		and beam.angular_velocity.length() < 0.03, "Undisturbed centered lift remains balanced")

	var initial_basis := beam.global_basis
	beam.apply_torque_impulse(Vector3.UP * 600.0)
	await frames(6)
	var yaw_speed := beam.angular_velocity.y
	check(absf(yaw_speed - 600.0 / inertia.y) < 0.02,
		"A known yaw impulse produces the speed predicted by the beam's inertia")
	await frames(115)
	var yaw := initial_basis.x.signed_angle_to(beam.global_basis.x, Vector3.UP)
	check(yaw > 0.16 and beam.angular_velocity.y > yaw_speed * 0.60
		and beam.angular_velocity.y < yaw_speed and absf(beam.global_basis.x.y) < 0.04,
		"Centered single-point yaw stays free and decays gradually without a leveling torque")
	crane.detach_load()


func test_tension_torque(beam: InteractableObject) -> void:
	var height: float = supply.catalog[catalog_index(BEAM)].size.y
	var initial_pose := hall.global_transform * Transform3D(Basis.IDENTITY, Vector3(0, 3.0, 9.5))
	var point := initial_pose * Vector3(1.15, height * 0.5, 0)
	await stage_empty_hook(point)
	# Stage the beam clear of the floor so contact cannot mask the first strap torque.
	beam.global_transform = initial_pose
	PhysicsServer3D.body_set_state(beam.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, initial_pose)
	beam.linear_velocity = Vector3.ZERO
	beam.angular_velocity = Vector3.ZERO
	beam.sleeping = false
	var issue := crane.attach_load(beam, point)
	check(issue.is_empty(), "Attach the beam 1.15 m off center: " + issue)
	if not issue.is_empty():
		return
	var measured := Vector3.ZERO
	var predicted := Vector3.ZERO
	for frame in 35:
		var state := PhysicsServer3D.body_get_direct_state(beam.get_rid())
		var arm := crane.rigging.load_point() - state.transform * state.center_of_mass_local
		var tensor := state.inverse_inertia_tensor
		var before := beam.angular_velocity
		await physics_frame
		var impulse := -crane.rigging.hook_impulse
		if impulse.length() > 20.0:
			predicted = tensor * arm.cross(impulse)
			measured = beam.angular_velocity - before
			break
	check(predicted.z > 0.004 and measured.z > 0.0
		and absf(measured.z - predicted.z) < predicted.z * 0.25,
		"The first meaningful tension impulse immediately gives the expected off-center angular response")

	crane.adjust_hook_steps(40, false)
	await frames(510)
	var to_attachment := crane.rigging.load_point() - beam.global_position
	check(beam.global_transform.is_finite() and beam.angular_velocity.is_finite()
		and absf(beam.global_basis.x.y) > 0.82 and to_attachment.normalized().y > 0.78,
		"Off-center lift can turn freely toward the gravity-supported attitude")

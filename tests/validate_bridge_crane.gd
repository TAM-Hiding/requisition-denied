extends SceneTree

const STEP := 1.0 / 60.0

var facility: Node3D
var crane: BridgeCrane
var checks := 0
var failures := 0


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, note: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(note)


func advance(seconds: float) -> void:
	for tick in roundi(seconds / STEP):
		await physics_frame


func run() -> void:
	facility = preload("res://scenes/facility.tscn").instantiate()
	root.add_child(facility)
	current_scene = facility
	await physics_frame
	await physics_frame
	crane = facility.get("overhead_crane")
	await test_coverage()
	await test_motion()
	await test_unloaded_obstructions()
	await test_physical_suspension()
	await test_side_load_limit()
	await test_maintenance_trigger()
	facility.queue_free()
	await process_frame
	print("RD-015B bridge crane: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func test_coverage() -> void:
	var hall := crane.get_parent() as Node3D
	check(BridgeCrane.NOMINAL_CAPACITY_KG == 50000 and CraneSuspension.NOMINAL_BLOCK_MASS_KG == 225.0,
		"Nominal crane and hook capacities remain available as equipment specifications")
	check(is_equal_approx(crane.position.length(), 0.0), "Crane shares the hall's coordinate origin")
	check(crane.bridge.lower < 1.0 and crane.bridge.upper > hall.get("depth") - 1.0,
		"Rail travel spans nearly the entire hall length")
	check(crane.trolley.lower < -8.24 and crane.trolley.upper > 8.24,
		"Trolley travels nearly the full span")
	check(crane.rail_height >= 9.5 and crane.rail_height < 10.0, "Runway follows the specified elevation")
	test_moving_envelope(hall)
	check(crane.geometry.suspension_origin_y - crane.minimum_suspension_length > hall.get("deck_height") + 3.5,
		"Raised hook clears the usable mezzanine volume")
	var original := hall.transform
	hall.transform = Transform3D(Basis(Vector3.UP, PI / 3.0), Vector3(15, 1.5, -7.0))
	await reset_hook(crane.trolley.position, crane.bridge.position, crane.suspension.height)
	crane.set_controls(1.0, 1.0, false)
	await advance(0.25)
	crane.clear_controls()
	await advance(1.0)
	var local := hall.to_local(crane.hook_attachment().origin)
	check(absf(local.x - crane.trolley.position) < 0.12 and absf(local.z - crane.bridge.position) < 0.12
		and absf(local.y - crane.suspension.height) < 0.60, "The attachment is correctly transformed with a rotated hall")
	hall.transform = original
	await reset_hook(-1.5, 8.0, 5.75)


func test_moving_envelope(hall: Node3D) -> void:
	var geometry := crane.geometry
	var hall_inverse := hall.global_transform.affine_inverse()
	var obstacles: Array[AABB] = []
	var runway: Array[AABB] = []
	for group in ["Lighting", "Steelwork", "Mezzanine", "Shell"]:
		for obstacle: MeshInstance3D in hall.get_node(group).find_children("*", "MeshInstance3D", true, false):
			obstacles.append((hall_inverse * obstacle.global_transform) * obstacle.get_aabb())
	for obstacle: MeshInstance3D in geometry.get_node("Runways").find_children("*", "MeshInstance3D", true, false):
		runway.append((hall_inverse * obstacle.global_transform) * obstacle.get_aabb())

	geometry.pose(geometry.bridge_min, geometry.trolley_min, crane.suspension.height, 0)
	var uppermost := -INF
	for piece: MeshInstance3D in geometry.bridge.find_children("*", "MeshInstance3D", true, false):
		# The hook and chain use the independent suspension envelope. The chain is a MultiMeshInstance3D.
		if geometry.hook.is_ancestor_of(piece):
			continue
		var start := (hall_inverse * piece.global_transform) * piece.get_aabb()
		var finish := start
		var on_trolley := geometry.trolley.is_ancestor_of(piece)
		finish.position.z += geometry.bridge_max - geometry.bridge_min
		if on_trolley:
			finish.position.x += geometry.trolley_max - geometry.trolley_min
		var swept := start.merge(finish)
		uppermost = maxf(uppermost, swept.end.y)
		check(_clears(swept, obstacles), "%s clears the hall along its entire travel" % piece.name)
		# The bridge wheels intentionally contact the runway. The underhung trolley must clear it.
		if on_trolley:
			check(_clears(swept, runway), "%s clears both fixed runways" % piece.name)
	check(is_equal_approx(uppermost, crane.rail_height + CraneGeometry.PRESENTATION_TOP),
		"Declared moving envelope includes the actual uppermost truck or girder component")
	geometry.pose_suspended(crane.bridge.position, crane.trolley.position, crane.hook.global_transform)


func _clears(swept: AABB, obstacles: Array[AABB]) -> bool:
	for fixed in obstacles:
		var overlap := swept.intersection(fixed).size
		if minf(overlap.x, minf(overlap.y, overlap.z)) > 0.001:
			return false
	return true


func test_motion() -> void:
	var x := crane.trolley.position
	var z := crane.bridge.position
	crane.set_controls(1, 1, false)
	await advance(0.5)
	check(is_equal_approx(crane.trolley.velocity, crane.trolley_acceleration * 0.5)
		and is_equal_approx(crane.bridge.velocity, crane.bridge_acceleration * 0.5),
		"Both horizontal axes accelerate at their configured rates")
	check(crane.trolley.position > x and crane.bridge.position > z, "Both horizontal axes can move together")
	var v := crane.bridge.velocity
	crane.clear_controls()
	await advance(0.1)
	check(is_equal_approx(crane.bridge.velocity, v - crane.bridge_braking * 0.1), "Disconnect brakes progressively")
	await advance(1.0)
	z = crane.bridge.position
	x = crane.trolley.position
	await advance(0.5)
	check(crane.bridge.position == z and crane.trolley.position == x, "Idle bridge and trolley hold position")
	crane.set_controls(0, 1, false)
	await advance(0.30)
	check(absf(crane.hook.angular_velocity.y) > 0.01,
		"The offset unloaded block reacts passively to powered carriage acceleration")
	crane.clear_controls()
	await advance(0.75)

	crane.set_controls(-1, -1, true)
	await advance(1.0)
	check(is_equal_approx(crane.bridge.velocity, -crane.bridge_speed * crane.precision_multiplier)
		and is_equal_approx(crane.trolley.velocity, -crane.trolley_speed * crane.precision_multiplier),
		"Precision demand independently caps the two horizontal speeds")
	crane.clear_controls()
	await advance(0.5)
	var height := crane.suspension.height
	crane.adjust_hook_steps(4, false)
	check(is_equal_approx(crane.suspension.target, height + 0.40) and crane.suspension.height == height,
		"Discrete wheel steps accumulate on the target without teleporting the hook")
	await advance(0.1)
	check(crane.suspension.height > height and crane.suspension.height < height + 0.08,
		"Motor approaches the height target smoothly")
	await advance(2.0)
	crane.adjust_hook_steps(-1, true)
	check(is_equal_approx(crane.suspension.target, height + 0.39), "Fine wheel step is one centimeter")
	crane.adjust_hook_steps(1000, false)
	await advance(15.0)
	check(is_equal_approx(crane.suspension.length(), crane.minimum_suspension_length),
		"Commanded raise clamps to the minimum suspension length")
	crane.adjust_hook_steps(-1000, false)
	await advance(18.0)
	check(is_equal_approx(crane.suspension.height, crane.minimum_hook_height) and crane.suspension.velocity == 0.0,
		"Commanded lower clamps above the slab and holds")
	crane.adjust_hook_steps(30, false)
	await advance(0.5)
	crane.clear_controls()
	await advance(2.0)
	height = crane.suspension.height
	await advance(1.0)
	check(crane.suspension.height == height and crane.suspension.velocity == 0.0, "Remote release stops the hoist")
	var initial_yaw := crane.hook.global_rotation.y
	crane.hook.apply_torque_impulse(Vector3.UP * 12.0)
	await advance(1.0)
	check(angle_difference(initial_yaw, crane.hook.global_rotation.y) > 0.25 and crane.hook.angular_velocity.y < 1.0,
		"An applied impulse changes swivel angle with passive rotational damping")
	await advance(10.0)
	var resting_yaw := crane.hook.global_rotation.y
	await advance(2.0)
	check(angle_difference(initial_yaw, resting_yaw) > 0.35 and absf(angle_difference(resting_yaw, crane.hook.global_rotation.y)) < 0.02,
		"Hook holds the resulting free angle without self-alignment")


func reset_hook(x: float, z: float, height: float) -> void:
	crane.clear_controls()
	crane.trolley.position = x
	crane.bridge.position = z
	crane.trolley.velocity = 0.0
	crane.bridge.velocity = 0.0
	crane.suspension.height = height
	crane.suspension.velocity = 0.0
	crane.suspension.request_height(height)
	var transform_at := Transform3D(crane.global_basis, crane.to_global(Vector3(x, height, z)))
	crane.hook.global_transform = transform_at
	crane.hook.linear_velocity = Vector3.ZERO
	crane.hook.angular_velocity = Vector3.ZERO
	PhysicsServer3D.body_set_state(crane.hook.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, transform_at)
	await advance(0.10)


func test_unloaded_obstructions() -> void:
	await reset_hook(0.0, 21.0, 5.75)
	crane.adjust_hook_steps(-1000, false)
	await advance(6.5)
	var stopped := crane.to_local(crane.hook.global_position).y
	check(stopped >= 3.81 and stopped < 3.91 and crane.hook.slack_m > 0.40
		and crane.hook.tension_newtons < 1.0,
		"The physical hook rests on the mezzanine and does not apply compressive force")

	await reset_hook(0.0, 17.5, 3.75)
	crane.set_controls(0, 1, false)
	await advance(4.0)
	check(crane.to_local(crane.hook.global_position).z < 19.1 and absf(crane.bridge.velocity) < 0.12
		and rad_to_deg(crane.swing_angle()) < crane.maximum_angle_degrees + 1.0
		and crane.status_text().contains("HOOK PATH OBSTRUCTED"),
		"The hook and chain stop at the mezzanine guardrail")
	check(crane.maintenance.impact_count == 0, "Hook obstructions do not count as horizontal end-stop impacts")

	crane.adjust_hook_steps(1000, false)
	crane.set_controls(0, 1, true)
	await advance(7.0)
	check(crane.bridge.position > 20.0, "Raising above the obstacle restores bridge travel over the deck")
	await reset_hook(-1.5, 8.0, 7.97)


func test_physical_suspension() -> void:
	await reset_hook(0.0, 8.0, 7.2)
	var short_period := await swing_period()
	await reset_hook(0.0, 8.0, 4.0)
	var long_period := await swing_period()
	check(short_period > 2.0 and short_period < 3.1 and long_period > 3.6 and long_period < 5.5,
		"The simulated pendulum period increases with paid-out length")
	check(long_period > short_period * 1.50, "Cable swing emerges from gravity at both tested lengths")

	await reset_hook(0.0, 8.0, 2.2)
	crane.adjust_hook_steps(-200, false)
	await advance(4.0)
	var grounded := crane.to_local(crane.hook.global_position)
	check(grounded.y > 0.45 and grounded.y < 0.52 and crane.hook.get_contact_count() > 0,
		"The solid block settles on the hall floor")
	check(crane.hook.slack_m > 0.02 and crane.hook.tension_newtons < 1.0,
		"Paying chain onto the slab creates slack without tension")
	var actor := facility.get_node("Otis") as OtisController
	actor.global_position = crane.to_global(grounded + Vector3(0, -grounded.y + 0.03, 1.35))
	await advance(0.10)
	var contact := actor.move_and_collide(Vector3.FORWARD * 1.35, true)
	check(contact != null and contact.get_collider() == crane.hook, "Otis collides with the grounded hook block")
	actor.global_position = Vector3(0, 0.05, 4)

	await reset_hook(8.25, 4.75, 2.3)
	crane.adjust_hook_steps(-200, false)
	await advance(3.5)
	var saw_contact := crane.to_local(crane.hook.global_position).y
	check(saw_contact > 1.10 and saw_contact < 1.53 and crane.hook.get_contact_count() > 0,
		"The hook makes physical contact with bandsaw geometry")
	crane.adjust_hook_steps(25, false)
	await advance(3.10)
	check(crane.to_local(crane.hook.global_position).y > saw_contact + 1.1,
		"The hook raises away from equipment after creating slack")


func test_side_load_limit() -> void:
	await reset_hook(0.0, 8.0, 5.75)
	crane.hook.freeze = true
	crane.set_controls(1, 0, false)
	await advance(5.0)
	var limited := rad_to_deg(crane.swing_angle())
	check(limited > 27.0 and limited <= 30.05 and crane.trolley.velocity < 0.12,
		"A retained hook progressively inhibits outward carriage movement at the side-load limit")
	check(crane.status_text().contains("HOOK PATH OBSTRUCTED") and crane.maintenance.impact_count == 0,
		"Side-load limiting uses obstruction feedback without adding maintenance damage")
	crane.set_controls(-1, 0, false)
	await advance(0.6)
	check(rad_to_deg(crane.swing_angle()) < limited - 1.0, "The carriage can move inward to relieve side loading")
	crane.hook.freeze = false
	await reset_hook(0.0, 8.0, 5.75)
	crane.hook.freeze = true
	crane.set_controls(-1, -1, false)
	await advance(5.0)
	var diagonal := rad_to_deg(crane.swing_angle())
	check(diagonal > 27.0 and diagonal <= 30.05 and crane.trolley.position < -0.7 and crane.bridge.position < 7.3,
		"The 30-degree envelope also applies to combined axes in the opposite quadrant")
	crane.hook.freeze = false
	await reset_hook(-1.5, 8.0, 7.97)


func swing_period() -> float:
	var start := crane.hook.global_position.x
	crane.hook.apply_central_impulse(Vector3.RIGHT * crane.hook.mass * 0.70)
	var last := 0.0
	var zeroes := 0
	var peak := 0.0
	for tick in range(1, 420):
		await physics_frame
		var displacement := crane.hook.global_position.x - start
		peak = maxf(peak, absf(displacement))
		if last != 0.0 and displacement * last < 0.0:
			zeroes += 1
			if zeroes == 2:
				check(peak > 0.15, "Cable permits visible, gravity-responsive lateral movement")
				return tick * STEP
		last = displacement
	return 0.0


func test_maintenance_trigger() -> void:
	crane.maintenance.random.seed = 1501
	crane.adjust_hook_steps(90, false)
	await advance(14.0)
	await reset_hook(crane.trolley.upper - 0.18, 8.0, 7.97)
	crane.set_controls(1, 0, true)
	await advance(2.0)
	check(crane.trolley.position == crane.trolley.upper and crane.maintenance.impact_count == 0,
		"Low-speed stop contact counts zero qualifying impacts")
	await reset_hook(crane.trolley.upper - 3.5, 8.0, 7.97)
	crane.set_controls(-1, 0, false)
	await advance(0.45)
	crane.clear_controls()
	await advance(1.0)
	crane.set_controls(1, 0, false)
	await advance(5.0)
	check(crane.maintenance.impact_count == 1, "A high-speed boundary impact counts once")
	await advance(3.0)
	check(crane.maintenance.impact_count == 1, "Holding against the boundary does not repeat damage")
	for trip in 3:
		crane.set_controls(-1, 0, false)
		await advance(3.5)
		crane.set_controls(1, 0, false)
		await advance(7.0)
	check(not crane.maintenance.motion_allowed(&"trolley", -1.0),
		"Repeated directional impacts break the affected drive")
	var at := crane.trolley.position
	crane.set_controls(-1, 0, false)
	await advance(1.0)
	check(crane.trolley.position == at, "Broken trolley safely refuses motion")
	crane.clear_controls()
	var events := crane.maintenance.events
	check(events.size() == 1, "Only one maintenance incident fires while broken")
	if events.is_empty():
		return
	var event: Dictionary = events[0]
	var selected: Array = event.components
	check(event.axis == &"trolley" and event.side == 1 and event.speed >= crane.trolley_impact_speed,
		"Incident retains the qualifying axis, side, and pre-impact speed")
	check(selected.size() >= 3 and selected.size() <= 5 and _distinct(selected),
		"Incident selects three to five different components")
	check(selected[0] == &"trolley_drive_b", "A positive X impact prioritizes its right trolley drive")
	var severity_seen := false
	for id in selected:
		var part := crane.maintenance.component(id)
		check(part.smoke.emitting and part.sparks.emitting, "Local damage effects indicate " + String(id))
		if part.condition == MaintenanceComponent.Condition.DAMAGED:
			severity_seen = true
		check(part.repair().is_empty() and not part.smoke.emitting and not part.sparks.emitting,
			"Repair clears the fault effects for " + String(id))
	check(severity_seen, "The incident includes some impaired but unbroken components")
	check(crane.maintenance.motion_allowed(&"trolley", -1.0), "Repair restores trolley drive")
	var motor := crane.maintenance.component(&"hoist_motor")
	motor.apply_damage(MaintenanceComponent.Condition.DAMAGED, "Diagnostic")
	check(crane.maintenance.motion_allowed(&"hoist", 1.0), "A damaged motor remains functional")
	motor.apply_damage(MaintenanceComponent.Condition.BROKEN, "Diagnostic")
	check(not crane.maintenance.motion_allowed(&"hoist", 1.0) and crane.maintenance.motion_allowed(&"hoist", -1.0),
		"Broken hoist motor restricts raising only")
	motor.repair()
	var brake := crane.maintenance.component(&"hoist_brake")
	brake.apply_damage(MaintenanceComponent.Condition.BROKEN, "Diagnostic")
	var height := crane.suspension.height
	crane.adjust_hook_steps(-5, false)
	await advance(1.0)
	check(crane.suspension.height == height, "Brake failure holds the hook without uncontrolled lowering")
	brake.repair()


func _distinct(ids: Array) -> bool:
	var seen := {}
	for id in ids:
		seen[id] = true
	return seen.size() == ids.size()

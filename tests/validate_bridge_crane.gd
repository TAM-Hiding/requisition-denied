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
		crane._physics_process(STEP)


func run() -> void:
	facility = preload("res://scenes/facility.tscn").instantiate()
	root.add_child(facility)
	current_scene = facility
	await physics_frame
	await physics_frame
	crane = facility.get("overhead_crane")
	crane.set_physics_process(false)
	test_coverage()
	test_motion()
	test_unloaded_obstructions()
	test_maintenance_trigger()
	facility.queue_free()
	await process_frame
	print("RD-015A bridge crane: %d checks, %d failures" % [checks, failures])
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
	crane.set_controls(1.0, 1.0, false)
	advance(0.25)
	crane.clear_controls()
	advance(1.0)
	var local := hall.to_local(crane.hook_attachment().origin)
	check(is_equal_approx(local.x, crane.trolley.position) and is_equal_approx(local.z, crane.bridge.position)
		and absf(local.y - crane.suspension.height) < 0.60, "The attachment is correctly transformed with a rotated hall")
	hall.transform = original


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
	geometry.pose(crane.bridge.position, crane.trolley.position, crane.suspension.height, crane.suspension.swivel_yaw)


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
	advance(0.5)
	check(is_equal_approx(crane.trolley.velocity, crane.trolley_acceleration * 0.5)
		and is_equal_approx(crane.bridge.velocity, crane.bridge_acceleration * 0.5),
		"Both horizontal axes accelerate at their configured rates")
	check(crane.trolley.position > x and crane.bridge.position > z, "Both horizontal axes can move together")
	var v := crane.bridge.velocity
	crane.clear_controls()
	advance(0.1)
	check(is_equal_approx(crane.bridge.velocity, v - crane.bridge_braking * 0.1), "Disconnect brakes progressively")
	advance(1.0)
	z = crane.bridge.position
	x = crane.trolley.position
	advance(0.5)
	check(crane.bridge.position == z and crane.trolley.position == x, "Idle bridge and trolley hold position")
	crane.set_controls(0, 1, false)
	advance(0.30)
	check(absf(crane.suspension.swivel_velocity) > 0.01,
		"The offset unloaded block reacts passively to powered carriage acceleration")
	crane.clear_controls()
	advance(0.75)

	crane.set_controls(-1, -1, true)
	advance(1.0)
	check(is_equal_approx(crane.bridge.velocity, -crane.bridge_speed * crane.precision_multiplier)
		and is_equal_approx(crane.trolley.velocity, -crane.trolley_speed * crane.precision_multiplier),
		"Precision demand independently caps the two horizontal speeds")
	crane.clear_controls()
	advance(0.5)
	var height := crane.suspension.height
	crane.adjust_hook_steps(4, false)
	check(is_equal_approx(crane.suspension.target, height + 0.40) and crane.suspension.height == height,
		"Discrete wheel steps accumulate on the target without teleporting the hook")
	advance(0.1)
	check(crane.suspension.height > height and crane.suspension.height < height + 0.08,
		"Motor approaches the height target smoothly")
	advance(2.0)
	crane.adjust_hook_steps(-1, true)
	check(is_equal_approx(crane.suspension.target, height + 0.39), "Fine wheel step is one centimeter")
	crane.adjust_hook_steps(1000, false)
	advance(15.0)
	check(is_equal_approx(crane.suspension.length(), crane.minimum_suspension_length),
		"Commanded raise clamps to the minimum suspension length")
	crane.adjust_hook_steps(-1000, false)
	advance(18.0)
	check(is_equal_approx(crane.suspension.height, crane.minimum_hook_height) and crane.suspension.velocity == 0.0,
		"Commanded lower clamps above the slab and holds")
	crane.adjust_hook_steps(30, false)
	advance(0.5)
	crane.clear_controls()
	advance(2.0)
	height = crane.suspension.height
	advance(1.0)
	check(crane.suspension.height == height and crane.suspension.velocity == 0.0, "Remote release stops the hoist")
	var initial_yaw := crane.suspension.swivel_yaw
	crane.suspension.apply_swivel_impulse(12.0)
	advance(1.0)
	check(angle_difference(initial_yaw, crane.suspension.swivel_yaw) > 0.25 and crane.suspension.swivel_velocity < 1.0,
		"An applied impulse changes swivel angle with passive rotational damping")
	advance(10.0)
	var resting_yaw := crane.suspension.swivel_yaw
	advance(2.0)
	check(angle_difference(initial_yaw, resting_yaw) > 0.35 and resting_yaw == crane.suspension.swivel_yaw,
		"Hook holds the resulting free angle without self-alignment")


func test_unloaded_obstructions() -> void:
	var initial_bridge := crane.bridge.position
	var initial_trolley := crane.trolley.position
	crane.bridge.position = 20.0
	crane.trolley.position = 0.0
	crane.suspension.height = 5.75
	crane.suspension.request_height(5.75)
	crane.adjust_hook_steps(-1000, false)
	advance(6.5)
	var stopped := crane.suspension.height
	check(stopped >= 3.83 and stopped < 3.88 and crane.suspension.velocity == 0.0,
		"Unloaded hook stops just above the mezzanine deck instead of passing through")

	crane.bridge.position = 17.5
	crane.suspension.height = 2.6
	crane.suspension.request_height(2.6)
	crane.set_controls(0, 1, false)
	advance(4.0)
	check(crane.bridge.position > 18.5 and crane.bridge.position < 19.0
		and crane.status_text().contains("HOOK PATH OBSTRUCTED"),
		"A lowered suspension stops ahead of the deck envelope")
	check(crane.maintenance.impact_count == 0, "Hook obstructions do not count as horizontal end-stop impacts")

	crane.adjust_hook_steps(1000, false)
	advance(5.0)
	check(crane.bridge.position > 20.0, "Raising above the obstacle restores full bridge travel over the deck")
	crane.clear_controls()
	advance(1.5)
	crane.bridge.position = initial_bridge
	crane.trolley.position = initial_trolley


func test_maintenance_trigger() -> void:
	crane.maintenance.random.seed = 1501
	crane.adjust_hook_steps(90, false)
	advance(14.0)
	crane.trolley.position = crane.trolley.upper - 0.18
	crane.set_controls(1, 0, true)
	advance(2.0)
	check(crane.trolley.position == crane.trolley.upper and crane.maintenance.impact_count == 0,
		"Low-speed stop contact counts zero qualifying impacts")
	crane.trolley.position = crane.trolley.upper - 3.5
	crane.set_controls(-1, 0, false)
	advance(0.45)
	crane.clear_controls()
	advance(1.0)
	crane.set_controls(1, 0, false)
	advance(5.0)
	check(crane.maintenance.impact_count == 1, "A high-speed boundary impact counts once")
	advance(3.0)
	check(crane.maintenance.impact_count == 1, "Holding against the boundary does not repeat damage")
	for trip in 3:
		crane.set_controls(-1, 0, false)
		advance(3.5)
		crane.set_controls(1, 0, false)
		advance(7.0)
	check(not crane.maintenance.motion_allowed(&"trolley", -1.0),
		"Repeated directional impacts break the affected drive")
	var at := crane.trolley.position
	crane.set_controls(-1, 0, false)
	advance(1.0)
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
	advance(1.0)
	check(crane.suspension.height == height, "Brake failure holds the hook without uncontrolled lowering")
	brake.repair()


func _distinct(ids: Array) -> bool:
	var seen := {}
	for id in ids:
		seen[id] = true
	return seen.size() == ids.size()

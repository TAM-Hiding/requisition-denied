extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func frames(count: int) -> void:
	for frame in count:
		await physics_frame

func run() -> void:
	var facility := preload("res://scenes/facility.tscn").instantiate()
	facility.chassis_seed = 42
	root.add_child(facility)
	current_scene = facility
	var ui := facility.get_node("InteractionUI")
	ui.set_physics_process(false)
	var wrench := facility.get_node("Wrench") as InteractableObject
	var authored_wrench_pose := wrench.global_transform
	await frames(4)
	var otis := facility.get_node("Otis") as OtisController
	var spawn_clearance := PlacementClearance.new()
	spawn_clearance.configure(wrench)
	otis.global_position = Vector3(1.0, 0.02, 0.03)
	await frames(3)
	otis.camera.look_at(wrench.global_position)
	check(spawn_clearance.clear(authored_wrench_pose), "Authored service wrench spawn clears the generator and floor")
	check(otis.placement.begin_world(wrench), "Freshly settled service wrench can be grabbed")
	otis.placement.cancel()
	var generator := facility.get("generator") as MechanicalComponent
	var assembly := generator.get_node("Assembly") as MechanicalAssembly
	var panel_mount := assembly.mount(&"access_panel")
	var module_mount := assembly.mount(&"power_module")
	var panel := panel_mount.occupant
	var module := module_mount.occupant
	var anchors := generator.installed_mount
	var panel_id := panel.get_instance_id()
	var module_id := module.get_instance_id()
	var panel_collider: Shape3D = panel.get_node("CollisionShape3D").shape
	check(anchors.occupant == generator and generator.freeze
		and generator.definition.mobility == ObjectDefinition.Mobility.MOVABLE, "The fixed floor mount owns the movable housing")
	check(not anchors.remove().is_empty() and not generator.query_actions().has(&"remove"), "Floor anchors block ordinary removal")
	check(assembly.configuration() == MechanicalAssembly.Configuration.COMPLETE and assembly.available_stage() == 3, "Generator starts complete and operational")
	check(anchors.is_ancestor_of(module) and module_mount.get_parent() == assembly, "Floor mount contains the generator subassembly")
	check(generator.inspection_information().description.contains("Stage 3"), "Inspection exposes configured capability")
	check(module_mount.remove().contains("access_panel"), "Panel blocks module removal")

	var service := InteractionService.new()
	otis.position = Vector3(3.21, 0.01, -0.35)
	otis.camera.look_at(panel.global_position)
	await frames(4)
	check(service.permitted(otis, otis.camera, panel, 3.0), "The service panel can be targeted")
	ui.open_menu(panel)
	ui.perform_action(&"remove")
	check(not ui.menu_open and panel_mount.occupant == null and panel.get_parent() == facility and not panel.freeze,
		"Contextual Remove releases the same panel into the world")
	check(assembly.configuration() == MechanicalAssembly.Configuration.EXPOSED and assembly.available_stage() == 3, "Exposed generator can still supply Stage 3")
	await frames(35)
	# Move the loose cover clear of the bay's extraction corridor.
	panel.global_position.x -= 0.95
	await frames(3)
	otis.camera.look_at(module.global_position)
	await frames(4)
	ui.open_menu(module)
	ui.perform_action(&"remove")
	check(module_mount.occupant == null and module.installed_mount == null and not module.freeze, "Exposed module can be removed through the menu: " + ui.information.text)
	check(assembly.configuration() == MechanicalAssembly.Configuration.INCOMPLETE and assembly.available_stage() == 0, "Missing module disables generator capability")
	var basic := PowerConsumerDefinition.new()
	check(not assembly.supplies(basic), "Unavailable generator cannot supply Stage 1")

	# Clear the extraction corridor before putting unrelated cargo in the bay.
	module.global_position.x += 0.76
	module.linear_velocity = Vector3.ZERO
	# Close the empty mount around unrelated loose cargo, then clear it again.
	var cargo := facility.get_node("TestWeight") as InteractableObject
	cargo.global_transform = Transform3D(Basis.IDENTITY, module_mount.global_position + Vector3.DOWN * 0.20)
	cargo.linear_velocity = Vector3.ZERO
	cargo.sleeping = false
	await frames(25)
	panel.global_transform = panel_mount.global_transform
	panel.global_position.z += 0.035
	var panel_issue := panel_mount.install(panel)
	check(panel_issue.is_empty() and module_mount.occupant == null and assembly.available_stage() == 0,
		"Panel closes over loose cargo without granting generator power: " + panel_issue)
	check(panel_mount.remove().is_empty(), "Panel reopens to retrieve unrelated cargo")
	panel.global_position.x -= 0.95
	otis.position = Vector3(3.21, 0.01, -0.28)
	await frames(4)
	otis.camera.look_at(cargo.global_position)
	check(otis.placement.begin_world(cargo), "Loose cargo can be retrieved after opening the panel")
	if otis.placement.is_grabbing():
		cargo.global_position = Vector3(4.4, 0.14, 2.1)
		check(otis.placement.confirm(), "Cargo is placed outside the cabinet")
	check(module_mount.occupant == null and assembly.available_stage() == 0, "Removing cargo leaves the module mount vacant")

	# First place the module at a clear alignment through active world manipulation.
	await frames(35)
	otis.position = Vector3(3.21, 0.01, 0.2)
	otis.camera.look_at(module.global_position)
	await frames(4)
	check(otis.placement.begin_world(module), "Detached module enters precision manipulation")
	otis.placement.set_physics_process(false)
	module.global_transform = module_mount.global_transform
	check(otis.placement.confirm() and module_mount.occupant == null and assembly.available_stage() == 0,
		"Ordinary placement inside the bay leaves the module uninstalled")
	await frames(12)
	otis.camera.look_at(module.global_position)
	check(otis.placement.begin_world(module), "Loose module can be regrabbed inside the bay")
	otis.camera.look_at(otis.camera.global_position + Vector3.RIGHT)
	otis.placement.distance = 1.4
	module.global_transform = Transform3D(Basis.IDENTITY, otis.placement.target_position())
	otis.placement.set_rotating(true)
	for stroke in [Vector2(42, 21), Vector2(-13, 53), Vector2(35, -36)]:
		otis.placement.rotate_from_mouse(stroke)
		for frame in 12:
			otis.placement.update_preview(1.0 / 60.0)
	otis.placement.set_rotating(false)
	check(otis.placement.valid and not module.global_basis.is_equal_approx(Basis.IDENTITY),
		"Regrabbed module can be rotated freely before alignment and installation")
	module.global_transform = module_mount.global_transform
	module.global_position.z += 0.15
	var obstruction := facility.box(facility, "MountPathObstruction", Vector3(0.1, 0.1, 0.012),
		module_mount.global_position - Vector3.BACK * 0.155, null, true) as StaticBody3D
	await frames(2)
	check(otis.placement.installation_candidate() == module_mount and not otis.placement.install_grab()
		and otis.placement.is_active(), "A blocked snap keeps the target and original body")
	obstruction.queue_free()
	await frames(3)
	check(otis.placement.installation_candidate() == module_mount
		and otis.placement.installation_feedback(module_mount).is_empty(),
		"Aligned module offers Install from the clear front insertion approach")
	if DisplayServer.get_name() == "headless":
		check(otis.placement.install_grab(), "Explicit Install completes from manipulation")
	else:
		var press := InputEventAction.new()
		press.action = &"interact"
		press.pressed = true
		ui._input(press)
		check(otis.placement.is_seating(), "Contextual E routes to Install")
	check(otis.placement.is_seating() and module_mount.occupant == null and assembly.available_stage() == 0,
		"Generator remains unpowered while its module seats")
	otis.placement.advance_seating(0.21)
	check(not otis.placement.is_active() and module.freeze and module.installed_mount == module_mount
		and module.get_instance_id() == module_id and module.global_transform.is_equal_approx(module_mount.global_transform),
		"Install retains the body and snaps to the exact mount datum")
	check(assembly.available_stage() == 3 and assembly.supplies(basic), "Reinstalling the module restores output")
	module.integrity = MechanicalComponent.Integrity.BROKEN
	check(assembly.configuration() == MechanicalAssembly.Configuration.EXPOSED and not assembly.operational(),
		"Structural condition affects availability independently of occupancy")
	module.integrity = MechanicalComponent.Integrity.INTACT
	check(panel_mount.compatibility_error(facility.get_node("Wrench") as MechanicalComponent) != "", "Non-component is rejected")
	panel.global_transform = panel_mount.global_transform
	panel.global_position.z += 0.16
	check(String(panel_mount.alignment(panel).issue).contains("closer"), "Mount enforces position tolerance")
	panel.global_transform = panel_mount.global_transform.rotated_local(Vector3.BACK, deg_to_rad(20))
	panel.global_position.z += 0.03
	check(String(panel_mount.alignment(panel).issue).contains("Align"), "Mount enforces angular tolerance")
	panel.global_transform = panel_mount.global_transform
	panel.global_position.z += 0.04
	check(panel_mount.install(panel).is_empty(), "Panel can be reinstalled")
	check(panel.get_instance_id() == panel_id and panel.get_node("CollisionShape3D").shape == panel_collider
		and panel.global_transform.is_equal_approx(panel_mount.global_transform), "Panel identity, shape and attachment orientation persist")
	check(module_mount.remove().contains("access_panel") and assembly.configuration() == MechanicalAssembly.Configuration.COMPLETE,
		"Reinstalled panel restores the access dependency")

	var fixture := facility.get_node("MountTestFixture/Assembly") as MechanicalAssembly
	var battery_mount := fixture.mount(&"battery_socket")
	var battery := battery_mount.occupant
	var battery_id := battery.get_instance_id()
	var seated_clearance := PlacementClearance.new()
	seated_clearance.configure(battery)
	check(battery.freeze and seated_clearance.clear(battery.global_transform), "Battery begins seated in a clear bore")
	var pivot := fixture.mount(&"future_pivot")
	check(battery_mount.definition.position_tolerance < panel_mount.definition.position_tolerance, "Independent fixture uses different tolerances")
	check(not battery_mount.apply_impact(50.0) and battery_mount.occupant == battery, "Exact strength does not detach")
	check(battery_mount.apply_impact(50.01) and battery_mount.occupant == null and not battery.freeze, "Explicit threshold test detaches battery")
	check(battery_mount.definition.connection.failure_threshold == 50.0, "Failure does not mutate strength metadata")
	check(pivot.definition.connection.axis == Vector3.FORWARD and pivot.compatibility_error(battery).contains("not simulated"),
		"Revolute definition is authored without creating a functional joint")
	check(panel_mount.compatibility_error(battery).contains("occupied"), "Occupied mount rejects another body")
	check(module_mount.definition.connection.fails(400.0, true) and not module_mount.definition.connection.fails(400.0, false),
		"Condition modifier affects deterministic connection failure")
	check(panel_mount.remove().is_empty() and panel_mount.compatibility_error(battery).contains("Incompatible"),
		"Vacant socket rejects a component with the wrong tag")
	panel.global_transform = panel_mount.global_transform
	panel.global_position.z += 0.04
	check(panel_mount.install(panel).is_empty(), "Original panel reinstalls after compatibility check")

	for attempt in 3:
		battery.global_transform = battery_mount.global_transform
		battery.global_position.z += 0.03
		check(battery_mount.install(battery).is_empty() and battery.get_instance_id() == battery_id,
			"Fixture repeatedly installs the same battery")
		if attempt < 2:
			check(battery_mount.remove().is_empty(), "Fixture repeatedly releases the same battery")
		await frames(2)
	var owned_pose := battery.transform
	var base := fixture.get_parent() as Node3D
	base.position.x += 0.12
	check(battery.transform == owned_pose and battery.global_transform.is_equal_approx(battery_mount.global_transform),
		"Fixed attachment follows an ancestor transform")
	base.position.x -= 0.12
	check(battery_mount.remove().is_empty(), "Original battery can be replaced")
	battery.global_position.x += 0.6
	var replacement := facility.mechanical_part(facility.part_definition(&"RD-FIX-SPARE", "Test datum insert", 2.0),
		&"keyed_battery", Vector3(0.030, 0.030, 0.035), null) as MechanicalComponent
	replacement.profile.mating_transform = Transform3D(Basis(Vector3.UP, 0.12), Vector3(0.025, 0, 0))
	replacement.global_transform = battery_mount.global_transform * replacement.profile.mating_transform.affine_inverse()
	replacement.global_position.z += 0.03
	await frames(1)
	check(battery_mount.install(replacement).is_empty() and battery_mount.occupant == replacement
		and (replacement.global_transform * replacement.profile.mating_transform).is_equal_approx(battery_mount.global_transform)
		and battery.get_instance_id() == battery_id and battery.installed_mount == null,
		"Compatible replacement aligns a nonidentity mating datum and leaves the original body intact")
	check(anchors.occupant == generator and generator.freeze, "Assembly operations leave floor anchors intact")

	for stage in range(1, 4):
		var source := PowerSourceDefinition.new()
		source.stage = stage
		for requirement in range(1, 4):
			basic.required_stage = requirement
			check(source.can_supply(basic, true) == (stage >= requirement)
				and not source.can_supply(basic, false), "Stage %d availability for demand %d" % [stage, requirement])

	check(battery_mount.remove().is_empty(), "Test insert clears the keyed socket")
	replacement.queue_free()
	await frames(2)
	await grounded_and_focus(otis, ui, battery_mount, battery, facility.get_node("Crate"))
	await battery_and_tuning(facility, otis, battery_mount, battery, module, panel_mount, module_mount)

	await continuous_rotation(otis, wrench)
	if DisplayServer.get_name() != "headless":
		var workstation := facility.get_node("Terminal") as TerminalWorkstation
		var session: TerminalInteraction = facility.terminal_session
		otis.global_position = Vector3(0, 0.02, -4.10)
		await frames(2)
		otis.camera.look_at(workstation.global_position)
		check(session.enter() and not otis.controls_enabled and otis.placement.input_suspended
			and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "CRT settings own gameplay input and show the cursor")
		session.screen_ui.show_section("Settings")
		var preferences := session.screen_ui.settings_panel
		(preferences.toggles["invert_vertical"][1] as CheckBox).set_pressed(true)
		check(otis.placement.invert_vertical_rotation, "The CRT applies rotation preferences live")
		preferences.reset()
		session.leave()
		check(not session.active and otis.controls_enabled and not otis.placement.input_suspended
			and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "Closing settings restores mouse capture and gameplay")

	facility.queue_free()
	await process_frame
	print("RD-007: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func grounded_and_focus(otis: OtisController, ui: Node, socket: MechanicalMount,
		battery: MechanicalComponent, crate: InteractableObject) -> void:
	var placement := otis.placement
	var identity := battery.get_instance_id()
	var facility := otis.get_parent()
	var probe_body := facility.mechanical_part(facility.part_definition(&"RD-TEST-CONTACT", "Contact probe", 2.0),
		&"test", Vector3(0.33, 0.12, 0.29), null) as MechanicalComponent
	probe_body.global_position = Vector3(-2, 1, -2)
	var contact_clearance := PlacementClearance.new()
	contact_clearance.configure(probe_body)
	var cases := [
		Transform3D(Basis(Vector3.UP, 0.1628244), Vector3(-4.058261, 0.060767, -2.7)),
		Transform3D(Basis(Vector3.UP, -0.1301519), Vector3(-4.058175, 0.061064, -2.7)),
		Transform3D(Basis(Vector3.UP, 0.071304), Vector3(-4.066836, 0.060901, -2.7)),
	]
	for pose: Transform3D in cases:
		var probe := PhysicsTestMotionParameters3D.new()
		probe.from = pose
		probe.margin = 0.003
		probe.max_collisions = 8
		probe.recovery_as_collision = true
		var result := PhysicsTestMotionResult3D.new()
		PhysicsServer3D.body_test_motion(probe_body.get_rid(), probe, result)
		var recovered := pose
		recovered.origin += result.get_travel()
		var extracted := contact_clearance.pickup_pose(pose)
		check(not contact_clearance.clear(recovered) and contact_clearance.clear(extracted)
			and extracted.origin.distance_to(pose.origin) <= PlacementClearance.PICKUP_LIMIT,
			"Bounded outward sweep clears a fixture contact that recovery alone misses")
	var embedded := Transform3D(Basis.IDENTITY, Vector3(-4.12, 0.059, -2.7))
	check(not contact_clearance.clear(contact_clearance.pickup_pose(embedded)), "Deep obstruction cannot be recovered as a pickup")
	probe_body.queue_free()
	var battery_clearance := PlacementClearance.new()
	battery_clearance.configure(battery)
	var corner_basis := Basis(Vector3.UP, 0.495721) * Basis(Vector3.RIGHT, -0.007419)
	var corner := Transform3D(corner_basis, Vector3(-4.160743, 0.034265, -2.637913))
	var corner_extraction := battery_clearance.pickup_pose(corner, false, Vector3(0, 1.5, 1.3))
	check(battery_clearance.clear(corner_extraction)
		and corner_extraction.origin.distance_to(corner.origin) <= PlacementClearance.PICKUP_LIMIT,
		"Camera-side extraction recovers the battery from the fixture and floor contact")
	var floor_y := 0.039
	var samples := [
		Vector3(-3.3, floor_y, -2.7),
		Vector3(-4.184, floor_y, -2.7),
		Vector3(-5.951, floor_y, -2.0),
		Vector3(-5.017, floor_y, -2.7),
	]
	for index in samples.size():
		var point: Vector3 = samples[index]
		battery.global_transform = Transform3D(Basis.IDENTITY, point)
		battery.linear_velocity = Vector3.ZERO
		battery.angular_velocity = Vector3.ZERO
		battery.sleeping = true
		otis.global_position = Vector3(point.x, 0.02, point.z + 1.1)
		otis.camera.look_at(battery.global_position)
		await frames(3)
		var resting := battery.global_position
		otis.camera.look_at(resting)
		check(placement.begin_world(battery), "Can pick up battery from floor/contact sample %d" % index)
		if placement.is_grabbing():
			check(battery.get_instance_id() == identity and battery.global_position.distance_to(resting) <= 0.026,
				"Pickup remains local and retains the battery")
			placement.cancel()
	battery.global_transform = Transform3D(Basis.IDENTITY, Vector3(-3.5, 0.10, -2.1))
	otis.global_position = Vector3(-3.5, 0.02, -0.9)
	otis.camera.look_at(battery.global_position)
	await frames(3)
	otis.camera.look_at(battery.global_position)
	check(placement.begin_world(battery), "Can reacquire battery after prior cancellations")
	if not placement.is_grabbing():
		return
	placement.set_physics_process(true)
	placement.press_drop(1000000)
	placement.set_rotating(true)
	placement.rotate_from_mouse(Vector2(35, 10))
	var pose := battery.global_transform
	ui._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	var key_up := InputEventAction.new()
	key_up.action = &"drop_item"
	key_up.pressed = false
	ui._input(key_up)
	await frames(5)
	check(placement.input_suspended and not placement.rotating and battery.freeze
		and battery.get_instance_id() == identity and battery.global_transform == pose,
		"Focus loss holds the exact pose and discards pending movement and key-up")
	check(not placement.install_grab() and socket.occupant == null, "Focus suspension cannot install")
	ui._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	ui._input(key_up)
	check(placement.is_grabbing() and not placement.input_suspended, "Focus return ignores stale G release")
	placement.adjust_distance(3)
	await frames(12)
	check(battery.global_position.distance_to(pose.origin) > 0.06, "Placement can continue after focus returns")

	placement.set_physics_process(false)
	var destination := socket.global_transform * battery.profile.mating_transform.affine_inverse()
	battery.global_transform = destination
	battery.global_position.z += 0.25
	check(placement.installation_candidate() == socket and not placement.installation_feedback(socket).is_empty()
		and not placement.install_grab() and placement.is_grabbing(), "Acquisition is wider than positional snap tolerance")
	battery.global_transform = destination.rotated_local(Vector3.UP, deg_to_rad(45.0))
	battery.global_position.z += 0.16
	check(placement.installation_candidate() == socket and placement.installation_feedback(socket).contains("Align"),
		"Acquired misaligned mount explains the orientation requirement")
	battery.global_transform = destination
	battery.global_position.z += 0.03
	check(placement.install_grab() and socket.occupant == null, "Install starts without registering the connection")
	placement.advance_seating(0.21)
	check(socket.occupant == battery and not placement.is_active(),
		"Install after focus interruption and failed alignment preserves the same battery")
	otis.global_position = Vector3(crate.global_position.x, 0.02, crate.global_position.z + 2.1)
	otis.camera.look_at(crate.global_position)
	await frames(3)
	check(placement.begin_world(crate), "A different body can be grabbed after installation")
	ui._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	ui._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	placement.cancel()
	check(not placement.is_active() and not crate.freeze, "Explicit cancellation still releases after a focus cycle")


func continuous_rotation(otis: OtisController, wrench: InteractableObject) -> void:
	var placement := otis.placement
	placement.set_physics_process(false)
	for iteration in 8:
		var point := Vector3(1.644 - 0.001 * (iteration % 4), 0.039, -2.5)
		wrench.global_transform = Transform3D(Basis.IDENTITY, point)
		wrench.linear_velocity = Vector3.ZERO
		wrench.angular_velocity = Vector3.ZERO
		wrench.sleeping = iteration % 2 == 0
		otis.global_position = Vector3(0.55, 0.02, -2.5)
		await frames(2)
		otis.camera.look_at(wrench.global_position)
		check(placement.begin_world(wrench), "Repeated wrench pickup beside generator, iteration %d" % iteration)
		if placement.is_grabbing():
			check(placement.confirm(), "Repeated generator-side placement restores physics")
	otis.global_position = Vector3(0, 0.02, 2.0)
	wrench.global_transform = Transform3D(Basis.IDENTITY, Vector3(0, 0.05, 0.8))
	wrench.sleeping = true
	await frames(2)
	otis.camera.look_at(wrench.global_position)
	check(placement.begin_world(wrench), "Wrench can be grabbed before continuous rotation")
	if not placement.is_grabbing():
		return
	otis.camera.look_at(otis.camera.global_position + Vector3.FORWARD)
	placement.distance = 1.4
	var neutral := Transform3D(Basis.IDENTITY, placement.target_position())
	for drag in [Vector2(22, 0), Vector2(0, 22), Vector2(-22, 0)]:
		wrench.global_transform = neutral
		placement.set_rotating(true)
		var axis := Vector3.UP if drag.y == 0 else Vector3.RIGHT
		var expected_direction := signf(drag.x if drag.y == 0 else drag.y)
		var accumulated := 0.0
		var uninterrupted := true
		for step in 280:
			var before := wrench.global_basis.get_rotation_quaternion()
			placement.rotate_from_mouse(drag)
			placement.update_preview(1.0 / 60.0)
			var after := wrench.global_basis.get_rotation_quaternion()
			var change := (after * before.inverse()).normalized()
			if change.w < 0.0:
				change = -change
			var turn := change.get_angle()
			uninterrupted = uninterrupted and turn > 0.005 and change.get_axis().dot(axis) * expected_direction > 0.99
			accumulated += turn
		check(uninterrupted and accumulated > TAU * 3.0, "One uninterrupted drag completes more than three revolutions: " + str(drag))
		check(placement.valid and wrench.global_basis.is_equal_approx(wrench.global_basis.orthonormalized()),
			"Continuous turns retain a valid orthonormal orientation")
	for invert in [Vector2(0, 0), Vector2(1, 0), Vector2(0, 1), Vector2(1, 1)]:
		placement.invert_horizontal_rotation = invert.x != 0.0
		placement.invert_vertical_rotation = invert.y != 0.0
		placement.set_rotating(true)
		wrench.global_transform = neutral
		placement.rotate_from_mouse(Vector2(14, 14))
		placement.update_preview(1.0 / 60.0)
		var axis := wrench.global_basis.get_rotation_quaternion().get_axis()
		check(signf(axis.x) == (1.0 if invert.y == 0.0 else -1.0)
			and signf(axis.y) == (1.0 if invert.x == 0.0 else -1.0), "Independent input inversion: " + str(invert))
	placement.invert_horizontal_rotation = false
	placement.invert_vertical_rotation = false
	check(placement.confirm(), "Compound orientation can be placed")
	await frames(40)
	otis.camera.look_at(wrench.global_position)
	check(placement.begin_world(wrench), "Wrench can be regrabbed after arbitrary placement")
	placement.cancel()

func battery_and_tuning(facility: Node3D, otis: OtisController, socket: MechanicalMount,
		battery: MechanicalComponent, module: MechanicalComponent, panel_mount: MechanicalMount,
		module_mount: MechanicalMount) -> void:
	var placement := otis.placement
	var settings := placement.mechanical_settings
	var id := battery.get_instance_id()
	check(socket.occupant == battery and socket.definition.keyed, "Battery is seated in a keyed socket")
	check(socket.remove().is_empty(), "Battery extracts through the physical socket")
	var seat := socket.global_transform
	var approach := seat.translated(Vector3.BACK * 0.17)
	otis.global_position = Vector3(-4.6, 0.02, -0.87)
	battery.global_transform = approach
	await frames(2)
	battery.global_transform = approach
	otis.camera.look_at(battery.global_position)
	await frames(1)
	check(placement.begin_world(battery), "Battery can enter precision manipulation")
	if not placement.is_grabbing():
		return
	battery.global_transform = approach.rotated_local(Vector3.UP, PI)
	check(placement.installation_feedback(socket).contains("insertion axis"), "Wrong-end insertion is rejected")
	battery.global_transform = approach.rotated_local(Vector3.BACK, deg_to_rad(45))
	check(placement.installation_feedback(socket).contains("key"), "Incorrect roll is rejected independently of axis")
	var candidate := settings.values.duplicate(true)
	candidate.installation.key_rotation_tolerance_degrees = 50.0
	check(settings.apply(candidate).is_empty() and placement.installation_feedback(socket).is_empty(),
		"Wider key tolerance takes effect on the next request")
	battery.global_transform = approach.rotated_local(Vector3.UP, deg_to_rad(35))
	check(placement.installation_feedback(socket).contains("axis"), "Default insertion-axis tolerance applies")
	candidate.installation.axis_tolerance_degrees = 40.0
	check(settings.apply(candidate).is_empty() and placement.installation_feedback(socket).is_empty(),
		"Wider axis tolerance takes effect on the next request")
	battery.global_transform = approach
	candidate.installation.snap_distance_m = 0.12
	check(settings.apply(candidate).is_empty() and placement.installation_candidate() == socket
		and placement.installation_feedback(socket).contains("closer"), "Snap distance is separate from acquisition")
	candidate.installation.acquisition_distance_m = 0.14
	check(settings.apply(candidate).is_empty() and placement.installation_candidate() == null,
		"Acquisition distance changes the candidate without changing compatibility")
	settings.reset()
	check(placement.installation_candidate() == socket and placement.installation_feedback(socket).is_empty(),
		"Defaults restore the snap distance and candidate")
	var blocker := facility.call("box", facility, "KeyedSweepBlocker", Vector3(0.03, 0.03, 0.012),
		seat.origin + Vector3.BACK * 0.12, null, true) as StaticBody3D
	await frames(2)
	check(placement.installation_feedback(socket).contains("blocked") and not placement.install_grab(),
		"Solid geometry between clear endpoints blocks battery installation")
	blocker.queue_free()
	await frames(2)
	battery.global_transform = approach.rotated_local(Vector3.BACK, deg_to_rad(25))
	check(placement.installation_feedback(socket).is_empty(), "Correct insertion end and approximate key alignment are assisted")
	candidate = settings.values.duplicate(true)
	candidate.installation.snap_duration_seconds = 0.40
	check(settings.apply(candidate).is_empty() and placement.install_grab(), "Explicit install starts animated seating")
	check(socket.pending == battery and socket.occupant == null and not placement.install_grab() and not placement.confirm(),
		"Pending seating is exclusive and ordinary placement cannot bypass it")
	placement.advance_seating(0.17)
	check(socket.occupant == null and placement.is_seating() and battery.global_position.distance_to(seat.origin) < 0.17,
		"Battery visibly moves before the functional connection exists")
	settings.reset()
	placement.advance_seating(0.04)
	check(socket.occupant == null, "Live tuning cannot shorten an ongoing animation")
	placement.advance_seating(0.20)
	check(socket.occupant == battery and battery.get_instance_id() == id
		and battery.global_transform.is_equal_approx(seat), "Seating completes with the exact datum and identity")
	check(socket.remove().is_empty(), "Same battery can be removed again")
	battery.global_transform = approach
	await frames(1)
	otis.camera.look_at(battery.global_position)
	check(placement.begin_world(battery) and placement.install_grab(), "Repeated explicit seating starts")
	var moving_blocker := facility.call("box", facility, "LateSeatBlocker", Vector3(0.03, 0.03, 0.012),
		seat.origin + Vector3.BACK * 0.12, null, true) as StaticBody3D
	await frames(2)
	placement.advance_seating(0.20)
	check(not placement.is_seating() and placement.is_grabbing() and socket.pending == null
		and socket.occupant == null and battery.get_instance_id() == id,
		"A blocker entering after confirmation interrupts seating and retains control")
	moving_blocker.queue_free()
	await frames(2)
	check(placement.install_grab(), "Clearing an interrupted path permits another attempt")
	placement.cancel()
	check(socket.pending == null and socket.occupant == null and not battery.freeze
		and battery.get_instance_id() == id, "Cancellation clears reservation and releases the same live body")

	var file := "user://rd007_test_%d.json" % Time.get_ticks_usec()
	candidate = settings.values.duplicate(true)
	candidate.installation.snap_distance_m = 0.24
	candidate.rotation.invert_vertical = true
	check(settings.apply(candidate).is_empty() and settings.save_file(file).is_empty(), "Runtime values save as JSON")
	var from_disk := MechanicalInteractionSettings.new()
	check(from_disk.load_file(file).is_empty() and is_equal_approx(from_disk.values.installation.snap_distance_m, 0.24)
		and from_disk.values.rotation.invert_vertical, "New settings instance restores saved values")
	var snapshot := settings.export_snapshot()
	settings.reset()
	check(not snapshot.is_empty() and settings.load_file(snapshot).is_empty()
		and settings.values.rotation.invert_vertical, "Timestamped snapshot exports and imports")
	var invalid := candidate.duplicate(true)
	invalid.schema_version = 99
	check(settings.apply(invalid).contains("Unsupported"), "Unknown schema reports a validation error")
	invalid.schema_version = 1
	invalid.installation.snap_distance_m = INF
	check(settings.apply(invalid).contains("finite"), "Non-finite numeric setting is rejected")
	invalid.installation.snap_distance_m = 0.50
	check(not settings.apply(invalid).is_empty(), "Out-of-range numeric setting is rejected")
	var broken := FileAccess.open(file, FileAccess.WRITE)
	broken.store_string("{ malformed")
	broken.close()
	check(settings.load_file(file).contains("Invalid JSON") and settings.values.rotation.invert_vertical,
		"Malformed JSON reports the failure and leaves active settings intact")
	DirAccess.remove_absolute(file)
	if not snapshot.is_empty():
		DirAccess.remove_absolute(snapshot)
	settings.reset()

	var cover := panel_mount.occupant
	check(panel_mount.remove().is_empty(), "Cover can be removed before the plate pickup test")
	cover.global_position.x -= 1.0
	check(module_mount.remove().is_empty(), "Module can be removed for repeated plate pickups")
	var plate_clearance := PlacementClearance.new()
	plate_clearance.configure(module)
	var resting_pose := Transform3D(Basis.IDENTITY, Vector3(2.7, 0.2455, 1.4))
	check(plate_clearance.physically_clear(resting_pose) and not plate_clearance.clear(resting_pose),
		"A supported pose may be physically clear while inside the preview margin")
	check(plate_clearance.clear(plate_clearance.depart_resting_pose(resting_pose, Vector3.UP * 0.05))
		and plate_clearance.depart_resting_pose(resting_pose, Vector3.DOWN).is_equal_approx(resting_pose),
		"Resting departure can lift the module but cannot enter the supporting floor")
	for iteration in 5:
		module.global_transform = Transform3D(Basis(Vector3.UP, 0.19 * iteration), Vector3(2.7, 0.26, 1.4))
		module.linear_velocity = Vector3.ZERO
		module.angular_velocity = Vector3.ZERO
		module.sleeping = false
		otis.global_position = Vector3(2.7, 0.02, 2.7)
		await frames(24)
		otis.camera.look_at(module.global_position)
		check(placement.begin_world(module), "Settled module can be retrieved from pressure plate, cycle %d" % iteration)
		if placement.is_grabbing():
			check(placement.confirm(), "Retrieved module can be placed back on the plate")

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
	root.add_child(facility)
	current_scene = facility
	var ui := facility.get_node("InteractionUI")
	ui.set_physics_process(false)
	await frames(4)
	var otis := facility.get_node("Otis") as OtisController
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

	# First place the module at a clear alignment through active world manipulation.
	await frames(35)
	otis.position = Vector3(3.21, 0.01, 0.2)
	otis.camera.look_at(module.global_position)
	await frames(4)
	check(otis.placement.begin_world(module), "Detached module enters precision manipulation")
	otis.placement.set_physics_process(false)
	module.global_transform = module_mount.global_transform
	module.global_position.z += 0.045
	var obstruction := facility.box(facility, "MountPathObstruction", Vector3(0.1, 0.1, 0.012),
		module_mount.global_position - Vector3.BACK * 0.155, null, true) as StaticBody3D
	await frames(2)
	check(otis.placement.installation_candidate() == null and not otis.placement.install_grab()
		and otis.placement.is_active(), "A blocked snap neither offers Install nor releases the original body")
	obstruction.queue_free()
	await frames(3)
	check(otis.placement.installation_candidate() == module_mount, "Aligned module offers contextual Install")
	if DisplayServer.get_name() == "headless":
		check(otis.placement.install_grab(), "Explicit Install completes from manipulation")
	else:
		var press := InputEventAction.new()
		press.action = &"interact"
		press.pressed = true
		ui._input(press)
		check(not otis.placement.is_active(), "Contextual E routes to Install")
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
	check(panel_mount.alignment_error(panel).contains("closer"), "Mount enforces position tolerance")
	panel.global_transform = panel_mount.global_transform.rotated_local(Vector3.BACK, deg_to_rad(20))
	panel.global_position.z += 0.03
	check(panel_mount.alignment_error(panel).contains("Align"), "Mount enforces angular tolerance")
	panel.global_transform = panel_mount.global_transform
	panel.global_position.z += 0.04
	check(panel_mount.install(panel).is_empty(), "Panel can be reinstalled")
	check(panel.get_instance_id() == panel_id and panel.get_node("CollisionShape3D").shape == panel_collider
		and panel.global_transform.is_equal_approx(panel_mount.global_transform), "Panel identity, shape and attachment orientation persist")
	check(module_mount.remove().contains("access_panel") and assembly.configuration() == MechanicalAssembly.Configuration.COMPLETE,
		"Reinstalled panel restores the access dependency")

	var fixture := facility.get_node("MountTestFixture/Assembly") as MechanicalAssembly
	var bracket_mount := fixture.mount(&"fixture_bracket")
	var bracket := bracket_mount.occupant
	var bracket_id := bracket.get_instance_id()
	var pivot := fixture.mount(&"future_pivot")
	check(bracket_mount.definition.position_tolerance < panel_mount.definition.position_tolerance, "Independent fixture uses different tolerances")
	check(not bracket_mount.apply_impact(50.0) and bracket_mount.occupant == bracket, "Exact strength does not detach")
	check(bracket_mount.apply_impact(50.01) and bracket_mount.occupant == null and not bracket.freeze, "Explicit threshold test detaches bracket")
	check(bracket_mount.definition.connection.failure_threshold == 50.0, "Failure does not mutate strength metadata")
	check(pivot.definition.connection.axis == Vector3.FORWARD and pivot.compatibility_error(bracket).contains("not simulated"),
		"Revolute definition is authored without creating a functional joint")
	check(panel_mount.compatibility_error(bracket).contains("occupied"), "Occupied mount rejects another body")
	check(module_mount.definition.connection.fails(400.0, true) and not module_mount.definition.connection.fails(400.0, false),
		"Condition modifier affects deterministic connection failure")
	check(panel_mount.remove().is_empty() and panel_mount.compatibility_error(bracket).contains("Incompatible"),
		"Vacant socket rejects a component with the wrong tag")
	panel.global_transform = panel_mount.global_transform
	panel.global_position.z += 0.04
	check(panel_mount.install(panel).is_empty(), "Original panel reinstalls after compatibility check")

	for attempt in 3:
		bracket.global_transform = bracket_mount.global_transform
		bracket.global_position.y += 0.02
		check(bracket_mount.install(bracket).is_empty() and bracket.get_instance_id() == bracket_id,
			"Fixture repeatedly installs the same bracket")
		if attempt < 2:
			check(bracket_mount.remove().is_empty(), "Fixture repeatedly releases the same bracket")
		await frames(2)
	var owned_pose := bracket.transform
	var base := fixture.get_parent() as Node3D
	base.position.x += 0.12
	check(bracket.transform == owned_pose and bracket.global_transform.is_equal_approx(bracket_mount.global_transform),
		"Fixed attachment follows an ancestor transform")
	check(bracket_mount.remove().is_empty(), "Original bracket can be replaced")
	bracket.global_position.x += 0.6
	var replacement := facility.mechanical_part(facility.part_definition(&"RD-FIX-SPARE", "Spare bracket", 2.0),
		&"fixture_bracket", Vector3(0.33, 0.12, 0.29), null) as MechanicalComponent
	replacement.profile.mating_transform = Transform3D(Basis(Vector3.UP, 0.12), Vector3(0.025, 0, 0))
	replacement.global_transform = bracket_mount.global_transform * replacement.profile.mating_transform.affine_inverse()
	replacement.global_position.y += 0.02
	await frames(1)
	check(bracket_mount.install(replacement).is_empty() and bracket_mount.occupant == replacement
		and (replacement.global_transform * replacement.profile.mating_transform).is_equal_approx(bracket_mount.global_transform)
		and bracket.get_instance_id() == bracket_id and bracket.installed_mount == null,
		"Compatible replacement aligns a nonidentity mating datum and leaves the original body intact")
	check(anchors.occupant == generator and generator.freeze, "Assembly operations leave floor anchors intact")

	for stage in range(1, 4):
		var source := PowerSourceDefinition.new()
		source.stage = stage
		for requirement in range(1, 4):
			basic.required_stage = requirement
			check(source.can_supply(basic, true) == (stage >= requirement)
				and not source.can_supply(basic, false), "Stage %d availability for demand %d" % [stage, requirement])

	facility.queue_free()
	await process_frame
	print("RD-007: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

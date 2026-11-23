extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(description)

func frames(count: int = 2) -> void:
	for i in count:
		await physics_frame

func run() -> void:
	var facility = preload("res://scenes/facility.tscn").instantiate()
	facility.chassis_seed = 42
	root.add_child(facility)
	current_scene = facility
	var supply: ScrapSupply = facility.scrap_supply
	var actor: OtisController = facility.get_node("Otis")
	var tool: FasteningTool = facility.bolt_tool
	var system: FasteningSystem = facility.fastening
	var rack: InteractableObject = facility.get_node("DevelopmentScrapRack")
	var rack_session: TerminalInteraction = facility.scrap_session
	var ui = facility.get_node("InteractionUI")
	await frames(4)
	var original_stock := supply.catalog.filter(func(entry: Dictionary) -> bool:
		return not entry.get("industrial", false))
	check(original_stock.size() == 27 and supply.catalog.slice(0, original_stock.size()) == original_stock,
		"27 original stock variants retain their registration and order")
	for obsolete in ["SteelPlate", "AngleBracket", "LongAngle", "SteelBar", "TriangularGusset"]:
		check(facility.get_node_or_null(obsolete) == null, "Obsolete chamber fixture removed: " + obsolete)
	var all_ids := {}
	for index in original_stock.size():
		var data := supply.catalog[index]
		var part := supply.dispense(index)
		check(part != null and data.mass > 0.0 and data.size.is_finite(), "Dispense valid " + data.title)
		if part == null:
			continue
		check(part.get_node("CollisionShape3D").shape != null and not part.freeze
			and part.query_actions().has(&"inspect") and part.query_actions().has(&"move")
			and not all_ids.has(part.definition.object_id), "Part moves and inspects with independent identity")
		all_ids[part.definition.object_id] = true
		check(supply.dispense(index) == null, "Same-frame dispense does not overlap")
		if data.category in ["Round tubing", "Square tubing"]:
			await frames(2)
			var axis_start: Vector3 = part.global_position - Vector3.RIGHT * (data.size.x * 0.49)
			var bore := system.cast(axis_start, axis_start + Vector3.RIGHT * (data.size.x * 0.98))
			check(bore.is_empty(), "Tubing retains a clear axial bore")
		if data.category == "Round tubing":
			check_round_tube(part, supply, index)
			part.freeze = true
			part.global_transform = Transform3D(Basis(Vector3.UP, PI / 3.0), supply.delivery)
			system.sync_body_transform(part)
			await frames(2)
			var next_id := supply.next_id
			check(supply.dispense(index) == null and supply.next_id == next_id,
				"Rotated compound stock blocks an overlapping delivery on a later physics frame")
		part.queue_free()
		await frames(2)

	actor.global_position = supply.delivery * Vector3(1, 0, 1) + Vector3.UP * 0.02
	await frames()
	check(supply.dispense(0) == null, "Otis blocks deliveries")
	actor.global_position = Vector3(-4.80, 0.02, 4.05)
	await frames()
	actor.camera.look_at(rack.global_position)
	check(rack_session.enter() and not actor.controls_enabled and actor.placement.input_suspended,
		"Rack opens and owns gameplay input")
	var panel := rack_session.scrap_panel
	check(panel.stock.item_count == supply.catalog.size(), "Rack UI lists the catalog")
	panel.dispense_selected()
	await frames(2)
	var first := facility.get_node_or_null("Scrap_28") as InteractableObject
	check(first != null and panel.feedback.text.begins_with("Dispensed"), "The UI dispenses a part")
	panel.dispense_selected()
	check(panel.feedback.text == "REQUISITION DENIED — DELIVERY AREA OBSTRUCTED", "Existing stock blocks delivery")
	rack_session.leave()
	if first == null:
		quit(1)
		return
	first.gravity_scale = 0
	first.global_position = Vector3(2.0, 1.1, 3.425)
	await frames()
	var second := supply.dispense(0)
	check(second != null and second != first and second.definition != first.definition, "Rack replenishes the same stock")
	if second == null:
		quit(1)
		return
	await frames()
	second.gravity_scale = 0
	first.global_transform = Transform3D(Basis.IDENTITY, Vector3(2.0, 1.13, 3.45))
	second.global_transform = Transform3D(Basis.IDENTITY, Vector3(2.0, 1.05, 3.45))
	first.linear_velocity = Vector3.ZERO
	second.linear_velocity = Vector3.ZERO
	await frames(5)
	var bolt := system.create_round(FasteningTool.GRADES[0])
	var issue := system.install(bolt, Vector3(2.0, 2.0, 3.45), Vector3.DOWN, 2.0)
	check(issue.is_empty() and first.fastened and second.fastened, "Two dispensed flat bars form a movable assembly: " + issue)

	var held := supply.dispense(1)
	check(held != null, "Held test stock available")
	if held == null:
		quit(1)
		return
	actor.global_position = Vector3(-4.7, 0.02, 3.82)
	await frames()
	actor.camera.look_at(held.global_position)
	check(actor.placement.begin_world(held), "Stock supports normal precision pickup")
	actor.placement.set_input_suspended(true)
	held.global_position = Vector3(-3.6, 0.8, 4.2)
	await frames()
	var loose := supply.dispense(2)
	var preferences: MechanicalSettingsPanel = facility.terminal_session.screen_ui.settings_panel
	preferences.request_cleanup()
	check(is_instance_valid(loose) and not loose.is_queued_for_deletion(), "Cleanup requires confirmation")
	preferences.request_cleanup()
	await frames()
	check(not is_instance_valid(loose) and is_instance_valid(first) and is_instance_valid(second)
		and is_instance_valid(held) and is_instance_valid(facility.get_node("Crate"))
		and is_instance_valid(tool)
		and is_instance_valid(rack) and supply.clear_loose() == 0, "Cleanup keeps assemblies, held stock and permanent fixtures")
	actor.placement.set_input_suspended(false)
	actor.placement.cancel()

	check(tool.removal_behavior == "Timed" and tool.removal_seconds == 5.0, "Timed is the five-second default")
	tool.removal_input(true)
	tool.update_removal(4.0, true)
	tool.update_removal(10.0, false)
	check(tool.removing and is_equal_approx(tool.removal_remaining, 1), "Suspended input pauses the timer")
	actor.global_position = Vector3(2.0, 0.02, 2.7)
	await frames()
	if bolt.state == InstalledFastener.State.INSTALLED:
		actor.camera.look_at(bolt.head())
		check(tool.use(actor.camera, actor).begins_with("RECOVERED") and is_equal_approx(tool.removal_remaining, 5),
			"Successful recovery resets the timer")
	tool.update_removal(5.0, true)
	check(not tool.removing, "Timer returns automatically to install")
	tool.configure_removal("Toggle", 5)
	tool.removal_input(true)
	tool.removal_input(false)
	tool.update_removal(20, true)
	check(tool.removing, "Toggle remains latched")
	tool.removal_input(true)
	check(not tool.removing, "Second toggle returns to install")
	tool.configure_removal("Hold", 5)
	tool.removal_input(true)
	check(tool.removing, "R press enters hold mode")
	tool.removal_input(false)
	check(not tool.removing, "R release ends hold mode")
	tool.removal_input(true)
	tool.update_removal(0, false)
	check(not tool.removing, "A terminal or focus loss cannot leave hold mode stuck")
	check(InputMap.action_get_events("tool_grade")[0].physical_keycode == KEY_V
		and InputMap.action_get_events("tool_replenish")[0].physical_keycode == KEY_B, "V and B are bound")
	check(actor.equipment.pick_up(tool).ok, "Tool available for input test")
	var grade := tool.grade_index
	var event := InputEventKey.new()
	event.physical_keycode = KEY_V
	event.pressed = true
	check(ui.handle_fastening_input(event) and tool.grade_index == (grade + 1) % 3
		and tool.hud_text().contains(tool.GRADES[tool.grade_index].title.to_upper()), "V changes grade and HUD")

	tool.configure_removal("Timed", 5)
	tool.removal_input(true)
	actor.global_position = Vector3(-4.80, 0.02, 4.05)
	await frames()
	actor.camera.look_at(rack.global_position)
	check(rack_session.enter(), "Rack also opens with the Uni-Bolt equipped")
	var remaining := tool.removal_remaining
	grade = tool.grade_index
	ui._input(event)
	await frames(5)
	check(is_equal_approx(tool.removal_remaining, remaining) and tool.grade_index == grade
		and actor.equipped_tool() == tool and not tool.visible, "Rack pauses timing, hides tool and consumes grade input")
	rack_session.leave()
	if DisplayServer.get_name() != "headless":
		await frames(4)
		check(tool.removal_remaining < remaining, "Captured gameplay resumes removal timing")

	var settings := MechanicalInteractionSettings.new()
	var legacy := settings.values.duplicate(true)
	legacy.controls.erase("removal_behavior")
	legacy.controls.erase("removal_seconds")
	check(settings.apply(legacy).is_empty() and settings.values.controls.removal_behavior == "Timed"
		and settings.values.controls.removal_seconds == 5, "Legacy snapshot defaults to Timed")
	var values := settings.values.duplicate(true)
	values.controls.removal_behavior = "Hold"
	values.controls.removal_seconds = 7
	var path := "user://rd009_removal_test.json"
	var reopened := MechanicalInteractionSettings.new()
	check(settings.apply(values).is_empty() and settings.save_file(path).is_empty()
		and reopened.load_file(path).is_empty() and reopened.values.controls.removal_behavior == "Hold"
		and reopened.values.controls.removal_seconds == 7, "Removal preferences round-trip through JSON")
	DirAccess.remove_absolute(path)
	await heavy_stock_drag(supply, actor)
	await pickup_diagnostics(facility, supply, actor, system)
	await hydraulic_split(facility, supply, actor, system)
	facility.queue_free()
	await frames()
	await compare_ram_branches()
	await process_frame
	print("RD-009: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func check_round_tube(part: InteractableObject, supply: ScrapSupply, index: int) -> void:
	var model := part.get_children().filter(func(child: Node) -> bool: return child is MeshInstance3D)
	check(model.size() == 1 and part.get_shape_owners().size() == 12,
		"Round tube has one seamless visual mesh and retains its twelve collision hulls")
	var tube: Dictionary = supply.catalog[index]
	if model.size() == 1:
		var mesh := (model[0] as MeshInstance3D).mesh
		var surface := mesh.surface_get_arrays(0)
		var vertices: PackedVector3Array = surface[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = surface[Mesh.ARRAY_NORMAL]
		var triangles: PackedInt32Array = surface[Mesh.ARRAY_INDEX]
		var min_radius: float = tube.size.y * 0.5 - ScrapCatalog.WALL
		var open_and_facing := true
		for vertex in vertices:
			open_and_facing = open_and_facing and Vector2(vertex.y, vertex.z).length() >= min_radius - 0.0001
		for i in range(0, triangles.size(), 3):
			var a := triangles[i]
			var b := triangles[i + 1]
			var c := triangles[i + 2]
			var cross := (vertices[b] - vertices[a]).cross(vertices[c] - vertices[a])
			open_and_facing = open_and_facing and cross.dot(normals[a]) < 0.0
		check(open_and_facing and triangles.size() == ScrapCatalog.TUBE_VISUAL_SEGMENTS * 24,
			"The smooth mesh has correctly facing walls and rims with no cap across the bore")
	var rod: Array = supply.catalog[11].shapes[0]
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = rod[0]
	query.transform = Transform3D(rod[2].basis, part.global_position - Vector3.RIGHT * (tube.size.x * 0.5 + 0.19))
	query.motion = Vector3.RIGHT * (tube.size.x + 0.38)
	query.collision_mask = 1
	var fractions := part.get_world_3d().direct_space_state.cast_motion(query)
	check(fractions[0] >= 1.0, "The stock steel rod can sweep through the entire round bore")

func heavy_stock_drag(supply: ScrapSupply, actor: OtisController) -> void:
	var plate := supply.dispense(16)
	check(plate != null, "Dispense the large steel plate")
	if plate == null:
		return
	plate.global_position = Vector3(2.0, 0.025, 2.0)
	actor.global_position = Vector3(2.0, 0.02, 3.15)
	await frames(5)
	var start := plate.global_position
	actor.camera.look_at(start)
	var can_drag := actor.placement.begin_world(plate)
	check(is_equal_approx(plate.mass, 45.57) and plate.mass > actor.placement.lift_capacity()
		and can_drag and actor.placement.is_supported_grab() and not plate.freeze,
		"The 45.57 kg plate remains too heavy to lift but can be dragged")
	actor.camera.look_at(start + Vector3(0.8, 0.45, 0))
	await frames(45)
	check(plate.global_position.x > start.x + 0.1 and absf(plate.global_position.y - start.y) < 0.03,
		"The heavy plate moves along the floor without being lifted")
	actor.placement.cancel()
	plate.queue_free()
	await frames()

func hydraulic_split(facility: Node3D, supply: ScrapSupply, actor: OtisController, system: FasteningSystem) -> void:
	var ram := facility.get("test_ram") as StructuralTestRam
	var crate := facility.get_node("Crate") as InteractableObject
	var parts: Array[InteractableObject] = []
	var bolts: Array[InstalledFastener] = []
	crate.global_transform = Transform3D(Basis.IDENTITY, Vector3(-2.5, 0.65, -0.5))
	crate.linear_velocity = Vector3.ZERO
	var crate_shapes := crate.get_shape_owners().size()
	await frames(4)
	for i in 3:
		var part := supply.dispense(15)
		check(part != null, "Dispense scrap for hydraulic split")
		if part == null:
			return
		parts.append(part)
		await frames()
		var placement := Vector3(crate.position.x + (-0.28 if i == 0 else 0.28),
			crate.position.y + (0.681 if i == 2 else 0.661), crate.position.z)
		part.gravity_scale = 0.0
		part.global_position = placement
		part.linear_velocity = Vector3.ZERO
		system.sync_body_transform(part)
		await frames(2)
		# Exercise a follower that entered the graph with a stale kinematic flag.
		# The other branch is built from ordinary dynamic stock.
		if i == 0:
			part.freeze = true
		var bolt := system.create_round(FasteningTool.GRADES[2 if i == 2 else 0])
		var origin := placement + Vector3(0.0 if i != 2 else 0.07, 0.07, 0.0)
		var issue := system.install(bolt, origin, Vector3.DOWN, 1.0)
		check(issue.is_empty(), "Build scrap link %d: %s" % [i, issue])
		if not issue.is_empty():
			return
		bolts.append(bolt)
		await frames()
	var detached := parts[0]
	var mass := detached.mass
	var identity := detached.get_instance_id()
	var definition := detached.definition
	var condition := definition.condition
	var connected_inspection := detached.inspection_information()
	ram.travel = 1.797
	ram.face.position.x = ram.travel
	ram.set_force_index(9)
	ram.set_drive(StructuralTestRam.Drive.EXTEND)
	await frames(18)
	ram.set_drive(StructuralTestRam.Drive.IDLE)
	check(bolts[0].state == InstalledFastener.State.FAILED and bolts[0].load_estimate > bolts[0].grade.strength,
		"Hydraulic inertia overloads the weak single-part link")
	check(bolts[1].state == InstalledFastener.State.FAILED and bolts[1].load_estimate > bolts[1].grade.strength
		and bolts[2].state == InstalledFastener.State.INSTALLED, "The ram breaks only links exceeding their rating")
	check(system.between(crate, detached) == null and system.physics_root(detached) == detached
		and system.incident(detached).is_empty(), "The single part has no surviving assembly membership")
	check(parts[1].fastened and system.physics_root(parts[1]) != crate
		and system.physics_root(parts[2]) == system.physics_root(parts[1]),
		"Surviving scrap remains a smaller assembly")
	check(not detached.fastened and not detached.freeze and detached.collision_layer == 1
		and detached.mass == mass and detached.get_instance_id() == identity
		and detached.definition == definition and detached.definition.condition == condition
		and detached.get_parent() == facility
		and detached.query_actions().has(&"move") and detached.query_actions().has(&"inspect"),
		"Independent scrap restores its body and normal interactions")
	check(crate.get_shape_owners().size() == crate_shapes and detached.get_shape_owners().size() == 1
		and system.cast(detached.global_position + Vector3.UP * 0.08,
			detached.global_position - Vector3.UP * 0.08, [], false, FasteningSystem.PROBE_LAYER).is_empty(),
		"Compound copies and query proxies are removed from the disconnected bodies")
	check(connected_inspection.description.contains("Connected assembly")
		and detached.inspection_information().description.contains("Independent"),
		"Inspection identifies connected and independent stock")
	actor.global_position = detached.global_position + Vector3(0, -1.0, 0.9)
	await frames()
	actor.camera.look_at(detached.global_position)
	var service := InteractionService.new()
	var inspected := service.request(&"inspect", actor, actor.camera, detached, actor.interaction_distance, actor.knowledge)
	check(inspected.ok and actor.knowledge.has_inspected(detached.definition.object_id)
		and inspected.information.description.contains("Independent"), "Detached scrap can be inspected and recorded")
	var ui = facility.get_node("InteractionUI")
	ui.debug_visible = true
	await frames()
	check(ui.debug_label.text.contains("ASSEMBLY  INDEPENDENT")
		and ui.debug_label.text.contains(detached.definition.object_id), "F3 reports the live independent target")
	ui.debug_visible = false
	actor.camera.look_at(detached.global_position)
	var result := service.request(&"move", actor, actor.camera, detached, actor.interaction_distance, actor.knowledge)
	check(result.ok and actor.placement.is_grabbing(), "The live Move action can acquire the fractured part")
	actor.placement.cancel()

func compare_ram_branches() -> void:
	for count in 3:
		var chamber = preload("res://scenes/facility.tscn").instantiate()
		root.add_child(chamber)
		var crate := chamber.get_node("Crate") as InteractableObject
		var system: FasteningSystem = chamber.fastening
		var ram: StructuralTestRam = chamber.test_ram
		var supply: ScrapSupply = chamber.scrap_supply
		crate.global_position = Vector3(-2.5, 0.65, -0.5)
		crate.linear_velocity = Vector3.ZERO
		system.sync_body_transform(crate)
		await frames(5)
		var bolts: Array[InstalledFastener] = []
		var parts: Array[InteractableObject] = []
		for index in count:
			var stock := supply.dispense(0)
			parts.append(stock)
			stock.gravity_scale = 0.0
			stock.global_position = crate.global_position + Vector3(index * 0.055, 0.08, 0.661 + index * 0.022)
			var origin := stock.global_position + Vector3(0.035 * index, 0, 0.06)
			system.sync_body_transform(stock)
			await frames(2)
			var bolt := system.create_round(FasteningTool.GRADES[0])
			var issue := system.install(bolt, origin, Vector3.FORWARD, 0.5)
			check(issue.is_empty(), "Side branch installs: " + issue)
			bolts.append(bolt)
			await frames()
		var start := crate.global_position.x
		ram.travel = 1.797
		ram.face.position.x = ram.travel
		ram.set_force_index(4)
		ram.set_drive(StructuralTestRam.Drive.EXTEND)
		var peaks := PackedFloat64Array()
		peaks.resize(count)
		for step in 10:
			await frames(1)
			for i in count:
				peaks[i] = maxf(peaks[i], bolts[i].load_estimate)
		var travel := crate.global_position.x - start
		ram.set_drive(StructuralTestRam.Drive.IDLE)
		print("RD-009 comparative ram · %d attached · peak loads %s · crate moved %.3f m" % [count, peaks, travel])
		check(travel > 0.005 and ram.specimen == crate, "Ram contacts and drives the unanchored crate")
		check(bolts.all(func(bolt: InstalledFastener) -> bool: return bolt.state == InstalledFastener.State.INSTALLED),
			"At 800 units, the %d-part side branch survives ordinary ram contact" % count)
		if count == 2 and bolts[0].state == InstalledFastener.State.INSTALLED:
			check(bolts[0].b == crate and bolts[1].b == parts[0] and peaks[0] > peaks[1] and peaks[1] > 0.0,
				"The two-part graph loads both links and the parent carries more")
			await move_split_cluster(chamber, system, crate, parts, bolts)
		chamber.queue_free()
		await frames()

func move_split_cluster(chamber: Node3D, system: FasteningSystem, crate: InteractableObject,
		parts: Array[InteractableObject], bolts: Array[InstalledFastener]) -> void:
	system.apply_ram_inertia(crate, Vector3.ZERO, Vector3.UP)
	check(bolts[0].load_estimate > 0.0 and bolts[1].load_estimate > 0.0
		and bolts[0].state == InstalledFastener.State.INSTALLED, "Angular acceleration adds load to the eccentric branch")
	# A high, explicit branch load is still a real overload.
	system.apply_structural_load(crate, bolts[0].head(), Vector3.RIGHT * 110)
	var body := system.physics_root(parts[1]) as InteractableObject
	check(bolts[0].state == InstalledFastener.State.FAILED and bolts[1].state == InstalledFastener.State.INSTALLED
		and body != crate and parts[0].assembly_root() == body and parts[1].assembly_root() == body,
		"Overload leaves a free cluster with both parts and the surviving internal bolt")
	var actor := chamber.get_node("Otis") as OtisController
	var leaf := parts[0] if body == parts[1] else parts[1]
	var diagnostics := system.diagnostics({}, leaf)
	check(diagnostics.contains("EXPLICIT LOAD") and diagnostics.contains("Group %d" % bolts[1].group_id),
		"Structural diagnostics show the surviving link and the overload that split the cluster")
	var exposed_edge := -0.13 if leaf == parts[0] else 0.13
	actor.global_position = Vector3(leaf.global_position.x + exposed_edge, 0.02, leaf.global_position.z + 1.45)
	await frames(5)
	actor.camera.look_at(leaf.global_position + Vector3(exposed_edge, 0, 0))
	var move := InteractionService.new().request(&"move", actor, actor.camera, leaf, actor.interaction_distance, actor.knowledge)
	check(move.ok and body.state == InteractableObject.State.CARRIED and leaf.fastened
		and move.message.contains("Connected assembly · 6.78 kg"), "Move on the follower grabs the whole 6.78 kg cluster: " + move.message)
	if not move.ok:
		return
	check(not system.remove(bolts[1]), "A held cluster keeps its internal connection during movement")
	var relative := body.to_local(leaf.global_position)
	var start := body.global_position
	actor.camera.look_at(leaf.global_position + Vector3(0.4, 0.4, 0.25))
	await frames(30)
	check(body.global_position.distance_to(start) > 0.1 and body.to_local(leaf.global_position).is_equal_approx(relative),
		"The root and follower travel together as one collision body")
	check(actor.placement.confirm() and bolts[1].state == InstalledFastener.State.INSTALLED and not body.freeze,
		"Confirm restores dynamics without removing the internal bolt")
	body.global_position = Vector3(2.7, 0.04, 2.55)
	body.gravity_scale = 1.0
	system.sync_body_transform(body)
	actor.global_position = Vector3(2.7, 0.02, 3.7)
	var lift := actor.placement.lift_capacity()
	actor.chassis.set_contribution(&"test_lift", {AndroidChassis.Attribute.LIFT_KG: 5.0 - lift})
	await frames(6)
	actor.camera.look_at(body.global_position)
	actor.placement.press_drop(0)
	actor.placement.release_drop(PrecisionPlacement.HOLD_THRESHOLD_USEC)
	check(actor.placement.is_supported_grab() and actor.placement.last_grab_feedback.contains("6.78 kg / 5.00 kg")
		and bolts[1].state == InstalledFastener.State.INSTALLED, "Hold G drags a free cluster above lift capacity")
	actor.placement.cancel()

func pickup_diagnostics(chamber: Node3D, supply: ScrapSupply, actor: OtisController, system: FasteningSystem) -> void:
	var stock := supply.dispense(0)
	check(stock != null, "Dispense the pickup-clearance bracket")
	if stock == null:
		return
	var service := InteractionService.new()
	actor.global_position = Vector3(2.0, 0.02, 2.0)
	await frames(5)
	stock.gravity_scale = 0.0
	stock.global_position = actor.global_position + Vector3(0.0, 0.80, -0.25)
	system.sync_body_transform(stock)
	actor.camera.look_at(stock.global_position)
	var obstruction := service.request(&"move", actor, actor.camera, stock, actor.interaction_distance, actor.knowledge)
	check(not obstruction.ok and obstruction.message.contains("Pickup path obstructed by Otis")
		and not obstruction.message.contains("Lift capacity"), "Player clearance rejection names Otis separately from mass")
	stock.mass = 45.0
	var combined := service.request(&"move", actor, actor.camera, stock, actor.interaction_distance, actor.knowledge)
	check(combined.ok and actor.placement.is_supported_grab() and combined.message.contains("Lift capacity exceeded")
		and combined.message.contains("Pickup path obstructed by Otis"), "Capacity and obstruction can both be reported during drag")
	actor.placement.cancel()
	stock.fastened = true
	var stale := service.request(&"move", actor, actor.camera, stock, actor.interaction_distance, actor.knowledge)
	check(not stale.ok and stale.message.contains("Invalid assembly state"), "A stale member reports invalid topology")
	stock.fastened = false
	stock.queue_free()
	await frames(2)

	var crate := chamber.get_node("Crate") as InteractableObject
	crate.mass = 45.0
	crate.global_position = Vector3(2.4, 0.65, 2.4)
	system.sync_body_transform(crate)
	var calibration := chamber.get_node_or_null("TestWeight") as InteractableObject
	if calibration == null:
		check(false, "The calibration block is available")
		return
	calibration.global_position = crate.global_position + Vector3(0, 0.78, 0)
	system.sync_body_transform(calibration)
	actor.global_position = Vector3(2.4, 0.02, 3.85)
	await frames(10)
	var lift := actor.chassis.effective(AndroidChassis.Attribute.LIFT_KG)
	actor.chassis.set_contribution(&"test_lift", {AndroidChassis.Attribute.LIFT_KG: 36.75 - lift})
	actor.camera.look_at(crate.global_position)
	var heavy := service.request(&"move", actor, actor.camera, crate, actor.interaction_distance, actor.knowledge)
	check(heavy.ok and actor.placement.is_supported_grab() and heavy.message.contains("45.00 kg / 36.75 kg")
		and not heavy.message.contains("53.00") and not calibration.fastened,
		"An unbolted 8 kg block does not count toward the crate's manipulation mass")
	actor.placement.cancel()
	actor.chassis.set_contribution(&"test_lift", {})
	crate.mass = crate.definition.mass_kg

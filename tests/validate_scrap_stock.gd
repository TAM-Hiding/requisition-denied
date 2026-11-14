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
	check(supply.catalog.size() == 27, "27 authored stock variants")
	var all_ids := {}
	for index in supply.catalog.size():
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
	check(panel.feedback.text.contains("occupied"), "Existing stock blocks delivery")
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
		and is_instance_valid(facility.get_node("TriangularGusset")) and is_instance_valid(tool)
		and is_instance_valid(rack) and supply.clear_loose() == 0, "Cleanup keeps assemblies, held stock and original fixtures")
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
	facility.queue_free()
	await process_frame
	print("RD-009: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

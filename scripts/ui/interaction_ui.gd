extends CanvasLayer
var service := InteractionService.new()
var hud: Control
var target: InteractableObject
var menu_target: InteractableObject
var target_distance: float = 0.0
var debug_visible: bool = false
var menu_open: bool = false
var prompt: Label
var help: Label
var debug_label: Label
var crosshair: Control
var tool_readout: Label
var panel: PanelContainer
var menu_items: VBoxContainer
var title: Label
var information: Label
var status: Label
var feedback_time: float = 0.0
var e_pending: bool = false
var e_elapsed: float = 0.0
var e_consumed: bool = false
var menu_actions: Array[StringName] = []
@onready var otis: OtisController = get_parent().get_node("Otis")

var application_focused := true
var _mouse_mode_before_focus_loss := Input.MOUSE_MODE_VISIBLE

func _ready() -> void:
	hud = Control.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hud)
	var heading := Label.new()
	heading.text = "REQUISITION DENIED   /   DEVELOPMENT"
	heading.position = Vector2(24, 18)
	hud.add_child(heading)
	help = Label.new()
	help.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	help.position += Vector2(24, -40)
	hud.add_child(help)
	crosshair = Control.new()
	crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	crosshair.position -= Vector2(8, 8)
	crosshair.size = Vector2(16, 16)
	crosshair.draw.connect(func() -> void:
		crosshair.draw_circle(crosshair.size * 0.5, 1.8, Color.WHITE, true, -1.0, true))
	hud.add_child(crosshair)
	tool_readout = Label.new()
	tool_readout.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	tool_readout.position += Vector2(-590, 24)
	tool_readout.size.x = 566
	tool_readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	hud.add_child(tool_readout)
	prompt = Label.new()
	prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	prompt.position += Vector2(-180, 25)
	prompt.size.x = 360
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hud.add_child(prompt)
	debug_label = Label.new()
	debug_label.position = Vector2(24, 62)
	debug_label.visible = false
	hud.add_child(debug_label)
	panel = PanelContainer.new()
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0.055, 0.075, 0.085, 0.97)
	background.border_color = Color("526b73")
	background.set_border_width_all(1)
	background.set_corner_radius_all(4)
	panel.add_theme_stylebox_override("panel", background)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.position += Vector2(-250, -170)
	panel.custom_minimum_size = Vector2(500, 0)
	hud.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)
	title = Label.new()
	title.add_theme_font_size_override("font_size", 24)
	column.add_child(title)
	menu_items = VBoxContainer.new()
	column.add_child(menu_items)
	information = Label.new()
	information.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	information.custom_minimum_size.x = 450
	column.add_child(information)
	var close := Button.new()
	close.text = "Close  [Esc]"
	close.pressed.connect(close_menu)
	column.add_child(close)
	status = Label.new()
	status.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	status.position += Vector2(24, -76)
	hud.add_child(status)
	otis.equipment.feedback.connect(show_feedback)
	otis.placement.grab_feedback.connect(show_feedback)
	panel.hide()
	var settings := otis.placement.mechanical_settings
	settings.values.rotation.invert_horizontal = otis.placement.invert_horizontal_rotation
	settings.values.rotation.invert_vertical = otis.placement.invert_vertical_rotation
	settings.values.controls.mouse_sensitivity = otis.mouse_sensitivity
	settings.values.controls.precision_rotation_sensitivity = otis.placement.rotation_sensitivity
	settings.values.controls.ads_sensitivity_multiplier = otis.tool_aim_sensitivity
	settings.changed.connect(apply_mechanical_settings)
	if FileAccess.file_exists(MechanicalInteractionSettings.FILE_PATH):
		var issue := settings.load_file()
		if not issue.is_empty():
			show_feedback(issue)
	apply_mechanical_settings()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
	var tool := otis.equipped_tool()
	if tool != null:
		tool.update_removal(delta, gameplay_input_allowed())
	if not application_focused or active_station() != null:
		return
	var ram: StructuralTestRam = get_parent().test_ram
	var aim := {}
	if tool != null and gameplay_input_allowed():
		aim = tool.aim_feedback(otis.camera, otis)
		tool_readout.text = tool.hud_text() + "\nLMB Use  •  RMB Aim  •  R Mode  •  V Grade  •  B Refill"
		var guidance: String = aim.issue
		if guidance.is_empty():
			guidance = "REMOVE BOLT #%d" % aim.bolt.id if tool.removing else "INSTALL UNI-BOLT"
		if not tool.removing and tool.rounds.is_empty():
			guidance = "MAGAZINE EMPTY"
		tool_readout.text += "\n" + guidance
		if ram.drive != StructuralTestRam.Drive.IDLE:
			tool_readout.text += "\n" + ram.hud_text()
	elif ram.drive != StructuralTestRam.Drive.IDLE or debug_visible:
		tool_readout.text = ram.hud_text() + "\nF5 Drive  •  F6 / Shift+F6 Force  •  F7 Reset"
	else:
		tool_readout.text = ""
	var placing := otis.placement.is_active()
	var socket := otis.placement.installation_candidate()
	var mount_issue := ""
	if placing:
		help.text = "Wheel Range  •  G Place  •  Esc Cancel"
		if otis.placement.is_grabbing():
			help.text += "  •  1 Stow  •  X Drop Tool" if tool != null else "  •  1 Equip Tool"
		if not otis.placement.is_supported_grab():
			help.text += "  •  Hold Middle Mouse Rotate"
	elif tool != null:
		help.text = "Hold G Grab  •  1 Stow  •  X Drop Tool  •  E Context  •  F3 Debug"
	else:
		help.text = "WASD Move  •  E Context  •  Hold E Stow  •  1 Equip  •  G Drop / hold to place or grab  •  Esc Cursor  •  F3 Debug  •  Terminal Settings"
	status.visible = tool != null or not placing or not otis.placement.valid or socket != null
	advance_hold(delta)
	if gameplay_input_allowed():
		otis.placement.advance_drop()
	else:
		otis.placement.clear_gesture()
		if otis.placement.rotating:
			otis.placement.set_rotating(false)
	feedback_time = maxf(0, feedback_time - delta)
	if feedback_time == 0:
		status.text = ""
	if menu_open:
		if not is_instance_valid(menu_target) or menu_target.state not in [InteractableObject.State.WORLD, InteractableObject.State.MOVING]:
			close_menu()
		elif menu_actions != menu_target.query_actions():
			rebuild_actions()
	var hit := otis.target_hit()
	target = null
	target_distance = 0.0
	if not hit.is_empty() and hit.collider is InteractableObject:
		target = hit.collider
		target_distance = otis.camera.global_position.distance_to(hit.position)
	crosshair.visible = not menu_open and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
		and not otis.equipment.presentation.sight_replaces_crosshair()
	crosshair.modulate = Color("a2e7df") if target != null else Color.WHITE
	if menu_open:
		prompt.text = ""
	elif Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		prompt.text = "Left-click to resume"
	elif otis.placement.is_supported_grab():
		prompt.text = "SUPPORTED GRAB"
	elif otis.placement.is_seating():
		prompt.text = "SEATING  •  Esc Cancel"
	elif socket != null:
		mount_issue = otis.placement.installation_feedback(socket)
		prompt.text = "[E] Install  •  %s" % otis.placement.installation_name() if mount_issue.is_empty() else mount_issue
	elif placing:
		var placement := otis.placement
		prompt.text = "%s  |  %s" % [
			"ROTATING" if placement.rotating else "PLACEMENT", "CLEAR" if placement.valid else "BLOCKED"]
	elif target != null:
		prompt.text = "[E]  " + target.definition.display_name
	else:
		prompt.text = ""
	prompt.modulate = Color("eda79a") if otis.placement.is_active() and not otis.placement.valid else Color.WHITE
	var actions: Array[StringName] = []
	if target != null:
		actions = target.query_actions()
	var target_id: StringName = target.definition.object_id if target != null else &"none"
	if hit.get("collider") is PoweredBarrier:
		target_id = hit.collider.barrier_id
		target_distance = otis.camera.global_position.distance_to(hit.position)
	debug_label.text = "TARGET  %s\nDISTANCE  %s\nACTIONS  %s\nINSPECTED OBJECTS  %d" % [
		target_id,
		"%.2f m" % target_distance if target_id != &"none" else "—", str(actions), otis.knowledge.inspected_object_count()]
	var held := otis.equipment.held_item()
	debug_label.text += "\nMOBILITY  %s\nSTATE  %s\nEQUIPPED  %s\nSTORED  %d\nMOVING  %s" % [
		target.mobility_name() if target != null else "—",
		target.state_name() if target != null else "—",
		held.definition.object_id if held != null else &"none",
		otis.equipment.stored_items().size(), str(otis.placement.is_grabbing())]
	debug_label.text += "\nEQUIPMENT STATE  " + ("HELD" if held != null else ("STOWED" if not otis.equipment.stored_items().is_empty() else "EMPTY"))

	debug_label.text += "\nHELD OBSTRUCTED  %s\nMOVEMENT LIMIT  %.2f m/s" % [
		str(otis.equipment.presentation.obstructed), otis.movement_speed * (1.0 - 0.25 * otis.placement.load_fraction())]

	debug_label.text += "\nEQUIPMENT POSE  " + HeldItemPresentation.Pose.keys()[otis.equipment.presentation.requested_pose]

	if debug_visible:
		debug_label.text += get_parent().environmental_diagnostics()
		if tool != null:
			debug_label.text += tool.system.diagnostics(aim)
		if otis.placement.mechanical_settings.values.debug.show_alignment_diagnostics:
			if socket != null:
				debug_label.text += otis.placement.alignment_diagnostics(socket, mount_issue)
			elif placing:
				debug_label.text += "\nMOUNT  " + ("SEATING" if otis.placement.is_seating() else "NO CANDIDATE")

func _input(event: InputEvent) -> void:
	if not application_focused:
		get_viewport().set_input_as_handled()
		return
	var terminal := active_station()
	if terminal != null:
		if terminal.snapshot_picker_visible():
			return
		if event.is_action("ui_cancel") and event.is_echo():
			get_viewport().set_input_as_handled()
			return
		terminal.route(event)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.echo:
		return
	if event.is_action_released("tool_secondary_aim"):
		otis.set_tool_aiming(false)
	if gameplay_input_allowed() and handle_fastening_input(event):
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("debug_overlay"):
		debug_visible = not debug_visible
		get_parent().fastening.load_debug = debug_visible
		apply_mechanical_settings()
		debug_label.visible = debug_visible
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		cancel_hold()
		otis.placement.clear_gesture()
		if otis.placement.is_active():
			otis.placement.cancel()
		elif menu_open:
			close_menu()
		else:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("drop_item") and gameplay_input_allowed():
		cancel_hold()
		otis.placement.press_drop()
		get_viewport().set_input_as_handled()
	elif event.is_action_released("drop_item"):
		if gameplay_input_allowed():
			otis.placement.release_drop()
		else:
			otis.placement.clear_gesture()
		get_viewport().set_input_as_handled()
	elif otis.placement.is_active() and gameplay_input_allowed() and handle_placement_controls(event):
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact") and gameplay_input_allowed():
		e_pending = true
		e_elapsed = 0
		e_consumed = false
		get_viewport().set_input_as_handled()
	elif event.is_action_released("interact"):
		if e_pending and not e_consumed and gameplay_input_allowed():
			var station := station_for(target)
			if station == null or not station.enter():
				open_menu(target)
		cancel_hold()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("equip_first") and gameplay_input_allowed():
		cancel_hold()
		service.request_actor_action(&"equip_first", otis)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and not menu_open:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()

func handle_placement_controls(event: InputEvent) -> bool:
	if event.is_action("interact") or event.is_action("equip_first"):
		if event.is_action_pressed("interact") and otis.placement.installation_candidate() != null:
			otis.placement.install_grab()
		return true
	if event.is_action("precision_rotate"):
		if otis.tool_aiming:
			return true
		if otis.placement.is_supported_grab():
			return false
		otis.placement.set_rotating(event.is_action_pressed("precision_rotate"))
		return true
	if event.is_action_pressed("precision_range_in"):
		if not otis.tool_aiming:
			otis.placement.adjust_distance(1)
		return true
	if event.is_action_pressed("precision_range_out"):
		if not otis.tool_aiming:
			otis.placement.adjust_distance(-1)
		return true
	return false

func handle_fastening_input(event: InputEvent) -> bool:
	var tool := otis.equipped_tool()
	if event.is_action_pressed("equip_first") and tool != null:
		otis.set_tool_aiming(false)
		tool.update_removal(0.0, false)
		otis.equipment.stow()
		return true
	if event.is_action_pressed("drop_tool") and tool != null:
		otis.set_tool_aiming(false)
		tool.update_removal(0.0, false)
		otis.equipment.drop()
		return true
	if otis.placement.is_grabbing() and event.is_action_pressed("equip_first"):
		var targeted := otis.target_hit().get("collider") as FasteningTool
		if otis.equipment.held_item() == null and targeted != null and otis.equipment.stored_items().is_empty():
			otis.equipment.pick_up(targeted)
		else:
			service.request_actor_action(&"equip_first", otis)
		return true
	var ram: StructuralTestRam = get_parent().test_ram
	if ram.handle_shortcut(event):
		show_feedback(ram.hud_text())
	elif tool == null:
		return false
	elif event.is_action_pressed("tool_primary"):
		if not otis.placement.is_seating() and not otis.placement.is_supported_grab():
			show_feedback(tool.use(otis.camera, otis))
		else:
			show_feedback("Finish the current mechanical operation first.")
	elif event.is_action_pressed("tool_secondary_aim"):
		otis.set_tool_aiming(true)
	elif event.is_action("tool_mode_toggle"):
		tool.removal_input(event.is_action_pressed("tool_mode_toggle"))
		show_feedback("UNI-BOLT · REMOVE" if tool.removing else "UNI-BOLT · INSTALL")
	elif event.is_action_pressed("tool_grade"):
		tool.load_grade(tool.grade_index + 1)
	elif event.is_action_pressed("tool_replenish"):
		tool.replenish()
	else:
		return false
	return true

func set_terminal_active(active: bool) -> void:
	if active:
		suspend_tool_input()
	cancel_hold()
	otis.set_tool_aiming(false)
	otis.equipment.presentation.set_station_active(active)
	hud.visible = not active

func active_station() -> TerminalInteraction:
	for station: TerminalInteraction in [get_parent().terminal_session, get_parent().ram_session, get_parent().scrap_session]:
		if is_instance_valid(station) and station.active:
			return station
	return null

func station_for(object: InteractableObject) -> TerminalInteraction:
	for station: TerminalInteraction in [get_parent().terminal_session, get_parent().ram_session, get_parent().scrap_session]:
		if is_instance_valid(station) and station.is_target(object):
			return station
	return null

func gameplay_input_allowed() -> bool:
	return application_focused and not menu_open and active_station() == null and otis.controls_enabled and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED

func cancel_hold() -> void:
	e_pending = false
	e_elapsed = 0
	e_consumed = false

func advance_hold(delta: float) -> void:
	if not e_pending or e_consumed:
		return
	if not gameplay_input_allowed():
		cancel_hold()
		return
	e_elapsed += delta
	if e_elapsed >= otis.interact_hold_threshold:
		e_consumed = true
		if not otis.placement.is_grabbing():
			service.request_actor_action(&"stow", otis)

func show_feedback(message: String) -> void:
	status.text = message
	feedback_time = 3.5

func open_menu(object: InteractableObject) -> void:
	if otis.placement.is_active() or not service.permitted(otis, otis.camera, object, otis.interaction_distance):
		return
	cancel_hold()
	otis.placement.clear_gesture()
	menu_target = object
	menu_open = true
	otis.controls_enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	title.text = object.definition.display_name
	information.text = "Choose an action."
	rebuild_actions()
	panel.show()

func rebuild_actions() -> void:
	menu_actions = menu_target.query_actions()
	for child in menu_items.get_children():
		menu_items.remove_child(child)
		child.queue_free()
	for action in menu_actions:
		var button := Button.new()
		button.text = String(action).replace("_", " ").capitalize()
		var use_terminal: bool = action == &"use_terminal" and station_for(menu_target) != null
		button.disabled = action not in [&"inspect", &"pick_up", &"move", &"remove"] and not use_terminal
		if button.disabled:
			button.text += " — unavailable in RD-002"
		button.pressed.connect(perform_action.bind(action))
		menu_items.add_child(button)
	if menu_items.get_child_count() > 0:
		menu_items.get_child(0).grab_focus()

func perform_action(action: StringName) -> void:
	var station := station_for(menu_target)
	if action == &"use_terminal" and station != null:
		close_menu()
		station.enter()
		return
	var result := service.request(action, otis, otis.camera, menu_target, otis.interaction_distance, otis.knowledge)
	if result.ok and action != &"inspect":
		close_menu()
	elif result.ok:
		information.text = "%s\n\n%s\n\nRecorded in Otis’s knowledge." % [result.information.name, result.information.description]
	else:
		information.text = result.message

func close_menu() -> void:
	cancel_hold()
	menu_open = false
	menu_target = null
	panel.hide()
	otis.controls_enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT and application_focused:
		application_focused = false
		suspend_tool_input()
		_mouse_mode_before_focus_loss = Input.mouse_mode
		if is_instance_valid(otis) and is_instance_valid(otis.equipment):
			otis.set_tool_aiming(false)
		cancel_hold()
		if is_instance_valid(otis) and is_instance_valid(otis.placement):
			otis.placement.set_input_suspended(true)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN and not application_focused:
		application_focused = true
		cancel_hold()
		if is_instance_valid(otis) and is_instance_valid(otis.placement):
			otis.placement.set_input_suspended(active_station() != null)
		Input.mouse_mode = _mouse_mode_before_focus_loss

func apply_mechanical_settings() -> void:
	var values := otis.placement.mechanical_settings.values
	otis.placement.pickup_debug = debug_visible and values.pickup.show_clearance_diagnostics
	otis.placement.invert_horizontal_rotation = values.rotation.invert_horizontal
	otis.placement.invert_vertical_rotation = values.rotation.invert_vertical
	otis.mouse_sensitivity = values.controls.mouse_sensitivity
	otis.placement.rotation_sensitivity = values.controls.precision_rotation_sensitivity
	otis.tool_aim_sensitivity = values.controls.ads_sensitivity_multiplier
	var tool := get_parent().bolt_tool as FasteningTool
	if is_instance_valid(tool):
		tool.configure_removal(values.controls.removal_behavior, values.controls.removal_seconds)
	var fastening: FasteningSystem = get_parent().fastening
	if is_instance_valid(fastening):
		fastening.set_visual_scale_percent(values[MechanicalInteractionSettings.VISUAL_SCALE_KEY])


func show_bolt_failure(bolt: InstalledFastener) -> void:
	show_feedback("BOLT #%d FAILED UNDER LOAD · GROUP #%d · %s · %.0f / %.0f" % [
		bolt.id, bolt.group_id, bolt.failure_source, bolt.load_estimate, bolt.grade.strength])


func suspend_tool_input() -> void:
	if is_instance_valid(otis) and is_instance_valid(otis.equipment):
		var tool := otis.equipped_tool()
		if tool != null:
			tool.update_removal(0.0, false)

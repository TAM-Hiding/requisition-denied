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
var crosshair: Label
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
	crosshair = Label.new()
	crosshair.text = "·"
	crosshair.add_theme_font_size_override("font_size", 32)
	crosshair.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	crosshair.position += Vector2(-5, -22)
	hud.add_child(crosshair)
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
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
	if not application_focused or get_parent().terminal_session.active:
		return
	var placing := otis.placement.is_active()
	var socket := otis.placement.installation_candidate()
	if placing:
		help.text = "Wheel Range  •  G Place  •  Esc Cancel"
		if not otis.placement.is_supported_grab():
			help.text += "  •  Hold Middle Mouse Rotate"
	else:
		help.text = "WASD Move  •  E Context  •  Hold E Stow  •  1 Equip  •  G Drop / hold to place or grab  •  Esc Cursor  •  F3 Debug"
	status.visible = not placing or not otis.placement.valid or socket != null
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
	crosshair.visible = not menu_open and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	crosshair.modulate = Color("a2e7df") if target != null else Color.WHITE
	if menu_open:
		prompt.text = ""
	elif Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		prompt.text = "Left-click to resume"
	elif otis.placement.is_supported_grab():
		prompt.text = "SUPPORTED GRAB"
	elif socket != null:
		var issue := otis.placement.installation_feedback(socket)
		prompt.text = "[E] Install  •  %s" % socket.definition.mount_id if issue.is_empty() else issue
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

func _input(event: InputEvent) -> void:
	if not application_focused:
		get_viewport().set_input_as_handled()
		return
	var terminal: TerminalInteraction = get_parent().terminal_session
	if is_instance_valid(terminal) and terminal.active:
		if event.is_action("ui_cancel") and event.is_echo():
			get_viewport().set_input_as_handled()
			return
		terminal.route(event)
		get_viewport().set_input_as_handled()
		return
	if event is InputEventKey and event.echo:
		return
	if event.is_action_pressed("debug_overlay"):
		debug_visible = not debug_visible
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
			if not (terminal.is_target(target) and terminal.enter()):
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
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			if otis.placement.is_supported_grab():
				return false
			otis.placement.set_rotating(event.pressed)
			return true
		if not event.pressed:
			return false
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			otis.placement.adjust_distance(1)
			return true
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			otis.placement.adjust_distance(-1)
			return true
	return false

func set_terminal_active(active: bool) -> void:
	cancel_hold()
	hud.visible = not active

func gameplay_input_allowed() -> bool:
	return application_focused and not menu_open and otis.controls_enabled and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED

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
		var use_terminal: bool = action == &"use_terminal" and get_parent().terminal_session.is_target(menu_target)
		button.disabled = action not in [&"inspect", &"pick_up", &"move", &"remove"] and not use_terminal
		if button.disabled:
			button.text += " — unavailable in RD-002"
		button.pressed.connect(perform_action.bind(action))
		menu_items.add_child(button)
	if menu_items.get_child_count() > 0:
		menu_items.get_child(0).grab_focus()

func perform_action(action: StringName) -> void:
	if action == &"use_terminal" and get_parent().terminal_session.is_target(menu_target):
		close_menu()
		get_parent().terminal_session.enter()
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
		_mouse_mode_before_focus_loss = Input.mouse_mode
		cancel_hold()
		if is_instance_valid(otis) and is_instance_valid(otis.placement):
			otis.placement.set_input_suspended(true)
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif what == NOTIFICATION_APPLICATION_FOCUS_IN and not application_focused:
		application_focused = true
		cancel_hold()
		if is_instance_valid(otis) and is_instance_valid(otis.placement):
			otis.placement.set_input_suspended(false)
		Input.mouse_mode = _mouse_mode_before_focus_loss

extends CanvasLayer
var service := InteractionService.new()
var target: InteractableObject
var menu_target: InteractableObject
var target_distance: float = 0.0
var debug_visible: bool = false
var menu_open: bool = false
var prompt: Label
var debug_label: Label
var crosshair: Label
var panel: PanelContainer
var menu_items: VBoxContainer
var title: Label
var information: Label
@onready var otis: OtisController = get_parent().get_node("Otis")

func _ready() -> void:
	var hud := Control.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hud)
	var heading := Label.new()
	heading.text = "REQUISITION DENIED   /   RD–001"
	heading.position = Vector2(24, 18)
	hud.add_child(heading)
	var help := Label.new()
	help.text = "WASD  Move    •    E  Context    •    Esc  Release / close    •    F3  Diagnostics"
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
	panel.hide()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(_delta: float) -> void:
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
	elif target != null:
		prompt.text = "[E]  " + target.definition.display_name
	else:
		prompt.text = ""
	var actions: Array[StringName] = []
	if target != null:
		actions = target.query_actions()
	debug_label.text = "TARGET  %s\nDISTANCE  %s\nACTIONS  %s\nINSPECTED OBJECTS  %d" % [
		target.definition.object_id if target != null else &"none",
		"%.2f m" % target_distance if target != null else "—", str(actions), otis.knowledge.inspected_object_count()]

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("debug_overlay"):
		debug_visible = not debug_visible
		debug_label.visible = debug_visible
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		if menu_open:
			close_menu()
		else:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact") and not menu_open and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		open_menu(target)
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and not menu_open:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()

func open_menu(object: InteractableObject) -> void:
	if not service.permitted(otis, otis.camera, object, otis.interaction_distance):
		return
	menu_target = object
	menu_open = true
	otis.controls_enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	title.text = object.definition.display_name
	information.text = "Choose an action."
	for child in menu_items.get_children():
		menu_items.remove_child(child)
		child.queue_free()
	for action in object.query_actions():
		var button := Button.new()
		button.text = String(action).capitalize()
		button.disabled = action != &"inspect"
		if button.disabled:
			button.text += " — unavailable in RD-001"
		button.pressed.connect(perform_action.bind(action))
		menu_items.add_child(button)
	panel.show()
	if menu_items.get_child_count() > 0:
		menu_items.get_child(0).grab_focus()

func perform_action(action: StringName) -> void:
	var result := service.request(action, otis, otis.camera, menu_target, otis.interaction_distance, otis.knowledge)
	if result.ok:
		information.text = "%s\n\n%s\n\nRecorded in Otis’s knowledge." % [result.information.name, result.information.description]
	else:
		information.text = result.message

func close_menu() -> void:
	menu_open = false
	menu_target = null
	panel.hide()
	otis.controls_enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

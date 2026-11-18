class_name InventoryScreen
extends CanvasLayer
signal opening
var actor: OtisController
var active := false
var panel: PanelContainer
var preview: InventoryPreview
var bag: BagView
var bag_panel: VBoxContainer
var view_toggle: Button
var _preview_column: VBoxContainer
var _dump_sequence := false
var grid: GridContainer
var grid_scroll: ScrollContainer
var collapse: Button
var load_label: Label
var details: Label
var feedback: Label
var slot_button: Button
var popup: PopupMenu
var selected: InteractableObject
var turn_left := false
var turn_right := false
var previous_mouse_mode: int
var previous_suspension := false
var _hud: Control

func _ready() -> void:
	layer = 12
	register_action(&"inventory_toggle", KEY_T)
	register_action(&"inventory_rotate_left", KEY_Q)
	register_action(&"inventory_rotate_right", KEY_E)
	panel = PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.add_theme_stylebox_override("panel", style(Color("#101b20"), 0))
	add_child(panel)
	var margin := MarginContainer.new()
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 26)
	panel.add_child(margin)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 16)
	margin.add_child(content)
	var header := HBoxContainer.new()
	content.add_child(header)
	var title := label("PERSONNEL STORAGE  /  OTIS", 25)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	var close := Button.new()
	close.text = "CLOSE  [T / ESC]"
	close.pressed.connect(hide_inventory)
	header.add_child(close)
	content.add_child(label("ICF-01 WAYFARER     •     PERSONAL STORAGE AUTHORIZATION", 13))
	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 20)
	content.add_child(columns)
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 240
	left.add_theme_constant_override("separation", 16)
	columns.add_child(left)
	left.add_child(label("EQUIPMENT", 17))
	slot_button = Button.new()
	slot_button.custom_minimum_size = Vector2(230, 75)
	slot_button.gui_input.connect(func(event: InputEvent) -> void:
		entry_input(event, actor.equipment.held_item()))
	left.add_child(slot_button)
	load_label = label("", 15)
	left.add_child(load_label)
	details = label("Select an item to inspect its storage record.", 14)
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.custom_minimum_size.x = 230
	var detail_scroll := ScrollContainer.new()
	detail_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_scroll.add_child(details)
	left.add_child(detail_scroll)
	var centre := VBoxContainer.new()
	_preview_column = centre
	centre.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	centre.size_flags_stretch_ratio = 1.1
	columns.add_child(centre)
	preview = InventoryPreview.new()
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	centre.add_child(preview)
	centre.add_child(label("Q / E   ROTATE CHASSIS", 14))
	var right := VBoxContainer.new()
	right.custom_minimum_size.x = 310
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(right)
	collapse = Button.new()
	collapse.text = "CONTENTS   ▾"
	collapse.pressed.connect(func() -> void:
		grid_scroll.visible = not grid_scroll.visible
		collapse.text = "CONTENTS   ▾" if grid_scroll.visible else "CONTENTS   ▸")
	right.add_child(collapse)
	view_toggle = Button.new()
	view_toggle.text = "BAG VIEW"
	view_toggle.pressed.connect(toggle_view)
	right.add_child(view_toggle)
	bag_panel = VBoxContainer.new()
	bag_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(bag_panel)
	bag = BagView.new()
	bag.container = actor.equipment.container
	bag.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bag.item_selected.connect(select_item)
	bag.context_requested.connect(bag_context)
	bag.dump_requested.connect(dump_bag)
	bag_panel.add_child(bag)
	bag_panel.add_child(label("LMB DRAG • WHEEL HEIGHT\nRMB CLICK ACTIONS / HOLD PLOW • MMB TURN BAG", 12))
	bag_panel.hide()
	grid_scroll = ScrollContainer.new()
	grid_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(grid_scroll)
	grid = GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	grid_scroll.add_child(grid)
	feedback = label("Right-click an entry for available actions.", 15)
	content.add_child(feedback)
	content.add_child(label("PERSONAL STORAGE IS A PRIVILEGE. CONTAINER RATINGS ARE ENFORCED.", 12))
	popup = PopupMenu.new()
	popup.id_pressed.connect(perform_action)
	add_child(popup)
	panel.hide()

static func register_action(action: StringName, key: Key) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var event := InputEventKey.new()
	event.physical_keycode = key
	InputMap.action_add_event(action, event)

static func style(color: Color, border: int = 1) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.border_color = Color("#526467")
	box.set_border_width_all(border)
	box.set_content_margin_all(12)
	return box

static func label(text: String, size: int) -> Label:
	var result := Label.new()
	result.text = text
	result.add_theme_font_size_override("font_size", size)
	result.add_theme_color_override("font_color", Color("#c9d8d4"))
	return result

func show_inventory(hud: Control) -> bool:
	if active or not actor.controls_enabled or actor.equipment.dumping or _dump_sequence:
		return false
	_hud = hud
	opening.emit()
	previous_mouse_mode = Input.mouse_mode
	previous_suspension = actor.placement.input_suspended
	actor.set_tool_aiming(false)
	actor.placement.set_input_suspended(true)
	actor.controls_enabled = false
	actor.equipment.presentation.set_station_active(true)
	active = true
	panel.show()
	_hud.hide()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	refresh()
	return true

func hide_inventory(force := false) -> void:
	if _dump_sequence and not force:
		return
	if not active:
		return
	bag.close()
	bag_panel.hide()
	_preview_column.show()
	grid_scroll.show()
	collapse.show()
	view_toggle.text = "BAG VIEW"
	active = false
	turn_left = false
	turn_right = false
	popup.hide()
	panel.hide()
	_hud.show()
	actor.controls_enabled = true
	actor.placement.set_input_suspended(previous_suspension)
	actor.equipment.presentation.set_station_active(false)
	Input.mouse_mode = previous_mouse_mode

func route(event: InputEvent) -> void:
	if not active:
		return
	if _dump_sequence:
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and not event.pressed:
		if not bag.get_global_rect().has_point(event.position):
			bag.release_right(false)
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		bag.end_drag()
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE and not event.pressed:
		bag.orbiting = false
	if event.is_action_pressed("inventory_toggle") or event.is_action_pressed("ui_cancel"):
		if not event.is_echo():
			hide_inventory()
		get_viewport().set_input_as_handled()
	elif event.is_action("inventory_rotate_left"):
		turn_left = event.is_pressed()
		get_viewport().set_input_as_handled()
	elif event.is_action("inventory_rotate_right"):
		turn_right = event.is_pressed()
		get_viewport().set_input_as_handled()
	elif event is InputEventKey or event is InputEventAction:
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if active:
		preview.pivot.rotation.y += (float(turn_right) - float(turn_left)) * delta * 1.6

func toggle_view() -> void:
	if _dump_sequence:
		return
	if bag.active:
		bag.close()
		bag_panel.hide()
		_preview_column.show()
		grid_scroll.show()
		collapse.show()
		view_toggle.text = "BAG VIEW"
	else:
		bag.selected = selected if actor.equipment.container.contains(selected) else null
		var issue := bag.open()
		if not issue.is_empty():
			feedback.text = issue
			return
		bag_panel.show()
		_preview_column.hide()
		grid_scroll.hide()
		collapse.hide()
		view_toggle.text = "GRID VIEW"

func select_item(item: InteractableObject) -> void:
	selected = item
	bag.selected = item
	var record := InventoryItem.from_body(item)
	var size := record.dimensions()
	details.text = "%s\n%s\n\n%s\n%.2f kg · %.2f L\n%.0f × %.0f × %.0f mm" % [
		item.definition.display_name, item.definition.object_id, item.definition.condition,
		item.mass, record.volume_m3() * 1000, size.x * 1000, size.y * 1000, size.z * 1000]
	if item is FasteningTool:
		details.text += "\n\n%s\nMAGAZINE %d / %d\nRESERVE %d\n%s MODE" % [
			item.GRADES[item.grade_index].title, item.rounds.size(), item.CAPACITY, item.recovered.size(),
			"REMOVE" if item.removing else "INSTALL"]
	else:
		for key in item.definition.properties.keys().slice(0, 5):
			if key != "inventory_icon":
				details.text += "\n%s  %s" % [key, str(item.definition.properties[key]).left(100)]

func refresh() -> void:
	var reopen := bag.active
	if reopen:
		bag.close()
	var equipment := actor.equipment
	var container := equipment.container
	var mass := actor.carrying_loads()
	load_label.text = "CARRIED  %.2f kg\nLIFT REFERENCE  %.2f kg\n\nINVENTORY  %.2f kg\nEQUIPPED  %.2f kg\nEXTERNAL HOLD  %.2f kg\n\nVOLUME  %.1f / %.1f L\nCONTAINER RATING  %.1f kg" % [
		mass.total, actor.placement.lift_capacity(), mass.inventory, mass.equipped, mass.external,
		container.volume_m3() * 1000, container.definition.effective_capacity_m3() * 1000, container.definition.maximum_mass_kg]
	load_label.text += "\nNOMINAL  %.0f L%s" % [container.definition.capacity_m3 * 1000,
		" · EXPANDED" if container.volume_m3() > container.definition.capacity_m3 else ""]
	var held := equipment.held_item()
	slot_button.text = "TOOL SLOT\n" + (held.definition.display_name if held != null else "Empty")
	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()
	for item in container.items():
		var button := Button.new()
		button.custom_minimum_size = Vector2(145, 104)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var icon: String = item.definition.properties.get("inventory_icon",
			"⚙" if item is FasteningTool else ("⚒" if item.mobility() == ObjectDefinition.Mobility.CARRYABLE else "▰"))
		button.text = "%s\n%s\n%s · %.2f kg" % [icon, item.definition.display_name, item.definition.condition, item.mass]
		button.tooltip_text = "STORED · " + String(item.definition.object_id)
		button.add_theme_stylebox_override("normal", style(Color("#243439")))
		button.gui_input.connect(entry_input.bind(item))
		grid.add_child(button)
	preview.refresh(actor)
	if reopen:
		bag.selected = selected if actor.equipment.container.contains(selected) else null
		var issue := bag.open()
		if not issue.is_empty():
			feedback.text = issue

func entry_input(event: InputEvent, item: InteractableObject) -> void:
	if not event is InputEventMouseButton or not event.pressed or not is_instance_valid(item):
		return
	select_item(item)
	if event.button_index != MOUSE_BUTTON_RIGHT:
		return
	popup.clear()
	if actor.equipment.held_item() == item:
		popup.add_item("Unequip", 1)
		popup.add_item("Drop into world", 2)
	else:
		if actor.equipment.equipment_slot(item) != &"":
			popup.add_item("Equip", 0)
		popup.add_item("Retrieve into world", 2)
	popup.position = Vector2i(get_viewport().get_mouse_position())
	popup.popup()

func perform_action(id: int) -> void:
	if not is_instance_valid(selected) or _dump_sequence:
		return
	if id == 3:
		select_item(selected)
		feedback.text = "Inspection displayed."
		return
	if id == 4:
		return
	var reopen := bag.active
	if reopen:
		bag.close()
	var equipment := actor.equipment
	var result := {"ok": false, "message": "Item unavailable."}
	if id == 0:
		result = equipment.equip_item(selected)
	elif id == 1 and selected == equipment.held_item():
		result = equipment.stow()
	elif id == 2:
		result = equipment.drop() if selected == equipment.held_item() else equipment.retrieve(selected)
	feedback.text = result.message
	# A newly equipped item remains hidden behind the interface.
	equipment.presentation.set_station_active(true)
	refresh()
	if reopen:
		bag.selected = selected if equipment.container.contains(selected) else null
		var issue := bag.open()
		if not issue.is_empty():
			feedback.text = issue


func bag_context(item: InteractableObject) -> void:
	if not actor.equipment.container.contains(item):
		return
	select_item(item)
	popup.clear()
	if actor.equipment.equipment_slot(item) != &"":
		popup.add_item("Equip", 0)
	popup.add_item("Drop", 2)
	popup.add_item("Inspect", 3)
	popup.add_item("Cancel", 4)
	popup.position = Vector2i(get_viewport().get_mouse_position())
	popup.popup()

func dump_bag() -> void:
	if _dump_sequence:
		return
	_dump_sequence = true
	feedback.text = "Emptying satchel…"
	if is_instance_valid(bag.interior):
		var tween := create_tween().set_parallel()
		for body: RigidBody3D in bag.interior.proxies.values():
			tween.tween_property(body, "position", body.position + Vector3.UP * 0.04, 0.22)
		await tween.finished
	hide_inventory(true)
	var result: Dictionary = await actor.equipment.dump_container()
	_dump_sequence = false
	get_parent().call("show_feedback", result.message)

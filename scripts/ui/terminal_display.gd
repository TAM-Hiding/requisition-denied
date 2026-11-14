class_name TerminalDisplay
extends MarginContainer
## The UI lives in the workstation's screen texture, including its focus targets.
const SECTIONS := ["Messages", "Requisitions", "Inventory", "Records", "Settings"]
const PHOSPHOR := Color("a8d5a3")
var session: AdministrativeSession
var actor: OtisController
var terminal_id: StringName
var section := "Messages"
var navigation := HBoxContainer.new()
var entries := ItemList.new()
var detail := RichTextLabel.new()
var submit_button := Button.new()
var brightness := HSlider.new()
var settings_panel: MechanicalSettingsPanel
var brightness_readout := Label.new()
var footer := Label.new()
var standby := Label.new()
var interface := VBoxContainer.new()
var _selected: Variant
var _latest_event := ""
var _request_result: Dictionary = {}

func configure(data: AdministrativeSession, otis: OtisController, id: StringName) -> void:
	session = data
	actor = otis
	terminal_id = id
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	resized.connect(queue_redraw)
	add_child(interface)
	for side in ["left", "right", "top", "bottom"]:
		add_theme_constant_override("margin_" + side, 24)
	interface.add_theme_constant_override("separation", 12)
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["IBM Plex Mono", "DejaVu Sans Mono", "monospace"])
	var appearance := Theme.new()
	appearance.default_font = mono
	appearance.default_font_size = 21
	for type in ["Label", "Button", "ItemList", "CheckBox", "LineEdit"]:
		appearance.set_color("font_color", type, PHOSPHOR)
	appearance.set_color("default_color", "RichTextLabel", PHOSPHOR)
	appearance.set_color("font_selected_color", "ItemList", Color("dcf5d5"))
	appearance.set_color("font_focus_color", "Button", Color("dcf5d5"))
	appearance.set_color("font_placeholder_color", "LineEdit", Color("789473"))
	appearance.set_color("caret_color", "LineEdit", PHOSPHOR)
	appearance.set_stylebox("normal", "LineEdit", _frame(Color("0c1b12"), Color("435c43")))
	appearance.set_stylebox("focus", "LineEdit", _frame(Color.TRANSPARENT, PHOSPHOR))
	appearance.set_stylebox("normal", "Button", _frame(Color("14251a"), Color("435c43")))
	appearance.set_stylebox("hover", "Button", _frame(Color("223b28"), Color("799676")))
	appearance.set_stylebox("pressed", "Button", _frame(Color("294a30"), Color("a1c597")))
	appearance.set_stylebox("focus", "Button", _frame(Color.TRANSPARENT, PHOSPHOR))
	appearance.set_stylebox("panel", "ItemList", _frame(Color("0c1b12"), Color("435c43")))
	appearance.set_stylebox("selected", "ItemList", _frame(Color("294a30"), Color("638465")))
	appearance.set_stylebox("focus", "ItemList", _frame(Color.TRANSPARENT, PHOSPHOR))
	appearance.set_stylebox("normal", "RichTextLabel", _frame(Color("0c1b12"), Color("435c43")))
	theme = appearance

	var masthead := HBoxContainer.new()
	interface.add_child(masthead)
	var heading := Label.new()
	heading.text = "THE FACILITY   /   ADMINISTRATIVE TERMINAL"
	heading.add_theme_font_size_override("font_size", 28)
	heading.size_flags_horizontal = SIZE_EXPAND_FILL
	masthead.add_child(heading)
	var insignia := Label.new()
	insignia.text = "▣"
	insignia.modulate.a = 0.45
	insignia.add_theme_font_size_override("font_size", 29)
	masthead.add_child(insignia)
	interface.add_child(navigation)
	var group := ButtonGroup.new()
	for name in SECTIONS:
		var button := Button.new()
		button.text = name.to_upper()
		button.toggle_mode = true
		button.button_group = group
		button.size_flags_horizontal = SIZE_EXPAND_FILL
		button.pressed.connect(show_section.bind(name))
		navigation.add_child(button)

	var columns := HBoxContainer.new()
	columns.size_flags_vertical = SIZE_EXPAND_FILL
	columns.add_theme_constant_override("separation", 12)
	interface.add_child(columns)
	entries.custom_minimum_size.x = 362
	entries.add_theme_font_size_override("font_size", 18)
	entries.item_selected.connect(_select_entry)
	columns.add_child(entries)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = SIZE_EXPAND_FILL
	columns.add_child(right)
	detail.size_flags_vertical = SIZE_EXPAND_FILL
	detail.add_theme_font_size_override("normal_font_size", 23)
	right.add_child(detail)
	submit_button.text = "SUBMIT REQUEST"
	submit_button.pressed.connect(_submit)
	right.add_child(submit_button)
	brightness.min_value = 0.45
	brightness.max_value = 1.0
	brightness.step = 0.01
	brightness.custom_minimum_size.y = 28
	brightness.set_value_no_signal(session.text_brightness)
	brightness.value_changed.connect(_set_brightness)
	settings_panel = MechanicalSettingsPanel.new()
	settings_panel.settings = actor.placement.mechanical_settings
	settings_panel.size_flags_vertical = SIZE_EXPAND_FILL
	right.add_child(settings_panel)
	settings_panel.brightness_slot.add_child(brightness_readout)
	settings_panel.brightness_slot.add_child(brightness)
	interface.add_child(footer)
	footer.add_theme_font_size_override("font_size", 16)
	standby.text = "▣  THE FACILITY\nADMINISTRATIVE WORKSTATION\n\nOPERATIONAL  /  [E] ACCESS"
	standby.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	standby.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	standby.add_theme_font_size_override("font_size", 30)
	add_child(standby)
	session.event_published.connect(_observe_event)
	actor.equipment.changed.connect(_equipment_changed)
	_set_brightness(session.text_brightness)
	set_active(false)

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("08120d"))

func set_active(active: bool) -> void:
	interface.visible = active
	standby.visible = not active
	if active:
		show_section(section)
		for button: Button in navigation.get_children():
			if button.button_pressed:
				button.grab_focus()
				break

func show_section(value: String) -> void:
	if value not in SECTIONS:
		return
	section = value
	for index in SECTIONS.size():
		(navigation.get_child(index) as Button).set_pressed_no_signal(SECTIONS[index] == value)
	_selected = null
	_request_result = {}
	entries.clear()
	entries.visible = value in ["Messages", "Requisitions", "Records"]
	submit_button.hide()
	settings_panel.visible = value == "Settings"
	detail.visible = value != "Settings"
	match value:
		"Messages":
			_fill_messages()
			detail.text = "ADMINISTRATIVE INBOX\n\nSelect a message to read it."
		"Requisitions":
			_fill_requests()
			detail.text = "REQUISITION CATALOG\n\nSelect an allocation or review a submitted request."
		"Inventory":
			_show_inventory()
		"Records":
			for id in actor.knowledge.inspected_ids():
				var facts := actor.knowledge.records_for(id)
				_add_entry(facts.back().name, id)
			detail.text = "OTIS / INSPECTION RECORDS\n\n" + ("No objects inspected." if entries.item_count == 0 else "Select an inspected object.")
		"Settings":
			settings_panel.refresh()
	_update_footer()

func _add_entry(label: String, metadata: Variant) -> void:
	var index := entries.add_item(label)
	entries.set_item_metadata(index, metadata)
	entries.set_item_tooltip(index, label)

func _fill_messages() -> void:
	entries.clear()
	for message in session.messages():
		_add_entry(("%s  " % (" " if message.read else "●")) + message.subject, message.id)
		if message.id == _selected:
			entries.select(entries.item_count - 1)

func _fill_requests() -> void:
	entries.clear()
	for id in AdministrativeSession.CATALOG:
		_add_entry(AdministrativeSession.CATALOG[id].name, id)
	for request in session.requests():
		_add_entry("%s  %s" % [request.id, AdministrativeSession.RequestStatus.keys()[request.status]], request)
		if _request_result.get("id") == request.id:
			entries.select(entries.item_count - 1)

func _select_entry(index: int) -> void:
	_selected = entries.get_item_metadata(index)
	match section:
		"Messages":
			var message := session.read_message(_selected)
			detail.text = "%s\nFROM  %s\n\n%s" % [message.subject.to_upper(), message.sender, message.body]
			_fill_messages()
			_update_footer()
		"Requisitions":
			submit_button.visible = _selected is StringName
			if _selected is Dictionary:
				_show_request(_selected)
			else:
				var entry: Dictionary = AdministrativeSession.CATALOG[_selected]
				detail.text = "%s\n\n%s\n\n%s" % [entry.name.to_upper(), entry.description, entry.eligibility]
		"Records":
			var notes := PackedStringArray()
			for fact in actor.knowledge.records_for(_selected):
				notes.append("%s\n%s" % [fact.name.to_upper(), fact.description])
			detail.text = "%s\n\n%s" % [_selected, "\n\n".join(notes)]

func _submit() -> void:
	if section != "Requisitions" or not (_selected is StringName):
		return
	_request_result = session.submit(_selected, terminal_id)
	if _request_result.is_empty():
		return
	_selected = _request_result
	_fill_requests()
	_show_request(_request_result)
	submit_button.hide()
	entries.grab_focus()

func _show_request(request: Dictionary) -> void:
	detail.text = "%s\n\nREFERENCE  %s\nSTATUS     %s\n\n%s" % [
		request.name.to_upper(), request.id, AdministrativeSession.RequestStatus.keys()[request.status], request.reason]

func _equipment_changed() -> void:
	if section == "Inventory":
		_show_inventory()

func _show_inventory() -> void:
	var held := actor.equipment.held_item()
	var stored := actor.equipment.stored_items()
	var names := PackedStringArray()
	for item in stored:
		names.append(item.definition.display_name)
	detail.text = "PERSONNEL EQUIPMENT RECORD / OTIS\n\nEQUIPPED\n%s\n\nSTORED  %d / %d\n%s" % [
		held.definition.display_name if held != null else "None", stored.size(), actor.equipment.storage_capacity,
		"\n".join(names) if not names.is_empty() else "None"]
	detail.text += "\n\nOTIS / UNIT DIAGNOSTICS\n\nCHASSIS CONFIGURATION  STANDARD\nMAXIMUM LIFT  %.2f kg\nWALK SPEED    %.2f m/s\nACCELERATION  %.2f m/s²\nCHASSIS MASS  %.2f kg\n\nSTATUS  OPERATIONAL" % [
		actor.chassis.effective(AndroidChassis.Attribute.LIFT_KG), actor.movement_speed,
		actor.acceleration, actor.body_mass_kg]

func _set_brightness(value: float) -> void:
	session.text_brightness = value
	interface.modulate = Color(value, value, value)
	brightness_readout.text = "CRT text brightness  %d%%" % roundi(session.text_brightness * 100.0)

func _observe_event(event: Dictionary) -> void:
	_latest_event = String(event.type).replace("_", " ")
	_update_footer()

func _update_footer() -> void:
	footer.text = "OPERATIONAL  /  UNREAD %d  /  ESC EXIT" % session.unread_count()
	if not _latest_event.is_empty():
		footer.text += "  /  " + _latest_event

func _frame(fill: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(2)
	style.border_width_bottom = 3
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style

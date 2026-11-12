class_name MechanicalSettingsPanel
extends VBoxContainer

signal browse_requested
## CRT controls over the existing live configuration and JSON storage.
const SECTIONS := ["CONTROLS", "MECHANICS", "VISUALS", "DEVELOPMENT"]
const INSTALLATION_LABELS := {
	"acquisition_distance_m": "Acquisition distance (m)",
	"snap_distance_m": "Snap distance (m)",
	"axis_tolerance_degrees": "Insertion-axis tolerance (°)",
	"key_rotation_tolerance_degrees": "Key alignment tolerance (°)",
	"snap_duration_seconds": "Installation duration (s)",
}
const CONTROL_LABELS := {
	"mouse_sensitivity": "Mouse sensitivity",
	"precision_rotation_sensitivity": "Precision rotation sensitivity",
	"ads_sensitivity_multiplier": "ADS sensitivity multiplier",
}
const CONTROL_REFERENCE := "WASD Move   ·   E Context   ·   Hold G Manipulate\nG Place   ·   1 Equip / stow tool   ·   X Drop Uni-Bolt\nLMB Operate tool   ·   Hold RMB Aim   ·   R Mode\nMiddle mouse Rotate   ·   Wheel Adjust range   ·   Esc Exit"
const DEVELOPMENT_REFERENCE := "F3 Diagnostics\nF5 Ram drive   ·   F6 / Shift+F6 Adjust force   ·   F7 Reset\nF8 Cycle grade   ·   F9 Refill test ammunition"

var settings: MechanicalInteractionSettings
var pages: Array[ScrollContainer] = []
var tabs := HBoxContainer.new()
var fields := {}
var toggles := {}
var message := Label.new()
var import_path := LineEdit.new()
var brightness_slot := VBoxContainer.new()
var section_index := 0

func _ready() -> void:
	add_theme_constant_override("separation", 7)
	add_child(tabs)
	var group := ButtonGroup.new()
	var contents := VBoxContainer.new()
	contents.size_flags_vertical = SIZE_EXPAND_FILL
	add_child(contents)
	for title in SECTIONS:
		var index := pages.size()
		var tab := Button.new()
		tab.text = title
		tab.toggle_mode = true
		tab.button_group = group
		tab.size_flags_horizontal = SIZE_EXPAND_FILL
		tab.pressed.connect(show_settings.bind(index))
		tabs.add_child(tab)
		var scroll := ScrollContainer.new()
		scroll.size_flags_vertical = SIZE_EXPAND_FILL
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		scroll.follow_focus = true
		contents.add_child(scroll)
		pages.append(scroll)

	var controls := page(0)
	for key: String in CONTROL_LABELS:
		add_number(controls, "controls", key, CONTROL_LABELS[key], MechanicalInteractionSettings.CONTROL_LIMITS[key], 0.05 if key == "ads_sensitivity_multiplier" else 0.0001)
	add_toggle(controls, "rotation", "invert_horizontal", "Invert horizontal rotation")
	add_toggle(controls, "rotation", "invert_vertical", "Invert vertical rotation")
	add_text(controls, CONTROL_REFERENCE)

	var mechanics := page(1)
	for key: String in INSTALLATION_LABELS:
		add_number(mechanics, "installation", key, INSTALLATION_LABELS[key],
			MechanicalInteractionSettings.LIMITS[key], 1.0 if key.ends_with("_degrees") else 0.01)

	var visuals := page(2)
	add_number(visuals, "", MechanicalInteractionSettings.VISUAL_SCALE_KEY,
		"Fastener Visual Scale (%)", Vector2(75, 250), 5.0)
	visuals.add_child(brightness_slot)

	var development := page(3)
	add_toggle(development, "pickup", "show_clearance_diagnostics", "Pickup clearance diagnostics")
	add_toggle(development, "debug", "show_alignment_diagnostics", "Alignment diagnostics")
	add_text(development, DEVELOPMENT_REFERENCE)
	var actions := HBoxContainer.new()
	development.add_child(actions)
	add_button(actions, "SAVE", save)
	add_button(actions, "RESET DEFAULTS", reset)
	add_button(actions, "EXPORT JSON", export_snapshot)
	var import_row := HBoxContainer.new()
	development.add_child(import_row)
	import_path.placeholder_text = "Snapshot path (.json or user://…)"
	import_path.size_flags_horizontal = SIZE_EXPAND_FILL
	import_row.add_child(import_path)
	import_path.text_submitted.connect(import_snapshot)
	add_button(import_row, "BROWSE", func() -> void: browse_requested.emit())
	add_button(import_row, "IMPORT JSON", func() -> void: import_snapshot(import_path.text))

	message.add_theme_font_size_override("font_size", 17)
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(message)
	message.text = "Changes apply live. Save in Development to keep them after restart."
	settings.changed.connect(refresh)
	refresh()
	show_settings(0)

func page(index: int) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 5)
	pages[index].add_child(column)
	return column

func show_settings(index: int) -> void:
	section_index = index
	for i in pages.size():
		pages[i].visible = i == index
		(tabs.get_child(i) as Button).set_pressed_no_signal(i == index)

func add_number(parent: Container, section: String, key: String, label: String, bounds: Vector2, step: float) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var text := Label.new()
	text.text = label
	text.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(text)
	var field := SpinBox.new()
	field.min_value = snappedf(bounds.x, 0.00001)
	field.max_value = snappedf(bounds.y, 0.00001)
	field.step = step
	field.custom_minimum_size.x = 165
	row.add_child(field)
	fields[key] = [section, field]
	field.value_changed.connect(func(value: float) -> void: update_field(section, key, value))

func add_toggle(parent: Container, section: String, key: String, label: String) -> void:
	var toggle := CheckBox.new()
	toggle.text = label
	parent.add_child(toggle)
	toggles[key] = [section, toggle]
	toggle.toggled.connect(func(value: bool) -> void: update_field(section, key, value))

func add_text(parent: Container, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 18)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)

func add_button(parent: Container, caption: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = caption
	parent.add_child(button)
	button.pressed.connect(callback)

func refresh() -> void:
	for key: String in fields:
		var entry: Array = fields[key]
		var source: Dictionary = settings.values if entry[0].is_empty() else settings.values[entry[0]]
		entry[1].set_value_no_signal(source[key])
	for key: String in toggles:
		var entry: Array = toggles[key]
		entry[1].set_pressed_no_signal(settings.values[entry[0]][key])

func update_field(section: String, key: String, value: Variant) -> void:
	var candidate := settings.values.duplicate(true)
	if section.is_empty():
		candidate[key] = value
	else:
		candidate[section][key] = value
	var issue := settings.apply(candidate)
	message.text = "Live settings updated." if issue.is_empty() else issue
	if not issue.is_empty():
		refresh()

func save() -> void:
	var issue := settings.save_file()
	message.text = "Saved for the next launch." if issue.is_empty() else issue

func reset() -> void:
	settings.reset()
	message.text = "Defaults restored. Save to keep them after restart."

func export_snapshot() -> void:
	var path := settings.export_snapshot()
	if not path.is_empty():
		import_path.text = path
	message.text = "Exported to " + path if not path.is_empty() else "Could not write snapshot."

func import_snapshot(path: String) -> void:
	import_path.text = path.strip_edges()
	var issue := settings.load_file(import_path.text)
	message.text = "Snapshot applied. Save to keep it after restart." if issue.is_empty() else issue

class_name MechanicalSettingsPanel
extends PanelContainer

signal closed
signal changed

const NUMBERS := {
	"acquisition_distance_m": "Acquisition distance (m)",
	"snap_distance_m": "Snap distance (m)",
	"axis_tolerance_degrees": "Insertion-axis tolerance (°)",
	"key_rotation_tolerance_degrees": "Key rotation tolerance (°)",
	"snap_duration_seconds": "Snap duration (s)",
}
const SWITCHES := [
	["pickup", "show_clearance_diagnostics", "Pickup clearance diagnostics"],
	["debug", "show_alignment_diagnostics", "Alignment diagnostics"],
	["rotation", "invert_horizontal", "Invert horizontal rotation"],
	["rotation", "invert_vertical", "Invert vertical rotation"],
]

var settings: MechanicalInteractionSettings
var fields := {}
var switches: Array[CheckBox] = []
var message: Label
var picker: FileDialog
var updating := false

func _ready() -> void:
	var margin := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 18)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	margin.add_child(column)
	var title := Label.new()
	title.text = "Development / Mechanical Interaction"
	title.add_theme_font_size_override("font_size", 22)
	column.add_child(title)
	var grid := GridContainer.new()
	grid.columns = 2
	column.add_child(grid)
	for key: String in NUMBERS:
		var label := Label.new()
		label.text = NUMBERS[key]
		grid.add_child(label)
		var field := SpinBox.new()
		var limits: Vector2 = MechanicalInteractionSettings.LIMITS[key]
		field.min_value = snappedf(limits.x, 0.001)
		field.max_value = snappedf(limits.y, 0.001)
		field.step = 1.0 if key.ends_with("_degrees") else 0.01
		field.custom_minimum_size.x = 115
		grid.add_child(field)
		fields[key] = field
		field.value_changed.connect(func(_value: float) -> void: apply_fields())
	for spec in SWITCHES:
		var toggle := CheckBox.new()
		toggle.text = spec[2]
		column.add_child(toggle)
		switches.append(toggle)
		toggle.toggled.connect(func(_enabled: bool) -> void: apply_fields())
	var buttons := GridContainer.new()
	buttons.columns = 2
	column.add_child(buttons)
	add_button(buttons, "Save Settings", save)
	add_button(buttons, "Reset to Defaults", reset)
	add_button(buttons, "Export Snapshot", export_snapshot)
	add_button(buttons, "Import Snapshot", show_import)
	message = Label.new()
	message.custom_minimum_size = Vector2(380, 50)
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.text = "Changes apply live. Save to keep them after restart."
	column.add_child(message)
	add_button(column, "Close [Esc]", func() -> void: closed.emit())
	picker = FileDialog.new()
	picker.title = "Import Mechanical Interaction Snapshot"
	picker.access = FileDialog.ACCESS_FILESYSTEM
	picker.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	picker.add_filter("*.json", "Mechanical settings")
	add_child(picker)
	picker.file_selected.connect(import_snapshot)
	refresh()

func add_button(parent: Container, caption: String, action: Callable) -> void:
	var button := Button.new()
	button.text = caption
	parent.add_child(button)
	button.pressed.connect(action)

func refresh() -> void:
	updating = true
	for key: String in fields:
		fields[key].set_value_no_signal(settings.values.installation[key])
	for index in SWITCHES.size():
		var spec: Array = SWITCHES[index]
		switches[index].set_pressed_no_signal(settings.values[spec[0]][spec[1]])
	updating = false

func apply_fields() -> bool:
	if updating:
		return false
	var candidate := settings.values.duplicate(true)
	for key: String in fields:
		candidate.installation[key] = fields[key].value
	for index in SWITCHES.size():
		var spec: Array = SWITCHES[index]
		candidate[spec[0]][spec[1]] = switches[index].button_pressed
	var issue := settings.apply(candidate)
	message.text = "Live settings updated." if issue.is_empty() else issue
	if issue.is_empty():
		changed.emit()
	return issue.is_empty()

func save() -> void:
	if apply_fields():
		var issue := settings.save_file()
		message.text = "Saved for the next launch." if issue.is_empty() else issue

func reset() -> void:
	settings.reset()
	refresh()
	message.text = "Defaults restored. Save to keep them after restart."
	changed.emit()

func export_snapshot() -> void:
	if apply_fields():
		var path := settings.export_snapshot()
		message.text = "Exported to " + path if not path.is_empty() else "Could not write snapshot."

func show_import() -> void:
	picker.current_dir = ProjectSettings.globalize_path("user://")
	picker.popup_centered_clamped(Vector2i(720, 490))

func import_snapshot(path: String) -> void:
	var issue := settings.load_file(path)
	message.text = "Snapshot applied. Save to keep it after restart." if issue.is_empty() else issue
	if issue.is_empty():
		refresh()
		changed.emit()

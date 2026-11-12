class_name RamControlPanel
extends MarginContainer

const PHOSPHOR := Color("c4d5a0")
var ram: StructuralTestRam
var force_slider := HSlider.new()
var readout := Label.new()
var buttons := {}

func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	resized.connect(queue_redraw)
	var mono := SystemFont.new()
	mono.font_names = PackedStringArray(["IBM Plex Mono", "DejaVu Sans Mono", "monospace"])
	var appearance := Theme.new()
	appearance.default_font = mono
	appearance.default_font_size = 22
	appearance.set_color("font_color", "Label", PHOSPHOR)
	appearance.set_color("font_color", "Button", PHOSPHOR)
	for state in ["normal", "hover", "pressed", "focus"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("273124") if state in ["hover", "pressed"] else Color("172016")
		style.border_color = PHOSPHOR if state == "focus" else Color("667550")
		style.set_border_width_all(2)
		style.content_margin_top = 7
		style.content_margin_bottom = 7
		appearance.set_stylebox(state, "Button", style)
	theme = appearance
	for side in ["left", "right", "top", "bottom"]:
		add_theme_constant_override("margin_" + side, 26)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	add_child(column)
	var title := Label.new()
	title.text = "STRUCTURAL TEST ACTUATOR"
	title.add_theme_font_size_override("font_size", 31)
	column.add_child(title)
	readout.size_flags_vertical = SIZE_EXPAND_FILL
	readout.add_theme_font_size_override("font_size", 26)
	column.add_child(readout)
	var force := HBoxContainer.new()
	column.add_child(force)
	button(force, "FORCE −", ram.change_force.bind(-1))
	force_slider.max_value = StructuralTestRam.FORCE_STEPS.size() - 1
	force_slider.step = 1
	force_slider.size_flags_horizontal = SIZE_EXPAND_FILL
	force_slider.value_changed.connect(func(value: float) -> void: ram.set_force_index(roundi(value)))
	force.add_child(force_slider)
	button(force, "FORCE +", ram.change_force.bind(1))
	var controls := HBoxContainer.new()
	column.add_child(controls)
	button(controls, "EXTEND", ram.set_drive.bind(StructuralTestRam.Drive.EXTEND))
	button(controls, "RETRACT", ram.set_drive.bind(StructuralTestRam.Drive.RETRACT))
	button(controls, "STOP", ram.set_drive.bind(StructuralTestRam.Drive.IDLE))
	button(controls, "RESET", ram.reset_ram)
	var footer := Label.new()
	footer.text = "ESC EXIT   /   RESET RETRACTS THE RAM"
	column.add_child(footer)
	refresh()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), Color("10180f"))

func _process(_delta: float) -> void:
	refresh()

func refresh() -> void:
	force_slider.set_value_no_signal(ram.force_index)
	readout.text = "FORCE LIMIT  %06d\nAPPLIED LOAD %06d\nSTROKE       %.2f / %.2f m\nSTATUS       %s" % [
		roundi(ram.force_limit()), roundi(ram.actual_load), ram.travel, StructuralTestRam.STROKE, ram.status_text()]

func button(parent: Container, title: String, callback: Callable) -> void:
	var control := Button.new()
	control.text = title
	control.size_flags_horizontal = SIZE_EXPAND_FILL
	control.pressed.connect(callback)
	parent.add_child(control)
	buttons[title] = control

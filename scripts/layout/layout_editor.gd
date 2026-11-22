class_name LayoutEditor
extends Control
signal active_changed(enabled: bool)
## Administrative input owner. Otis keeps normal movement while the cursor is captured.
const WORKSHOP_ARGUMENT := "--workshop-layout"

var _development_access := OS.is_debug_build() and OS.get_cmdline_user_args().has(WORKSHOP_ARGUMENT)
var actor: OtisController
var workspace: LayoutWorkspace
var active := false
var snap_enabled := true
var snap_step := 0.25
var pending: Dictionary = {}
var preview: LayoutPlaceholder
var nudge := Vector3.ZERO
var _previous_mouse_mode: Input.MouseMode
var _previous_placement_suspension := false

var panel: PanelContainer
var catalog: OptionButton
var item_list: ItemList
var dimension_inputs: Array[SpinBox] = []
var name_input: LineEdit
var notes_input: LineEdit
var edit_controls: VBoxContainer
var feedback: Label
var reticle: Label
var dialog: FileDialog

func configure(hall: Node3D, otis: OtisController) -> void:
	actor = otis
	workspace = LayoutWorkspace.new()
	workspace.name = "EquipmentLayout"
	workspace.actor = otis
	workspace.hall = hall
	hall.add_child(workspace)

func _ready() -> void:
	hide()
	if not _development_access:
		set_physics_process(false)
		return
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var guide := Label.new()
	guide.position = Vector2(22, 18)
	guide.text = "THE FACILITY   /   ENGINEERING LAYOUT"
	guide.add_theme_color_override("font_color", Color("b2ded4"))
	add_child(guide)
	feedback = Label.new()
	feedback.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	feedback.position += Vector2(22, -76)
	add_child(feedback)
	var controls := Label.new()
	controls.text = "Tab  Tools   ·   LMB  Select/place   ·   G  Move   ·   R/Shift+R  Rotate   ·   Arrows  Nudge   ·   Shift  Free snap   ·   Esc/L  Exit"
	controls.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	controls.position += Vector2(22, -40)
	add_child(controls)
	reticle = Label.new()
	reticle.text = "+"
	reticle.size = Vector2(24, 24)
	reticle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	reticle.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	reticle.position -= Vector2(12, 12)
	add_child(reticle)
	for label in [guide, feedback, controls, reticle]:
		label.add_theme_color_override("font_outline_color", Color("102124"))
		label.add_theme_constant_override("outline_size", 4)
	build_panel()

func build_panel() -> void:
	panel = PanelContainer.new()
	panel.position = Vector2(22, 58)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("16272b")
	style.border_color = Color("49615e")
	style.set_border_width_all(1)
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)
	var column := VBoxContainer.new()
	column.custom_minimum_size.x = 350
	panel.add_child(column)
	var title := Label.new()
	title.text = "Equipment layout"
	title.add_theme_font_size_override("font_size", 21)
	column.add_child(title)
	var spawn_row := HBoxContainer.new()
	column.add_child(spawn_row)
	catalog = OptionButton.new()
	catalog.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for type in LayoutCatalog.types():
		catalog.add_item(LayoutCatalog.definition(type).name)
		catalog.set_item_metadata(catalog.item_count - 1, type)
	spawn_row.add_child(catalog)
	button(spawn_row, "Spawn", spawn_requested)
	item_list = ItemList.new()
	item_list.custom_minimum_size.y = 104
	item_list.item_selected.connect(func(index: int) -> void:
		workspace.select(item_list.get_item_metadata(index))
		refresh_properties())
	column.add_child(item_list)
	var actions := HBoxContainer.new()
	column.add_child(actions)
	button(actions, "Move", func() -> void: move_selected(false))
	button(actions, "Duplicate", func() -> void: move_selected(true))
	button(actions, "Delete", delete_selected)

	edit_controls = VBoxContainer.new()
	column.add_child(edit_controls)
	name_input = LineEdit.new()
	name_input.max_length = 80
	name_input.placeholder_text = "Display name"
	edit_controls.add_child(name_input)
	notes_input = LineEdit.new()
	notes_input.max_length = 160
	notes_input.placeholder_text = "Planning note"
	edit_controls.add_child(notes_input)
	var dimensions := HBoxContainer.new()
	edit_controls.add_child(dimensions)
	for caption in ["Width", "Height", "Depth"]:
		var axis := VBoxContainer.new()
		dimensions.add_child(axis)
		var label := Label.new()
		label.text = caption
		axis.add_child(label)
		dimension_inputs.append(spinner(axis, 0.10, 40.00, 0.0001, 1.0, "m"))
	button(edit_controls, "Apply dimensions and name", apply_properties)
	var snapping := HBoxContainer.new()
	column.add_child(snapping)
	var check_snap := CheckButton.new()
	check_snap.text = "Grid"
	check_snap.button_pressed = snap_enabled
	check_snap.toggled.connect(func(enabled: bool) -> void: snap_enabled = enabled)
	snapping.add_child(check_snap)
	var increment := spinner(snapping, 0.01, 2.0, 0.01, snap_step, "m")
	increment.value_changed.connect(func(value: float) -> void: snap_step = value)
	var files := HBoxContainer.new()
	column.add_child(files)
	button(files, "Save layout", save_layout)
	button(files, "Load…", open_file.bind(false))
	button(files, "Export JSON…", open_file.bind(true))
	var footer := HBoxContainer.new()
	column.add_child(footer)
	button(footer, "Walk and aim  [Tab]", show_panel.bind(false)).focus_mode = Control.FOCUS_NONE
	button(footer, "Exit layout  [Esc]", leave).focus_mode = Control.FOCUS_NONE

	dialog = FileDialog.new()
	dialog.size = Vector2i(760, 500)
	dialog.filters = PackedStringArray(["*.json ; Engineering layout JSON"])
	dialog.deleting_enabled = false
	dialog.file_selected.connect(file_selected)
	add_child(dialog)

func button(parent: Container, caption: String, action: Callable) -> Button:
	var widget := Button.new()
	widget.text = caption
	widget.pressed.connect(action)
	parent.add_child(widget)
	return widget

func spinner(parent: Container, low: float, high: float, step: float, initial: float, unit: String) -> SpinBox:
	var widget := SpinBox.new()
	widget.min_value = low
	widget.max_value = high
	widget.step = step
	widget.value = initial
	widget.suffix = unit
	widget.custom_minimum_size.x = 100
	parent.add_child(widget)
	return widget

func has_development_access() -> bool:
	return _development_access

func can_enter() -> bool:
	if not _development_access or not actor.controls_enabled or actor.locomotion.climbing or actor.placement.is_active():
		return false
	var point := workspace.hall.to_local(actor.global_position)
	return _within_hall_footprint(point) and workspace.has_support_near(point)

func _within_hall_footprint(point: Vector3) -> bool:
	return absf(point.x) < float(workspace.hall.get("width")) / 2 and point.z >= 0.0 \
		and point.z < float(workspace.hall.get("depth"))

func enter() -> void:
	if active or not can_enter():
		return
	active = true
	_previous_mouse_mode = Input.mouse_mode
	_previous_placement_suspension = actor.placement.input_suspended
	actor.set_tool_aiming(false)
	actor.placement.clear_gesture()
	actor.placement.set_input_suspended(true)
	workspace.set_editing(true)
	show()
	show_panel(true)
	report("Choose a placeholder, or press Tab to walk and select.")
	active_changed.emit(true)

func leave() -> void:
	if not active:
		return
	dialog.hide()
	cancel_preview()
	workspace.set_editing(false)
	actor.locomotion.cancel_input()
	actor.placement.set_input_suspended(_previous_placement_suspension)
	Input.mouse_mode = _previous_mouse_mode
	active = false
	hide()
	active_changed.emit(false)

func show_panel(enabled: bool) -> void:
	panel.visible = enabled
	reticle.visible = not enabled
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if enabled else Input.MOUSE_MODE_CAPTURED
	if enabled:
		refresh_list()

func route(event: InputEvent) -> bool:
	if not active or dialog.visible:
		return false
	if event is InputEventKey and event.pressed and not event.echo:
		var key: Key = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
		# Text fields can accept ordinary letters while the panel owns the mouse.
		if key == KEY_TAB:
			show_panel(not panel.visible)
			return true
		if key == KEY_ESCAPE or (key == KEY_L and not panel.visible):
			if key == KEY_ESCAPE and not pending.is_empty() and not panel.visible:
				cancel_preview()
			else:
				leave()
			return true
		if not panel.visible:
			return walk_shortcut(key, event.shift_pressed, event.ctrl_pressed)
	if panel.visible or not event is InputEventMouseButton:
		return false
	if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		# Process after physics has synchronized the current camera and world.
		_click_requested = true
		return true
	if event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		cancel_preview()
		return true
	return false

func walk_shortcut(key: Key, fine: bool, fine_rotation: bool) -> bool:
	if key == KEY_G:
		move_selected(false)
		return true
	if pending.is_empty():
		return false
	if key == KEY_R:
		var step := 1.0 if fine_rotation else 15.0
		pending.yaw = wrapf(pending.yaw + deg_to_rad(-step if fine else step), -PI, PI)
		return true
	var delta := Vector3.ZERO
	match key:
		KEY_LEFT: delta.x = -1
		KEY_RIGHT: delta.x = 1
		KEY_UP: delta.z = -1
		KEY_DOWN: delta.z = 1
		_: return false
	nudge += delta * (0.01 if fine else 0.05)
	return true

var _click_requested := false

func _physics_process(_delta: float) -> void:
	if not active:
		return
	if not _within_hall_footprint(workspace.hall.to_local(actor.global_position)):
		leave()
		return
	if panel.visible or dialog.visible:
		_click_requested = false
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var clicked := _click_requested
	_click_requested = false
	if pending.is_empty():
		if clicked:
			workspace.select(workspace.cursor_pick(camera))
			report("Selected %s." % workspace.record(workspace.active_id).name if not workspace.active_id.is_empty()
				else "Aim at equipment to select it, or use the list.")
		return
	var hit: Variant = workspace.cursor_floor(camera)
	preview.visible = hit is Vector3
	if not preview.visible:
		report("Aim at the hall floor or mezzanine to place.")
		return
	pending.position = snapped_floor(hit, snap_enabled and not Input.is_physical_key_pressed(KEY_SHIFT), snap_step) + nudge
	preview.position = pending.position
	preview.rotation.y = pending.yaw
	var issue := workspace.validate_placement(pending, workspace.records(), workspace.excluded_bodies())
	preview.set_highlight(true, issue.is_empty())
	report("Place %s   •   R rotate   •   RMB cancel" % pending.name if issue.is_empty() else issue)
	if clicked and issue.is_empty():
		var result := workspace.upsert(pending)
		if result.is_empty():
			var caption: String = pending.name
			cancel_preview()
			report("Placed %s." % caption)
		else:
			report(result)

static func snapped_floor(point: Vector3, enabled: bool, step: float) -> Vector3:
	return Vector3(snappedf(point.x, step), point.y, snappedf(point.z, step)) if enabled else point

func spawn_requested() -> void:
	if catalog.selected >= 0:
		start_preview(workspace.new_record(catalog.get_item_metadata(catalog.selected)))

func move_selected(duplicate: bool) -> void:
	var record := workspace.record(workspace.active_id)
	if record.is_empty():
		report("Select a placeholder first.")
		return
	if duplicate:
		record.id = workspace.new_record(record.type).id
	start_preview(record)

func start_preview(candidate: Dictionary) -> void:
	if candidate.is_empty():
		return
	cancel_preview()
	pending = candidate
	preview = LayoutPlaceholder.new()
	workspace.add_child(preview)
	preview.configure(candidate, true)
	preview.set_editing(true)
	preview.hide()
	show_panel(false)

func cancel_preview() -> void:
	if is_instance_valid(preview):
		preview.hide()
		preview.queue_free()
	preview = null
	pending = {}
	nudge = Vector3.ZERO
	_click_requested = false

func delete_selected() -> void:
	if workspace.active_id.is_empty():
		report("Select a placeholder first.")
		return
	cancel_preview()
	workspace.remove(workspace.active_id)
	refresh_list()
	report("Placeholder deleted from the working layout.")

func apply_properties() -> void:
	var candidate := workspace.record(workspace.active_id)
	if candidate.is_empty():
		return
	var caption := name_input.text.strip_edges()
	if caption.is_empty():
		report("Enter a display name.")
		return
	candidate.name = caption
	candidate.size = Vector3(dimension_inputs[0].value, dimension_inputs[1].value, dimension_inputs[2].value)
	candidate.properties["notes"] = notes_input.text
	var issue := workspace.upsert(candidate)
	if issue.is_empty():
		refresh_list()
		report("Updated %s." % caption)
	else:
		report(issue)

func refresh_list() -> void:
	item_list.clear()
	for record in workspace.records():
		var index := item_list.add_item(record.name)
		item_list.set_item_metadata(index, record.id)
		if record.id == workspace.active_id:
			item_list.select(index)
	refresh_properties()

func refresh_properties() -> void:
	var record := workspace.record(workspace.active_id)
	edit_controls.visible = not record.is_empty()
	if record.is_empty():
		return
	name_input.text = record.name
	notes_input.text = str(record.properties.get("notes", ""))
	for axis in 3:
		dimension_inputs[axis].value = record.size[axis]

func layout_filename() -> String:
	return "hall-" + Time.get_datetime_string_from_system().replace(":", "").replace("T", "-") + ".json"

func save_layout() -> void:
	var issue := LayoutStorage.ensure_directory()
	if not issue.is_empty():
		report(issue)
		return
	var filename := layout_filename()
	var path := LayoutStorage.DIRECTORY.path_join(filename)
	var suffix := 2
	while FileAccess.file_exists(path):
		path = LayoutStorage.DIRECTORY.path_join(filename.get_basename() + "-%d.json" % suffix)
		suffix += 1
	issue = LayoutStorage.write_new(path, workspace.records())
	report("Saved %s." % path.get_file() if issue.is_empty() else issue)

func open_file(exporting: bool) -> void:
	var issue := LayoutStorage.ensure_directory()
	if not issue.is_empty():
		report(issue)
		return
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE if exporting else FileDialog.FILE_MODE_OPEN_FILE
	dialog.title = "Export engineering layout JSON" if exporting else "Load engineering layout"
	dialog.current_dir = ProjectSettings.globalize_path(LayoutStorage.DIRECTORY)
	dialog.current_file = layout_filename() if exporting else ""
	dialog.overwrite_warning_enabled = false
	dialog.popup_centered_clamped(Vector2i(760, 500))

func file_selected(path: String) -> void:
	if dialog.file_mode == FileDialog.FILE_MODE_SAVE_FILE:
		var issue := LayoutStorage.write_new(path, workspace.records())
		report("Exported %s." % path.get_file() if issue.is_empty() else issue)
		return
	var result := LayoutStorage.read(path)
	if not result.ok:
		report(result.error)
		return
	var issue := workspace.replace_all(LayoutReference.migrate(result.records))
	if issue.is_empty():
		cancel_preview()
		refresh_list()
		report("Loaded %s." % path.get_file())
	else:
		report("Layout kept. " + issue)

func report(message: String) -> void:
	feedback.text = message

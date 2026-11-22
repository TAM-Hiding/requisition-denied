extends SceneTree

var checks := 0
var failures := 0
var facility: Node3D
var actor: OtisController
var ui: CanvasLayer
var editor: LayoutEditor
var layout: LayoutWorkspace

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func frames(count: int) -> void:
	for frame in count:
		await physics_frame

func tap(key: Key, shift := false, control := false) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.pressed = true
	event.shift_pressed = shift
	event.ctrl_pressed = control
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func click(button := MOUSE_BUTTON_LEFT) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func load_facility() -> void:
	facility = preload("res://scenes/facility.tscn").instantiate()
	root.add_child(facility)
	current_scene = facility
	actor = facility.get_node("Otis")
	ui = facility.get_node("InteractionUI")
	editor = ui.layout_editor
	layout = editor.workspace

func reset_at(point: Vector3, yaw := PI) -> void:
	actor.global_position = layout.hall.to_global(point)
	actor.rotation.y = yaw
	actor.velocity = Vector3.ZERO
	actor.camera.rotation = Vector3.ZERO
	await frames(10)

func run() -> void:
	load_facility()
	await frames(6)
	tap(KEY_L)
	check(not editor.active and ui.hud.visible, "Layout input leaves the original chamber in normal gameplay")
	await reset_at(Vector3(0, 0.03, 4))
	tap(KEY_L)
	check(editor.active and editor.panel.visible and not ui.hud.visible and actor.placement.input_suspended,
		"L enters layout mode on hall floor and suspends gameplay tool input")
	tap(KEY_T)
	check(not ui.inventory.active, "Inventory cannot take ownership from the layout editor")
	editor.open_file(false)
	check(editor.dialog.visible and editor.dialog.file_mode == FileDialog.FILE_MODE_OPEN_FILE,
		"Load opens the actual JSON file picker")
	editor.dialog.hide()
	editor.open_file(true)
	check(editor.dialog.visible and editor.dialog.file_mode == FileDialog.FILE_MODE_SAVE_FILE
		and not editor.dialog.overwrite_warning_enabled, "Export opens a create-only JSON file picker")
	editor.dialog.hide()
	await catalog_checks()
	await preview_checks()
	await persistence_checks()
	facility.queue_free()
	await process_frame
	print("RD-014B layout editor: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func catalog_checks() -> void:
	var types := LayoutCatalog.types()
	check(types.size() == 13, "All thirteen placeholders are available in the runtime catalog")
	var index := 0
	for type in types:
		var record := layout.new_record(type)
		record.position = Vector3(0, 0, 10)
		editor.catalog.select(index)
		editor.spawn_requested()
		var ghost := editor.preview
		check(is_instance_valid(ghost) and editor.pending.type == type
			and ghost.find_children("*", "StaticBody3D", true, false).is_empty(),
			"Catalog spawns a non-colliding %s preview" % type)
		editor.cancel_preview()
		var issue := layout.upsert(record)
		check(issue.is_empty(), "%s commits to the hall: %s" % [type, issue])
		var placed := layout.items.get(record.id) as LayoutPlaceholder
		if placed != null:
			var marker: bool = LayoutCatalog.definition(type).marker
			check(placed.find_children("*", "StaticBody3D", true, false).is_empty() == marker,
				"%s has the expected equipment or planning collision" % type)
		layout.remove(record.id)
		await frames(2)
		index += 1

func preview_checks() -> void:
	var record := layout.new_record("workbench")
	await reset_at(Vector3(0, 0.03, 4))
	actor.camera.rotation.x = -0.40
	editor.start_preview(record)
	await frames(3)
	check(editor.preview.visible and editor.pending.position.y == 0.0
		and is_equal_approx(editor.pending.position.z, snappedf(editor.pending.position.z, editor.snap_step)),
		"Walk-and-aim preview tracks the snapped hall floor")
	var snapped: Vector3 = editor.pending.position
	tap(KEY_R)
	tap(KEY_R, true, true)
	tap(KEY_RIGHT, true)
	await frames(2)
	check(is_equal_approx(float(editor.pending.yaw), deg_to_rad(14))
		and is_equal_approx(float(editor.pending.position.x), snapped.x + 0.01),
		"Rotate in both increments and nudge by one centimetre")
	click()
	await frames(3)
	check(editor.pending.is_empty() and layout.items.has(record.id) and layout.active_id == record.id,
		"Click places the preview and selects the committed equipment")
	var collider := layout.items[record.id].get_node("PlaceholderCollision") as StaticBody3D
	check(not facility.fastening.compatible(collider, actor),
		"Gameplay cannot install structural fasteners into an editable placeholder")
	var original := layout.record(record.id)
	var moved := original.duplicate(true)
	moved.position = Vector3(-3.0, 0, 8.0)
	moved.yaw = 0.73
	check(layout.upsert(moved).is_empty() and layout.record(record.id).position == moved.position
		and is_equal_approx(layout.record(record.id).yaw, moved.yaw), "Move and rotation update the same identifier")
	editor.show_panel(true)
	editor.refresh_list()
	editor.name_input.text = "North bench"
	editor.notes_input.text = "Leave aisle"
	editor.dimension_inputs[0].value = 2.25
	editor.apply_properties()
	check(layout.record(record.id).name == "North bench" and layout.record(record.id).size.x == 2.25
		and layout.record(record.id).properties.notes == "Leave aisle", "Panel applies dimensions and planning metadata")
	editor.move_selected(true)
	var copy := editor.pending.duplicate(true)
	check(copy.id != record.id and copy.size == layout.record(record.id).size, "Duplicate uses a new ID and copies dimensions")
	editor.cancel_preview()
	var overlap_error := layout.upsert(copy)
	check(not overlap_error.is_empty() and layout.items.size() == 1, "Collision rejects the overlapping duplicate")
	copy.position = Vector3(3, 0, 10)
	check(layout.upsert(copy).is_empty(), "Duplicate places at a clear location")
	editor.delete_selected()
	check(layout.items.size() == 1 and layout.items.has(record.id), "Delete removes only the selected duplicate")
	var door := layout.new_record("personnel_door_marker")
	door.position = moved.position
	check(layout.upsert(door).is_empty(), "Planning door marker may overlap furniture without cutting the hall")
	var blocked := layout.new_record("workbench")
	blocked.position = Vector3(0, 0, 1.1)
	check(not layout.upsert(blocked).is_empty(), "Personnel doorway clearance is preserved")
	blocked.position = Vector3(7.15, 0, 12.2)
	check(not layout.upsert(blocked).is_empty(), "Stair approach is kept clear")
	blocked.position = Vector3(-8.2, 0, 10.5)
	check(not layout.upsert(blocked).is_empty(), "Existing hall footing blocks equipment")
	blocked.position = Vector3(8.9, 0, 7)
	blocked.yaw = 0.78
	check(not layout.upsert(blocked).is_empty(), "Rotated equipment must remain inside hall bounds")
	var ray := actor.camera
	await reset_at(Vector3(-3, 0.03, 5))
	ray.look_at(layout.hall.to_global(moved.position + Vector3.UP * 1.4))
	check(layout.cursor_pick(ray) == door.id, "A non-colliding door marker is selectable by sight")
	check(LayoutEditor.snapped_floor(Vector3(0.26, 0.33, 4.49), false, 0.5).is_equal_approx(Vector3(0.26, 0, 4.49))
		and LayoutEditor.snapped_floor(Vector3(0.26, 0.33, 4.49), true, 0.5).is_equal_approx(Vector3(0.5, 0, 4.5)),
		"Grid increment and temporary free placement resolve in meters")
	tap(KEY_ESCAPE)
	check(not editor.active and ui.hud.visible and not actor.placement.input_suspended,
		"Leaving layout mode restores gameplay input and HUD")
	tap(KEY_T)
	check(ui.inventory.active, "Inventory resumes after layout mode")
	ui.inventory.hide_inventory()

func persistence_checks() -> void:
	var original := layout.records()
	var directory := "user://rd014b-check-" + Crypto.new().generate_random_bytes(8).hex_encode()
	check(DirAccess.make_dir_recursive_absolute(directory) == OK, "Create an isolated test save directory")
	var path := directory.path_join("layout.json")
	var exported := directory.path_join("layout-export.json")
	check(LayoutStorage.write_new(path, original).is_empty(), "Save a versioned layout JSON")
	editor.dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	editor.file_selected(ProjectSettings.globalize_path(exported))
	check(FileAccess.file_exists(exported) and FileAccess.get_file_as_string(exported) == FileAccess.get_file_as_string(path),
		"Export uses the same documented coordinates and content as save")
	check(not LayoutStorage.write_new(path, []).is_empty(), "Existing layouts cannot be overwritten")
	facility.queue_free()
	await process_frame
	load_facility()
	await frames(4)
	check(layout.records().is_empty(), "A reopened Facility starts without unsaved scene data")
	await reset_at(Vector3(0, 0.03, 4))
	editor.dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	editor.file_selected(path)
	check(LayoutStorage.encode(layout.records()) == LayoutStorage.encode(original),
		"Loading after reopening restores unchanged IDs, geometry, orientation and properties")
	var blocked := original[0].duplicate(true)
	blocked.position = Vector3(0, 0, 1)
	var bad_records: Array[Dictionary] = [blocked]
	check(not layout.replace_all(bad_records).is_empty()
		and LayoutStorage.encode(layout.records()) == LayoutStorage.encode(original),
		"A colliding load leaves the previous layout intact")
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(exported)
	DirAccess.remove_absolute(directory)

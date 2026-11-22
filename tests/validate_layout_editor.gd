extends SceneTree

# Headless has no captured pointer. The enabled-mode test still exercises
# the production input routing, locomotion logic and Jolt collision.
class HeadlessLocomotion extends OtisLocomotion:
	func input_active() -> bool:
		return actor.controls_enabled

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

func load_facility(load_approved := false) -> void:
	facility = preload("res://scenes/facility.tscn").instantiate()
	facility.set("load_approved_layout", load_approved)
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
	if not OS.get_cmdline_user_args().has("--workshop-layout"):
		await standard_launch_checks()
	else:
		await development_launch_checks()
	facility.queue_free()
	await process_frame
	print("RD-014C layout editor: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func standard_launch_checks() -> void:
	load_facility(true)
	await frames(10)
	check(layout.items.size() == 28 and layout.items.has(LayoutReference.SAW_ID) and not layout.editing,
		"Normal launch installs the approved hall without putting it in edit mode")
	check(not editor.has_development_access() and not editor.visible and editor.get_child_count() == 0
		and not editor.is_physics_processing(), "Normal launch constructs no layout editor UI or editor physics loop")
	var mouse := Input.mouse_mode
	tap(KEY_L)
	await reset_at(Vector3(0, 0.03, 4))
	check(not ui.help.text.contains("L Layout"), "The normal hall HUD has no layout shortcut")
	tap(KEY_L)
	check(ui.feedback_time == 0 and not editor.active and ui.hud.visible,
		"L has no effect in either the chamber or the hall on normal launch")
	editor.enter()
	check(not editor.active and not editor.can_enter() and Input.mouse_mode == mouse
		and not actor.placement.input_suspended, "A direct editor entry cannot bypass the launch gate")

func development_launch_checks() -> void:
	load_facility()
	await frames(6)
	check(editor.has_development_access() and is_instance_valid(editor.panel),
		"A debug launch explicitly opted in to the workshop editor")
	editor.enter()
	tap(KEY_L)
	check(not editor.active and ui.hud.visible, "Neither direct nor shortcut entry opens the editor from the original chamber")
	await reset_at(Vector3(0, 0.03, 4))
	check(ui.help.text.contains("L Layout"), "The opted-in hall HUD announces its editor shortcut")
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
	await elevation_checks()
	await boundary_checks()
	await persistence_checks()

func catalog_checks() -> void:
	var types := LayoutCatalog.types()
	check(types.size() == 16, "The catalog includes the previous placeholders, rack and two bandsaw supports")
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
	check(LayoutEditor.snapped_floor(Vector3(0.26, 0.33, 4.49), false, 0.5).is_equal_approx(Vector3(0.26, 0.33, 4.49))
		and LayoutEditor.snapped_floor(Vector3(0.26, 0.33, 4.49), true, 0.5).is_equal_approx(Vector3(0.5, 0.33, 4.5)),
		"Grid increment and temporary free placement preserve the support elevation")
	tap(KEY_ESCAPE)
	check(not editor.active and ui.hud.visible and not actor.placement.input_suspended,
		"Leaving layout mode restores gameplay input and HUD")
	tap(KEY_T)
	check(ui.inventory.active, "Inventory resumes after layout mode")
	ui.inventory.hide_inventory()

func elevation_checks() -> void:
	var deck_height: float = layout.hall.get("deck_height")
	await reset_at(Vector3(0, deck_height + 0.03, 20.0))
	tap(KEY_L)
	check(editor.active and editor.panel.visible, "L opens the existing editor on the mezzanine")
	actor.camera.rotation.x = -0.76
	var bench := layout.new_record("workbench")
	bench.yaw = 0.21
	editor.start_preview(bench)
	await frames(4)
	check(editor.preview.visible and is_equal_approx(editor.pending.position.y, deck_height),
		"Walk-and-aim resolves the visible mezzanine support instead of the slab below")
	click()
	await frames(3)
	var upper := layout.record(bench.id)
	check(not upper.is_empty() and is_equal_approx(upper.position.y, deck_height)
		and is_equal_approx(upper.yaw, bench.yaw), "Normal click commits the actual elevation and placement rotation")
	if upper.is_empty():
		editor.leave()
		return

	editor.move_selected(true)
	var duplicate := editor.pending.duplicate(true)
	check(duplicate.id != upper.id and duplicate.position == upper.position and duplicate.yaw == upper.yaw,
		"Duplicate preview copies the elevated transform to a fresh identity")
	editor.cancel_preview()
	check(not layout.upsert(duplicate).is_empty(), "Same-level equipment collision rejects the original duplicate pose")
	duplicate.position.x = 3.25
	check(layout.upsert(duplicate).is_empty(), "Elevated duplicate can be placed in a clear location")
	editor.show_panel(true)
	editor.name_input.text = "Upper staging"
	editor.dimension_inputs[1].value = 1.17
	editor.apply_properties()
	var resized := layout.record(duplicate.id)
	check(resized.name == "Upper staging" and resized.position == duplicate.position
		and is_equal_approx(resized.size.y, 1.17) and resized.yaw == duplicate.yaw,
		"Applying panel properties to elevated equipment preserves its base and rotation")

	var lower := layout.new_record("workbench")
	lower.position = Vector3(upper.position.x, 0.0, upper.position.z)
	check(layout.upsert(lower).is_empty(), "The same XZ footprint is available below the mezzanine with headroom")
	var tall := lower.duplicate(true)
	tall.size.y = deck_height + 0.25
	check(not layout.validate_placement(tall, [], layout.excluded_bodies()).is_empty(),
		"An overheight ground placement cannot penetrate the mezzanine slab")
	var unsupported := upper.duplicate(true)
	unsupported.position.y += 0.01
	check(not layout.upsert(unsupported).is_empty(), "An unsupported elevated edit is rejected without moving the record")
	unsupported.position.y = deck_height
	unsupported.position.z = 19.26
	unsupported.yaw = PI / 4
	check(layout.validate_placement(unsupported, [], layout.excluded_bodies()).contains("entire footprint"),
		"Rotated corners cannot overhang the edge even with the center on the deck")
	var cellar := layout.new_record("storage_cabinet")
	for entrance: Vector3 in [Vector3(-8.30, 0.0, 2.75), Vector3(7.0, 0.0, 23.65)]:
		cellar.position = entrance
		check(layout.validate_placement(cellar, [], layout.excluded_bodies()).contains("storage-cell doorway"),
			"Placement keeps the storage cell approach open")
	cellar.position.y = deck_height
	check(layout.validate_placement(cellar, [], layout.excluded_bodies()).is_empty(),
		"A ground-level storage cell approach does not reserve the deck above")
	var stair := upper.duplicate(true)
	stair.position = Vector3(7.15, deck_height, 19.65)
	check(not layout.upsert(stair).is_empty(), "The mezzanine stair landing stays clear")
	var probe := Camera3D.new()
	layout.hall.add_child(probe)
	probe.position = Vector3(7.15, 4.5, 15.8)
	probe.look_at(layout.hall.to_global(Vector3(7.15, 1.0, 15.8)), Vector3.FORWARD)
	check(layout.cursor_floor(probe) == null, "The stair flight is not a tagged horizontal support")
	probe.position = Vector3(-8.3, 2.2, 10.5)
	probe.look_at(layout.hall.to_global(Vector3(-8.3, 0.5, 10.5)), Vector3.FORWARD)
	check(layout.cursor_floor(probe) == null, "The unrelated horizontal utility footing cannot support placement")
	probe.queue_free()

	layout.remove(lower.id)
	layout.select(upper.id)
	editor.move_selected(false)
	await reset_at(Vector3(0, 0.03, 19.8))
	actor.camera.rotation.x = -0.76
	await frames(3)
	check(editor.preview.visible and is_zero_approx(editor.pending.position.y),
		"An elevated record can be moved by targeting the slab from beneath the deck")
	click()
	await frames(3)
	check(editor.pending.is_empty() and is_zero_approx(float(layout.record(upper.id).position.y))
		and is_equal_approx(layout.record(upper.id).yaw, upper.yaw),
		"Moving levels updates the same ID and keeps its yaw")
	tap(KEY_ESCAPE)
	check(not editor.active and is_equal_approx(layout.record(duplicate.id).position.y, deck_height),
		"Leaving layout mode retains the elevated copy for normal gameplay and persistence")

func boundary_checks() -> void:
	if DisplayServer.get_name() == "headless":
		actor.remove_child(actor.locomotion)
		actor.locomotion.free()
		actor.locomotion = HeadlessLocomotion.new()
		actor.add_child(actor.locomotion)
		actor.locomotion.feedback.connect(ui.show_feedback)
	await reset_at(Vector3(7.15, 0.03, 11.34))
	tap(KEY_L)
	tap(KEY_TAB)
	tap(KEY_SPACE)
	await frames(7)
	check(editor.active and layout.hall.to_local(actor.global_position).y > 0.20,
		"Jumping above the floor keeps the editor active inside the hall footprint")
	await frames(55)

	Input.action_press(&"move_forward")
	await frames(158)
	Input.action_release(&"move_forward")
	var upper := layout.hall.to_local(actor.global_position)
	var deck_height: float = layout.hall.get("deck_height")
	check(editor.active and upper.z > 19.0 and absf(upper.y - deck_height) < 0.07,
		"Walking up the stairs into the mezzanine keeps an active editor enabled")

	await reset_at(Vector3(0, 0.03, 0.85), 0)
	editor.start_preview(layout.new_record("workbench"))
	Input.action_press(&"move_forward")
	await frames(35)
	Input.action_release(&"move_forward")
	check(layout.hall.to_local(actor.global_position).z < 0.0 and not editor.active and editor.pending.is_empty()
		and not is_instance_valid(editor.preview) and ui.hud.visible and not actor.placement.input_suspended,
		"Walking through the chamber doorway exits edit mode, cancels the preview and restores gameplay")

	for boundary: Array in [
		[Vector3(-8.18, 0.03, 2.75), PI / 2, Vector3(-9.4, 0.03, 2.75)],
		[Vector3(7.0, 0.03, 23.02), PI, Vector3(7.0, 0.03, 24.7)],
	]:
		await reset_at(boundary[0], boundary[1])
		var previous_mouse := Input.mouse_mode
		tap(KEY_L)
		check(editor.active and editor.panel.visible, "The debug editor opens from the hall side of a storage doorway")
		editor.open_file(false)
		actor.global_position = layout.hall.to_global(boundary[2])
		await frames(4)
		check(not editor.active and not editor.dialog.visible and not layout.editing and ui.hud.visible
			and Input.mouse_mode == previous_mouse and not actor.placement.input_suspended,
			"Crossing into exterior storage closes edit controls and the open dialog")

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
		"Loading after reopening restores unchanged IDs, geometry, elevation, orientation and properties")
	var blocked := original[0].duplicate(true)
	blocked.position = Vector3(0, 0, 1)
	var bad_records: Array[Dictionary] = [blocked]
	check(not layout.replace_all(bad_records).is_empty()
		and LayoutStorage.encode(layout.records()) == LayoutStorage.encode(original),
		"A colliding load leaves the previous layout intact")
	blocked.position = Vector3(0, 2.1, 9)
	check(not layout.replace_all(bad_records).is_empty()
		and LayoutStorage.encode(layout.records()) == LayoutStorage.encode(original),
		"A well-formed load without a physical support leaves the complete layout intact")
	DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(exported)
	DirAccess.remove_absolute(directory)

extends SceneTree
var failures: int = 0
var checks: int = 0

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	check(ProjectSettings.get_setting("application/run/main_scene") == "res://scenes/facility.tscn", "Main scene configured")
	check(InputMap.action_get_events("debug_overlay")[0].physical_keycode == KEY_F3, "F3 debug binding")
	var ids: Array[StringName] = []
	for kind in ["crate", "generator", "terminal"]:
		var definition := load("res://data/objects/%s.tres" % kind) as ObjectDefinition
		check(definition != null, "Definition loads: " + kind)
		check(not ids.has(definition.object_id) and definition.object_id != &"", "Unique object ID")
		ids.append(definition.object_id)
		var object := InteractableObject.new()
		object.definition = definition
		check(object.query_actions().has(&"inspect"), "Inspect exposed")
		var actions := object.query_actions()
		actions.clear()
		check(object.query_actions().has(&"inspect"), "Action query cannot mutate world")
		object.free()
	var facility := load("res://scenes/facility.tscn").instantiate() as Node3D
	root.add_child(facility)
	current_scene = facility
	await physics_frame
	await physics_frame
	var otis := facility.get_node("Otis") as OtisController
	var ui := facility.get_node("InteractionUI")
	var service := InteractionService.new()
	check(otis != null and otis.camera.current, "Otis and active camera exist")
	for kind in ["Crate", "Generator", "Terminal"]:
		var object := (facility.get("generator") if kind == "Generator" else facility.get_node(kind)) as InteractableObject
		otis.position = Vector3(object.global_position.x, 0.01, object.global_position.z + 2.5)
		otis.velocity = Vector3.ZERO
		otis.camera.look_at(object.global_position)
		await physics_frame
		await physics_frame
		check(otis.target_hit().get("collider") == object, "Ray targets " + kind)
		ui.open_menu(object)
		check(ui.menu_open and not otis.controls_enabled and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Menu releases mouse and locks walking")
		ui.perform_action(&"inspect")
		check(ui.information.text.contains(object.definition.description), "Correct inspection UI")
		check(otis.knowledge.has_inspected(object.definition.object_id), "Inspection recorded")
		ui.perform_action(&"inspect")
		check(otis.knowledge.records_for(object.definition.object_id).size() == 1, "Identical inspections deduplicated")
		var initial_description: String = object.inspection_information().description
		var records := otis.knowledge.records_for(object.definition.object_id)
		records[0]["description"] = "tampered"
		check(otis.knowledge.records_for(object.definition.object_id)[0].description == initial_description, "Knowledge reads are isolated snapshots")
		var old_description := object.definition.description
		object.definition.description = "Changed world"
		check(otis.knowledge.records_for(object.definition.object_id)[0].description == initial_description, "World does not rewrite knowledge")
		object.definition.description = old_description
		check(not service.request(&"activate", otis, otis.camera, object, 3, otis.knowledge).ok, "Unavailable action rejected")
		otis.position.z += 4
		await physics_frame
		check(not service.request(&"inspect", otis, otis.camera, object, 3, otis.knowledge).ok, "Stale menu distance rejected")
		ui.close_menu()
		check(not ui.menu_open and otis.controls_enabled and (DisplayServer.get_name() == "headless" or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED), "Menu close restores capture")
	check(otis.knowledge.inspected_object_count() == 3, "Three objects known")
	check(not PlayerKnowledge.new().has_inspected(ids[0]), "Knowledge not shared with other actors")
	# Occlusion: aim at crate from outside the north wall, with extended test reach.
	var crate := facility.get_node("Crate") as InteractableObject
	otis.position = Vector3(crate.position.x, 0.01, -7)
	otis.camera.look_at(crate.global_position)
	await physics_frame
	check(not service.request(&"inspect", otis, otis.camera, crate, 20, otis.knowledge).ok, "Wall blocks interaction")
	# Collision sweep against every room surface and each object.
	otis.position = Vector3(0, 0.02, 3)
	await physics_frame
	for motion in [Vector3(0, -2, 0), Vector3(0, 6, 0), Vector3(20, 0, 0), Vector3(-20, 0, 0), Vector3(0, 0, 20), Vector3(0, 0, -20)]:
		check(otis.test_move(otis.global_transform, motion), "Room collision: " + str(motion))
	for kind in ["Crate", "Generator", "Terminal"]:
		var object := (facility.get("generator") if kind == "Generator" else facility.get_node(kind)) as InteractableObject
		otis.position = object.global_position + Vector3(0, -0.3, 2)
		await physics_frame
		check(otis.test_move(otis.global_transform, Vector3(0, 0, -3)), "Object collision: " + kind)
	var debug_event := InputEventAction.new()
	debug_event.action = "debug_overlay"
	debug_event.pressed = true
	ui._input(debug_event)
	check(ui.debug_label.visible, "Diagnostics toggles on")
	ui._input(debug_event)
	check(not ui.debug_label.visible, "Diagnostics toggles off")
	var escape := InputEventAction.new()
	escape.action = "ui_cancel"
	escape.pressed = true
	ui._input(escape)
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Escape releases capture")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	ui._input(click)
	check(DisplayServer.get_name() == "headless" or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "Left click recaptures")
	if DisplayServer.get_name() != "headless":
		otis.position = Vector3(0, 0.02, 4)
		otis.rotation = Vector3.ZERO
		otis.camera.rotation = Vector3.ZERO
		otis.velocity = Vector3.ZERO
		var start := otis.position
		Input.action_press("move_forward")
		for frame in range(20):
			await physics_frame
		Input.action_release("move_forward")
		check(otis.position.z < start.z - 0.2, "W moves Otis forward")
		var motion := InputEventMouseMotion.new()
		motion.relative = Vector2(30, 20)
		otis._unhandled_input(motion)
		check(otis.rotation.y < 0 and otis.camera.rotation.x < 0, "Mouse look rotates body and camera")
		ui.open_menu(null)
		otis.position = Vector3(-2.5, 0.02, 2)
		otis.rotation = Vector3.ZERO
		otis.camera.look_at(crate.global_position)
		await physics_frame
		await physics_frame
		ui.open_menu(crate)
		ui.perform_action(&"inspect")
		await process_frame
		await RenderingServer.frame_post_draw
		if OS.get_environment("RD_SCREENSHOT") != "":
			root.get_texture().get_image().save_png(OS.get_environment("RD_SCREENSHOT"))
	facility.queue_free()
	await process_frame
	print("RD-001: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

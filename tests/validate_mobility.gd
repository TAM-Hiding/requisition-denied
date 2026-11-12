extends SceneTree
var failures: int = 0
var checks: int = 0
var service := InteractionService.new()
var facility: Node3D
var otis: OtisController
var ui: CanvasLayer
var equipment: EquipmentController

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func frames(count: int) -> void:
	for frame in range(count):
		await physics_frame

func aim_at(item: InteractableObject) -> void:
	otis.position = Vector3(item.global_position.x, 0.02, item.global_position.z + 1.8)
	otis.velocity = Vector3.ZERO
	otis.rotation = Vector3.ZERO
	otis.camera.look_at(item.global_position)
	await frames(3)

func request(action: StringName, item: InteractableObject) -> Dictionary:
	return service.request(action, otis, otis.camera, item, otis.interaction_distance, otis.knowledge)

func input_action(action: StringName, pressed: bool) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = pressed
	ui._input(event)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	facility = load("res://scenes/facility.tscn").instantiate()
	root.add_child(facility)
	current_scene = facility
	otis = facility.get_node("Otis")
	ui = facility.get_node("InteractionUI")
	equipment = otis.equipment
	await frames(10)
	var wrench := facility.get_node("Wrench") as InteractableObject
	var crate := facility.get_node("Crate") as InteractableObject
	var instance_id := wrench.get_instance_id()
	var object_id := wrench.definition.object_id
	check(InputMap.action_get_events("drop_item")[0].physical_keycode == KEY_G, "G binding")
	check(InputMap.action_get_events("equip_first")[0].physical_keycode == KEY_1, "1 binding")
	check(is_equal_approx(otis.interact_hold_threshold, 0.35), "Hold threshold default")
	for kind in ["Generator", "Terminal"]:
		var fixed := (facility.get("generator") if kind == "Generator" else facility.get_node(kind)) as InteractableObject
		await aim_at(fixed)
		check(fixed.freeze and fixed.mobility() == ObjectDefinition.Mobility.FIXED, "Fixed body remains fixed")
		check(not fixed.query_actions().has(&"pick_up") and not fixed.query_actions().has(&"move"), "Fixed actions exclude manipulation")
		check(not request(&"pick_up", fixed).ok and not request(&"move", fixed).ok, "Fixed action requests rejected")
		check(not equipment.pick_up(fixed).ok and not otis.placement.begin_world(fixed), "Equipment also rejects fixed bodies")
	check(crate.query_actions().has(&"move") and not crate.query_actions().has(&"pick_up"), "Movable action classification")
	await aim_at(crate)
	check(not request(&"pick_up", crate).ok, "Movable cannot be picked up")
	check(not equipment.stow().ok and equipment.stored_items().is_empty(), "Movable cannot enter storage")
	check(request(&"move", crate).ok and otis.placement.is_grabbing(), "Move begins through shared precision controller")
	check(crate.get_parent() == facility and crate.freeze, "Suspended crate remains a collidable world body")
	check(not crate.query_actions().has(&"move"), "Manipulated body cannot be retargeted")
	otis.placement.cancel()
	check(not crate.freeze and crate.state == InteractableObject.State.WORLD, "Cancellation returns ordinary physics")
	check(crate.query_actions().has(&"move"), "Move action returns after release")
	# Runtime mobility override is instance-local; no definition rewrite.
	var generator := facility.get("generator") as MechanicalComponent
	check(not generator.set_mobility(ObjectDefinition.Mobility.MOVABLE) and generator.freeze,
		"Installed floor connection prevents runtime mobility changes")
	await aim_at(crate)
	ui.open_menu(crate)
	check(crate.set_mobility(ObjectDefinition.Mobility.FIXED), "Loose instance can change mobility")
	await frames(2)
	check(not ui.menu_actions.has(&"move"), "Open menu refreshes after mobility changes")
	check(crate.definition.mobility == ObjectDefinition.Mobility.MOVABLE, "Definition remains unchanged")
	check(crate.set_mobility(ObjectDefinition.Mobility.MOVABLE) and not crate.freeze, "Loose instance can return to movable")
	await frames(2)
	check(ui.menu_actions.has(&"move"), "Open menu restores Move for a loose movable body")
	ui.close_menu()
	await aim_at(wrench)
	check(request(&"inspect", wrench).ok, "Wrench inspection works before pickup")
	check(request(&"pick_up", wrench).ok, "World to held via contextual service")
	check(equipment.held_item() == wrench and wrench.state == InteractableObject.State.HELD, "Active slot owns held instance")
	check(wrench.get_parent() == otis.get_node("Camera3D/EquipmentAnchor") and wrench.visible, "Held model on camera anchor")
	check(wrench.freeze and wrench.collision_layer == 0 and wrench.collision_mask == 0, "Held physics disabled safely")
	await frames(2)
	check(ui.debug_label.text.contains(String(object_id)) and ui.debug_label.text.contains("EQUIPMENT STATE  HELD"), "Diagnostics report held identity and state")
	check(wrench.query_actions().is_empty(), "Held item unavailable as loose target")
	check(not request(&"pick_up", wrench).ok and not equipment.pick_up(wrench).ok, "Repeated pickup rejected")
	check(equipment.stored_items().is_empty(), "Pickup does not also store reference")
	check(not wrench.set_mobility(ObjectDefinition.Mobility.FIXED), "Cannot change mobility during transition ownership")
	equipment.storage_capacity = 0
	check(not equipment.stow().ok and equipment.held_item() == wrench and not ui.status.text.is_empty(), "Full storage keeps item held with feedback")
	equipment.storage_capacity = 1
	check(service.request_actor_action(&"stow", otis).ok, "Held to stowed")
	check(equipment.held_item() == null and equipment.stored_items() == [wrench], "Stored differs from active equipment")
	check(wrench.state == InteractableObject.State.STOWED and not wrench.visible and wrench.freeze, "Stowed item hidden and frozen")
	await frames(2)
	check(ui.debug_label.text.contains("STORED  1") and ui.debug_label.text.contains("EQUIPMENT STATE  STOWED"), "Diagnostics distinguish storage from equipped state")
	check(not equipment.stow().ok and equipment.stored_items().size() == 1, "Repeated stow does not duplicate")
	var references := equipment.stored_items()
	references.clear()
	check(equipment.stored_items().size() == 1, "Storage reference list is defensive copy")
	check(service.request_actor_action(&"equip_first", otis).ok, "Stowed to held")
	check(equipment.held_item() == wrench and equipment.stored_items().is_empty(), "Retrieve removes stored reference")
	check(not equipment.equip_first().ok, "Retrieve cannot duplicate equipped reference")
	check(wrench.get_instance_id() == instance_id and wrench.definition.object_id == object_id, "Identity persists through equipment transitions")
	# Candidate volumes and camera ray prevent dropping through wall or into actor.
	otis.position = Vector3(-2, 0.02, -5.65)
	otis.rotation = Vector3.ZERO
	otis.camera.rotation = Vector3.ZERO
	await frames(3)
	check(not equipment.drop().ok and equipment.held_item() == wrench, "Wall-blocked drop preserves held item")
	otis.position = Vector3(0, 0.02, 3)
	otis.camera.rotation = Vector3(-1.5, 0, 0)
	await frames(3)
	check(not equipment.drop().ok and wrench.state == InteractableObject.State.HELD, "Downward drop refuses overlap with player")
	otis.camera.rotation = Vector3.ZERO
	await frames(3)
	check(service.request_actor_action(&"drop", otis).ok, "Held to world drop")
	check(equipment.held_item() == null and equipment.stored_items().is_empty(), "Drop clears equipment ownership")
	check(wrench.get_parent() == facility and wrench.visible and not wrench.freeze and wrench.collision_layer == 1, "Drop restores world physics and presentation")
	var dropped_y := wrench.global_position.y
	await frames(90)
	check(wrench.global_position.y < dropped_y - 0.5 and wrench.global_position.y > 0.02, "Dropped item falls then rests on floor")
	check(wrench.get_instance_id() == instance_id and wrench.definition.object_id == object_id, "Identity persists after drop")
	await aim_at(wrench)
	check(otis.target_hit().get("collider") == wrench, "Dropped item targetable")
	check(request(&"inspect", wrench).ok and otis.knowledge.records_for(object_id).size() == 1, "Inspection identity and dedup survive manipulation")
	check(otis.knowledge.inspected_object_count() == 1, "Only legitimately inspected object is learned")
	if DisplayServer.get_name() != "headless":
		# Real capture permits testing E tap/hold arbitration at the UI boundary.
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		input_action(&"interact", true)
		check(not ui.menu_open, "E press defers tap until release")
		ui.advance_hold(0.1)
		input_action(&"interact", false)
		check(ui.menu_open, "Short E release opens menu")
		ui.perform_action(&"pick_up")
		check(not ui.menu_open and equipment.held_item() == wrench, "Pickup closes menu and equips")
		input_action(&"interact", true)
		ui.advance_hold(0.4)
		input_action(&"interact", false)
		check(wrench.state == InteractableObject.State.STOWED and not ui.menu_open, "Long E stows without tap menu")
		input_action(&"equip_first", true)
		check(equipment.held_item() == wrench, "1 retrieves through input")
		# Focus loss cancels pending tap/hold and releases environmental control.
		input_action(&"interact", true)
		ui._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
		input_action(&"interact", false)
		check(not ui.menu_open and not ui.e_pending and wrench.state == InteractableObject.State.HELD, "Focus loss cancels E gesture")
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		otis.position = Vector3(0, 0.02, 3)
		otis.camera.rotation = Vector3.ZERO
		await frames(3)
		if OS.get_environment("RD_SCREENSHOT") != "":
			await process_frame
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(OS.get_environment("RD_SCREENSHOT"))
		input_action(&"drop_item", true)
		input_action(&"drop_item", false)
		check(wrench.state == InteractableObject.State.WORLD, "G drops through input")
		await aim_at(crate)
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		check(request(&"move", crate).ok, "Graphical Move begins")
		await frames(5)
		check(otis.placement.is_grabbing(), "Move persists while captured")
		input_action(&"drop_item", true)
		input_action(&"drop_item", false)
		check(not otis.placement.is_grabbing() and not crate.freeze, "G tap places without a menu")
		await aim_at(crate)
		check(request(&"move", crate).ok, "Move restarts")
		ui._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
		check(not otis.placement.is_grabbing() and not crate.freeze, "Focus loss releases Move")
	facility.queue_free()
	await process_frame
	print("RD-002: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

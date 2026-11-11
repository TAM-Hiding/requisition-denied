extends SceneTree

var checks := 0
var failures := 0
var events_seen := 0

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)

func frames(count: int) -> void:
	for frame in count:
		await physics_frame

func action(name: StringName, pressed: bool) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = name
	event.pressed = pressed
	return event

func place(body: RigidBody3D, point: Vector3) -> void:
	body.global_position = point
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	body.sleeping = false

func run() -> void:
	var facility := preload("res://scenes/facility.tscn").instantiate()
	root.add_child(facility)
	current_scene = facility
	await frames(4)
	var actor: OtisController = facility.get_node("Otis")
	var work: TerminalWorkstation = facility.get_node("Terminal")
	var world_ui := facility.get_node("InteractionUI")
	var terminal: TerminalInteraction = facility.terminal_session
	var screen := terminal.screen_ui
	var admin: AdministrativeSession = facility.administration
	var wrench: InteractableObject = facility.get_node("Wrench")
	var weight: InteractableObject = facility.get_node("TestWeight")
	var crate: InteractableObject = facility.get_node("Crate")
	var plate: PhysicalLoadSensor = facility.load_plate
	var gate: PoweredBarrier = facility.barrier
	var graphical := DisplayServer.get_name() != "headless"
	admin.event_published.connect(func(_event: Dictionary) -> void: events_seen += 1)
	actor.camera.look_at(work.global_position)
	check(not terminal.enter(), "Terminal rejects an out-of-range actor")
	actor.global_position = Vector3(0, 0.01, -4.1)
	actor.camera.look_at(work.global_position)
	await frames(4)
	check(actor.target_hit().get("collider") == work, "Otis can target the physical monitor")
	check(actor.equipment.pick_up(wrench).ok, "Wrench equipped before entering")
	var camera_before := actor.camera.global_transform
	var actor_before := actor.global_position
	if graphical:
		world_ui._input(action(&"interact", true))
		world_ui._input(action(&"interact", false))
	else:
		terminal.enter()
	check(terminal.active and terminal.camera.current and not actor.controls_enabled and not world_ui.hud.visible,
		"Terminal owns camera and input")
	check(not terminal.enter() and work.display.get_child_count() == 1, "Repeated activation cannot stack interfaces")
	check(not paused and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Terminal releases mouse without pausing")

	Input.action_press("move_forward")
	world_ui._input(action(&"drop_item", true))
	world_ui._input(action(&"interact", true))
	world_ui._input(action(&"equip_first", true))
	await frames(30)
	world_ui._input(action(&"drop_item", false))
	world_ui._input(action(&"interact", false))
	Input.action_release("move_forward")
	check(actor.global_position.is_equal_approx(actor_before) and actor.camera.global_transform.is_equal_approx(camera_before),
		"Movement and first-person view remain fixed")
	check(actor.equipment.held_item() == wrench and not actor.placement.is_active(), "World equipment inputs cannot run")
	check(terminal.camera.global_position.distance_to(work.view_anchor.global_position) < 0.005, "Camera arrives at workstation")
	check(admin.messages().size() == 3 and admin.unread_count() == 3, "Three authored unread messages")
	if graphical:
		await process_frame
		var point := screen.entries.get_item_rect(0).get_center() + screen.entries.global_position
		click_screen(terminal, work, world_ui, point)
	else:
		screen.entries.item_selected.emit(0)
	check(admin.unread_count() == 2 and screen.detail.text.contains("PERSONNEL ORIENTATION"), "Selecting a message marks it read")
	if graphical:
		screen.navigation.get_child(0).grab_focus()
		send_key(world_ui, KEY_TAB)
		send_key(world_ui, KEY_ENTER)
		check(screen.section == "Requisitions", "Tab and Enter navigate the terminal")
	else:
		screen.show_section("Requisitions")
	check(screen.entries.item_count == 3, "Three catalog entries are available")
	var item_count := facility.get_child_count()
	screen.entries.item_selected.emit(1)
	check(screen.detail.text.contains("Available for review") and screen.submit_button.visible, "Catalog details and submit action")
	screen.submit_button.pressed.emit()
	var denied := admin.requests()[0]
	check(denied.status == AdministrativeSession.RequestStatus.DENIED and screen.detail.text.contains(denied.id),
		"Submission creates a visible deterministic denial")
	screen.entries.item_selected.emit(0)
	screen.submit_button.pressed.emit()
	var approved := admin.requests()[1]
	check(approved.id != denied.id and approved.status == AdministrativeSession.RequestStatus.APPROVED,
		"Distinct request identifiers and approval without fulfillment")
	check(admin.submit(&"unknown", &"test").is_empty() and admin.requests().size() == 2, "Unknown catalog entry rejected")
	check(events_seen == 2 and admin.events()[0].type == &"REQUISITION_SUBMITTED"
		and admin.events()[0].context.request_id == denied.id and admin.events()[0].id != admin.events()[1].id,
		"Submission emits structured, uniquely identified events")
	check(item_count == facility.get_child_count(), "Requests spawn no physical items")

	screen.show_section("Inventory")
	check(screen.detail.text.contains(wrench.definition.display_name), "Equipped wrench shown")
	world_ui._input(action(&"ui_cancel", true))
	check(not terminal.active and actor.camera.current and actor.controls_enabled and world_ui.hud.visible, "Escape returns camera and controls")
	check(not graphical or Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, "Escape restores mouse capture")
	check(actor.equipment.stow().ok and terminal.enter(), "Stowing works again after exit")
	check(screen.detail.text.contains("EQUIPPED\nNone") and screen.detail.text.contains(wrench.definition.display_name),
		"Reopened inventory reflects stored wrench")
	terminal.leave()
	check(actor.equipment.equip_first().ok and actor.equipment.drop().ok and terminal.enter(),
		"Retrieving and dropping still work")
	check(not screen.detail.text.contains(wrench.definition.display_name), "Dropped wrench is absent")
	screen.show_section("Records")
	check(screen.entries.item_count == 0, "Uninspected world objects are absent")
	actor.knowledge.record_inspection(crate.definition.object_id, crate.inspection_information())
	actor.knowledge.record_inspection(crate.definition.object_id, crate.inspection_information())
	screen.show_section("Records")
	screen.entries.item_selected.emit(0)
	check(screen.entries.item_count == 1 and screen.detail.text.contains(crate.definition.description), "Records reflect deduplicated acquired knowledge")
	screen.show_section("Settings")
	screen.brightness.value = 0.59
	check(is_equal_approx(admin.text_brightness, 0.59) and screen.interface.modulate.r < 0.6,
		"Brightness adjusts the actual display")

	place(crate, plate.global_position + Vector3(-0.51, 0.66, 0))
	place(weight, plate.global_position + Vector3(0.73, 1.2, 0))
	await frames(155)
	check(terminal.active and weight.position.y < 0.2, "World physics keeps running with terminal open")
	check(is_equal_approx(plate.measured_kg, 43) and plate.output.is_active() and gate.state == PoweredBarrier.State.OPEN,
		"Load plate and barrier continue operating with terminal open")
	place(crate, gate.closed_position + Vector3.DOWN * 0.34)
	await frames(95)
	check(gate.state == PoweredBarrier.State.BLOCKED and admin.events().back().type == &"BARRIER_OBSTRUCTED",
		"Physical obstruction publishes an administrative event")
	place(crate, Vector3(-2.5, 0.66, -0.5))
	await frames(110)
	check(gate.state == PoweredBarrier.State.CLOSED and admin.events().back().type == &"BARRIER_RESTORED"
		and screen.footer.text.contains("BARRIER RESTORED"), "Restoration is published and shown as a fact")
	terminal.leave()
	check(terminal.enter() and is_equal_approx(screen.brightness.value, 0.59) and admin.unread_count() == 2,
		"Display settings and message state survive repeated entry")
	screen.show_section("Requisitions")
	check(screen.entries.item_count == 5 and admin.requests().size() == 2, "Requisition history survives reopening")
	if graphical and not OS.get_environment("RD_TERMINAL_SCREENSHOT").is_empty():
		await frames(25)
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("RD_TERMINAL_SCREENSHOT"))
	terminal.leave()
	facility.queue_free()
	await process_frame
	print("RD-005: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func click_screen(terminal: TerminalInteraction, work: TerminalWorkstation, world_ui: Node, point: Vector2) -> void:
	var uv := point / Vector2(work.display.size) - Vector2(0.5, 0.5)
	var world := work.screen.to_global(Vector3(uv.x * work.SCREEN_SIZE.x, -uv.y * work.SCREEN_SIZE.y, 0))
	var window_point := terminal.camera.unproject_position(world)
	for down in [true, false]:
		var click := InputEventMouseButton.new()
		click.button_index = MOUSE_BUTTON_LEFT
		click.position = window_point
		click.pressed = down
		world_ui._input(click)

func send_key(world_ui: Node, key: Key) -> void:
	for down in [true, false]:
		var event := InputEventKey.new()
		event.keycode = key
		event.physical_keycode = key
		event.pressed = down
		world_ui._input(event)

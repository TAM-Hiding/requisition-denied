extends SceneTree
var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func frames(count := 2) -> void:
	for i in count:
		await physics_frame

func item(facility: Node3D, id: String, size: Vector3, mass: float,
		mobility := ObjectDefinition.Mobility.CARRYABLE) -> InteractableObject:
	var body := InteractableObject.new()
	body.name = id
	body.definition = ObjectDefinition.new()
	body.definition.object_id = StringName(id)
	body.definition.display_name = id.replace("_", " ").capitalize()
	body.definition.mass_kg = mass
	body.definition.mobility = mobility
	var collider := CollisionShape3D.new()
	collider.name = "CollisionShape3D"
	collider.shape = BoxShape3D.new()
	collider.shape.size = size
	body.add_child(collider)
	facility.add_child(body)
	body.global_position = Vector3(4.5, 1.8, 4.5)
	body.gravity_scale = 0.0
	return body

func run() -> void:
	var facility = preload("res://scenes/facility.tscn").instantiate()
	root.add_child(facility)
	current_scene = facility
	var actor := facility.get_node("Otis") as OtisController
	var eq := actor.equipment
	var container := eq.container
	await frames(4)
	var wrench := facility.get_node("Wrench") as InteractableObject
	var tool: FasteningTool = facility.get("bolt_tool")
	var identity := wrench.get_instance_id()
	var notifications: Array[int] = [0]
	container.changed.connect(func() -> void: notifications[0] += 1)
	check(eq.store_world(wrench).ok and wrench.storage_owner == container and wrench.state == InteractableObject.State.STOWED,
		"World storage transfers the same rigid body to its container")
	check(not wrench.visible and wrench.freeze and wrench.collision_layer == 0
		and container.records()[0].dimensions().length() > 0, "Stored body is dormant with physical dimensions")
	check(not eq.store_world(wrench).ok and container.items().size() == 1, "Repeated insertion cannot duplicate ownership")
	var foreign := InventoryContainer.new()
	foreign.definition = container.definition.duplicate()
	facility.add_child(foreign)
	check(not foreign.insert(wrench).is_empty(), "A second container cannot claim an owned object")
	check(eq.equip_item(wrench).ok and eq.held_item() == wrench and container.items().is_empty()
		and wrench.equipment_owner == eq and wrench.storage_owner == null, "Equipping removes container ownership")
	check(not eq.equip_item(wrench).ok and not eq.pick_up(wrench).ok, "Repeated equipment requests cannot duplicate references")
	check(is_equal_approx(actor.carrying_loads().total, wrench.mass), "Equipment mass is counted once")
	check(eq.stow().ok and is_equal_approx(actor.carrying_loads().total, wrench.mass), "Stowing preserves total carried mass")
	check(wrench.get_instance_id() == identity, "Item identity survives equipment and inventory transfers")
	check(notifications[0] == 3, "Container listeners see one notification per completed storage transaction")
	var no_tree := InteractableObject.new()
	no_tree.definition = wrench.definition
	check(not container.insert(no_tree).is_empty() and no_tree.storage_owner == null,
		"A body outside the scene tree cannot enter storage")
	no_tree.free()

	var large := item(facility, "Long_tube", Vector3(0.90, 0.02, 0.02), 0.5, ObjectDefinition.Mobility.MOVABLE)
	check(eq.store_world(large).message.contains("dimensions") and large.get_parent() == facility and not large.freeze,
		"A slender long item fails dimensions without leaving the world")
	var heavy := item(facility, "Dense_block", Vector3(0.05, 0.05, 0.05), 26)
	check(eq.store_world(heavy).message.contains("structural"), "Structural mass rating is independent of Otis")
	var volume := container.definition.capacity_m3
	container.definition.capacity_m3 = 0.0000001
	check(eq.store_world(tool).message.contains("volume"), "Aggregate container volume is enforced")
	container.definition.capacity_m3 = volume
	container.packing_validator = func(_record: InventoryItem) -> String: return "Physical packing rejected."
	check(eq.store_world(tool).message == "Physical packing rejected.", "Physical packing can veto the grid's approximate fit")
	container.packing_validator = Callable()
	check(eq.pick_up(tool).ok, "Existing Uni-Bolt pickup stays authoritative")
	tool.load_grade(1)
	tool.rounds.pop_back()
	var ammo := tool.inventory_state()
	check(eq.stow().ok and tool.inventory_state() == ammo and container.items().size() == 2,
		"Tool ammunition and grade survive storage beside another item")

	var manifest: Dictionary = JSON.parse_string(JSON.stringify(container.snapshot()))
	var registry := {String(wrench.definition.object_id): wrench, String(tool.definition.object_id): tool}
	var restore_issue := container.restore_manifest(manifest, registry)
	check(restore_issue.is_empty(), restore_issue + " Versioned manifest round-trips through JSON against live identities")
	check(tool.inventory_state() == ammo and tool.get_instance_id() == registry[String(tool.definition.object_id)].get_instance_id(),
		"Manifest resolution preserves the actual tool and mutable state")
	var detached := wrench.duplicate() as InteractableObject
	var detached_registry := registry.duplicate()
	detached_registry[String(wrench.definition.object_id)] = detached
	check(not container.restore_manifest(manifest, detached_registry).is_empty() and detached.storage_owner == null,
		"Manifest resolution cannot claim an object outside the world")
	detached.free()
	var bad := manifest.duplicate(true)
	bad.items.append(bad.items[0])
	check(not container.restore_manifest(bad, registry).is_empty() and container.items().size() == 2,
		"Duplicate manifest identities roll back without changing contents")
	bad = manifest.duplicate(true)
	bad.version = 99
	check(not container.restore_manifest(bad, registry).is_empty(), "Unsupported schema versions are rejected")
	bad = manifest.duplicate(true)
	bad.items[0].internal_pose = [[0]]
	check(not container.restore_manifest(bad, registry).is_empty(), "Invalid packing transforms are rejected atomically")
	var records := container.records()
	records.clear()
	check(container.items().size() == 2, "Record lists are defensive copies")
	var incompatible := item(facility, "Glove_fixture", Vector3(0.08, 0.08, 0.08), 0.1)
	incompatible.definition.equipment_slots = [&"hands"]
	check(eq.store_world(incompatible).ok and not eq.equip_item(incompatible).ok, "An unsupported category cannot equip in the tool slot")
	check(eq.equip_item(wrench).ok, "Stored wrench automatically selects tool slot")
	var limit := container.definition.maximum_mass_kg
	container.definition.maximum_mass_kg = 0
	check(not eq.equip_item(tool).ok and eq.held_item() == wrench and tool.storage_owner == container,
		"Slot conflict rejects safely when displaced equipment cannot be stored")
	container.definition.maximum_mass_kg = limit
	check(eq.equip_item(tool).ok and eq.held_item() == tool and wrench.storage_owner == container,
		"Successful slot replacement stores the displaced item")
	check(tool.inventory_state() == ammo, "Slot replacement preserves Uni-Bolt ammunition")
	actor.global_position = Vector3(0, 0.02, 3)
	actor.camera.rotation = Vector3.ZERO
	await frames(3)
	var blocker := StaticBody3D.new()
	var block_shape := CollisionShape3D.new()
	block_shape.shape = BoxShape3D.new()
	block_shape.shape.size = Vector3(3, 3, 0.30)
	blocker.add_child(block_shape)
	facility.add_child(blocker)
	blocker.global_position = actor.camera.global_position + Vector3(0, 0, -0.4)
	await frames(3)
	check(not eq.retrieve(wrench).ok and wrench.storage_owner == container and container.contains(wrench),
		"Obstructed retrieval keeps the stored item and its ownership")
	blocker.queue_free()
	await frames()
	current_scene = null
	check(not eq.retrieve(wrench).ok and container.contains(wrench) and wrench.storage_owner == container,
		"Retrieval without a valid world parent leaves ownership intact")
	current_scene = facility
	check(eq.retrieve(wrench).ok and wrench.storage_owner == null and wrench.state == InteractableObject.State.WORLD
		and not wrench.freeze and wrench.collision_layer == 1 and wrench.get_instance_id() == identity,
		"Clear retrieval restores the original physical body")
	wrench.global_position = Vector3(4, 2, 3)
	var wide := item(facility, "Wide_retrieval_fixture", Vector3(0.4, 0.1, 0.2), 0.2)
	wide.global_position = actor.camera.global_position + Vector3.FORWARD * 1.6
	await frames(3)
	check(InteractionService.new().request(&"store", actor, actor.camera, wide, actor.interaction_distance, actor.knowledge).ok,
		"World storage works through the normal contextual action permission gate")
	var edge := StaticBody3D.new()
	var edge_shape := CollisionShape3D.new()
	edge_shape.shape = BoxShape3D.new()
	edge_shape.shape.size = Vector3(0.04, 0.20, 0.04)
	edge.add_child(edge_shape)
	facility.add_child(edge)
	edge.global_position = actor.camera.global_position + Vector3(0.15, 0, -0.30)
	await frames(3)
	check(not eq.retrieve(wide).ok and container.contains(wide),
		"An edge obstruction blocks the full shape sweep despite clear center ray and destination")
	edge.queue_free()
	await frames()
	check(eq.retrieve(wide).ok, "Retrieval resumes when the edge obstruction clears")
	wide.queue_free()
	# A non-equippable entry precedes the tool while a separate workpiece
	# remains under manipulation.
	check(eq.stow().ok, "Tool stows after retrieval tests")
	check(eq.retrieve(tool).ok, "Tool can be retrieved without equipping")
	check(eq.store_world(tool).ok and container.items()[0] == incompatible,
		"Mixed inventory can put a non-tool before the Uni-Bolt")
	# Reposition the retrieved wrench for a clean, real pickup route.
	wrench.gravity_scale = 0.0
	wrench.linear_velocity = Vector3.ZERO
	wrench.global_position = Vector3(0, 1.65, 1.3)
	await frames(3)
	actor.camera.look_at(wrench.global_position)
	check(actor.placement.begin_world(wrench), "External workpiece pickup remains available with inventory")
	check(InteractionService.new().request_actor_action(&"equip_first", actor).ok
		and actor.equipped_tool() == tool and actor.placement.is_grabbing(),
		"Press 1 finds the compatible tool behind non-equipment while holding a workpiece")
	actor.set_tool_aiming(true)
	var pinned := wrench.global_transform
	actor.global_position.x += 0.2
	if actor.placement.is_active():
		actor.placement.update_preview(0.1)
	check(wrench.global_transform.is_equal_approx(pinned), "Inventory-integrated tool retains aim-to-hold stabilization")
	actor.set_tool_aiming(false)
	actor.placement.cancel()

	# Many small objects are limited by physical capacity, never cell count.
	for i in 8:
		check(eq.store_world(item(facility, "Fastener_case_%d" % i, Vector3.ONE * 0.02, 0.01)).ok,
			"Inventory accepts another distinct item within physical capacity")
	var ui = facility.get_node("InteractionUI")
	var screen: InventoryScreen = ui.inventory
	var pose := actor.global_transform
	ui.e_pending = true
	ui.e_elapsed = 0.3
	check(screen.show_inventory(ui.hud) and not actor.controls_enabled and actor.placement.input_suspended,
		"Inventory owns gameplay input while the Facility keeps simulating")
	check(not ui.e_pending, "Opening cancels a pending E hold")
	check(screen.preview.viewport.own_world_3d and screen.preview.pivot.get_child_count() == 1,
		"Preview uses an isolated world with the current chassis")
	var rotate := InputEventAction.new()
	rotate.action = &"inventory_rotate_left"
	rotate.pressed = true
	screen.route(rotate)
	screen._process(0.5)
	check(screen.preview.pivot.rotation.y < -0.1 and actor.global_transform == pose, "Q rotates only the preview")
	screen.collapse.pressed.emit()
	check(not screen.grid_scroll.visible, "Inventory grid collapses without modifying contents")
	screen.collapse.pressed.emit()
	check(screen.grid.get_child_count() == container.items().size() and screen.grid.get_child_count() > 8,
		"The scrollable grid has one entry per object without a fixed slot limit")
	var count := tool.rounds.size()
	var shot := InputEventAction.new()
	shot.action = &"tool_primary"
	shot.pressed = true
	ui._input(shot)
	check(tool.rounds.size() == count and actor.equipped_tool() == tool, "UI input cannot fire the Uni-Bolt")
	ui._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not screen.turn_left and not screen.turn_right, "Focus loss clears preview rotation input")
	ui._notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	screen.hide_inventory()
	check(actor.controls_enabled and not actor.placement.input_suspended and actor.camera.is_current(),
		"Closing restores gameplay and the existing camera")
	check(not container.items().has(wrench) and eq.held_item() == tool, "UI never duplicates container or equipment records")
	facility.queue_free()
	await process_frame
	print("RD-011: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

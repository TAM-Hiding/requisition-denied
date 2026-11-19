extends SceneTree
var checks := 0
var failures := 0
var facility: Node3D
var screen: InventoryScreen
var equipment: EquipmentController
var bag: BagView
var items: Array[InteractableObject] = []
var tool_state: Dictionary

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func frames(count: int) -> void:
	for i in count:
		await physics_frame

func mouse(button: MouseButton, pressed: bool, point: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.position = point
	bag._gui_input(event)

func visible_point(item: InteractableObject) -> Variant:
	var body: RigidBody3D = bag.interior.proxies[item]
	var box := ContainerPacking.bounds(InventoryItem.from_body(item), body.transform)
	var center := bag.camera.unproject_position(box.get_center())
	if bag.interior.pick(bag.camera, center).get("item") == item:
		return center
	# Scan actual rays; a hollow/compound object's AABB center need not be solid.
	for x in range(1, 10):
		for z in range(1, 10):
			var point := bag.camera.unproject_position(Vector3(
				lerpf(box.position.x, box.end.x, x / 10.0), box.end.y,
				lerpf(box.position.z, box.end.z, z / 10.0)))
			if bag.interior.pick(bag.camera, point).get("item") == item:
				return point
	return null

func setup(indices: Array[int], with_tool := false) -> void:
	facility = preload("res://scenes/facility.tscn").instantiate()
	root.add_child(facility)
	current_scene = facility
	await frames(5)
	equipment = facility.get_node("Otis").equipment
	screen = facility.get_node("InteractionUI").inventory
	items.clear()
	for index in indices:
		var item := facility.scrap_supply.dispense(index) as InteractableObject
		check(item != null and equipment.store_world(item).ok, "Fresh catalog stock enters the existing container")
		items.append(item)
		await frames(2)
	if with_tool:
		var tool := facility.get("bolt_tool") as FasteningTool
		tool.load_grade(1)
		tool.rounds.pop_back()
		tool_state = tool.inventory_state()
		check(equipment.pick_up(tool).ok, "Real Uni-Bolt equips before storage transfer")
		items.append(tool)
	screen.show_inventory(facility.get_node("InteractionUI").hud)
	screen.toggle_view()
	if with_tool:
		screen.selected = items.back()
		screen.perform_action(1)
		check(equipment.held_item() == null and equipment.container.contains(items.back()),
			"Unequip clears the slot and stores the original tool")
	bag = screen.bag
	await frames(120)
	check(bag.interior.proxies.size() == items.size() and bag.interior.containment_tolerance <= 0.0241,
		"Each authoritative item has one proxy and the defensive tolerance stays bounded")
	for item in items:
		var proxy: RigidBody3D = bag.interior.proxies[item]
		var original_shapes := item.get_children().filter(func(child: Node) -> bool:
			return child is CollisionShape3D and not child.disabled)
		var proxy_shapes := proxy.get_children().filter(func(child: Node) -> bool: return child is CollisionShape3D)
		check(not proxy.freeze and proxy.can_sleep and proxy.mass == item.mass
			and original_shapes.size() == proxy_shapes.size(), "Loose proxies retain mass, sleeping and every collision component")
		var shapes_match := true
		for index in original_shapes.size():
			shapes_match = shapes_match and original_shapes[index].shape == proxy_shapes[index].shape \
				and original_shapes[index].transform.is_equal_approx(proxy_shapes[index].transform)
		check(shapes_match, "Proxy collision shapes preserve their dimensions, orientation and offsets")

func teardown() -> void:
	screen.hide_inventory()
	facility.queue_free()
	await frames(3)

func exercise_single(item: InteractableObject) -> void:
	var proxy: RigidBody3D = bag.interior.proxies[item]
	var identity := item.get_instance_id()
	var point: Variant = visible_point(item)
	check(point != null, "Actual ray selects settled round stock")
	if point == null:
		return
	proxy.sleeping = true
	await frames(2)
	mouse(MOUSE_BUTTON_LEFT, true, point)
	check(screen.selected == item and bag.interior.drag_item == item and not proxy.sleeping,
		"LMB resolves the original item and wakes its sleeping proxy")
	var start := proxy.position
	var motion := InputEventMouseMotion.new()
	motion.position = bag.camera.unproject_position(proxy.position + Vector3(0.05, 0, 0.07))
	bag._gui_input(motion)
	await frames(75)
	var horizontal := Vector2(proxy.position.x - start.x, proxy.position.z - start.z).length()
	check(horizontal > 0.025, "Settled round stock responds to actual horizontal mouse dragging")
	var floor_y := proxy.position.y
	for i in 4:
		mouse(MOUSE_BUTTON_WHEEL_DOWN, true, motion.position)
	await frames(65)
	check(proxy.position.y > floor_y + 0.06, "Wheel input lifts round stock off the floor")
	var raised := proxy.position.y
	mouse(MOUSE_BUTTON_LEFT, false, motion.position)
	check(bag.interior.drag_item == item, "LMB release preserves the persistent physical hold")
	mouse(MOUSE_BUTTON_LEFT, true, Vector2(5, 5))
	mouse(MOUSE_BUTTON_LEFT, false, Vector2(5, 5))
	await frames(90)
	check(proxy.position.y < raised - 0.04 and bag.interior.drag_item == null,
		"Releasing the drag restores settling under gravity")
	proxy.sleeping = true
	await frames(2)
	mouse(MOUSE_BUTTON_WHEEL_DOWN, true, motion.position)
	await frames(12)
	check(proxy.position.y > floor_y + 0.01, "Selected stock can be awakened and lifted again after settling")
	await frames(65)
	check(bag.interior.drag_item == item and item.get_instance_id() == identity
		and item.storage_owner == equipment.container and equipment.container.items().count(item) == 1,
		"Persistent wheel hold preserves one unchanged owned object")
	mouse(MOUSE_BUTTON_LEFT, true, Vector2(5, 5))
	mouse(MOUSE_BUTTON_LEFT, false, Vector2(5, 5))
	await frames(75)
	# A real excursion still invokes recovery; physical walls remain primary.
	var safe: Transform3D = bag.interior.safe_poses[item]
	proxy.position.x += 1.0
	await frames(2)
	check(proxy.position.distance_to(safe.origin) < 0.02, "True escape beyond contact slop still recovers")
	# Approach from the bag interior; a plow sphere cannot start through a wall.
	bag.view_yaw = PI
	bag.update_camera()
	var contact := bag.interior.pick(bag.camera, visible_point(item))
	bag.interior.begin_plow(contact.position + contact.normal * 0.028)
	var plow_start := proxy.position
	bag.interior.plow_goal += Vector3(-0.06, 0, 0)
	await frames(65)
	check(bag.interior.plowing and proxy.position.distance_to(plow_start) > 0.001,
		"Round stock remains responsive to the ordinary bounded plow")
	bag.interior.end_plow()
	check(not bag.interior.plowing and not bag.dumping and bag.bag_angle == 0,
		"Ordinary manipulation neither sticks the plow nor triggers inversion")
	print("ROUND PHYSICS ", item.definition.display_name, " horizontal=", horizontal, " lift=", raised - floor_y)

func exercise_group(order: Array[int], label: String) -> void:
	# Rummage top items first; a buried item legitimately cannot lift through a
	# covering solid. No collision or ownership shortcuts are used.
	for index in order:
		var item := items[index]
		var body: RigidBody3D = bag.interior.proxies[item]
		var start := body.position
		bag.select(item)
		check(bag.interior.begin_drag(item), "Each rummaged source acquires its own physical manipulation target")
		bag.interior.drag_goal += Vector3(0.06, 0.10, 0.06)
		await frames(90)
		var moved := body.position.distance_to(start)
		check(moved > 0.015, label + ": settled/contacted item remains physically responsive")
		check(bag.interior.contained(ContainerPacking.bounds(InventoryItem.from_body(item), body.transform), item), "Mixed shapes remain inside collision containment")
		bag.interior.end_drag()
		await frames(35)
		print(label, " ", item.definition.display_name, " movement=", moved)
	var ids := items.map(func(item: InteractableObject) -> int: return item.get_instance_id())
	for cycle in 2:
		screen.toggle_view()
		screen.toggle_view()
		bag = screen.bag
		await frames(50)
	check(items.map(func(item: InteractableObject) -> int: return item.get_instance_id()) == ids
		and equipment.container.items().size() == items.size()
		and items.all(func(item: InteractableObject) -> bool: return item.storage_owner == equipment.container),
		"Repeated reopening preserves the exact owned instances and proxy mapping")
	var tool := items.back() as FasteningTool
	check(tool.inventory_state() == tool_state, "Transfers and contact preserve Uni-Bolt grade and ammunition")
	var body: RigidBody3D = bag.interior.proxies[tool]
	var before := body.position
	check(bag.interior.begin_drag(tool), "Reopened tool acquires its own physical manipulation target")
	bag.interior.drag_goal += Vector3(0.03, 0.07, 0.02)
	await frames(70)
	check(body.position.distance_to(before) > 0.015, "Unequipped Uni-Bolt remains manipulable after reopening")
	bag.interior.end_drag()
	check(not bag.dumping and bag.bag_angle == 0, "Reopening and contact never activate a dump")

func geometry_checks() -> void:
	var rod := items[0]
	var shape := rod.get_node("CollisionShape3D") as CollisionShape3D
	check(shape.shape is CylinderShape3D and is_equal_approx(shape.shape.height, 0.35)
		and is_equal_approx(shape.shape.radius, 0.017), "Rod uses the catalog's real oriented cylinder")
	var pose := Transform3D(Basis(Vector3.RIGHT, 0.65), Vector3(0, 0.02, 0))
	var record := InventoryItem.from_body(rod)
	var box := ContainerPacking.bounds(record, pose)
	check(is_equal_approx(box.size.y, 0.034) and is_equal_approx(box.size.z, 0.034),
		"Rolling a circular cylinder does not invent rectangular corners")
	check(ContainerPacking.inside(box, bag.interior.extent), "A genuinely valid rolled cylinder remains contained")
	var fake_box: AABB = pose * ContainerPacking.local_bounds(rod)
	check(fake_box.position.y < -0.003 and box.position.y > 0,
		"Regression reproduces the former false floor penetration")
	# Exercise the same rolled resting state through the real solver.
	var body: RigidBody3D = bag.interior.proxies[rod]
	body.transform = pose
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	await frames(90)
	bag.interior.begin_drag(rod)
	var start := body.position
	bag.interior.drag_goal += Vector3(0.06, 0.10, 0.05)
	await frames(70)
	check(body.position.y > start.y + 0.06, "Rolled floor contact does not cancel manipulation impulses")
	bag.interior.end_drag()
	await frames(80)

func run() -> void:
	await setup([11])
	await geometry_checks()
	await exercise_single(items[0])
	await teardown()
	await setup([9])
	check(items[0].get_children().filter(func(child: Node) -> bool: return child is CollisionShape3D).size() == 12,
		"Hollow tubing keeps all twelve convex collision strips")
	await exercise_single(items[0])
	await teardown()
	await setup([], true)
	await exercise_group([0], "C tool alone")
	await teardown()
	await setup([11, 9], true)
	await exercise_group([2, 1, 0], "D round stock and tool")
	await teardown()
	await setup([0, 17, 11, 9], true)
	await exercise_group([1, 4, 3, 2, 0], "E mixed stock")
	await teardown()
	print("RD-012 round stock: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

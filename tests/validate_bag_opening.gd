extends "res://tests/validate_round_stock_bag.gd"

func bottom(item: InteractableObject) -> float:
	return ContainerPacking.bounds(InventoryItem.from_body(item), bag.interior.proxies[item].transform).position.y

func lift(item: InteractableObject, clicks: int) -> void:
	bag.select(item)
	for i in clicks:
		mouse(MOUSE_BUTTON_WHEEL_DOWN, true, Vector2(450, 300))
	await frames(110)

func release_empty() -> void:
	mouse(MOUSE_BUTTON_LEFT, true, Vector2(5, 5))
	mouse(MOUSE_BUTTON_LEFT, false, Vector2(5, 5))

func rendered_bottom(item: InteractableObject) -> float:
	var body: RigidBody3D = bag.interior.proxies[item]
	var lowest := INF
	for mesh: MeshInstance3D in body.find_children("*", "MeshInstance3D", true, false):
		for vertex in mesh.mesh.get_faces():
			lowest = minf(lowest, (body.transform * mesh.transform * vertex).y)
	return lowest

func paired_tube_contacts() -> void:
	await setup([9, 9])
	for index in items.size():
		var body: RigidBody3D = bag.interior.proxies[items[index]]
		body.transform = Transform3D(Basis(Vector3.RIGHT, 0.26 if index == 0 else 0),
			Vector3(0, 0.25, -0.07 if index == 0 else 0.07))
		body.sleeping = false
	await frames(180)
	for item in items:
		check(bottom(item) >= -0.001 and rendered_bottom(item) >= -0.002,
			"Dropped and rolled paired tubes retain exterior support within the existing faceted-hull approximation")
	var body: RigidBody3D = bag.interior.proxies[items[0]]
	var other: RigidBody3D = bag.interior.proxies[items[1]]
	var before := body.position
	bag.interior.begin_drag(items[0])
	bag.interior.drag_goal = other.position
	await frames(120)
	check(body.position.distance_to(before) > 0.02 and body.position.distance_to(other.position) > 0.09,
		"Held tube pushes and collides with another tube rather than crossing its occupied volume")
	bag.end_drag()
	await frames(80)
	check(items.all(func(item: InteractableObject) -> bool: return bottom(item) >= -0.001),
		"Both tubes remain floor-supported after mutual contact")
	await teardown()

func floor_and_controls() -> void:
	await setup([9])
	var item := items[0]
	var body: RigidBody3D = bag.interior.proxies[item]
	check(body.max_contacts_reported == 4 and not body.contact_monitor,
		"All bag proxies retain compound contact manifolds without monitor signals")
	check(bottom(item) >= -0.001, "Tube settles on its actual outer surface rather than 20 mm into the floor")
	var shape := item.get_node("CollisionShape3D") as CollisionShape3D
	check(shape.shape is ConvexPolygonShape3D and bag.interior.proxies[item].mass == item.mass,
		"Hollow tube still uses the real compound hull and mass")
	check(rendered_bottom(item) > -0.002, "Rendered tube bottom has no substantial floor penetration")
	# A ray down the bore must not hit this supposedly hollow stock.
	var start := body.position + body.basis.x * -0.25
	var end := body.position + body.basis.x * 0.25
	var bore := PhysicsRayQueryParameters3D.create(start, end, 1)
	check(bag.interior.get_world_3d().direct_space_state.intersect_ray(bore).is_empty(),
		"The hollow bore is not replaced with a solid cylinder")
	var point: Vector2 = visible_point(item)
	mouse(MOUSE_BUTTON_LEFT, true, point)
	var start_y := body.position.y
	var initial_goal := bag.interior.drag_goal.y
	mouse(MOUSE_BUTTON_WHEEL_DOWN, true, point)
	check(is_equal_approx(bag.interior.drag_goal.y - initial_goal, 0.08),
		"Wheel-down raises by the centrally configured doubled 8 cm increment")
	await frames(65)
	check(body.position.y > start_y + 0.05, "Wheel-down physically lifts the tube")
	mouse(MOUSE_BUTTON_LEFT, false, point)
	var held_y := body.position.y
	await frames(60)
	check(bag.interior.drag_item == item and not body.freeze and absf(body.position.y - held_y) < 0.01,
		"LMB release keeps the target held through active collision-aware physics")
	check((screen.bag_panel.get_child(1) as Label).text.begins_with("HELD AT TARGET"),
		"The interface identifies a persistent held target")
	point = visible_point(item)
	mouse(MOUSE_BUTTON_LEFT, true, point)
	var horizontal_start := body.position
	var target_height := bag.interior.drag_goal.y
	var motion := InputEventMouseMotion.new()
	motion.position = bag.camera.unproject_position(body.position + Vector3(0.05, 0, 0.05))
	bag._gui_input(motion)
	await frames(65)
	check(Vector2(body.position.x - horizontal_start.x, body.position.z - horizontal_start.z).length() > 0.025,
		"Settled hollow tube follows actual horizontal drag input")
	check(absf(bag.interior.drag_goal.y - target_height) < 0.001,
		"A new horizontal drag retains the established manipulation height")
	mouse(MOUSE_BUTTON_LEFT, false, motion.position)
	var raised_goal := bag.interior.drag_goal.y
	mouse(MOUSE_BUTTON_WHEEL_UP, true, motion.position)
	check(is_equal_approx(raised_goal - bag.interior.drag_goal.y, 0.08), "Wheel-up lowers the same target")
	await frames(50)
	release_empty()
	await frames(120)
	check(bag.interior.drag_item == null and bottom(item) >= -0.001 and bottom(item) < 0.005,
		"Clicking empty space releases to gravity and the tube resettles on the exterior")
	await lift(item, 2)
	release_empty()
	await frames(150)
	check(bottom(item) >= -0.001, "A second fall and settled manipulation cycle do not lose tube floor contacts")
	check(not bag.dumping and equipment.container.contains(item), "Ordinary height adjustment neither drops nor dumps the item")
	await teardown()

func block_release_area() -> Array[StaticBody3D]:
	var walls: Array[StaticBody3D] = []
	var center: Vector3 = equipment.actor.global_position
	for side in [-1.0, 1.0]:
		for axis in [0, 2]:
			var wall := StaticBody3D.new()
			var shape := CollisionShape3D.new()
			shape.shape = BoxShape3D.new()
			shape.shape.size = Vector3(0.15, 4.0, 1.15) if axis == 0 else Vector3(1.15, 4.0, 0.15)
			wall.add_child(shape)
			facility.add_child(wall)
			wall.position = center + (Vector3(side * 0.5, 1.5, 0) if axis == 0 else Vector3(0, 1.5, side * 0.5))
			walls.append(wall)
	return walls

func opening_transfer(blocked := false) -> void:
	await setup([], true)
	var item := items[0]
	var identity := item.get_instance_id()
	var state := item.inventory_state()
	var body: RigidBody3D = bag.interior.proxies[item]
	# Only the selected object's lid exception is changed, not wall collisions.
	await lift(item, 4)
	check(not bag.interior.can_extract(item), "A partly raised object's center is insufficient for extraction")
	var bag_opening := bag.interior.extent.y
	await lift(item, 4)
	check(bottom(item) >= bag_opening + bag.tuning.exit_clearance and bag.interior.can_extract(item),
		"The whole object must physically clear the opening plus its safety margin")
	check((screen.bag_panel.get_child(1) as Label).text.begins_with("READY TO DROP"),
		"The interface identifies whole-object exit readiness")
	check(item.storage_owner == equipment.container and item.state == InteractableObject.State.STOWED,
		"Crossing the logical boundary alone never transfers ownership")
	var obstacles: Array[StaticBody3D] = []
	if blocked:
		obstacles = block_release_area()
		await frames(3)
	# Releasing an actual new LMB drag confirms extraction; simply releasing
	# the wheel never triggers a transfer.
	var point: Vector2 = visible_point(item)
	mouse(MOUSE_BUTTON_LEFT, true, point)
	mouse(MOUSE_BUTTON_LEFT, false, point)
	await frames(6)
	if blocked:
		check(equipment.container.contains(item) and item.storage_owner == equipment.container
			and item.state == InteractableObject.State.STOWED and screen.feedback.text.contains("No clear space"),
			"Blocked drag-to-drop retains the item and reports the same transactional rejection as RMB Drop")
		check(bag.active and bag.interior.proxies.has(item) and not bag.interior.can_extract(item),
			"A failed drop reopens the item safely inside the authoritative bag")
		for wall in obstacles:
			wall.queue_free()
		await frames(3)
		await lift(item, 9)
		release_empty()
		await frames(6)
	check(not equipment.container.contains(item) and item.storage_owner == null
		and item.state == InteractableObject.State.WORLD and not item.freeze,
		"Deliberate release beyond the opening uses the shared physical world transfer")
	check(item.get_instance_id() == identity and item.inventory_state() == state
		and equipment.held_item() == null, "Extraction preserves original identity, ammunition, condition and slot ownership")
	await frames(100)
	check(item.global_position.y > -0.1 and item.storage_owner == null,
		"Extracted items remain real collision-aware world physics objects")
	await teardown()

func partial_exit_and_collisions() -> void:
	await setup([11, 9])
	var item := items[0]
	await lift(item, 2)
	var body: RigidBody3D = bag.interior.proxies[item]
	var start := body.position
	bag.interior.drag_goal.x = 5
	bag.interior.drag_goal.z = 5
	await frames(100)
	var box := ContainerPacking.bounds(InventoryItem.from_body(item), body.transform)
	check(box.end.x <= bag.interior.extent.x / 2 + 0.001 and box.end.z <= bag.interior.extent.z / 2 + 0.001,
		"Persistent holding does not tunnel through side walls")
	check(body.position.distance_to(start) > 0.01 and not body.freeze, "Wall-constrained holding remains physical")
	await lift(item, 3)
	check(not bag.interior.can_extract(item), "Minor opening overlap cannot trigger a drop")
	release_empty()
	await frames(2)
	check(bag.interior.returning, "Partial release requests a bounded return instead of restoring an overlapping lid")
	var resuming_y := body.position.y
	check(bag.interior.begin_drag(item) and not bag.interior.returning
		and absf(bag.interior.drag_goal.y - resuming_y) < 0.001,
		"Reselecting during return resumes at the current physical height")
	# A freely colliding part can rotate during return. Recompute clearance
	# from that current geometry rather than a stale vertical extent.
	body.rotation.z += 0.45
	bag.end_drag()
	await frames(160)
	check(bag.interior.drag_item == null and not bag.interior.returning
		and equipment.container.contains(item), "Cancelled partial exits return through the opening before restoring their lid")
	# A held item outside is cancelled safely when the view closes. Its
	# ephemeral outside pose must never be saved as packing metadata.
	await lift(item, 9)
	check(bag.interior.can_extract(item), "Clear exit can be prepared without automatic transfer")
	screen.toggle_view()
	screen.toggle_view()
	bag = screen.bag
	await frames(80)
	check(equipment.container.items().size() == 2 and bag.interior.drag_item == null
		and equipment.container.records().all(func(record: InventoryItem) -> bool:
			return ContainerPacking.inside(ContainerPacking.bounds(record, record.internal_pose),
				bag.interior.extent, 0.004)), "Closing an extraction preview never persists an outside packing pose or duplicates ownership")
	var tube := items[1]
	check(bottom(tube) >= -0.001, "Tube contact remains correct alongside round rod after reopening")
	# Preserve the alternate RMB transfer path.
	screen.bag_context(item)
	var drop_index := screen.popup.get_item_index(2)
	check(drop_index >= 0 and screen.popup.get_item_text(drop_index) == "Drop", "RMB Drop remains available")
	screen.perform_action(2)
	check(not equipment.container.contains(item) and item.state == InteractableObject.State.WORLD,
		"RMB Drop continues to use the same transfer operation")
	check(bag.tuning.inversion_degrees == 155 and bag.tuning.inversion_dwell == 0.35
		and equipment.container.definition.capacity_m3 == 0.05
		and equipment.container.definition.effective_capacity_m3() == 0.06
		and equipment.container.definition.maximum_mass_kg == 25,
		"Inversion effort, capacity and expansion ratings are unchanged")
	await teardown()

func run() -> void:
	await paired_tube_contacts()
	await floor_and_controls()
	await opening_transfer()
	await opening_transfer(true)
	await partial_exit_and_collisions()
	print("RD-012 opening controls: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

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

func stock(world: Node3D, id: String, size: Vector3, mass := 0.2) -> InteractableObject:
	var item := InteractableObject.new()
	item.definition = ObjectDefinition.new()
	item.definition.object_id = StringName(id)
	item.definition.display_name = id
	item.definition.mass_kg = mass
	item.definition.mobility = ObjectDefinition.Mobility.CARRYABLE
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	shape.shape = BoxShape3D.new()
	shape.shape.size = size
	item.add_child(shape)
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	mesh.mesh.size = size
	item.add_child(mesh)
	world.add_child(item)
	item.position = Vector3(4, 1, 4)
	item.gravity_scale = 0
	return item

func run() -> void:
	var facility = preload("res://scenes/facility.tscn").instantiate()
	root.add_child(facility)
	current_scene = facility
	var actor := facility.get_node("Otis") as OtisController
	var eq := actor.equipment
	var container := eq.container
	var screen: InventoryScreen = facility.get_node("InteractionUI").inventory
	await frames(4)
	check(is_equal_approx(container.definition.capacity_m3, 0.05) and container.definition.maximum_mass_kg == 25,
		"Satchel capacity is 50 L with an independent 25 kg structural rating")
	check(container.definition.insertion_dimensions == Vector3(0.64, 0.4, 0.26), "Visible interior and opening share metre dimensions")
	var wrench := facility.get_node("Wrench") as InteractableObject
	var identity := wrench.get_instance_id()
	check(eq.store_world(wrench).ok, "Existing world item enters physical packing")
	var first := container.records()[0]
	check(first.packed and ContainerPacking.inside(ContainerPacking.bounds(first, first.internal_pose),
		container.definition.packing_dimensions()), "Storage assigns a safe interior pose before ownership transfer")
	var crate := stock(facility, "TestBlock", Vector3(0.09, 0.055, 0.09))
	check(eq.store_world(crate).ok and container.items().size() == 2, "A second real item occupies the same authoritative container")
	var light_mass := container.mass_kg()
	var heavy := stock(facility, "Overweight", Vector3.ONE * 0.05, 26)
	check(not eq.store_world(heavy).ok and heavy.storage_owner == null, "Physical view does not bypass structural rating")
	var tiny := InventoryContainer.new()
	tiny.definition = container.definition.duplicate()
	tiny.definition.container_id = &"SMALL"
	tiny.definition.insertion_dimensions = Vector3.ONE * 0.2
	tiny.definition.expanded_capacity_m3 = 0
	tiny.definition.expanded_dimensions = Vector3.ZERO
	facility.add_child(tiny)
	var one := stock(facility, "One", Vector3.ONE * 0.15)
	var two := stock(facility, "Two", Vector3.ONE * 0.15)
	check(tiny.insert(one).is_empty(), "Generic container supports the same packing backend")
	var count := tiny.items().size()
	var rejection := tiny.insert(two)
	check(rejection.contains("physical placement") and two.storage_owner == null and two.state == InteractableObject.State.WORLD
		and tiny.items().size() == count, "A fragmented physical fit rejects atomically even below nominal volume")
	check(screen.show_inventory(facility.get_node("InteractionUI").hud), "Inventory still opens with T's normal screen")
	screen.selected = wrench
	screen.toggle_view()
	await frames(30)
	check(screen.bag.active and screen.bag.simulation.own_world_3d and screen.bag.interior.proxies.size() == container.items().size(),
		"Bag view creates an isolated physics world with one representation per record")
	check(screen.bag.interior.selected == wrench and wrench.storage_owner == container and wrench.get_instance_id() == identity,
		"Grid and physical selection refer to the same original item")
	var interior := screen.bag.interior
	var body: RigidBody3D = interior.proxies[crate]
	check(is_equal_approx(body.mass, crate.mass), "Physical proxy mass matches its authoritative item")
	var start := body.position
	var size := InventoryItem.from_body(crate).dimensions()
	var top := start + Vector3(0, size.y / 2, 0)
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_RIGHT
	press.pressed = true
	press.position = screen.bag.camera.unproject_position(top)
	screen.bag._gui_input(press)
	check(not interior.plowing, "RMB press waits for a deliberate hold and movement")
	var movement := InputEventMouseMotion.new()
	movement.position = screen.bag.camera.unproject_position(Vector3(start.x + 0.09, top.y, start.z))
	screen.bag._gui_input(movement)
	screen.bag.advance_gestures(screen.bag.tuning.plow_hold_seconds + 0.01)
	check(interior.plowing, "RMB hold and movement begin the plow")
	await frames(65)
	check(body.position.distance_to(start) > 0.004, "Plow movement physically displaces a block")
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_RIGHT
	release.pressed = false
	screen.route(release)
	check(not interior.plowing and interior.pusher.collision_layer == 0, "RMB release immediately restores ordinary selection")
	check(ContainerPacking.inside(ContainerPacking.bounds(InventoryItem.from_body(crate), body.transform),
		container.definition.packing_dimensions(), 0.004), "Pushed object stays within bag walls")
	var point := screen.bag.camera.unproject_position(body.global_position)
	var hit := interior.pick(screen.bag.camera, point)
	check(not hit.is_empty() and hit.item == crate, "Normal cursor ray selects the visible physical item")
	var click := InputEventMouseButton.new()
	click.button_index = MOUSE_BUTTON_LEFT
	click.pressed = true
	click.position = point
	screen.bag._gui_input(click)
	check(screen.selected == crate and not interior.plowing, "Normal click synchronizes selection without pushing")
	var pose := body.transform
	screen.toggle_view()
	await frames()
	check(not screen.bag.active and screen.bag.simulation == null and first.body == wrench,
		"Leaving Bag View releases temporary physics without affecting inventory ownership")
	var crate_record: InventoryItem
	for record in container.records():
		if record.body == crate:
			crate_record = record
	check(crate_record.internal_pose.is_equal_approx(pose), "Closing captures the physical arrangement")
	screen.toggle_view()
	check(screen.bag.interior.proxies[crate].transform.is_equal_approx(pose), "Reopening preserves the pushed position and orientation")
	screen.toggle_view()
	for record in container.records():
		record.packed = false
		record.internal_pose = Transform3D.IDENTITY
	screen.toggle_view()
	check(screen.bag.active and container.items().size() == 2
		and container.records().all(func(record: InventoryItem) -> bool: return record.packed),
		"Legacy records without packing metadata initialize without losing items")
	screen.toggle_view()
	var snapshot := JSON.parse_string(JSON.stringify(container.snapshot())) as Dictionary
	var registry := {String(wrench.definition.object_id): wrench, String(crate.definition.object_id): crate}
	check(container.restore_manifest(snapshot, registry).is_empty(), "Packed transforms round-trip through the existing manifest")
	for i in 3:
		screen.toggle_view()
		await frames(2)
		screen.toggle_view()
		await frames(2)
	check(container.mass_kg() == light_mass and container.items().size() == 2 and not screen.bag.active,
		"Repeated inspection never duplicates objects or carried mass")
	screen.selected = wrench
	screen.perform_action(0)
	check(eq.held_item() == wrench and not container.contains(wrench), "Grid Equip uses the same physical packing records")
	screen.toggle_view()
	check(screen.bag.interior.selected == null and not container.contains(wrench),
		"Bag retrieval cannot accidentally drop an equipped grid selection")
	screen.toggle_view()
	screen.perform_action(1)
	check(container.contains(wrench) and eq.held_item() == null, "Unequip returns the same item to a valid physical placement")
	screen.hide_inventory()
	check(actor.controls_enabled and not actor.placement.input_suspended, "Closing restores normal world controls")
	check(actor.get_node("ICF01_Wayfarer").core.get_node("RearEquipmentMount/IndustrialSatchel") != null,
		"Satchel is attached through the canonical rear mount")
	await stress_container(facility, screen)
	facility.queue_free()
	await process_frame
	print("RD-012: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func stress_container(facility: Node3D, screen: InventoryScreen) -> void:
	var container := InventoryContainer.new()
	container.definition = preload("res://data/inventory/personal_storage.tres").duplicate()
	container.definition.container_id = &"NEAR-FULL"
	facility.add_child(container)
	var started := Time.get_ticks_usec()
	for index in 40:
		var item := stock(facility, "Load_%d" % index, Vector3(0.12, 0.08, 0.12))
		var issue := container.insert(item)
		check(issue.is_empty(), "Nearly full container admits a small object through bounded packing: " + issue)
	check(container.volume_m3() > 0.045 and container.fullness() == &"bulging", "Near-full geometry reaches the bulging fullness band")
	var bag := BagView.new()
	bag.container = container
	bag.size = Vector2(500, 500)
	screen.add_child(bag)
	check(bag.open().is_empty() and bag.interior.proxies.size() == 40, "Near-full view instantiates forty physical proxies")
	await frames(90)
	var contained := true
	for record in container.records():
		contained = contained and ContainerPacking.inside(ContainerPacking.bounds(record,
			bag.interior.proxies[record.body].transform), container.definition.packing_dimensions(), 0.004)
	check(contained, "Near-full contents remain inside the isolated boundaries")
	bag.close()
	check(bag.simulation == null, "Near-full physics is released on close")
	print("RD-012 near-full packing and 90 physics frames: %.2f seconds" % ((Time.get_ticks_usec() - started) / 1000000.0))
	bag.queue_free()

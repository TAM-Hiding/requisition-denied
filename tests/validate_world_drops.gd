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

func fixture(world: Node3D, id: String, size := Vector3(0.06, 0.05, 0.08)) -> InteractableObject:
	var item := InteractableObject.new()
	item.name = id
	item.definition = ObjectDefinition.new()
	item.definition.object_id = StringName(id)
	item.definition.display_name = id
	item.definition.mass_kg = 0.2
	item.definition.mobility = ObjectDefinition.Mobility.CARRYABLE
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	shape.shape = BoxShape3D.new()
	shape.shape.size = size
	item.add_child(shape)
	world.add_child(item)
	item.position = Vector3(4.5, 1.8, 4.5)
	return item

func enclose(world: Node3D, center: Vector3) -> Array[StaticBody3D]:
	var result: Array[StaticBody3D] = []
	for side in [-1.0, 1.0]:
		for axis in [0, 2]:
			var wall := StaticBody3D.new()
			var shape := CollisionShape3D.new()
			shape.shape = BoxShape3D.new()
			shape.shape.size = Vector3(0.15, 4.0, 1.15) if axis == 0 else Vector3(1.15, 4.0, 0.15)
			wall.add_child(shape)
			world.add_child(wall)
			wall.position = center + Vector3(side * 0.5, 1.5, 0) if axis == 0 else center + Vector3(0, 1.5, side * 0.5)
			result.append(wall)
	return result

func run() -> void:
	var facility = preload("res://scenes/facility.tscn").instantiate()
	root.add_child(facility)
	current_scene = facility
	var actor := facility.get_node("Otis") as OtisController
	var equipment := actor.equipment
	actor.global_position = Vector3(0, 0.02, 3)
	actor.camera.rotation = Vector3.ZERO
	equipment.world_drops.rng.seed = 71487
	await frames(4)
	var items: Array[InteractableObject] = []
	var origins: Array[Vector3] = []
	for i in 8:
		var item := fixture(facility, "NaturalDrop_%d" % i)
		items.append(item)
		check(equipment.store_world(item).ok, "The distribution fixture stores before dropping")
		var id := item.get_instance_id()
		check(equipment.retrieve(item).ok and item.get_instance_id() == id and item.storage_owner == null,
			"Natural release preserves the physical item and removes inventory ownership once")
		origins.append(item.global_position)
		var offset := item.global_position - actor.global_position
		check(offset.z < 0 and Vector2(offset.x, offset.z).length() >= 0.70
			and Vector2(offset.x, offset.z).length() <= 1.75 and not item.lock_rotation,
			"Release uses the forward half-space, bounded reach and free world rotation")
	var varied := false
	for position in origins:
		varied = varied or absf(position.x - origins[0].x) > 0.25
	check(varied, "Consecutive drops vary their angular and radial positions")
	await frames(120)
	check(items.all(func(item: InteractableObject) -> bool:
		return item.global_position.y > -0.05 and item.global_position.y < 0.16 and not item.freeze),
		"The physical objects settle naturally instead of remaining frozen or forming an exact stack")
	for item in items:
		item.queue_free()
	await frames()

	var blocked := fixture(facility, "BlockedDrop")
	check(equipment.store_world(blocked).ok, "Blocked-release fixture enters inventory")
	var walls := enclose(facility, actor.global_position)
	await frames(3)
	check(not equipment.retrieve(blocked).ok and blocked.storage_owner == equipment.container
		and blocked.state == InteractableObject.State.STOWED and equipment.container.contains(blocked),
		"An enclosed full-shape release fails without losing or materializing the item")
	var blocked_dump: Dictionary = await equipment.dump_container()
	check(blocked_dump.released == 0 and blocked_dump.retained == 1 and not equipment.dumping,
		"A completely blocked batch reports retained inventory and releases its operation lock")
	for wall in walls:
		wall.queue_free()
	await frames()
	check(equipment.retrieve(blocked).ok, "Release succeeds again when the world route clears")
	blocked.queue_free()
	await frames()

	var partial: Array[InteractableObject] = []
	for i in 3:
		var part := fixture(facility, "Partial_%d" % i)
		partial.append(part)
		check(equipment.store_world(part).ok, "Partial batch fixture stores")
	var interrupt := func() -> void:
		if partial[0].state == InteractableObject.State.WORLD:
			equipment.world_drops.attempts = 0
	equipment.container.changed.connect(interrupt)
	var report: Dictionary = await equipment.dump_container()
	equipment.container.changed.disconnect(interrupt)
	check(report.released == 1 and report.retained == 2 and report.message.contains("retained"),
		"A batch reports partial success when subsequent placements become unavailable")
	check(partial[0].state == InteractableObject.State.WORLD and partial[1].storage_owner == equipment.container
		and partial[2].storage_owner == equipment.container and equipment.container.items().size() == 2,
		"Partial release never duplicates or deletes the original objects")
	equipment.world_drops.attempts = 48
	var completed: Dictionary = await equipment.dump_container()
	check(completed.released == 2 and completed.retained == 0 and equipment.container.items().is_empty(),
		"A later dump can release the retained objects")
	var tool: FasteningTool = facility.get("bolt_tool")
	tool.load_grade(1)
	tool.rounds.pop_back()
	var before := tool.inventory_state()
	var tool_identity := tool.get_instance_id()
	check(equipment.store_world(tool).ok, "The real Uni-Bolt can be stored for a dump")
	var tool_dump: Dictionary = await equipment.dump_container()
	check(tool_dump.released == 1 and tool.get_instance_id() == tool_identity and tool.inventory_state() == before,
		"Dumping preserves Uni-Bolt grade, ammunition and mutable state")
	facility.queue_free()
	await process_frame
	print("World drops: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

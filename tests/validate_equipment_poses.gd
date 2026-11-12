extends SceneTree
var checks: int = 0
var failures: int = 0
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
func _initialize() -> void:
	call_deferred("run")
func frames(count: int) -> void:
	for frame in range(count):
		await physics_frame
func clear_volume(actor: OtisController, item: InteractableObject) -> bool:
	if not item.visible:
		return true
	var presentation := actor.equipment.presentation
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = presentation.profile.envelope
	query.transform = item.global_transform * presentation.profile.envelope_transform
	query.collision_mask = 1
	query.exclude = [actor.get_rid(), item.get_rid()]
	return actor.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()
func run() -> void:
	var facility := load("res://scenes/facility.tscn").instantiate() as Node3D
	root.add_child(facility)
	current_scene = facility
	var actor := facility.get_node("Otis") as OtisController
	actor.set_physics_process(false)
	var item := facility.get_node("Wrench") as InteractableObject
	var crate := facility.get_node("Crate") as InteractableObject
	var presentation := actor.equipment.presentation
	await frames(3)
	check(actor.equipment.pick_up(item).ok, "Equip item for presentation tests")
	var identity := item.get_instance_id()
	var parent := item.get_parent()
	actor.position = Vector3(3, 0.02, -3)
	actor.rotation = Vector3.ZERO
	actor.camera.rotation = Vector3.ZERO
	for frame in range(40):
		presentation.update_pose(0.0167)
	var normal := actor.camera.to_local(item.global_position)
	check(presentation.requested_pose == HeldItemPresentation.Pose.NORMAL and presentation.pose_blend == 0, "Default pose is NORMAL")
	actor.position.z = -5.45
	presentation.update_pose(0.0167)
	for frame in range(30):
		presentation.update_pose(0.0167)
	var retracted := actor.camera.to_local(item.global_position)
	check(item.visible and clear_volume(actor, item) and presentation.obstructed, "Natural retraction remains collision-clear")
	check(absf(retracted.x - normal.x) < 0.01 and presentation.lateral_shift < 0.001, "Front-wall retraction preserves lateral equipment offset")
	check(retracted.z > normal.z + 0.2 and absf(retracted.z - normal.z) > absf(retracted.y - normal.y) * 5, "Backward travel dominates retraction")
	actor.position = Vector3(5.65, 0.02, 1)
	presentation.update_pose(0.0167)
	check(clear_volume(actor, item) and presentation.lateral_shift <= presentation.profile.lateral_clearance_limit, "Side obstruction permits only bounded lateral correction")
	actor.position = Vector3(3, 0.02, -3)
	for frame in range(60):
		presentation.update_pose(0.0167)
	check(presentation.extension > 0.999 and presentation.lateral_shift < 0.001, "Clearance restores normal extension and lateral offset")
	var service := InteractionService.new()
	actor.position = Vector3(crate.position.x, 0.02, crate.position.z + 2.2)
	actor.camera.look_at(crate.global_position)
	await frames(2)
	check(service.request(&"inspect", actor, actor.camera, crate, 3, actor.knowledge).ok, "Ordinary inspection remains available")
	check(presentation.requested_pose == HeldItemPresentation.Pose.NORMAL, "Inspect does not request lowered pose")
	check(service.request(&"move", actor, actor.camera, crate, 3, actor.knowledge).ok, "Environmental action begins with equipment held")
	check(presentation.requested_pose == HeldItemPresentation.Pose.LOWERED and presentation.pose_blend < 0.01, "Move requests LOWERED without snapping")
	presentation.update_pose(0.0167)
	check(presentation.pose_blend > 0 and presentation.pose_blend < 0.2, "Pose starts with a small interpolated step")
	for frame in range(60):
		presentation.update_pose(0.0167)
	check(presentation.pose_blend > 0.99, "Lowered pose completes smoothly")
	var lowered := presentation.pose_origin_camera()
	var anchor := actor.camera.to_local(actor.get_node("Camera3D/EquipmentAnchor").global_position)
	check(lowered.y < anchor.y - 0.15 and lowered.x > anchor.x, "Lowered pose moves bottom-right")
	check(item.get_parent() == parent and item.state == InteractableObject.State.HELD and actor.equipment.held_item() == item, "Lowering neither detaches nor stows item")
	# Test both poses at abrupt yaw/pitch changes beside a wall.
	actor.position = Vector3(5.65, 0.02, 1)
	for angle in range(0, 361, 45):
		actor.rotation.y = deg_to_rad(angle)
		actor.camera.rotation.x = deg_to_rad(45 if angle % 90 == 0 else -45)
		presentation.update_pose(0.0083)
		check(clear_volume(actor, item), "Lowered pose remains collision-aware on rapid turn %d" % angle)
	check(actor.placement.confirm(), "Release environmental object")
	check(presentation.requested_pose == HeldItemPresentation.Pose.NORMAL and presentation.pose_blend > 0.99, "Release requests NORMAL without ownership change or snap")
	actor.position = Vector3(3, 0.02, -3)
	actor.rotation = Vector3.ZERO
	actor.camera.rotation = Vector3.ZERO
	for frame in range(80):
		presentation.update_pose(0.0167)
	check(presentation.pose_blend < 0.001 and presentation.extension > 0.999, "Release restores normal presentation")
	actor.position = Vector3(crate.position.x, 0.02, crate.position.z + 2.2)
	actor.camera.look_at(crate.global_position)
	for cycle in range(8):
		check(actor.placement.begin_world(crate), "Repeated manipulation starts: %d" % cycle)
		for frame in range(8):
			presentation.update_pose(0.0167)
		actor.placement.cancel()
		for frame in range(8):
			presentation.update_pose(0.0167)
	check(item.get_instance_id() == identity and actor.equipment.held_item() == item and actor.equipment.stored_items().is_empty(), "Repeated pose reversals preserve one equipped instance")
	check(actor.equipment.stow().ok and actor.equipment.equip_first().ok, "Stow/retrieve survives pose transitions")
	check(item.get_instance_id() == identity and item.state == InteractableObject.State.HELD, "Equipment identity retained after retrieve")
	if DisplayServer.get_name() != "headless" and OS.get_environment("RD_SCREENSHOT") != "":
		actor.position = Vector3(0, 0.02, 4)
		actor.camera.rotation = Vector3.ZERO
		presentation.request_pose(HeldItemPresentation.Pose.LOWERED)
		for frame in range(80):
			presentation.update_pose(0.0167)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("RD_SCREENSHOT"))
	facility.queue_free()
	await process_frame
	print("Equipment poses: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

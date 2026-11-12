extends SceneTree
var failures: int = 0
var checks: int = 0
var facility: Node3D
var otis: OtisController
var wrench: InteractableObject
var presentation: HeldItemPresentation
var service := InteractionService.new()

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func frames(count: int) -> void:
	for frame in range(count):
		await physics_frame

func held_clear() -> bool:
	if not wrench.visible:
		return true # Deliberate fallback when even the retracted envelope is blocked.
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = presentation.profile.envelope
	query.transform = wrench.global_transform * presentation.profile.envelope_transform
	query.collision_mask = 1
	query.exclude = [wrench.get_rid(), otis.get_rid()]
	return otis.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func aim_at(item: InteractableObject) -> void:
	otis.position = Vector3(item.position.x, 0.02, item.position.z + 1.8)
	otis.rotation = Vector3.ZERO
	otis.camera.look_at(item.global_position)
	await frames(3)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	facility = load("res://scenes/facility.tscn").instantiate()
	root.add_child(facility)
	current_scene = facility
	otis = facility.get_node("Otis")
	wrench = facility.get_node("Wrench")
	presentation = otis.equipment.presentation
	otis.set_physics_process(false)
	await frames(4)
	await aim_at(wrench)
	check(service.request(&"pick_up", otis, otis.camera, wrench, 3, otis.knowledge).ok, "Pickup through ordinary interaction")
	var identity := wrench.get_instance_id()
	otis.rotation = Vector3.ZERO
	otis.camera.rotation = Vector3.ZERO
	otis.position = Vector3(-3, 0.02, -3)
	for frame in range(30):
		presentation.update_pose(0.0167)
	check(is_equal_approx(presentation.extension, 1) and wrench.visible, "Normal held pose visible in clear space")
	# Camera/player translation into a wall retracts before the next render.
	otis.position.z = -5.65
	presentation.update_pose(0.0167)
	check(presentation.extension < 0.5 and presentation.obstructed, "Translation toward wall retracts equipment")
	check(wrench.visible and held_clear(), "Retracted model remains visible outside wall")
	var stable_min: float = INF
	var stable_max: float = 0
	for frame in range(40):
		presentation.update_pose(0.0167)
		if frame >= 10:
			stable_min = minf(stable_min, presentation.extension)
			stable_max = maxf(stable_max, presentation.extension)
	check(stable_max - stable_min < 0.0001 and held_clear(), "Stationary obstruction does not cycle between restore and retract")
	check(otis.position.is_equal_approx(Vector3(-3, 0.02, -5.65)), "Envelope does not displace actor")
	check(wrench.freeze and wrench.collision_layer == 0, "Held body stays non-dynamic")
	otis.position.z = -3
	presentation.update_pose(0.0167)
	check(presentation.extension < 1, "Clearance restores gradually rather than snapping out")
	for frame in range(40):
		presentation.update_pose(0.0167)
	check(is_equal_approx(presentation.extension, 1), "Held pose fully restores without sticking")
	# Rapid yaw/pitch changes against side wall: each rendered pose must be clear.
	otis.position = Vector3(5.65, 0.02, 1)
	for yaw in range(0, 361, 30):
		otis.rotation.y = deg_to_rad(yaw)
		otis.camera.rotation.x = deg_to_rad(55 if yaw % 60 == 0 else -55)
		presentation.update_pose(0.0083)
		check(held_clear(), "Rapid rotation leaves no visible envelope intersection: %d" % yaw)
	# Swept inter-frame occupancy catches a thin obstacle with clear endpoints.
	otis.rotation = Vector3.ZERO
	otis.camera.rotation = Vector3.ZERO
	otis.position = Vector3(-3.6, 0.02, -2)
	presentation.track(wrench)
	var material := StandardMaterial3D.new()
	facility.box(facility, "ThinObstacle", Vector3(0.06, 0.8, 0.1), Vector3(-3, 1.4, -2.65), material, true)
	await frames(2)
	otis.position.x = -3.0
	presentation.update_pose(0.0167)
	check(presentation.extension < 0.5 and held_clear(), "Swept held volume catches rapid travel across thin obstacle")
	facility.get_node("ThinObstacle").queue_free()
	await frames(2)
	var original_profile := wrench.definition.held_profile
	var alternate := HeldItemProfile.new()
	alternate.envelope = SphereShape3D.new()
	alternate.envelope.radius = 0.25
	wrench.definition.held_profile = alternate
	otis.position = Vector3(-3, 0.02, -5.65)
	presentation.track(wrench)
	check(presentation.profile == alternate and presentation.obstructed and held_clear(), "Item-specific alternate shape controls occupancy")
	wrench.definition.held_profile = original_profile
	presentation.track(wrench)
	otis.position = Vector3(0, 0.02, 3)
	otis.rotation = Vector3.ZERO
	otis.camera.rotation = Vector3.ZERO
	await frames(2)
	check(otis.equipment.stow().ok and wrench.state == InteractableObject.State.STOWED, "Stow still works after retraction")
	check(presentation.item == null and not wrench.visible, "Stowed item no longer tracked or shown")
	check(otis.equipment.equip_first().ok and presentation.item == wrench, "Retrieve restores presentation ownership")
	check(otis.equipment.drop().ok and presentation.item == null, "Drop clears held presentation")
	await frames(80)
	check(wrench.position.y > 0.02 and wrench.position.y < 0.2, "Drop still settles on floor")
	check(otis.equipment.pick_up(wrench).ok and wrench.get_instance_id() == identity, "Same instance picked up again")
	# Preserve the user's confirmed surface placements on both fixtures.
	for kind in ["Crate", "Generator"]:
		var object := (facility.get("generator") if kind == "Generator" else facility.get_node(kind)) as InteractableObject
		var collider := object.get_node("CollisionShape3D") as CollisionShape3D
		var top: float = object.global_position.y + collider.shape.size.y * 0.5
		otis.position = Vector3(object.global_position.x, 0.02, object.global_position.z + 1.5)
		otis.camera.look_at(Vector3(object.global_position.x, top + 0.15, object.global_position.z + 0.35))
		await frames(3)
		check(otis.equipment.drop().ok, "Clear drop onto " + kind)
		await frames(90)
		check(wrench.position.y > top + 0.02 and wrench.position.y < top + 0.15, "Wrench rests on top of " + kind)
		check(otis.equipment.pick_up(wrench).ok, "Retrieve surface-placed wrench")
	check(wrench.get_instance_id() == identity, "Surface placement preserves instance identity")
	var crate := facility.get_node("Crate") as InteractableObject
	await aim_at(crate)
	check(service.request(&"move", otis, otis.camera, crate, 3, otis.knowledge).ok, "Move action allowed with equipped wrench")
	check(otis.equipment.held_item() == wrench and wrench.state == InteractableObject.State.HELD, "Move does not stow/drop/duplicate equipment")
	check(otis.placement.load_fraction() > 0.0, "Suspended load applies chassis movement penalties")
	check(otis.placement.confirm() and otis.equipment.held_item() == wrench, "Placement preserves equipped item")
	check(otis.placement.load_fraction() == 0.0, "Placement removes movement penalty")
	if DisplayServer.get_name() != "headless":
		# Save the close-wall view after the motion test, before teardown.
		otis.set_physics_process(false)
		otis.position = Vector3(3, 0.02, -5.25)
		otis.rotation = Vector3.ZERO
		otis.camera.rotation = Vector3.ZERO
		presentation.update_pose(0.0167)
		await process_frame
		await RenderingServer.frame_post_draw
		if OS.get_environment("RD_SCREENSHOT") != "":
			root.get_texture().get_image().save_png(OS.get_environment("RD_SCREENSHOT"))
	facility.queue_free()
	await process_frame
	print("RD-002 follow-up: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

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
		var object := facility.get_node(kind) as InteractableObject
		var collider := object.get_node("CollisionShape3D") as CollisionShape3D
		var top: float = object.position.y + collider.shape.size.y * 0.5
		otis.position = Vector3(object.position.x, 0.02, object.position.z + 1.5)
		otis.camera.look_at(Vector3(object.position.x, top + 0.15, object.position.z + 0.35))
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
	check(otis.manipulation.effective_speed(otis.movement_speed) < crate.move_speed, "Manipulation speed leaves tracking headroom")
	check(otis.manipulation.minimum_separation() > 0.95, "Separation accounts for both collision bodies")
	check(otis.manipulation.stop_move().ok and otis.equipment.held_item() == wrench, "Release preserves equipped item")
	check(is_equal_approx(otis.manipulation.effective_speed(otis.movement_speed), 4), "Normal speed returns after release")
	if DisplayServer.get_name() != "headless":
		await pushing_regression(crate)
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

func pushing_regression(crate: InteractableObject) -> void:
	otis.position = Vector3(crate.position.x, 0.02, crate.position.z + 2.2)
	otis.rotation = Vector3.ZERO
	otis.camera.look_at(crate.global_position)
	otis.velocity = Vector3.ZERO
	otis.set_physics_process(true)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await frames(3)
	check(service.request(&"move", otis, otis.camera, crate, 3, otis.knowledge).ok, "Forward push begins with held item")
	var distance := otis.manipulation.intended_distance()
	var original_speed := otis.movement_speed
	var minimum_gap: float = INF
	var contacts: int = 0
	var max_speed: float = 0
	var reversals: int = 0
	var previous_z := crate.position.z
	var start_z := crate.position.z
	Input.action_press("move_forward")
	for frame in range(100):
		await physics_frame
		var gap := Vector2(crate.position.x - otis.position.x, crate.position.z - otis.position.z).length()
		minimum_gap = minf(minimum_gap, gap)
		max_speed = maxf(max_speed, Vector2(otis.velocity.x, otis.velocity.z).length())
		if crate.position.z > previous_z + 0.005:
			reversals += 1
		previous_z = crate.position.z
		for index in range(otis.get_slide_collision_count()):
			if otis.get_slide_collision(index).get_collider() == crate:
				contacts += 1
	Input.action_release("move_forward")
	print("Push metrics: min gap=%.3f m, contacts=%d, max player speed=%.3f m/s, crate reversals=%d" % [minimum_gap, contacts, max_speed, reversals])
	check(crate.position.z < start_z - 1, "Forward push moves crate deliberately")
	check(contacts == 0 and reversals == 0, "Forward push has no player/crate contact correction or backwards oscillation")
	check(minimum_gap >= otis.manipulation.minimum_separation() - 0.03, "Minimum separation maintained through forward push")
	check(max_speed <= otis.manipulation.effective_speed(original_speed) + 0.01, "Player cannot outrun crate drive")
	check(is_equal_approx(distance, otis.manipulation.intended_distance()), "Intended distance never ratchets due to motion")
	# Continue into the north wall; no collision bypass or player/crate shoving.
	Input.action_press("move_forward")
	await frames(220)
	Input.action_release("move_forward")
	check(crate.position.z > -5.4 and otis.position.z > crate.position.z + 1.35, "Wall stops crate and player holds separation")
	check(otis.manipulation.moving_object() == crate, "Blocked push remains controlled")
	check(otis.equipment.held_item() == wrench and wrench.state == InteractableObject.State.HELD, "Equipment unchanged throughout push")
	otis.manipulation.stop_move()
	check(is_equal_approx(otis.movement_speed, original_speed) and is_equal_approx(otis.manipulation.effective_speed(original_speed), original_speed), "Release restores normal configured movement speed")
	# Resume ordinary equipment shortcuts after manipulation, preserving identity.
	check(service.request_actor_action(&"stow", otis).ok and service.request_actor_action(&"equip_first", otis).ok, "Equipment controls still work after manipulation")

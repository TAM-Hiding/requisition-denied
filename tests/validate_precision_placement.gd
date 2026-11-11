extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func frames(count: int) -> void:
	for frame in count:
		await physics_frame

func tap(placement: PrecisionPlacement) -> void:
	placement.press_drop(1000000)
	placement.release_drop(1100000)

func key(code: Key, pressed: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	return event

func run() -> void:
	var facility := load("res://scenes/facility.tscn").instantiate() as Node3D
	root.add_child(facility)
	current_scene = facility
	var actor := facility.get_node("Otis") as OtisController
	var ui: CanvasLayer = facility.get_node("InteractionUI")
	ui.set_physics_process(false)
	var placement := actor.placement
	var equipment := actor.equipment
	var wrench := facility.get_node("Wrench") as InteractableObject
	var id := wrench.get_instance_id()
	var shape: Shape3D = wrench.get_node("CollisionShape3D").shape
	await frames(5)
	check(equipment.pick_up(wrench).ok, "Equip wrench")
	placement.press_drop(1000000)
	placement.advance_drop(1349999)
	check(not placement.is_active() and equipment.held_item() == wrench, "349999 microseconds is still a pending tap")
	placement.release_drop(1349999)
	check(wrench.state == InteractableObject.State.WORLD and equipment.held_item() == null, "Short G executes ordinary drop")
	await frames(4)
	check(equipment.pick_up(wrench).ok, "Re-equip the same wrench")
	placement.press_drop(2000000)
	placement.advance_drop(2350000)
	check(placement.is_active(), "Exactly 350000 microseconds enters placement")
	placement.release_drop(2360000)
	check(placement.is_active() and equipment.held_item() == wrench, "Entry release keeps preview active")
	check(wrench.freeze and wrench.collision_layer == 0 and equipment.presentation.item == null, "Preview suspends held presentation and physics")
	check(wrench.get_instance_id() == id and equipment.stored_items().is_empty(), "Preview retains one instance and the same slot")
	check(not equipment.stow().ok and not equipment.drop().ok, "Other equipment transitions are guarded")
	placement.press_drop(3000000)
	placement.release_drop(3500000)
	check(placement.is_active(), "Holding again does not confirm")
	await frames(35)
	check(placement.valid and wrench.global_position.distance_to(placement.target_position()) < 0.005, "Preview follows camera target")
	check(placement.axis == 0, "Initial axis is X")
	for expected in [1, 2, 0]:
		placement.cycle_axis()
		check(placement.axis == expected, "Cycle visits axis %d" % expected)
	var before := wrench.global_transform
	placement.rotate_from_mouse(25)
	await frames(5)
	var expected_basis := before.basis * Basis(Vector3.RIGHT, 25 * placement.rotation_speed)
	check(wrench.global_basis.is_equal_approx(expected_basis), "Rotation uses the object's local X")
	check(wrench.global_position.distance_to(before.origin) < 0.005, "Rotation preserves pivot")
	actor.camera.rotate_y(0.2)
	await frames(35)
	check(wrench.global_basis.is_equal_approx(expected_basis), "Camera aiming preserves object orientation")
	placement.adjust_distance(100)
	check(placement.distance == placement.maximum_distance, "Wheel clamps maximum distance")
	placement.adjust_distance(-100)
	check(placement.distance == placement.minimum_distance, "Wheel clamps minimum distance")
	placement.distance = 1.35
	actor.global_position = Vector3(-5.45, 0.01, 3.0)
	wrench.global_transform = Transform3D(Basis.IDENTITY, Vector3(-5.7, 1.65, 2.55))
	aim(actor, Vector3(-6.8, 1.65, 2.55))
	await frames(35)
	check(placement.valid and wrench.global_position.x > -6.0, "Wall-constrained displayed pose is clear")
	var wall_start := wrench.global_position
	var wall_target := placement.target_position() + Vector3.BACK * 1.1
	aim(actor, wall_target)
	var wall_clear := true
	for step in 32:
		await physics_frame
		wall_clear = wall_clear and placement.valid
	check(wrench.global_position.z > wall_start.z + 0.8 and absf(wrench.global_position.x - wall_start.x) < 0.04,
		"Wall contact preserves tangential travel")
	check(wall_clear and wrench.collision_mask == 0, "Every wall-slide pose is clear and the preview mask is restored")
	var valid_pose := wrench.global_transform
	wrench.global_position = Vector3(-6.1, 1.65, 3)
	tap(placement)
	check(placement.is_active() and equipment.held_item() == wrench, "Actually overlapping wall pose cannot be confirmed")
	wrench.global_transform = valid_pose
	actor.global_position = Vector3(-5.2, 0.01, 5.1)
	await frames(3)
	wrench.global_transform = Transform3D(Basis.IDENTITY, Vector3(-5.7, 1.6, 5.7))
	aim(actor, Vector3(-6.45, 1.1, 6.45))
	await frames(40)
	var corner := wrench.global_position
	check(corner.x > -6 and corner.x < -5.85 and corner.z < 6 and corner.z > 5.7
		and absf(corner.y - 1.1) < 0.035 and placement.valid, "Two-plane corner clips both inward components and allows vertical travel")
	var departure := Vector3(-5.5, 1.1, 5.5)
	aim(actor, departure)
	placement.update_preview(1.0 / 60.0)
	var expected_departure := corner.lerp(departure, 1.0 - exp(-placement.follow_speed / 60.0))
	check(wrench.global_position.distance_to(expected_departure) < 0.005, "Corner departure resumes smoothed motion immediately")
	var outside_actor := wrench.global_transform
	wrench.global_position = actor.global_position + Vector3.UP
	check(not placement.confirm() and not placement.valid, "Actually overlapping Otis cannot be confirmed")
	wrench.global_transform = outside_actor
	placement.minimum_distance = 0.45
	actor.global_position = Vector3(4.5, 0.01, 3.8)
	actor.camera.look_at(actor.camera.global_position + Vector3.RIGHT)
	placement.distance = 1.35
	await frames(55)
	wrench.global_transform = Transform3D(Basis.IDENTITY, placement.target_position())
	await frames(8)
	check(placement.valid, "Narrow side of wrench fits near wall")
	placement.cycle_axis()
	placement.rotate_from_mouse(175)
	await frames(15)
	check(placement.valid and wrench.global_position.x < 6.0
		and absf(wrench.global_basis.z.x) < 0.99, "Wall stops unsafe rotation while the displayed pose stays clear")
	var stopped_basis := wrench.global_basis
	placement.rotate_from_mouse(-15)
	await frames(7)
	check(not wrench.global_basis.is_equal_approx(stopped_basis) and placement.valid, "Reverse rotation can leave wall contact")
	var crate := facility.get_node("Crate") as InteractableObject
	actor.global_position = crate.global_position + Vector3(0, -0.64, 1.8)
	await frames(3)
	actor.camera.look_at(crate.global_position)
	placement.distance = actor.camera.global_position.distance_to(crate.global_position)
	await frames(30)
	var safe_pose := wrench.global_transform
	wrench.global_position = crate.global_position
	check(not placement.confirm(), "Actually overlapping crate cannot be confirmed")
	wrench.global_transform = safe_pose
	placement.cancel()
	check(not placement.is_active() and equipment.presentation.item == wrench and not wrench.top_level, "Cancel restores ordinary equipped presentation")
	check(wrench.get_instance_id() == id and equipment.held_item() == wrench, "Cancel preserves identity and ownership")
	actor.global_position = Vector3(0, 0.01, 4)
	await frames(3)
	actor.camera.look_at(actor.camera.global_position + Vector3.FORWARD)
	await frames(10)
	placement.press_drop(4000000)
	placement.release_drop(4350000)
	check(placement.is_active(), "Release checks threshold even between physics ticks")
	await frames(40)
	var release_pose := wrench.global_transform
	tap(placement)
	check(not placement.is_active() and equipment.held_item() == null and wrench.global_transform.is_equal_approx(release_pose), "Valid tap releases displayed pose")
	check(wrench.get_instance_id() == id and wrench.get_node("CollisionShape3D").shape == shape and is_equal_approx(wrench.mass, 0.6), "Release preserves identity, shape and mass")
	await frames(90)
	check(wrench.global_position.y < 0.25 and not wrench.freeze and not wrench.lock_rotation, "Unsupported item falls to floor with angular physics")

	var plate: PhysicalLoadSensor = facility.load_plate
	var weight := facility.get_node("TestWeight") as InteractableObject
	crate.global_position = plate.global_position + Vector3.UP * 0.66
	crate.linear_velocity = Vector3.ZERO
	crate.sleeping = false
	actor.global_position = plate.global_position + Vector3(0, 0.01, 1.9)
	await frames(25)
	check(is_equal_approx(plate.measured_kg, 35), "Crate starts below load threshold")
	check(equipment.pick_up(weight).ok, "Precision controller also supports calibration weight")
	var elevated := crate.global_position + Vector3.UP * 1.29
	actor.camera.look_at(elevated)
	await frames(12)
	check(placement.begin(), "Enter placement for elevated surface")
	# A controlled initial tilt makes the response measurable independently
	# of the equipment anchor's authored rotation.
	var tilt := Basis(Vector3.BACK, deg_to_rad(35.0))
	weight.global_transform = Transform3D(tilt, elevated)
	aim(actor, elevated + Vector3.LEFT * 0.12)
	await frames(28)
	check(weight.global_basis.is_equal_approx(tilt), "Free translation preserves the tilted orientation")
	placement.rotating = true
	placement.cycle_axis()
	placement.cycle_axis()
	placement.rotate_from_mouse(-4)
	await frames(4)
	var manual_basis := weight.global_basis
	check(not manual_basis.is_equal_approx(tilt), "Manual rotation still controls the held block")
	aim(actor, crate.global_position + Vector3.UP * 0.4 + Vector3.LEFT * 0.28)
	await frames(40)
	var contact := weight.global_position
	check(placement.valid and contact.y > crate.global_position.y + 0.65, "Tilted corner meets crate without penetration")
	check(weight.global_basis.is_equal_approx(manual_basis), "Holding R suppresses contact response")
	# Release R and continue applying pressure without changing the aim.
	var before_contact := weight.global_basis
	placement.rotating = false
	await frames(6)
	var early_turn := before_contact.get_rotation_quaternion().angle_to(weight.global_basis.get_rotation_quaternion())
	check(early_turn > 0.003 and early_turn < 0.16, "Releasing R resumes progressive contact rotation")
	var all_clear := true
	for step in 150:
		await physics_frame
		all_clear = all_clear and placement.valid
	check(all_clear, "Every accommodated pose remains clear")
	check(weight.global_basis.y.dot(Vector3.UP) > 0.997, "Downward pressure brings the block's face toward the crate")
	var settled_basis := weight.global_basis
	var settled_height := weight.global_position.y
	await frames(45)
	check(weight.global_basis.is_equal_approx(settled_basis) and absf(weight.global_position.y - settled_height) < 0.002,
		"Sustained pressure does not oscillate a settled face")
	var slide_start := weight.global_position
	aim(actor, slide_start + Vector3.RIGHT * 0.42)
	await frames(35)
	check(weight.global_position.x > slide_start.x + 0.36 and weight.global_basis.is_equal_approx(settled_basis),
		"Parallel motion slides without spontaneous rotation")
	var lift_start := weight.global_position
	aim(actor, lift_start + Vector3.UP * 0.2)
	await frames(30)
	check(weight.global_position.y > lift_start.y + 0.17 and weight.global_basis.is_equal_approx(settled_basis),
		"Aiming upward leaves contact without changing orientation")
	aim(actor, crate.global_position + Vector3.UP * 0.45)
	await frames(40)
	check(placement.valid, "Accommodated block returns to a release-safe pose")
	check(placement.confirm(), "Confirm collision-constrained placement above crate")
	await frames(145)
	check(weight.global_position.y > 1.3 and is_equal_approx(plate.measured_kg, 43), "Rotated weight settles on crate and totals 43 kg")
	check(plate.is_active() and facility.barrier.state == PoweredBarrier.State.OPEN, "Sustained stack opens gate")
	check(equipment.pick_up(weight).ok, "Remove the same calibration block")
	await frames(6)
	check(not plate.is_active() and is_equal_approx(plate.measured_kg, 35), "Removing weight releases signal")
	actor.global_position = Vector3(4.55, 0.01, 3.65)
	await frames(4)
	aim(actor, Vector3(6.25, 1.65, 3.1))
	await frames(12)
	check(placement.begin(), "Enter placement for wall contact response")
	aim(actor, Vector3(6.25, 1.65, 3.1))
	var wall_tilt := Basis(Vector3.RIGHT, deg_to_rad(20.0)) * Basis(Vector3.BACK, deg_to_rad(25.0))
	weight.global_transform = Transform3D(wall_tilt, Vector3(5.55, 1.65, 3.1))
	var wall_clear_frames := true
	for step in 140:
		await physics_frame
		wall_clear_frames = wall_clear_frames and placement.valid
	check(wall_clear_frames and weight.global_position.x < 6.0, "Wall accommodation stays clear")
	check(weight.global_basis.x.dot(Vector3.RIGHT) > 0.997 and weight.global_basis.y.dot(Vector3.UP) < 0.99,
		"Pressure against the wall can settle a face while retaining tilt from world up")
	placement.cancel()
	if DisplayServer.get_name() != "headless":
		await validate_graphical_input(actor, ui)
	facility.queue_free()
	await process_frame
	print("RD-004: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func aim(actor: OtisController, target: Vector3) -> void:
	actor.camera.look_at(target)
	actor.placement.distance = actor.camera.global_position.distance_to(target)

func validate_graphical_input(actor: OtisController, ui: CanvasLayer) -> void:
	actor.global_position = Vector3(0, 0.01, 4)
	await frames(5)
	actor.camera.look_at(actor.camera.global_position + Vector3.FORWARD)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	ui.set_physics_process(true)
	ui._input(key(KEY_G, true))
	await create_timer(0.42).timeout
	ui._input(key(KEY_G, false))
	check(actor.placement.is_active(), "Graphical G events enter persistent preview")
	var camera_basis := actor.camera.global_basis
	var item := actor.equipment.held_item()
	var item_basis := item.global_basis
	ui._input(key(KEY_R, true))
	var motion := InputEventMouseMotion.new()
	motion.relative = Vector2(20, 0)
	actor._unhandled_input(motion)
	await frames(5)
	check(actor.camera.global_basis.is_equal_approx(camera_basis) and not item.global_basis.is_equal_approx(item_basis), "R routes mouse motion to object")
	ui._input(key(KEY_R, false))
	actor._unhandled_input(motion)
	check(not actor.camera.global_basis.is_equal_approx(camera_basis), "R release restores camera motion")
	ui._input(key(KEY_SHIFT, true))
	ui._input(key(KEY_SHIFT, false))
	check(actor.placement.axis == 1, "Shift key event selects Y")
	var prior_distance := actor.placement.distance
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	ui._input(wheel)
	check(actor.placement.distance > prior_distance, "Mouse wheel event changes range")
	var start := actor.global_position
	Input.action_press("move_right")
	await frames(16)
	Input.action_release("move_right")
	check(actor.global_position.distance_to(start) > 0.15 and actor.placement.is_active(), "WASD works during placement")
	if not OS.get_environment("RD_SCREENSHOT").is_empty():
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("RD_SCREENSHOT"))
	ui._input(key(KEY_ESCAPE, true))
	check(not actor.placement.is_active() and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and actor.equipment.held_item() == item, "Escape cancels and retains capture and item")

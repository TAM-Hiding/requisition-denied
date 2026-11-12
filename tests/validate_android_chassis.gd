extends SceneTree

var checks := 0
var failures := 0

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

func place(body: RigidBody3D, point: Vector3) -> void:
	body.global_transform = Transform3D(Basis.IDENTITY, point)
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	body.sleeping = false

func chassis_values(chassis: AndroidChassis) -> Array[float]:
	var values: Array[float] = []
	for index in AndroidChassis.NOMINAL.size():
		values.append(chassis.effective(index))
	return values

func run() -> void:
	var same := chassis_values(AndroidChassis.generate(506))
	check(same == chassis_values(AndroidChassis.generate(506)), "Fixed seed is reproducible")
	check(same != chassis_values(AndroidChassis.generate(507)), "Different seeds produce different configurations")
	var in_range := true
	for seed_value in 128:
		var values := chassis_values(AndroidChassis.generate(seed_value))
		for index in values.size():
			var nominal: float = AndroidChassis.NOMINAL[index]
			var tolerance: float = AndroidChassis.TOLERANCE[index]
			in_range = in_range and absf(values[index] - nominal) <= nominal * tolerance + 0.000001
	check(in_range, "Manufacturing values stay within tolerance")
	var modified := AndroidChassis.generate(506)
	check(modified.set_contribution(&"test_arms", {AndroidChassis.Attribute.LIFT_KG: 3.0})
		and is_equal_approx(modified.effective(AndroidChassis.Attribute.LIFT_KG), modified.base(AndroidChassis.Attribute.LIFT_KG) + 3.0),
		"Installed contribution changes effective lift without changing base")
	check(not modified.set_contribution(&"invalid", {AndroidChassis.Attribute.MASS_KG: INF}),
		"Invalid component data is rejected")

	var facility := preload("res://scenes/facility.tscn").instantiate()
	facility.chassis_seed = 506
	root.add_child(facility)
	current_scene = facility
	await frames(5)
	var actor: OtisController = facility.get_node("Otis")
	var crate: InteractableObject = facility.get_node("Crate")
	var weight: InteractableObject = facility.get_node("TestWeight")
	var wrench: InteractableObject = facility.get_node("Wrench")
	var placement := actor.placement
	var plate: PhysicalLoadSensor = facility.load_plate
	var ui := facility.get_node("InteractionUI")
	ui.set_physics_process(false)
	var identity := crate.get_instance_id()
	var shape: Shape3D = crate.get_node("CollisionShape3D").shape
	check(chassis_values(actor.chassis) == same, "Facility creates Otis's requested seeded chassis")
	check(is_equal_approx(actor.movement_speed, same[AndroidChassis.Attribute.WALK_MPS])
		and is_equal_approx(actor.acceleration, same[AndroidChassis.Attribute.ACCELERATION_MPS2]),
		"Walking speed and acceleration read the chassis")
	check(crate.mass == 35.0 and weight.mass == 8.0 and plate.activation_kg == 40.0 and plate.release_kg == 37.0,
		"Load masses and thresholds retain their original values")
	actor.global_position = Vector3(-2.5, 0.01, 1.15)
	await frames(4)
	aim(actor, crate.global_position)
	check(crate.query_actions().has(&"move") and crate.query_actions().has(&"inspect")
		and not crate.query_actions().has(&"lift"), "Context retains Move and Inspect")
	placement.press_drop(1000000)
	placement.advance_drop(1199999)
	placement.release_drop(1199999)
	check(not placement.is_active() and not crate.freeze, "Short G tap never grabs")
	grab(actor, crate)
	check(placement.is_grabbing() and crate.freeze and crate.get_instance_id() == identity
		and crate.get_node("CollisionShape3D").shape == shape and crate.mass == 35.0
		and crate.collision_layer == 1 and crate.get_parent() == facility, "Hold G acquires the original collidable world body")
	check(not placement.begin_world(crate) and not facility.terminal_session.enter(),
		"Grab owns the interaction")
	var origin_y := crate.position.y
	var initial_basis := crate.basis
	var initial_range := placement.distance
	placement.adjust_distance(1)
	check(placement.distance > initial_range, "Grab shares wheel range adjustment")
	aim(actor, crate.position + Vector3.UP * 0.55)
	await frames(30)
	await check_freeform(actor, crate)
	check(crate.position.y > origin_y + 0.25 and not crate.basis.is_equal_approx(initial_basis)
		and placement.valid, "Grab follows camera lift and shares manual rotation")
	actor.camera.look_at(actor.camera.global_position + Vector3(0, 1, -0.1))
	check(actor.target_hit().get("collider") != crate and placement.is_grabbing(), "Losing targeting does not release the grab")
	var clear_pose := crate.global_transform
	place_gesture(placement)
	check(not placement.is_active() and not crate.freeze and crate.global_transform == clear_pose,
		"A second G tap restores physics at the last clear pose")
	await frames(45)
	check(crate.position.y < clear_pose.origin.y - 0.22 and placement.load_fraction() == 0.0,
		"Released crate falls and unloaded movement returns")
	var prior := 1.01
	var smooth := true
	for step in 111:
		var factor := PrecisionPlacement.response_factor(step, 100.0)
		smooth = smooth and factor <= prior and prior - factor <= 0.011 and factor >= 0.299
		prior = factor
	check(smooth and PrecisionPlacement.response_factor(10, 100) > PrecisionPlacement.response_factor(90, 100),
		"Response falls smoothly to a bounded floor as load increases")

	place(crate, Vector3(-2.5, 0.65, -0.5))
	await frames(12)
	crate.mass = 55.0
	grab(actor, crate)
	check(placement.is_supported_grab() and not crate.freeze and placement.suspended_mass_kg() == 0.0,
		"Overweight grab keeps dynamics and transfers no mass to Otis")
	var heavy_origin := crate.position
	aim(actor, heavy_origin + Vector3.RIGHT * 0.55 + Vector3.UP * 0.55)
	placement.set_rotating(true)
	check(not placement.rotating, "Overweight drag cannot claim rotation input")
	await frames(45)
	check(crate.position.x > heavy_origin.x + 0.15 and crate.position.y < 0.67,
		"Overweight grab slides under gravity without a lifting or rotation command")
	var escape := InputEventAction.new()
	escape.action = "ui_cancel"
	escape.pressed = true
	ui._input(escape)
	check(not placement.is_active() and not crate.freeze and crate.state == InteractableObject.State.WORLD,
		"Escape releases the supported grab")
	aim(actor, crate.global_position)
	ui.open_menu(crate)
	ui.perform_action(&"move")
	check(not ui.menu_open and placement.is_supported_grab() and not crate.freeze, "Contextual Move uses supported precision manipulation")
	place_gesture(placement)
	check(not placement.is_active(), "Contextual supported movement confirms")

	crate.mass = 35.0

	aim(actor, crate.global_position)
	ui.open_menu(crate)
	ui.perform_action(&"move")
	check(not ui.menu_open and placement.is_grabbing() and crate.freeze, "Contextual Move activates the same suspended controller")
	var start_height := crate.position.y
	aim(actor, crate.position + Vector3.UP * 0.45)
	await frames(24)
	check(crate.position.y > start_height + 0.20, "Contextual Move can lift within capacity")
	ui._notification(Node.NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(placement.is_active() and crate.freeze and placement.input_suspended, "Focus loss suspends contextual movement")
	ui._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	placement.cancel()
	await frames(30)

	await check_obstacle(actor, crate, Vector3(2.5, 0.01, 4.7), Vector3.RIGHT, 6.0, "east wall")
	await check_obstacle(actor, crate, Vector3(0, 0.01, -2.6), Vector3.FORWARD, 5.04, "terminal desk")
	await check_obstacle(actor, crate, Vector3(4.65, 0.01, -1.3), Vector3.FORWARD, 4.26, "closed gate")

	actor.global_position = Vector3(-3, 0.01, 4)
	place(crate, Vector3(-3, 0.65, 2.35))
	await frames(15)
	grab(actor, crate)
	var tilted := Basis(Vector3.BACK, 0.33)
	crate.global_transform = Transform3D(tilted, Vector3(-3, 1.05, 2.35))
	aim(actor, Vector3(-3, 0.35, 2.35))
	await frames(65)
	check(placement.valid and crate.basis.y.dot(Vector3.UP) > tilted.y.dot(Vector3.UP) + 0.02,
		"Shared floor contact rotates a tilted crate toward a supported face")
	ui._input(escape)
	check(not placement.is_grabbing() and not crate.freeze, "Escape restores dynamics for a suspended crate")

	actor.global_position = plate.global_position + Vector3.UP * 0.01
	place(crate, plate.global_position + Vector3(0, 0.65, 1.75))
	await frames(12)
	grab(actor, crate)
	aim(actor, crate.position + Vector3.UP * 0.35)
	await frames(30)
	check(is_equal_approx(plate.measured_kg, actor.body_mass_kg + 35.0) and plate.is_active(),
		"Suspended load transfers through Otis exactly once")
	place_gesture(placement)
	await frames(100)
	check(is_equal_approx(plate.measured_kg, actor.body_mass_kg)
		and facility.barrier.state == PoweredBarrier.State.OPEN, "Released crate outside plate contributes no carried mass")

	actor.global_position = Vector3(0, 0.02, 1.25)
	place(wrench, Vector3(0, 0.06, 0))
	await frames(12)
	grab(actor, wrench)
	check(placement.is_grabbing() and actor.equipment.held_item() == null, "World wrench can be positioned without equipment ownership")
	place_gesture(placement)
	check(not wrench.freeze and not placement.is_active(), "World wrench returns to physics")
	check(actor.equipment.pick_up(wrench).ok and actor.equipment.stow().ok
		and actor.equipment.equip_first().ok, "Wrench pickup, storage and retrieval still work")
	actor.camera.look_at(actor.camera.global_position + Vector3.FORWARD)
	placement.press_drop(2000000)
	placement.advance_drop(2200000)
	placement.release_drop(2200000)
	check(actor.equipment.placing and not placement.is_grabbing(), "Wrench placement persists after key-up")
	placement.cancel()
	check(actor.equipment.held_item() == wrench and not placement.is_active(), "Cancel returns the equipped wrench")
	placement.press_drop(3000000)
	placement.release_drop(3200000)
	await frames(15)
	place_gesture(placement)
	check(not placement.is_active() and actor.equipment.held_item() == null, "Wrench precision confirmation releases equipment")
	check(actor.equipment.pick_up(wrench).ok and actor.equipment.drop().ok, "Wrench ordinary drop still works")
	var terminal: TerminalWorkstation = facility.get_node("Terminal")
	actor.global_position = Vector3(0, 0.01, -4.1)
	actor.camera.look_at(terminal.global_position)
	await frames(5)
	var session: TerminalInteraction = facility.terminal_session
	check(session.enter(), "Enter the terminal after releasing the crate")
	session.screen_ui.show_section("Inventory")
	var readout := session.screen_ui.detail.text
	check(readout.contains("%.2f kg" % same[0]) and readout.contains("%.2f m/s" % same[1])
		and readout.contains("%.2f m/s²" % same[2]) and readout.contains("%.2f kg" % same[4]),
		"Terminal shows actual chassis numbers and units")
	session.leave()
	check(session.enter() and session.screen_ui.detail.text == readout
		and chassis_values(actor.chassis) == same, "Terminal reentry and equipment activity do not reroll the chassis")
	session.leave()
	if DisplayServer.get_name() != "headless":
		actor.global_position = Vector3(-3, 0.01, 4)
		place(crate, Vector3(-3, 0.65, 2.35))
		await frames(15)
		aim(actor, crate.global_position)
		var event := InputEventAction.new()
		event.action = "drop_item"
		event.pressed = true
		ui._input(event)
		await create_timer(0.23).timeout
		placement.advance_drop()
		check(placement.is_grabbing(), "Gameplay G input routes into world grab")
		event.pressed = false
		ui._input(event)
		check(placement.is_grabbing() and crate.freeze, "Gameplay activation key-up keeps manipulation active")
		aim(actor, crate.global_position + Vector3.UP * 0.5)
		await frames(25)
		var middle := InputEventMouseButton.new()
		middle.button_index = MOUSE_BUTTON_MIDDLE
		middle.pressed = true
		ui._input(middle)
		var camera_basis := actor.camera.global_basis
		var motion := InputEventMouseMotion.new()
		motion.relative = Vector2(40, 25)
		actor._unhandled_input(motion)
		await frames(12)
		var turned := crate.global_basis
		var anchor_before_walk := placement.target_position()
		Input.action_press("move_forward")
		await frames(20)
		Input.action_release("move_forward")
		check(placement.rotating and actor.camera.global_basis == camera_basis
			and placement.target_position().distance_to(anchor_before_walk) > 0.25
			and crate.global_position.distance_to(placement.target_position()) < 0.50
			and crate.global_basis.is_equal_approx(turned), "World crate follows WASD during middle-mouse rotation")
		event.pressed = true
		ui._input(event)
		event.pressed = false
		ui._input(event)
		check(not placement.is_grabbing() and not crate.freeze and not placement.rotating,
			"Gameplay G tap restores physics and input while middle is held")

	facility.queue_free()
	await process_frame
	print("RD-006: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func aim(actor: OtisController, point: Vector3) -> void:
	actor.camera.look_at(point)
	actor.placement.distance = minf(actor.placement.maximum_distance, actor.camera.global_position.distance_to(point))

func grab(actor: OtisController, item: InteractableObject) -> void:
	aim(actor, item.global_position)
	actor.placement.press_drop(1000000)
	actor.placement.advance_drop(1200000)
	actor.placement.release_drop(1200000)

func place_gesture(placement: PrecisionPlacement) -> void:
	placement.press_drop(2000000)
	placement.release_drop(2100000)

func check_freeform(actor: OtisController, item: InteractableObject) -> void:
	var placement := actor.placement
	var anchor := placement.target_position()
	var camera_basis := actor.camera.global_basis
	var pose := item.global_transform
	var original := item.global_basis.get_rotation_quaternion()
	var turns: Array[float] = []
	for drag in [Vector2(55, 0), Vector2(0, 55), Vector2(45, 45)]:
		placement.set_rotating(true)
		placement.rotate_from_mouse(drag)
		await frames(12)
		var turn := item.global_basis.get_rotation_quaternion() * original.inverse()
		var local_axis := camera_basis.inverse() * turn.get_axis()
		check(turn.get_angle() > 0.08, "Arcball responds to drag " + str(drag))
		if drag.x != 0 and drag.y != 0:
			check(absf(local_axis.x) > 0.3 and absf(local_axis.y) > 0.3, "Diagonal drag combines pitch and yaw")
		elif drag.x == 0:
			check(absf(local_axis.x) > 0.95, "Vertical drag rotates about camera right")
		else:
			check(absf(local_axis.y) > 0.95, "Horizontal drag rotates about camera up")
			turns.append(turn.get_angle())
		placement.set_rotating(false)
		item.global_transform = pose
	var mass := item.mass
	item.mass = 10.0
	placement.set_rotating(true)
	placement.rotate_from_mouse(Vector2(55, 0))
	await frames(12)
	check(original.angle_to(item.global_basis.get_rotation_quaternion()) > turns[0] + 0.10,
		"Same drag turns a lighter load farther")
	item.mass = mass
	placement.set_rotating(false)
	placement.set_rotating(true)
	placement.rotate_from_mouse(Vector2(80, 0))
	await frames(12)
	var before_roll := item.global_basis.get_rotation_quaternion()
	placement.rotate_from_mouse(Vector2(0, 65))
	await frames(12)
	var roll := item.global_basis.get_rotation_quaternion() * before_roll.inverse()
	check(absf((camera_basis.inverse() * roll.get_axis()).z) > 0.2, "Off-center arcball stroke includes view-axis roll")
	for index in 16:
		placement.set_rotating(false)
		var saved := item.global_basis
		placement.set_rotating(true)
		check(item.global_basis == saved, "Starting a new gesture preserves orientation")
		placement.rotate_from_mouse(Vector2(55, 30))
		await frames(6)
	placement.set_rotating(false)
	var result := item.global_basis
	await frames(4)
	check(is_equal_approx(result.determinant(), 1.0) and result.is_equal_approx(item.global_basis)
		and result.is_equal_approx(result.orthonormalized()), "Repeated compound gestures preserve an orthonormal basis")
	check(item.global_position.distance_to(anchor) < 0.01 and actor.camera.global_basis == camera_basis,
		"Rotation alone leaves the placement anchor and camera stationary")

func check_obstacle(actor: OtisController, crate: InteractableObject, start: Vector3,
		direction: Vector3, boundary: float, label: String) -> void:
	actor.global_position = start
	place(crate, start + direction * 1.55 + Vector3.UP * 0.65)
	await frames(16)
	grab(actor, crate)
	check(actor.placement.is_grabbing(), "Grab near " + label)
	aim(actor, start + direction * 3.5 + Vector3.UP * 1.25)
	actor.placement.set_rotating(true)
	await frames(70)
	actor.placement.set_rotating(false)
	var blocked := crate.position.dot(direction) + 0.65
	check(blocked <= boundary + 0.006 and blocked >= boundary - 0.10 and actor.placement.valid,
		"Shared sweep stops at %s (face %.3f)" % [label, blocked])
	var contact_basis := crate.global_basis
	actor.placement.set_rotating(true)
	actor.placement.rotate_from_mouse(Vector2(115, 0))
	await frames(24)
	check(actor.placement.valid and contact_basis.get_rotation_quaternion().angle_to(
		crate.global_basis.get_rotation_quaternion()) < 0.2, "Rotation cannot penetrate " + label)
	actor.placement.set_rotating(false)
	aim(actor, start + direction * 1.6 + Vector3.UP * 1.1)
	await frames(35)
	check(crate.position.dot(direction) + 0.65 < blocked - 0.12, "Retreat clears " + label)
	var pose := crate.global_transform
	place_gesture(actor.placement)
	check(crate.global_transform == pose and not crate.freeze, "Release at safe pose near " + label)
	await frames(20)

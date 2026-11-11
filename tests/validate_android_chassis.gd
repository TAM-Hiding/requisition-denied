extends SceneTree

const DT := 1.0 / 60.0
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
	var carry := actor.carry
	var plate: PhysicalLoadSensor = facility.load_plate
	var ui := facility.get_node("InteractionUI")
	var identity := crate.get_instance_id()
	var shape: Shape3D = crate.get_node("CollisionShape3D").shape
	check(chassis_values(actor.chassis) == same, "Facility creates Otis's requested seeded chassis")
	check(is_equal_approx(actor.movement_speed, same[AndroidChassis.Attribute.WALK_MPS])
		and is_equal_approx(actor.acceleration, same[AndroidChassis.Attribute.ACCELERATION_MPS2]),
		"Walking speed and acceleration read the chassis")
	check(crate.mass == 35.0 and weight.mass == 8.0 and plate.activation_kg == 40.0 and plate.release_kg == 37.0,
		"Load masses and thresholds retain their original values")
	actor.global_position = Vector3(-2.5, 0.01, 1.15)
	actor.camera.look_at(crate.global_position)
	await frames(4)
	check(crate.query_actions().has(&"lift") and crate.query_actions().has(&"move"), "Crate exposes both Lift and Move")
	crate.mass = 55.0
	var before := crate.global_transform
	check(not carry.lift(crate).ok and carry.item == null and crate.state == InteractableObject.State.WORLD
		and not crate.freeze and crate.global_transform == before, "Over-capacity lift leaves world state intact")
	check(actor.manipulation.begin_move(crate).ok, "Over-capacity crate can still be pushed or dragged")
	actor.manipulation.stop_move()
	crate.mass = 35.0
	check(actor.equipment.pick_up(wrench).ok, "Handheld equipment can remain equipped")
	ui.open_menu(crate)
	check(ui.menu_open and ui.menu_actions.has(&"lift"), "Lift is available in the interaction menu")
	ui.perform_action(&"lift")
	check(not ui.menu_open and carry.item == crate and crate.state == InteractableObject.State.CARRIED,
		"Contextual Lift takes carry ownership. HUD: " + ui.information.text)
	if carry.item != crate:
		facility.queue_free()
		quit(1)
		return
	check(crate.get_instance_id() == identity and crate.get_node("CollisionShape3D").shape == shape
		and crate.mass == 35.0 and crate.collision_layer == 1 and crate.get_parent() == facility,
		"Carried crate keeps identity, mass, shape and its world collider")
	var fraction := 35.0 / same[AndroidChassis.Attribute.LIFT_KG]
	check(is_equal_approx(carry.speed_factor(), 1.0 - 0.25 * fraction)
		and is_equal_approx(carry.acceleration_factor(), 1.0 - 0.30 * fraction), "Carry modifiers scale with actual load fraction")
	check(not actor.manipulation.begin_move(crate).ok and not actor.placement.begin()
		and not facility.terminal_session.enter(), "Carry prevents competing world interaction modes")
	check(actor.equipment.held_item() == wrench, "Carry preserves equipped wrench")
	await frames(15)
	var release_pose := crate.global_transform
	check(carry.release().ok and crate.global_transform == release_pose and not crate.freeze
		and crate.state == InteractableObject.State.WORLD, "Release restores physics at the same pose")
	await frames(32)
	check(crate.global_position.y < release_pose.origin.y - 0.15 and carry.speed_factor() == 1.0
		and carry.acceleration_factor() == 1.0, "Crate settles and movement returns to unloaded values")
	check(actor.equipment.stow().ok and actor.equipment.equip_first().ok and actor.equipment.drop().ok,
		"Handheld equipment can be stowed, retrieved and dropped after carrying")
	place(wrench, Vector3(0, 0.1, 0))

	await check_obstacle(actor, crate, Vector3(2.5, 0.01, 4.7), Vector3.RIGHT, 6.0, "east wall")
	await check_obstacle(actor, crate, Vector3(0, 0.01, -2.6), Vector3.FORWARD, 5.04, "terminal desk")
	await check_obstacle(actor, crate, Vector3(4.65, 0.01, -1.3), Vector3.FORWARD, 4.26, "closed gate")

	actor.global_position = plate.global_position + Vector3(0, 0.01, 2.4)
	actor.rotation.y = 0.0
	place(crate, actor.global_position + Vector3(0, 0.65, -1.65))
	await frames(15)
	check(carry.lift(crate).ok, "Crate can be lifted for the pressure plate trial")
	await travel(actor, Vector3.FORWARD, 58)
	await frames(30)
	check(is_equal_approx(plate.measured_kg, actor.body_mass_kg + 35.0) and plate.is_active(),
		"Carried mass transfers through Otis once")
	check(carry.release().ok, "Release on the plate is safe")
	await frames(85)
	check(is_equal_approx(plate.measured_kg, actor.body_mass_kg),
		"Once the crate is released outside the plate only chassis mass remains")
	check(facility.barrier.state == PoweredBarrier.State.OPEN, "Effective chassis mass activates the unchanged gate")

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
		await check_walking(actor, crate)

	facility.queue_free()
	await process_frame
	print("RD-006: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func travel(actor: OtisController, direction: Vector3, count: int) -> void:
	actor.set_physics_process(false)
	for step in count:
		await physics_frame
		var request := direction * actor.movement_speed * actor.carry.speed_factor()
		actor.move_and_collide(actor.carry.constrain_velocity(request, DT) * DT)
		actor.carry.update_goal(DT)
	actor.set_physics_process(true)

func check_obstacle(actor: OtisController, crate: InteractableObject, start: Vector3,
		direction: Vector3, boundary: float, label: String) -> void:
	actor.global_position = start
	actor.rotation.y = Vector3.FORWARD.signed_angle_to(direction, Vector3.UP)
	place(crate, start + direction * 1.65 + Vector3.UP * 0.65)
	await frames(18)
	check(actor.carry.lift(crate).ok, "Lift succeeds near " + label)
	await travel(actor, direction, 85)
	var blocked_pose := crate.global_transform
	var blocked_face := blocked_pose.origin.dot(direction) + 0.65
	check(blocked_face <= boundary + 0.006 and blocked_face >= boundary - 0.09
		and actor.global_position.dot(direction) < boundary - 0.30, "Crate and Otis stop at %s (face %.3f, actor %.3f)" % [label, blocked_face, actor.global_position.dot(direction)])
	await travel(actor, direction, 15)
	check(crate.global_position.distance_to(blocked_pose.origin) < 0.015, "Blocked carry stays stable at " + label)
	await travel(actor, -direction, 28)
	check(crate.global_position.dot(direction) < blocked_pose.origin.dot(direction) - 0.20,
		"Retreat clears " + label)
	var release_pose := crate.global_transform
	check(actor.carry.release().ok and crate.global_transform == release_pose, "Release preserves clear pose near " + label)
	await frames(18)

func check_walking(actor: OtisController, crate: InteractableObject) -> void:
	actor.global_position = Vector3(-3.5, 0.01, 2.8)
	actor.rotation.y = 0.0
	place(crate, Vector3(-3.5, 0.65, 1.15))
	await frames(12)
	check(actor.carry.lift(crate).ok, "Lift succeeds for WASD trial")
	Input.action_press("move_forward")
	await frames(24)
	check(absf(actor.velocity.z + actor.movement_speed * actor.carry.speed_factor()) < 0.02,
		"WASD uses the loaded walking speed")
	Input.action_release("move_forward")
	check(actor.carry.release().ok, "Release after WASD")
	actor.global_position = Vector3(-4.9, 0.01, 3.8)
	await frames(15)
	Input.action_press("move_forward")
	await frames(24)
	check(absf(actor.velocity.z + actor.movement_speed) < 0.02, "WASD returns to chassis walking speed")
	Input.action_release("move_forward")

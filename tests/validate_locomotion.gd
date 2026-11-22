extends SceneTree
# Headless DisplayServer cannot capture a pointer. Override only that input
# gate in tests; movement, real InputMap actions, colliders and Jolt stay real.
# Graphical runs exercise the production class without this adapter.
class HeadlessDriver extends OtisLocomotion:
	var captured := true
	func input_active() -> bool:
		return actor.controls_enabled and captured

var checks := 0
var failures := 0
var world: Node3D
var actor: OtisController
var movement: OtisLocomotion

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

func release_actions() -> void:
	for action in ["move_forward", "move_back", "move_left", "move_right", "locomotion_sprint", "locomotion_jump", "locomotion_posture"]:
		Input.action_release(action)

func reset(at := Vector3(0, 0.03, 4)) -> void:
	release_actions()
	movement.cancel_input()
	actor.global_transform = Transform3D(Basis.IDENTITY, at)
	actor.velocity = Vector3.ZERO
	actor.controls_enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	movement.request_posture(OtisLocomotion.Posture.STANDING)
	await frames(8)

func jump_event() -> void:
	var event := InputEventAction.new()
	event.action = &"locomotion_jump"
	event.pressed = true
	actor._unhandled_input(event)

func unit_loads() -> void:
	for index in LocomotionLoad.SAMPLES.size():
		var modifiers := LocomotionLoad.modifiers(40 * LocomotionLoad.SAMPLES[index], 40)
		check(is_equal_approx(modifiers.jump, LocomotionLoad.JUMP[index])
			and is_equal_approx(modifiers.sprint, LocomotionLoad.SPRINT[index]), "Load sample preserves the requested jump/sprint tuning")
	var alternate := LocomotionLoad.modifiers(20, 40, [1.0, 0.9, 0.8, 0.7, 0.6], [1.0, 1.0, 1.0, 1.0, 1.0])
	check(is_equal_approx(alternate.jump, 0.8) and alternate.sprint == 1,
		"Exported load factors can tune capabilities without rewriting the controller")
	var overload := LocomotionLoad.modifiers(1000, 0)
	check(overload.jump > 0 and overload.walk > 0 and overload.sprint > 0
		and is_finite(overload.jump), "Temporary overload degrades without negative/unstable capabilities")

func sprint_checks() -> void:
	await reset()
	for action in ["locomotion_sprint", "locomotion_jump", "locomotion_posture"]:
		var events := InputMap.action_get_events(action)
		var expected := {"locomotion_sprint": KEY_SHIFT, "locomotion_jump": KEY_SPACE, "locomotion_posture": KEY_ALT}
		check(events.size() == 1 and events[0] is InputEventKey and events[0].physical_keycode == expected[action],
			"New controls have the expected named physical-key bindings")
	Input.action_press("move_forward")
	await frames(16)
	check(absf(actor.velocity.z + actor.movement_speed) < 0.1, "Ordinary forward speed remains chassis-owned")
	Input.action_press("locomotion_sprint")
	await frames(16)
	check(movement.sprinting and absf(actor.velocity.z + actor.movement_speed * 1.6) < 0.1,
		"Held Shift plus forward input enables 1.6x sprint")
	Input.action_release("locomotion_sprint")
	await frames(1)
	check(not movement.sprinting and movement.current_speed == actor.movement_speed, "Shift release immediately cancels sprint state")
	await frames(16)
	check(absf(actor.velocity.z + actor.movement_speed) < 0.1, "Modest deceleration restores walking speed")
	Input.action_press("locomotion_sprint")
	Input.action_release("move_forward")
	await frames(1)
	check(not movement.sprinting, "Releasing W cancels sprint even with Shift held")
	await frames(30)
	check(actor.velocity.length() < 0.02, "No automatic continued movement or sprint")
	await reset()
	Input.action_press("move_right")
	Input.action_press("locomotion_sprint")
	await frames(12)
	check(not movement.sprinting and actor.velocity.x > 0, "Strafing alone does not sprint")
	Input.action_press("move_forward")
	await frames(20)
	check(movement.sprinting and Vector2(actor.velocity.x, actor.velocity.z).length() <= actor.movement_speed * 1.6 + 0.01,
		"Diagonal movement is normalized rather than adding independent sprint speeds")
	await reset()

func jump_checks() -> void:
	check(actor.is_on_floor(), "Actual character physics establishes a grounded pose")
	jump_event()
	await frames(2)
	check(actor.velocity.y > 0 and not actor.is_on_floor(), "Space initiates a physical jump")
	var previous_y := actor.velocity.y
	check(not movement.request_jump() and actor.velocity.y == previous_y, "Airborne Space cannot double-jump without a ledge")
	var peak := actor.position.y
	for frame in 90:
		await frames(1)
		peak = maxf(peak, actor.position.y)
	check(peak > 0.65 and peak < 0.82, "Unloaded jump reaches approximately 0.75m under gravity")
	check(actor.is_on_floor() and absf(actor.position.y) < 0.03 and actor.velocity.y <= 0.01,
		"Landing restores actual grounded movement")

func posture_checks() -> void:
	var alt := InputEventKey.new()
	alt.physical_keycode = KEY_ALT
	alt.keycode = KEY_ALT
	alt.pressed = true
	alt.alt_pressed = true
	Input.parse_input_event(alt)
	await frames(1)
	alt = alt.duplicate()
	alt.pressed = false
	alt.alt_pressed = false
	Input.parse_input_event(alt)
	await frames(1)
	check(movement.posture == OtisLocomotion.Posture.CROUCHING, "Real Alt key events reach the posture gesture through input routing")
	movement.request_posture(OtisLocomotion.Posture.STANDING)
	movement.press_posture(0)
	movement.release_posture(100000)
	check(movement.posture == OtisLocomotion.Posture.CROUCHING
		and is_equal_approx((movement.collider.shape as CapsuleShape3D).height, movement.tuning.crouch_height),
		"Alt tap changes the actual collision capsule to crouch")
	await frames(30)
	check(actor.camera.position.y < 1.3 and actor.position.y < 0.03, "Crouch lowers camera while retaining floor contact")
	Input.action_press("move_forward")
	Input.action_press("locomotion_sprint")
	await frames(12)
	check(not movement.sprinting and movement.current_speed <= actor.movement_speed * 0.61,
		"Crouch speed is 60 percent and cannot sprint")
	await reset(Vector3(-2.1, 0.03, 3.3))
	check(movement.request_posture(OtisLocomotion.Posture.CROUCHING), "Crouch is available with overhead clearance")
	actor.position = Vector3(-2.1, 0.02, 1.5)
	await frames(8)
	check(not movement.request_posture(OtisLocomotion.Posture.STANDING)
		and movement.posture == OtisLocomotion.Posture.CROUCHING, "Low roof rejects standing without changing posture")
	check(not movement.request_jump(), "Crouched jump cannot force standing through a roof")
	await reset()
	movement.press_posture(1000)
	movement.advance_posture(400999)
	check(movement.posture == OtisLocomotion.Posture.STANDING, "Alt hold does not trigger before its threshold")
	movement.advance_posture(401000)
	check(movement.posture == OtisLocomotion.Posture.PRONE, "Sustained Alt enters belly crawl at0.4seconds")
	movement.release_posture(600000)
	check(movement.posture == OtisLocomotion.Posture.PRONE, "Long Alt release cannot also toggle crouch")
	check(movement.collider.shape is BoxShape3D
		and movement.collider.shape.size.z > 2 and movement.collider.shape.size.y < 0.9,
		"Prone uses a genuinely horizontal footprint including the approved satchel")
	await frames(30)
	check(actor.camera.position.y < 0.4 and not movement.request_jump(), "Prone lowers the eye and disables jumping")
	Input.action_press("move_forward")
	Input.action_press("locomotion_sprint")
	var start := actor.position
	await frames(20)
	check(not movement.sprinting and actor.position.distance_to(start) > 0.15
		and movement.current_speed <= actor.movement_speed * 0.31, "Belly crawl moves physically at30percent with no sprint")
	release_actions()
	actor.position = Vector3(2.1, 0.02, 1.5)
	actor.velocity = Vector3.ZERO
	await frames(8)
	movement.press_posture(0)
	movement.release_posture(100000)
	check(movement.posture == OtisLocomotion.Posture.PRONE,
		"A crawl-height roof safely rejects rising to crouch")
	await reset(Vector3(0, 0.03, 4))
	movement.request_posture(OtisLocomotion.Posture.PRONE)
	movement.press_posture(0)
	movement.release_posture(100000)
	check(movement.posture == OtisLocomotion.Posture.CROUCHING, "Alt tap from crawling returns to crouch")
	movement.press_posture(0)
	movement.release_posture(100000)
	check(movement.posture == OtisLocomotion.Posture.STANDING, "Second tap stands with clearance")
	await reset()
	movement.request_posture(OtisLocomotion.Posture.CROUCHING)
	jump_event()
	await frames(2)
	check(movement.posture == OtisLocomotion.Posture.STANDING and actor.velocity.y > 0,
		"An open-field crouch jump first acquires clear standing posture")
	await frames(70)
	await reset()
	# Expanded footprint and yaw need real geometry checks.
	var obstacle := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = Vector3(0.2, 2, 4)
	obstacle.add_child(shape)
	world.add_child(obstacle)
	obstacle.position = actor.position + Vector3(0.62, 1, -0.2)
	await frames(2)
	check(movement.request_posture(OtisLocomotion.Posture.PRONE), "Prone fits parallel to a nearby wall")
	var initial := actor.rotation.y
	movement.try_turn(PI / 2)
	check(absf(actor.rotation.y - initial) < PI / 2 - 0.1
		and movement.profile_clear(OtisLocomotion.Posture.PRONE, actor.global_transform),
		"A fast mouse turn cannot rotate the long prone footprint through a wall")
	obstacle.queue_free()
	await frames(2)
	await reset()

func climb_checks() -> void:
	await reset(Vector3(-3, 0.03, -1.25))
	var candidate := movement.ledge_candidate()
	print("LEDGE CANDIDATE ", candidate)
	check(not candidate.is_empty() and movement.try_climb(), "Space-range detection finds a supported ledge and clear path")
	check(movement.climbing and not movement.sprinting, "Ledge traversal owns movement and disables sprint")
	var rig := actor.get_node("ICF01_Wayfarer") as WayfarerRig
	var elapsed := 0
	var previous := 0.0
	var progressed := true
	var closest_hand := INF
	var expected_time := movement.tuning.climb_time(movement.climb_variant)
	while movement.climbing and elapsed < 90:
		await frames(1)
		elapsed += 1
		if movement.climbing:
			progressed = progressed and movement.climb_progress > previous and movement.climb_progress <= 1.0
			previous = movement.climb_progress
			if previous >= 0.20 and previous <= 0.49:
				for limb in rig.limbs:
					var fingertip: Vector3 = limb.hand.to_global(Vector3(0, -0.09, -0.02))
					var edge: Vector3 = movement.climb_edge + actor.global_basis.x * limb.side * 0.20
					closest_hand = minf(closest_hand, fingertip.distance_to(edge))
	check(closest_hand < 0.23, "A short ledge climb visibly braces a hand near the ledge edge")
	check(progressed and previous > 0.90, "Climb presentation advances along the validated physical path")
	check(absf(float(elapsed) / Engine.physics_ticks_per_second - expected_time) < 0.05,
		"Collision-checked traversal follows its configured variant timing within physics tick rounding")
	check(movement.climb_variant == -1 and movement.climb_progress == 0,
		"Completed traversal clears its animation state")
	await frames(45)
	check(rig.core.rotation.length() < 0.01 and absf(rig.core.position.z) < 0.01,
		"Completed traversal returns the torso pose to rest")
	print("CLIMB END ",actor.position," ",movement.last_feedback)
	check(not movement.climbing and actor.position.y > 0.63 and actor.position.z < -1.9,
		"Two collision-checked movement stages put Otis onto the low ledge")
	check(actor.is_on_floor(), "Completed climb settles onto the supporting surface")
	await reset(Vector3(3, 0.03, -1.25))
	check(movement.ledge_candidate().is_empty(), "A high ledge is unreachable while standing")
	jump_event()
	await frames(18)
	check(actor.position.y > 0.6 and not actor.is_on_floor(), "A real jump raises Otis toward a higher ledge")
	check(movement.request_jump() and movement.climbing, "Airborne Space grabs a reachable ledge")
	await frames(100)
	check(not movement.climbing and actor.position.y > 1.77 and actor.is_on_floor(), "Jump-to-ledge completes safely and lands")
	await reset(Vector3(-3, 0.03, -1.25))
	var blocker := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = Vector3(2.5, 0.2, 2)
	blocker.add_child(shape)
	world.add_child(blocker)
	blocker.position = Vector3(-3, 1.9, -2.6)
	await frames(2)
	check(movement.ledge_candidate().is_empty(), "Destination ceiling prevents climbing")
	blocker.queue_free()
	await frames(2)
	check(movement.try_climb(), "Clear ledge becomes available after obstruction removal")
	await frames(5)
	# Introduce a solid into the remaining vertical path while climbing.
	var trap := StaticBody3D.new()
	var trap_shape := CollisionShape3D.new()
	trap_shape.shape = BoxShape3D.new()
	trap_shape.shape.size = Vector3(1, 0.08, 1)
	trap.add_child(trap_shape)
	world.add_child(trap)
	trap.position = actor.position + Vector3(0, 1.85, 0)
	await frames(25)
	check(not movement.climbing and movement.last_feedback.contains("obstructed"), "A new obstruction stops traversal at the last valid pose")
	check(movement.climb_variant == -1 and movement.climb_progress == 0 and rig.core.rotation.length() < 0.02,
		"Interrupted traversal clears its animation state and recovers the torso pose")
	trap.queue_free()
	await frames(50)
	await reset(Vector3(-3, 0.03, -1.25))
	check(movement.try_climb(), "Climb can start again after interruption")
	await frames(3)
	(world.get_node("LowLedge") as Node3D).position.x += 0.1
	await frames(2)
	check(not movement.climbing and movement.last_feedback.contains("Support moved"), "Moving support invalidates an active climb")
	(world.get_node("LowLedge") as Node3D).position.x -= 0.1
	await reset()

func climb_variant_checks() -> void:
	const Poses = preload("res://scripts/character/wayfarer_climb_poses.gd")
	var early: Array[Vector4] = []
	var sequence: Array[int] = []
	var variant_count := OtisLocomotion.ClimbVariant.size()
	movement.climb_random.seed = 13
	for index in range(60):
		sequence.append(movement._next_climb_variant())
		if index >= 2 and sequence[index] == sequence[index - 1] and sequence[index] == sequence[index - 2]:
			check(false, "A climb variant cannot occur three times in a row")
			break
	check(sequence.size() == 60, "Seeded climb selection avoids three consecutive repeats")
	for variant in variant_count:
		check(sequence.has(variant), "The seeded selector can choose each climb variant")
		early.append(Poses.sample(variant, 0.22)[2])
		check(Poses.sample(variant, 0) == Poses.REST and Poses.sample(variant, 1) == Poses.REST,
			"Each animation starts and ends in the ordinary standing pose")
		var duration := movement.tuning.climb_time(variant)
		check(duration >= 0.5 and duration <= 0.85, "Each climb variant stays within the requested timing bounds")
	check(early[0].x - early[0].y > 0.45 and absf(early[1].x - early[1].y) < 0.15
		and early[2].y - early[2].x > 0.65,
		"Scramble catches left, maintenance hoist uses both hands, and awkward recovery catches right")
	var tuck: Vector4 = Poses.sample(OtisLocomotion.ClimbVariant.SCRAMBLE, 0.50)[3]
	var step: Vector4 = Poses.sample(OtisLocomotion.ClimbVariant.MAINTENANCE_HOIST, 0.66)[3]
	var twist: Vector3 = Poses.sample(OtisLocomotion.ClimbVariant.AWKWARD_RECOVERY, 0.43)[0]
	check(tuck.z < -1.6 and tuck.w < -1.6 and step.x - step.y > 0.9 and twist.y > 0.35,
		"Scramble tucks both knees, maintenance hoist steps one leg first, and awkward recovery twists the torso")

func rig_checks() -> void:
	var rig := actor.get_node("ICF01_Wayfarer") as WayfarerRig
	rig.animate(1, false, false)
	var neutral: float = rig.limbs[0].thigh.rotation.x
	actor.velocity = Vector3(0, 0, -4)
	rig.gait_phase = 0
	rig.animate(0.1, false, false)
	var forward: float = rig.limbs[0].thigh.rotation.x
	actor.velocity = Vector3(0, 0, 4)
	rig.gait_phase = 0
	rig.limbs[0].thigh.rotation.x = neutral
	rig.animate(0.1, false, false)
	check(forward * float(rig.limbs[0].thigh.rotation.x) < 0, "Backward gait reverses the forward stride")
	actor.velocity = Vector3(4, 0, 0)
	rig.animate(0.1, false, false)
	check(absf(rig.limbs[0].thigh.rotation.z) > 0.02, "Strafing articulates a lateral stride")
	actor.velocity = Vector3.ZERO
	movement.request_posture(OtisLocomotion.Posture.CROUCHING)
	rig.animate(1, false, false)
	check(rig.core.position.y < 0.5 and rig.limbs[0].shin.rotation.x < -2,
		"Mechanical crouch folds the approved existing hip/knee joints")
	prone_rig_checks(rig)
	await reset()

func prone_rig_checks(rig: WayfarerRig) -> void:
	var left: Dictionary = rig.limbs[0]
	var right: Dictionary = rig.limbs[1]
	var lowest_sole := INF
	movement.request_posture(OtisLocomotion.Posture.PRONE)
	for frame in 32:
		rig.animate(1.0 / 60.0, false, false)
		for limb in rig.limbs:
			lowest_sole = minf(lowest_sole, mesh_clearance(limb.foot))
	check(absf(rig.rotation.x + PI / 2) < 0.12 and left.forearm.rotation.x > 1.7
		and left.hand.global_position.y < actor.global_position.y + 0.14,
		"Unequipped prone rests flat on bent forearms")
	check(lowest_sole > -0.02, "Crouch to prone keeps the visual soles close to or clear of the floor")
	actor.velocity.z = -actor.movement_speed * movement.tuning.crawl_multiplier
	rig.gait_phase = 0.0
	var opposite_pulls := true
	for frame in 42:
		rig.animate(1.0 / 60.0, false, false)
		opposite_pulls = opposite_pulls and absf(left.shoulder.rotation.x + right.shoulder.rotation.x - 1.44) < 0.05
	check(opposite_pulls and absf(left.shoulder.rotation.x - right.shoulder.rotation.x) > 0.04,
		"Unequipped crawl alternates short reaches between both forearms")

	var low_shoulders := Vector2(INF, INF)
	var high_shoulders := Vector2(-INF, -INF)
	var right_clearance := INF
	for frame in 96:
		rig.animate(1.0 / 60.0, true, false)
		if frame > 30:
			var shoulders := Vector2(left.shoulder.rotation.x, right.shoulder.rotation.x)
			low_shoulders = low_shoulders.min(shoulders)
			high_shoulders = high_shoulders.max(shoulders)
			right_clearance = minf(right_clearance, mesh_clearance(right.shoulder))
	var travel := high_shoulders - low_shoulders
	check(travel.y > 0.05 and travel.y < 0.50 * travel.x and right_clearance > 0.02,
		"Equipped crawl keeps the right arm clear and active with a reduced stroke")
	var idle_wrist := actor.to_local(right.hand.global_position)
	var aim_clearance := INF
	for frame in 32:
		actor.equipment.presentation.aim_blend = minf(float(frame) / 8.0, 1.0)
		rig.animate(1.0 / 60.0, true, false)
		aim_clearance = minf(aim_clearance, mesh_clearance(right.shoulder))
	check(right.forearm.rotation.x < 0.45 and actor.to_local(right.hand.global_position).z < idle_wrist.z - 0.30
		and aim_clearance > -0.025, "Prone aim extends the right arm without a severe floor intersection")
	for frame in 32:
		actor.equipment.presentation.aim_blend = maxf(0.0, 1.0 - float(frame) / 8.0)
		rig.animate(1.0 / 60.0, true, false)
	check(right.forearm.rotation.x > 1.7 and actor.to_local(right.hand.global_position).distance_to(idle_wrist) < 0.08,
		"Prone aim release returns the arm to its compact crawl pose")

	actor.velocity = Vector3.ZERO
	movement.request_posture(OtisLocomotion.Posture.CROUCHING)
	lowest_sole = INF
	for frame in 32:
		rig.animate(1.0 / 60.0, false, false)
		for limb in rig.limbs:
			lowest_sole = minf(lowest_sole, mesh_clearance(limb.foot))
	check(absf(rig.rotation.x) < 0.01 and left.shin.rotation.x < -2 and lowest_sole > -0.025,
		"Prone to crouch recovers the original pose without severe sole penetration")

func mesh_clearance(joint: Node3D) -> float:
	var minimum := INF
	for mesh: MeshInstance3D in joint.find_children("*", "MeshInstance3D", true, false):
		var bounds := mesh.mesh.get_aabb()
		for corner in range(8):
			minimum = minf(minimum, mesh.to_global(bounds.get_endpoint(corner)).y)
	return minimum - actor.global_position.y

func payload(id: String, mass_kg: float) -> InteractableObject:
	var item := InteractableObject.new()
	item.definition = ObjectDefinition.new()
	item.definition.object_id = StringName(id)
	item.definition.display_name = id
	item.definition.mobility = ObjectDefinition.Mobility.CARRYABLE
	item.definition.mass_kg = mass_kg
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	shape.shape = BoxShape3D.new()
	shape.shape.size = Vector3.ONE * 0.06
	item.add_child(shape)
	world.add_child(item)
	item.position = Vector3(4, 0.2, 4)
	return item

func carried_load_checks() -> void:
	await reset()
	var stored := payload("RD13-test-stored", 25)
	var held := payload("RD13-test-equipped", 15)
	check(actor.equipment.store_world(stored).ok and actor.equipment.pick_up(held).ok,
		"Real container and equipment transfers establish a full carried load")
	await frames(3)
	var loads := actor.carrying_loads()
	check(loads.inventory == 25 and loads.equipped == 15 and loads.external == 0 and loads.total == 40,
		"Load accounting includes stored and equipped masses once each")
	check(is_equal_approx(movement.load_modifiers.ratio, 1), "Carried load normalizes against the existing lift capacity")
	Input.action_press("move_forward")
	Input.action_press("locomotion_sprint")
	await frames(20)
	check(movement.sprinting and is_equal_approx(movement.current_speed, actor.movement_speed * 1.6 * 0.55),
		"Full carried load applies the55percent sprint modifier in real movement")
	release_actions()
	await frames(25)
	var floor_y := actor.position.y
	jump_event()
	var peak := floor_y
	for frame in 90:
		await frames(1)
		peak = maxf(peak, actor.position.y)
	check(peak - floor_y > 0.10 and peak - floor_y < 0.19 and actor.is_on_floor(),
		"Real loaded jump arc is approximately20percent of unloaded height and lands")
	check(actor.equipment.begin_placement() and actor.carrying_loads().total == 40
		and actor.carrying_loads().external == 0, "Owned precision equipment is not counted a second time")
	actor.equipment.cancel_placement()
	var dragged := payload("RD13-test-external", 20)
	# Unit-level accounting/state checks borrow the real placement contract
	# synchronously; no incomplete fixture is advanced through its solver.
	actor.placement._grab = dragged
	actor.placement._supported = true
	check(actor.carrying_loads().total == 40, "Supported dragging adds no carried-load penalty")
	check(not movement.request_jump(), "Supported heavy dragging restricts jumping")
	actor.placement._supported = false
	check(actor.carrying_loads().external == 20 and actor.carrying_loads().total == 60,
		"A distinct suspended external body contributes once")
	actor.placement._grab = null
	actor.placement._supported = false
	dragged.queue_free()
	check(actor.equipment.drop().ok and actor.equipment.retrieve(stored).ok,
		"Existing dropping and storage retrieval still release the loaded fixtures")
	held.queue_free()
	stored.queue_free()
	await frames(3)
	check(actor.carrying_loads().total == 0, "Released fixtures leave no stale movement load")

func configure_actor() -> void:
	actor = world.get_node("Otis")
	actor.chassis = AndroidChassis.new()
	if DisplayServer.get_name() == "headless":
		var original := actor.locomotion
		actor.remove_child(original)
		original.free()
		actor.locomotion = HeadlessDriver.new()
		actor.add_child(actor.locomotion)
	movement = actor.locomotion

func interaction_checks() -> void:
	world = preload("res://scenes/facility.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	configure_actor()
	await reset(Vector3(0, 0.03, 3))
	var ui = world.get_node("InteractionUI")
	var tool := world.get("bolt_tool") as FasteningTool
	check(actor.equipment.pick_up(tool).ok, "Uni-Bolt equips through the unchanged gameplay system")
	Input.action_press("move_forward")
	await frames(14)
	check(actor.velocity.length() > 1 and actor.equipped_tool() == tool, "Movement remains available with an equipped tool")
	movement.press_posture()
	movement._jump_pending = true
	check(ui.inventory.show_inventory(ui.hud), "Actual inventory opens during locomotion")
	await frames(3)
	check(actor.velocity.x == 0 and actor.velocity.z == 0 and not movement.sprinting
		and movement._alt_pressed_at < 0 and not movement._jump_pending,
		"Inventory stops movement and discards pending posture/jump gestures")
	release_actions()
	ui.inventory.hide_inventory()
	await frames(3)
	check(actor.controls_enabled and movement.posture == OtisLocomotion.Posture.STANDING
		and actor.equipped_tool() == tool, "Inventory close restores controls without stale posture or lost equipment")
	Input.action_press("move_right")
	await frames(12)
	check(actor.velocity.x > 1, "Movement resumes after inventory closes")
	release_actions()
	await frames(20)
	actor.set_tool_aiming(true)
	Input.action_press("move_forward")
	Input.action_press("locomotion_sprint")
	await frames(2)
	check(not movement.sprinting and actor.tool_aiming, "ADS retains aiming and blocks incompatible sprint")
	actor.set_tool_aiming(false)
	release_actions()
	# Terminal interaction uses its real ray/range validation and cleanup.
	actor.global_position = Vector3(0, 0.03, -3.3)
	actor.velocity = Vector3.ZERO
	actor.rotation = Vector3.ZERO
	actor.camera.rotation = Vector3.ZERO
	await frames(10)
	check(world.terminal_session.enter(), "Physical terminal remains accessible")
	await frames(4)
	check(not actor.controls_enabled and not movement.sprinting and actor.velocity.x == 0 and actor.velocity.z == 0,
		"Terminal ownership suspends locomotion")
	world.terminal_session.leave()
	await frames(4)
	check(actor.controls_enabled and actor.camera.is_current(), "Terminal close restores the movement camera")
	# Existing movable crate is a valid stationary ledge too. Opening the
	# real inventory must cancel the active traversal without teleporting.
	await reset(Vector3(-2.5, 0.03, 1.0))
	check(movement.try_climb(), "A stationary Facility crate provides a supported ledge")
	var climb_position := actor.position
	check(ui.inventory.show_inventory(ui.hud), "Inventory can interrupt traversal")
	await frames(2)
	check(not movement.climbing and actor.position.distance_to(climb_position) < 0.1,
		"Inventory interruption clears the climb at its last collision-safe position")
	ui.inventory.hide_inventory()
	await reset(Vector3(0, 0.03, 3))
	movement.request_posture(OtisLocomotion.Posture.PRONE)
	await frames(20)
	check(ui.inventory.show_inventory(ui.hud), "Inventory opens while prone")
	var preview_core := ui.inventory.preview.pivot.get_child(0) as Node3D
	check(preview_core.position.is_equal_approx(Vector3(0, 0.94, 0)) and preview_core.rotation.is_zero_approx(),
		"Inventory uses the neutral equipment mannequin instead of a half-applied crawl pose")
	var live_rig := actor.get_node("ICF01_Wayfarer") as WayfarerRig
	var preview_head := preview_core.get_node(live_rig.core.get_path_to(live_rig.head)) as Node3D
	check(absf(preview_head.rotation.x - clampf(actor.camera.rotation.x, -0.32, 0.38)) < 0.001,
		"Prone inventory normalizes head presentation as well as its body pose")
	ui.inventory.hide_inventory()
	check(movement.posture == OtisLocomotion.Posture.PRONE and actor.equipped_tool() == tool,
		"Closing the mannequin preserves live posture and original equipment")
	await reset(Vector3(0, 0.03, 3))
	# Adapter only substitutes pointer capture in the headless environment.
	movement.press_posture()
	if movement is HeadlessDriver:
		movement.captured = false
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await frames(2)
	check(movement._alt_pressed_at < 0 and not movement.sprinting, "Cursor release cancels movement gestures")
	if movement is HeadlessDriver:
		movement.captured = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await frames(2)
	check(movement.posture == OtisLocomotion.Posture.STANDING, "Recapture never executes a stale Alt gesture")
	world.queue_free()
	await frames(3)

func run() -> void:
	unit_loads()
	world = preload("res://scenes/locomotion_validation.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	configure_actor()
	await sprint_checks()
	await jump_checks()
	await posture_checks()
	await climb_checks()
	climb_variant_checks()
	await rig_checks()
	await carried_load_checks()
	release_actions()
	world.queue_free()
	await process_frame
	await interaction_checks()
	print("RD-013 locomotion: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

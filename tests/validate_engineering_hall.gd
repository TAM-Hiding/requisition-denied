extends SceneTree

## Run the shipped Facility with its Jolt geometry and InputMap. Headless has
## no pointer capture, so only the input-activation check needs a substitute.
class HeadlessLocomotion extends OtisLocomotion:
	func input_active() -> bool:
		return actor.controls_enabled

const HALL_ORIGIN := Vector3(0, 0, 6.2)
const HALL_HALF_WIDTH := 9.144
const HALL_DEPTH := 24.384
const DECK_HEIGHT := 3.35
const STAIR_X := 7.15

var checks := 0
var failures := 0
var facility: Node3D
var hall: Node3D
var otis: OtisController

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func frames(count: int) -> void:
	for frame in count:
		await physics_frame

func reset_actor(at: Vector3, yaw := 0.0) -> void:
	otis.locomotion.cancel_input()
	otis.global_transform = Transform3D(Basis(Vector3.UP, yaw), at)
	otis.velocity = Vector3.ZERO
	otis.camera.rotation = Vector3.ZERO
	otis.locomotion.request_posture(OtisLocomotion.Posture.STANDING)
	await frames(10)

func walk_until(action: StringName, reached: Callable, limit: int) -> bool:
	Input.action_press(action)
	for frame in limit:
		if reached.call():
			break
		await physics_frame
	Input.action_release(action)
	return reached.call()

func tap_key(code: Key) -> void:
	for pressed in [true, false]:
		var event := InputEventKey.new()
		event.physical_keycode = code
		event.pressed = pressed
		Input.parse_input_event(event)
	Input.flush_buffered_events()

func solid_ray(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, otis.collision_mask, [otis.get_rid()])
	return facility.get_world_3d().direct_space_state.intersect_ray(query)

func hall_point(x: float, y: float, z: float) -> Vector3:
	return hall.to_global(Vector3(x, y, z))

func shell_checks() -> void:
	check(hall.global_position.is_equal_approx(HALL_ORIGIN), "Hall adjoins the chamber's south boundary")
	for group in ["Shell", "Steelwork", "Mezzanine", "Lighting", "Markings"]:
		var node := hall.get_node_or_null(group)
		check(node != null and node.get_child_count() > 0, "Hall provides the authored %s group" % group)
	var floor := solid_ray(hall_point(0, 2, 8), hall_point(0, -1, 8))
	var roof := solid_ray(hall_point(0, 9.5, 8), hall_point(0, 12.5, 8))
	check(not floor.is_empty() and absf(floor.position.y) < 0.015, "Hall slab meets chamber floor elevation")
	check(not roof.is_empty() and absf(roof.position.y - 11.35) < 0.05,
		"Roof has a collidable underside at the design height")
	for side in [-1.0, 1.0]:
		var wall := solid_ray(hall_point(0, 1.5, 8), hall_point(side * (HALL_HALF_WIDTH + 1), 1.5, 8))
		check(not wall.is_empty() and absf(wall.position.x - side * HALL_HALF_WIDTH) < 0.05,
			"Hall wall is collidable at the planned clear width")
	var end := solid_ray(hall_point(0, 1.5, 22), hall_point(0, 1.5, HALL_DEPTH + 1))
	check(not end.is_empty() and absf(hall.to_local(end.position).z - HALL_DEPTH) < 0.05,
		"Hall's far end closes the full-depth footprint")

func doorway_checks() -> void:
	for x in [-0.86, 0.0, 0.86]:
		check(solid_ray(Vector3(x, 2.41, 5.7), Vector3(x, 2.41, 6.6)).is_empty(),
			"Door aperture is open at x %.2f near the clear head height" % x)
	for x in [-0.96, 0.96]:
		check(not solid_ray(Vector3(x, 1.4, 5.7), Vector3(x, 1.4, 6.6)).is_empty(),
			"Door jamb blocks travel at x %.2f" % x)
	check(not solid_ray(Vector3(0, 2.49, 5.7), Vector3(0, 2.49, 6.6)).is_empty(),
		"Doorway retains its physical header")
	for z in [5.95, 6.18, 6.2, 6.25, 6.45]:
		var floor := solid_ray(Vector3(0, 0.25, z), Vector3(0, -0.20, z))
		check(not floor.is_empty() and absf(floor.position.y) < 0.015, "Solid level threshold at z %.2f" % z)

	await reset_actor(Vector3(0, 0.03, 4.75), PI)
	var crossed_into_hall := await walk_until(&"move_forward", func() -> bool: return otis.position.z > 8.2, 100)
	check(crossed_into_hall and otis.is_on_floor() and absf(otis.position.y) < 0.04,
		"Normal forward walking crosses the chamber threshold into the hall")
	var crossed_back := await walk_until(&"move_back", func() -> bool: return otis.position.z < 5.0, 105)
	check(crossed_back and otis.is_on_floor() and absf(otis.position.y) < 0.04,
		"Normal walking returns through the same threshold")

func mezzanine_checks() -> void:
	await reset_actor(hall_point(STAIR_X, 0.03, 11.6), PI)
	var reached_deck := await walk_until(&"move_forward",
		func() -> bool: return otis.position.z > hall_point(0, 0, 20.4).z, 210)
	check(reached_deck and otis.is_on_floor() and absf(otis.position.y - DECK_HEIGHT) < 0.07,
		"Stair ascends to its connected deck using ordinary movement")
	var reached_floor := await walk_until(&"move_back",
		func() -> bool: return otis.position.z < hall_point(0, 0, 11.6).z, 210)
	check(reached_floor and otis.is_on_floor() and absf(otis.position.y) < 0.07,
		"Descending the same stair rejoins the hall floor")

	var mid_stair := solid_ray(hall_point(STAIR_X, 3.8, 15.8), hall_point(STAIR_X, 0.1, 15.8))
	check(not mid_stair.is_empty() and mid_stair.position.y > 1.55 and mid_stair.position.y < 1.85,
		"A smooth collision surface supports the center of the stair flight")
	for side in [-1.0, 1.0]:
		check(not solid_ray(hall_point(STAIR_X, 2.25, 15.8), hall_point(STAIR_X + 1.1 * side, 2.25, 15.8)).is_empty(),
			"Both stair flight guards have physical collision")

	await reset_actor(hall_point(0, DECK_HEIGHT + 0.03, 20.4))
	check(otis.is_on_floor() and absf(otis.position.y - DECK_HEIGHT) < 0.04, "The raised deck supports Otis")
	var rail := otis.test_move(otis.global_transform, Vector3(0, 0, -3))
	check(rail, "Deck edge guard collides with the standing character")
	var escaped := await walk_until(&"move_forward",
		func() -> bool: return otis.position.z < hall_point(0, 0, 18.9).z, 60)
	check(not escaped and otis.is_on_floor() and absf(otis.position.y - DECK_HEIGHT) < 0.04,
		"Walking into the mezzanine guard keeps Otis on the deck")

	await reset_actor(hall_point(0, DECK_HEIGHT + 0.03, 20.7))
	check(otis.locomotion.request_posture(OtisLocomotion.Posture.PRONE), "Deck provides prone clearance")
	check(otis.test_move(otis.global_transform, Vector3(0, 0, -2)),
		"Deck guard blocks a crawl across the exposed edge")

func movement_and_camera_checks() -> void:
	await reset_actor(hall_point(0, 0.03, 13))
	var view := otis.view_camera
	check(otis.camera.is_current(), "Entering the hall preserves first-person view")
	tap_key(KEY_C)
	await frames(12)
	check(view.is_current() and view.third_person and view.global_position.distance_to(view.posture_focus()) > 2.65,
		"The hall's open floor allows the existing shoulder camera its intended reach")
	tap_key(KEY_K)
	await frames(4)
	var angle := view.orbit_angle
	Input.action_press(&"camera_orbit_left")
	await frames(14)
	Input.action_release(&"camera_orbit_left")
	check(view.is_current() and view.orbiting and not is_equal_approx(view.orbit_angle, angle),
		"K orbit and held Q pan work in the hall")

	var start := otis.position
	Input.action_press(&"move_forward")
	Input.action_press(&"locomotion_sprint")
	await frames(16)
	check(otis.locomotion.sprinting and otis.position.z < start.z - 0.45, "Held sprint moves across the hall in orbit")
	Input.action_release(&"move_forward")
	Input.action_release(&"locomotion_sprint")
	await frames(8)
	tap_key(KEY_SPACE)
	await frames(5)
	check(otis.velocity.y > 0 and otis.position.y > 0.1, "Jumping works on the hall slab in orbit")
	await frames(60)

	check(otis.locomotion.request_posture(OtisLocomotion.Posture.CROUCHING), "Hall grants crouch clearance")
	check(otis.locomotion.request_posture(OtisLocomotion.Posture.PRONE), "Hall grants prone clearance")
	start = otis.position
	Input.action_press(&"move_forward")
	await frames(32)
	Input.action_release(&"move_forward")
	check(otis.position.z < start.z - 0.30 and otis.is_on_floor() and view.is_current(),
		"Prone movement works across the hall slab in orbit")
	tap_key(KEY_K)
	check(view.third_person and view.is_current() and not view.orbiting, "K returns to the selected shoulder view")
	tap_key(KEY_C)
	check(otis.camera.is_current() and otis.locomotion.posture == OtisLocomotion.Posture.PRONE,
		"C returns to the low first-person view without changing posture")

func footing_check() -> void:
	await reset_actor(hall_point(-7.04, 0.03, 10.5), PI / 2)
	var ledge := otis.locomotion.ledge_candidate()
	check(not ledge.is_empty() and absf(ledge.rise - 0.68) < 0.05,
		"The west architectural footing offers a grounded, climbable ledge")
	tap_key(KEY_SPACE)
	await frames(3)
	check(otis.locomotion.climbing, "Space starts ordinary ledge traversal on the hall footing")
	await frames(64)
	check(not otis.locomotion.climbing and otis.is_on_floor() and otis.position.x < -7.8
		and absf(otis.position.y - 0.68) < 0.05, "Otis completes the climb and stands on solid footing")

func run() -> void:
	facility = preload("res://scenes/facility.tscn").instantiate()
	facility.set("chassis_seed", 14)
	root.add_child(facility)
	current_scene = facility
	otis = facility.get_node("Otis")
	hall = facility.get_node_or_null("EngineeringTestHall")
	check(hall != null, "Engineering Test Hall loads in the shipped Facility")
	if hall != null:
		if DisplayServer.get_name() == "headless":
			otis.remove_child(otis.locomotion)
			otis.locomotion.free()
			otis.locomotion = HeadlessLocomotion.new()
			otis.add_child(otis.locomotion)
		else:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		await frames(8)
		shell_checks()
		await doorway_checks()
		await mezzanine_checks()
		await movement_and_camera_checks()
		await footing_check()
	facility.queue_free()
	await process_frame
	print("RD-014A engineering hall: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

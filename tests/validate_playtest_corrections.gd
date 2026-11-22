extends SceneTree

# Use real Jolt shapes and InputMap; headless has no captured cursor.
class HeadlessLocomotion extends OtisLocomotion:
	func input_active() -> bool:
		return actor.controls_enabled

var checks := 0
var failures := 0
var world: Node3D
var actor: OtisController
var supply: ScrapSupply
var fastening: FasteningSystem

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

func run() -> void:
	world = preload("res://scenes/locomotion_validation.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	bind_actor()
	fastening = FasteningSystem.new()
	world.add_child(fastening)
	fastening.set_physics_process(false)
	supply = ScrapSupply.new()
	supply.delivery = Vector3(1.4, 0.20, 3.0)
	world.add_child(supply)
	await contact_checks()
	await camera_checks()
	world.queue_free()
	await process_frame
	await facility_checks()
	print("RD-013 playtest corrections: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func bind_actor() -> void:
	actor = world.get_node("Otis")
	if DisplayServer.get_name() == "headless":
		actor.remove_child(actor.locomotion)
		actor.locomotion.free()
		actor.locomotion = HeadlessLocomotion.new()
		actor.add_child(actor.locomotion)
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func reset_actor(at: Vector3) -> void:
	actor.global_transform = Transform3D(Basis.IDENTITY, at)
	actor.velocity = Vector3.ZERO
	actor.camera.rotation = Vector3.ZERO
	await frames(8)

func item(at: Vector3, kilograms: float, mode := ObjectDefinition.Mobility.CARRYABLE) -> InteractableObject:
	var body := InteractableObject.new()
	body.definition = ObjectDefinition.new()
	body.definition.mass_kg = kilograms
	body.definition.mobility = mode
	body.definition.display_name = "Contact test block"
	body.position = at
	var collider := CollisionShape3D.new()
	collider.name = "CollisionShape3D"
	collider.shape = BoxShape3D.new()
	collider.shape.size = Vector3(0.12, 0.08, 0.25)
	body.add_child(collider)
	world.add_child(body)
	return body

func push_into(body: InteractableObject, ticks := 24) -> float:
	var at := body.global_position
	await reset_actor(Vector3(at.x, 0.03, at.z + 0.43))
	Input.action_press(&"move_forward")
	await frames(ticks)
	Input.action_release(&"move_forward")
	await frames(1)
	return at.z - body.global_position.z

func contact_checks() -> void:
	var light := item(Vector3(0, 0.042, 3), 1.1)
	await frames(10)
	light.sleeping = true
	var light_id := light.get_instance_id()
	var light_distance := await push_into(light)
	check(light_distance > 0.22 and not light.freeze, "Walking nudges a sleeping wrench-sized rigid body: %.3f m" % light_distance)
	check(light.get_instance_id() == light_id and light.get_parent() == world,
		"Contact keeps the same world object")
	check(actor.velocity.length() < actor.movement_speed + 0.1 and actor.is_on_floor(),
		"Contact preserves stable grounded movement")
	var heavy := item(Vector3(-1.2, 0.042, 3), actor.body_mass_kg * 1.5)
	check(await push_into(heavy) < light_distance * 0.6, "Heavy stock resists the same sustained contact")
	var machine := item(Vector3(-2.4, 0.042, 3), actor.body_mass_kg * 4.0)
	var machine_distance := await push_into(machine, 60)
	check(absf(machine_distance) < 0.065, "Massive unanchored machinery resists incidental contact: %.3f m" % machine_distance)
	var fixed := item(Vector3(2.8, 0.04, 3), 1.1, ObjectDefinition.Mobility.FIXED)
	check(is_zero_approx(await push_into(fixed)) and fixed.freeze, "Fixed geometry receives no impulse")
	var leaf := item(Vector3(2.8, 0.04, 3.22), 1.1)
	var anchored := FastenerConnection.new()
	anchored.a = fixed
	anchored.b = leaf
	fastening.connections.append(anchored)
	fastening.rebuild()
	check(is_zero_approx(await push_into(leaf)) and leaf.fastened and leaf.assembly_root() == fixed,
		"Contact on an anchored follower respects the bolted constraint")

	var root_body := item(Vector3(4.1, 0.042, 3), 3.0)
	var follower := item(Vector3(4.1, 0.042, 3.22), 1.1)
	var floating := FastenerConnection.new()
	floating.a = root_body
	floating.b = follower
	fastening.connections.append(floating)
	fastening.rebuild()
	var spacing := follower.global_position - root_body.global_position
	check(await push_into(follower) > 0.12 and is_equal_approx(root_body.mass, 4.1)
		and (follower.global_position - root_body.global_position).is_equal_approx(spacing),
		"Contact on a movable follower moves the compounded root at total mass")
	var scrap := supply.dispense(0)
	check(scrap != null, "Dispenser creates a new piece of light stock")
	if scrap != null:
		await frames(40)
		var distance := await push_into(scrap)
		check(distance > 0.12 and scrap.has_meta(ScrapSupply.PROVENANCE), "Newly dispensed flat stock moves on contact: %.3f m" % distance)
	await reset_actor(Vector3(0, 0.03, 3.8))
	var pickup := actor.equipment.pick_up(light)
	var drop := actor.equipment.drop()
	check(pickup.ok and drop.ok, "Light item equips/drops: %s / %s" % [pickup.message, drop.message])
	await frames(65)
	check(await push_into(light) > 0.12 and light.get_instance_id() == light_id
		and light.state == InteractableObject.State.WORLD, "Contact works on the same object after equipment drop")

func key(code: Key, pressed := true) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = pressed
	return event

func wheel(button: MouseButton) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	return event

func camera_checks() -> void:
	await reset_actor(Vector3(0, 0.03, 4.0))
	var view := actor.view_camera
	var start := actor.global_transform
	check(actor.camera.is_current() and not view.route(key(KEY_Q)) and not view.route(key(KEY_E)),
		"First person is default and normal Q/E inputs are passed through")
	check(view.route(key(KEY_C)) and view.is_current() and view.third_person and actor.global_transform == start,
		"C shows the shoulder camera without changing the body")
	check(view.route(key(KEY_K)) and view.orbiting and view.route(key(KEY_C)) and view.third_person,
		"K enters orbit and C leaves the previously selected gameplay view intact")
	check(view.route(key(KEY_E)) and view.route(key(KEY_E, false)) and view.route(key(KEY_Q))
		and not view.route(wheel(MOUSE_BUTTON_WHEEL_UP)) and not view.route(wheel(MOUSE_BUTTON_WHEEL_DOWN)),
		"Orbit consumes Q/E press and release and passes vertical wheel input")
	var angle := view.orbit_angle
	var heading := actor.global_basis
	check(view.route(wheel(MOUSE_BUTTON_WHEEL_LEFT)) and not is_equal_approx(view.orbit_angle, angle)
		and view.route(wheel(MOUSE_BUTTON_WHEEL_RIGHT)) and is_equal_approx(view.orbit_angle, angle),
		"Horizontal tilt rotates the orbit in both directions")
	Input.action_press(&"camera_orbit_right")
	await frames(10)
	Input.action_release(&"camera_orbit_right")
	check(not is_equal_approx(view.orbit_angle, angle) and actor.global_basis == heading,
		"Held orbit input continuously pans without turning Otis")
	angle = view.orbit_angle
	actor.locomotion.try_turn(0.12)
	await frames(2)
	check(is_equal_approx(view.orbit_angle, angle), "Orbit heading stays world-relative as Otis turns")
	Input.action_press(&"move_forward")
	Input.action_press(&"locomotion_sprint")
	await frames(10)
	check(actor.locomotion.sprinting and actor.position.z < start.origin.z - 0.15,
		"Forward movement and hold-to-sprint work while orbiting")
	Input.action_release(&"move_forward")
	Input.action_release(&"locomotion_sprint")
	actor._unhandled_input(key(KEY_SPACE))
	await frames(3)
	check(actor.velocity.y > 0.0, "Space still jumps while orbiting")
	await reset_actor(Vector3(0, 0.03, 4.0))
	actor._unhandled_input(key(KEY_ALT))
	actor._unhandled_input(key(KEY_ALT, false))
	await frames(2)
	check(actor.locomotion.posture == OtisLocomotion.Posture.CROUCHING,
		"Posture tap works in orbit mode")
	check(view.route(key(KEY_K)) and view.is_current() and not view.orbiting and view.third_person,
		"K restores the selected shoulder camera")
	world.block("CameraWall", Vector3(3, 3, 0.2), Vector3(0, 1.5, 4.65), Color.WHITE)
	await frames(8)
	check(view.global_position.z < 4.48 and view.global_position.z >= actor.global_position.z,
		"Shoulder camera retracts immediately in front of a wall")
	check(view.route(key(KEY_C)) and actor.camera.is_current() and not view.third_person
		and actor.locomotion.posture == OtisLocomotion.Posture.CROUCHING,
		"First person resumes at the existing posture")
	check(view.route(key(KEY_K)) and view.route(key(KEY_K)) and actor.camera.is_current(),
		"Orbit also restores first person after dismissal")


func facility_checks() -> void:
	world = preload("res://scenes/facility.tscn").instantiate()
	root.add_child(world)
	current_scene = world
	bind_actor()
	await frames(6)
	var wrench := world.get_node("Wrench") as InteractableObject
	wrench.global_position = Vector3(0, 0.045, 2.75)
	await frames(8)
	var distance := await push_into(wrench)
	check(distance > 0.20, "The Facility's authored wrench moves from grounded contact: %.3f m" % distance)

	var tool := world.get("bolt_tool") as FasteningTool
	tool.global_transform = Transform3D(Basis.IDENTITY, Vector3(-0.8, 0.18, 3.0))
	await frames(30)
	distance = await push_into(tool)
	check(distance > 0.12, "The loose Uni-Bolt moves from grounded contact: %.3f m" % distance)

	var ui := world.get_node("InteractionUI")
	ui.application_focused = true
	actor.view_camera.set_orbiting(true)
	ui.e_pending = true
	ui._input(key(KEY_E))
	ui._input(key(KEY_E, false))
	check(not ui.e_pending and not ui.menu_open and actor.view_camera.orbiting,
		"Facility input consumes orbit E before the context and stow paths")
	world.queue_free()
	await process_frame

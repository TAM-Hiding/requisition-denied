extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func frames(count: int) -> void:
	for frame in count:
		await physics_frame

func aim(actor: OtisController, point: Vector3) -> void:
	actor.camera.look_at(point)
	actor.placement.distance = actor.camera.global_position.distance_to(point)

func place(body: RigidBody3D, point: Vector3) -> void:
	body.global_transform = Transform3D(Basis.IDENTITY, point)
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	body.sleeping = false

func run() -> void:
	var facility := preload("res://scenes/facility.tscn").instantiate()
	root.add_child(facility)
	current_scene = facility
	await frames(5)
	var actor: OtisController = facility.get_node("Otis")
	var crate: InteractableObject = facility.get_node("Crate")
	var weight: InteractableObject = facility.get_node("TestWeight")
	var wrench: InteractableObject = facility.get_node("Wrench")
	var start_basis := weight.global_basis
	var collider := weight.get_node("CollisionShape3D") as CollisionShape3D
	var weight_id := weight.get_instance_id()
	check(actor.equipment.pick_up(weight).ok, "Pick up the fresh calibration weight")
	var first_turn := await press_against_crate(actor, crate, weight, "First weight pickup", 1, -84)
	actor.placement.cancel()
	check(actor.equipment.held_item() == weight and not weight.top_level, "Cancel restores equipped weight")
	aim(actor, actor.camera.global_position + Vector3.RIGHT)
	check(actor.equipment.drop().ok, "Ordinary drop of the same weight succeeds")
	await frames(45)
	check(actor.equipment.pick_up(weight).ok, "Pick up the dropped weight")
	var next_turn := await press_against_crate(actor, crate, weight, "Second weight pickup", 1, -84)
	check(absf(first_turn - next_turn) < 0.06, "Same controls produce comparable turns before and after dropping")
	check(weight.get_instance_id() == weight_id and weight.get_node("CollisionShape3D") == collider
		and start_basis.is_equal_approx(Basis.IDENTITY), "Fresh and retrieved weight use the same collider and identity")
	actor.placement.cancel()
	check(actor.equipment.stow().ok and actor.equipment.equip_first().ok, "Weight can be stowed and retrieved")
	await press_against_crate(actor, crate, weight, "Weight from storage", 1, -84)
	check(actor.placement.confirm(), "Confirmation releases the placed weight")
	await frames(40)
	check(weight.state == InteractableObject.State.WORLD and not weight.freeze and weight.global_position.y > 1.3,
		"Confirmed weight rests on the crate in world physics")

	place(weight, Vector3(4.4, 0.13, 2.1))
	check(actor.equipment.pick_up(wrench).ok, "Pick up the fresh wrench")
	await press_against_crate(actor, crate, wrench, "First wrench pickup", 0, -84)
	actor.placement.cancel()
	aim(actor, actor.camera.global_position + Vector3.RIGHT)
	check(actor.equipment.drop().ok, "Ordinary wrench drop still works")
	await frames(35)
	check(actor.equipment.pick_up(wrench).ok, "Pick up the dropped wrench")
	await press_against_crate(actor, crate, wrench, "Second wrench pickup", 0, -84)
	actor.placement.cancel()
	aim(actor, actor.camera.global_position + Vector3.RIGHT)
	check(actor.equipment.drop().ok, "Release wrench for gate tests")
	await test_gate(facility, crate, wrench, weight)

	facility.queue_free()
	await process_frame
	print("RD-005 physics follow-up: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func press_against_crate(actor: OtisController, crate: InteractableObject, item: InteractableObject,
		label: String, axis: int, mouse_input: float) -> float:
	var placement := actor.placement
	actor.global_position = Vector3(crate.position.x, 0.01, crate.position.z + 1.8)
	var above := crate.global_position + Vector3.UP * 1.2
	aim(actor, above)
	await frames(4)
	placement.press_drop(1000000)
	placement.advance_drop(1350000)
	placement.release_drop(1360000)
	check(placement.is_active(), label + " enters precision placement")
	if not placement.is_active():
		return 0.0
	aim(actor, above)
	await frames(28)
	var original := item.global_basis.get_rotation_quaternion()
	for step in axis:
		placement.cycle_axis()
	placement.rotating = true
	placement.rotate_from_mouse(mouse_input)
	await frames(7)
	var tilted := item.global_basis.get_rotation_quaternion()
	check(original.angle_to(tilted) > 0.52, label + " accepts a 30–45 degree manual tilt")
	aim(actor, crate.global_position + Vector3.UP * 0.40)
	await frames(28)
	check(tilted.angle_to(item.global_basis.get_rotation_quaternion()) < 0.002,
		label + " preserves the tilt while R is held into contact")
	placement.rotating = false
	var clear := PlacementClearance.new()
	clear.configure(item)
	var all_clear := true
	for step in 8:
		await physics_frame
		all_clear = all_clear and placement.valid and clear.clear(item.global_transform)
	var early_turn := tilted.angle_to(item.global_basis.get_rotation_quaternion())
	check(early_turn > 0.012 and early_turn < 0.24, label + " turns progressively under contact pressure")
	for step in 104:
		await physics_frame
		all_clear = all_clear and placement.valid and clear.clear(item.global_transform)
	var turned := tilted.angle_to(item.global_basis.get_rotation_quaternion())
	check(all_clear and turned > 0.13, label + " settles without an overlapping preview")
	return turned

func test_gate(facility: Node3D, crate: InteractableObject, wrench: InteractableObject, weight: InteractableObject) -> void:
	var gate: PoweredBarrier = facility.barrier
	var plate: PhysicalLoadSensor = facility.load_plate
	var actor: OtisController = facility.get_node("Otis")
	var gate_top := gate.closed_position + Vector3.UP * 0.96
	var home := actor.global_position
	actor.global_position = plate.global_position + Vector3.UP * 0.01
	await frames(125)
	check(plate.output.is_active() and gate.state == PoweredBarrier.State.OPEN, "An empty gate opens from plate input")
	actor.global_position = home
	await frames(100)
	check(gate.state == PoweredBarrier.State.CLOSED, "Empty gate closes after plate release")

	place(wrench, gate_top + Vector3.UP * 0.06)
	await frames(25)
	var supported_height := wrench.global_position.y
	actor.global_position = plate.global_position + Vector3.UP * 0.01
	await frames(75)
	check(gate.global_position.y > gate.closed_position.y + 0.45
		and absf(wrench.global_position.y - supported_height - (gate.global_position.y - gate.closed_position.y)) < 0.025,
		"The gate physically lifts the supported wrench at the same rate")
	await frames(65)
	check(gate.state == PoweredBarrier.State.BLOCKED and gate.position.y > gate.open_position.y - 0.065
		and wrench.global_position.y + 0.04 <= 4.002,
		"The supported wrench meets the ceiling without penetration")
	place(wrench, Vector3(0, 0.06, 0))
	await frames(12)
	check(gate.state == PoweredBarrier.State.OPEN, "Gate completes opening after the wrench is removed")
	actor.global_position = home
	await frames(105)

	place(weight, gate_top + Vector3.UP * 0.14)
	await frames(25)
	actor.global_position = plate.global_position + Vector3.UP * 0.01
	await frames(145)
	check(gate.state == PoweredBarrier.State.BLOCKED and gate.position.y > gate.closed_position.y + 1.6
		and weight.global_position.y + 0.115 <= 4.002
		and absf(weight.global_position.y - (gate.global_position.y + 0.96 + 0.115)) < 0.02,
		"The gate lifts the calibration weight until its actual overhead clearance runs out")
	actor.global_position = home
	await frames(105)
	check(gate.state == PoweredBarrier.State.CLOSED and weight.global_position.y < 2.2,
		"Reversal moves away from the load and closes while it falls back")
	place(weight, Vector3(4.4, 0.13, 2.1))

	place(crate, gate.closed_position + Vector3(0, -0.34, 0.741))
	await frames(35)
	actor.global_position = plate.global_position + Vector3.UP * 0.01
	await frames(125)
	check(gate.state == PoweredBarrier.State.OPEN and absf(crate.position.z - (gate.closed_position.z + 0.741)) < 0.01,
		"Crate face contact beside the swept path does not stall or displace it")
	place(crate, gate.closed_position + Vector3.DOWN * 0.34)
	await frames(20)
	actor.global_position = home
	await frames(105)
	check(gate.state == PoweredBarrier.State.BLOCKED and gate.global_position.y - 0.96 >= 1.29,
		"Crate in the closing path remains a genuine obstruction")
	actor.global_position = plate.global_position + Vector3.UP * 0.01
	await frames(70)
	check(gate.state == PoweredBarrier.State.OPEN, "Gate reverses away from a genuine closing obstruction")
	place(crate, Vector3(-2.5, 0.66, -0.5))
	actor.global_position = home
	await frames(110)
	check(gate.state == PoweredBarrier.State.CLOSED, "Normal operation resumes after the obstruction clears")

	var blocker := StaticBody3D.new()
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.5, 0.20, 0.5)
	collider.shape = box
	blocker.add_child(collider)
	blocker.position = gate_top + Vector3.UP * 0.5
	facility.add_child(blocker)
	actor.global_position = plate.global_position + Vector3.UP * 0.01
	await frames(75)
	check(gate.state == PoweredBarrier.State.BLOCKED
		and gate.global_position.y + 0.96 <= blocker.global_position.y - 0.10 + 0.002,
		"A fixed object across the opening path stops the gate before contact")
	blocker.queue_free()
	await frames(105)
	check(gate.state == PoweredBarrier.State.OPEN, "Removing the fixed opening obstruction lets the gate resume")
	actor.global_position = home
	await frames(105)

	# Give the same gate a shorter stroke to exercise loads with headroom.
	gate.open_position = gate.closed_position + Vector3.UP * 1.5
	place(wrench, gate_top + Vector3(-0.35, 0.06, 0))
	place(weight, gate_top + Vector3(0.35, 0.14, 0))
	await frames(25)
	actor.global_position = plate.global_position + Vector3.UP * 0.01
	await frames(160)
	var open_top := gate.open_position.y + 0.96
	check(gate.state == PoweredBarrier.State.OPEN
		and absf(wrench.global_position.y - open_top - 0.04) < 0.012
		and absf(weight.global_position.y - open_top - 0.115) < 0.012,
		"With headroom the gate reaches its open endpoint carrying both loads")

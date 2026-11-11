extends SceneTree

var checks := 0
var failures := 0
var transitions := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)

func frames(count: int) -> void:
	for frame in count:
		await physics_frame

func place(body: RigidBody3D, at: Vector3) -> void:
	body.global_position = at
	body.linear_velocity = Vector3.ZERO
	body.angular_velocity = Vector3.ZERO
	body.sleeping = false

func run() -> void:
	var facility := load("res://scenes/facility.tscn").instantiate() as Node3D
	root.add_child(facility)
	current_scene = facility
	var plate: PhysicalLoadSensor = facility.load_plate
	var gate: PoweredBarrier = facility.barrier
	var controller: BarrierController = facility.barrier_control
	var crate := facility.get_node("Crate") as InteractableObject
	var wrench := facility.get_node("Wrench") as InteractableObject
	var weight := facility.get_node("TestWeight") as InteractableObject
	var actor := facility.get_node("Otis") as OtisController
	var center := plate.global_position
	await frames(8)
	check(plate.measured_kg == 0 and not plate.output.is_active(), "Empty plate ignores nearby fixtures and objects")
	check(gate.state == PoweredBarrier.State.CLOSED, "Gate starts closed")
	check(gate_blocks(gate, actor), "Closed collision blocks passage")
	place(crate, Vector3(0.35, 0.66, center.z))
	await frames(12)
	crate.state = InteractableObject.State.MOVING
	crate.move_goal = center + Vector3.UP * 0.65
	await frames(125)
	crate.state = InteractableObject.State.WORLD
	await frames(14)
	check(absf(crate.position.x - center.x) < 0.15, "Existing physics drive crosses flush plate seam")
	check(is_equal_approx(plate.measured_kg, 35), "Plate measures actual crate mass")
	check(not plate.output.is_active(), "Crate alone is below threshold")
	place(wrench, center + Vector3.UP * 1.36)
	await frames(22)
	check(is_equal_approx(plate.measured_kg, 35.6), "Wrench stack is counted exactly once per body")
	place(wrench, Vector3(0, 0.1, 0))
	place(weight, center + Vector3.UP * 1.43)
	await frames(12)
	check(is_equal_approx(plate.measured_kg, 43), "Portable weight and crate combine through support chain")
	check(not plate.output.is_active(), "Short threshold crossing does not activate")
	place(weight, Vector3(4.4, 0.13, 2.1))
	await frames(8)
	check(plate.qualifying_time == 0, "Load interruption resets continuous dwell")
	place(weight, center + Vector3.UP * 1.43)
	await frames(38)
	check(plate.output.is_active() and controller.input_active, "Dwell activates output and receiver")
	await frames(95)
	check(gate.state == PoweredBarrier.State.OPEN and not gate_blocks(gate, actor), "Open gate permits passage")
	var service := InteractionService.new()
	actor.global_position = center + Vector3(0, 0.01, 1.6)
	actor.camera.look_at(weight.global_position)
	await frames(3)
	check(service.request(&"pick_up", actor, actor.camera, weight, 3, actor.knowledge).ok, "Calibration block can be picked up through the contextual action")
	actor.camera.look_at(actor.camera.global_position + Vector3.FORWARD)
	check(actor.equipment.drop().ok, "Existing drop action places calibration block above crate")
	await frames(60)
	check(is_equal_approx(plate.measured_kg, 43) and plate.is_active(), "Player equipment placement activates the stack")
	weight.mass = 3.0
	await frames(12)
	check(is_equal_approx(plate.measured_kg, 38) and plate.output.is_active(), "Hysteresis retains activation between 37 and 40 kg")
	actor.global_position = center + Vector3(0, 0.01, 1.7)
	actor.camera.look_at(center + Vector3(0, 0, 0.87))
	await frames(3)
	var inspection := service.request(&"inspect", actor, actor.camera, plate, 3, actor.knowledge)
	check(inspection.ok and "38.0 KG" in inspection.information.description, "Normal inspection reports live device properties")
	check(actor.knowledge.inspected_object_count() == 1, "Device inspection uses existing knowledge records")
	place(weight, Vector3(4.4, 0.13, 2.1))
	actor.global_position = Vector3(gate.global_position.x, 0.01, gate.global_position.z)
	await frames(45)
	check(not controller.input_active and not plate.output.is_active(), "Removing enough mass requests close")
	check(gate.state == PoweredBarrier.State.BLOCKED and gate.position.y - 0.96 >= 1.79, "Gate pauses above Otis")
	var blocked_height := gate.position.y
	await frames(15)
	check(is_equal_approx(gate.position.y, blocked_height), "Blocked gate stays stationary")
	actor.global_position = Vector3(0, 0.01, 4)
	await frames(100)
	check(gate.state == PoweredBarrier.State.CLOSED and gate_blocks(gate, actor), "Gate resumes closing when Otis clears")
	place(crate, center + Vector3(-0.51, 0.66, 0))
	weight.mass = 8.0
	place(weight, center + Vector3(0.73, 0.13, 0))
	await frames(38)
	check(is_equal_approx(plate.measured_kg, 43) and plate.output.is_active(), "Independent objects on plate add their mass")
	await frames(95)
	place(crate, Vector3(4.65, 0.66, -4.35))
	await frames(70)
	check(gate.state == PoweredBarrier.State.BLOCKED and gate.position.y - 0.96 >= 1.29, "Gate pauses above movable crate")
	place(crate, Vector3(-2.5, 0.66, -0.5))
	place(weight, center + Vector3(1.16, 0.13, 0))
	await frames(100)
	check(plate.measured_kg == 0 and gate.state == PoweredBarrier.State.CLOSED, "Nearby floor support does not count")
	place(weight, center + Vector3.UP * 1.7)
	await frames(5)
	check(plate.measured_kg == 0, "Airborne overlapping body does not count")
	place(weight, Vector3(4.4, 0.13, 2.1))
	actor.global_position = center + Vector3.UP * 0.01
	await frames(38)
	check(is_equal_approx(plate.measured_kg, actor.body_mass_kg) and controller.input_active, "Otis loads plate using explicit body mass")
	actor.global_position = Vector3(0, 0.01, 4)
	await frames(5)
	var source := EnvironmentalSignal.new()
	source.source_id = &"TEST-OUT"
	source.initial_output = true
	source.output_changed.connect(func(_active: bool) -> void: transitions += 1)
	facility.add_child(source)
	controller.connect_inputs([source])
	check(controller.input_active, "Receiver samples pre-existing active source")
	source.set_output(true)
	check(transitions == 0, "Identical output does not emit")
	await frames(12)
	var reversal_position := gate.position.y
	source.set_output(false)
	check(transitions == 1 and not controller.input_active, "Changed output propagates once")
	await frames(3)
	check(gate.position.y < reversal_position and reversal_position - gate.position.y < 0.12, "Reversing mid-animation continues from current pose")
	source.set_output(true)
	await frames(3)
	check(gate.state == PoweredBarrier.State.OPENING, "Second reversal opens again")
	controller.connect_inputs([source, plate.output])
	check(not controller.input_active, "All configured inputs must be active")
	controller.connect_inputs([source])
	facility.remove_child(source)
	check(not controller.input_active and controller.inputs[0] == null, "Source exit clears reference and requests close")
	facility.add_child(source)
	source.set_output(false)
	source.set_output(true)
	check(not controller.input_active, "Removed source cannot reactivate disconnected receiver")
	controller.connect_inputs([source])
	check(controller.input_active, "Explicit reconnection samples current state")
	controller.connect_inputs([])
	check(not controller.input_active, "Empty input list requests close")
	if DisplayServer.get_name() != "headless" and not OS.get_environment("RD_SCREENSHOT").is_empty():
		actor.global_position = Vector3(0.3, 0.01, 3.9)
		actor.camera.look_at(Vector3(3.05, 0.3, -0.3))
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(OS.get_environment("RD_SCREENSHOT"))
	facility.queue_free()
	await process_frame
	print("RD-003: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func gate_blocks(gate: PoweredBarrier, actor: OtisController) -> bool:
	var start := Transform3D(Basis.IDENTITY, Vector3(gate.closed_position.x, 0.025, gate.closed_position.z + 0.7))
	return actor.test_move(start, Vector3.FORWARD * 1.4)

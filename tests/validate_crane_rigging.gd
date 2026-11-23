extends SceneTree


class TestHoist extends Node3D:
	var hook: RigidBody3D
	var load_body: RigidBody3D
	var strap: CraneRigging
	var speed := 0.0
	var peak_tension := 0.0

	func configure(load_mass: float) -> void:
		var ground := StaticBody3D.new()
		ground.position = Vector3(0, -0.10, 0)
		add_child(ground)
		add_box(ground, Vector3(6, 0.20, 6))

		hook = RigidBody3D.new()
		hook.mass = 225.0
		hook.position = Vector3(0, 0.84, 0)
		hook.gravity_scale = 0.0
		hook.lock_rotation = true
		hook.can_sleep = false
		add_child(hook)
		add_box(hook, Vector3(0.40, 0.35, 0.38))

		load_body = RigidBody3D.new()
		load_body.mass = load_mass
		load_body.position = Vector3(0, 0.11, 0)
		load_body.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
		load_body.center_of_mass = Vector3(0.03, 0, 0)
		load_body.lock_rotation = true
		load_body.continuous_cd = true
		load_body.angular_damp = 0.7
		add_child(load_body)
		add_box(load_body, Vector3(1.8, 0.20, 0.25))

		strap = CraneRigging.new()
		add_child(strap)

	func add_box(body: PhysicsBody3D, size: Vector3) -> void:
		var collider := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		collider.shape = box
		body.add_child(collider)

	func throat() -> Vector3:
		return hook.to_global(Vector3(0, -0.18, 0))

	func attach(point: Vector3) -> String:
		return strap.attach(hook, throat(), load_body, load_body.to_global(point), load_body.mass, Vector3.ZERO)

	func _physics_process(delta: float) -> void:
		var state := PhysicsServer3D.body_get_direct_state(hook.get_rid())
		if state == null:
			return
		state.linear_velocity = Vector3.UP * speed
		strap.step(delta, Vector3.UP, speed)
		peak_tension = maxf(peak_tension, strap.tension_newtons)
		# Vertical reference actuator for this fixture. The real crane has its own cable constraint.
		state.linear_velocity = Vector3.UP * speed


var checks := 0
var failures := 0


func _initialize() -> void:
	run.call_deferred()


func check(ok: bool, note: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(note)


func frames(count: int) -> void:
	for frame in count:
		await physics_frame


func make_hoist(mass: float) -> TestHoist:
	var hoist := TestHoist.new()
	root.add_child(hoist)
	hoist.configure(mass)
	return hoist


func run() -> void:
	var hoist := make_hoist(85.0)
	await frames(15)
	var before := hoist.load_body.global_transform
	var hit := hoist.load_body.to_global(Vector3(0, 0.10, 0))
	check(not hoist.strap.attach(hoist.hook, hoist.throat(), hoist.load_body, hit, 50001.0).is_empty(),
		"Rigging rejects masses above the marked crane capacity")
	check(not hoist.strap.attach(hoist.hook, hoist.throat(), hoist.load_body, hit, NAN).is_empty(),
		"Rigging rejects invalid mass")
	check(not hoist.strap.attach(hoist.hook, hoist.throat() + Vector3.UP, hoist.load_body, hit, 85.0).is_empty(),
		"Rigging rejects attachment points out of hook reach")
	hoist.load_body.freeze = true
	check(not hoist.attach(Vector3(0, 0.10, 0)).is_empty(), "An anchored load cannot be rigged")
	hoist.load_body.freeze = false
	check(hoist.attach(Vector3(0, 0.10, 0)).is_empty() and hoist.strap.is_attached(), "Centered rig attaches")
	check(hoist.load_body.global_transform == before and hoist.load_body.get_parent() == hoist
		and not hoist.load_body.lock_rotation, "Attachment leaves the load in place, independent and free to turn")
	test_rebind(hoist, hit)
	await frames(8)
	check(hoist.strap.slack_m >= 0.025 and hoist.strap.tension_newtons == 0.0,
		"Ground-supported load has slack and no compressive force")
	hoist.speed = 0.45
	await frames(145)
	hoist.speed = 0.0
	await frames(100)
	check(hoist.load_body.position.y > 0.92 and hoist.peak_tension > 300.0,
		"Strap takes up slack and physically raises the load")
	check(absf(hoist.load_body.global_basis.x.y) < 0.08
		and absf(hoist.strap.load_point().distance_to(hoist.strap.hook_point()) - hoist.strap.length_m) < 0.03,
		"A centered beam hangs level at the strap length")
	hoist.speed = -0.45
	await frames(145)
	hoist.speed = 0.0
	await frames(22)
	check(absf(hoist.load_body.position.y - 0.10) < 0.02 and hoist.strap.slack_m > 0.02
		and hoist.strap.tension_newtons == 0.0, "Lowering onto the floor produces slack without penetrating the floor")
	before = hoist.load_body.global_transform
	hoist.strap.detach()
	check(not hoist.strap.is_attached() and hoist.load_body.global_transform == before and hoist.load_body.lock_rotation
		and hoist.load_body.center_of_mass.is_equal_approx(Vector3(0.03, 0, 0)),
		"Detachment restores the body's original settings without moving it")
	hoist.queue_free()
	await frames(2)

	hoist = make_hoist(1250.0)
	await frames(15)
	hoist.hook.position.x = 0.72
	await frames(2)
	check(hoist.attach(Vector3(0.72, 0.10, 0)).is_empty(), "Far-side rig attaches to a heavy beam")
	hoist.speed = 0.43
	await frames(285)
	hoist.speed = 0.0
	await frames(155)
	check(hoist.load_body.position.y > 0.65 and absf(hoist.load_body.global_basis.x.y) > 0.72,
		"Off-center loaded beam tilts toward a physically balanced orientation")
	check(hoist.load_body.global_transform.is_finite() and hoist.strap.tension_newtons >= 0.0
		and hoist.strap.load_point().distance_to(hoist.strap.hook_point()) - hoist.strap.length_m < 0.04,
		"Large block-to-load mass ratio stays finite and tightly constrained")
	hoist.load_body.queue_free()
	await frames(3)
	check(not hoist.strap.is_attached() and hoist.strap.length_m == 0.0 and hoist.strap.load_mass_kg == 0.0,
		"Removing a load clears its strap and mass accounting safely")
	hoist.queue_free()
	await frames(2)
	await test_mezzanine_delivery()
	print("RD-015B strap constraint: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func test_rebind(hoist: TestHoist, selected: Vector3) -> void:
	var released_member := RigidBody3D.new()
	released_member.position = selected
	released_member.mass = 12.0
	released_member.lock_rotation = true
	hoist.add_child(released_member)
	var length := hoist.strap.length_m
	var hook_world := hoist.strap.hook_point()
	var original_pose := hoist.load_body.global_transform
	var member_pose := released_member.global_transform

	check(not hoist.strap.rebind_load(released_member, selected + Vector3.RIGHT * 0.30, 12.0),
		"Cannot rebind to an unrelated point during an assembly split")
	check(hoist.strap.rebind_load(released_member, selected, 12.0) and hoist.strap.load_body == released_member
		and hoist.strap.length_m == length and hoist.strap.hook_point() == hook_world
		and hoist.load_body.lock_rotation and not released_member.lock_rotation,
		"Rebind transfers a matching attachment to the newly independent body at the same length")
	check(hoist.load_body.global_transform == original_pose and released_member.global_transform == member_pose,
		"Rebind changes neither body transform")
	check(hoist.strap.rebind_load(hoist.load_body, selected, hoist.load_body.mass, Vector3.ZERO)
		and released_member.lock_rotation, "Rebound load also restores its original settings when released")
	released_member.free()


func test_mezzanine_delivery() -> void:
	var facility := preload("res://scenes/facility.tscn").instantiate()
	root.add_child(facility)
	current_scene = facility
	var hall: Node3D = facility.get_node("EngineeringTestHall")
	var crane: BridgeCrane = facility.overhead_crane
	var beam := RigidBody3D.new()
	beam.name = "MezzanineDeliveryBeam"
	beam.mass = 73.0
	beam.position = Vector3(-1.5, 0.11, 17.0)
	beam.lock_rotation = true
	beam.continuous_cd = true
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.2, 0.20, 0.28)
	collider.shape = box
	beam.add_child(collider)
	hall.add_child(beam)

	# Stage the empty hook just before the mezzanine. All loaded motion uses the actual OC-01 axes.
	crane.bridge.position = 17.0
	crane.suspension.height = 1.0
	crane.suspension.request_height(1.0)
	crane.hook.global_position = hall.to_global(Vector3(crane.trolley.position, 1.0, crane.bridge.position))
	await frames(20)
	check(crane.attach_load(beam, beam.to_global(Vector3.UP * 0.10)).is_empty() and crane.rigged_body() == beam,
		"OC-01 accepts a free beam at the actual floor-to-hook attachment point")
	crane.adjust_hook_steps(56, false)
	await frames(550)
	check(hall.to_local(beam.global_position).y > 5.5 and crane.rigging.tension_newtons > 600.0,
		"Powered hoist raises the physical beam above the mezzanine railing")
	crane.set_controls(0.0, 1.0, false)
	await frames(220)
	crane.clear_controls()
	await frames(320)
	var delivered := hall.to_local(beam.global_position)
	check(delivered.z > 22.0 and delivered.y > 5.5 and absf(beam.global_basis.x.y) < 0.10,
		"Bridge carries the independently simulated beam across the guardrail")
	crane.adjust_hook_steps(-45, false)
	await frames(500)
	delivered = hall.to_local(beam.global_position)
	check(absf(delivered.y - 3.45) < 0.03 and crane.rigging.slack_m > 0.12
		and crane.rigging.tension_newtons == 0.0, "Mezzanine supports the delivered beam with a slack strap")
	check(crane.detach_load().is_empty() and crane.rigged_body() == null,
		"Lift can detach on the deck")
	await frames(25)
	check(hall.to_local(beam.global_position).distance_to(delivered) < 0.03
		and beam.get_parent() == hall, "Detached load remains on the deck without reparenting or drift")
	facility.queue_free()
	await frames(2)

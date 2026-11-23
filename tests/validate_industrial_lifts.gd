extends SceneTree

const FLAT_BAR := "Flat Bar — 20 ft"
const ROUND_BAR := "Round Bar — 20 ft"
const BEAM := "Wide-Flange Beam — 30 ft"
const BLOCK := "Machinery Test Block — 5 t"
const CASES := [FLAT_BAR, ROUND_BAR, BEAM, BLOCK]

var facility: Node3D
var hall: Node3D
var crane: BridgeCrane
var supply: ScrapSupply
var checks := 0
var failures := 0


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	facility = preload("res://scenes/facility.tscn").instantiate()
	root.add_child(facility)
	current_scene = facility
	hall = facility.get_node("EngineeringTestHall")
	crane = facility.overhead_crane
	supply = facility.scrap_supply
	await frames(12)
	for title: String in CASES:
		await test_centered_lift(title)
	for title: String in CASES:
		await test_off_center_release(title)
	await test_compound_lift()
	await test_suspended_wall()
	await test_multiple_stock()
	check(crane.maintenance.impact_count == 0, "Industrial lifts and contacts do not charge end-stop maintenance")
	facility.queue_free()
	await frames(2)
	print("RD-015C industrial crane lifts: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func frames(count: int) -> void:
	for frame in count:
		await physics_frame


func check(ok: bool, note: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(note)


func catalog_index(title: String) -> int:
	for index in supply.catalog.size():
		if supply.catalog[index].title == title:
			return index
	return -1


func dispense(title: String) -> InteractableObject:
	var index := catalog_index(title)
	var part := supply.dispense(index) if index >= 0 else null
	check(part != null, "Development catalog dispenses " + title)
	return part


func settle_on_slab(part: InteractableObject, height: float, title: String) -> void:
	await frames(90)
	check(absf(hall.to_local(part.global_position).y - height * 0.5) < 0.045
		and part.linear_velocity.length() < 0.08 and part.angular_velocity.length() < 0.08,
		title + " settles on the slab after an ordinary delivery")


func stage_empty_hook(point: Vector3) -> void:
	crane.clear_controls()
	var position := hall.to_local(point) + Vector3.UP * 1.05
	crane.trolley.position = position.x
	crane.bridge.position = position.z
	crane.trolley.velocity = 0.0
	crane.bridge.velocity = 0.0
	crane.suspension.height = position.y
	crane.suspension.velocity = 0.0
	crane.suspension.request_height(position.y)
	var pose := Transform3D(hall.global_basis, hall.to_global(position))
	crane.hook.global_transform = pose
	crane.hook.linear_velocity = Vector3.ZERO
	crane.hook.angular_velocity = Vector3.ZERO
	PhysicsServer3D.body_set_state(crane.hook.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, pose)
	await frames(12)


func test_centered_lift(title: String) -> void:
	var part := dispense(title)
	if part == null:
		return
	var size: Vector3 = supply.catalog[catalog_index(title)].size
	await settle_on_slab(part, size.y, title)
	var original := hall.to_local(part.global_position)
	var point := part.to_global(Vector3.UP * size.y * 0.5)
	await stage_empty_hook(point)
	var result := crane.attach_load(part, point)
	check(result.is_empty() and crane.rigged_body() == part, title + " rigs at its center: " + result)
	if not result.is_empty():
		part.queue_free()
		await frames(3)
		return
	crane.adjust_hook_steps(23, false)
	await frames(265)
	var raised := hall.to_local(part.global_position)
	check(raised.y > original.y + 2.0 and Vector2(raised.x - original.x, raised.z - original.z).length() < 0.12
		and absf(part.global_basis.x.y) < 0.08 and absf(part.global_basis.z.y) < 0.08,
		"%s lifts level and stays centered: %s" % [title, raised])
	check(crane.rigging.tension_newtons > part.mass * 6.0 and part.global_transform.is_finite(),
		title + " hangs under its own finite physical load")
	var state := PhysicsServer3D.body_get_direct_state(part.get_rid())
	var tensor := state.inverse_inertia_tensor
	var about_length := part.global_basis.x.dot(tensor * part.global_basis.x)
	var across_length := part.global_basis.y.dot(tensor * part.global_basis.y)
	check(about_length > 0.0 and across_length > 0.0
		and (title == BLOCK or about_length > 50.0 * across_length),
		title + " uses finite shape-derived rotational inertia")

	if title == BLOCK:
		await test_block_transport(part, raised, size.y)
	elif title == BEAM:
		await test_two_supports(part, size)
	else:
		check(crane.detach_load().is_empty(), title + " releases in free flight")
		await frames(150)
		check(absf(hall.to_local(part.global_position).y - size.y * 0.5) < 0.07
			and not part.lock_rotation and not part.freeze, title + " falls to the slab and keeps free rotation")
		if title == ROUND_BAR:
			await test_round_roll(part)
	part.queue_free()
	await frames(4)


func test_round_roll(part: InteractableObject) -> void:
	var before := hall.to_local(part.global_position)
	var pose := part.global_basis
	part.apply_central_impulse(hall.global_basis.z * (part.mass * 0.75))
	await frames(19)
	var delta := hall.to_local(part.global_position) - before
	var turn := pose.get_rotation_quaternion().angle_to(part.global_basis.get_rotation_quaternion())
	check(delta.z > 0.05 and turn > 0.25 and absf(delta.y) < 0.025,
		"Released solid round bar rolls around its cylindrical axis along the floor")


func test_block_transport(part: InteractableObject, raised: Vector3, height: float) -> void:
	crane.set_controls(1.0, 1.0, true)
	await frames(300)
	crane.clear_controls()
	await frames(260)
	var moved := hall.to_local(part.global_position)
	check(moved.x > raised.x + 1.10 and moved.z > raised.z + 1.25 and moved.y > height * 0.5 + 1.8
		and part.global_transform.is_finite(), "The bridge and trolley transport the 5 t block in suspension")
	crane.adjust_hook_steps(-27, false)
	await frames(360)
	check(absf(hall.to_local(part.global_position).y - height * 0.5) < 0.06
		and crane.rigging.slack_m > 0.10 and crane.rigging.tension_newtons < 30.0,
		"The machinery block transfers its weight to the floor and leaves slack")
	check(crane.detach_load().is_empty() and crane.rigged_body() == null,
		"Ground-supported machinery block detaches normally")
	part.mass = 50001.0
	check(crane.rig_candidate(part, part.global_position).contains("rated capacity"),
		"An otherwise compatible article still cannot exceed OC-01's rated capacity")
	part.mass = part.definition.mass_kg
	await frames(3)


func test_two_supports(part: InteractableObject, size: Vector3) -> void:
	var at := hall.to_local(part.global_position)
	var supports: Array[StaticBody3D] = []
	for offset: float in [-3.0, 3.0]:
		var support := StaticBody3D.new()
		support.position = Vector3(at.x + offset, 0.32, at.z)
		var collision := CollisionShape3D.new()
		var pad := BoxShape3D.new()
		pad.size = Vector3(0.65, 0.64, 0.9)
		collision.shape = pad
		support.add_child(collision)
		hall.add_child(support)
		supports.append(support)
	crane.adjust_hook_steps(-22, false)
	await frames(330)
	check(absf(hall.to_local(part.global_position).y - size.y * 0.5 - 0.64) < 0.07
		and absf(part.global_basis.x.y) < 0.045 and crane.rigging.slack_m > 0.10,
		"Wide-flange beam rests level on two separate supports with slack in the strap")
	var before := part.global_position
	check(crane.detach_load().is_empty(), "Beam detaches onto both supports")
	await frames(110)
	check(part.global_position.distance_to(before) < 0.03 and part.linear_velocity.length() < 0.04,
		"The released beam stays supported without persistent drift")
	for support in supports:
		support.queue_free()


func test_off_center_release(title: String) -> void:
	var part := dispense(title)
	if part == null:
		return
	var size: Vector3 = supply.catalog[catalog_index(title)].size
	await frames(90)
	var x_offset := 1.15 if title == BEAM else (0.45 if title == BLOCK else 0.85)
	var point := part.to_global(Vector3(x_offset, size.y * 0.5, 0))
	await stage_empty_hook(point)
	var result := crane.attach_load(part, point)
	check(result.is_empty(), title + " accepts an off-center attachment: " + result)
	if not result.is_empty():
		part.queue_free()
		await frames(3)
		return
	crane.adjust_hook_steps(75, false)
	await frames(740)
	var pose := part.global_transform
	check(pose.is_finite() and hall.to_local(pose.origin).y > size.y * 0.5 + 2.0
		and absf(part.global_basis.x.y) > 0.45,
		"%s develops a physical tilt about the off-center attachment: %.3f at %s" % [title, part.global_basis.x.y, pose.origin])
	check(crane.detach_load().is_empty() and part.global_transform == pose and not part.lock_rotation,
		title + " detaches without teleporting or restoring a rotation lock")
	await frames(490)
	var dropped := hall.to_local(part.global_position)
	if title == ROUND_BAR:
		# A high end-on impact can leave this slender cylinder precessing on its rim.
		var tilt := absf(part.global_basis.x.y)
		var contact_height := size.x * 0.5 * tilt + size.y * 0.5 * sqrt(maxf(0.0, 1.0 - tilt * tilt))
		check(absf(dropped.y - contact_height) < 0.10 and dropped.y < hall.to_local(pose.origin).y - 1.0
			and part.angular_velocity.is_finite(),
			"An off-center round-bar release falls to physical rim or barrel contact")
	elif title == BLOCK:
		var basis := part.global_basis
		var supported_height := maxf(absf(basis.x.y) * size.x, maxf(absf(basis.y.y) * size.y, absf(basis.z.y) * size.z)) * 0.5
		check(absf(dropped.y - supported_height) < 0.06 and part.linear_velocity.length() < 0.12
			and part.angular_velocity.length() < 0.12, "The off-center casting settles on a stable face")
	else:
		check(dropped.y < size.y * 0.5 + 0.38 and absf(part.global_basis.x.y) < 0.18
			and part.linear_velocity.length() < 0.12, "%s tips and settles freely after release: %s" % [title, dropped])
	part.queue_free()
	await frames(4)


func test_compound_lift() -> void:
	var bar := dispense(FLAT_BAR)
	if bar == null:
		return
	await frames(80)
	var plate := dispense("Medium flat plate")
	if plate == null:
		bar.queue_free()
		await frames(4)
		return
	var on_top := bar.to_global(Vector3(-0.7, 0.029, 0.0))
	var actor := facility.get_node("Otis") as OtisController
	actor.equipment.restore_world(plate, Transform3D(hall.global_basis, on_top), false)
	await frames(28)
	var fastening: FasteningSystem = facility.fastening
	var bolt := fastening.create_round(FasteningTool.GRADES[0])
	var issue := fastening.install(bolt, on_top + Vector3.UP * 0.45, Vector3.DOWN, 1.0)
	check(issue.is_empty() and plate.fastened and bar.fastened,
		"Uni-Bolt fastens the long flat bar to another independent stock member: " + issue)
	if not issue.is_empty():
		plate.queue_free()
		bar.queue_free()
		await frames(4)
		return
	var info := crane.mass_properties.resolve(bar)
	var center := info.world_center()
	var expected := (bar.global_position * bar.definition.mass_kg + plate.global_position * plate.definition.mass_kg) / info.mass_kg
	check(info.members.has(plate) and info.members.has(bar)
		and is_equal_approx(info.mass_kg, bar.definition.mass_kg + plate.definition.mass_kg)
		and center.distance_to(expected) < 0.015,
		"Compound mass and center of mass account for both unequal stock members")
	var relative := bar.global_transform.affine_inverse() * plate.global_transform
	var point := bar.to_global(Vector3(0.60, 0.00635, 0))
	await stage_empty_hook(point)
	issue = crane.attach_load(bar, point)
	check(issue.is_empty(), "Compatible long-stock compound rigs as one body: " + issue)
	crane.adjust_hook_steps(58.0, false)
	await frames(610)
	check(hall.to_local(bar.global_position).y > 2.0
		and relative.is_equal_approx(bar.global_transform.affine_inverse() * plate.global_transform),
		"Moving crane lifts the bolted long stock without displacing its member")
	check(crane.detach_load().is_empty(), "Long-stock compound releases from the hook")
	await frames(390)
	check(bolt.state == InstalledFastener.State.INSTALLED and plate.assembly_root() == bar.assembly_root()
		and relative.is_equal_approx(bar.global_transform.affine_inverse() * plate.global_transform)
		and not bar.lock_rotation and hall.to_local(bar.global_position).y < 0.20,
		"Released long-stock compound settles with free rotation and Uni-Bolt intact")
	plate.queue_free()
	bar.queue_free()
	await frames(4)


func set_stock_pose(part: InteractableObject, position: Vector3, yaw := 0.0) -> void:
	var pose := hall.global_transform * Transform3D(Basis(Vector3.UP, yaw), position)
	part.global_transform = pose
	part.sleeping = false
	PhysicsServer3D.body_set_state(part.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, pose)


func test_suspended_wall() -> void:
	var beam := dispense(BEAM)
	if beam == null:
		return
	var size: Vector3 = supply.catalog[catalog_index(BEAM)].size
	set_stock_pose(beam, Vector3(0, size.y * 0.5 + 0.02, 11.6))
	await frames(45)
	var point := beam.to_global(Vector3.UP * size.y * 0.5)
	await stage_empty_hook(point)
	check(crane.attach_load(beam, point).is_empty(), "Wall test rigs the actual wide-flange collider")
	crane.adjust_hook_steps(28, false)
	await frames(300)
	crane.set_controls(1, 0, false)
	await frames(410)
	var world := hall.global_transform.affine_inverse() * beam.global_transform
	var extent := absf(world.basis.x.x) * size.x * 0.5 + absf(world.basis.y.x) * size.y * 0.5 \
		+ absf(world.basis.z.x) * size.z * 0.5
	var edge := world.origin.x + extent
	check(edge > 8.65 and edge < 9.19 and crane.rigged_body() == beam and world.is_finite(),
		"The transported beam meets the east wall and remains on its inside: %.3f" % edge)
	crane.clear_controls()
	crane.detach_load()
	beam.queue_free()
	await frames(4)


func test_multiple_stock() -> void:
	var bar := dispense(FLAT_BAR)
	if bar == null:
		return
	set_stock_pose(bar, Vector3(0, 0.16, 12.5))
	await frames(65)
	var round_bar := dispense(ROUND_BAR)
	if round_bar == null:
		bar.queue_free()
		await frames(4)
		return
	set_stock_pose(round_bar, Vector3(0, 0.30, 12.5), PI / 2.0)
	await frames(130)
	var flat_y := hall.to_local(bar.global_position).y
	var round_y := hall.to_local(round_bar.global_position).y
	check(flat_y > -0.015 and flat_y < 0.03 and round_y > 0.025 and round_y < 0.09
		and bar.linear_velocity.length() < 0.10 and round_bar.linear_velocity.length() < 0.10,
		"Crossing long articles settle on each other and the slab without penetrating")
	bar.queue_free()
	round_bar.queue_free()
	await frames(4)

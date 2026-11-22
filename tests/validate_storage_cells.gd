extends SceneTree

# Headless Godot has no captured cursor. Leave movement and Jolt unchanged.
class HeadlessLocomotion extends OtisLocomotion:
	func input_active() -> bool:
		return actor.controls_enabled

var facility: Node3D
var hall: Node3D
var otis: OtisController
var checks := 0
var failures := 0

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
	facility = preload("res://scenes/facility.tscn").instantiate()
	root.add_child(facility)
	current_scene = facility
	hall = facility.get_node("EngineeringTestHall")
	otis = facility.get_node("Otis")
	if DisplayServer.get_name() == "headless":
		otis.locomotion.free()
		otis.locomotion = HeadlessLocomotion.new()
		otis.add_child(otis.locomotion)
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	await frames(6)
	check(hall.get_node("Shell/SlabCollider").get_meta(&"layout_support", false)
		and hall.get_node("Mezzanine/Deck").get_meta(&"layout_support", false),
		"Both existing flat hall surfaces are tagged for equipment placement")
	await cell_checks("A", Vector3(-9.0, 0, 2.75), -PI / 2, 9.144 - 9.0)
	await cell_checks("B", Vector3(7.0, 0, 24.25), 0.0, 24.384 - 24.25)
	facility.queue_free()
	await process_frame
	print("RD-014C storage cells: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func cell_checks(letter: String, position: Vector3, yaw: float, inside_wall: float) -> void:
	var cell := hall.get_node_or_null("StorageCells/StorageCell" + letter) as Node3D
	check(cell != null, "Storage cell %s exists" % letter)
	if cell == null:
		return
	check(cell.position.is_equal_approx(position) and is_equal_approx(cell.rotation.y, yaw),
		"Cell %s matches the exact exported doorway position and yaw" % letter)
	var outside_wall := inside_wall + 0.24
	for x in [-0.51, 0.0, 0.51]:
		var header_clear := not blocked(cell, Vector3(x, 2.15, inside_wall - 0.18), Vector3(x, 2.15, outside_wall + 0.18))
		check(header_clear, "Cell %s doorway is unobstructed across the clear opening at x %.2f" % [letter, x])
	for x in [-0.70, 0.70, -2.20, 2.20]:
		check(blocked(cell, Vector3(x, 1.2, inside_wall - 0.24), Vector3(x, 1.2, outside_wall + 0.24)),
			"Cell %s retains solid hall wall beside and beyond the opening at x %.2f" % [letter, x])
	check(blocked(cell, Vector3(0, 2.23, inside_wall - 0.16), Vector3(0, 2.23, outside_wall + 0.15)),
		"Cell %s has a physical door header" % letter)
	for z: float in [inside_wall - 0.05, inside_wall, inside_wall + 0.05, outside_wall, outside_wall + 1.7]:
		var support := ray(cell.to_global(Vector3(0, 0.33, z)), cell.to_global(Vector3(0, -0.15, z)))
		check(not support.is_empty() and absf(support.position.y) < 0.002,
			"Cell %s has level floor support across the slab seam at depth %.3f" % [letter, z])
	var center := Vector3(0, 1.2, outside_wall + 2.5)
	for side in [-1.0, 1.0]:
		check(blocked(cell, center, center + Vector3(side * 2.3, 0, 0)), "Cell %s has a solid exterior side wall" % letter)
	check(blocked(cell, center, center + Vector3(0, 0, 2.8)), "Cell %s has a solid exterior back wall" % letter)
	check(blocked(cell, center, center + Vector3(0, 1.8, 0)), "Cell %s has a collidable ceiling" % letter)
	check(cell.find_children("*", "SpotLight3D", false, false).size() == 2,
		"Cell %s has two fluorescent work lights" % letter)
	check(cell.to_global(center).distance_to(hall.to_global(position)) > 2.5,
		"Cell %s interior extends through the original exterior wall" % letter)

	otis.global_transform = Transform3D(Basis(Vector3.UP, yaw + PI), cell.to_global(Vector3(0, 0.03, -0.80)))
	otis.velocity = Vector3.ZERO
	await frames(10)
	var entered := await walk_to(cell, &"move_forward", outside_wall + 0.90, true)
	check(entered and otis.is_on_floor() and absf(otis.global_position.y) < 0.03,
		"Otis walks through cell %s's shell opening onto the connected floor" % letter)
	var returned := await walk_to(cell, &"move_back", -0.55, false)
	check(returned and otis.is_on_floor() and absf(otis.global_position.y) < 0.03,
		"Otis walks back through cell %s's opening into the hall" % letter)

func walk_to(cell: Node3D, action: StringName, depth: float, entering: bool) -> bool:
	Input.action_press(action)
	for frame in 90:
		await physics_frame
		var at := cell.to_local(otis.global_position).z
		if (entering and at >= depth) or (not entering and at <= depth):
			Input.action_release(action)
			return true
	Input.action_release(action)
	return false

func blocked(cell: Node3D, from: Vector3, to: Vector3) -> bool:
	return not ray(cell.to_global(from), cell.to_global(to)).is_empty()

func ray(from: Vector3, to: Vector3) -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(from, to, otis.collision_mask, [otis.get_rid()])
	return otis.get_world_3d().direct_space_state.intersect_ray(query)

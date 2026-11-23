extends SceneTree

# Headless uses the native controller, with only the pointer-capture prerequisite bypassed.
class HeadlessLocomotion extends OtisLocomotion:
	func input_active() -> bool:
		return actor.controls_enabled

const PAD := Vector3(0, 0, 12.0)
const PLATFORM_SIZE := Vector3(4.0, 0.12, 3.5)
const RISE := 1.6
const MAST_EYE := Vector3.UP * 1.35

var facility: Node3D
var hall: Node3D
var actor: OtisController
var crane: BridgeCrane
var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func frames(count: int) -> void:
	for frame in count:
		await physics_frame

func check(condition: bool, note: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(note)

func run() -> void:
	facility = preload("res://scenes/facility.tscn").instantiate()
	facility.chassis_seed = 42
	root.add_child(facility)
	current_scene = facility
	actor = facility.get_node("Otis")
	hall = facility.get_node("EngineeringTestHall")
	crane = facility.overhead_crane
	if DisplayServer.get_name() == "headless":
		actor.remove_child(actor.locomotion)
		actor.locomotion.free()
		actor.locomotion = HeadlessLocomotion.new()
		actor.add_child(actor.locomotion)
	await frames(12)
	await test_stationary_floor()
	await test_suspended_platform()
	await test_unstable_platform()
	await test_camera_only()
	await test_rotating_support()
	await test_lateral_contact()
	facility.queue_free()
	await frames(3)
	print("RD-015D moving platforms: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func new_stock(title: String, size: Vector3, kg: float, at: Vector3) -> InteractableObject:
	var item := InteractableObject.new()
	item.name = title
	item.definition = ObjectDefinition.new()
	item.definition.display_name = title
	item.definition.mass_kg = kg
	item.definition.mobility = ObjectDefinition.Mobility.MOVABLE
	item.definition.properties[&"center_of_mass_local"] = Vector3.ZERO
	var collider := CollisionShape3D.new()
	collider.name = "CollisionShape3D"
	var box := BoxShape3D.new()
	box.size = size
	collider.shape = box
	item.add_child(collider)
	item.position = at
	hall.add_child(item)
	item.lock_rotation = false
	return item

func add_suspension_mast(platform: InteractableObject) -> void:
	# Elevate the attachment above the combined center of mass so the rider's
	# off-center weight can tilt the fixture without overturning it.
	var mast := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.16, 1.29, 0.16)
	mast.shape = shape
	mast.position.y = MAST_EYE.y - shape.size.y * 0.5
	platform.add_child(mast)

func stand_over(point: Vector3) -> void:
	actor.global_transform = Transform3D(Basis.IDENTITY, point + Vector3.UP * 0.03)
	actor.velocity = Vector3.ZERO
	actor.camera.rotation = Vector3.ZERO

func park_actor() -> void:
	stand_over(Vector3(0, 0, 4.0))
	await frames(8)

func mount_hook(item: InteractableObject, local_eye := Vector3.UP * 0.06) -> bool:
	crane.clear_controls()
	var eye := item.to_global(local_eye)
	var at := hall.to_local(eye) + Vector3.UP * 0.99
	crane.trolley.position = at.x
	crane.bridge.position = at.z
	crane.trolley.velocity = 0.0
	crane.bridge.velocity = 0.0
	crane.suspension.height = at.y
	crane.suspension.velocity = 0.0
	crane.suspension.request_height(at.y)
	var pose := Transform3D(hall.global_basis, hall.to_global(at))
	crane.hook.global_transform = pose
	crane.hook.linear_velocity = Vector3.ZERO
	crane.hook.angular_velocity = Vector3.ZERO
	PhysicsServer3D.body_set_state(crane.hook.get_rid(), PhysicsServer3D.BODY_STATE_TRANSFORM, pose)
	await frames(15)
	var issue := crane.attach_load(item, eye)
	check(issue.is_empty() and crane.rigged_body() == item, "Existing hook rigs " + item.name + ": " + issue)
	return issue.is_empty()

func test_stationary_floor() -> void:
	var floor := new_stock("Resting platform", PLATFORM_SIZE, 220.0, PAD + Vector3.UP * 0.09)
	await frames(50)
	var before := floor.global_transform
	stand_over(floor.to_global(Vector3(0.45, 0.06, 0.25)))
	await frames(60)
	check(actor.is_on_floor(), "Otis has standing contact on the stationary rigid platform")
	check(before.origin.distance_to(floor.global_position) < 0.035
		and floor.angular_velocity.length() < 0.10, "Idle standing keeps a supported rigid body stationary")
	await park_actor()
	floor.queue_free()
	await frames(3)

func test_suspended_platform() -> void:
	var floor := new_stock("Suspended platform", PLATFORM_SIZE, 360.0, PAD + Vector3.UP * 0.09)
	add_suspension_mast(floor)
	await frames(48)
	if not await mount_hook(floor, MAST_EYE):
		floor.queue_free()
		await frames(3)
		return
	stand_over(floor.to_global(Vector3(0.62, 0.06, 0.0)))
	await frames(40)
	var floor_start := floor.global_position.y
	var actor_start := actor.global_position.y
	crane.adjust_hook_steps(RISE / crane.hoist_step, false)
	var max_angular_speed := 0.0
	var max_vertical_speed := 0.0
	var max_rider_speed := 0.0
	for frame in 310:
		await physics_frame
		max_angular_speed = maxf(max_angular_speed, floor.angular_velocity.length())
		max_vertical_speed = maxf(max_vertical_speed, absf(floor.linear_velocity.y))
		max_rider_speed = maxf(max_rider_speed, actor.get_real_velocity().y)
	var floor_rise := floor.global_position.y - floor_start
	var actor_rise := actor.global_position.y - actor_start
	var foot := floor.to_local(actor.global_position)
	check(floor_rise > 1.12 and max_vertical_speed < 1.6,
		"Occupied crane platform rises under load without jumping (rise %.3f, peak speed %.3f)" % [floor_rise, max_vertical_speed])
	check(actor_rise > 1.10 and actor.is_on_floor() and absf(foot.y - 0.06) < 0.13
		and actor.global_transform.is_finite() and max_angular_speed < 2.5,
		"Otis rides the platform upward with stable contact (rise %.3f, foot Y %.3f)" % [actor_rise, foot.y])

	check(max_rider_speed > 0.4 and max_rider_speed < 2.6,
		"Vertical platform velocity reaches the standing rider without a recovery spike (%.3f m/s)" % max_rider_speed)
	var average_tension := 0.0
	for frame in 90:
		await physics_frame
		average_tension += crane.rigging.tension_newtons / 90.0
	var estimated_rider_mass := average_tension / actor.gravity - floor.mass
	check(estimated_rider_mass > actor.supporting_load_kg() * 0.50
		and estimated_rider_mass < actor.supporting_load_kg() * 1.65,
		"Standing rider adds finite weight to the strap (%.1f kg equivalent)" % estimated_rider_mass)

	var before_walk := floor.to_local(actor.global_position)
	Input.action_press(&"move_back")
	await frames(14)
	Input.action_release(&"move_back")
	await frames(14)
	var after_walk := floor.to_local(actor.global_position)
	check(actor.is_on_floor() and after_walk.z - before_walk.z > 0.22 and floor.angular_velocity.length() < 2.5,
		"Otis can walk relative to the suspended floor without an excessive platform kick")
	crane.set_controls(1, 0, true)
	await frames(54)
	var before_jump := actor.global_position
	var support_velocity := actor.get_platform_velocity()
	check(actor.locomotion.request_jump(), "Otis can jump from the moving rigid floor")
	await physics_frame
	check(not actor.is_on_floor() and support_velocity.x > 0.06
		and absf(actor.velocity.x - support_velocity.x) < 0.075,
		"The rider inherits the floor's lateral velocity at takeoff")
	await frames(9)
	check(not actor.is_on_floor() and actor.global_position.y > before_jump.y + 0.15,
		"Jump detaches standing contact naturally")
	crane.clear_controls()
	await park_actor()
	crane.detach_load()
	floor.queue_free()
	await frames(3)

func test_unstable_platform() -> void:
	var floor := new_stock("Low lifting point", PLATFORM_SIZE, 360.0, PAD + Vector3.UP * 0.09)
	await frames(48)
	if not await mount_hook(floor):
		floor.queue_free()
		await frames(3)
		return
	stand_over(floor.to_global(Vector3(0.74, 0.06, 0.0)))
	await frames(28)
	crane.adjust_hook_steps(RISE / crane.hoist_step, false)
	var steepest_normal := 1.0
	for frame in 280:
		await physics_frame
		steepest_normal = minf(steepest_normal, floor.global_basis.y.dot(Vector3.UP))
	check(steepest_normal < 0.65 and actor.global_position.y - hall.global_position.y < 0.20
		and floor.global_position.y > actor.global_position.y + 1.0,
		"A low unstable lifting point can tip under the rider and let Otis fall")
	await park_actor()
	crane.detach_load()
	floor.queue_free()
	await frames(3)

func test_camera_only() -> void:
	var floor := new_stock("Cage floor", PLATFORM_SIZE, 360.0, PAD + Vector3.UP * 0.09)
	add_suspension_mast(floor)
	await frames(48)
	var walls: Array[InteractableObject] = []
	for side: float in [-1.0, 1.0]:
		var wall := new_stock("Cage side", Vector3(0.09, 1.65, 2.5), 65.0,
			hall.to_local(floor.global_position) + Vector3(side * 2.045, 0.81, 0))
		wall.gravity_scale = 0.0
		walls.append(wall)
		await frames(7)
		var fastening: FasteningSystem = facility.fastening
		var bolt := fastening.create_round(FasteningTool.GRADES[0])
		var contact := floor.global_position + Vector3(side * 2.5, 0.025, 0)
		var issue := fastening.install(bolt, contact, Vector3(-side, 0, 0), 1.0)
		check(issue.is_empty() and floor.fastened and wall.fastened, "Camera fixture is a bolted cage: " + issue)
		wall.gravity_scale = 1.0
	if not await mount_hook(floor, MAST_EYE):
		for wall in walls:
			wall.queue_free()
		floor.queue_free()
		await frames(3)
		return
	crane.adjust_hook_steps(15.0, false)
	await frames(255)
	stand_over(floor.to_global(Vector3(1.52, 0.06, 0)))
	await frames(95)
	var idle_linear := 0.0
	var idle_angular := 0.0
	for frame in 75:
		await physics_frame
		idle_linear = maxf(idle_linear, floor.linear_velocity.length())
		idle_angular = maxf(idle_angular, floor.angular_velocity.length())
	check(actor.is_on_floor() and absf(floor.to_local(actor.global_position).y - 0.06) < 0.14
		and floor.global_position.y > 1.0, "Otis stands inside the cage while it is suspended")
	var camera_basis := actor.camera.global_basis
	var max_pitch := 0.0
	var moved_linear := 0.0
	var moved_angular := 0.0
	for frame in 75:
		var look := InputEventMouseMotion.new()
		look.relative = Vector2(18.0, 30.0 if frame < 37 else -30.0)
		actor._unhandled_input(look)
		await physics_frame
		moved_linear = maxf(moved_linear, floor.linear_velocity.length())
		moved_angular = maxf(moved_angular, floor.angular_velocity.length())
		max_pitch = maxf(max_pitch, absf(actor.camera.rotation.x))
	check(not camera_basis.is_equal_approx(actor.camera.global_basis) and max_pitch > 1.4,
		"Real mouse-look path changes yaw and looks nearly vertical")
	check(moved_linear <= idle_linear + 0.14 and moved_angular <= idle_angular + 0.18,
		"Camera-only motion adds no arbitrary platform acceleration (linear %.3f → %.3f, angular %.3f → %.3f)" % [
			idle_linear, moved_linear, idle_angular, moved_angular])
	check(walls.all(func(wall: InteractableObject) -> bool: return wall.assembly_root() == floor)
		and crane.rigged_body() == floor and not floor.freeze and actor.global_transform.is_finite()
		and actor.is_on_floor() and absf(floor.to_local(actor.global_position).y - 0.06) < 0.14,
		"Camera turns keep the cage attached and Otis standing without penetration")
	await park_actor()
	crane.detach_load()
	for wall in walls:
		wall.queue_free()
	floor.queue_free()
	await frames(3)

func test_rotating_support() -> void:
	var floor := new_stock("Rotating support", PLATFORM_SIZE, 400.0, PAD + Vector3.UP * 2.0)
	# Isolate point-velocity following from slab friction while keeping the body dynamic.
	floor.gravity_scale = 0.0
	await frames(4)
	stand_over(floor.to_global(Vector3(1.1, 0.06, 0.30)))
	await frames(18)
	var before := floor.to_local(actor.global_position)
	var at := actor.global_position
	floor.angular_velocity = Vector3.UP * 0.43
	await frames(45)
	var after := floor.to_local(actor.global_position)
	check(actor.is_on_floor() and Vector2(before.x - after.x, before.z - after.z).length() < 0.15
		and Vector2(actor.global_position.x - at.x, actor.global_position.z - at.z).length() > 0.21,
		"Yawing support carries Otis around its actual off-center contact point")
	await park_actor()
	floor.queue_free()
	await frames(3)


func test_lateral_contact() -> void:
	stand_over(hall.to_global(Vector3(0, 0, 11.5)))
	var driver := new_stock("Moving contact body", Vector3(0.6, 1.0, 0.9), 400.0, Vector3(-1.5, 0.8, 11.5))
	driver.gravity_scale = 0.0
	driver.linear_damp = 0.0
	driver.lock_rotation = true
	await frames(20)
	driver.linear_velocity = Vector3.RIGHT * 2.5
	var largest_overlap := 0.0
	for frame in 125:
		await physics_frame
		var separation := actor.global_position.x - driver.global_position.x
		largest_overlap = maxf(largest_overlap, 0.6 - separation)
	check(driver.global_position.x > 2.0 and actor.global_position.x > driver.global_position.x + 0.45
		and actor.is_on_floor() and largest_overlap < 0.09,
		"A sideways moving body displaces Otis without stalling or sustained overlap")
	await park_actor()
	driver.queue_free()
	await frames(3)

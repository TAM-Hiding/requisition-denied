class_name StructuralTestRam
extends Node3D

const FORCE_STEPS := [60.0, 120.0, 240.0, 400.0, 800.0, 1800.0, 5000.0, 10000.0, 16000.0, 24000.0]
const SPEED := 0.42
const STROKE := 4.35
enum Drive { IDLE, EXTEND, RETRACT }
var system: FasteningSystem
var face: AnimatableBody3D
var readout: Label3D
var drive := Drive.IDLE
var force_index := 2
var travel := 0.0
var actual_load := 0.0
var displacement := 0.0
var stalled := false
var specimen: PhysicsBody3D
var specimen_start := Vector3.ZERO

func force_limit() -> float:
	return FORCE_STEPS[force_index]

func toggle_drive() -> void:
	drive = Drive.RETRACT if drive == Drive.EXTEND or (drive == Drive.IDLE and travel > 0.0) else Drive.EXTEND

func change_force(steps: int) -> void:
	force_index = clampi(force_index + steps, 0, FORCE_STEPS.size() - 1)

func reset_ram() -> void:
	actual_load = 0.0
	system.last_load = 0.0
	stalled = false
	specimen = null
	displacement = 0.0
	drive = Drive.RETRACT

func _physics_process(delta: float) -> void:
	actual_load = 0.0
	stalled = false
	if drive != Drive.IDLE:
		step_drive(delta)
	if is_instance_valid(specimen):
		displacement = specimen.global_position.distance_to(specimen_start)
	if readout != null:
		readout.text = "STRUCTURAL TEST RAM\n%.0f SET  /  %.0f APPLIED\n%.2f m  /  %s" % [
			force_limit(), actual_load, travel, "STALL" if stalled else Drive.keys()[drive]]

func step_drive(delta: float) -> void:
	var axis := global_basis.x.normalized()
	var desired := move_toward(travel, STROKE if drive == Drive.EXTEND else 0.0, SPEED * delta)
	var motion := PhysicsTestMotionParameters3D.new()
	motion.from = face.global_transform
	motion.motion = axis * (desired - travel)
	motion.margin = 0.003
	motion.recovery_as_collision = true
	var contact := PhysicsTestMotionResult3D.new()
	var hit := PhysicsServer3D.body_test_motion(face.get_rid(), motion, contact)
	var fraction := contact.get_collision_safe_fraction() if hit else 1.0
	travel = lerpf(travel, desired, fraction)
	face.position.x = travel
	if hit:
		stalled = true
		if drive != Drive.EXTEND:
			return
		var body := FasteningSystem.logical_body(contact.get_collider(), contact.get_collider_shape())
		if not is_instance_valid(body) or not system.compatible(body):
			return
		if specimen != body:
			specimen = body
			specimen_start = body.global_position
		var root := system.physics_root(body) as RigidBody3D
		actual_load = force_limit()
		if is_instance_valid(root) and not root.freeze:
			var required := maxf(0.0, SPEED - root.linear_velocity.dot(axis)) * root.mass / maxf(delta, 0.0001)
			actual_load = minf(actual_load, required)
		if not system.anchored(body):
			system.apply_structural_load(body, contact.get_collision_point(), axis * actual_load)
		root = system.physics_root(body) as RigidBody3D
		if is_instance_valid(root) and not root.freeze:
			# The kinematic face does not shove contacts itself. The only drive
			# on a free specimen is this explicit, force- and speed-capped impulse.
			var delta_speed := maxf(0.0, SPEED - root.linear_velocity.dot(axis))
			root.apply_central_impulse(axis * minf(actual_load * delta, delta_speed * root.mass))
	elif is_equal_approx(travel, 0.0) or is_equal_approx(travel, STROKE):
		drive = Drive.IDLE

func hud_text() -> String:
	return "RAM  %.0f / %.0f APPLIED  |  %.2f m  |  Δ %.2f m  |  %s  |  %d ACTIVE / %d FAILED · GROUP %d" % [
		actual_load, force_limit(), travel, displacement, "STALL" if stalled else Drive.keys()[drive],
		system.installed_count(), system.failed.size(), system.last_failed_group]

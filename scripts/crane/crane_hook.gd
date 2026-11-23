class_name CraneHook
extends RigidBody3D
## The block collides in Jolt. The single cable acts through its swivel axis.

const BLOCK_OFFSET := Vector3(0.014, 0.0, 0.009)
const HOOK_EYE := Vector3(0, -0.34, 0)

var tension_newtons := 0.0
var slack_m := 0.0

func _ready() -> void:
	set_meta(&"no_crane_lift", true)
	set_meta(&"no_fasteners", true)
	mass = CraneSuspension.NOMINAL_BLOCK_MASS_KG
	center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector3.ZERO
	# The swivel carries yaw; the pendulum angle lives in the suspension.
	axis_lock_angular_x = true
	axis_lock_angular_z = true
	inertia = Vector3(12.0, 12.0, 12.0)
	linear_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	linear_damp = 0.34
	angular_damp_mode = RigidBody3D.DAMP_MODE_REPLACE
	angular_damp = 0.75
	can_sleep = false
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 8
	collision_layer = 1 | 16
	collision_mask = 1 | 2 | 16
	_shape(Vector3(0.49, 0.34, 0.38), Vector3(0, 0.061, 0))
	_shape(Vector3(0.35, 0.39, 0.17), Vector3(0, -0.285, 0))


func enforce_cable(anchor: Vector3, paid_length: float, delta: float, supported_mass: float) -> void:
	tension_newtons = 0.0
	var offset := global_position - anchor
	var distance := offset.length()
	slack_m = maxf(paid_length - distance, 0.0)
	if distance < 0.001 or not is_finite(distance):
		return
	var radial := offset / distance
	var state := PhysicsServer3D.body_get_direct_state(get_rid())
	var v := state.linear_velocity if state != null else linear_velocity
	var along := v.dot(radial)
	# Predict crossing the paid-out length. Apply only an inward correction.
	var inward_speed := cable_inward_speed(paid_length, distance, delta)
	var budget := maxf(mass, supported_mass) * 55.0 * delta
	var impulse := clampf((along + inward_speed) * mass, 0.0, budget)
	if impulse > 0.0:
		apply_central_impulse(-radial * impulse)
		tension_newtons = impulse / delta


func cable_inward_speed(paid_length: float, distance: float, delta: float) -> float:
	var allowed := minf((paid_length - distance) / delta, 8.0)
	return minf(-allowed * 0.60, 2.0) if allowed < 0.0 else -allowed


func react_swivel(delta_velocity: Vector3, delta: float) -> void:
	var lever := global_basis * BLOCK_OFFSET
	var impulse := lever.cross(-mass * delta_velocity).y
	# Bearing friction acts in the direction opposite rotation.
	var omega := angular_velocity.y
	var friction := minf(absf(omega) * inertia.y, 0.09 * inertia.y * delta)
	apply_torque_impulse(Vector3.UP * (impulse - signf(omega) * friction))


func _shape(size: Vector3, offset: Vector3) -> void:
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collider.shape = box
	collider.position = offset
	add_child(collider)

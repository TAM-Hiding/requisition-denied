class_name CraneSuspension
extends RefCounted
## Unloaded hoist. Positive velocity raises the hook, shortening the commanded suspension.

const NOMINAL_BLOCK_MASS_KG := 225.0
# Center-of-mass eccentricity of the hook and latch under the swivel bearing.
const BLOCK_OFFSET := Vector3(0.014, 0.0, 0.009)

var outlet_height: float
var minimum_length: float
var maximum_length: float
var height: float
var target: float
var velocity := 0.0
var swivel_yaw := 0.0
var swivel_velocity := 0.0

var swivel_inertia := 12.0
var swivel_friction := 0.09
var swivel_damping := 0.75


func _init(outlet_y: float, shortest: float, longest: float, initial_height: float) -> void:
	outlet_height = outlet_y
	minimum_length = shortest
	maximum_length = longest
	request_height(initial_height)
	height = target


func length() -> float:
	return outlet_height - height


func request_height(value: float) -> void:
	target = clampf(value, outlet_height - maximum_length, outlet_height - minimum_length)


func stop(acceleration: float) -> void:
	# Continue only as far as braking requires when the remote disconnects.
	request_height(height + velocity * absf(velocity) / (2.0 * acceleration))


func apply_swivel_impulse(newton_meter_seconds: float) -> void:
	swivel_velocity += newton_meter_seconds / swivel_inertia


func react_to_carriage(delta_velocity: Vector3) -> void:
	var offset := BLOCK_OFFSET.rotated(Vector3.UP, swivel_yaw)
	var inertial_impulse := -NOMINAL_BLOCK_MASS_KG * delta_velocity
	apply_swivel_impulse(offset.cross(inertial_impulse).y)


func advance(delta: float, speed: float, acceleration: float, can_raise: bool, can_lower: bool) -> void:
	var distance := target - height
	var direction := signf(distance)
	var permitted := (direction > 0.0 and can_raise) or (direction < 0.0 and can_lower)
	var desired := direction * minf(speed, sqrt(2.0 * acceleration * absf(distance))) if permitted else 0.0
	velocity = move_toward(velocity, desired, acceleration * delta)
	var step := velocity * delta
	if direction == signf(step) and absf(step) >= absf(distance):
		height = target
		velocity = 0.0
	else:
		height = clampf(height + step, outlet_height - maximum_length, outlet_height - minimum_length)
		if is_equal_approx(height, outlet_height - maximum_length) and velocity < 0.0 \
				or is_equal_approx(height, outlet_height - minimum_length) and velocity > 0.0:
			velocity = 0.0

	swivel_velocity = move_toward(swivel_velocity, 0.0, swivel_friction * delta)
	swivel_velocity *= exp(-swivel_damping * delta)
	swivel_yaw = wrapf(swivel_yaw + swivel_velocity * delta, -PI, PI)

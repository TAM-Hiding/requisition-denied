class_name CraneSuspension
extends RefCounted
## Hoist motor. Positive velocity reels in the paid-out suspension length.

const NOMINAL_BLOCK_MASS_KG := 225.0
var outlet_height: float
var minimum_length: float
var maximum_length: float
var height: float
var target: float
var velocity := 0.0


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

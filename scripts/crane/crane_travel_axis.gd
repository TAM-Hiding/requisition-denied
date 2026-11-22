class_name CraneTravelAxis
extends RefCounted
## Signed travel in meters and m/s. A stop reports the velocity immediately before contact.

const RELEASE_DISTANCE := 0.04

var lower: float
var upper: float
var position: float
var velocity := 0.0
var _contact := 0


func _init(minimum: float, maximum: float, initial: float) -> void:
	lower = minimum
	upper = maximum
	position = clampf(initial, lower, upper)


func advance(delta: float, demand: float, speed: float, acceleration: float, braking: float,
		can_move: Callable = Callable()) -> float:
	var desired := clampf(demand, -1.0, 1.0) * speed
	var reversing := velocity * desired < 0.0
	var slowing := reversing or absf(desired) < absf(velocity)
	velocity = move_toward(velocity, 0.0 if reversing else desired, delta * (braking if slowing else acceleration))
	var next := position + velocity * delta
	var clamped := clampf(next, lower, upper)
	if clamped != position and can_move.is_valid() and not can_move.call(clamped):
		velocity = 0.0
		return 0.0
	var impact := 0.0
	if (next >= upper and velocity > 0.0) or (next <= lower and velocity < 0.0):
		var side := 1 if velocity > 0.0 else -1
		if _contact != side:
			impact = velocity
		_contact = side
		velocity = 0.0
	position = clamped
	if (_contact > 0 and position < upper - RELEASE_DISTANCE) \
			or (_contact < 0 and position > lower + RELEASE_DISTANCE):
		_contact = 0
	return impact

class_name AndroidChassis
extends RefCounted
## Session-owned manufacturing values plus additive contributions from installed hardware.
enum Attribute { LIFT_KG, WALK_MPS, ACCELERATION_MPS2, MANIPULATION_NEWTONS, MASS_KG, STABILITY }
const NOMINAL := [40.0, 4.0, 18.0, 400.0, 80.0, 1.0]
const TOLERANCE := [0.10, 0.05, 0.08, 0.0, 0.05, 0.0]
var _base := PackedFloat64Array(NOMINAL)
var _contributions: Dictionary = {}

static func generate(seed_value: int) -> AndroidChassis:
	var chassis := AndroidChassis.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	for index in NOMINAL.size():
		chassis._base[index] = NOMINAL[index] * (1.0 + rng.randf_range(-TOLERANCE[index], TOLERANCE[index]))
	return chassis

func base(attribute: Attribute) -> float:
	return _base[attribute]

func effective(attribute: Attribute) -> float:
	var value := base(attribute)
	for contribution: Dictionary in _contributions.values():
		value += contribution.get(attribute, 0.0)
	return maxf(value, 0.0)

func set_contribution(component_id: StringName, adjustments: Dictionary) -> bool:
	if component_id.is_empty():
		return false
	for attribute: Variant in adjustments:
		var amount: Variant = adjustments[attribute]
		if typeof(attribute) != TYPE_INT or attribute < 0 or attribute >= NOMINAL.size():
			return false
		if typeof(amount) not in [TYPE_FLOAT, TYPE_INT] or not is_finite(float(amount)):
			return false
	if adjustments.is_empty():
		_contributions.erase(component_id)
	else:
		_contributions[component_id] = adjustments.duplicate()
	return true

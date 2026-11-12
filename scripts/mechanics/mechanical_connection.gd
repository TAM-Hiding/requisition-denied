class_name MechanicalConnection
extends Resource
## Authored constraint and optional deterministic failure rule.
enum Kind { FIXED, REVOLUTE, PRISMATIC }
enum FailureMode { DETACH }
@export var kind := Kind.FIXED
@export var axis := Vector3.UP
@export var limits := Vector2.ZERO
@export var failure_enabled := false
@export var failure_threshold := 0.0
@export var failure_mode := FailureMode.DETACH
@export_range(0.0, 1.0) var damaged_strength_factor := 0.65

func fails(impact: float, damaged: bool) -> bool:
	var strength := failure_threshold * (damaged_strength_factor if damaged else 1.0)
	return failure_enabled and failure_threshold > 0.0 and is_finite(impact) and impact > strength

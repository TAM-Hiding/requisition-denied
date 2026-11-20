class_name LocomotionLoad
extends RefCounted
## Piecewise-linear gameplay curves; no stamina or rigid-body force model.
const SAMPLES := [0.0, 0.25, 0.5, 0.7, 1.0]
const JUMP := [1.0, 0.85, 0.65, 0.45, 0.2]
const SPRINT := [1.0, 0.95, 0.85, 0.75, 0.55]

static func curve(ratio: float, values: Array) -> float:
	var value := clampf(ratio, 0.0, 1.0)
	for index in range(1, SAMPLES.size()):
		if value <= SAMPLES[index]:
			return lerpf(values[index - 1], values[index],
				(value - SAMPLES[index - 1]) / (SAMPLES[index] - SAMPLES[index - 1]))
	return values.back()

static func modifiers(mass_kg: float, capacity_kg: float, jump_factors: Array = JUMP,
		sprint_factors: Array = SPRINT) -> Dictionary:
	var ratio := maxf(mass_kg, 0.0) / maxf(capacity_kg, 0.001)
	var overload := maxf(0.15, 1.0 / (1.0 + maxf(0.0, ratio - 1.0) * 0.5))
	var jump_values: Array = jump_factors if jump_factors.size() == SAMPLES.size() else JUMP
	var sprint_values: Array = sprint_factors if sprint_factors.size() == SAMPLES.size() else SPRINT
	return {"ratio": ratio, "jump": maxf(0.05, curve(ratio, jump_values)) * overload,
		"sprint": maxf(0.05, curve(ratio, sprint_values)) * overload,
		"walk": lerpf(1.0, 0.75, clampf(ratio, 0, 1)) * overload,
		"acceleration": lerpf(1.0, 0.7, clampf(ratio, 0, 1)) * overload}

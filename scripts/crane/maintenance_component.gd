class_name MaintenanceComponent
extends Node3D
## State and presentation for one independently serviceable machine component.
signal condition_changed
signal repaired

enum Condition { OPERATIONAL, DAMAGED, BROKEN }

var component_id: StringName
var display_name: String
var condition := Condition.OPERATIONAL
var fault := ""
## A future equipment station may provide tools, authorizations or replacement parts.
## Return an empty string when repair is allowed, or a reason to show to the operator.
var repair_requirement: Callable

var smoke: CPUParticles3D
var sparks: CPUParticles3D

func configure(id: StringName, label: String) -> void:
	component_id = id
	display_name = label
	name = String(id)
	smoke = _make_smoke()
	sparks = _make_sparks()
	add_child(smoke)
	add_child(sparks)
	_update_effects()

func apply_damage(next: Condition, reason: String) -> void:
	if next < condition or next == Condition.OPERATIONAL:
		return
	condition = next
	fault = reason
	_update_effects()
	condition_changed.emit()

func is_broken() -> bool:
	return condition == Condition.BROKEN

func repair_issue() -> String:
	if condition == Condition.OPERATIONAL:
		return "Component is operational."
	return String(repair_requirement.call(self)) if repair_requirement.is_valid() else ""

func repair() -> String:
	var issue := repair_issue()
	if not issue.is_empty():
		return issue
	condition = Condition.OPERATIONAL
	fault = ""
	_update_effects()
	condition_changed.emit()
	repaired.emit()
	return ""

func condition_label() -> String:
	return String(Condition.keys()[condition]).capitalize()

func inspection_text() -> String:
	var issue := repair_issue()
	return "Condition: %s\nFault: %s\nRepair: %s" % [
		condition_label(), fault if not fault.is_empty() else "None",
		issue if not issue.is_empty() else "Available. Press E to repair."]

func _make_smoke() -> CPUParticles3D:
	var effect := CPUParticles3D.new()
	effect.name = "Smoke"
	effect.emitting = false
	effect.amount = 7
	effect.lifetime = 1.2
	effect.direction = Vector3.UP
	effect.spread = 23.0
	effect.gravity = Vector3(0, 0.65, 0)
	effect.initial_velocity_min = 0.18
	effect.initial_velocity_max = 0.38
	effect.scale_amount_min = 0.8
	effect.scale_amount_max = 1.45
	var mesh := SphereMesh.new()
	mesh.radius = 0.12
	mesh.height = 0.24
	mesh.radial_segments = 6
	mesh.rings = 3
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	mesh.material = material
	effect.mesh = mesh
	return effect

func _make_sparks() -> CPUParticles3D:
	var effect := CPUParticles3D.new()
	effect.name = "Sparks"
	effect.emitting = false
	effect.lifetime = 0.30
	effect.direction = Vector3.UP
	effect.spread = 65.0
	effect.gravity = Vector3(0, -6.0, 0)
	effect.initial_velocity_min = 0.5
	effect.initial_velocity_max = 1.7
	effect.scale_amount_min = 0.55
	effect.scale_amount_max = 1.25
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.025, 0.075, 0.025)
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.vertex_color_use_as_albedo = true
	mesh.material = material
	effect.mesh = mesh
	return effect

func _update_effects() -> void:
	if condition == Condition.OPERATIONAL:
		smoke.emitting = false
		sparks.emitting = false
		# Turning visibility off also clears any already emitted particles on repair.
		smoke.hide()
		sparks.hide()
		return
	var broken := is_broken()
	var haze := Gradient.new()
	haze.colors = PackedColorArray([Color(0.05, 0.05, 0.06, 0.85) if broken else Color(0.45, 0.46, 0.47, 0.54),
		Color(0.05, 0.05, 0.06, 0.0) if broken else Color(0.45, 0.46, 0.47, 0.0)])
	smoke.color_ramp = haze
	smoke.amount = 15 if broken else 7
	sparks.amount = 10 if broken else 2
	sparks.lifetime = 0.34 if broken else 0.9
	var spark_fade := Gradient.new()
	spark_fade.offsets = PackedFloat32Array([0.0, 0.24, 0.34, 1.0])
	spark_fade.colors = PackedColorArray([Color("ffed93"), Color("ffad51"), Color(1, 0.4, 0.1, 0), Color(1, 0.4, 0.1, 0)])
	sparks.color_ramp = spark_fade
	smoke.show()
	sparks.show()
	smoke.restart()
	sparks.restart()
	smoke.emitting = true
	sparks.emitting = true

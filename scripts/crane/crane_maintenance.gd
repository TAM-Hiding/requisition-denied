class_name CraneMaintenance
extends Node3D
## Maps a qualifying crane impact to an inspectable maintenance event.
signal event_recorded(event: Dictionary)

const COMPONENTS := {
	&"trolley_drive_a": "Trolley drive A",
	&"trolley_drive_b": "Trolley drive B",
	&"hoist_motor": "Hoist motor",
	&"hoist_brake": "Hoist brake",
	&"bridge_roller_a": "Bridge roller A",
	&"bridge_roller_b": "Bridge roller B",
	&"bridge_drive_a": "Bridge drive A",
	&"bridge_drive_b": "Bridge drive B",
}
const LABELS := ["TROL A", "TROL B", "MOTOR", "BRAKE", "ROLL A", "ROLL B", "DRV A", "DRV B"]

@export_range(1, 30, 1) var impact_threshold := 4
var impact_count := 0
var events: Array[Dictionary] = []
var components: Dictionary[StringName, MaintenanceComponent] = {}
var access_panel: Node3D
var random := RandomNumberGenerator.new()

func configure(effect_anchors: Dictionary) -> void:
	for id: StringName in COMPONENTS:
		var part := MaintenanceComponent.new()
		part.configure(id, COMPONENTS[id])
		var anchor := effect_anchors.get(id) as Node3D
		(anchor if is_instance_valid(anchor) else self).add_child(part)
		components[id] = part

func component(id: StringName) -> MaintenanceComponent:
	return components.get(id)

func register_impact(axis: StringName, side: int, speed: float) -> bool:
	if axis not in [&"trolley", &"bridge"] or components.is_empty() or _has_broken_component():
		return false
	impact_count += 1
	if impact_count < impact_threshold:
		return false
	impact_count = 0
	var fault := "Repeated high-speed %s travel into the %s end stop." % [
		axis, "positive" if side > 0 else "negative"]
	var affected := _select_components(axis, side)
	for index in affected.size():
		var broken := index == 0 or (index > 1 and random.randf() < 0.28)
		component(affected[index]).apply_damage(
			MaintenanceComponent.Condition.BROKEN if broken else MaintenanceComponent.Condition.DAMAGED, fault)
	var event := {"axis": axis, "side": side, "speed": speed, "components": affected, "fault": fault}
	events.append(event)
	event_recorded.emit(event.duplicate(true))
	return true

func motion_allowed(axis: StringName, direction: float) -> bool:
	if components.is_empty():
		return true
	match axis:
		&"trolley":
			return not _any_broken([&"trolley_drive_a", &"trolley_drive_b"])
		&"bridge":
			return not _any_broken([&"bridge_drive_a", &"bridge_drive_b", &"bridge_roller_a", &"bridge_roller_b"])
		&"hoist":
			return not component(&"hoist_brake").is_broken() 				and (direction <= 0.0 or not component(&"hoist_motor").is_broken())
	return true

func status_text() -> String:
	var warnings := PackedStringArray()
	for part in components.values():
		if part.condition != MaintenanceComponent.Condition.OPERATIONAL:
			warnings.append("%s · %s" % [part.display_name, part.condition_label()])
	if not warnings.is_empty():
		return "\n".join(warnings)
	return "" if impact_count == 0 else "End-stop impacts %d/%d" % [impact_count, impact_threshold]

func install_service_access(hall: Node3D) -> Node3D:
	access_panel = Node3D.new()
	access_panel.name = "CraneServiceAccess"
	access_panel.position = Vector3(1.95, 1.50, 0.155)
	hall.add_child(access_panel)
	MaintenanceAccessPoint.add_box(access_panel, "Cabinet", Vector3(1.43, 0.65, 0.14),
		Vector3(0, 0, -0.047), Color("303d42"))
	MaintenanceAccessPoint.add_label(access_panel, "OC-01  /  CRANE SERVICE", Vector3(0, 0.239, 0.031), 0.00165)
	var index := 0
	for id: StringName in COMPONENTS:
		var point := MaintenanceAccessPoint.new()
		point.configure(component(id), LABELS[index])
		point.position = Vector3((index % 4 - 1.5) * 0.32, 0.065 if index < 4 else -0.125, 0.04)
		access_panel.add_child(point)
		index += 1
	return access_panel

func _has_broken_component() -> bool:
	return _any_broken(components.keys())

func _any_broken(ids: Array) -> bool:
	for id: StringName in ids:
		if component(id).is_broken():
			return true
	return false

func _select_components(axis: StringName, side: int) -> Array[StringName]:
	var primary: StringName
	var weights: Dictionary[StringName, float] = {}
	for id: StringName in COMPONENTS:
		weights[id] = 1.0
	if axis == &"trolley":
		primary = &"trolley_drive_b" if side > 0 else &"trolley_drive_a"
		weights[&"trolley_drive_a"] = 8.0
		weights[&"trolley_drive_b"] = 8.0
		weights[&"hoist_motor"] = 4.0
		weights[&"hoist_brake"] = 4.0
	else:
		primary = &"bridge_drive_b" if side > 0 else &"bridge_drive_a"
		weights[&"bridge_drive_a"] = 7.0
		weights[&"bridge_drive_b"] = 7.0
		weights[&"bridge_roller_a"] = 6.0
		weights[&"bridge_roller_b"] = 6.0
		# A directional stop loads the corresponding drive group first.
		weights[&"bridge_roller_b" if side > 0 else &"bridge_roller_a"] = 9.0
	var selected: Array[StringName] = [primary]
	weights.erase(primary)
	for unused in random.randi_range(2, 4):
		var total := 0.0
		for weight in weights.values():
			total += weight
		var roll := random.randf() * total
		var chosen: StringName
		for id in weights:
			chosen = id
			roll -= weights[id]
			if roll <= 0.0:
				break
		selected.append(chosen)
		weights.erase(chosen)
	return selected

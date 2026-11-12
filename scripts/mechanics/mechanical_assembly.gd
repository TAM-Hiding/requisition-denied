class_name MechanicalAssembly
extends Node3D

enum Configuration { COMPLETE, EXPOSED, INCOMPLETE }
@export var power_source: PowerSourceDefinition
@export var disabled := false

func mount(mount_id: StringName) -> MechanicalMount:
	for child in get_children():
		if child is MechanicalMount and child.definition != null and child.definition.mount_id == mount_id:
			return child
	return null

func add_mount(definition: MountDefinition) -> MechanicalMount:
	if definition == null or definition.mount_id == &"" or mount(definition.mount_id) != null:
		return null
	var socket := MechanicalMount.new()
	socket.name = definition.mount_id
	socket.definition = definition
	add_child(socket)
	return socket

func operational() -> bool:
	if disabled or (get_parent() is MechanicalComponent and get_parent().integrity == MechanicalComponent.Integrity.BROKEN):
		return false
	for child in get_children():
		if child is MechanicalMount and child.definition.required_for_operation:
			if not is_instance_valid(child.occupant) or child.occupant.integrity == MechanicalComponent.Integrity.BROKEN:
				return false
	return true

func available_stage() -> int:
	return power_source.stage if power_source != null and operational() else PowerSourceDefinition.Stage.NONE

func supplies(consumer: PowerConsumerDefinition) -> bool:
	return power_source != null and power_source.can_supply(consumer, operational())

func configuration() -> Configuration:
	var exposed := false
	for child in get_children():
		if child is MechanicalMount and not is_instance_valid(child.occupant):
			if child.definition.required_for_operation:
				return Configuration.INCOMPLETE
			if child.definition.connection != null and child.definition.connection.kind == MechanicalConnection.Kind.FIXED:
				exposed = true
	return Configuration.EXPOSED if exposed else Configuration.COMPLETE

func configuration_text() -> String:
	var lines := PackedStringArray(["Configuration: %s" % Configuration.keys()[configuration()].capitalize()])
	for child in get_children():
		if child is MechanicalMount:
			var component_name: String = child.occupant.definition.display_name if is_instance_valid(child.occupant) else "vacant"
			lines.append("%s  %s" % [child.definition.mount_id, component_name])
	if power_source != null:
		lines.append("Power: Stage %d available" % available_stage() if operational() else "Power: unavailable")
	return "\n".join(lines)

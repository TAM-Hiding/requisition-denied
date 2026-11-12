class_name MechanicalComponent
extends InteractableObject

enum Integrity { INTACT, DAMAGED, BROKEN }
@export var profile: ComponentProfile
@export var integrity := Integrity.INTACT
var installed_mount: MechanicalMount
var seating_mount: MechanicalMount
var loose_parent: Node3D

func mobility() -> int:
	return ObjectDefinition.Mobility.FIXED if is_instance_valid(installed_mount) else super.mobility()

func set_mobility(value: ObjectDefinition.Mobility) -> bool:
	return not is_instance_valid(installed_mount) and super.set_mobility(value)

func query_actions() -> Array[StringName]:
	var actions := super.query_actions()
	if is_instance_valid(installed_mount) and installed_mount.definition.removable:
		actions.append(&"remove")
	return actions

func inspection_information() -> Dictionary:
	var info := super.inspection_information()
	info.description += "\n\nStructure: %s" % Integrity.keys()[integrity].capitalize()
	info.description += "\nMount: %s" % (installed_mount.definition.mount_id if is_instance_valid(installed_mount) else &"detached")
	for child in get_children():
		if child is MechanicalAssembly:
			info.description += "\n" + child.configuration_text()
	return info

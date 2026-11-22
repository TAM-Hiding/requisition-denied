class_name CraneRemote
extends InteractableObject
## A paired handheld device that uses the regular equipment slot and satchel.

var crane: BridgeCrane
var _indicator: StandardMaterial3D

func _ready() -> void:
	definition = ObjectDefinition.new()
	definition.object_id = &"RD-OC01-REMOTE"
	definition.display_name = "OC-01 crane remote"
	definition.description = "Wireless pendant paired to the hall's bridge crane. Equip it and press V inside the hall to connect."
	definition.mass_kg = 0.65
	definition.mobility = ObjectDefinition.Mobility.CARRYABLE

	var envelope := BoxShape3D.new()
	envelope.size = Vector3(0.125, 0.085, 0.242)
	var collider := CollisionShape3D.new()
	collider.name = "CollisionShape3D"
	collider.position.z = -0.021
	collider.shape = envelope
	add_child(collider)
	var profile := HeldItemProfile.new()
	profile.envelope = envelope
	profile.envelope_transform = collider.transform
	profile.anticipation_margin = 0.035
	definition.held_profile = profile

	var rubber := material(Color("252e34"))
	var color_coded_case := material(Color("be9446"))
	var keys := material(Color("3f5258"))
	box_part("PendantHousing", Vector3(0.104, 0.064, 0.189), Vector3.ZERO, color_coded_case)
	box_part("Face", Vector3(0.083, 0.007, 0.171), Vector3(0, 0.031, 0), rubber)
	for side in [-1.0, 1.0]:
		box_part("Bumper", Vector3(0.012, 0.071, 0.184), Vector3(side * 0.054, 0, 0), rubber)
		for z in [-0.027, 0.004, 0.035]:
			box_part("DriveKey", Vector3(0.022, 0.008, 0.019), Vector3(side * 0.018, 0.036, z), keys)
	box_part("StopButton", Vector3(0.023, 0.012, 0.017), Vector3(0, 0.035, 0.067), material(Color("bc5445")))
	box_part("Antenna", Vector3(0.016, 0.023, 0.048), Vector3(0.027, 0.008, -0.117), rubber)
	_indicator = material(Color("71563c"))
	box_part("LinkIndicator", Vector3(0.039, 0.004, 0.017), Vector3(0, 0.036, -0.064), _indicator)
	set_link_status(false)
	super._ready()

func in_range(actor: OtisController) -> bool:
	if not is_instance_valid(crane):
		return false
	var hall := crane.get_parent() as Node3D
	if hall == null:
		return false
	var point := hall.to_local(actor.global_position)
	return absf(point.x) < float(hall.get("width")) * 0.5 and point.z >= 0.0 and point.z < float(hall.get("depth"))

func set_link_status(linked: bool) -> void:
	if _indicator == null:
		return
	_indicator.albedo_color = Color("9bd5ad") if linked else Color("88704b")
	_indicator.emission_enabled = linked
	_indicator.emission = _indicator.albedo_color

func box_part(label: String, size: Vector3, at: Vector3, surface: Material) -> void:
	var part := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	part.mesh = mesh
	part.material_override = surface
	part.name = label
	part.position = at
	add_child(part)

func material(color: Color) -> StandardMaterial3D:
	var surface := StandardMaterial3D.new()
	surface.albedo_color = color
	surface.roughness = 0.80
	return surface

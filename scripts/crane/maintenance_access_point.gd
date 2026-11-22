class_name MaintenanceAccessPoint
extends InteractableObject
## Reachable service relay for an individual component mounted on inaccessible machinery.
const FACE_SIZE := Vector3(0.286, 0.158, 0.075)
var component: MaintenanceComponent
var indicator: MeshInstance3D

func configure(part: MaintenanceComponent, abbreviation: String) -> void:
	component = part
	name = String(part.component_id)
	definition = ObjectDefinition.new()
	definition.object_id = StringName("oc01_service_" + name)
	definition.display_name = part.display_name
	definition.description = "OC-01 crane service relay"
	definition.mass_kg = 0.4
	add_box(self, "Plate", FACE_SIZE, Vector3.ZERO, Color("4c5d5e"))
	indicator = add_box(self, "ConditionLamp", Vector3(0.024, 0.024, 0.009),
		Vector3(-0.105, 0.039, 0.04), Color("81bcad"))
	add_label(self, abbreviation, Vector3(0.01, -0.015, 0.04), 0.0011)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = FACE_SIZE
	collision.shape = shape
	add_child(collision)
	component.condition_changed.connect(_update_indicator)

func _ready() -> void:
	super._ready()
	# This shallow wall-mounted panel is picked by the ordinary interaction ray only.
	collision_layer = 4
	collision_mask = 0
	_update_indicator()

func query_actions() -> Array[StringName]:
	var actions := super.query_actions()
	if not actions.is_empty() and is_instance_valid(component) and component.repair_issue().is_empty():
		actions.append(&"repair")
	return actions

func inspection_information() -> Dictionary:
	var result := super.inspection_information()
	result.description += "\n\n" + component.inspection_text()
	return result

func _update_indicator() -> void:
	var colors := [Color("81bcad"), Color("eaaf5d"), Color("f4866f")]
	(indicator.material_override as StandardMaterial3D).albedo_color = colors[component.condition]

static func add_box(parent: Node3D, mesh_name: String, size: Vector3, at: Vector3, color: Color) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	visual.name = mesh_name
	visual.position = at
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.8
	visual.material_override = material
	parent.add_child(visual)
	return visual

static func add_label(parent: Node3D, caption: String, at: Vector3, scale_in_meters: float) -> void:
	var label := Label3D.new()
	label.text = caption
	label.position = at
	label.font_size = 32
	label.pixel_size = scale_in_meters
	label.outline_size = 0
	label.modulate = Color("b4c6bf")
	parent.add_child(label)

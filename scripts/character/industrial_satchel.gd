extends Node3D
## Cosmetic shell. It reads aggregate fullness and adds no physics bodies.
@export var tuning: SatchelTuning = preload("res://data/inventory/satchel_tuning.tres")
var container: InventoryContainer
var shell: Node3D
var target_scale := Vector3.ONE

func _ready() -> void:
	shell = Node3D.new()
	add_child(shell)
	var fabric := StandardMaterial3D.new()
	fabric.albedo_color = Color("#66654b")
	fabric.roughness = 0.95
	var strap := StandardMaterial3D.new()
	strap.albedo_color = Color("#303c3d")
	strap.roughness = 0.85
	var trim := StandardMaterial3D.new()
	trim.albedo_color = Color("#9e8c57")
	trim.metallic = 0.5
	add_box(shell, Vector3(0.62, 0.39, 0.25), Vector3.ZERO, fabric)
	add_box(shell, Vector3(0.63, 0.10, 0.035), Vector3(0, 0.155, 0.132), fabric)
	for x in [-0.21, 0.21]:
		add_box(shell, Vector3(0.04, 0.4, 0.027), Vector3(x, 0, 0.137), strap)
		add_box(shell, Vector3(0.056, 0.034, 0.02), Vector3(x, 0.05, 0.156), trim)

	var shoulder_strap := MeshInstance3D.new()
	shoulder_strap.mesh = BoxMesh.new()
	shoulder_strap.mesh.size = Vector3(0.044, 0.58, 0.028)
	shoulder_strap.position = Vector3(-0.05, 0.28, -0.14)
	shoulder_strap.rotation.z = deg_to_rad(-28)
	shoulder_strap.material_override = strap
	add_child(shoulder_strap)
	add_box(shell, Vector3(0.22, 0.07, 0.012), Vector3(0, -0.05, 0.132), strap)
	bind_container.call_deferred()

func add_box(parent: Node3D, size: Vector3, at: Vector3, material: Material) -> void:
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	mesh.mesh.size = size
	mesh.position = at
	mesh.material_override = material
	parent.add_child(mesh)

func bind_container() -> void:
	var actor := get_parent()
	while actor != null and not actor is OtisController:
		actor = actor.get_parent()
	if actor != null:
		container = actor.equipment.container
		container.changed.connect(update_fullness)
		update_fullness()

func update_fullness() -> void:
	match container.fullness():
		&"empty": target_scale = Vector3(0.94, 0.96, 0.62)
		&"partially_full": target_scale = Vector3(0.98, 1.0, 0.86)
		&"full": target_scale = Vector3(1.0, 1.0, 1.0)
		&"bulging": target_scale = Vector3(1.10, 1.08, 1.20)

func _process(delta: float) -> void:
	transform = tuning.attachment_transform()
	shell.scale = shell.scale.lerp(target_scale, 1 - exp(-6 * delta))

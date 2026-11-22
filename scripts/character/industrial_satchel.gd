extends Node3D
## Cosmetic shell. It reads aggregate fullness and adds no physics bodies.
const SHELL_DEPTH := 0.25
const STRAP_WIDTH := 0.044
const STRAP_THICKNESS := 0.016
# Centerline on the rigid torso, from the rear of the left shoulder to the
# right hip. The endpoints beyond these points are attached to the bag.
const STRAP_PATH := [
	Vector3(-0.09, 0.36, 0.110),
	Vector3(-0.13, 0.52, 0.086),
	Vector3(-0.13, 0.58, 0.065),
	Vector3(-0.13, 0.58, -0.065),
	Vector3(-0.13, 0.53, -0.086),
	Vector3(-0.095, 0.46, -0.150),
	Vector3(-0.035, 0.36, -0.145),
	Vector3(0.116, 0.111, -0.097),
	Vector3(0.135, 0.104, 0.014),
	Vector3(0.123, 0.101, 0.099)
]
const STRAP_NORMALS := [
	Vector3.BACK, Vector3.BACK, Vector3(0, 1, 1), Vector3.UP,
	Vector3(0, 1, -1), Vector3.FORWARD, Vector3.FORWARD, Vector3.FORWARD,
	Vector3.RIGHT, Vector3.RIGHT, Vector3.BACK
]
@export var tuning: SatchelTuning = preload("res://data/inventory/satchel_tuning.tres")
var container: InventoryContainer
var shell: Node3D
var shoulder_strap := Node3D.new()
var target_scale := Vector3.ONE

func _ready() -> void:
	transform = tuning.attachment_transform()
	shell = Node3D.new()
	shell.name = "SatchelShell"
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
	add_box(shell, Vector3(0.62, 0.39, SHELL_DEPTH), Vector3.ZERO, fabric)
	add_box(shell, Vector3(0.63, 0.10, 0.035), Vector3(0, 0.155, 0.132), fabric)
	for x in [-0.21, 0.21]:
		add_box(shell, Vector3(0.04, 0.4, 0.027), Vector3(x, 0, 0.137), strap)
		add_box(shell, Vector3(0.056, 0.034, 0.02), Vector3(x, 0.05, 0.156), trim)

	shoulder_strap.name = "ShoulderStrap"
	add_child(shoulder_strap)
	for segment in STRAP_NORMALS.size():
		add_box(shoulder_strap, Vector3(STRAP_WIDTH, 1, STRAP_THICKNESS), Vector3.ZERO, strap)
	align_shoulder_strap()
	add_box(shell, Vector3(0.22, 0.07, 0.012), Vector3(0, -0.05, 0.132), strap)
	bind_container.call_deferred()

func align_shoulder_strap() -> void:
	var mount := get_parent() as Node3D
	var torso_to_bag := (mount.transform * transform).affine_inverse()
	var points: Array[Vector3] = [Vector3(-0.20, 0.13, -0.117)]
	for point in STRAP_PATH:
		points.append(torso_to_bag * point)
	points.append(Vector3(0.245, 0.063, -0.117))
	for index in STRAP_NORMALS.size():
		var start := points[index]
		var end := points[index + 1]
		var along := (end - start).normalized()
		var across := along.cross(torso_to_bag.basis * STRAP_NORMALS[index]).normalized()
		var segment := shoulder_strap.get_child(index) as MeshInstance3D
		segment.basis = Basis(across, along, across.cross(along))
		segment.position = (start + end) * 0.5
		(segment.mesh as BoxMesh).size.y = start.distance_to(end) + STRAP_THICKNESS

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
	var attachment := tuning.attachment_transform()
	if not transform.is_equal_approx(attachment):
		transform = attachment
		align_shoulder_strap()
	shell.scale = shell.scale.lerp(target_scale, 1 - exp(-6 * delta))
	# Fullness changes the outer depth while keeping the inner face against
	# the back and both strap ends seated in the shell.
	shell.position.z = SHELL_DEPTH * 0.5 * (shell.scale.z - 1.0)

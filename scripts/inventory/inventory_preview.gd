class_name InventoryPreview
extends SubViewportContainer
var viewport: SubViewport
var pivot: Node3D

func _ready() -> void:
	stretch = true
	viewport = SubViewport.new()
	viewport.size = Vector2i(480, 650)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(viewport)
	var world := Node3D.new()
	viewport.add_child(world)
	pivot = Node3D.new()
	world.add_child(pivot)
	var camera := Camera3D.new()
	camera.position = Vector3(0, 1.02, -3.3)
	camera.look_at_from_position(camera.position, Vector3(0, 0.94, 0))
	camera.fov = 38
	world.add_child(camera)
	camera.make_current()
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("#182529")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("#b8c8cb")
	environment.environment.ambient_light_energy = 0.75
	world.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35, -40, 0)
	light.light_energy = 1.7
	world.add_child(light)

func refresh(actor: OtisController) -> void:
	for child in pivot.get_children():
		pivot.remove_child(child)
		child.queue_free()
	var rig := actor.get_node("ICF01_Wayfarer") as WayfarerRig
	var core := copy_visual(rig.core, pivot)
	core.name = "PreviewChassis"
	# The hierarchy is copied as visual nodes only, including socket transforms.
	var item := actor.equipment.held_item()
	if item != null and not actor.equipment.placing:
		var hand_path := rig.core.get_path_to(rig.limbs[1].hand.get_node("ToolAlignment"))
		var socket := core.get_node(hand_path) as Node3D
		var projection := Node3D.new()
		socket.add_child(projection)
		projection.position = -Vector3(0, -0.035, 0.10) if item is FasteningTool else Vector3.ZERO
		for source in item.find_children("*", "MeshInstance3D", true, false):
			var mesh := MeshInstance3D.new()
			mesh.mesh = source.mesh
			mesh.material_override = source.material_override
			mesh.transform = item.global_transform.affine_inverse() * source.global_transform
			projection.add_child(mesh)

func copy_visual(source: Node3D, parent: Node3D) -> Node3D:
	var node: Node3D
	if source is MeshInstance3D:
		var model := MeshInstance3D.new()
		model.mesh = source.mesh
		model.material_override = source.material_override
		node = model
	else:
		node = Node3D.new()
	node.name = source.name
	node.transform = source.transform
	parent.add_child(node)
	for child in source.get_children():
		if child is Node3D and not child is Camera3D and not child is CollisionObject3D:
			copy_visual(child, node)
	return node

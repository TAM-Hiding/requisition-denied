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
	# Pose the visual copy from current ownership, independent of which render
	# frame last animated the live chassis.
	var item := actor.equipment.held_item()
	var holding := item != null and not actor.equipment.placing
	var gaze := clampf(actor.camera.rotation.x, -0.32, 0.38)
	for limb in rig.limbs:
		var shoulder := core.get_node(rig.core.get_path_to(limb.shoulder)) as Node3D
		var forearm := core.get_node(rig.core.get_path_to(limb.forearm)) as Node3D
		var hand := core.get_node(rig.core.get_path_to(limb.hand)) as Node3D
		var tool_hand: bool = holding and limb.side > 0
		shoulder.rotation.x = 0.38 if tool_hand else 0.0
		shoulder.rotation.z = limb.side * (0.09 if tool_hand else 0.04)
		forearm.rotation.x = 0.83 if tool_hand else 0.10
		hand.basis = Basis(Vector3.RIGHT, clampf(gaze - shoulder.rotation.x - forearm.rotation.x, -0.70, 0.70)) \
			if tool_hand else WayfarerRig.resting_wrist(limb.side)

	if item != null and not actor.equipment.placing:
		var hand_path := rig.core.get_path_to(rig.limbs[1].hand.get_node("ToolAlignment"))
		var socket := core.get_node(hand_path) as Node3D
		var projection := Node3D.new()
		socket.add_child(projection)
		projection.basis = socket.global_basis.inverse() * pivot.global_basis * Basis(Vector3.RIGHT, gaze)
		var handle := Vector3(0, -0.035, 0.10) if item is FasteningTool else Vector3.ZERO
		for source in item.find_children("*", "MeshInstance3D", true, false):
			var mesh := MeshInstance3D.new()
			mesh.mesh = source.mesh
			mesh.material_override = source.material_override
			mesh.transform = item.global_transform.affine_inverse() * source.global_transform
			mesh.position -= handle
			projection.add_child(mesh)

static func copy_visual(source: Node3D, parent: Node3D) -> Node3D:
	var node: Node3D
	if source is Label3D:
		var label := Label3D.new()
		label.text = source.text
		label.font_size = source.font_size
		label.pixel_size = source.pixel_size
		label.modulate = source.modulate
		label.outline_size = source.outline_size
		label.billboard = source.billboard
		node = label
	elif source is MeshInstance3D:
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

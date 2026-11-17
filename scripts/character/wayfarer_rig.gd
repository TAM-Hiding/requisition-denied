class_name WayfarerRig
extends Node3D
## Visual joint hierarchy. Motion input is read from the gameplay controller.
const CHASSIS_ID := &"icf01.wayfarer"
const MODULES := {
	&"core": preload("res://scenes/character/core.tres"),
	&"head": preload("res://scenes/character/head.tres"),
	&"upper_arm": preload("res://scenes/character/upper_arm.tres"),
	&"forearm": preload("res://scenes/character/forearm.tres"),
	&"forearm_service": preload("res://scenes/character/forearm_service.tres"),
	&"hand": preload("res://scenes/character/hand.tres"),
	&"thigh": preload("res://scenes/character/thigh.tres"),
	&"shin": preload("res://scenes/character/shin.tres"),
	&"foot": preload("res://scenes/character/foot.tres"),
}
const FIRST_PERSON_ITEM := 1 << 18
var core: Node3D
var head: Node3D
var limbs: Array[Dictionary] = []
var gait_phase := 0.0
var time_alive := 0.0
var previous_yaw := 0.0
var inspection_side := 0
var inspection_camera: Camera3D
var displayed_item: InteractableObject
var display_meshes: Dictionary
var original_layers: Dictionary
@onready var actor := get_parent() as OtisController

func _ready() -> void:
	visible = false
	core = mount(self, "CoreChassis", MODULES[&"core"], 0.0)
	core.position.y = 0.94
	head = mount(core.get_node("HeadMount"), "HeadModule", MODULES[&"head"], 0.0)
	for side in [-1.0, 1.0]:
		var label := "Left" if side < 0.0 else "Right"
		var shoulder := mount(core.get_node(label + "ShoulderMount"), label + "UpperArm", MODULES[&"upper_arm"], side)
		var forearm := mount(shoulder.get_node("ElbowConnection"), label + "Forearm", MODULES[&"forearm"], side)
		var hand := mount(forearm.get_node("WristConnection"), label + "Hand", MODULES[&"hand"], side)
		var thigh := mount(core.get_node(label + "HipMount"), label + "Thigh", MODULES[&"thigh"], side)
		var shin := mount(thigh.get_node("KneeConnection"), label + "Shin", MODULES[&"shin"], side)
		var foot := mount(shin.get_node("AnkleConnection"), label + "Foot", MODULES[&"foot"], side)
		limbs.append({"side": side, "label": label, "shoulder": shoulder, "forearm": forearm,
			"hand": hand, "thigh": thigh, "shin": shin, "foot": foot})

	inspection_camera = Camera3D.new()
	inspection_camera.name = "WayfarerInspectionCamera"
	inspection_camera.top_level = true
	inspection_camera.fov = 46.0
	inspection_camera.cull_mask = (actor.get_node("Camera3D") as Camera3D).cull_mask & ~FIRST_PERSON_ITEM
	add_child(inspection_camera)

func mount(parent: Node3D, slot: String, definition: ChassisModuleDefinition, side: float) -> Node3D:
	var module := definition.instantiate_module()
	if module == null:
		return null
	if "side" in module:
		module.set("side", side)
	module.name = slot
	parent.add_child(module)
	return module

func replace_forearm(side_index: int, definition: ChassisModuleDefinition) -> bool:
	if side_index < 0 or side_index >= limbs.size() or definition == null 			or definition.category != &"forearm" or definition.mounting_interface != &"elbow":
		return false
	var limb := limbs[side_index]
	var old: Node3D = limb.forearm
	var hand: Node3D = limb.hand
	var replacement := definition.instantiate_module()
	if replacement == null:
		return false
	var wrist := replacement.get_node_or_null("WristConnection") as Marker3D
	if wrist == null or not wrist.transform.is_equal_approx((hand.get_parent() as Marker3D).transform) 			or not replacement.get_node_or_null("ElbowConnection") is Marker3D 			or not replacement.get_node_or_null("ForearmAccessoryMount") is Marker3D:
		replacement.free()
		return false
	if "side" in replacement:
		replacement.set("side", limb.side)
	var parent := old.get_parent()
	parent.remove_child(old)
	replacement.name = limb.label + "Forearm"
	replacement.transform = old.transform
	parent.add_child(replacement)
	hand.reparent(wrist, false)
	old.queue_free()
	limb.forearm = replacement
	return true

func _unhandled_key_input(event: InputEvent) -> void:
	if not OS.is_debug_build() or not actor.controls_enabled or not event is InputEventKey or event.is_echo():
		return
	if event.pressed and event.physical_keycode == KEY_K and not event.ctrl_pressed and not event.alt_pressed 			and not event.shift_pressed and not event.meta_pressed:
		set_inspection((inspection_side + 1) % 3)
		get_viewport().set_input_as_handled()

func set_inspection(view: int) -> void:
	inspection_side = view
	visible = view != 0
	if visible:
		update_camera()
		inspection_camera.make_current()
	else:
		clear_display_item()
		if inspection_camera.is_current():
			actor.camera.make_current()

func update_camera() -> void:
	var focus := actor.to_global(Vector3(0, 0.96, 0))
	var desired := actor.to_global(Vector3(1.35, 1.47, -3.05 if inspection_side == 1 else 3.05))
	var query := PhysicsRayQueryParameters3D.create(focus, desired, 17, [actor.get_rid()])
	var hit := actor.get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		desired = hit.position.lerp(focus, 0.06)
	if desired.distance_squared_to(focus) > 0.01:
		inspection_camera.global_position = desired
		inspection_camera.look_at(focus)

func _process(delta: float) -> void:
	if actor.equipment == null:
		return
	if inspection_side != 0 and not inspection_camera.is_current():
		set_inspection(0)
	var held := actor.equipment.held_item()
	var holding := is_instance_valid(held) and not actor.equipment.placing
	animate(delta, holding, actor.placement.is_active())
	if inspection_side != 0:
		update_camera()
		update_display_item(held if holding and held.visible else null)

func animate(delta: float, holding: bool, manipulating: bool) -> void:
	time_alive += delta
	var movement := Vector2(actor.velocity.x, actor.velocity.z).length()
	var stride := clampf(movement / maxf(actor.movement_speed, 0.01), 0.0, 1.0)
	gait_phase = fposmod(gait_phase + movement * delta * 2.8, TAU)
	var yaw_delta := angle_difference(previous_yaw, actor.rotation.y)
	previous_yaw = actor.rotation.y
	var blend := 1.0 - exp(-12.0 * delta)
	var turning := clampf(yaw_delta / maxf(delta, 0.001), -2.0, 2.0)
	core.position.y = lerpf(core.position.y, 0.94 + 0.013 * absf(sin(gait_phase)) * stride, blend)
	core.rotation.z = lerpf(core.rotation.z, turning * 0.026, blend)
	var gaze := clampf(actor.camera.rotation.x, -0.32, 0.38)
	head.rotation.x = lerpf(head.rotation.x, gaze + sin(time_alive * 1.8) * 0.018, blend)
	head.rotation.y = lerpf(head.rotation.y, turning * 0.12, blend)
	for limb in limbs:
		var wave := sin(gait_phase) * float(limb.side)
		var thigh: Node3D = limb.thigh
		var shin: Node3D = limb.shin
		var foot: Node3D = limb.foot
		var shoulder: Node3D = limb.shoulder
		var forearm: Node3D = limb.forearm
		var hand: Node3D = limb.hand
		thigh.rotation.x = lerpf(thigh.rotation.x, wave * stride * 0.31, blend)
		thigh.rotation.y = lerpf(thigh.rotation.y, turning * 0.06 * limb.side, blend)
		shin.rotation.x = lerpf(shin.rotation.x, -maxf(0.0, wave) * stride * 0.43, blend)
		foot.rotation.x = lerpf(foot.rotation.x, -0.75 * (thigh.rotation.x + shin.rotation.x), blend)
		var tool_hand: bool = limb.side > 0 and holding
		var reaching: bool = tool_hand or manipulating
		var reach := 0.3 if manipulating else (0.59 if actor.tool_aiming else 0.38)
		shoulder.rotation.x = lerpf(shoulder.rotation.x, reach if reaching else -wave * stride * 0.21, blend)
		shoulder.rotation.z = lerpf(shoulder.rotation.z, limb.side * (0.09 if reaching else 0.04), blend)
		forearm.rotation.x = lerpf(forearm.rotation.x, (1.10 if actor.tool_aiming else 0.83) if tool_hand
			else (0.64 if manipulating else 0.10), blend)
		hand.rotation.x = lerpf(hand.rotation.x, gaze - shoulder.rotation.x - forearm.rotation.x if tool_hand else 0.0, blend)

func update_display_item(item: InteractableObject) -> void:
	if displayed_item != item:
		clear_display_item()
		displayed_item = item
		if is_instance_valid(item):
			var socket := limbs[1].hand.get_node("ToolAlignment") as Marker3D
			for child in item.find_children("*", "MeshInstance3D", true, false):
				var source := child as MeshInstance3D
				original_layers[source] = source.layers
				source.layers = FIRST_PERSON_ITEM
				var display := MeshInstance3D.new()
				display.mesh = source.mesh
				display.material_override = source.material_override
				socket.add_child(display)
				display_meshes[source] = display
	if not is_instance_valid(item):
		return
	var handle := Vector3(0.0, -0.035, 0.10) if item is FasteningTool else Vector3.ZERO
	for source: MeshInstance3D in display_meshes:
		if not is_instance_valid(source):
			continue
		var display: MeshInstance3D = display_meshes[source]
		display.transform = item.global_transform.affine_inverse() * source.global_transform
		display.position -= handle
		display.visible = source.is_visible_in_tree()
		display.material_override = source.material_override

func clear_display_item() -> void:
	for source: MeshInstance3D in original_layers:
		if is_instance_valid(source):
			source.layers = original_layers[source]
	for display: MeshInstance3D in display_meshes.values():
		display.hide()
		display.queue_free()
	original_layers.clear()
	display_meshes.clear()
	displayed_item = null

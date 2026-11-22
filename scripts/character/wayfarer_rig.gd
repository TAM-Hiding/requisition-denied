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
const REST_WRIST_CANT := deg_to_rad(12.0)
const FIRST_PERSON_ITEM := 1 << 18
var core: Node3D
var head: Node3D
var limbs: Array[Dictionary] = []
var gait_phase := 0.0
var time_alive := 0.0
var previous_yaw := 0.0
var displayed_item: InteractableObject
var display_meshes: Dictionary
var original_layers: Dictionary
@onready var actor := get_parent() as OtisController

func _ready() -> void:
	visible = false
	core = mount(self, "CoreChassis", MODULES[&"core"], 0.0)
	core.position.y = 0.94
	var satchel := Node3D.new()
	satchel.set_script(preload("res://scripts/character/industrial_satchel.gd"))
	satchel.name = "IndustrialSatchel"
	core.get_node("RearEquipmentMount").add_child(satchel)
	satchel.transform = satchel.tuning.attachment_transform()
	head = mount(core.get_node("HeadMount"), "HeadModule", MODULES[&"head"], 0.0)
	for side in [-1.0, 1.0]:
		var label := "Left" if side < 0.0 else "Right"
		var shoulder := mount(core.get_node(label + "ShoulderMount"), label + "UpperArm", MODULES[&"upper_arm"], side)
		var forearm := mount(shoulder.get_node("ElbowConnection"), label + "Forearm", MODULES[&"forearm"], side)
		var hand := mount(forearm.get_node("WristConnection"), label + "Hand", MODULES[&"hand"], side)
		hand.basis = resting_wrist(side)
		var thigh := mount(core.get_node(label + "HipMount"), label + "Thigh", MODULES[&"thigh"], side)
		var shin := mount(thigh.get_node("KneeConnection"), label + "Shin", MODULES[&"shin"], side)
		var foot := mount(shin.get_node("AnkleConnection"), label + "Foot", MODULES[&"foot"], side)
		limbs.append({"side": side, "label": label, "shoulder": shoulder, "forearm": forearm,
			"hand": hand, "thigh": thigh, "shin": shin, "foot": foot})


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

func _process(delta: float) -> void:
	if actor.equipment == null:
		return
	var held := actor.equipment.held_item()
	var holding := is_instance_valid(held) and not actor.equipment.placing
	animate(delta, holding, actor.placement.is_active())
	if visible:
		update_display_item(held if holding and held.visible else null)

static func resting_wrist(side: float) -> Basis:
	# Turn the palm toward the thigh, then tip the fingers inward in the
	# forearm frame. The grip frame stays the reference for equipment.
	return Basis(Vector3.BACK, -side * REST_WRIST_CANT) * Basis(Vector3.UP, side * PI / 2.0)

func animate(delta: float, holding: bool, manipulating: bool) -> void:
	time_alive += delta
	var movement := Vector2(actor.velocity.x, actor.velocity.z).length()
	var local_velocity := actor.global_basis.inverse() * Vector3(actor.velocity.x, 0, actor.velocity.z)
	var forward := clampf(-local_velocity.z / maxf(movement, 0.01), -1, 1)
	var lateral := clampf(local_velocity.x / maxf(movement, 0.01), -1, 1)
	var crouched := actor.locomotion != null and actor.locomotion.posture == OtisLocomotion.Posture.CROUCHING
	var prone := actor.locomotion != null and actor.locomotion.posture == OtisLocomotion.Posture.PRONE
	var climbing := actor.locomotion != null and actor.locomotion.climbing
	var climb_pose: Array = []
	var ledge_brace := 0.0
	if climbing:
		var progress := actor.locomotion.climb_progress
		climb_pose = preload("res://scripts/character/wayfarer_climb_poses.gd").sample(
			actor.locomotion.climb_variant, progress)
		# A short ledge calls for a deep brace instead of an overhead pull.
		ledge_brace = (1.0 - smoothstep(0.65, 1.15, actor.locomotion.climb_rise)) \
			* smoothstep(0, 0.19, progress) * (1.0 - smoothstep(0.60, 0.87, progress))
	var stride := clampf(movement / maxf(actor.movement_speed, 0.01), 0.0, 1.0)
	gait_phase = fposmod(gait_phase + movement * delta * 2.8, TAU)
	var yaw_delta := angle_difference(previous_yaw, actor.rotation.y)
	previous_yaw = actor.rotation.y
	var blend := 1.0 - exp((-26.0 if climbing else -12.0) * delta)
	var turning := clampf(yaw_delta / maxf(delta, 0.001), -2.0, 2.0)
	# Articulate the same joints/geometry. The original standing-forward
	# amplitudes and phase rate remain the reference gait.
	position = position.lerp(Vector3(0, 0.25, 0.85) if prone else Vector3.ZERO, blend)
	rotation.x = lerp_angle(rotation.x, -PI / 2 if prone else 0.0, blend)
	var core_height := (0.465 if crouched else 0.94) + 0.013 * absf(sin(gait_phase)) * stride
	var core_angles := Vector3(0.12 if crouched else 0.0, 0, turning * 0.026)
	var core_forward := 0.0
	if climbing:
		core_height += climb_pose[1].x
		core_forward = climb_pose[1].y
		core_angles = climb_pose[0]
		core_angles.x = lerpf(core_angles.x, -1.08, ledge_brace)
		core_height = lerpf(core_height, 0.46, ledge_brace)
		core_forward *= 1.0 - ledge_brace * 0.75
	core.position = core.position.lerp(Vector3(0, core_height, -core_forward), blend)
	core.rotation = core.rotation.lerp(core_angles, blend)
	var gaze := clampf(actor.camera.rotation.x, -0.32, 0.38)
	head.rotation.x = lerpf(head.rotation.x, gaze + (PI / 2 if prone else 0.0) + sin(time_alive * 1.8) * 0.018, blend)
	head.rotation.y = lerpf(head.rotation.y, turning * 0.12, blend)
	for limb in limbs:
		var wave := sin(gait_phase) * float(limb.side)
		var thigh: Node3D = limb.thigh
		var shin: Node3D = limb.shin
		var foot: Node3D = limb.foot
		var shoulder: Node3D = limb.shoulder
		var forearm: Node3D = limb.forearm
		var hand: Node3D = limb.hand
		var leg_swing := wave * forward
		var hip_goal := leg_swing * stride * 0.31
		var knee_goal := -maxf(0.0, leg_swing) * stride * 0.43
		if crouched:
			hip_goal += 1.15
			knee_goal -= 2.3
		elif prone:
			hip_goal = wave * stride * 0.15
			knee_goal = -0.12 - maxf(0.0, wave) * stride * 0.28
		elif climbing:
			var index := 0 if limb.side < 0 else 1
			hip_goal = climb_pose[3][index]
			knee_goal = climb_pose[3][index + 2]
			hip_goal += ledge_brace * 0.36
			knee_goal -= ledge_brace * 0.47
		thigh.rotation.x = lerpf(thigh.rotation.x, hip_goal, blend)
		thigh.rotation.z = lerpf(thigh.rotation.z, -wave * stride * lateral * 0.24, blend)
		thigh.rotation.y = lerpf(thigh.rotation.y, turning * 0.06 * limb.side, blend)
		shin.rotation.x = lerpf(shin.rotation.x, knee_goal, blend)
		foot.rotation.x = lerpf(foot.rotation.x, -0.75 * (thigh.rotation.x + shin.rotation.x), blend)
		var tool_hand: bool = limb.side > 0 and holding
		var reaching: bool = tool_hand or manipulating
		var reach := 0.3 if manipulating else (0.59 if actor.tool_aiming else 0.38)
		var arm_goal := reach if reaching else -leg_swing * stride * 0.21
		var arm_roll: float = limb.side * (0.09 if reaching else 0.04)
		var elbow_goal := (1.10 if actor.tool_aiming else 0.83) if tool_hand else (0.64 if manipulating else 0.10)
		if prone and not tool_hand:
			arm_goal = 2.8 + wave * stride * 0.18
		elif climbing and not tool_hand:
			var index := 0 if limb.side < 0 else 1
			arm_goal = climb_pose[2][index]
			elbow_goal = climb_pose[2][index + 2]
			var plant := ledge_brace * smoothstep(0.50, 1.20, arm_goal)
			if plant > 0.0:
				var brace := short_ledge_arm_pose(shoulder, forearm, limb.side)
				arm_goal = lerpf(arm_goal, brace.x, plant)
				elbow_goal = lerpf(elbow_goal, brace.y, plant)
				arm_roll *= 1.0 - plant
		shoulder.rotation.x = lerpf(shoulder.rotation.x, arm_goal, blend)
		shoulder.rotation.z = lerpf(shoulder.rotation.z, arm_roll, blend)
		forearm.rotation.x = lerpf(forearm.rotation.x, elbow_goal, blend)
		if prone and not tool_hand:
			forearm.rotation.x = lerpf(forearm.rotation.x, 0.65 - wave * stride * 0.12, blend)
		var wrist_goal := Basis.IDENTITY if prone else resting_wrist(limb.side)
		if climbing and not tool_hand:
			wrist_goal = wrist_goal.slerp(Basis(Vector3.RIGHT, -0.32), smoothstep(0.45, 1.0, arm_goal))
		if reaching:
			wrist_goal = Basis(Vector3.RIGHT, clampf(gaze - shoulder.rotation.x - forearm.rotation.x, -0.70, 0.70)) if tool_hand else Basis.IDENTITY
		hand.quaternion = hand.quaternion.slerp(wrist_goal.get_rotation_quaternion(), blend)

func short_ledge_arm_pose(shoulder: Node3D, forearm: Node3D, side: float) -> Vector2:
	# Fit the shoulder/elbow hinges in their shared pitch plane. The pose track
	# controls hand timing and body motion. Contact is cosmetic.
	var edge := actor.locomotion.climb_edge + actor.global_basis.x * side * 0.20
	edge.y += 0.025
	var offset: Vector3 = (shoulder.get_parent() as Node3D).to_local(edge)
	var reach := Vector2(-offset.y, -offset.z)
	var upper: float = (forearm.get_parent() as Node3D).position.length()
	var lower: float = (forearm.get_node("WristConnection") as Node3D).position.length() + 0.075
	var distance := clampf(reach.length(), absf(upper - lower) + 0.05, upper + lower - 0.005)
	var elbow := acos(clampf((distance * distance - upper * upper - lower * lower) / (2.0 * upper * lower), -1, 1))
	var pitch := reach.angle() - atan2(lower * sin(elbow), upper + lower * cos(elbow))
	return Vector2(clampf(pitch, -0.2, 1.85), minf(elbow, 1.8))

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
		var socket := display.get_parent() as Node3D
		var gaze := clampf(actor.camera.rotation.x, -0.32, 0.38)
		var compensation := socket.global_basis.inverse() * actor.global_basis * Basis(Vector3.RIGHT, gaze)
		var model_pose := item.global_transform.affine_inverse() * source.global_transform
		model_pose.origin -= handle
		display.transform = Transform3D(compensation, Vector3.ZERO) * model_pose
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

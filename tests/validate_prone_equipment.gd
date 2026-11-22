extends SceneTree

var checks := 0
var failures := 0
var actor: OtisController
var tool: FasteningTool
var rig: WayfarerRig

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(description)

func frames(count: int) -> void:
	for frame in count:
		await physics_frame

func grip_aligned() -> bool:
	return rig.right_grip().global_transform.is_equal_approx(
		tool.global_transform * Transform3D(Basis.IDENTITY, FasteningTool.HANDLE_CENTER))

func block(parent: Node3D, at: Vector3, size: Vector3, fixed: bool) -> InteractableObject:
	var body := InteractableObject.new()
	body.definition = ObjectDefinition.new()
	body.definition.mobility = ObjectDefinition.Mobility.FIXED if fixed else ObjectDefinition.Mobility.MOVABLE
	body.gravity_scale = 0.0
	body.position = at
	var collider := CollisionShape3D.new()
	collider.name = "CollisionShape3D"
	collider.shape = BoxShape3D.new()
	collider.shape.size = size
	body.add_child(collider)
	parent.add_child(body)
	return body

func run() -> void:
	var facility := preload("res://scenes/facility.tscn").instantiate()
	root.add_child(facility)
	current_scene = facility
	actor = facility.get_node("Otis")
	rig = actor.get_node("ICF01_Wayfarer")
	tool = facility.bolt_tool
	var presentation := actor.equipment.presentation
	var eye_mask := actor.camera.cull_mask
	var tool_id := tool.get_instance_id()
	actor.position = Vector3(0, 0.025, 4.5)
	actor.rotation = Vector3.ZERO
	actor.camera.rotation = Vector3.ZERO
	await frames(8)
	check(actor.equipment.pick_up(tool).ok and actor.locomotion.request_posture(OtisLocomotion.Posture.CROUCHING)
		and actor.locomotion.request_posture(OtisLocomotion.Posture.PRONE), "Uni-Bolt equips before crouch-to-prone")
	await frames(45)
	check(grip_aligned() and tool.visible and presentation.prone_pose_clear(tool.global_transform),
		"Prone idle keeps the original tool above the floor in the actual grip")
	check(rig.display_meshes.is_empty() and tool.get_instance_id() == tool_id,
		"No separate equipment projection or simulated tool is created in prone")
	var neutral_elbow: float = rig.limbs[1].forearm.rotation.x
	var neutral_grip := rig.right_grip().global_position
	actor.velocity = Vector3(0, 0, -1.1)
	rig.animate(0.05, true, false)
	presentation.update_pose(0)
	check(grip_aligned() and tool.visible and not rig.right_grip().global_position.is_equal_approx(neutral_grip),
		"The supporting stroke moves the live equipped tool with its right hand")
	actor.velocity = Vector3.ZERO

	actor.set_tool_aiming(true)
	await frames(40)
	check(actor.tool_aiming and presentation.aim_blend == 1.0 and rig.limbs[1].forearm.rotation.x < neutral_elbow - 0.5,
		"Aim extends the right arm from its supporting pose")
	var aim := tool.aim_ray(actor.camera, actor)
	check(aim.issue.is_empty() and Vector3(aim.origin).is_equal_approx(tool.to_global(FasteningTool.MUZZLE))
		and Vector3(aim.direction).is_equal_approx(-tool.global_basis.z) and grip_aligned(),
		"Aiming and firing directions originate at the barrel on the same held instance")
	var right_arm: Node3D = rig.limbs[1].shoulder
	var arm_mesh := right_arm.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	var head_mesh := rig.head.find_children("*", "MeshInstance3D", true, false)[0] as MeshInstance3D
	check(actor.camera.is_current() and arm_mesh.is_visible_in_tree() and arm_mesh.layers & actor.camera.cull_mask
		and not (head_mesh.layers & actor.camera.cull_mask) and tool.is_visible_in_tree()
		and actor.camera.is_position_in_frustum(tool.to_global(FasteningTool.REAR_SIGHT_TIP)),
		"First person sees the actual arm and tool, with the head excluded from the eye camera")

	# Aim at two contacting surfaces, with geometry positioned relative to the
	# actual character so an offset weapon must converge toward the eye ray.
	var primary := block(facility, Vector3(0, 0.32, 1.95), Vector3(0.55, 0.40, 0.04), false)
	var backing := block(facility, Vector3(0, 0.32, 1.88), Vector3(0.55, 0.40, 0.10), true)
	await frames(30)
	var feedback := tool.aim_feedback(actor.camera, actor)
	check(feedback.issue.is_empty() and feedback.get("a") == primary and feedback.get("b") == backing,
		"Prone ADS converges on the eye target: %s" % feedback.issue)
	var count := tool.rounds.size()
	var result := tool.use(actor.camera, actor)
	check(result.begins_with("INSTALLED") and tool.rounds.size() == count - 1,
		"Uni-Bolt can install from the prone barrel: %s" % result)
	count = tool.rounds.size()
	var blocker := block(facility, tool.to_global(FasteningTool.MUZZLE), Vector3(0.13, 0.14, 0.12), true)
	await frames(2)
	check(not tool.visible and grip_aligned() and tool.use(actor.camera, actor) == "TOOL OBSTRUCTED" and tool.rounds.size() == count,
		"Blocking the barrel cannot consume a round or fire through geometry")
	blocker.queue_free()
	await frames(12)

	actor.view_camera.third_person = true
	actor.view_camera.restore_view()
	await frames(2)
	check(actor.view_camera.is_current() and grip_aligned() and rig.display_meshes.is_empty()
		and head_mesh.layers & actor.view_camera.cull_mask, "Shoulder view sees the same held item and full chassis")
	actor.view_camera.set_orbiting(true)
	await frames(2)
	check(actor.view_camera.orbiting and grip_aligned() and tool.get_instance_id() == tool_id,
		"Orbit uses the same held instance and anatomical grip")
	actor.view_camera.set_orbiting(false)
	actor.view_camera.third_person = false
	actor.view_camera.restore_view()

	actor.set_tool_aiming(false)
	await frames(36)
	check(not actor.tool_aiming and presentation.aim_blend == 0.0 and not rig.visible and grip_aligned()
		and absf(float(rig.limbs[1].forearm.rotation.x) - neutral_elbow) < 0.10,
		"Release returns to the bent right elbow and clears the first-person arm view")
	check(actor.locomotion.request_posture(OtisLocomotion.Posture.CROUCHING),
		"Prone position can still transition to crouch")
	await frames(40)
	check(not presentation.uses_prone_grip() and not rig.visible and actor.camera.is_current()
		and actor.camera.cull_mask == eye_mask
		and actor.equipment.held_item() == tool,
		"Crouched presentation recovers without state or ownership contamination")
	check(actor.equipment.stow().ok and actor.equipment.equip_first().ok and actor.equipment.held_item() == tool,
		"Stow and re-equip still transfer the same tool instance")
	facility.queue_free()
	await process_frame
	print("RD-013 prone equipment: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

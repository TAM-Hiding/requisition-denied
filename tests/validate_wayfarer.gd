extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func run() -> void:
	var facility := preload("res://scenes/facility.tscn").instantiate()
	root.add_child(facility)
	current_scene = facility
	var actor := facility.get_node("Otis") as OtisController
	var rig := actor.get_node("ICF01_Wayfarer") as WayfarerRig
	await physics_frame
	var ids := {}
	for entry: ChassisModuleDefinition in WayfarerRig.MODULES.values():
		var module := entry.instantiate_module()
		check(module != null and not ids.has(entry.module_id) and not entry.category.is_empty()
			and not entry.mounting_interface.is_empty(), "Registered chassis module has a valid, unique contract")
		ids[entry.module_id] = true
		if module != null:
			module.free()
	check(rig.limbs.size() == 2 and rig.core.get_node("RearEquipmentMount") is Marker3D
		and rig.core.get_node("WaistEquipmentMount") is Marker3D, "The complete chassis exposes accessory mounts")
	check(rig.find_children("*", "CollisionObject3D", true, false).is_empty(),
		"The visual rig adds no gameplay collision bodies")
	check(not rig.visible and actor.camera.is_current(), "The first-person camera is clear on startup")
	check_handedness(rig)
	var before := actor.global_transform
	var look := actor.camera.transform
	var chassis := actor.chassis
	rig.set_inspection(1)
	check(rig.visible and rig.inspection_camera.is_current() and actor.global_transform == before
		and actor.camera.transform == look and actor.chassis == chassis, "Inspection only replaces the rendered viewpoint")
	rig.set_inspection(2)
	check(actor.to_local(rig.inspection_camera.global_position).z > 0.0, "Rear inspection shows the spine")
	var tool: FasteningTool = facility.get("bolt_tool")
	check(actor.equipment.pick_up(tool).ok, "Uni-Bolt still equips through the gameplay controller")
	rig.update_display_item(tool)
	var hand: Node3D = rig.limbs[1].hand
	var grip := hand.get_node("PrimaryGrip") as Marker3D
	var alignment := hand.get_node("ToolAlignment") as Marker3D
	var grip_transform := grip.global_transform
	var gun_transform := tool.global_transform
	check(not rig.display_meshes.is_empty() and rig.displayed_item == tool, "The hand carries a visual projection of the equipped tool")
	check(rig.replace_forearm(1, WayfarerRig.MODULES[&"forearm_service"])
		and rig.limbs[1].hand == hand and grip.global_transform.is_equal_approx(grip_transform)
		and hand.get_parent().get_parent() == rig.limbs[1].forearm
		and tool.global_transform == gun_transform and actor.equipped_tool() == tool,
		"Service forearm swaps without moving the hand, grip or gameplay item")
	for display: MeshInstance3D in rig.display_meshes.values():
		check(display.get_parent() == alignment, "Tool projection stays on the replacement arm's original hand socket")
	check(not rig.replace_forearm(1, WayfarerRig.MODULES[&"foot"]), "An incompatible interface is rejected")
	var invalid := WayfarerRig.MODULES[&"forearm"].duplicate() as ChassisModuleDefinition
	invalid.attachment_sockets.append(&"MissingSocket")
	check(not rig.replace_forearm(1, invalid) and rig.limbs[1].hand == hand,
		"A malformed visual scene is rejected without disrupting the hand")
	actor.velocity = Vector3(0, 0, -actor.movement_speed)
	rig.animate(0.18, true, false)
	check(absf(rig.limbs[0].thigh.rotation.x) > 0.05 and rig.limbs[1].forearm.rotation.x > 0.25,
		"Gait and equipment pose layer on the same joint hierarchy")
	actor.velocity = Vector3.ZERO
	rig.set_inspection(0)
	check(actor.camera.is_current() and not rig.visible and rig.display_meshes.is_empty()
		and actor.equipment.stow().ok, "First person and gameplay equipment resume after inspection")
	facility.queue_free()
	await process_frame
	print("RD-010: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func check_handedness(rig: WayfarerRig) -> void:
	var left: Node3D = rig.limbs[0].hand
	var right: Node3D = rig.limbs[1].hand
	var left_thumb := left.get_node("ThumbBase") as MeshInstance3D
	var right_thumb := right.get_node("ThumbBase") as MeshInstance3D
	var left_tip := left.get_node("ThumbTip") as MeshInstance3D
	var right_tip := right.get_node("ThumbTip") as MeshInstance3D
	check(left_thumb.position.x > 0.0 and right_thumb.position.x < 0.0
		and absf(rig.to_local(left_thumb.global_position).x) < absf(rig.to_local(left.global_position).x)
		and absf(rig.to_local(right_thumb.global_position).x) < absf(rig.to_local(right.global_position).x),
		"The left and right thumbs face inward in neutral stance")
	check(is_equal_approx(left_thumb.position.x, -right_thumb.position.x)
		and is_equal_approx(left_tip.rotation.z, -right_tip.rotation.z)
		and (left_tip.basis * Vector3.DOWN).x < 0.0 and (right_tip.basis * Vector3.DOWN).x > 0.0,
		"Thumb links mirror across the wrists and curl across their own palms")
	for hand in [left, right]:
		var thumb := hand.get_node("ThumbBase") as MeshInstance3D
		var index_finger := hand.get_node("IndexFinger") as MeshInstance3D
		var little_finger := hand.get_node("LittleFinger") as MeshInstance3D
		var grip := hand.get_node("PrimaryGrip") as Marker3D
		var back := hand.get_node("BackPlate") as MeshInstance3D
		check(index_finger.position.x * thumb.position.x > 0.0
			and little_finger.position.x * thumb.position.x < 0.0
			and index_finger.position.y < 0.0 and (index_finger.basis * Vector3.DOWN).dot(Vector3.DOWN) > 0.9
			and index_finger.position.z < 0.0 and grip.position.z < 0.0 and back.position.z > 0.0,
			"Finger order is handed and the palm faces its forward grip")

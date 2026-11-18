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
	actor.set_tool_aiming(true)
	rig.animate(1.0, true, false)
	var pitch := clampf(actor.camera.rotation.x, -0.32, 0.38) - float(rig.limbs[1].shoulder.rotation.x) \
		- float(rig.limbs[1].forearm.rotation.x)
	check(hand.basis.is_equal_approx(Basis(Vector3.RIGHT, clampf(pitch, -0.70, 0.70)))
		and grip.transform == Transform3D(Basis.IDENTITY, Vector3(0, -0.091, -0.035))
		and alignment.transform == grip.transform,
		"Aiming bounds wrist flexion while preserving the exact grip sockets")
	actor.set_tool_aiming(false)
	rig.set_inspection(0)
	check(actor.camera.is_current() and not rig.visible and rig.display_meshes.is_empty()
		and actor.equipment.stow().ok, "First person and gameplay equipment resume after inspection")
	facility.queue_free()
	await process_frame
	print("RD-010: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func check_handedness(rig: WayfarerRig) -> void:
	rig.animate(1.0, false, false)
	for i in 2:
		var side := -1.0 if i == 0 else 1.0
		var hand: Node3D = rig.limbs[i].hand
		var thumb := hand.get_node("ThumbBase") as MeshInstance3D
		var tip := hand.get_node("ThumbTip") as MeshInstance3D
		var index := hand.get_node("IndexFinger") as MeshInstance3D
		var little := hand.get_node("LittleFinger") as MeshInstance3D
		var back := hand.get_node("BackPlate") as MeshInstance3D
		var palm := rig.to_local(hand.to_global(Vector3.FORWARD)) - rig.to_local(hand.global_position)
		var down := rig.to_local(hand.to_global(Vector3.DOWN)) - rig.to_local(hand.global_position)
		var thumb_offset := rig.to_local(thumb.global_position) - rig.to_local(hand.global_position)
		var back_offset := rig.to_local(back.global_position) - rig.to_local(hand.global_position)
		check(thumb.position.x * side > 0.0 and index.position.x * side > 0.0 and little.position.x * side < 0.0
			and (tip.basis * Vector3.DOWN).x * side < 0.0, "Thumb and finger order match the anatomical hand")
		check(palm.dot(Vector3.LEFT * side) > 0.95 and back_offset.x * side > 0.0
			and thumb_offset.z < -0.025, "In Otis's frame palms face thighs, backs face out and thumbs sit forward")
		var cant := rad_to_deg(atan2(-side * down.x, -down.y))
		check(down.dot(Vector3.DOWN) > 0.95 and cant >= 9.0 and cant <= 15.0,
			"Neutral fingers hang down with a slight inward wrist cant")

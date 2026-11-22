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

func frames(count := 2) -> void:
	for i in count:
		await physics_frame

func mouse(bag: BagView, button: MouseButton, pressed: bool, point: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.position = point
	bag._gui_input(event)

func point_for(bag: BagView, item: InteractableObject) -> Vector2:
	var body: RigidBody3D = bag.interior.proxies[item]
	var bounds := ContainerPacking.bounds(InventoryItem.from_body(item), body.transform)
	var top := Vector3(bounds.get_center().x, bounds.end.y, bounds.get_center().z)
	return bag.camera.unproject_position(top)

func run() -> void:
	var facility = preload("res://scenes/facility.tscn").instantiate()
	root.add_child(facility)
	current_scene = facility
	var actor := facility.get_node("Otis") as OtisController
	var screen: InventoryScreen = facility.get_node("InteractionUI").inventory
	var eq := actor.equipment
	await frames(5)
	check(facility.get_node_or_null("SteelPlate") == null and facility.get_node_or_null("TriangularGusset") == null,
		"Obsolete authored scrap is absent from the development chamber")
	var rig := actor.get_node("ICF01_Wayfarer") as WayfarerRig
	var satchel := rig.core.get_node("RearEquipmentMount/IndustrialSatchel") as Node3D
	var tuning: SatchelTuning = satchel.get("tuning")
	check(satchel.transform.is_equal_approx(tuning.attachment_transform()) and tuning.roll_degrees != 0
		and tuning.vertical_offset < -0.21, "Messenger attachment uses the saved lower diagonal configuration")
	check(satchel.position.is_equal_approx(Vector3(0.01, -0.31, 0.112)),
		"Messenger attachment shifts 7 cm to Otis's left at the same height and depth")
	check_live_attachment(actor, rig, satchel)
	var wrench := facility.get_node("Wrench") as InteractableObject
	var tool: FasteningTool = facility.get("bolt_tool")
	check(eq.store_world(wrench).ok and eq.store_world(tool).ok, "Physical context fixtures preserve original tools")
	var ammo := tool.inventory_state()
	var mass := eq.container.mass_kg()
	screen.show_inventory(facility.get_node("InteractionUI").hud)
	screen.toggle_view()
	var bag := screen.bag
	await frames(20)
	check(screen._preview_column.visible == false and bag.size.x > 500, "Bag View temporarily borrows character preview space")
	var pointer := point_for(bag, wrench)
	mouse(bag, MOUSE_BUTTON_RIGHT, true, pointer)
	check(not bag.interior.plowing, "Stationary RMB begins a pending click")
	mouse(bag, MOUSE_BUTTON_RIGHT, false, pointer)
	check(screen.popup.visible and screen.popup.item_count == 4 and screen.popup.get_item_text(0) == "Equip",
		"A short RMB click opens Equip, Drop, Inspect and Cancel")
	screen.perform_action(3)
	check(screen.details.text.contains("RD-WRENCH") and eq.container.mass_kg() == mass,
		"Inspect displays the selected identity without a transfer")
	screen.popup.hide()
	pointer = point_for(bag, wrench)
	mouse(bag, MOUSE_BUTTON_RIGHT, true, pointer)
	var motion := InputEventMouseMotion.new()
	motion.position = pointer + Vector2(25, 0)
	bag._gui_input(motion)
	bag.advance_gestures(bag.tuning.plow_hold_seconds + 0.01)
	check(bag.interior.plowing, "RMB movement activates Plow Mode only after the hold threshold")
	mouse(bag, MOUSE_BUTTON_RIGHT, false, motion.position)
	check(not bag.interior.plowing and not screen.popup.visible, "Consumed RMB release does not open a context menu")
	screen.selected = tool
	screen.perform_action(0)
	check(eq.held_item() == tool and not eq.container.contains(tool), "Bag context equips directly from storage")
	var preview_core := screen.preview.pivot.get_child(0) as Node3D
	var shoulder_path := rig.core.get_path_to(rig.limbs[1].shoulder)
	check(absf((preview_core.get_node(shoulder_path) as Node3D).rotation.x - 0.38) < 0.001,
		"Preview displays the equipped arm immediately")
	screen.perform_action(1)
	preview_core = screen.preview.pivot.get_child(0)
	var hand_path := rig.core.get_path_to(rig.limbs[1].hand)
	check(eq.held_item() == null and absf((preview_core.get_node(shoulder_path) as Node3D).rotation.x) < 0.001
		and (preview_core.get_node(hand_path) as Node3D).basis.is_equal_approx(WayfarerRig.resting_wrist(1)),
		"Unequip immediately restores neutral preview arm and correct hand orientation")
	check(tool.inventory_state() == ammo, "Direct context transfers preserve the actual magazine and grade")
	screen.hide_inventory()
	# Select a real generated gusset for vertical recovery from the floor.
	check(eq.retrieve(wrench).ok and eq.retrieve(tool).ok, "Tools can drop through shared forward-arc release")
	var gusset := facility.scrap_supply.dispense(17) as InteractableObject
	check(gusset != null and eq.store_world(gusset).ok, "Dispenser-generated triangular gusset enters the same bag")
	screen.show_inventory(facility.get_node("InteractionUI").hud)
	screen.toggle_view()
	bag = screen.bag
	await frames(25)
	var proxy: RigidBody3D = bag.interior.proxies[gusset]
	var centroid := proxy.global_transform * Vector3(-0.04, 0.01, -0.05)
	pointer = bag.camera.unproject_position(centroid)
	mouse(bag, MOUSE_BUTTON_LEFT, true, pointer)
	check(bag.interior.drag_item == gusset, "A gusset lying on the bottom is selectable for physical dragging")
	var y := proxy.position.y
	var fov := bag.camera.fov
	for i in 4:
		mouse(bag, MOUSE_BUTTON_WHEEL_DOWN, true, pointer)
	await frames(50)
	check(proxy.position.y > y + 0.06 and bag.camera.fov == fov, "Wheel raises the selected manipulation target without camera zoom")
	mouse(bag, MOUSE_BUTTON_LEFT, false, pointer)
	check(bag.interior.drag_item == gusset, "Releasing LMB preserves the physical hold")
	mouse(bag, MOUSE_BUTTON_LEFT, true, Vector2(5, 5))
	mouse(bag, MOUSE_BUTTON_LEFT, false, Vector2(5, 5))
	var raised := proxy.position.y
	await frames(45)
	check(proxy.position.y < raised - 0.03, "Released item settles back into the bag")
	var pleats := bag.interior.walls.filter(func(wall: Node3D) -> bool: return wall.get_meta(&"long_face", false))
	check(pleats.size() == 6 and bag.interior.walls.all(func(wall: Node3D) -> bool:
		return wall.position.distance_to(wall.get_meta(&"rest_position")) <= 0.009),
		"Both long faces have three bounded pleats")
	var resting := proxy.position.y
	bag.selected = gusset
	mouse(bag, MOUSE_BUTTON_WHEEL_DOWN, true, pointer)
	await frames(12)
	check(proxy.position.y > resting + 0.01, "A selected item also accepts a brief wheel-only vertical nudge")
	await frames(35)
	check(bag.interior.drag_item == gusset, "Wheel-only manipulation remains held until deliberately released")
	mouse(bag, MOUSE_BUTTON_LEFT, true, Vector2(5, 5))
	mouse(bag, MOUSE_BUTTON_LEFT, false, Vector2(5, 5))
	var saved_fov := bag.camera.fov
	bag.selected = null
	mouse(bag, MOUSE_BUTTON_WHEEL_DOWN, true, pointer)
	check(bag.camera.fov == saved_fov and bag.interior.drag_item == null, "Wheel with no selected drag does nothing")
	# Horizontal orbit must not invert the bag. A deliberate vertical turn does.
	var yaw := bag.view_yaw
	mouse(bag, MOUSE_BUTTON_MIDDLE, true, pointer)
	motion.position = pointer
	motion.relative = Vector2(10, 0)
	bag._gui_input(motion)
	bag.advance_gestures(0.01)
	check(bag.view_yaw > yaw and bag.bag_angle == 0, "Orbit follows horizontal input without accidental dumping")
	bag.view_tilt = 0.65 + deg_to_rad(160)
	bag.advance_gestures(0.1)
	check(bag.opening_direction().dot(Vector3.UP) < -0.9 and not bag.dumping,
		"Inversion checks opening direction and requires a dwell")
	bag.advance_gestures(bag.tuning.inversion_dwell + 0.01)
	check(bag.dumping and screen._dump_sequence, "Deliberate inversion begins the coordinated dump sequence")
	screen.hide_inventory()
	screen.toggle_view()
	check(screen.active and bag.active, "UI buttons cannot remove the interior during its dumping animation")
	await frames(90)
	check(not screen.active and not eq.dumping and not eq.container.contains(gusset)
		and gusset.state == InteractableObject.State.WORLD and gusset.storage_owner == null,
		"The dump closes inventory and releases the same physical gusset")
	screen.show_inventory(facility.get_node("InteractionUI").hud)
	screen.toggle_view()
	bag = screen.bag
	bag.orbiting = true
	bag.view_tilt = 1.3
	bag.advance_gestures(0.01)
	bag.orbiting = false
	for i in 80:
		bag.advance_gestures(1.0 / 60)
	check(bag.interior.transform.is_equal_approx(Transform3D.IDENTITY) and bag.interior.is_physics_processing(),
		"An empty tilted bag returns to upright simulation")
	# Close halfway through a turn, before upright recovery completes.
	bag.orbiting = true
	bag.view_tilt = 1.4
	bag.advance_gestures(0.01)
	screen.hide_inventory()
	screen.show_inventory(facility.get_node("InteractionUI").hud)
	screen.toggle_view()
	bag.orbiting = true
	bag.advance_gestures(0.01)
	check(bag.bag_angle == 0, "Reopening cannot reuse an old inversion angle")
	screen.hide_inventory()
	await expanded_capacity(facility)
	facility.queue_free()
	await process_frame
	print("RD-012 corrections: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func check_live_attachment(actor: OtisController, rig: WayfarerRig, satchel: Node3D) -> void:
	var shell := satchel.get_node("SatchelShell") as Node3D
	var bag_body := shell.get_child(0) as MeshInstance3D
	var strap := satchel.get_node("ShoulderStrap") as Node3D
	var shoulder_segment := strap.get_child(3) as MeshInstance3D
	var shell_half_depth := (bag_body.mesh as BoxMesh).size.z * 0.5
	satchel._process(2.0)
	var back := shell.transform * Vector3(0, 0, -shell_half_depth)
	check(is_equal_approx(back.z, -shell_half_depth)
		and satchel.get_parent().transform.origin.z + (satchel.transform * back).z < 0.17,
		"An empty bag keeps its inward face within 17 cm of the torso centerline")
	var over_shoulder := rig.core.to_local(shoulder_segment.global_position)
	check(over_shoulder.distance_to(Vector3(-0.13, 0.58, 0)) < 0.01,
		"The strap crosses just over the left shoulder beam")
	var shell_bounds := bag_body.get_aabb()
	var first := strap.get_child(0) as MeshInstance3D
	var last := strap.get_child(strap.get_child_count() - 1) as MeshInstance3D
	var start := first.transform * (Vector3.DOWN * ((first.mesh as BoxMesh).size.y * 0.5 - 0.008))
	var end := last.transform * (Vector3.UP * ((last.mesh as BoxMesh).size.y * 0.5 - 0.008))
	check(shell_bounds.has_point(shell.transform.affine_inverse() * start)
		and shell_bounds.has_point(shell.transform.affine_inverse() * end),
		"Both ends of the wrap enter the shell even when empty")
	var bag_pose := rig.core.global_transform.affine_inverse() * satchel.global_transform
	for posture in [OtisLocomotion.Posture.CROUCHING, OtisLocomotion.Posture.PRONE, OtisLocomotion.Posture.STANDING]:
		var accepted := actor.locomotion.request_posture(posture)
		rig.animate(1.0, false, false)
		check(accepted and (rig.core.global_transform.affine_inverse() * satchel.global_transform).is_equal_approx(bag_pose)
			and rig.core.to_local(shoulder_segment.global_position).is_equal_approx(over_shoulder),
			"Bag and shoulder loop stay torso-relative in " + OtisLocomotion.Posture.keys()[posture])

func expanded_capacity(world: Node3D) -> void:
	var container := InventoryContainer.new()
	container.definition = preload("res://data/inventory/personal_storage.tres").duplicate()
	container.definition.container_id = &"EXPANSION-TEST"
	world.add_child(container)
	check(container.definition.capacity_m3 == 0.05 and container.definition.effective_capacity_m3() == 0.06
		and container.definition.maximum_mass_kg == 25, "Nominal, expanded and structural ratings are separate")
	for index in 7:
		var item := InteractableObject.new()
		item.definition = ObjectDefinition.new()
		item.definition.object_id = StringName("EXPAND-%d" % index)
		item.definition.mobility = ObjectDefinition.Mobility.MOVABLE
		item.definition.mass_kg = 0.2
		var shape := CollisionShape3D.new()
		shape.name = "CollisionShape3D"
		shape.shape = BoxShape3D.new()
		shape.shape.size = Vector3(0.2, 0.2, 0.24)
		item.add_child(shape)
		world.add_child(item)
		var issue := container.insert(item)
		check(issue.is_empty() if index < 6 else issue.contains("volume"), "Expansion accepts 57.6 L and rejects the next 9.6 L")
	check(container.volume_m3() > 0.05 and container.volume_m3() <= 0.06 and container.items().size() == 6,
		"Expanded physical packing remains within the accepted 60 L ceiling")
	check(container.records().all(func(record: InventoryItem) -> bool:
		return ContainerPacking.inside(ContainerPacking.bounds(record, record.internal_pose),
			container.definition.packing_dimensions())), "Expanded placements fit the same envelope used by collision walls")

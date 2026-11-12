extends SceneTree

var checks := 0
var failures := 0
var facility: Node3D
var system: FasteningSystem
var tool: FasteningTool
var actor: OtisController

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func frames(count := 2) -> void:
	for index in count:
		await physics_frame

func run() -> void:
	facility = preload("res://scenes/facility.tscn").instantiate()
	facility.chassis_seed = 42
	root.add_child(facility)
	current_scene = facility
	system = facility.fastening
	tool = facility.bolt_tool
	actor = facility.get_node("Otis")
	facility.get_node("InteractionUI").set_physics_process(false)
	await frames(4)
	check((InputMap.action_get_events("tool_primary")[0] as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT,
		"LMB is a named tool action")
	check((InputMap.action_get_events("tool_secondary_aim")[0] as InputEventMouseButton).button_index == MOUSE_BUTTON_RIGHT,
		"RMB is a named tool action")
	check((InputMap.action_get_events("tool_mode_toggle")[0] as InputEventKey).physical_keycode == KEY_R,
		"R switches named tool modes")
	check(tool.rounds.size() == 20 and tool.rounds[0].grade.strength == 100.0, "Standard magazine starts full")
	await concurrent_work()
	await compound_and_strength()
	await repeated_construction()
	await pose_and_gusset()
	await invalidated_edge()
	await rig()
	facility.queue_free()
	await process_frame
	print("RD-008: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func piece(title: String, position: Vector3, size: Vector3, kilograms := 2.0) -> InteractableObject:
	var part := facility.stock_piece(StringName(title), title, kilograms, position, size, null) as InteractableObject
	part.gravity_scale = 0.0
	return part

func wall(title: String, position: Vector3, size: Vector3) -> StaticBody3D:
	return facility.box(facility, title, size, position, null, true) as StaticBody3D

func install(point: Vector3, direction: Vector3, grade := 0) -> InstalledFastener:
	var bolt := system.create_round(FasteningTool.GRADES[grade])
	var issue := system.install(bolt, point, direction, 3.0)
	check(issue.is_empty(), "Fastener installed: " + issue)
	return bolt

func concurrent_work() -> void:
	var backing := wall("FixtureWall", Vector3(3.3, 1.4, 4.55), Vector3(1.0, 1.0, 0.10))
	var panel := piece("HeldPanel", Vector3(3.3, 1.4, 4.38), Vector3(0.4, 0.40, 0.04))
	actor.global_position = Vector3(3.3, 0.02, 2.65)
	await frames(3)
	check(system.probe(Vector3(0, 2.7, 2.9), Vector3.UP, 0.5).issue == "NO TARGET SURFACE",
		"Empty rays reject fastening")
	var single := system.probe(Vector3(3.3, 1.4, 3.3), Vector3.BACK, 2.0)
	check(single.issue == "NO SECONDARY MATERIAL IN CONTACT", "Air gap rejects two visible bodies")
	check(actor.equipment.pick_up(tool).ok and actor.equipment.stow().ok, "Tool can be stored before grabbing a part")
	actor.camera.look_at(panel.global_position)
	check(actor.placement.begin_world(panel), "A lightweight panel enters precision manipulation")
	actor.placement.set_physics_process(false)
	panel.global_position = Vector3(3.3, 1.4, 4.47)
	var pinned := panel.global_transform
	var ui := facility.get_node("InteractionUI")
	var equip := InputEventAction.new()
	equip.action = &"equip_first"
	equip.pressed = true
	if DisplayServer.get_name() != "headless":
		check(ui.handle_fastening_input(equip), "Equipment input is routed while precision manipulation is active")
	else:
		actor.equipment.equip_first()
	check(actor.equipped_tool() == tool and actor.placement.is_grabbing() and panel.global_transform == pinned,
		"Equipping while grabbing preserves the workpiece")
	var aim := InputEventAction.new()
	aim.action = &"tool_secondary_aim"
	aim.pressed = true
	check(ui.handle_fastening_input(aim), "ADS action is accepted while grabbing")
	actor.camera.look_at(panel.global_position + Vector3(0.12, 0.04, 0))
	actor.placement.update_preview(0.12)
	await frames(16)
	check(actor.tool_aiming and actor.camera.fov < actor.camera_fov and panel.global_transform.is_equal_approx(pinned),
		"ADS narrows FOV while the world pose remains pinned during camera movement")
	var candidate := system.probe(actor.camera.global_position, -actor.camera.global_basis.z, 3.0, actor)
	check(candidate.issue.is_empty() and candidate.a == panel and candidate.b == backing,
		"Ray targets the actual held workpiece and its backing, never the gun or Otis")
	var shot := InputEventAction.new()
	shot.action = &"tool_primary"
	shot.pressed = true
	ui.handle_fastening_input(shot)
	var group := system.between(panel, backing)
	check(group != null and not actor.placement.is_grabbing() and panel.fastened and panel.freeze,
		"First bolt hands off ownership to the fixed connection")
	if group == null:
		actor.placement.cancel()
		return
	await frames()
	actor.camera.look_at(panel.global_position + Vector3(-0.12, -0.04, 0))
	ui.handle_fastening_input(shot)
	check(group.bolts.size() == 2, "Second bolt independently reinforces the same pair through compound proxies")
	var recovered := group.bolts[0]
	var direction := recovered.head() - actor.camera.global_position
	check(system.target_bolt(actor.camera.global_position, direction, 3.0, actor) == recovered,
		"Individual bolt is targetable from its head")
	if DisplayServer.get_name() != "headless":
		var release := InputEventMouseButton.new()
		release.button_index = MOUSE_BUTTON_RIGHT
		ui._input(release)
	else:
		actor.set_tool_aiming(false)
	actor.placement.cancel()
	await frames(14)
	check(not actor.tool_aiming and is_equal_approx(actor.camera.fov, actor.camera_fov) and group.bolts.size() == 2,
		"ADS release and placement cancellation leave attached work intact")
	tool.load_grade(1)
	tool.removing = true
	actor.camera.look_at(recovered.head())
	check(tool.use(actor.camera, actor).begins_with("RECOVERED") and tool.recovered.has(recovered)
		and recovered.grade == FasteningTool.GRADES[0] and group.bolts.size() == 1,
		"Wrong-grade removal retains the exact bolt in reserve")
	tool.load_grade(0)
	check(tool.rounds.has(recovered) and tool.rounds.size() == FasteningTool.CAPACITY, "Matching reload returns recovered identity at capacity")
	var final := group.bolts[0]
	actor.camera.look_at(final.head())
	check(tool.use(actor.camera, actor).begins_with("RECOVERED") and tool.recovered.has(final)
		and tool.rounds.size() == 20 and not panel.fastened and not panel.freeze,
		"Full magazine retains extra rounds and last removal frees the same panel")
	tool.removing = false
	panel.queue_free()
	backing.queue_free()
	await frames()

func compound_and_strength() -> void:
	var backing := facility.get_node("Crate") as InteractableObject
	backing.global_transform = Transform3D(Basis.IDENTITY, Vector3(0.8, 1.65, 5.2))
	backing.gravity_scale = 0.0
	backing.linear_velocity = Vector3.ZERO
	backing.angular_velocity = Vector3.ZERO
	var angle := facility.get_node("AngleBracket") as InteractableObject
	angle.gravity_scale = 0.0
	# Face the upright flange toward the crate with the horizontal leg
	# extending toward Otis. The back of the flange sits within 8 mm.
	angle.global_transform = Transform3D(Basis(Vector3.UP, PI), Vector3(0.8, 1.25, 4.417))
	angle.linear_velocity = Vector3.ZERO
	angle.angular_velocity = Vector3.ZERO
	actor.global_position = Vector3(0.8, 0.02, 3.15)
	await frames(3)
	actor.camera.look_at(angle.to_global(Vector3(0.05, 0.16, -0.109)))
	check(actor.placement.begin_world(angle), "Compound angle bracket remains precision-manipulable with the tool equipped")
	actor.set_tool_aiming(true)
	var start := actor.camera.global_position
	var ray := -actor.camera.global_basis.z
	var angle_result := system.probe(start, ray, 3.0, actor)
	check(angle_result.a == angle and angle_result.b == backing, "The held bracket can target a second movable body")
	var issue := tool.use(actor.camera, actor)
	check(issue.begins_with("INSTALLED"), "Held angle fastens to a movable backing: " + issue)
	actor.set_tool_aiming(false)
	var group := system.between(angle, backing)
	if group == null:
		actor.placement.cancel()
		angle.queue_free()
		backing.gravity_scale = 1.0
		await frames()
		return
	await frames()
	var bolt := group.bolts[0]
	var root_body := system.physics_root(angle) as RigidBody3D
	check(root_body == backing and angle.get_parent() == backing and angle.collision_layer == 0
		and is_equal_approx(root_body.mass, 38.0), "Free island has one simulated compound and preserves mass")
	var local := angle.to_local(bolt.head())
	var start_pos := angle.global_position
	root_body.apply_central_impulse(Vector3.RIGHT * 20.0)
	await frames(10)
	check(angle.global_position.x > start_pos.x + 0.05 and angle.to_local(bolt.head()).is_equal_approx(local),
		"Fastener locations stay local as the compound moves")
	system.apply_structural_load(angle, bolt.head(), Vector3.RIGHT * 101)
	check(bolt.state == InstalledFastener.State.FAILED and not bolt.recoverable() and not system.remove(bolt)
		and angle.get_parent() == facility and angle.collision_layer == 1 and not angle.freeze,
		"Single overload breaks the bolt and restores detached collision and ownership")
	await frames(5)
	check(angle.linear_velocity.x > 0.1, "Detached member continues with inherited momentum")
	angle.queue_free()
	backing.gravity_scale = 1.0
	await frames()

	# A lower plate sits against a fixed support. A second plate bolts to it.
	var fixed := wall("SeriesSupport", Vector3(2.5, 2.5, 4.95), Vector3(0.7, 0.7, 0.10))
	var lower := piece("SeriesBackPlate", Vector3(2.5, 2.5, 4.87), Vector3(0.56, 0.56, 0.04), 5.0)
	var upper := piece("SeriesFrontPlate", Vector3(2.5, 2.5, 4.81), Vector3(0.40, 0.40, 0.04))
	upper.rotation.z = 0.31
	await frames()
	var floor_bolt := install(Vector3(2.75, 2.5, 4.30), Vector3.BACK, 2)
	await frames()
	var standard := install(Vector3(2.43, 2.5, 4.30), Vector3.BACK)
	await frames()
	var reinforced := install(Vector3(2.57, 2.5, 4.30), Vector3.BACK, 1)
	await frames()
	var connection := system.between(lower, upper)
	check(connection != null and system.physics_root(upper) == fixed
		and is_equal_approx(upper.rotation.z, 0.31), "Series connections preserve arbitrary orientation in an anchored island")
	if connection == null:
		return
	var center := (standard.head() + reinforced.head()) * 0.5
	connection.estimate(center, Vector3.RIGHT * 120.0)
	check(is_equal_approx(standard.load_estimate, 60.0) and is_equal_approx(reinforced.load_estimate, 60.0),
		"Centered force is shared across both fasteners")
	var moment_force := Vector3.UP * 80.0
	connection.estimate(center + Vector3.RIGHT * 0.22, moment_force)
	var spread_load := standard.load_estimate
	var original_a := standard.local_a
	var original_b := reinforced.local_a
	standard.local_a = standard.a.to_local(standard.head() + Vector3.RIGHT * 0.06)
	reinforced.local_a = reinforced.a.to_local(reinforced.head() - Vector3.RIGHT * 0.06)
	connection.estimate(center + Vector3.RIGHT * 0.22, moment_force)
	check(standard.load_estimate > spread_load, "Clustering raises estimated bolt load under leverage")
	standard.local_a = original_a
	reinforced.local_a = original_b
	system.apply_structural_load(upper, center, Vector3.RIGHT * 230.0)
	check(standard.state == InstalledFastener.State.FAILED and reinforced.state == InstalledFastener.State.INSTALLED
		and connection.bolts.size() == 1 and floor_bolt.state == InstalledFastener.State.INSTALLED,
		"Mixed grades fail progressively and the surviving bolt takes the redistributed load")
	system.apply_structural_load(upper, reinforced.head(), Vector3.RIGHT * 315.0)
	check(reinforced.state == InstalledFastener.State.FAILED and not upper.fastened and lower.fastened
		and floor_bolt.state == InstalledFastener.State.INSTALLED, "The broken series edge does not destroy its unrelated anchor")
	system.apply_structural_load(lower, floor_bolt.head(), Vector3.RIGHT * 9000.0)
	check(floor_bolt.state == InstalledFastener.State.INSTALLED, "MegaBolt withstands a load above the ordinary grades")
	system.apply_structural_load(lower, floor_bolt.head(), Vector3.RIGHT * 10500.0)
	check(floor_bolt.state == InstalledFastener.State.FAILED and not lower.fastened, "MegaBolt can fail above its own rating")
	await frames()
	var first := install(Vector3(2.43, 2.5, 4.30), Vector3.BACK)
	await frames()
	var second := install(Vector3(2.57, 2.5, 4.30), Vector3.BACK)
	var failure_count := system.failed.size()
	system.apply_structural_load(upper, (first.head() + second.head()) * 0.5, Vector3.RIGHT * 210.0)
	check(system.failed.size() == failure_count + 2 and first.load_estimate != second.load_estimate
		and not upper.fastened and not lower.fastened, "Cascade redistributes to the survivor before final detachment")

func rig() -> void:
	var ram := facility.test_ram as StructuralTestRam
	var crate := facility.get_node("Crate") as InteractableObject
	crate.global_transform = Transform3D(Basis.IDENTITY, Vector3(-2.5, 0.65, -0.5))
	crate.linear_velocity = Vector3.ZERO
	crate.angular_velocity = Vector3.ZERO
	await frames(12)
	var too_thick := system.probe(Vector3(-2.5, 2.5, -0.5), Vector3.DOWN, 3.0)
	check(too_thick.issue == "FASTENER TOO SHORT", "A thick crate cannot be drilled through its main body")
	var approach := Vector3(-3.95, 1.4, -0.5)
	var bolt := install(approach, Vector3(-3.105, 0.05, -0.5) - approach, 2)
	await frames(4)
	check(crate.fastened and system.physics_root(crate) == facility.get_node("Floor"), "Thin crate skid supports direct floor attachment")
	var closed_rod_length := ram.rod_sleeve.scale.y + ram.rod_core.scale.y
	ram.travel = 1.70
	ram.face.position.x = ram.travel
	ram.change_force(-10)
	ram.toggle_drive()
	# Starting partway along its travel, toggle selects retract.
	ram.drive = StructuralTestRam.Drive.EXTEND
	await frames(70)
	check(ram.stalled and ram.actual_load > 0 and ram.actual_load <= ram.force_limit() and crate.fastened,
		"Low force stalls against the anchored crate and respects its limit")
	check(ram.rod_sleeve.scale.y + ram.rod_core.scale.y > closed_rod_length + 1.0
		and is_equal_approx(ram.rod_core.position.x + ram.rod_core.scale.y * 0.5, ram.face.position.x - 0.0525)
		and is_equal_approx(ram.face.position.x, ram.travel), "Visible rod ends at the swept collision plate at stall")
	ram.change_force(20)
	check(ram.force_limit() > 9999.0, "Rig setting can exceed MegaBolt strength")
	await frames(35)
	check(bolt.state == InstalledFastener.State.FAILED and not crate.fastened and ram.displacement > 0.015,
		"High force breaks the anchor and drives the now-free crate")
	var count := system.failed.size()
	ram.reset_ram()
	await frames(380)
	check(ram.travel <= 0.001 and ram.drive == StructuralTestRam.Drive.IDLE and ram.actual_load == 0.0,
		"Reset retracts and clears active force")
	check(is_equal_approx(ram.rod_sleeve.scale.y + ram.rod_core.scale.y, closed_rod_length),
		"Visible sleeves retract to their initial length")
	check(system.failed.size() == count and bolt.state == InstalledFastener.State.FAILED,
		"Rig reset leaves structural failures intact")
	crate.global_transform = Transform3D(Basis.IDENTITY, Vector3(-2.5, 0.65, -0.5))
	crate.linear_velocity = Vector3.ZERO
	await frames(4)
	ram.toggle_drive()
	ram.travel = 1.75
	ram.face.position.x = ram.travel
	ram.change_force(-4)
	await frames(70)
	check(crate.global_position.x > -2.45 and ram.actual_load <= ram.force_limit(),
		"A second stroke drives the free crate at a bounded force")
	ram.toggle_drive()
	var retract_from := ram.travel
	await frames(20)
	check(ram.travel < retract_from - 0.08 and ram.actual_load == 0.0,
		"Drive reversal retracts without applying a test force")

func action(name: StringName, pressed := true) -> InputEventAction:
	var event := InputEventAction.new()
	event.action = name
	event.pressed = pressed
	return event

func repeated_construction() -> void:
	var ui := facility.get_node("InteractionUI")
	var placement := actor.placement
	var backing := piece("CycleBacking", Vector3(3.3, 1.4, 4.65), Vector3(0.70, 0.70, 0.20), 8.0)
	var panel := piece("CyclePlate", Vector3(3.3, 1.4, 4.52), Vector3(0.42, 0.36, 0.04))
	actor.global_position = Vector3(3.3, 0.02, 2.80)
	tool.load_grade(0)
	actor.camera.look_at(actor.camera.global_position + Vector3.UP, Vector3.FORWARD)
	await frames(2)
	placement.press_drop(1000000)
	placement.release_drop(1300000)
	check(actor.equipped_tool() == tool and not placement.is_active(), "Holding G without a workpiece never places the gun")
	check(InputMap.action_get_events("drop_tool")[0].physical_keycode == KEY_X, "Dedicated tool drop uses named X binding")
	actor.camera.look_at(panel.global_position)
	placement.press_drop(1000000)
	placement.release_drop(1300000)
	ui._input(action(&"ui_cancel"))
	check(not placement.is_grabbing() and not panel.freeze and not panel.fastened and actor.equipped_tool() == tool,
		"Escape releases the temporary grab while keeping equipment available")
	var baseline_groups := system.connections.size()
	var failed_count := system.failed.size()
	var reserve_count := tool.recovered.size()
	var magazine := tool.rounds.duplicate()
	tool.rounds.clear()
	check(tool.use(actor.camera, actor) == "MAGAZINE EMPTY" and system.connections.size() == baseline_groups,
		"Empty magazine cannot commit structural state")
	tool.rounds.assign(magazine)
	var bad_grade := FastenerGrade.new()
	var invalid_round := system.create_round(bad_grade)
	check(system.install(invalid_round, actor.camera.global_position, Vector3.UP, 3.0, actor) == "INVALID FASTENER"
		and invalid_round.state == InstalledFastener.State.RECOVERED and invalid_round.visual == null,
		"Zero-rated fastener is rejected before any change")
	var forged := InstalledFastener.new()
	forged.id = tool.rounds[0].id
	forged.grade = tool.rounds[0].grade
	check(system.install(forged, actor.camera.global_position, Vector3.UP, 3.0, actor) == "INVALID FASTENER",
		"Duplicate unissued identity is rejected")

	for cycle in 16:
		var reverse := cycle % 2 == 0
		if tool.removing:
			ui.handle_fastening_input(action(&"tool_mode_toggle"))
		var at := Vector3(3.3 + 0.025 * (cycle % 3), 1.40, 4.52)
		var initial := Transform3D(Basis(Vector3.BACK, -0.22 + 0.02 * cycle), at)
		panel.global_transform = initial
		backing.global_transform = Transform3D(Basis.IDENTITY, at + Vector3.BACK * 0.128)
		for body in [panel, backing]:
			body.linear_velocity = Vector3.ZERO
			body.angular_velocity = Vector3.ZERO
		await frames(2)
		if reverse:
			ui.handle_fastening_input(action(&"equip_first"))
		actor.camera.look_at(panel.global_position)
		placement.press_drop(1000000)
		placement.release_drop(1300000)
		check(placement.is_grabbing() and panel.state == InteractableObject.State.CARRIED,
			"Hold G acquires rotated plate in interaction order %s, cycle %d" % [reverse, cycle])
		if not placement.is_grabbing():
			break
		if reverse:
			ui.handle_fastening_input(action(&"equip_first"))
		check(actor.equipped_tool() == tool, "1 equips the tool during cycle %d" % cycle)
		var original_pose := panel.global_transform
		var original_range := placement.distance
		placement.adjust_distance(1)
		check(placement.distance > original_range and placement.target_position() != original_pose.origin,
			"Workpiece remains adjustable immediately after equipping")
		placement.distance = original_range
		ui.handle_fastening_input(action(&"tool_secondary_aim"))
		actor.camera.look_at(actor.camera.global_position + Vector3.UP, Vector3.FORWARD)
		placement.update_preview(1.0 / 60.0)
		check(panel.global_transform.is_equal_approx(original_pose), "ADS pins without moving the workpiece")
		var before := tool.rounds.duplicate()
		check(not tool.use(actor.camera, actor).begins_with("INSTALLED") and tool.rounds == before
			and system.between(panel, backing) == null and placement.is_grabbing(),
			"Failed install preserves magazine, visual state, graph and grab")
		actor.set_tool_aiming(false)
		check(placement.target_position().is_equal_approx(original_pose.origin),
			"Releasing ADS resumes movement from the pinned world pose")
		actor.camera.look_at(panel.to_global(Vector3(-0.10, 0, 0)))
		ui.handle_fastening_input(action(&"tool_secondary_aim"))
		if cycle == 0:
			var obstruction := wall("WorkpieceClearanceBlocker", at + Vector3.RIGHT * 0.18, Vector3(0.08, 0.12, 0.08))
			await frames(2)
			check(tool.use(actor.camera, actor) == "WORKPIECE NEEDS CLEARANCE" and tool.rounds == before
				and placement.is_grabbing() and system.between(panel, backing) == null,
				"Clearance rejection preserves the original grab and rolls back the attempt")
			obstruction.queue_free()
			await frames(2)
		var committed := tool.use(actor.camera, actor)
		var group := system.between(panel, backing)
		check(committed.begins_with("INSTALLED") and group != null and panel.fastened and not placement.is_active()
			and panel.global_transform.is_equal_approx(original_pose), "Commit transfers the exact pose once: " + committed)
		if group == null:
			placement.cancel()
			break
		var first := group.bolts[0]
		check(first.group_id == group.id and first.grade.strength == 100 and first.load_estimate == 0
			and first.visual.is_visible_in_tree() and not tool.rounds.has(first), "Committed round has positive rating and visible membership")
		if cycle == 0:
			first.visual.queue_free()
			system.reconcile()
			check(first.visual.is_visible_in_tree() and first.visual.get_parent() == panel,
				"Missing representation is rebuilt at the installed point")
			var diagnostics := system.diagnostics({"a": panel, "b": backing})
			check(diagnostics.contains("LOAD 0 / RATING 100") and diagnostics.contains("FAILED"),
				"Diagnostics distinguish unloaded capacity from failure")
		# Move the compound, then reinforce it before another physics frame.
		backing.global_position.x += 0.16
		backing.force_update_transform()
		actor.camera.look_at(panel.to_global(Vector3(0.10, 0, 0)))
		var reinforced := tool.use(actor.camera, actor)
		check(reinforced.begins_with("INSTALLED") and group.bolts.size() == 2
			and first.visual.global_position.is_equal_approx(first.head()), "Moved island uses current probe and visual transforms: " + reinforced)
		actor.set_tool_aiming(false)
		ui._input(action(&"ui_cancel"))
		check(first.state == InstalledFastener.State.INSTALLED and panel.fastened, "Escape preserves completed attachment")
		ui.handle_fastening_input(action(&"tool_mode_toggle"))
		check(tool.removing and ui.status.text == "UNI-BOLT · REMOVE", "Mode switch replaces the prior action feedback")
		await frames(2)
		for bolt in group.bolts.duplicate():
			actor.camera.look_at(bolt.head())
			var preview := tool.aim_feedback(actor.camera, actor)
			var removed := tool.use(actor.camera, actor)
			check(preview.get("bolt") == bolt and removed.begins_with("RECOVERED")
				and bolt.state == InstalledFastener.State.RECOVERED and bolt.group_id == 0 and bolt.visual == null,
				"REMOVE targets and recovers the exact live record: " + removed)
		check(not panel.fastened and not panel.freeze and system.between(panel, backing) == null
			and tool.rounds.size() == 20, "Last removal clears all temporary and fixed state")
		if DisplayServer.get_name() != "headless":
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	check(system.connections.size() == baseline_groups and system.failed.size() == failed_count
		and tool.recovered.size() == reserve_count, "Repeated construction has no ghost connections, losses or failures")
	tool.removing = false
	actor.set_tool_aiming(false)
	placement.cancel()
	panel.queue_free()
	backing.queue_free()
	await frames()

func pose_and_gusset() -> void:
	var gusset := facility.get_node("TriangularGusset") as InteractableObject
	var model := gusset.get_node("Model") as MeshInstance3D
	var mesh := model.mesh
	var hull := gusset.get_node("CollisionShape3D").shape as ConvexPolygonShape3D
	var faces := mesh.get_faces()
	var top_visible := false
	for offset in range(0, faces.size(), 3):
		if faces[offset].y > 0 and faces[offset + 1].y > 0 and faces[offset + 2].y > 0:
			top_visible = (faces[offset + 2] - faces[offset]).cross(faces[offset + 1] - faces[offset]).y > 0
	check(top_visible and hull.points.size() == 6 and faces.size() == 24
		and model.material_override.transparency == BaseMaterial3D.TRANSPARENCY_DISABLED,
		"Gusset is an opaque outward-wound prism with matching hull")
	actor.global_position = Vector3(-3.65, 0.01, 4.7)
	await frames(3)
	actor.camera.look_at(gusset.global_position)
	check(actor.placement.begin_world(gusset) and model.mesh == mesh, "Held gusset keeps the original model")
	actor.placement.cancel()
	gusset.global_transform = Transform3D(Basis.IDENTITY, Vector3(0.55, 0.026, 2.7))
	await frames(3)
	var bolt := install(Vector3(0.50, 1.3, 2.65), Vector3.DOWN)
	check(gusset.fastened and model.mesh == mesh, "Installed gusset has the same triangle")
	check(system.remove(bolt) and not gusset.fastened and model.mesh == mesh, "Detached gusset has the same triangle")

	actor.global_position = Vector3(1.0, 0.02, 3.30)
	await frames(3)
	actor.camera.look_at(actor.camera.global_position + Vector3.FORWARD)
	actor.set_tool_aiming(true)
	await frames(15)
	var sight := tool.to_global(Vector3(0, FasteningTool.SIGHT_HEIGHT, -0.16))
	var local := actor.camera.to_local(sight)
	check(tool.global_basis.is_equal_approx(actor.camera.global_basis) and absf(local.x) < 0.01 and absf(local.y) < 0.01
		and tool.visible and not actor.equipment.presentation.obstructed, "Unobstructed ADS aligns the real sight and muzzle with the camera")
	var blocker := wall("MuzzleTestBlocker", actor.camera.global_position + Vector3.FORWARD * 0.57,
		Vector3(0.45, 0.45, 0.08))
	await frames(9)
	check(actor.equipment.presentation.obstructed and tool.visible,
		"Near-wall ADS retracts the gun without hiding it or tilting its sights")
	blocker.queue_free()
	actor.set_tool_aiming(false)
	await frames(22)
	check(is_equal_approx(actor.camera.fov, actor.camera_fov) and actor.camera.to_local(tool.global_position).x > 0.20,
		"RMB release restores the hip pose and normal FOV")
	var ui := facility.get_node("InteractionUI")
	ui.handle_fastening_input(action(&"drop_tool"))
	check(actor.equipped_tool() == null and tool.state == InteractableObject.State.WORLD,
		"X drops the Uni-Bolt through the dedicated action")


func invalidated_edge() -> void:
	var primary := piece("OrphanRecordPlate", Vector3(1.1, 1.4, 4.30), Vector3(0.38, 0.38, 0.04))
	var support := wall("OrphanRecordSupport", Vector3(1.1, 1.4, 4.38), Vector3(0.55, 0.55, 0.10))
	await frames()
	var bolt := install(Vector3(1.1, 1.4, 3.7), Vector3.BACK)
	var group := system.between(primary, support)
	if group == null:
		return
	var failures_before := system.failed.size()
	group.bolts.clear()
	system.reconcile()
	check(bolt.state == InstalledFastener.State.INVALIDATED and bolt.visual == null and not primary.fastened
		and not primary.freeze and system.between(primary, support) == null and system.failed.size() == failures_before,
		"Orphaned membership clears the visible bolt and constraint without inventing an overload")
	primary.queue_free()
	support.queue_free()
	await frames()

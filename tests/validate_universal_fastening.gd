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
	ram.travel = 1.70
	ram.face.position.x = ram.travel
	ram.change_force(-10)
	ram.toggle_drive()
	# Starting partway along its travel, toggle selects retract.
	ram.drive = StructuralTestRam.Drive.EXTEND
	await frames(70)
	check(ram.stalled and ram.actual_load > 0 and ram.actual_load <= ram.force_limit() and crate.fastened,
		"Low force stalls against the anchored crate and respects its limit")
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

extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)

func run() -> void:
	var facility := preload("res://scenes/facility.tscn").instantiate()
	root.add_child(facility)
	current_scene = facility
	var actor: OtisController = facility.get_node("Otis")
	var hall := facility.get_node("EngineeringTestHall") as Node3D
	var ui := facility.get_node("InteractionUI")
	var maintenance: CraneMaintenance = facility.overhead_crane.maintenance
	var access := maintenance.access_panel
	var part := maintenance.component(&"hoist_motor")
	var relay := access.get_node("hoist_motor") as MaintenanceAccessPoint
	actor.global_position = hall.to_global(Vector3(1.95, 0.03, 1.45))
	for unused in 8:
		await physics_frame
	var service := InteractionService.new()
	check(access.find_children("*", "RigidBody3D", false, false).size() == 8,
		"Eight individually addressable relays are reachable from the hall slab")
	actor.camera.look_at(relay.global_position)
	check(service.permitted(actor, actor.camera, relay, actor.interaction_distance),
		"The chosen relay is a normal line-of-sight interaction target from ground level")
	check(relay.collision_layer == 4 and relay.collision_mask == 0 and relay.freeze,
		"Service controls add no obstacle to Otis or machinery")
	check(not relay.query_actions().has(&"repair"), "An operational component does not offer repair")

	part.apply_damage(MaintenanceComponent.Condition.BROKEN, "Positive trolley end stop")
	check(relay.query_actions().has(&"repair") and part.smoke.emitting and part.sparks.emitting
		and not maintenance.motion_allowed(&"hoist", 1.0) and maintenance.motion_allowed(&"hoist", -1.0),
		"A broken motor has localized effects and restricts raising only")
	var uninspected := service.request(&"repair", actor, actor.camera, relay, actor.interaction_distance, actor.knowledge)
	check(not uninspected.ok and part.is_broken(), "Direct repair requires an inspection")
	ui.open_menu(relay)
	check(ui.menu_open and ui.information.text.contains("Broken") and ui.information.text.contains("Positive trolley end stop")
		and ui.information.text.contains("Press E to repair") and actor.knowledge.has_inspected(relay.definition.object_id),
		"Opening the relay inspects its named component and shows condition, fault and E repair")
	var e := InputEventKey.new()
	e.physical_keycode = KEY_E
	e.pressed = true
	ui._input(e)
	check(not ui.menu_open and actor.controls_enabled and ui.status.text == "Hoist motor repaired."
		and part.condition == MaintenanceComponent.Condition.OPERATIONAL and maintenance.motion_allowed(&"hoist", 1.0),
		"E repairs the inspected component, confirms the result, and restores gameplay")
	check(not part.smoke.emitting and not part.sparks.emitting and not part.smoke.visible and not part.sparks.visible,
		"Repair clears residual particles immediately")

	part.apply_damage(MaintenanceComponent.Condition.DAMAGED, "Workshop fault")
	part.repair_requirement = func(_component: MaintenanceComponent) -> String: return "Authorization pending."
	check(not relay.query_actions().has(&"repair") and relay.inspection_information().description.contains("Authorization pending."),
		"A future repair requirement can deny repair and explain why")
	facility.queue_free()
	await process_frame
	print("RD-015A crane service: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

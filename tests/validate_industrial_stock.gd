extends SceneTree

const ARTICLES := {
	"Flat Bar — 20 ft": [Vector3(6.096, 0.0127, 0.1524), 92.62, 1],
	"Round Bar — 20 ft": [Vector3(6.096, 0.0762, 0.0762), 218.23, 1],
	"Wide-Flange Beam — 30 ft": [Vector3(9.144, 0.30988, 0.205232), 676.12, 3],
	"Machinery Test Block — 5 t": [Vector3(1.50, 0.80, 1.00), 5000.0, 1],
}

var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, note: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(note)

func frames(ticks: int) -> void:
	for tick in ticks:
		await physics_frame

func run() -> void:
	var facility := preload("res://scenes/facility.tscn").instantiate()
	root.add_child(facility)
	current_scene = facility
	var hall := facility.get_node("EngineeringTestHall") as Node3D
	var actor := facility.get_node("Otis") as OtisController
	var supply: ScrapSupply = facility.scrap_supply
	await frames(10)
	var industrial := supply.catalog.filter(func(entry: Dictionary) -> bool:
		return entry.get("industrial", false))
	check(industrial.size() == ARTICLES.size() and supply.catalog.size() == 31, "Four industrial articles append to the existing catalog")
	var pad := hall.to_global(ScrapSupply.INDUSTRIAL_PAD)
	actor.global_position = pad + Vector3.UP * 0.025
	await frames(4)
	check(supply.dispense(27) == null, "A person occupying the hall pad blocks industrial delivery")
	actor.global_position = Vector3(-4.8, 0.02, 4.05)
	await frames(4)
	var rack := facility.get_node("DevelopmentScrapRack") as InteractableObject
	actor.camera.look_at(rack.global_position)
	var session: TerminalInteraction = facility.scrap_session
	check(session.enter(), "The existing terminal opens the industrial catalog")
	var panel := session.scrap_panel
	check(panel.stock.item_count == supply.catalog.size(), "Existing spawn UI shows all catalog entries")
	for index in range(27, supply.catalog.size()):
		var data := supply.catalog[index]
		var expected: Array = ARTICLES.get(data.title, [])
		check(not expected.is_empty(), "Expected registered industrial name: " + data.title)
		if expected.is_empty():
			continue
		panel.select_stock(index)
		check(panel.detail.text.contains("ENGINEERING TEST HALL") and panel.detail.text.contains("%.2f kg" % expected[1]),
			"Existing selection shows measured mass and delivery pad")
		var next_id := supply.next_id
		panel.dispense_selected()
		var part := facility.get_node_or_null("Scrap_%d" % next_id) as InteractableObject
		check(part != null and panel.feedback.text.ends_with("to the Engineering Test Hall."),
			"One industrial piece is dispensed through the existing UI")
		if part == null:
			continue
		check(part.global_position.distance_to(pad + Vector3.UP * (float(data.size.y) / 2.0 + 0.05)) < 0.002
			and supply.dispense(index) == null, "Hall delivery uses the authored pose and reserves it in the same frame")
		check(part.query_actions().has(&"inspect") and part.query_actions().has(&"move")
			and part.definition.description.contains(ScrapSupply.dimensions(data.size)),
			"Article is inspected and manipulated using the usual stock interaction")
		var colliders := part.find_children("*", "CollisionShape3D", false, false)
		check(colliders.size() == int(expected[2]), "Article has the intended efficient collider count")
		var bounds: AABB
		for collider: CollisionShape3D in colliders:
			var own_bounds := collider.transform * collider.shape.get_debug_mesh().get_aabb()
			bounds = bounds.merge(own_bounds) if bounds.has_volume() else own_bounds
		check(data.size.is_equal_approx(expected[0]) and bounds.size.distance_to(expected[0]) < 0.002,
			"Catalog and solver geometry have the expected dimensions")
		check(absf(part.mass - float(expected[1])) < 0.03 and not part.freeze and not part.lock_rotation,
			"Runtime mass matches the article and its rotation is free")
		var props := LiftMassProperties.new().resolve(part)
		check(props.is_liftable() and props.confidence == LiftMassProperties.Confidence.KNOWN
			and props.local_center.length() < 0.0001 and props.world_center().is_equal_approx(part.global_position),
			"Standard mass properties report a centered, liftable body")
		await frames(36)
		check(supply.dispense(index) == null, "The delivery pad detects even thin stock after it settles")
		var state := PhysicsServer3D.body_get_direct_state(part.get_rid())
		var inverse_inertia := state.inverse_inertia
		check(inverse_inertia.is_finite() and inverse_inertia.x > 0.0 and inverse_inertia.y > 0.0 and inverse_inertia.z > 0.0,
			"Jolt computes positive inertia from the physical geometry")
		if data.size.x > 5.0:
			check(inverse_inertia.x > maxf(inverse_inertia.y, inverse_inertia.z) * 50.0,
				"Length strongly resists end-over-end rotation relative to axial spin")
		if colliders.size() == 3:
			check_beam_profile(part)
		elif data.title == "Round Bar — 20 ft":
			var shape: CollisionShape3D = colliders[0]
			check(shape.shape is CylinderShape3D and absf(shape.basis.y.dot(Vector3.RIGHT)) > 0.999,
				"Round stock has a real coaxial cylindrical collider")
		part.queue_free()
		await frames(3)
	session.leave()
	var bar := supply.dispense(27)
	await frames(30)
	if bar != null:
		actor.global_position = pad + Vector3(0, 0.03, -1.2)
		await frames(4)
		actor.camera.look_at(bar.global_position)
		check(actor.placement.begin_world(bar) and actor.placement.is_supported_grab(),
			"Long stock uses the existing supported-drag path")
		actor.placement.cancel()
		check(bar.state == InteractableObject.State.WORLD and not bar.lock_rotation,
			"Releasing a supported drag restores natural rotation")
	else:
		check(false, "Long bar is available for the drag test")
	facility.queue_free()
	await frames(2)
	print("RD-015C industrial stock: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

func check_beam_profile(beam: InteractableObject) -> void:
	var space := beam.get_world_3d().direct_space_state
	var between_flanges := PhysicsRayQueryParameters3D.create(
		beam.to_global(Vector3(-4.7, 0, 0.065)), beam.to_global(Vector3(4.7, 0, 0.065)), 1)
	check(space.intersect_ray(between_flanges).is_empty(), "Flange gap is open along the length")
	var toward_web := PhysicsRayQueryParameters3D.create(
		beam.to_global(Vector3(0, 0, 0.18)), beam.to_global(Vector3(0, 0, -0.18)), 1)
	var hit := space.intersect_ray(toward_web)
	check(not hit.is_empty() and hit.collider == beam
		and absf(beam.to_local(hit.position).z - 0.009398 / 2.0) < 0.002,
		"The web has a separate contact surface at its nominal thickness")

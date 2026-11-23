extends SceneTree

var checks := 0
var failures := 0
var fixture := Node3D.new()
var catalog := LiftMassProperties.new()
var fastening := FasteningSystem.new()


func _initialize() -> void:
	run.call_deferred()


func check(value: bool, note: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(note)


func run() -> void:
	root.add_child(fixture)
	fixture.add_child(fastening)
	await validate_body_and_geometry()
	await validate_compound()
	validate_mounts()
	validate_fixtures()
	validate_procedural_stock()
	fixture.queue_free()
	await process_frame
	print("RD-015B lift mass properties: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)


func validate_body_and_geometry() -> void:
	var part := body("Uniform specimen", 12.0, Vector3(-2.0, 5.0, 0.0), Vector3.ONE)
	var collider := part.get_node("CollisionShape3D") as CollisionShape3D
	var info := catalog.resolve(part)
	check(info.mass_kg == 12.0 and info.local_center == Vector3.ZERO and info.is_liftable(),
		"A centered uniform specimen retains its runtime mass and is liftable")
	check(info.confidence == LiftMassProperties.Confidence.ESTIMATED, "Unauthored geometric COM is estimated")
	check(catalog.resolve(part) == info, "Repeated unchanged inspection uses the cached snapshot")
	part.transform = Transform3D(Basis(Vector3.UP, PI / 2.0), Vector3(1, 5, 0))
	check(catalog.resolve(part) == info and info.world_center().is_equal_approx(Vector3(1, 5, 0)),
		"Moving the entire object keeps its cached local center and updates world center")
	collider.position.x = 1.0
	var other := CollisionShape3D.new()
	other.shape = BoxShape3D.new()
	part.add_child(other)
	info = catalog.resolve(part)
	check(info.local_center.is_equal_approx(Vector3(0.5, 0, 0)), "Collision-derived center is local and volume-weighted")
	(other.shape as BoxShape3D).size = Vector3(3, 1, 1)
	var rebuilt := catalog.resolve(part)
	check(rebuilt != info and rebuilt.local_center.is_equal_approx(Vector3(0.25, 0, 0)),
		"Editing shape dimensions invalidates the observed resource and recalculates volume")
	part.definition.properties[&"center_of_mass_local"] = Vector3(0.5, 0.06, 0.0)
	info = catalog.resolve(part)
	check(info.confidence == LiftMassProperties.Confidence.KNOWN and
		info.local_center == Vector3(0.5, 0.06, 0.0), "An authored center supersedes a collision estimate")
	check(info.world_center().is_equal_approx(part.to_global(Vector3(0.5, 0.06, 0))),
		"Authored center transforms from local to world including rotation")
	part.mass = 23.5
	check(catalog.resolve(part).mass_kg == 23.5, "Changing runtime mass updates the cached mass")
	part.state = InteractableObject.State.HELD
	check(not catalog.resolve(part).is_liftable(), "Equipment-controlled bodies are not liftable")
	part.state = InteractableObject.State.WORLD
	part.definition.mass_kg = 0.0
	part.definition.properties[&"density_kg_m3"] = 2.5
	info = catalog.resolve(part)
	check(info.mass_kg == 10.0 and not info.is_liftable(),
		"A density estimate remains available when it differs from authoritative runtime mass")
	part.mass = 10.0
	check(catalog.resolve(part).is_liftable(), "Matching runtime mass permits rigging")
	part.definition.properties[&"density_kg_m3"] = 3.0
	check(catalog.resolve(part).mass_kg == 12.0, "Changing a source material density invalidates the snapshot")
	part.queue_free()
	await process_frame


func validate_compound() -> void:
	var a := body("Frame", 2.0, Vector3(0, 5, 0), Vector3(0.5, 0.5, 0.04))
	var b := body("Motor", 12.0, Vector3(0.09, 5, 0.04), Vector3(0.25, 0.35, 0.04))
	a.definition.properties[&"center_of_mass_local"] = Vector3.ZERO
	b.definition.properties[&"center_of_mass_local"] = Vector3(0.075, 0.06, 0)
	var initial := catalog.resolve(a)
	await physics_frame
	await physics_frame
	var round := fastening.create_round(FasteningTool.GRADES[0])
	var issue := fastening.install(round, Vector3(0.07, 5, -0.9), Vector3.BACK, 2.0)
	check(issue.is_empty(), "Test stock can be attached with a normal Uni-Bolt: " + issue)
	if not issue.is_empty():
		a.queue_free()
		b.queue_free()
		await process_frame
		return
	var assembly := catalog.resolve(a)
	var expected := (a.global_position * 2.0 + b.to_global(Vector3(0.075, 0.06, 0)) * 12.0) / 14.0
	check(assembly != initial and assembly.root == b and assembly.members.has(a) and assembly.members.has(b)
		and assembly.members.size() == 2, "Connecting unequal-mass components resolves either ray-hit member to the solver root")
	check(assembly.mass_kg == 14.0 and b.mass == 14.0 and assembly.is_liftable(),
		"Compound mass sums members once, matching the existing physics root")
	check(assembly.world_center().is_equal_approx(expected) and assembly.confidence == LiftMassProperties.Confidence.KNOWN,
		"Compound center is mass-weighted, uses individual authored offsets, and retains known status")
	check(catalog.resolve(b) == assembly, "Resolving another member of the same island reuses its snapshot")
	b.transform = Transform3D(Basis(Vector3.UP, PI * 0.3), Vector3(0, 4, -3))
	check(catalog.resolve(a) == assembly and assembly.world_center().is_equal_approx(b.to_global(assembly.local_center)),
		"Rigid compound movement transforms its center without recalculation")
	b.set_meta(&"rig_original_mass_center", {"mode": b.center_of_mass_mode, "center": b.center_of_mass})
	b.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	b.center_of_mass = assembly.local_center
	check(catalog.resolve(a) == assembly, "The temporary physics COM for lifting does not double-count a compound offset")
	b.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_AUTO
	b.remove_meta(&"rig_original_mass_center")
	check(fastening.remove(round), "The real fastener can be removed")
	var split := catalog.resolve(a)
	check(split.root == a and split.members.size() == 1 and split.mass_kg == 2.0
		and catalog.resolve(b).mass_kg == 12.0, "Separation invalidates membership and restores each mass")
	a.queue_free()
	b.queue_free()
	await process_frame


func validate_mounts() -> void:
	var base := component("Fixture base", 100.0, Vector3(4, 5, 3))
	var motor := component("Mounted motor", 20.0, Vector3(4, 5, 4))
	var assembly := MechanicalAssembly.new()
	base.add_child(assembly)
	var mount_definition := MountDefinition.new()
	mount_definition.mount_id = &"motor"
	mount_definition.accepted_tags = [&"test"]
	mount_definition.attachment.origin = Vector3.FORWARD
	mount_definition.connection = MechanicalConnection.new()
	var mount := assembly.add_mount(mount_definition)
	check(mount.seed(motor), "Test motor is mounted in the modeled assembly")
	var info := catalog.resolve(motor)
	check(info.root == base and info.members.size() == 2 and info.mass_kg == 120.0,
		"Mechanical mount membership is included in mass inspection")
	check(not info.is_liftable(), "Separately colliding mounted bodies are inspected but cannot be rigged as an unmerged island")
	motor.integrity = MechanicalComponent.Integrity.DAMAGED
	check(info != catalog.resolve(base), "An integrity change invalidates the assembly snapshot")
	check(mount.remove().is_empty() and catalog.resolve(base).mass_kg == 100.0,
		"Removing a mounted component restores the base-only mass")
	base.queue_free()
	motor.queue_free()


func validate_fixtures() -> void:
	var equipment := LayoutPlaceholder.new()
	fixture.add_child(equipment)
	equipment.configure({"type": "engine_lathe", "position": Vector3.ZERO, "size": Vector3(3, 1.4, 1.0),
		"yaw": PI, "name": "Layout lathe", "id": "lathe", "properties": {}})
	var collider := equipment.get_node("PlaceholderCollision") as StaticBody3D
	var info := catalog.resolve(collider)
	check(info.display_name == "Layout lathe" and info.mass_kg > 1000.0
		and info.confidence == LiftMassProperties.Confidence.ESTIMATED, "Shop fixtures expose authored mass estimates")
	check(info.local_center.x < 0.0 and info.world_center().x > 0.0 and not info.is_liftable(),
		"Lathe center accounts for headstock and hall transform, preserving static gameplay")
	var wall := StaticBody3D.new()
	fixture.add_child(wall)
	check(catalog.resolve(wall).root == null, "Plain architecture does not produce a rigging overlay")
	equipment.queue_free()
	wall.queue_free()


func validate_procedural_stock() -> void:
	var signed := -1.0
	for entry in ScrapCatalog.entries():
		var center: Vector3 = entry.center_of_mass
		check(center.is_finite() and entry.mass > 0.0, "Finite density-derived properties for " + entry.title)
		if entry.category == "Triangular gusset":
			check(is_equal_approx(center.x, -entry.size.x / 6.0)
				and is_equal_approx(center.z, -entry.size.z / 6.0), "Triangular prism uses the area centroid")
		if entry.category == "Angle iron":
			signed = maxf(signed, center.z)
	check(signed < -0.01, "Uneven angle iron leg geometry shifts the procedural mass center")


func body(title: String, kilograms: float, point: Vector3, size: Vector3,
		item: InteractableObject = null) -> InteractableObject:
	var part := item if item != null else InteractableObject.new()
	part.name = title
	part.definition = ObjectDefinition.new()
	part.definition.display_name = title
	part.definition.mobility = ObjectDefinition.Mobility.MOVABLE
	part.definition.mass_kg = kilograms
	part.gravity_scale = 0.0
	var collider := CollisionShape3D.new()
	collider.name = "CollisionShape3D"
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	part.add_child(collider)
	part.position = point
	fixture.add_child(part)
	return part


func component(title: String, kilograms: float, point: Vector3) -> MechanicalComponent:
	var part := MechanicalComponent.new()
	part.profile = ComponentProfile.new()
	part.profile.tags = [&"test"]
	body(title, kilograms, point, Vector3(0.25, 0.30, 0.4), part)
	return part

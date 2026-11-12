extends Node3D
## Primitive-only room. Collision follows the same dimensions as presentation.
const PLATE_CENTER := Vector3(2.7, 0, 1.4)
const PLATE_WIDTH := 2.1
var generator: MechanicalComponent
var load_plate: PhysicalLoadSensor
var barrier: PoweredBarrier
var barrier_control: BarrierController
var administration: AdministrativeSession
var terminal_session: TerminalInteraction
var _barrier_was_blocked := false


## A null seed uses new manufacturing variance on every Facility instance.
var chassis_seed: Variant = null

func _ready() -> void:
	$Otis.chassis = AndroidChassis.generate(randi() if chassis_seed == null else int(chassis_seed))
	var floor_mat := material(Color("343f46"))
	var wall_mat := material(Color("697579"))
	var dark := material(Color("202c33"))
	var amber := material(Color("c89a43"))
	var glow := material(Color("a2e7df"), true)
	var floor := box(self, "Floor", Vector3(12.4, 0.3, 12.4), Vector3(0, -0.15, 0), floor_mat, true)
	box(self, "Ceiling", Vector3(12.4, 0.3, 12.4), Vector3(0, 4.15, 0), dark, true)
	box(self, "NorthWall", Vector3(12.4, 4, 0.2), Vector3(0, 2, -6.1), wall_mat, true)
	box(self, "SouthWall", Vector3(12.4, 4, 0.2), Vector3(0, 2, 6.1), wall_mat, true)
	box(self, "WestWall", Vector3(0.2, 4, 12), Vector3(-6.1, 2, 0), wall_mat, true)
	box(self, "EastWall", Vector3(0.2, 4, 12), Vector3(6.1, 2, 0), wall_mat, true)
	for x in [-5.9, 5.9]:
		box(self, "WallStripe", Vector3(0.025, 0.13, 12), Vector3(x, 1.0, 0), amber)
	for x in [-4, 0, 4]:
		box(self, "FloorSeam", Vector3(0.025, 0.005, 12), Vector3(x, 0.003, 0), dark)
	for z in [-4, 0, 4]:
		box(self, "FloorSeam", Vector3(12, 0.005, 0.025), Vector3(0, 0.003, z), dark)
	for x in [-3.0, 3.0]:
		for z in [-3.0, 3.0]:
			box(self, "LightHousing", Vector3(2, 0.12, 0.55), Vector3(x, 3.91, z), dark)
			box(self, "LightStrip", Vector3(1.8, 0.03, 0.4), Vector3(x, 3.83, z), glow)
			var light := OmniLight3D.new()
			light.position = Vector3(x, 3.4, z)
			light.light_color = Color("c4e2e9")
			light.light_energy = 1.5
			light.omni_range = 8
			add_child(light)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("27343c")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("a8bec8")
	environment.environment.ambient_light_energy = 0.55
	add_child(environment)
	var crate := make_object("crate", Vector3(-2.5, 0.65, -0.5), Vector3(1.3, 1.3, 1.3), material(Color("986a43")))
	for y in [-0.48, 0.48]:
		box(crate, "CrateBand", Vector3(1.34, 0.1, 1.34), Vector3(0, y, 0), dark)
	build_machinery(floor as StaticBody3D, dark, amber)
	var wrench := make_object("wrench", Vector3(1.0, 0.043, -1.25), Vector3(0.11, 0.08, 0.35), dark)
	wrench.get_node("Model").queue_free()
	var steel := material(Color("b0bdc4"))
	box(wrench, "Handle", Vector3(0.045, 0.04, 0.25), Vector3(0, 0, 0.035), steel)
	box(wrench, "JawLeft", Vector3(0.035, 0.05, 0.11), Vector3(-0.0375, 0, -0.11), steel)
	box(wrench, "JawRight", Vector3(0.035, 0.05, 0.11), Vector3(0.0375, 0, -0.11), steel)
	box(wrench, "JawBridge", Vector3(0.11, 0.05, 0.035), Vector3(0, 0, -0.05), steel)
	administration = AdministrativeSession.new()
	add_child(administration)
	var terminal := TerminalWorkstation.new()
	terminal.name = "Terminal"
	terminal.definition = preload("res://data/objects/terminal.tres")
	terminal.position = Vector3(0, 1.6, -5.8)
	add_child(terminal)
	terminal_session = TerminalInteraction.new()
	terminal_session.name = "TerminalInteraction"
	add_child(terminal_session)
	terminal_session.configure($Otis, terminal, administration, terminal.screen, terminal.view_anchor, terminal.display)
	terminal_session.active_changed.connect($InteractionUI.set_terminal_active)
	label_at(self, "RD / 001   •   SYSTEMS TEST CHAMBER", Vector3(0, 3.05, -5.96), 42)
	label_at(crate, "STORAGE\n001", Vector3(0, 0, 0.66), 26)
	build_load_station(floor as StaticBody3D, dark, amber, steel)

func build_machinery(floor: StaticBody3D, dark: Material, amber: Material) -> void:
	var foundation := MechanicalAssembly.new()
	foundation.name = "FacilityMounts"
	floor.add_child(foundation)
	var anchors := mount_spec(&"floor_anchors", Vector3(2.7, 0.95, -2.5), &"industrial_base", 2000.0)
	anchors.removable = false
	anchors.release_offset = Vector3.UP * 0.025
	var floor_mount := foundation.add_mount(anchors)
	var housing := load("res://data/objects/generator.tres") as ObjectDefinition
	generator = mechanical_part(housing, &"industrial_base", Vector3(2, 1.6, 1.2), material(Color("54756a")))
	generator.name = "Generator"
	floor_mount.seed(generator)
	var assembly := MechanicalAssembly.new()
	assembly.name = "Assembly"
	assembly.power_source = PowerSourceDefinition.new()
	assembly.power_source.stage = PowerSourceDefinition.Stage.INDUSTRIAL
	generator.add_child(assembly)
	for y in [-0.3, -0.1, 0.1, 0.3]:
		box(generator, "Vent", Vector3(0.55, 0.055, 0.04), Vector3(-0.49, y, 0.62), dark)
	label_at(generator, "AUX / 01", Vector3(-0.48, 0.53, 0.625), 24)
	# The service bay projects from the housing face so its empty volume is usable.
	for x in [0.10, 0.92]:
		box(generator, "BayRail", Vector3(0.045, 0.85, 0.39), Vector3(x, 0.04, 0.81), dark, true)
	for y in [-0.36, 0.44]:
		box(generator, "BayRail", Vector3(0.78, 0.045, 0.39), Vector3(0.51, y, 0.81), dark, true)
	var cover_spec := mount_spec(&"access_panel", Vector3(0.51, 0.04, 1.07), &"aux_cover", 150.0)
	var core_spec := mount_spec(&"power_module", Vector3(0.51, 0.04, 0.83), &"aux_power", 500.0)
	core_spec.requires_vacant = [&"access_panel"]
	core_spec.approach_distance = 0.18
	core_spec.required_for_operation = true
	core_spec.release_offset = Vector3(0, 0, 0.38)
	var core := mechanical_part(part_definition(&"RD-GEN-CORE", "Power module", 12.0),
		&"aux_power", Vector3(0.48, 0.49, 0.32), amber)
	core.profile.functional_properties = {&"role": &"power_conversion"}
	label_at(core, "POWER / III", Vector3(0, 0.06, 0.162), 13, Color("202c33"))
	var module_mount := assembly.add_mount(core_spec)
	var panel_mount := assembly.add_mount(cover_spec)
	module_mount.seed(core)
	var cover := mechanical_part(part_definition(&"RD-GEN-PANEL", "Access panel", 4.0),
		&"aux_cover", Vector3(0.84, 0.86, 0.08), material(Color("63736d")))
	label_at(cover, "SERVICE ACCESS", Vector3(0, 0.04, 0.044), 16)
	panel_mount.seed(cover)

	var fixture_definition := part_definition(&"RD-FIX-BASE", "Mechanical test fixture", 70.0)
	fixture_definition.mobility = ObjectDefinition.Mobility.FIXED
	var fixture_base := mechanical_part(fixture_definition, &"fixture_base", Vector3(0.75, 0.62, 0.6), dark)
	fixture_base.name = "MountTestFixture"
	fixture_base.position = Vector3(-4.6, 0.31, -2.7)
	var fixture := MechanicalAssembly.new()
	fixture.name = "Assembly"
	fixture_base.add_child(fixture)
	var socket_height := 0.12
	var socket_spec := mount_spec(&"battery_socket", Vector3(0, socket_height, 0.43), &"keyed_battery", 50.0)
	socket_spec.keyed = true
	socket_spec.position_tolerance = 0.045
	socket_spec.angle_tolerance_degrees = 30.0
	socket_spec.release_offset = Vector3(0, 0, 0.16)
	var socket := fixture.add_mount(socket_spec)
	var rim := material(Color("687c81"))
	for segment in range(1, 16):
		# The missing top segment is the longitudinal keyway.
		var angle := TAU * segment / 16.0
		var radial := Vector3(sin(angle), cos(angle), 0)
		var wall := box(fixture_base, "SocketWall", Vector3(0.026, 0.024, 0.13),
			Vector3(0, socket_height, 0.369) + radial * 0.067, rim if segment in [1, 15] else dark, true)
		wall.rotation.z = -angle
	var battery := MechanicalComponent.new()
	battery.name = "BatteryCartridge"
	battery.definition = part_definition(&"RD-FIX-BATTERY", "Keyed battery cartridge", 2.0)
	battery.definition.description = "A keyed industrial cartridge. Insert the silver terminal first, with the raised ridge facing the socket slot."
	battery.profile = ComponentProfile.new()
	battery.profile.tags = [&"keyed_battery"]
	add_child(battery)
	cylinder(battery, 0.040, 0.166, 0.0, amber)
	cylinder(battery, 0.037, 0.018, 0.091, dark)
	var terminal := material(Color("b7c9cc"))
	cylinder(battery, 0.036, 0.020, -0.090, terminal)
	cylinder(battery, 0.018, 0.008, -0.102, terminal)
	box(battery, "KeyRidge", Vector3(0.014, 0.016, 0.153), Vector3(0, 0.043, -0.005), rim)
	var hull_points := PackedVector3Array()
	for end in [-0.100, 0.100]:
		for segment in 16:
			var angle := TAU * segment / 16.0
			hull_points.append(Vector3(cos(angle) * 0.040, sin(angle) * 0.040, end))
	for x in [-0.007, 0.007]:
		for z in [-0.0815, 0.0715]:
			hull_points.append(Vector3(x, 0.051, z))
	for segment in 8:
		var angle := TAU * segment / 8.0
		hull_points.append(Vector3(cos(angle) * 0.018, sin(angle) * 0.018, -0.106))
	var hull := ConvexPolygonShape3D.new()
	hull.points = hull_points
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	collision.shape = hull
	battery.add_child(collision)
	socket.seed(battery)
	var future_pivot := mount_spec(&"future_pivot", Vector3(0, 0.14, 0.34), &"keyed_battery", 0.0)
	future_pivot.connection.kind = MechanicalConnection.Kind.REVOLUTE
	future_pivot.connection.axis = Vector3.FORWARD
	fixture.add_mount(future_pivot)
	label_at(fixture_base, "BATTERY  /  KEY UP", Vector3(0, -0.06, 0.305), 14)

func cylinder(parent: Node3D, radius: float, length: float, z: float, surface: Material) -> void:
	var model := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = length
	mesh.radial_segments = 16
	mesh.rings = 0
	model.mesh = mesh
	model.material_override = surface
	model.rotation.x = PI * 0.5
	model.position.z = z
	parent.add_child(model)

func mount_spec(id: StringName, offset: Vector3, tag: StringName, strength: float) -> MountDefinition:
	var spec := MountDefinition.new()
	spec.mount_id = id
	spec.attachment.origin = offset
	spec.accepted_tags = [tag]
	spec.connection = MechanicalConnection.new()
	spec.connection.failure_enabled = strength > 0.0
	spec.connection.failure_threshold = strength
	return spec

func part_definition(id: StringName, title: String, kilograms: float) -> ObjectDefinition:
	var definition := ObjectDefinition.new()
	definition.object_id = id
	definition.display_name = title
	definition.mass_kg = kilograms
	definition.mobility = ObjectDefinition.Mobility.MOVABLE
	return definition

func mechanical_part(definition: ObjectDefinition, tag: StringName, size: Vector3,
		surface: Material) -> MechanicalComponent:
	var part := MechanicalComponent.new()
	part.definition = definition
	part.profile = ComponentProfile.new()
	part.profile.tags = [tag]
	add_child(part)
	box(part, "Model", size, Vector3.ZERO, surface)
	add_shape(part, size, Vector3.ZERO)
	part.get_child(part.get_child_count() - 1).name = "CollisionShape3D"
	return part

func build_load_station(floor: StaticBody3D, dark: Material, amber: Material, steel: Material) -> void:
	load_plate = PhysicalLoadSensor.new()
	load_plate.name = "LoadPlate"
	load_plate.sensor_id = &"RD-LOAD-001"
	load_plate.definition = ObjectDefinition.new()
	load_plate.definition.object_id = load_plate.sensor_id
	load_plate.definition.display_name = "Industrial load sensor"
	load_plate.definition.description = "A flush steel platform connected to the sliding barrier. Load must persist for 0.4 seconds."
	load_plate.position = PLATE_CENTER
	load_plate.support_surface = floor
	load_plate.surface_size = Vector2.ONE * PLATE_WIDTH
	load_plate.output = EnvironmentalSignal.new()
	load_plate.output.source_id = &"RD-LOAD-001-OUT"
	load_plate.add_child(load_plate.output)
	load_plate.detection_area = Area3D.new()
	load_plate.detection_area.collision_layer = 0
	load_plate.detection_area.collision_mask = 3
	load_plate.detection_area.monitorable = false
	load_plate.add_child(load_plate.detection_area)
	add_shape(load_plate.detection_area, Vector3(PLATE_WIDTH + 0.1, 3.9, PLATE_WIDTH + 0.1), Vector3(0, 1.9, 0))
	add_shape(load_plate, Vector3(PLATE_WIDTH, 0.01, PLATE_WIDTH), Vector3(0, 0.005, 0))
	add_child(load_plate)
	# The continuous floor carries load. This thin layer is for inspection rays.
	load_plate.collision_layer = 4
	load_plate.collision_mask = 0
	var deck := Node3D.new()
	load_plate.add_child(deck)
	box(deck, "Deck", Vector3(PLATE_WIDTH, 0.16, PLATE_WIDTH), Vector3(0, -0.066, 0), dark)
	for x in [-0.91, 0.91]:
		for z in [-0.8, -0.4, 0, 0.4, 0.8]:
			box(deck, "Hazard", Vector3(0.13, 0.005, 0.24), Vector3(x, 0.018, z), amber)
	var indicator := material(Color("d25042"), true)
	box(load_plate, "Indicator", Vector3(0.26, 0.016, 0.07), Vector3(0, 0.023, 0.94), indicator)
	load_plate.output.output_changed.connect(func(active: bool) -> void:
		indicator.emission = Color("57ed86") if active else Color("d25042")
		indicator.albedo_color = indicator.emission
		deck.position.y = -0.009 if active else 0.0
		log_environment("%s output %s" % [load_plate.sensor_id, active]))
	var weight := make_object("test_weight", Vector3(4.4, 0.13, 2.1), Vector3(0.29, 0.23, 0.29), steel)
	weight.name = "TestWeight"
	label_at(weight, "8 KG", Vector3(0, 0, 0.15), 24, Color("202c33"))

	barrier = PoweredBarrier.new()
	barrier.name = "SteelBarrier"
	barrier.barrier_id = &"RD-GATE-001"
	barrier.closed_position = Vector3(4.65, 1.0, -4.35)
	barrier.open_position = Vector3(4.65, 2.97, -4.35)
	barrier.collision_layer = 1
	barrier.collision_mask = 3
	add_shape(barrier, Vector3(1.88, 1.92, 0.18), Vector3.ZERO)
	box(barrier, "SteelPanel", Vector3(1.88, 1.92, 0.18), Vector3.ZERO, steel)
	box(barrier, "CautionBand", Vector3(1.88, 0.13, 0.012), Vector3(0, -0.71, 0.096), amber)
	label_at(barrier, "GATE 01", Vector3(0, 0.1, 0.1), 36, Color("202c33"))
	add_child(barrier)
	for x in [3.53, 5.77]:
		box(self, "GatePost", Vector3(0.29, 3.95, 0.38), Vector3(x, 1.975, -4.35), dark, true)
	box(self, "PlateConduit", Vector3(0.07, 0.007, 4.7), Vector3(3.79, 0.005, -1.55), amber)
	box(self, "ConduitEnd", Vector3(0.92, 0.007, 0.07), Vector3(4.22, 0.005, -3.87), amber)
	barrier_control = BarrierController.new()
	barrier_control.actuator = barrier
	barrier_control.inputs = [load_plate.output]
	add_child(barrier_control)
	barrier.state_changed.connect(_barrier_changed)

func _barrier_changed(state: PoweredBarrier.State) -> void:
	log_environment("%s %s" % [barrier.barrier_id, barrier.state_name()])
	var blocked := state == PoweredBarrier.State.BLOCKED
	if blocked == _barrier_was_blocked:
		return
	_barrier_was_blocked = blocked
	administration.publish_event(&"BARRIER_OBSTRUCTED" if blocked else &"BARRIER_RESTORED",
		barrier.barrier_id, {"state": barrier.state_name()})


func add_shape(body: CollisionObject3D, size: Vector3, at: Vector3) -> void:
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collider.shape = shape
	collider.position = at
	body.add_child(collider)

func environmental_diagnostics() -> String:
	return "\n%s  %.1f / %.1f kg\nPLATE %s  %s %s\n%s  INPUT %s\nGATE %s  OBSTRUCTED %s" % [
		load_plate.sensor_id, load_plate.measured_kg, load_plate.activation_kg,
		"ACTIVE" if load_plate.is_active() else "INACTIVE",
		load_plate.output.source_id if is_instance_valid(load_plate.output) else &"UNAVAILABLE", load_plate.is_active(),
		barrier.barrier_id, barrier_control.input_active, barrier.state_name(), barrier.state == PoweredBarrier.State.BLOCKED]

func log_environment(message: String) -> void:
	if $InteractionUI.debug_visible:
		print("[Facility] ", message)

func material(color: Color, emissive: bool = false) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = 0.85
	if emissive:
		result.emission_enabled = true
		result.emission = color
	return result

func box(parent: Node3D, title: String, size: Vector3, at: Vector3,
		mat: Material, solid: bool = false) -> Node3D:
	var root: Node3D = StaticBody3D.new() if solid else Node3D.new()
	root.name = title
	root.position = at
	parent.add_child(root)
	var mesh := MeshInstance3D.new()
	var cube := BoxMesh.new()
	cube.size = size
	mesh.mesh = cube
	mesh.material_override = mat
	root.add_child(mesh)
	if solid:
		var collider := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		collider.shape = shape
		root.add_child(collider)
	return root

func make_object(kind: String, at: Vector3, size: Vector3, mat: Material) -> InteractableObject:
	var object := InteractableObject.new()
	object.name = kind.capitalize()
	object.definition = load("res://data/objects/%s.tres" % kind)
	object.position = at
	add_child(object)
	box(object, "Model", size, Vector3.ZERO, mat)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.name = "CollisionShape3D"
	collision.shape = shape
	object.add_child(collision)
	return object

func label_at(parent: Node3D, text: String, at: Vector3, size: int, color: Color = Color.WHITE) -> void:
	var label := Label3D.new()
	label.text = text
	label.position = at
	label.font_size = size
	label.pixel_size = 0.004
	label.modulate = color
	parent.add_child(label)

class_name CraneGeometry
extends Node3D
## Low-poly presentation in hall-local coordinates. Motion and the unloaded
## suspension own their state independently of these render nodes.

const END_CLEARANCE := 0.90
const TROLLEY_INSET := 0.89
const RUNWAY_INSET := 0.574
const OUTLET_DROP := 0.77
const PRESENTATION_TOP := 0.485
const CHAIN_PITCH := 0.09

var bridge_min: float
var bridge_max: float
var trolley_min: float
var trolley_max: float
var suspension_origin_y: float
var component_anchors: Dictionary = {}
var bridge: Node3D
var trolley: Node3D
var hook: Node3D
var hoist_outlet: Marker3D
var hook_anchor: Marker3D

var _rail_height: float
var _chain: MultiMesh
var _chain_length := -1.0
var _paint := finish("a48140", 0.12)
var _panel := finish("737d7c")
var _frame := finish("3c4449")
var _steel := finish("585f62")
var _wheel := finish("2e3338")
var _metal := finish("909898")
var _warning := finish("d8ad49", 0.15)
var _pilot := finish("638370", 0.60)

func build(hall_width: float, hall_depth: float, rail_height: float) -> void:
	_rail_height = rail_height
	bridge_min = END_CLEARANCE
	bridge_max = hall_depth - END_CLEARANCE
	trolley_max = hall_width / 2.0 - TROLLEY_INSET
	trolley_min = -trolley_max
	suspension_origin_y = rail_height - OUTLET_DROP
	var rail_x := hall_width / 2.0 - RUNWAY_INSET
	var runway := group(self, &"Runways")
	for side: float in [-1.0, 1.0]:
		build_runway(runway, side, rail_x, hall_depth)
	bridge = group(self, &"Bridge")
	build_bridge(rail_x)
	trolley = group(bridge, &"Trolley")
	build_trolley()
	hook = group(trolley, &"HookBlock")
	build_hook()
	build_chain()
	pose(bridge_min, 0.0, suspension_origin_y - 1.4, 0.0)

func pose(bridge_z: float, trolley_x: float, hook_y: float, hook_yaw: float) -> void:
	bridge.position.z = bridge_z
	trolley.position.x = trolley_x
	hook.position.y = hook_y
	hook.rotation.y = hook_yaw
	# The upper falls do not rotate with the freely swiveling hook.
	var length := maxf(0.0, suspension_origin_y - hook_y - 0.23)
	if not is_equal_approx(length, _chain_length):
		pose_chain(length)

func build_runway(runway: Node3D, side: float, rail_x: float, depth: float) -> void:
	var rail := group(runway, &"WestRunway" if side < 0.0 else &"EastRunway",
		Vector3(side * rail_x, _rail_height, depth / 2.0))
	var length := depth - 0.34
	box(rail, &"SupportWeb", Vector3(0.085, 0.31, length), Vector3(0, -0.26, 0), _frame)
	for y: float in [-0.42, -0.10]:
		box(rail, &"SupportFlange", Vector3(0.20, 0.047, length), Vector3(0, y, 0), _frame)
	box(rail, &"RunnerBase", Vector3(0.16, 0.04, length), Vector3(0, -0.064, 0), _steel)
	box(rail, &"RunnerHead", Vector3(0.081, 0.045, length), Vector3(0, -0.023, 0), _metal)
	# The brackets land on the hall's five existing portal frames.
	for index in range(5):
		var z := clampf(depth * index * 0.25, 0.24, depth - 0.24) - depth / 2.0
		box(rail, &"ColumnSeat", Vector3(0.60, 0.12, 0.35), Vector3(side * 0.28, -0.48, z), _steel)
		box(rail, &"ColumnCleat", Vector3(0.12, 0.53, 0.29), Vector3(side * 0.33, -0.76, z), _frame)
		var brace := box(rail, &"KneeBrace", Vector3(0.09, 0.43, 0.16),
			Vector3(side * 0.205, -0.69, z), _frame)
		brace.rotation.z = -side * 0.58
	for directional_end: float in [-1.0, 1.0]:
		var z := directional_end * (depth / 2.0 - 0.14)
		box(rail, &"StopPedestal", Vector3(0.20, 0.25, 0.15), Vector3(0, 0.08, z), _paint)
		box(rail, &"StopBuffer", Vector3(0.18, 0.12, 0.09), Vector3(0, 0.11, z - directional_end * 0.065), _wheel)

func build_bridge(rail_x: float) -> void:
	var height := _rail_height
	var length := rail_x * 2.0
	box(bridge, &"GirderWeb", Vector3(length, 0.37, 0.26), Vector3(0, height + 0.21, 0), _paint)
	box(bridge, &"UpperFlange", Vector3(length, 0.064, 0.48), Vector3(0, height + 0.438, 0), _paint)
	box(bridge, &"LowerFlange", Vector3(length, 0.068, 0.50), Vector3(0, height + 0.046, 0), _paint)
	box(bridge, &"TrolleyTrack", Vector3(length - 0.08, 0.021, 0.50), Vector3(0, height + 0.089, 0), _steel)
	for fraction: float in [-0.82, -0.56, -0.30, -0.08, 0.08, 0.30, 0.56, 0.82]:
		box(bridge, &"WebStiffener", Vector3(0.055, 0.34, 0.32),
			Vector3(rail_x * fraction, height + 0.216, 0), _paint)
	for side: float in [-1.0, 1.0]:
		build_end_truck(side, rail_x)
		var plaque := group(bridge, &"CapacityMarking", Vector3(0, height + 0.233, side * 0.252))
		if side < 0.0:
			plaque.rotation.y = PI
		box(plaque, &"CapacityPlate", Vector3(2.15, 0.27, 0.24), Vector3.ZERO, _frame)
		var label := Label3D.new()
		label.name = &"RatedCapacity"
		label.text = "OC-01   /   50 t"
		label.font_size = 96
		label.pixel_size = 0.002
		label.outline_size = 0
		label.modulate = Color("e1d6b2")
		label.position.z = 0.123
		plaque.add_child(label)

func build_end_truck(side: float, rail_x: float) -> void:
	var code := "a" if side < 0.0 else "b"
	var truck := group(bridge, &"WestEndTruck" if side < 0.0 else &"EastEndTruck",
		Vector3(side * rail_x, _rail_height, 0))
	box(truck, &"TruckFrame", Vector3(0.28, 0.26, 1.12), Vector3(0, 0.29, 0), _paint)
	box(truck, &"TruckSpine", Vector3(0.22, 0.07, 1.21), Vector3(0, 0.45, 0), _paint)
	for z: float in [-0.39, 0.39]:
		cylinder(truck, &"TravelWheel", 0.137, 0.145, Vector3(0, 0.137, z), Vector3.RIGHT, _wheel)
		cylinder(truck, &"Hub", 0.067, 0.23, Vector3(0, 0.137, z), Vector3.RIGHT, _metal)
	for face: float in [-1.0, 1.0]:
		box(truck, &"EndBuffer", Vector3(0.19, 0.16, 0.07), Vector3(0, 0.15, face * 0.61), _wheel)
		box(truck, &"EndWarning", Vector3(0.12, 0.031, 0.008), Vector3(0, 0.19, face * 0.647), _warning)
	box(truck, &"DriveCase", Vector3(0.17, 0.22, 0.26), Vector3(-side * 0.185, 0.19, 0.26), _panel)
	anchor(truck, "bridge_roller_" + code, Vector3(-side * 0.115, 0.12, -0.40))
	anchor(truck, "bridge_drive_" + code, Vector3(-side * 0.282, 0.16, 0.26))

func build_trolley() -> void:
	var y := _rail_height
	for side: float in [-1.0, 1.0]:
		box(trolley, &"GuideCheek", Vector3(0.36, 0.54, 0.075),
			Vector3(0, y - 0.08, side * 0.33), _frame)
		for x: float in [-0.115, 0.115]:
			cylinder(trolley, &"TrolleyRoller", 0.082, 0.12,
				Vector3(x, y + 0.18, side * 0.247), Vector3.BACK, _wheel)
			cylinder(trolley, &"TrolleyHub", 0.034, 0.17,
				Vector3(x, y + 0.18, side * 0.247), Vector3.BACK, _metal)
	box(trolley, &"TrolleyChassis", Vector3(0.40, 0.12, 0.73), Vector3(0, y - 0.34, 0), _paint)
	box(trolley, &"HoistHousing", Vector3(0.56, 0.24, 0.56), Vector3(0, y - 0.62, 0), _panel)
	cylinder(trolley, &"HoistDrum", 0.16, 0.31, Vector3(0, y - 0.57, 0.31), Vector3.RIGHT, _steel)
	for side: float in [-1.0, 1.0]:
		cylinder(trolley, &"DrumFlange", 0.179, 0.038,
			Vector3(side * 0.175, y - 0.57, 0.31), Vector3.RIGHT, _paint)
		box(trolley, &"DriveGuard", Vector3(0.13, 0.18, 0.31),
			Vector3(side * 0.255, y - 0.66, -0.12), _paint)
		var drive_id := "trolley_drive_a" if side < 0.0 else "trolley_drive_b"
		anchor(trolley, drive_id, Vector3(side * 0.326, y - 0.696, -0.15))
	anchor(trolley, "hoist_motor", Vector3(-0.17, y - 0.55, 0.47))
	anchor(trolley, "hoist_brake", Vector3(0.17, y - 0.55, 0.47))
	box(trolley, &"RunIndicator", Vector3(0.09, 0.045, 0.008), Vector3(0, y - 0.61, -0.284), _pilot)
	hoist_outlet = Marker3D.new()
	hoist_outlet.name = &"HoistOutlet"
	hoist_outlet.position.y = suspension_origin_y
	trolley.add_child(hoist_outlet)

func build_hook() -> void:
	box(hook, &"BlockHousing", Vector3(0.46, 0.33, 0.30), Vector3(0, 0.063, 0), _paint)
	for side: float in [-1.0, 1.0]:
		box(hook, &"BlockSidePlate", Vector3(0.49, 0.25, 0.045), Vector3(0, 0.060, side * 0.164), _frame)
		for sign_x: float in [-1.0, 1.0]:
			cylinder(hook, &"SheaveAxle", 0.048, 0.055, Vector3(sign_x * 0.133, 0.066, side * 0.17), Vector3.BACK, _metal)
			var diagonal := box(hook, &"BlockWarning", Vector3(0.029, 0.118, 0.009),
				Vector3(sign_x * 0.061, 0.059, side * 0.193), _warning)
			diagonal.rotation.z = side * -0.55
	cylinder(hook, &"SwivelCollar", 0.095, 0.11, Vector3(0, -0.12, 0), Vector3.UP, _steel)
	var stem := cylinder(hook, &"HookShank", 0.042, 0.125, Vector3(-0.045, -0.18, 0), Vector3.UP, _metal)
	stem.rotation.z = -0.53
	var hook_profile := MeshInstance3D.new()
	hook_profile.name = &"ForgedHook"
	hook_profile.mesh = hook_mesh()
	hook_profile.material_override = _metal
	hook.add_child(hook_profile)
	var latch := box(hook, &"Latch", Vector3(0.16, 0.025, 0.030), Vector3(0.015, -0.239, 0), _steel)
	latch.rotation.z = 0.05
	hook_anchor = Marker3D.new()
	hook_anchor.name = &"HookAttachment"
	hook_anchor.position = Vector3(0, -0.34, 0)
	hook.add_child(hook_anchor)

func build_chain() -> void:
	var chain_link := TorusMesh.new()
	chain_link.inner_radius = 0.026
	chain_link.outer_radius = 0.052
	chain_link.rings = 8
	chain_link.ring_segments = 5
	_chain = MultiMesh.new()
	_chain.transform_format = MultiMesh.TRANSFORM_3D
	_chain.mesh = chain_link
	_chain.instance_count = ceili(suspension_origin_y / CHAIN_PITCH) * 2
	var falls := MultiMeshInstance3D.new()
	falls.name = &"SuspensionFalls"
	falls.multimesh = _chain
	falls.material_override = _metal
	falls.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	trolley.add_child(falls)

func pose_chain(length: float) -> void:
	_chain_length = length
	var count := clampi(ceili(length / CHAIN_PITCH), 0, _chain.instance_count >> 1)
	_chain.visible_instance_count = count * 2
	for index in count:
		var twist := PI / 5.0 if index % 2 == 0 else PI * 0.7
		var orient := Basis(Vector3.UP, twist) * Basis(Vector3.RIGHT, PI * 0.5)
		var shape := orient.scaled_local(Vector3(0.72, 1.0, 1.22))
		var center := suspension_origin_y - length * (index + 0.5) / count
		for fall in 2:
			var x := -0.096 if fall == 0 else 0.096
			_chain.set_instance_transform(index * 2 + fall, Transform3D(shape, Vector3(x, center, 0)))

func hook_mesh() -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	const SEGMENTS := 13
	const SIDES := 6
	for segment in SEGMENTS:
		for side in SIDES:
			var a := hook_vertex(segment, side, SEGMENTS, SIDES)
			var b := hook_vertex(segment, side + 1, SEGMENTS, SIDES)
			var c := hook_vertex(segment + 1, side + 1, SEGMENTS, SIDES)
			var d := hook_vertex(segment + 1, side, SEGMENTS, SIDES)
			for vertex in [a, b, c, a, c, d]:
				surface.add_vertex(vertex)
	for end: int in [0, SEGMENTS]:
		var middle := hook_center(float(end) / SEGMENTS)
		for side in SIDES:
			var a := hook_vertex(end, side, SEGMENTS, SIDES)
			var b := hook_vertex(end, side + 1, SEGMENTS, SIDES)
			for vertex in [middle, b, a] if end == 0 else [middle, a, b]:
				surface.add_vertex(vertex)
	surface.generate_normals()
	return surface.commit()

func hook_center(t: float) -> Vector3:
	var angle := lerpf(PI * 0.74, PI * 2.25, t)
	return Vector3(cos(angle) * 0.123, -0.325 + sin(angle) * 0.119, 0)

func hook_vertex(segment: int, side: int, segments: int, sides: int) -> Vector3:
	var t := float(segment) / segments
	var angle := lerpf(PI * 0.74, PI * 2.25, t)
	var around := TAU * side / sides
	var radial := Vector3(cos(angle), sin(angle), 0)
	var thickness := lerpf(0.045, 0.019, t * t)
	return hook_center(t) + radial * (cos(around) * thickness) + Vector3.BACK * (sin(around) * thickness * 1.14)

func anchor(parent: Node3D, id: String, at: Vector3) -> void:
	component_anchors[StringName(id)] = group(parent, StringName(id.to_pascal_case()), at)

func group(parent: Node3D, title: StringName, at := Vector3.ZERO) -> Node3D:
	var node := Node3D.new()
	node.name = title
	node.position = at
	parent.add_child(node, true)
	return node

func box(parent: Node3D, title: StringName, size: Vector3, at: Vector3, material: StandardMaterial3D) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return mesh_at(parent, title, mesh, at, material)

func cylinder(parent: Node3D, title: StringName, radius: float, height: float, at: Vector3,
		axis: Vector3, material: StandardMaterial3D) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 12
	mesh.rings = 1
	var node := mesh_at(parent, title, mesh, at, material)
	node.basis = Basis(Quaternion(Vector3.UP, axis))
	return node

func mesh_at(parent: Node3D, title: StringName, mesh: Mesh, at: Vector3,
		material: StandardMaterial3D) -> MeshInstance3D:
	var shape := MeshInstance3D.new()
	shape.name = title
	shape.mesh = mesh
	shape.material_override = material
	shape.position = at
	parent.add_child(shape, true)
	return shape

func finish(rgb: String, emission := 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(rgb)
	material.roughness = 0.84
	if emission > 0.0:
		material.emission_enabled = true
		material.emission = material.albedo_color
		material.emission_energy_multiplier = emission
	return material

extends Node3D
## Hall-local coordinates: floor datum y=0, personnel entry z=0, rear at +Z.
const WALL_THICKNESS := 0.24
const CHAMBER_HALF_WIDTH := 6.2
const CHAMBER_WALL_HEIGHT := 4.0
const STAIR_WIDTH := 1.8
const GUARD_HEIGHT := 1.10
const STAIR_STEPS := 20
const BAYS := 4

@export var width := 18.288
@export var depth := 24.384
@export var ceiling_height := 11.35
@export var deck_height := 3.35
@export var deck_depth := 5.384
@export var stair_run := 6.4
## Offsets from the right wall keep the stair and rail slot aligned on resize.
@export var stair_center_inset := 1.994

var concrete := finish("747879")
var wall := finish("747c7b")
var dado := finish("535d5e")
var roof := finish("495354")
var steel := finish("383b40")
var flange := finish("4d4946")
var primer := finish("61524a")
var rail := finish("888b81")
var amber := finish("9f824b")
var fixture := finish("c2d0cc", 1.4)
var shadow_line := finish("576063")

@onready var half_width := width * 0.5
@onready var deck_front := depth - deck_depth
@onready var stair_x := half_width - stair_center_inset
@onready var stair_start := deck_front - stair_run

func _ready() -> void:
	build_shell()
	build_steelwork()
	build_mezzanine()
	build_lighting()
	build_markings()

func build_shell() -> void:
	# One continuous slab collider shares the chamber's floor datum.
	box($Shell, "SlabCollider", Vector3(width, 0.30, depth), Vector3(0, -0.15, depth / 2), null, true)
	for index in BAYS:
		var bay_depth := depth / BAYS
		var z := (index + 0.5) * bay_depth
		box($Shell, "ConcreteBay", Vector3(width, 0.16, bay_depth - 0.025), Vector3(0, -0.08, z), concrete)
		if index > 0:
			box($Shell, "ControlJoint", Vector3(width, 0.012, 0.025), Vector3(0, -0.010, z - bay_depth / 2), shadow_line)
	for side in [-1.0, 1.0]:
		var x: float = side * (half_width + WALL_THICKNESS / 2)
		box($Shell, "SideWall", Vector3(WALL_THICKNESS, ceiling_height, depth), Vector3(x, ceiling_height / 2, depth / 2), wall, true)
		box($Shell, "ConcreteDado", Vector3(0.025, 1.25, depth),
			Vector3(side * (half_width - 0.01), 0.625, depth / 2), dado)
		for index in range(1, BAYS * 2):
			# Thin formwork joints remain visual so the collision wall stays planar.
			var seam_z := depth * index / (BAYS * 2)
			box($Shell, "WallFormJoint", Vector3(0.008, ceiling_height - 1.26, 0.023),
				Vector3(side * (half_width - 0.006), (ceiling_height + 1.26) / 2, seam_z), shadow_line)
		var wing := half_width - CHAMBER_HALF_WIDTH + WALL_THICKNESS
		box($Shell, "EntranceWing", Vector3(wing, ceiling_height, WALL_THICKNESS),
			Vector3(side * (CHAMBER_HALF_WIDTH + wing / 2), ceiling_height / 2, -WALL_THICKNESS / 2), wall, true)
	box($Shell, "RearWall", Vector3(width + 2 * WALL_THICKNESS, ceiling_height, WALL_THICKNESS),
		Vector3(0, ceiling_height / 2, depth + WALL_THICKNESS / 2), wall, true)
	var upper_bottom := CHAMBER_WALL_HEIGHT - 0.03
	var upper := ceiling_height - upper_bottom
	# Stand off the chamber roof face so its upper slab cannot z-fight with the wall.
	box($Shell, "EntranceUpperWall", Vector3(CHAMBER_HALF_WIDTH * 2, upper, WALL_THICKNESS),
		Vector3(0, upper_bottom + upper / 2, 0.02 - WALL_THICKNESS / 2), wall, true)
	box($Shell, "RoofDeck", Vector3(width + 2 * WALL_THICKNESS, 0.30, depth),
		Vector3(0, ceiling_height + 0.15, depth / 2), roof, true)

func build_steelwork() -> void:
	# Five portal frames, with wall-side runway girders and secondary roof purlins.
	for index in BAYS + 1:
		var z := clampf(depth * index / BAYS, 0.24, depth - 0.24)
		for side in [-1.0, 1.0]:
			var x: float = side * (half_width - 0.22)
			box($Steelwork, "PortalColumn", Vector3(0.42, ceiling_height, 0.38), Vector3(x, ceiling_height / 2, z), steel, true)
			box($Steelwork, "BaseShoe", Vector3(0.60, 0.13, 0.62), Vector3(x, 0.065, z), flange, true)
			box($Steelwork, "GirderSeat", Vector3(0.73, 0.24, 0.42), Vector3(side * (half_width - 0.37), ceiling_height - 3.52, z), flange)
		var beam_y := ceiling_height - 0.45
		ibeam($Steelwork, "PortalGirder", Vector3(-half_width, beam_y, z),
			Vector3(half_width, beam_y, z), 0.47, 0.32)
	for side in [-1.0, 1.0]:
		var x: float = side * (half_width - 0.45)
		var y := ceiling_height - 3.25
		ibeam($Steelwork, "RunwayGirder", Vector3(x, y, 0.18), Vector3(x, y, depth - 0.18), 0.44, 0.26)
		box($Steelwork, "RunwayPrimerPlate", Vector3(0.035, 0.31, depth - 0.38),
			Vector3(x - side * 0.053, y, depth / 2), primer)
	for index in range(1, BAYS * 3):
		if index % 3 != 0:
			var z := depth * index / (BAYS * 3)
			var y := ceiling_height - 0.094
			span($Steelwork, "RoofPanelSupport", Vector3(-half_width, y, z),
				Vector3(half_width, y, z), 0.075, 0.07, flange)
	for index in range(1, 10):
		var x := lerpf(-half_width, half_width, index / 10.0)
		var y := ceiling_height - 0.16
		ibeam($Steelwork, "RoofPurlin", Vector3(x, y, 0), Vector3(x, y, depth), 0.14, 0.11)

func build_mezzanine() -> void:
	var deck_width := width
	box($Mezzanine, "Deck", Vector3(deck_width, 0.22, deck_depth),
		Vector3(0, deck_height - 0.11, deck_front + deck_depth / 2), dado, true)
	ibeam($Mezzanine, "DeckFrontBeam", Vector3(-half_width, deck_height - 0.36, deck_front + 0.22),
		Vector3(half_width, deck_height - 0.36, deck_front + 0.22), 0.34, 0.27)
	for index in range(1, 12):
		var x := lerpf(-half_width, half_width, index / 12.0)
		ibeam($Mezzanine, "DeckJoist", Vector3(x, deck_height - 0.29, deck_front + 0.23),
			Vector3(x, deck_height - 0.29, depth - 0.06), 0.22, 0.13)
	for fraction in [-0.93, -0.36, 0.36, 0.95]:
		var at := Vector3(half_width * fraction, 0, deck_front + 0.48)
		box($Mezzanine, "DeckSupport", Vector3(0.26, deck_height - 0.20, 0.26),
			at + Vector3.UP * (deck_height - 0.20) / 2, steel, true)
		box($Mezzanine, "DeckSupportFoot", Vector3(0.48, 0.09, 0.48), at + Vector3.UP * 0.045, flange, true)

	var left := stair_x - STAIR_WIDTH / 2
	var right := stair_x + STAIR_WIDTH / 2
	# The gap in the deck rail is the full clear stair width.
	guardrail("DeckRail", Vector3(-half_width, deck_height, deck_front),
		Vector3(left, deck_height, deck_front))
	guardrail("DeckRailEnd", Vector3(right, deck_height, deck_front),
		Vector3(half_width, deck_height, deck_front))

	var rise := deck_height / STAIR_STEPS
	var run := stair_run / STAIR_STEPS
	for index in STAIR_STEPS:
		var y := (index + 1) * rise
		var z := stair_start + (index + 0.5) * run
		box($Mezzanine, "StairTread", Vector3(STAIR_WIDTH, 0.07, run), Vector3(stair_x, y - 0.035, z), flange)
		box($Mezzanine, "StairRiser", Vector3(STAIR_WIDTH, rise, 0.022),
			Vector3(stair_x, y - rise / 2, z - run / 2 + 0.011), steel)
		box($Mezzanine, "StairNosing", Vector3(STAIR_WIDTH, 0.008, 0.045),
			Vector3(stair_x, y + 0.004, z - run / 2 + 0.024), amber)
	# Use a smooth walking surface through the tread centers, with a
	# half-tread lead-in and a flat finish continuous with the landing.
	stair_collision(left, right, run / 2)
	for x in [left, right]:
		var start := Vector3(x, 0, stair_start)
		var end := Vector3(x, deck_height, deck_front)
		ibeam($Mezzanine, "StairStringer", start - Vector3.UP * 0.16, end - Vector3.UP * 0.16, 0.24, 0.14)
		guardrail("StairRail", start, end)

func stair_collision(left: float, right: float, half_tread: float) -> void:
	var body := StaticBody3D.new()
	body.name = "StairWalkingSurface"
	$Mezzanine.add_child(body)
	var shape := ConvexPolygonShape3D.new()
	var corners := PackedVector3Array()
	for x in [left, right]:
		corners.append(Vector3(x, 0, stair_start - half_tread))
		corners.append(Vector3(x, deck_height, deck_front - half_tread))
		corners.append(Vector3(x, deck_height, deck_front))
		corners.append(Vector3(x, deck_height - 0.25, deck_front))
		corners.append(Vector3(x, -0.25, stair_start - half_tread))
	shape.points = corners
	var collider := CollisionShape3D.new()
	collider.shape = shape
	body.add_child(collider)

func guardrail(title: String, start: Vector3, end: Vector3) -> void:
	var length := start.distance_to(end)
	var count := maxi(1, ceili(length / 1.85))
	for index in count + 1:
		var at := start.lerp(end, float(index) / count)
		box($Mezzanine, "RailPost", Vector3(0.065, GUARD_HEIGHT, 0.065), at + Vector3.UP * GUARD_HEIGHT / 2, rail)
	for height in [0.12, 0.57, GUARD_HEIGHT]:
		var lift: Vector3 = Vector3.UP * height
		span($Mezzanine, title, start + lift, end + lift, 0.06, 0.054, rail)
	# A guard's collision fills between the rails, including at crawl height.
	var guard_height := GUARD_HEIGHT
	var slope := (end - start).normalized()
	var projected := guard_height * sqrt(1 - slope.y * slope.y)
	span($Mezzanine, "GuardCollision", start + Vector3.UP * guard_height / 2,
		end + Vector3.UP * guard_height / 2, projected, 0.07, null, true)

func build_lighting() -> void:
	for index in BAYS:
		var z := (index + 0.5) * depth / BAYS
		for fraction in [-0.64, 0.0, 0.64]:
			var x: float = half_width * fraction
			var at := Vector3(x, ceiling_height - 1.10, z)
			box($Lighting, "HighBayHanger", Vector3(0.05, 1.0, 0.05), at + Vector3.UP * 0.55, steel)
			light_fixture(at, Vector2(1.46, 0.54), 13.5, 3.6, fraction == 0.0)
	for fraction in [-0.76, -0.27, 0.27, 0.76]:
		light_fixture(Vector3(half_width * fraction, deck_height - 0.44, deck_front + deck_depth / 2),
			Vector2(1.5, 0.22), 6.5, 1.8)
	# Small reciprocal pools of light keep both faces of the personnel threshold readable.
	for z in [0.45, -0.45]:
		var lamp := OmniLight3D.new()
		lamp.name = "ThresholdLight"
		lamp.position = Vector3(0, 2.63, z)
		lamp.omni_range = 3.2
		lamp.light_energy = 0.55
		lamp.light_color = Color("d2d5c4")
		$Lighting.add_child(lamp)

func light_fixture(at: Vector3, footprint: Vector2, reach: float, energy: float, casts_shadows := false) -> void:
	box($Lighting, "FixtureHousing", Vector3(footprint.x, 0.15, footprint.y), at, steel)
	box($Lighting, "FixtureLens", Vector3(footprint.x * 0.89, 0.034, footprint.y * 0.78),
		at - Vector3.UP * 0.092, fixture)
	var lamp := SpotLight3D.new()
	lamp.name = "WorkLight"
	lamp.position = at - Vector3.UP * 0.12
	lamp.rotation.x = -PI / 2
	lamp.spot_range = reach
	lamp.spot_angle = 70.0
	lamp.spot_attenuation = 0.45
	lamp.spot_angle_attenuation = 1.5
	lamp.light_energy = energy
	lamp.shadow_enabled = casts_shadows
	lamp.light_color = Color("e0e4d7")
	$Lighting.add_child(lamp)

func build_markings() -> void:
	# Low curb marks the perimeter of a former utility footing. It is genuine
	# shell geometry and provides a climbable edge without placing equipment.
	var pad_width := 1.54
	var pad_x := -half_width + pad_width / 2
	var pad_z := depth * 10.5 / 24.384
	box($Shell, "UtilityFooting", Vector3(pad_width, 0.68, 2.8), Vector3(pad_x, 0.34, pad_z), dado, true)
	box($Markings, "FootingEdge", Vector3(0.06, 0.005, 2.70),
		Vector3(-half_width + pad_width - 0.05, 0.683, pad_z), amber)
	for side in [-1.0, 1.0]:
		var x: float = side * (half_width - 1.09)
		box($Markings, "AisleEdge", Vector3(0.045, 0.005, depth - 2), Vector3(x, 0.003, depth / 2), amber)
	box($Markings, "ThresholdStripe", Vector3(1.80, 0.005, 0.085), Vector3(0, 0.003, 0.33), amber)
	placard("HallEntrySign", "THE FACILITY   /   ENGINEERING TEST HALL", Vector3(0, 2.99, -0.222), PI, 4.45)
	placard("ChamberReturnSign", "SYSTEMS TEST CHAMBER   /   RD-001", Vector3(0, 2.99, 0.012), 0, 3.9)
	placard("HallDesignation", "THE FACILITY   /   ENGINEERING TEST HALL", Vector3(0, ceiling_height - 4.65, depth - 0.012), PI, 7.2)

func placard(title: String, caption: String, at: Vector3, yaw: float, plaque_width: float) -> void:
	var sign := Node3D.new()
	sign.name = title
	sign.position = at
	sign.rotation.y = yaw
	$Markings.add_child(sign)
	box(sign, "EnamelBacking", Vector3(plaque_width, plaque_width * 0.114, 0.035), Vector3.ZERO, steel)
	box(sign, "HeaderRule", Vector3(plaque_width, 0.033, 0.039), Vector3(0, plaque_width * 0.052, 0), amber)
	var label := Label3D.new()
	label.text = caption
	label.font_size = 64
	label.pixel_size = plaque_width / 1840.0
	label.outline_size = 0
	label.modulate = Color("d8ded7")
	label.position.z = 0.021
	sign.add_child(label)

func finish(rgb: String, emission := 0.0) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(rgb)
	material.roughness = 0.84
	if emission > 0.0:
		material.emission_enabled = true
		material.emission = material.albedo_color
		material.emission_energy_multiplier = emission
	return material

func ibeam(parent: Node3D, title: String, start: Vector3, end: Vector3, height: float, breadth: float) -> void:
	span(parent, title, start, end, height, breadth * 0.27, steel)
	for side in [-1.0, 1.0]:
		var along := (end - start).normalized()
		var up := Vector3.UP.slide(along).normalized()
		var offset: Vector3 = up * side * height * 0.44
		span(parent, "Flange", start + offset, end + offset, height * 0.12, breadth, flange)

func span(parent: Node3D, title: String, start: Vector3, end: Vector3, height: float,
		breadth: float, material: Material, solid := false) -> void:
	var node := box(parent, title, Vector3(breadth, height, start.distance_to(end)),
		(start + end) * 0.5, material, solid)
	node.basis = Basis.looking_at(start - end, Vector3.UP)

func box(parent: Node3D, title: String, size: Vector3, at: Vector3, material: Material, solid := false) -> Node3D:
	var node: Node3D = StaticBody3D.new() if solid else Node3D.new()
	node.name = title
	node.position = at
	parent.add_child(node, true)
	if material != null:
		var mesh := MeshInstance3D.new()
		var cube := BoxMesh.new()
		cube.size = size
		mesh.mesh = cube
		mesh.material_override = material
		node.add_child(mesh)
	if solid:
		var collider := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		collider.shape = shape
		node.add_child(collider)
	return node

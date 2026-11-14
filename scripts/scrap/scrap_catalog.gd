class_name ScrapCatalog
extends RefCounted

## Length runs along local X. Dimensions and wall thicknesses are in metres.
const STOCK := [
	["Flat bar", "▰", Vector2(0.075, 0.018), [0.32, 0.65, 1.25]],
	["Angle iron", "∟", Vector2(0.13, 0.12), [0.32, 0.65, 1.25]],
	["Square tubing", "□", Vector2(0.09, 0.09), [0.40, 0.75, 1.25]],
	["Round tubing", "○", Vector2(0.10, 0.10), [0.40, 0.80]],
	["Steel rod", "━", Vector2(0.034, 0.034), [0.35, 0.75, 1.40]],
	["Flat plate", "▭", Vector2(0.018, 0.43), [0.28, 0.50, 0.75]],
	["Triangular gusset", "◣", Vector2(0.020, 0.30), [0.24, 0.44]],
	["Rectangular gusset", "▣", Vector2(0.025, 0.24), [0.32]],
	["Channel stock", "⊏", Vector2(0.14, 0.13), [0.38, 0.80]],
	["Solid block", "■", Vector2(0.085, 0.13), [0.13, 0.22]],
	["Irregular scrap", "◆", Vector2(0.033, 0.22), [0.25, 0.38, 0.49]],
]
const WALL := 0.012
const DENSITY := 7850.0

static func entries() -> Array[Dictionary]:
	var catalog: Array[Dictionary] = []
	for row in STOCK:
		var sizes: Array = row[3]
		var labels := ["Short", "Medium", "Long"] if row[0] in [
			"Flat bar", "Angle iron", "Square tubing", "Round tubing", "Steel rod", "Channel stock"
		] else ["Small", "Medium", "Large"]
		for index in sizes.size():
			var section: Vector2 = row[2]
			var size := Vector3(sizes[index], section.x, section.y)
			var entry := {"category": row[0], "icon": row[1], "title": "%s %s" % [labels[index], row[0].to_lower()],
				"size": size, "shapes": [], "volume": 0.0}
			describe(entry, index)
			entry.mass = snappedf(entry.volume * DENSITY, 0.01)
			catalog.append(entry)
	return catalog

static func describe(entry: Dictionary, variant: int) -> void:
	var size: Vector3 = entry.size
	match entry.category:
		"Angle iron", "Square tubing", "Channel stock":
			var half_y := (size.y - WALL) * 0.5
			var half_z := (size.z - WALL) * 0.5
			add_box(entry, Vector3(size.x, WALL, size.z), Vector3(0, -half_y, 0))
			if entry.category != "Angle iron":
				add_box(entry, Vector3(size.x, WALL, size.z), Vector3(0, half_y, 0))
			var side_height := size.y - WALL * (1 if entry.category == "Angle iron" else 2)
			var side_offset := WALL * 0.5 if entry.category == "Angle iron" else 0.0
			add_box(entry, Vector3(size.x, side_height, WALL), Vector3(0, side_offset, -half_z))
			if entry.category == "Square tubing":
				add_box(entry, Vector3(size.x, side_height, WALL), Vector3(0, 0, half_z))
		"Round tubing":
			var outer := size.y * 0.5
			var inner := outer - WALL
			for index in 12:
				var a := TAU * index / 12.0
				var b := TAU * (index + 1) / 12.0
				var outline := PackedVector2Array()
				for radius_angle in [Vector2(outer, a), Vector2(outer, b), Vector2(inner, b), Vector2(inner, a)]:
					outline.append(Vector2.from_angle(radius_angle.y) * radius_angle.x)
				add_prism(entry, outline, size.x, Transform3D(Basis(Vector3(1, 1, 1).normalized(), -TAU / 3.0), Vector3.ZERO))
		"Steel rod":
			var shape := CylinderShape3D.new()
			shape.radius = size.y * 0.5
			shape.height = size.x
			var mesh := CylinderMesh.new()
			mesh.top_radius = shape.radius
			mesh.bottom_radius = shape.radius
			mesh.height = size.x
			mesh.radial_segments = 12
			mesh.rings = 0
			entry.shapes.append([shape, mesh, Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3.ZERO)])
			entry.volume = PI * shape.radius * shape.radius * size.x
		"Triangular gusset", "Irregular scrap":
			var x := size.x * 0.5
			var z := size.z * 0.5
			var outline := PackedVector2Array([Vector2(-x, -z), Vector2(x, -z), Vector2(-x, z)])
			if entry.category == "Irregular scrap":
				outline = PackedVector2Array([Vector2(-x, -z * 0.6), Vector2(x * 0.4, -z), Vector2(x, z * (0.4 + variant * 0.2)), Vector2(-x * 0.52, z)])
			add_prism(entry, outline, size.y)
		_:
			add_box(entry, size, Vector3.ZERO)

static func add_box(entry: Dictionary, size: Vector3, at: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var mesh := BoxMesh.new()
	mesh.size = size
	entry.shapes.append([shape, mesh, Transform3D(Basis.IDENTITY, at)])
	entry.volume += size.x * size.y * size.z

static func add_prism(entry: Dictionary, outline: PackedVector2Array, height: float,
		pose := Transform3D.IDENTITY) -> void:
	var vertices := PackedVector3Array()
	for y in [-height * 0.5, height * 0.5]:
		for point in outline:
			vertices.append(Vector3(point.x, y, point.y))
	var shape := ConvexPolygonShape3D.new()
	shape.points = vertices
	var count := outline.size()
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var indices: Array[int] = []
	for i in range(1, count - 1):
		indices.append_array([0, i + 1, i, count, count + i, count + i + 1])
	var area := 0.0
	for i in count:
		var j := (i + 1) % count
		indices.append_array([i, j, count + j, i, count + j, count + i])
		area += outline[i].cross(outline[j])
	# Arc strips are counterclockwise or clockwise depending on the wall.
	if area < 0.0:
		indices.reverse()
	for index in indices:
		surface.add_vertex(vertices[index])
	surface.generate_normals()
	entry.shapes.append([shape, surface.commit(), pose])
	entry.volume += absf(area) * 0.5 * height

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
const TUBE_VISUAL_SEGMENTS := 48
const DENSITY := 7850.0
const INCH_M := 0.0254
const W12_50_DEPTH_M := 12.20 * INCH_M
const W12_50_WIDTH_M := 8.08 * INCH_M
const W12_50_FLANGE_M := 0.640 * INCH_M
const W12_50_WEB_M := 0.370 * INCH_M
const W12_50_AREA_M2 := 14.60 * INCH_M * INCH_M

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
				"size": size, "shapes": [], "volume": 0.0, "first_moment": Vector3.ZERO}
			describe(entry, index)
			entry.mass = snappedf(entry.volume * DENSITY, 0.01)
			entry.center_of_mass = entry.first_moment / entry.volume
			catalog.append(entry)
	catalog.append_array(industrial_entries())
	return catalog

static func industrial_entries() -> Array[Dictionary]:
	var flat := industrial_entry("Flat Bar — 20 ft", "▰", Vector3(6.096, 0.0127, 0.1524),
		"Solid steel flat bar, 6,096 mm long by 152.4 mm wide by 12.7 mm thick.")
	add_box(flat, flat.size, Vector3.ZERO)
	var round := industrial_entry("Round Bar — 20 ft", "━", Vector3(6.096, 0.0762, 0.0762),
		"Solid steel round bar, 6,096 mm long by 76.2 mm diameter.")
	add_rod(round, 32)
	var beam := industrial_entry("Wide-Flange Beam — 30 ft", "Ⅰ",
		Vector3(9.144, W12_50_DEPTH_M, W12_50_WIDTH_M),
		"W12×50 structural steel, 9,144 mm long with 309.9 mm section depth and 205.2 mm flange width.")
	var flange_size := Vector3(beam.size.x, W12_50_FLANGE_M, W12_50_WIDTH_M)
	var flange_offset := Vector3.UP * ((W12_50_DEPTH_M - W12_50_FLANGE_M) * 0.5)
	add_box(beam, flange_size, flange_offset)
	add_box(beam, flange_size, -flange_offset)
	add_box(beam, Vector3(beam.size.x, W12_50_DEPTH_M - 2.0 * W12_50_FLANGE_M, W12_50_WEB_M), Vector3.ZERO)
	# AISC Shapes Database v16.0 section area includes the small root fillets omitted from collision.
	beam.volume = W12_50_AREA_M2 * beam.size.x

	var machine := industrial_entry("Machinery Test Block — 5 t", "▣", Vector3(1.5, 0.8, 1.0),
		"Chamfered machinery test casting, 1,500 mm long by 1,000 mm wide by 800 mm high. Ballasted to 5,000 kg.")
	var outline := PackedVector2Array([
		Vector2(-0.75, -0.40), Vector2(-0.65, -0.50), Vector2(0.65, -0.50), Vector2(0.75, -0.40),
		Vector2(0.75, 0.40), Vector2(0.65, 0.50), Vector2(-0.65, 0.50), Vector2(-0.75, 0.40),
	])
	add_prism(machine, outline, machine.size.y)
	var entries: Array[Dictionary] = [flat, round, beam, machine]
	for entry in entries:
		entry.mass = snappedf(entry.volume * DENSITY, 0.01)
		entry.center_of_mass = entry.first_moment / entry.volume
	machine.mass = 5000.0
	return entries

static func industrial_entry(title: String, icon: String, size: Vector3, description: String) -> Dictionary:
	return {"category": "Industrial test stock", "industrial": true, "title": title, "icon": icon,
		"size": size, "description": description, "shapes": [], "volume": 0.0, "first_moment": Vector3.ZERO}

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
			entry.mesh = tube_mesh(size.x, outer, inner)
			for index in 12:
				var a := TAU * index / 12.0
				var b := TAU * (index + 1) / 12.0
				var outline := PackedVector2Array()
				for radius_angle in [Vector2(outer, a), Vector2(outer, b), Vector2(inner, b), Vector2(inner, a)]:
					outline.append(Vector2.from_angle(radius_angle.y) * radius_angle.x)
				add_prism(entry, outline, size.x,
					Transform3D(Basis(Vector3(1, 1, 1).normalized(), -TAU / 3.0), Vector3.ZERO), false)
		"Steel rod":
			add_rod(entry, 12)
		"Triangular gusset", "Irregular scrap":
			var x := size.x * 0.5
			var z := size.z * 0.5
			var outline := PackedVector2Array([Vector2(-x, -z), Vector2(x, -z), Vector2(-x, z)])
			if entry.category == "Irregular scrap":
				outline = PackedVector2Array([Vector2(-x, -z * 0.6), Vector2(x * 0.4, -z), Vector2(x, z * (0.4 + variant * 0.2)), Vector2(-x * 0.52, z)])
			add_prism(entry, outline, size.y)
		_:
			add_box(entry, size, Vector3.ZERO)

static func add_rod(entry: Dictionary, radial_segments: int) -> void:
	var size: Vector3 = entry.size
	var shape := CylinderShape3D.new()
	shape.radius = size.y * 0.5
	shape.height = size.x
	var mesh := CylinderMesh.new()
	mesh.top_radius = shape.radius
	mesh.bottom_radius = shape.radius
	mesh.height = size.x
	mesh.radial_segments = radial_segments
	mesh.rings = 0
	entry.shapes.append([shape, mesh, Transform3D(Basis(Vector3.BACK, PI * 0.5), Vector3.ZERO)])
	entry.volume = PI * shape.radius * shape.radius * size.x

static func add_box(entry: Dictionary, size: Vector3, at: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var mesh := BoxMesh.new()
	mesh.size = size
	entry.shapes.append([shape, mesh, Transform3D(Basis.IDENTITY, at)])
	var volume := size.x * size.y * size.z
	entry.volume += volume
	entry.first_moment += at * volume

static func add_prism(entry: Dictionary, outline: PackedVector2Array, height: float,
		pose := Transform3D.IDENTITY, render := true) -> void:
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
	var area_moment := Vector2.ZERO
	for i in count:
		var j := (i + 1) % count
		indices.append_array([i, j, count + j, i, count + j, count + i])
		var cross := outline[i].cross(outline[j])
		area += cross
		area_moment += (outline[i] + outline[j]) * cross
	# Arc strips are counterclockwise or clockwise depending on the wall.
	if area < 0.0:
		indices.reverse()
	var mesh: ArrayMesh
	if render:
		for index in indices:
			surface.add_vertex(vertices[index])
		surface.generate_normals()
		mesh = surface.commit()
	entry.shapes.append([shape, mesh, pose])
	var volume := absf(area) * 0.5 * height
	entry.volume += volume
	if not is_zero_approx(area):
		var centroid := area_moment / (3.0 * area)
		entry.first_moment += (pose * Vector3(centroid.x, 0.0, centroid.y)) * volume

## Only the exposed walls and rims are rendered. Cylinder normals are
## radial, while the two cut ends keep their flat annular faces.
static func tube_mesh(length: float, outer: float, inner: float) -> ArrayMesh:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var left := Vector3.LEFT * length * 0.5
	var right := -left
	for index in TUBE_VISUAL_SEGMENTS:
		var a := tube_radial(index)
		var b := tube_radial(index + 1)
		var lo := left + a * outer
		var ro := right + a * outer
		var li := left + a * inner
		var ri := right + a * inner
		var next_lo := left + b * outer
		var next_ro := right + b * outer
		var next_li := left + b * inner
		var next_ri := right + b * inner
		add_tube_quad(surface, [lo, ro, next_ro, next_lo], a, b)
		add_tube_quad(surface, [ri, li, next_li, next_ri], -a, -b)
		add_tube_quad(surface, [ro, ri, next_ri, next_ro], Vector3.RIGHT, Vector3.RIGHT)
		add_tube_quad(surface, [li, lo, next_lo, next_li], Vector3.LEFT, Vector3.LEFT)
	surface.index()
	return surface.commit()

static func tube_radial(index: int) -> Vector3:
	var angle := TAU * (index % TUBE_VISUAL_SEGMENTS) / TUBE_VISUAL_SEGMENTS
	return Vector3(0, cos(angle), sin(angle))

static func add_tube_quad(surface: SurfaceTool, points: Array[Vector3],
		first_normal: Vector3, next_normal: Vector3) -> void:
	for corner in [0, 1, 2, 0, 2, 3]:
		surface.set_normal(first_normal if corner < 2 else next_normal)
		surface.add_vertex(points[corner])

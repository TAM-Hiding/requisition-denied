extends Node3D
## Procedural art for the ICF-01 only. Sockets live in its scenes.
@export var section: StringName
var side := 1.0
static var palette: Dictionary

func _ready() -> void:
	if palette.is_empty():
		var colors := {
			"ivory": Color("#c9c3aa"), "replacement": Color("#8e9487"), "graphite": Color("#292e33"),
			"gunmetal": Color("#465159"), "steel": Color("#788489"), "visor": Color("#11191d"),
			"cyan": Color("#62d5db"), "amber": Color("#d69c45"), "yellow": Color("#9f8840")
		}
		for color in colors:
			var material := StandardMaterial3D.new()
			material.albedo_color = colors[color]
			material.roughness = 0.73
			material.metallic = 0.4 if color in ["gunmetal", "steel"] else 0.08
			if color in ["cyan", "amber"]:
				material.emission_enabled = true
				material.emission = colors[color]
				material.emission_energy_multiplier = 0.55
			palette[color] = material
	match section:
		&"core": core()
		&"head": head()
		&"upper_arm": upper_arm()
		&"forearm", &"forearm_service": forearm(section == &"forearm_service")
		&"hand": hand()
		&"thigh": thigh()
		&"shin": shin()
		&"foot": foot()

func mesh(primitive: Mesh, at: Vector3, material: String, angles := Vector3.ZERO) -> MeshInstance3D:
	var visual := MeshInstance3D.new()
	visual.mesh = primitive
	visual.material_override = palette[material]
	visual.position = at
	visual.rotation = angles
	add_child(visual)
	return visual

func block(size: Vector3, at: Vector3, material: String, angles := Vector3.ZERO) -> MeshInstance3D:
	var primitive := BoxMesh.new()
	primitive.size = size
	return mesh(primitive, at, material, angles)

func plate(size: Vector3, bevel: float, at: Vector3, material: String, angles := Vector3.ZERO) -> void:
	var x := size.x * 0.5
	var y := size.y * 0.5
	var z := size.z * 0.5
	var outline := PackedVector2Array([
		Vector2(-x + bevel, -y), Vector2(x - bevel, -y), Vector2(x, -y + bevel), Vector2(x, y - bevel),
		Vector2(x - bevel, y), Vector2(-x + bevel, y), Vector2(-x, y - bevel), Vector2(-x, -y + bevel)])
	var front := PackedVector3Array()
	var rear := PackedVector3Array()
	for point in outline:
		front.append(Vector3(point.x, point.y, -z))
		rear.append(Vector3(point.x, point.y, z))
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	surface.set_smooth_group(-1)
	for index in range(1, outline.size() - 1):
		for vertex in [front[0], front[index], front[index + 1], rear[0], rear[index + 1], rear[index]]:
			surface.add_vertex(vertex)
	for index in outline.size():
		var next := (index + 1) % outline.size()
		for vertex in [front[next], front[index], rear[index], front[next], rear[index], rear[next]]:
			surface.add_vertex(vertex)
	surface.generate_normals()
	mesh(surface.commit(), at, material, angles)

func cylinder(radius: float, height: float, at: Vector3, material: String, angles := Vector3.ZERO,
		top_scale := 1.0) -> void:
	var primitive := CylinderMesh.new()
	primitive.bottom_radius = radius
	primitive.top_radius = radius * top_scale
	primitive.height = height
	primitive.radial_segments = 8
	primitive.rings = 0
	mesh(primitive, at, material, angles)

func link(start: Vector3, end: Vector3, radius: float, material: String) -> void:
	var primitive := CylinderMesh.new()
	primitive.bottom_radius = radius
	primitive.top_radius = radius
	primitive.height = start.distance_to(end)
	primitive.radial_segments = 6
	primitive.rings = 0
	var visual := mesh(primitive, (start + end) * 0.5, material)
	var axis := Vector3.UP.cross(end - start)
	if axis.length_squared() > 0.000001:
		visual.basis = Basis(axis.normalized(), Vector3.UP.angle_to(end - start))

func core() -> void:
	block(Vector3(0.22, 0.13, 0.17), Vector3(0, 0.055, 0), "graphite")
	block(Vector3(0.14, 0.085, 0.035), Vector3(0, 0.065, -0.096), "ivory")
	cylinder(0.06, 0.13, Vector3(0, 0.19, 0.035), "steel")
	block(Vector3(0.075, 0.43, 0.10), Vector3(0, 0.375, 0.063), "graphite")
	for i in 7:
		block(Vector3(0.103, 0.025, 0.12), Vector3(0, 0.205 + i * 0.052, 0.079), "gunmetal")
	block(Vector3(0.38, 0.075, 0.145), Vector3(0, 0.53, 0), "gunmetal")
	block(Vector3(0.23, 0.27, 0.142), Vector3(0, 0.407, -0.022), "graphite")
	plate(Vector3(0.18, 0.155, 0.055), 0.022, Vector3(-0.035, 0.446, -0.106), "ivory",
		Vector3(0.08, 0, -0.07))
	block(Vector3(0.082, 0.12, 0.044), Vector3(0.099, 0.402, -0.094), "replacement")
	block(Vector3(0.024, 0.009, 0.003), Vector3(-0.077, 0.405, -0.137), "amber")
	for direction in [-1.0, 1.0]:
		for i in 3:
			block(Vector3(0.125, 0.027, 0.05), Vector3(direction * 0.103, 0.296 + i * 0.041, -0.033),
				"gunmetal", Vector3(0, direction * 0.25, direction * 0.19))
		link(Vector3(direction * 0.135, 0.49, 0.058), Vector3(direction * 0.086, 0.22, 0.095), 0.014, "graphite")
	cylinder(0.035, 0.18, Vector3(0, 0.645, -0.025), "steel", Vector3(0.18, 0, 0))
	cylinder(0.057, 0.043, Vector3(0, 0.584, -0.014), "graphite")
	cylinder(0.045, 0.034, Vector3(0, 0.696, -0.033), "gunmetal")
	for direction in [-1.0, 1.0]:
		link(Vector3(direction * 0.073, 0.559, 0.015), Vector3(direction * 0.026, 0.702, -0.023), 0.011, "steel")
	block(Vector3(0.10, 0.13, 0.031), Vector3(0, 0.38, 0.146), "gunmetal")

func head() -> void:
	block(Vector3(0.17, 0.156, 0.17), Vector3(0, 0.099, -0.018), "graphite")
	plate(Vector3(0.186, 0.079, 0.168), 0.023, Vector3(0, 0.15, -0.025), "ivory", Vector3(-0.12, 0, 0))
	block(Vector3(0.177, 0.052, 0.038), Vector3(0, 0.097, -0.103), "visor")
	block(Vector3(0.137, 0.043, 0.051), Vector3(0, 0.054, -0.087), "gunmetal", Vector3(0.20, 0, 0))
	var optic := block(Vector3(0.053, 0.014, 0.009), Vector3(0, 0.098, -0.125), "cyan")
	optic.name = "Optic"
	for direction in [-1.0, 1.0]:
		block(Vector3(0.025, 0.071, 0.109), Vector3(direction * 0.087, 0.087, 0), "ivory")
		cylinder(0.024, 0.022, Vector3(direction * 0.104, 0.09, 0.018), "steel", Vector3(0, 0, PI / 2))

func upper_arm() -> void:
	cylinder(0.063, 0.105, Vector3.ZERO, "steel", Vector3(0, 0, PI / 2))
	block(Vector3(0.067, 0.238, 0.075), Vector3(0, -0.139, 0), "graphite")
	block(Vector3(0.047, 0.12 if side < 0 else 0.086, 0.116), Vector3(side * 0.054, -0.047, 0),
		"ivory" if side < 0 else "replacement", Vector3(0, 0, side * 0.16))
	link(Vector3(0, -0.05, 0.05), Vector3(0, -0.232, 0.042), 0.014, "steel")

func forearm(service: bool) -> void:
	cylinder(0.043, 0.088, Vector3.ZERO, "steel", Vector3(0, 0, PI / 2))
	block(Vector3(0.071, 0.26, 0.067), Vector3(0, -0.158, 0), "graphite")
	if service:
		cylinder(0.056, 0.17, Vector3(0, -0.133, 0), "gunmetal", Vector3.ZERO, 0.84)
		for i in 3:
			block(Vector3(0.108, 0.019, 0.073), Vector3(0, -0.07 - i * 0.058, -0.023), "yellow")
	else:
		block(Vector3(0.084, 0.177, 0.044), Vector3(0, -0.135, -0.046),
			"replacement" if side > 0 else "ivory", Vector3(0.09, 0, side * 0.055))
		block(Vector3(0.042, 0.017, 0.004), Vector3(0, -0.182, -0.071), "yellow")
	link(Vector3(side * 0.039, -0.054, 0.041), Vector3(side * 0.033, -0.265, 0.032), 0.013, "steel")

func hand() -> void:
	cylinder(0.026, 0.044, Vector3.ZERO, "steel")
	block(Vector3(0.068, 0.067, 0.046), Vector3(0, -0.052, 0), "graphite")
	block(Vector3(0.065, 0.048, 0.016), Vector3(0, -0.048, 0.025), "gunmetal")
	for i in 4:
		var x := -0.024 + i * 0.016
		block(Vector3(0.013, 0.042, 0.017), Vector3(x, -0.099, -0.009), "steel", Vector3(0.24, 0, 0))
		block(Vector3(0.013, 0.019, 0.020), Vector3(x, -0.119, -0.022), "graphite")
	block(Vector3(0.019, 0.046, 0.022), Vector3(-side * 0.038, -0.064, -0.023), "steel", Vector3(0.4, 0, -side * 0.37))

func thigh() -> void:
	cylinder(0.055, 0.1, Vector3.ZERO, "steel", Vector3(0, 0, PI / 2))
	block(Vector3(0.096, 0.348, 0.093), Vector3(0, -0.207, 0), "graphite")
	block(Vector3(0.093, 0.212, 0.05), Vector3(0, -0.146, -0.06), "ivory", Vector3(0.11, 0, 0))
	link(Vector3(-side * 0.045, -0.07, 0.038), Vector3(-side * 0.046, -0.373, 0.047), 0.019, "steel")

func shin() -> void:
	cylinder(0.052, 0.12, Vector3.ZERO, "steel", Vector3(0, 0, PI / 2))
	block(Vector3(0.092, 0.091, 0.04), Vector3(0, -0.024, -0.055), "gunmetal")
	block(Vector3(0.085, 0.321, 0.087), Vector3(0, -0.215, 0.013), "graphite")
	block(Vector3(0.09, 0.216, 0.052), Vector3(0, -0.202, -0.052), "ivory", Vector3(0.05, 0, 0))
	link(Vector3(side * 0.046, -0.092, 0.053), Vector3(side * 0.034, -0.368, 0.031), 0.017, "steel")

func foot() -> void:
	cylinder(0.041, 0.092, Vector3.ZERO, "gunmetal", Vector3(0, 0, PI / 2))
	block(Vector3(0.134, 0.036, 0.257), Vector3(0, -0.072, -0.058), "graphite")
	block(Vector3(0.124, 0.052, 0.17), Vector3(0, -0.038, -0.099), "gunmetal")
	block(Vector3(0.105, 0.038, 0.095), Vector3(0, -0.025, -0.124), "ivory", Vector3(0.13, 0, 0))
	for i in 2:
		block(Vector3(0.018, 0.005, 0.043), Vector3(-0.029 + i * 0.055, -0.005, -0.144), "yellow")

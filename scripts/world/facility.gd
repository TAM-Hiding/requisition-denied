extends Node3D
## Primitive-only room. Collision follows the same dimensions as presentation.
func _ready() -> void:
	var floor_mat := material(Color("343f46"))
	var wall_mat := material(Color("697579"))
	var dark := material(Color("202c33"))
	var amber := material(Color("c89a43"))
	var glow := material(Color("a2e7df"), true)
	box(self, "Floor", Vector3(12.4, 0.3, 12.4), Vector3(0, -0.15, 0), floor_mat, true)
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
	var generator := make_object("generator", Vector3(2.7, 0.8, -2.5), Vector3(2, 1.6, 1.2), material(Color("54756a")))
	box(generator, "ControlPanel", Vector3(0.65, 0.5, 0.05), Vector3(0.45, 0.25, 0.63), dark)
	for y in [-0.3, -0.1, 0.1, 0.3]:
		box(generator, "Vent", Vector3(0.65, 0.055, 0.04), Vector3(-0.45, y, 0.63), dark)
	var terminal := make_object("terminal", Vector3(0, 1.6, -5.8), Vector3(1.2, 1.1, 0.4), dark)
	box(terminal, "Screen", Vector3(1, 0.65, 0.03), Vector3(0, 0.1, 0.22), glow)
	box(terminal, "Keyboard", Vector3(1, 0.1, 0.3), Vector3(0, -0.45, 0.28), wall_mat)
	label_at(self, "RD / 001   •   SYSTEMS TEST CHAMBER", Vector3(0, 3.05, -5.96), 42)
	label_at(terminal, "SERVICES\nUNAVAILABLE", Vector3(0, 0.1, 0.245), 24, Color("173a3b"))
	label_at(generator, "AUX / 01", Vector3(0.45, 0.25, 0.665), 22)
	label_at(crate, "STORAGE\n001", Vector3(0, 0, 0.66), 26)

func material(color: Color, emissive: bool = false) -> StandardMaterial3D:
	var result := StandardMaterial3D.new()
	result.albedo_color = color
	result.roughness = 0.85
	if emissive:
		result.emission_enabled = true
		result.emission = color
	return result

func box(parent: Node3D, title: String, size: Vector3, at: Vector3,
		mat: Material, solid: bool = false) -> void:
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

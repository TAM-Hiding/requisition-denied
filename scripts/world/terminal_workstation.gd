class_name TerminalWorkstation
extends InteractableObject
## This housing provides only the physical interface and a camera framing marker.
const SCREEN_SIZE := Vector2(0.92, 0.58)
var screen: MeshInstance3D
var view_anchor: Marker3D
var display: SubViewport

func _ready() -> void:
	super._ready()
	var steel := _finish(Color("424b48"))
	var graphite := _finish(Color("222b2a"))
	var edge := _finish(Color("68706a"))
	_part("Desktop", Vector3(1.82, 0.12, 0.92), Vector3(0, -0.57, 0.30), steel, true)
	_part("FrontLip", Vector3(1.82, 0.10, 0.035), Vector3(0, -0.64, 0.75), edge)
	for x in [-0.76, 0.76]:
		_part("Pedestal", Vector3(0.21, 0.98, 0.76), Vector3(x, -1.10, 0.3), graphite, true)
		_part("Foot", Vector3(0.31, 0.065, 0.82), Vector3(x, -1.56, 0.3), steel, true)
	_part("ComputerBase", Vector3(1.04, 0.13, 0.47), Vector3(0, -0.44, 0.09), edge, true)
	for x in [0.25, 0.31, 0.37, 0.43]:
		_part("Vent", Vector3(0.025, 0.037, 0.008), Vector3(x, -0.44, 0.329), graphite)
	# Stepped and chamfered silhouette with an inset screen and a separate bezel.
	_part("CRTBack", Vector3(0.94, 0.64, 0.31), Vector3(0, 0.005, 0.005), steel)
	_part("CRTBezel", Vector3(1.14, 0.80, 0.115), Vector3(0, 0.005, 0.205), graphite, true)
	for y in [-0.352, 0.352]:
		_part("HorizontalBevel", Vector3(1.11, 0.065, 0.09), Vector3(0, y, 0.272), edge)
	for x in [-0.518, 0.518]:
		_part("VerticalBevel", Vector3(0.075, 0.64, 0.09), Vector3(x, 0, 0.273), steel)
	_part("Keyboard", Vector3(0.85, 0.055, 0.23), Vector3(0, -0.48, 0.57), graphite, true)
	for row in 3:
		for column in 12:
			_part("Key", Vector3(0.051, 0.015, 0.036),
				Vector3((column - 5.5) * 0.063, -0.447, 0.51 + row * 0.052), edge)
	_part("Cable", Vector3(0.026, 0.028, 0.28), Vector3(-0.36, -0.50, 0.38), graphite)
	var badge := Label3D.new()
	badge.text = "THE FACILITY  /  RD-TERM-001"
	badge.font_size = 28
	badge.pixel_size = 0.00105
	badge.modulate = Color("b5b69a")
	badge.position = Vector3(0, -0.352, 0.323)
	add_child(badge)

	display = SubViewport.new()
	display.name = "Display"
	display.disable_3d = true
	display.size = Vector2i(960, 605)
	display.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	add_child(display)
	screen = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = SCREEN_SIZE
	screen.mesh = quad
	var glass := StandardMaterial3D.new()
	glass.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glass.albedo_texture = display.get_texture()
	screen.material_override = glass
	screen.position.z = 0.276
	add_child(screen)
	view_anchor = Marker3D.new()
	view_anchor.position = Vector3(0, 0, 1.14)
	add_child(view_anchor)

func _finish(color: Color) -> StandardMaterial3D:
	var surface := StandardMaterial3D.new()
	surface.albedo_color = color
	surface.metallic = 0.35
	surface.roughness = 0.76
	return surface

func _part(label: String, dimensions: Vector3, at: Vector3, material: Material, solid := false) -> void:
	var part := MeshInstance3D.new()
	part.name = label
	var block := BoxMesh.new()
	block.size = dimensions
	part.mesh = block
	part.material_override = material
	part.position = at
	add_child(part, true)
	if solid:
		var collider := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = dimensions
		collider.shape = shape
		collider.position = at
		add_child(collider)

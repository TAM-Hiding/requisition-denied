class_name LayoutPlaceholder
extends Node3D
## Placeholder art uses unit dimensions, with a footprint centered on the floor datum.

const STEEL := Color("#505c60")
const DARK := Color("#283337")
const SURFACE := Color("#8b9a98")
const MACHINE := Color("#647d73")
const STORAGE := Color("#777b62")
const SAFETY := Color("#be914d")
const MARKER := Color("#78b4b2")
const SELECTED := Color("#eec074")
const INVALID := Color("#e57562")

static var _finishes := {}

var _type := ""
var _integrated_portal := false
var _base_size := Vector3.ZERO
var _ghost := false
var _editing := false
var _selected := false
var _valid := true
var _graphics: Node3D
var _outline: Node3D
var _label: Label3D
var _body: StaticBody3D
var _collision_boxes: Array[Dictionary] = []

func configure(record: Dictionary, ghost := false) -> void:
	var next_type: String = record.type
	var next_size: Vector3 = record.size
	var type_changed := _graphics == null or next_type != _type
	var collision_changed := type_changed or next_size != _base_size or ghost != _ghost
	position = record.position
	rotation = Vector3(0, record.yaw, 0)
	_type = next_type
	_integrated_portal = LayoutReference.is_integrated_door(record)
	_base_size = next_size
	_ghost = ghost
	if _label == null:
		create_editing_labels()
	if type_changed:
		if _graphics != null:
			_graphics.free()
		_graphics = Node3D.new()
		_graphics.name = "PlaceholderGeometry"
		add_child(_graphics)
		_collision_boxes.clear()
		build_silhouette()
	_graphics.scale = _base_size
	_outline.scale = _base_size
	_label.position = Vector3.UP * (_base_size.y + 0.25)
	_label.text = record.name
	if collision_changed:
		update_collision()
	if is_instance_valid(_body):
		var estimate := LayoutCatalog.mass_estimate(_type, _base_size, record.name)
		if not estimate.is_empty():
			_body.set_meta(&"lift_mass_properties", estimate)
	update_highlight()

func set_editing(enabled: bool) -> void:
	if _editing == enabled:
		return
	_editing = enabled
	if _label != null:
		update_highlight()

func set_highlight(selected: bool, valid := true) -> void:
	if _selected == selected and _valid == valid:
		return
	_selected = selected
	_valid = valid
	if _label != null:
		update_highlight()

func create_editing_labels() -> void:
	_outline = Node3D.new()
	_outline.name = "FootprintOutline"
	add_child(_outline)
	for side in [-1, 1]:
		create_box(Vector3(1, 0.018, 0.02), Vector3(0, 0.014, side * 0.49), SELECTED, _outline)
		create_box(Vector3(0.02, 0.018, 1), Vector3(side * 0.49, 0.014, 0), SELECTED, _outline)
	_label = Label3D.new()
	_label.name = "EditorLabel"
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.font_size = 32
	_label.pixel_size = 0.004
	_label.outline_size = 5
	add_child(_label)

func update_highlight() -> void:
	var highlight := INVALID if not _valid else SELECTED
	var shadows := GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if _ghost else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_label.visible = _editing or _ghost
	_graphics.visible = _editing or _ghost or not _integrated_portal
	_label.modulate = highlight if (_selected or _ghost) else Color("#dce8e3")
	_outline.visible = _ghost or (_editing and _selected)
	for rail: MeshInstance3D in _outline.get_children():
		rail.material_override = finish(highlight)
	for mesh: MeshInstance3D in _graphics.get_children():
		var base_color: Color = mesh.get_meta(&"finish")
		if _ghost:
			base_color = base_color.lerp(MARKER if _valid else INVALID, 0.68)
			base_color.a = 0.54
		elif _selected and _editing:
			base_color = base_color.lerp(highlight, 0.36)
		mesh.material_override = finish(base_color)
		mesh.cast_shadow = shadows

func update_collision() -> void:
	if _body != null:
		_body.free()
		_body = null
	if _ghost or LayoutCatalog.definition(_type).get("marker", false):
		return
	_body = StaticBody3D.new()
	_body.name = "PlaceholderCollision"
	_body.collision_layer = 1
	_body.collision_mask = 0
	_body.set_meta(&"no_fasteners", true)
	add_child(_body)
	var boxes := _collision_boxes
	if boxes.is_empty():
		boxes = [{"size": Vector3.ONE, "position": Vector3(0, 0.5, 0)}]
	for part in boxes:
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = part.size * _base_size
		collision.shape = shape
		collision.position = part.position * _base_size
		_body.add_child(collision)

func build_silhouette() -> void:
	match _type:
		"fabrication_table_long", "fabrication_table_medium", "fabrication_table_small", "workbench":
			build_table()
		"milling_machine":
			build_mill()
		"engine_lathe":
			build_lathe()
		"drill_press":
			build_drill_press()
		"horizontal_bandsaw":
			build_bandsaw()
		"material_storage_rack":
			build_rack()
		"horizontal_stock_rack":
			build_horizontal_rack()
		"bandsaw_infeed_stand", "bandsaw_outfeed_support":
			build_saw_support()
		"lockers":
			build_storage(3, true)
		"storage_cabinet":
			build_storage(2, false)
		"storage_room_marker":
			build_room_marker()
		"personnel_door_marker":
			build_door_marker()

func build_table() -> void:
	var bench := _type == "workbench"
	box(Vector3(1, 0.10, 1), Vector3(0, 0.95, 0), STORAGE if bench else SURFACE, true)
	var leg_width := 0.035 if _type == "fabrication_table_long" else 0.062
	var leg_positions := [-0.44, -0.15, 0.15, 0.44] if _type == "fabrication_table_long" else [-0.42, 0.42]
	for x: float in leg_positions:
		for z in [-0.41, 0.41]:
			box(Vector3(leg_width, 0.90, 0.092), Vector3(x, 0.45, z), STEEL, true)
	for z in [-0.36, 0.36]:
		box(Vector3(0.90, 0.08, 0.048), Vector3(0, 0.86, z), STEEL, true)
	if bench:
		box(Vector3(0.89, 0.052, 0.69), Vector3(0, 0.26, 0.04), STEEL, true)
	else:
		for stripe in [-1, 1]:
			box(Vector3(0.14, 0.008, 0.012), Vector3(stripe * 0.40, 0.976, -0.494), SAFETY)

func build_mill() -> void:
	box(Vector3(0.68, 0.07, 0.99), Vector3(0, 0.035, 0), DARK)
	box(Vector3(0.40, 0.73, 0.40), Vector3(0, 0.40, 0.26), MACHINE)
	box(Vector3(0.42, 0.28, 0.38), Vector3(0, 0.34, -0.11), MACHINE)
	box(Vector3(0.96, 0.071, 0.33), Vector3(0, 0.48, -0.26), SURFACE)
	for z in [-0.37, -0.28, -0.19]:
		box(Vector3(0.90, 0.007, 0.018), Vector3(0, 0.516, z), DARK)
	box(Vector3(0.28, 0.09, 0.52), Vector3(0, 0.76, 0.02), MACHINE)
	box(Vector3(0.23, 0.13, 0.25), Vector3(0, 0.80, -0.23), STEEL)
	cylinder(0.084, 0.14, Vector3(0, 0.931, -0.23), MACHINE)
	cylinder(0.036, 0.136, Vector3(0, 0.669, -0.24), SURFACE)
	cylinder(0.096, 0.026, Vector3(0.24, 0.459, -0.447), DARK, Vector3(PI / 2, 0, 0))
	box(Vector3(0.11, 0.037, 0.022), Vector3(0.04, 0.807, -0.36), SAFETY)

func build_lathe() -> void:
	for x in [-0.36, 0.35]:
		box(Vector3(0.23, 0.48, 0.78), Vector3(x, 0.24, 0), MACHINE)
	box(Vector3(1, 0.13, 0.83), Vector3(0, 0.54, 0), DARK)
	for z in [-0.15, 0.13]:
		box(Vector3(0.92, 0.036, 0.12), Vector3(0, 0.62, z), SURFACE)
	box(Vector3(0.25, 0.35, 0.72), Vector3(-0.365, 0.80, 0), MACHINE)
	cylinder(0.13, 0.062, Vector3(-0.21, 0.81, 0), SURFACE, Vector3(0, 0, PI / 2))
	box(Vector3(0.18, 0.12, 0.61), Vector3(0.03, 0.68, -0.017), STEEL)
	box(Vector3(0.062, 0.086, 0.145), Vector3(0.01, 0.771, -0.045), DARK)
	box(Vector3(0.17, 0.25, 0.43), Vector3(0.34, 0.745, 0), MACHINE)
	box(Vector3(0.064, 0.06, 0.044), Vector3(-0.395, 0.84, -0.379), SAFETY)

func build_drill_press() -> void:
	box(Vector3(0.91, 0.056, 0.96), Vector3(0, 0.028, 0), DARK)
	cylinder(0.083, 0.83, Vector3(0, 0.44, 0.23), SURFACE)
	box(Vector3(0.56, 0.040, 0.34), Vector3(0, 0.45, -0.12), STEEL)
	box(Vector3(0.16, 0.061, 0.37), Vector3(0, 0.424, 0.12), STEEL)
	box(Vector3(0.68, 0.14, 0.84), Vector3(0, 0.924, -0.04), MACHINE)
	cylinder(0.062, 0.15, Vector3(0, 0.79, -0.23), SURFACE)
	cylinder(0.013, 0.12, Vector3(0, 0.669, -0.23), DARK)
	box(Vector3(0.23, 0.045, 0.064), Vector3(0.40, 0.892, -0.14), DARK)
	box(Vector3(0.14, 0.045, 0.021), Vector3(0.10, 0.90, -0.47), SAFETY)

func build_bandsaw() -> void:
	box(Vector3(0.89, 0.062, 0.89), Vector3(0, 0.031, 0), DARK, true)
	box(Vector3(0.87, 0.51, 0.72), Vector3(0, 0.285, 0), MACHINE, true)
	var bed := LayoutCatalog.SAW_BED_TOP
	box(Vector3(0.94, 0.08, 0.98), Vector3(0, bed - 0.04, 0), STEEL, true)
	for z in [-0.39, 0.39]:
		box(Vector3(0.43, 0.02, 0.17), Vector3(0, bed - 0.01, z), SURFACE, true)
	box(Vector3(0.13, 0.15, 0.30), Vector3(-0.16, bed + 0.075, -0.14), DARK, true)
	box(Vector3(0.22, 0.24, 0.50), Vector3(0.32, 0.72, 0.06), MACHINE, true)
	var bow := box(Vector3(0.83, 0.182, 0.30), Vector3(-0.025, 0.864, 0.09), MACHINE, true)
	bow.rotation.z = -0.10
	box(Vector3(0.17, 0.075, 0.20), Vector3(-0.38, 0.924, 0.10), SAFETY)

func build_horizontal_rack() -> void:
	for z in [-0.41, 0.0, 0.41]:
		box(Vector3(0.042, 0.92, 0.06), Vector3(-0.444, 0.46, z), DARK, true)
		box(Vector3(0.245, 0.033, 0.06), Vector3(-0.3425, 0.0165, z), STEEL, true)
		for tier in [0.26, 0.51, 0.76]:
			box(Vector3(0.245, 0.035, 0.046), Vector3(-0.3425, tier, z), STEEL, true)
			box(Vector3(0.022, 0.058, 0.046), Vector3(-0.231, tier + 0.031, z), DARK, true)
	for tier in [0.13, 0.88]:
		box(Vector3(0.035, 0.043, 0.88), Vector3(-0.447, tier, 0), DARK, true)

func build_saw_support() -> void:
	for z in [-0.37, 0.37]:
		box(Vector3(0.98, 0.06, 0.12), Vector3(0, 0.03, z), DARK, true)
		for x in [-0.36, 0.36]:
			box(Vector3(0.10, 0.82, 0.085), Vector3(x, 0.43, z), STEEL, true)
	for x in [-0.43, 0.43]:
		box(Vector3(0.12, 0.08, 0.98), Vector3(x, 0.84, 0), STEEL, true)
	if _type == "bandsaw_outfeed_support":
		box(Vector3(0.96, 0.08, 0.97), Vector3(0, 0.96, 0), DARK, true)
		return
	# Unit dimensions are scaled with the stand. Separate narrow colliders
	# match the tops of the stationary rollers for later stock support.
	for z in [-0.36, -0.12, 0.12, 0.36]:
		var center := Vector3(0, 0.95, z)
		cylinder(0.05, 0.72, center, SURFACE, Vector3(0, 0, PI / 2))
		_collision_boxes.append({"size": Vector3(0.72, 0.10, 0.10), "position": center})
		box(Vector3(0.06, 0.073, 0.105), Vector3(-0.39, 0.93, z), DARK, true)
		box(Vector3(0.06, 0.073, 0.105), Vector3(0.39, 0.93, z), DARK, true)

func build_rack() -> void:
	for x in [-0.475, 0.0, 0.475]:
		for z in [-0.44, 0.44]:
			box(Vector3(0.048, 1.0, 0.08), Vector3(x, 0.5, z), STEEL)
	for height in [0.12, 0.40, 0.66, 0.86]:
		box(Vector3(0.98, 0.035, 0.90), Vector3(0, height, 0), STORAGE)
		box(Vector3(0.98, 0.052, 0.05), Vector3(0, height, -0.45), SAFETY)

func build_storage(doors: int, vents: bool) -> void:
	box(Vector3(0.88, 0.10, 0.84), Vector3(0, 0.05, 0.025), DARK)
	box(Vector3(1.0, 0.93, 0.93), Vector3(0, 0.535, 0.035), STORAGE)
	var panel_width := 1.0 / doors
	for index in doors:
		var x := -0.5 + panel_width * (index + 0.5)
		box(Vector3(panel_width - 0.025, 0.86, 0.04), Vector3(x, 0.54, -0.446), MACHINE)
		box(Vector3(0.025, 0.11, 0.03), Vector3(x + panel_width * 0.32, 0.56, -0.48), SURFACE)
		if vents:
			for y in [0.80, 0.827, 0.854]:
				box(Vector3(panel_width * 0.55, 0.010, 0.008), Vector3(x, y, -0.469), DARK)

func build_room_marker() -> void:
	for side in [-1, 1]:
		box(Vector3(1, 0.01, 0.025), Vector3(0, 0.009, side * 0.482), MARKER)
		box(Vector3(0.025, 0.01, 1), Vector3(side * 0.482, 0.009, 0), MARKER)
		for end in [-1, 1]:
			box(Vector3(0.025, 1, 0.025), Vector3(side * 0.482, 0.5, end * 0.482), MARKER)
			box(Vector3(0.20, 0.025, 0.025), Vector3(side * 0.396, 0.985, end * 0.482), MARKER)
			box(Vector3(0.025, 0.025, 0.20), Vector3(side * 0.482, 0.985, end * 0.396), MARKER)

func build_door_marker() -> void:
	for side in [-1, 1]:
		box(Vector3(0.070, 0.965, 0.23), Vector3(side * 0.465, 0.4825, 0), MARKER)
	box(Vector3(1, 0.035, 0.23), Vector3(0, 0.9825, 0), MARKER)
	box(Vector3(1, 0.01, 1), Vector3(0, 0.007, 0), SAFETY)

func box(size: Vector3, at: Vector3, color: Color, solid := false) -> MeshInstance3D:
	if solid:
		_collision_boxes.append({"size": size, "position": at})
	return create_box(size, at, color, _graphics)

func create_box(size: Vector3, at: Vector3, color: Color, parent: Node3D) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return project_mesh(mesh, at, color, parent)

func cylinder(radius: float, height: float, at: Vector3, color: Color, angles := Vector3.ZERO) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 16
	mesh.rings = 0
	project_mesh(mesh, at, color, _graphics).rotation = angles

func project_mesh(mesh: Mesh, at: Vector3, color: Color, parent: Node3D) -> MeshInstance3D:
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.position = at
	part.set_meta(&"finish", color)
	parent.add_child(part)
	return part

static func finish(color: Color) -> StandardMaterial3D:
	if not _finishes.has(color):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.80
		if color.a < 1.0:
			material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_finishes[color] = material
	return _finishes[color]

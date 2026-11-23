class_name StrapMassOverlay
extends Node3D
## World-aligned marks retained as three small drawables while Strap Mode is active.

const KNOWN_COLOR := Color("87eca0")
const ESTIMATED_COLOR := Color("ecc675")
const UNKNOWN_COLOR := Color("a6b0b4")
const POINT_COLOR := Color("6edfe7")

var center_marker: MeshInstance3D
var vertical_line: MeshInstance3D
var strap_marker: MeshInstance3D


func _ready() -> void:
	top_level = true
	center_marker = _sphere("MassCenter", 0.041)
	strap_marker = _sphere("StrapPoint", 0.032)
	var shaft := CylinderMesh.new()
	shaft.top_radius = 0.006
	shaft.bottom_radius = 0.006
	shaft.height = 1.50
	shaft.radial_segments = 8
	shaft.rings = 0
	vertical_line = _graphic("MassVertical", shaft)
	_finish(strap_marker, POINT_COLOR, 0.90)
	clear_center()
	clear_strap()


func show_center(point: Vector3, confidence: int) -> void:
	var color := confidence_color(confidence)
	_finish(center_marker, color, 0.95)
	_finish(vertical_line, color, 0.62)
	center_marker.global_position = point
	vertical_line.global_position = point
	center_marker.show()
	vertical_line.show()


func show_strap(point: Vector3) -> void:
	strap_marker.global_position = point
	strap_marker.show()


func clear_center() -> void:
	center_marker.hide()
	vertical_line.hide()


func clear_strap() -> void:
	strap_marker.hide()


static func confidence_color(confidence: int) -> Color:
	match confidence:
		LiftMassProperties.Confidence.KNOWN:
			return KNOWN_COLOR
		LiftMassProperties.Confidence.ESTIMATED:
			return ESTIMATED_COLOR
		_:
			return UNKNOWN_COLOR


func _sphere(title: String, radius: float) -> MeshInstance3D:
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 12
	sphere.rings = 6
	return _graphic(title, sphere)


func _graphic(title: String, mesh: Mesh) -> MeshInstance3D:
	var graphic := MeshInstance3D.new()
	graphic.name = title
	graphic.mesh = mesh
	graphic.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var finish := StandardMaterial3D.new()
	finish.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	finish.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	finish.no_depth_test = true
	finish.render_priority = 1
	graphic.material_override = finish
	add_child(graphic)
	return graphic


func _finish(graphic: MeshInstance3D, color: Color, opacity: float) -> void:
	var finish := graphic.material_override as StandardMaterial3D
	finish.albedo_color = Color(color, opacity)

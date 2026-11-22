class_name LayoutCatalog
extends RefCounted
## Editor defaults in metres. Each record stores its own editable dimensions.

const DEFINITIONS := {
	"fabrication_table_long": {"name": "Long Fabrication Table", "size": Vector3(6.096, 0.92, 1.524), "marker": false},
	"fabrication_table_medium": {"name": "Medium Fabrication Table", "size": Vector3(3.048, 0.92, 1.524), "marker": false},
	"fabrication_table_small": {"name": "Small Fabrication Table", "size": Vector3(1.8288, 0.92, 1.524), "marker": false},
	"milling_machine": {"name": "Milling Machine", "size": Vector3(1.62, 2.20, 1.32), "marker": false},
	"engine_lathe": {"name": "Engine Lathe", "size": Vector3(2.95, 1.42, 1.04), "marker": false},
	"drill_press": {"name": "Floor Drill Press", "size": Vector3(0.74, 1.94, 0.82), "marker": false},
	"horizontal_bandsaw": {"name": "Horizontal Bandsaw", "size": Vector3(1.64, 1.03, 0.77), "marker": false},
	"material_storage_rack": {"name": "Material Storage Rack", "size": Vector3(2.64, 2.05, 0.78), "marker": false},
	"lockers": {"name": "Lockers", "size": Vector3(1.20, 1.91, 0.47), "marker": false},
	"storage_cabinet": {"name": "Storage Cabinet", "size": Vector3(1.10, 1.58, 0.54), "marker": false},
	"workbench": {"name": "Workbench", "size": Vector3(1.85, 0.94, 0.78), "marker": false},
	"storage_room_marker": {"name": "Storage Room Marker", "size": Vector3(3.65, 2.45, 3.05), "marker": true},
	"personnel_door_marker": {"name": "Personnel Door Marker", "size": Vector3(0.96, 2.11, 0.22), "marker": true},
}

static func types() -> Array[String]:
	var result: Array[String] = []
	result.assign(DEFINITIONS.keys())
	return result

static func definition(type: String) -> Dictionary:
	return DEFINITIONS[type].duplicate() if DEFINITIONS.has(type) else {}

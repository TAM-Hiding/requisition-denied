class_name LayoutCatalog
extends RefCounted
## Editor defaults in metres. Each record stores its own editable dimensions.

const SAW_BED_TOP := 0.65

const DEFINITIONS := {
	"fabrication_table_long": {"name": "Long Fabrication Table", "size": Vector3(6.096, 0.92, 1.524), "marker": false},
	"fabrication_table_medium": {"name": "Medium Fabrication Table", "size": Vector3(3.048, 0.92, 1.524), "marker": false},
	"fabrication_table_small": {"name": "Small Fabrication Table", "size": Vector3(1.8288, 0.92, 1.524), "marker": false},
	"milling_machine": {"name": "Milling Machine", "size": Vector3(1.62, 2.20, 1.32), "marker": false},
	"engine_lathe": {"name": "Engine Lathe", "size": Vector3(2.95, 1.42, 1.04), "marker": false},
	"drill_press": {"name": "Floor Drill Press", "size": Vector3(0.74, 1.94, 0.82), "marker": false},
	"horizontal_bandsaw": {"name": "Horizontal Bandsaw", "size": Vector3(1.64, 1.03, 0.77), "marker": false},
	"horizontal_stock_rack": {"name": "Horizontal Stock Rack", "size": Vector3(3.65, 2.45, 3.05), "marker": false},
	"bandsaw_infeed_stand": {"name": "Infeed Roller Stand", "size": Vector3(0.59, 0.67, 0.92), "marker": false},
	"bandsaw_outfeed_support": {"name": "Outfeed Support", "size": Vector3(0.59, 0.67, 0.92), "marker": false},
	"material_storage_rack": {"name": "Material Storage Rack", "size": Vector3(2.64, 2.05, 0.78), "marker": false},
	"lockers": {"name": "Lockers", "size": Vector3(1.20, 1.91, 0.47), "marker": false},
	"storage_cabinet": {"name": "Storage Cabinet", "size": Vector3(1.10, 1.58, 0.54), "marker": false},
	"workbench": {"name": "Workbench", "size": Vector3(1.85, 0.94, 0.78), "marker": false},
	"storage_room_marker": {"name": "Storage Room Marker", "size": Vector3(3.65, 2.45, 3.05), "marker": true},
	"personnel_door_marker": {"name": "Personnel Door Marker", "size": Vector3(0.96, 2.11, 0.22), "marker": true},
}

## Nominal gameplay mass and center fractions for modeled layout fixtures.
const MASS_ESTIMATES := {
	"fabrication_table_long": [322.0, Vector3(0.0, 0.78, 0.0)],
	"fabrication_table_medium": [170.0, Vector3(0.0, 0.78, 0.0)],
	"fabrication_table_small": [110.0, Vector3(0.0, 0.76, 0.0)],
	"workbench": [82.0, Vector3(0.0, 0.61, 0.0)],
	"milling_machine": [970.0, Vector3(0.0, 0.42, 0.06)],
	"engine_lathe": [1310.0, Vector3(-0.11, 0.56, 0.0)],
	"drill_press": [95.0, Vector3(0.0, 0.49, 0.10)],
	"horizontal_bandsaw": [365.0, Vector3(0.04, 0.36, 0.0)],
	"storage_cabinet": [83.0, Vector3(0.0, 0.44, 0.0)],
	"lockers": [67.0, Vector3(0.0, 0.46, 0.0)],
}

static func mass_estimate(type: String, size: Vector3, display_name: String) -> Dictionary:
	if not MASS_ESTIMATES.has(type):
		return {}
	var estimate: Array = MASS_ESTIMATES[type]
	var center: Vector3 = estimate[1]
	return {"name": display_name, "mass_kg": estimate[0], "center": center * size,
		"confidence": LiftMassProperties.Confidence.ESTIMATED}


static func types() -> Array[String]:
	var result: Array[String] = []
	result.assign(DEFINITIONS.keys())
	return result

static func definition(type: String) -> Dictionary:
	return DEFINITIONS[type].duplicate() if DEFINITIONS.has(type) else {}


static func occupied_box(type: String) -> AABB:
	# Match the open rack geometry inside its planning envelope. Rack yaw
	# controls which side is occupied, including the legacy arrangements.
	if type == "horizontal_stock_rack":
		return AABB(Vector3(-0.465, 0.0, -0.44), Vector3(0.245, 1.0, 0.88))
	return AABB(Vector3(-0.5, 0.0, -0.5), Vector3.ONE)

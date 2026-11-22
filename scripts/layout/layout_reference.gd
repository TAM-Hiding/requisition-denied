class_name LayoutReference
extends RefCounted
## The source file stays in the original schema and coordinate space.
const PATH := "res://data/layouts/engineering_hall_approved.json"
const APPROVED_DATA: JSON = preload("res://data/layouts/engineering_hall_approved.json")
const RACK_IDS := ["db52a041ea8717380c34d01def65f71a", "e0245a6aed43eff84ef9cd66ddc2fa3c"]
const DOOR_IDS := ["001984df9d48bf4f879d23b872f80ff9", "9898c08d10762bd5f4bfb296bf4f4c4f"]
const SAW_ID := "193dbaa3a4b1d730e1e56c34d745ccbe"

static func is_integrated_door(record: Dictionary) -> bool:
	return record.type == "personnel_door_marker" and record.id in DOOR_IDS

static func migrate(incoming: Array[Dictionary]) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	for value in incoming:
		var record := value.duplicate(true)
		if record.id in RACK_IDS and record.type == "storage_room_marker":
			record.type = "horizontal_stock_rack"
			if record.name == "Storage Room Marker":
				record.name = "Horizontal Stock Rack"
		records.append(record)
	return records

static func approved() -> Dictionary:
	var result := LayoutStorage.decode_data(APPROVED_DATA.data)
	if not result.ok:
		return result
	var records := migrate(result.records)
	for record in records.duplicate():
		if record.id == SAW_ID and record.type == "horizontal_bandsaw":
			# The shorter infeed sits between the front rack and the saw.
			var infeed := saw_support(record, "bandsaw_infeed_stand", -0.76)
			infeed.size.z = 0.60
			records.append(infeed)
			records.append(saw_support(record, "bandsaw_outfeed_support", 1.80))
	result.records = records
	return result

static func saw_support(saw: Dictionary, type: String, feed_offset: float) -> Dictionary:
	var spec := LayoutCatalog.definition(type)
	var size: Vector3 = spec.size
	size.y = Vector3(saw.size).y * LayoutCatalog.SAW_BED_TOP
	var position: Vector3 = saw.position
	position += (Vector3.BACK * feed_offset).rotated(Vector3.UP, saw.yaw)
	return {"id": "rd014c-" + type, "type": type, "name": spec.name, "position": position,
		"yaw": saw.yaw, "size": size, "properties": {}}

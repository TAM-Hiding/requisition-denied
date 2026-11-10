class_name PlayerKnowledge
extends RefCounted
## Actor-owned snapshots. World changes do not silently rewrite learned facts.
var _inspections: Dictionary = {}

func record_inspection(object_id: StringName, information: Dictionary) -> bool:
	if object_id == &"" or information.is_empty():
		return false
	var records: Array = _inspections.get(object_id, [])
	if records.has(information):
		return false
	records.append(information.duplicate(true))
	_inspections[object_id] = records
	return true

func inspected_object_count() -> int:
	return _inspections.size()

func has_inspected(object_id: StringName) -> bool:
	return _inspections.has(object_id)

func records_for(object_id: StringName) -> Array:
	return _inspections.get(object_id, []).duplicate(true)

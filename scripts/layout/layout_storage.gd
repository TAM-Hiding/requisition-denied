class_name LayoutStorage
extends RefCounted
## JSON layouts use hall-local meters and a floor-axis yaw in radians.
const DIRECTORY := "user://engineering-layouts"
const SCHEMA_VERSION := 1
const COORDINATE_SPACE := "engineering_test_hall_local"
const UNITS := {"position": "m", "size": "m", "yaw": "rad"}
const MIN_SIZE := 0.1
const MAX_SIZE := 40.0

static func ensure_directory() -> String:
	if DirAccess.dir_exists_absolute(DIRECTORY):
		return ""
	var result := DirAccess.make_dir_recursive_absolute(DIRECTORY)
	return "" if result == OK else "Could not create the layout folder: %s." % error_string(result)

static func encode(records: Array[Dictionary]) -> String:
	if not _validate_records(records).is_empty():
		return ""
	var entries: Array[Dictionary] = []
	for record in records:
		entries.append({
			"id": String(record.id),
			"type": String(record.type),
			"name": String(record.name),
			"position": _components(record.position),
			"size": _components(record.size),
			"yaw": float(record.yaw),
			"properties": record.properties,
		})
	return JSON.stringify({
		"schema_version": SCHEMA_VERSION,
		"coordinate_space": COORDINATE_SPACE,
		"units": UNITS,
		"records": entries,
	}, "\t", true, true) + "\n"

static func decode(text: String) -> Dictionary:
	var json := JSON.new()
	if json.parse(text) != OK:
		return _failure("Layout JSON at line %d: %s" % [json.get_error_line() + 1, json.get_error_message()])
	var data: Variant = json.data
	if not data is Dictionary:
		return _failure("The layout must be a JSON object.")
	var version: Variant = data.get("schema_version")
	if not _number(version) or version != SCHEMA_VERSION:
		return _failure("Unsupported layout schema version.")
	if data.get("coordinate_space") != COORDINATE_SPACE or data.get("units") != UNITS:
		return _failure("Layouts must use hall-local meters and yaw in radians.")
	if not data.get("records") is Array:
		return _failure("The layout must include a records array.")
	var records: Array[Dictionary] = []
	for entry: Variant in data.records:
		var index := records.size() + 1
		if not entry is Dictionary:
			return _failure("Record %d must be a JSON object." % index)
		if not _triple(entry.get("position")) or not _triple(entry.get("size")):
			return _failure("Record %d requires three finite coordinates for position and size." % index)
		# Reject invalid wire values before Vector3 narrows them to engine precision.
		if entry.position[1] != 0.0:
			return _failure("Record %d must be positioned on the hall floor." % index)
		for dimension: float in entry.size:
			if dimension < MIN_SIZE or dimension > MAX_SIZE:
				return _failure("Record %d dimensions must be between %.1f and %.0f meters." % [index, MIN_SIZE, MAX_SIZE])
		records.append({
			"id": entry.get("id"),
			"type": entry.get("type"),
			"name": entry.get("name"),
			"position": Vector3(entry.position[0], entry.position[1], entry.position[2]),
			"size": Vector3(entry.size[0], entry.size[1], entry.size[2]),
			"yaw": entry.get("yaw"),
			"properties": entry.get("properties"),
		})
	var error := _validate_records(records)
	if not error.is_empty():
		return _failure(error)
	return {"ok": true, "records": records, "error": ""}

static func read(path: String) -> Dictionary:
	if path.is_empty():
		return _failure("Select a layout file.")
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return _failure("Could not open the layout: %s." % error_string(FileAccess.get_open_error()))
	return decode(file.get_as_text())

static func write_new(path: String, records: Array[Dictionary]) -> String:
	var destination := ProjectSettings.globalize_path(path)
	if not destination.is_absolute_path() or path.get_file().is_empty():
		return "Select a destination filename for the layout."
	if FileAccess.file_exists(destination) or DirAccess.dir_exists_absolute(destination):
		return "A file or folder already exists at that destination."
	var payload := encode(records)
	if payload.is_empty():
		return _validate_records(records)
	var folder := destination.get_base_dir()
	var temporary := folder.path_join(".rd-layout-%s.tmp" % Crypto.new().generate_random_bytes(16).hex_encode())
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return "Could not open a temporary layout file: %s." % error_string(FileAccess.get_open_error())
	var stored := file.store_string(payload)
	file.flush()
	var write_error := file.get_error()
	file.close()
	if not stored or write_error != OK:
		DirAccess.remove_absolute(temporary)
		return "Could not write the complete layout: %s." % error_string(write_error if write_error != OK else ERR_FILE_CANT_WRITE)

	# A Linux hard link atomically publishes the complete file and fails when
	# the destination exists, including a directory or dangling symlink.
	var output: Array = []
	var published := OS.execute("ln", PackedStringArray(["-T", "--", temporary, destination]), output, true)
	DirAccess.remove_absolute(temporary)
	if published != 0:
		var detail := String(output[0]).strip_edges() if not output.is_empty() else ""
		return "Could not publish the layout without overwriting: %s" % (detail if not detail.is_empty() else "link creation failed.")
	return ""

static func _validate_records(records: Array[Dictionary]) -> String:
	var ids := {}
	for index in records.size():
		var record := records[index]
		var label := "Record %d" % (index + 1)
		if not _nonempty_text(record.get("id")) or not _nonempty_text(record.get("name")):
			return "%s requires an ID and name." % label
		var id := String(record.id)
		if ids.has(id):
			return "%s has a duplicate ID: %s." % [label, id]
		ids[id] = true
		var type: Variant = record.get("type")
		if not _nonempty_text(type) or LayoutCatalog.definition(String(type)).is_empty():
			return "%s has an unknown catalog type." % label
		var position: Variant = record.get("position")
		if not position is Vector3 or not position.is_finite() or position.y != 0.0:
			return "%s must be positioned on the hall floor with finite coordinates." % label
		var size: Variant = record.get("size")
		if not size is Vector3 or not size.is_finite() or size[size.min_axis_index()] < MIN_SIZE 				or size[size.max_axis_index()] > MAX_SIZE:
			return "%s dimensions must be between %.1f and %.0f meters." % [label, MIN_SIZE, MAX_SIZE]
		var yaw: Variant = record.get("yaw")
		if not _number(yaw) or absf(yaw) > TAU:
			return "%s yaw must be finite and within one turn in radians." % label
		var properties: Variant = record.get("properties")
		if not properties is Dictionary or not _json_value(properties, 0):
			return "%s properties must be a JSON object with JSON-compatible values." % label
	return ""

static func _failure(error: String) -> Dictionary:
	var records: Array[Dictionary] = []
	return {"ok": false, "records": records, "error": error}

static func _nonempty_text(value: Variant) -> bool:
	return (value is String or value is StringName) and not String(value).strip_edges().is_empty()

static func _number(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value))

static func _triple(value: Variant) -> bool:
	return value is Array and value.size() == 3 and _number(value[0]) and _number(value[1]) and _number(value[2])

static func _components(value: Vector3) -> Array[float]:
	return [value.x, value.y, value.z]

static func _json_value(value: Variant, depth: int) -> bool:
	# Bound recursive user data, including cyclic dictionaries passed to encode.
	if depth > 64:
		return false
	if value == null or value is bool or value is String or value is StringName or _number(value):
		return true
	if value is Array:
		for element: Variant in value:
			if not _json_value(element, depth + 1):
				return false
		return true
	if value is Dictionary:
		for key: Variant in value:
			if not (key is String or key is StringName) or not _json_value(value[key], depth + 1):
				return false
		return true
	return false

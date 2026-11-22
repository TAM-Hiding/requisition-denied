extends SceneTree

var checks := 0
var failures := 0

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(message)

func sample() -> Array[Dictionary]:
	return [{
		"id": "table-01",
		"type": "fabrication_table_long",
		"name": "Fabrication Bench — left",
		"position": Vector3(-6.125, 0.0, 8.625),
		"size": Vector3(6.096, 0.92, 1.524),
		"yaw": -PI / 3.0,
		"properties": {"drawing": "A-123", "locked": false, "metadata": [1.25, {"side": "east"}]},
	}, {
		"id": "door-01",
		"type": "personnel_door_marker",
		"name": "Personnel Door",
		"position": Vector3(0.5, 0.0, 12.0),
		"size": Vector3(0.96, 2.11, 0.22),
		"yaw": PI,
		"properties": {},
	}]

func wire() -> Dictionary:
	return JSON.parse_string(LayoutStorage.encode(sample()))

func reject_edit(key: String, value: Variant, description: String) -> void:
	var data := wire()
	data.records[0][key] = value
	var result := LayoutStorage.decode(JSON.stringify(data, "", true, true))
	check(not result.ok and result.records.is_empty() and not result.error.is_empty(), description)

func codec_checks() -> void:
	var records := sample()
	var encoded := LayoutStorage.encode(records)
	var result := LayoutStorage.decode(encoded)
	check(result.ok and result.error.is_empty() and result.records == records,
		"JSON round trip preserves stable IDs, dimensions, hall-local transforms, and properties")
	var data := wire()
	check(data.schema_version == 1 and data.coordinate_space == "engineering_test_hall_local"
		and data.units == {"position": "m", "size": "m", "yaw": "rad"},
		"JSON explicitly identifies its schema and coordinate units")
	check(data.records[0].position == [-6.125, 0.0, 8.625] and is_equal_approx(data.records[0].yaw, -PI / 3.0),
		"Wire format stores position as a coordinate triple and yaw in radians")
	check(LayoutStorage.decode(LayoutStorage.encode([])).ok, "Empty layouts are valid")
	check(not LayoutStorage.decode("[").ok and not LayoutStorage.decode("[]").ok,
		"Parser rejects malformed data and roots outside the schema")
	for invalid_version: Variant in [true, "1", 2]:
		data.schema_version = invalid_version
		check(not LayoutStorage.decode(JSON.stringify(data)).ok, "Unsupported or nonnumeric schema version is rejected")
	data = wire()
	data.units.yaw = "deg"
	check(not LayoutStorage.decode(JSON.stringify(data)).ok, "A foreign angle unit is rejected")
	data = wire()
	data.records.append(data.records[0].duplicate())
	check(not LayoutStorage.decode(JSON.stringify(data)).ok, "Duplicate identities reject the entire import")
	reject_edit("id", "", "Empty IDs are rejected")
	reject_edit("type", "unknown_fixture", "Unknown catalog types are rejected")
	reject_edit("name", null, "Missing names are rejected")
	reject_edit("position", [1, 0, 2, 3], "Coordinates must be exact triples")
	reject_edit("position", [1, -0.01, 2], "Negative positions below the hall datum are rejected")
	reject_edit("position", [1, -1e-50, 2], "A negative elevation cannot narrow into a valid floor coordinate")
	reject_edit("position", [1e100, 0, 2], "Coordinate overflow cannot enter the native Vector3")
	reject_edit("size", [0.09, 2, 1], "Subminimum dimensions are rejected")
	reject_edit("size", [1, 2, 41], "Oversized dimensions are rejected")
	reject_edit("size", [1, true, 1], "Boolean dimensions are rejected")
	reject_edit("yaw", "0", "String yaw is rejected")
	reject_edit("yaw", 100, "Out-of-range yaw is rejected")
	reject_edit("properties", ["tags"], "Properties must be an object")
	records[0].position = Vector3(INF, 0, 0)
	check(LayoutStorage.encode(records).is_empty(), "Native nonfinite coordinates cannot be exported")
	records = sample()
	records[0].properties = {"bad": Vector2.ZERO}
	check(LayoutStorage.encode(records).is_empty(), "Native non-JSON property values cannot be exported")
	records = sample()
	records[0].size = Vector3(LayoutStorage.MIN_SIZE, LayoutStorage.MAX_SIZE, 1.0)
	check(LayoutStorage.decode(LayoutStorage.encode(records)).ok, "Boundary dimensions round-trip without truncation")
	records[0].position.y = 3.35
	records[0].yaw = 0.123456789012345
	var elevated := LayoutStorage.decode(LayoutStorage.encode(records))
	check(elevated.ok and elevated.records == records,
		"Schema version one round-trips an elevated base and custom rotation without rounding")

func file_checks() -> void:
	var directory := "user://rd-layout-test-" + Crypto.new().generate_random_bytes(8).hex_encode()
	if DirAccess.make_dir_absolute(directory) != OK:
		check(false, "Create an isolated storage test folder")
		return
	var first := directory.path_join("Saved layout – east.json")
	var records := sample()
	check(LayoutStorage.write_new(first, records).is_empty(), "Writes a complete new layout")
	var loaded := LayoutStorage.read(ProjectSettings.globalize_path(first))
	check(loaded.ok and loaded.records == records, "Read restores the saved records from an absolute export path")
	var other := sample()
	other[0].name = "a different name"
	var before := FileAccess.get_file_as_string(first)
	check(not LayoutStorage.write_new(first, other).is_empty() and FileAccess.get_file_as_string(first) == before,
		"An existing destination stays byte-for-byte unchanged")
	var wrong_directory := directory.path_join("missing/failed.json")
	check(not LayoutStorage.write_new(wrong_directory, records).is_empty() and not FileAccess.file_exists(wrong_directory),
		"A missing export folder fails without creating a partial layout")
	var rejected := directory.path_join("invalid.json")
	other[0].yaw = INF
	check(not LayoutStorage.write_new(rejected, other).is_empty() and not FileAccess.file_exists(rejected),
		"Invalid data never reaches disk")

	var race := directory.path_join("Race.json")
	other = sample()
	other[0].name = "competing writer"
	var writer_a := Thread.new()
	var writer_b := Thread.new()
	var start_a := writer_a.start(LayoutStorage.write_new.bind(race, records))
	var start_b := writer_b.start(LayoutStorage.write_new.bind(race, other))
	var result_a: String = writer_a.wait_to_finish() if start_a == OK else "could not start"
	var result_b: String = writer_b.wait_to_finish() if start_b == OK else "could not start"
	loaded = LayoutStorage.read(race)
	check(start_a == OK and start_b == OK and result_a.is_empty() != result_b.is_empty()
		and loaded.ok and loaded.records == (records if result_a.is_empty() else other),
		"Concurrent publishers of one filename yield exactly one complete winner")
	var saved_files := DirAccess.open(directory)
	saved_files.include_hidden = true
	check(saved_files.get_files().size() == 2,
		"Successful and failed saves clean up their staging files")
	for name in saved_files.get_files():
		DirAccess.remove_absolute(directory.path_join(name))
	DirAccess.remove_absolute(directory)

func run() -> void:
	codec_checks()
	file_checks()
	print("RD-014B layout storage: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

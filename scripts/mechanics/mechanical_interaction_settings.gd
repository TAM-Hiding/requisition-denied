class_name MechanicalInteractionSettings
extends RefCounted

signal changed

const FILE_PATH := "user://mechanical_interaction_settings.json"
const VERSION := 1
const VISUAL_SCALE_KEY := "fastener_visual_scale_percent"
const CONTROL_LIMITS := {
	"mouse_sensitivity": Vector2(0.0005, 0.01),
	"precision_rotation_sensitivity": Vector2(0.001, 0.03),
	"ads_sensitivity_multiplier": Vector2(0.25, 2.0),
}
const LIMITS := {
	"acquisition_distance_m": Vector2(0.10, 0.60),
	"snap_distance_m": Vector2(0.01, 0.30),
	"axis_tolerance_degrees": Vector2(1, 60),
	"key_rotation_tolerance_degrees": Vector2(1, 75),
	"snap_duration_seconds": Vector2(0.05, 1.0),
}
const DEFAULTS := {
	"schema_version": VERSION,
	"fastener_visual_scale_percent": 100,
	"controls": {
		"mouse_sensitivity": 0.0025,
		"precision_rotation_sensitivity": 0.009,
		"ads_sensitivity_multiplier": 0.75,
	},
	"installation": {
		"acquisition_distance_m": 0.30,
		"snap_distance_m": 0.20,
		"axis_tolerance_degrees": 30.0,
		"key_rotation_tolerance_degrees": 35.0,
		"snap_duration_seconds": 0.20,
	},
	"pickup": {"show_clearance_diagnostics": true},
	"rotation": {"invert_horizontal": false, "invert_vertical": false},
	"debug": {"show_alignment_diagnostics": true},
}

var values := DEFAULTS.duplicate(true)

func reset() -> void:
	values = DEFAULTS.duplicate(true)
	changed.emit()

func load_file(path: String = FILE_PATH) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return "Cannot read settings (%s)." % error_string(FileAccess.get_open_error())
	if file.get_length() > 65536:
		return "Settings file exceeds 64 KiB."
	var parser := JSON.new()
	if parser.parse(file.get_as_text()) != OK:
		return "Invalid JSON on line %d: %s" % [parser.get_error_line(), parser.get_error_message()]
	return apply(parser.data)

func apply(candidate: Variant) -> String:
	if not candidate is Dictionary:
		return "Expected a settings JSON object."
	var version: Variant = candidate.get("schema_version")
	if typeof(version) not in [TYPE_INT, TYPE_FLOAT] or version != VERSION:
		return "Unsupported mechanical settings schema version: %s." % str(version)
	var validated := DEFAULTS.duplicate(true)
	for section: String in ["installation", "pickup", "rotation", "debug"]:
		var fields: Variant = candidate.get(section)
		if not fields is Dictionary:
			return "Missing settings section: %s." % section
		for key: String in DEFAULTS[section]:
			var value: Variant = fields.get(key)
			if section == "installation":
				var limits: Vector2 = LIMITS[key]
				if typeof(value) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(value)):
					return "%s must be a finite number." % key
				# Vector2 endpoints are float32 while JSON values are double.
				if value < snappedf(limits.x, 0.001) or value > snappedf(limits.y, 0.001):
					return "%s must be between %s and %s." % [key, limits.x, limits.y]
			elif typeof(value) != TYPE_BOOL:
				return "%s must be true or false." % key
			validated[section][key] = value
	if validated.installation.acquisition_distance_m < validated.installation.snap_distance_m:
		return "Acquisition distance must be at least the snap distance."
	var scale: Variant = candidate.get(VISUAL_SCALE_KEY, DEFAULTS[VISUAL_SCALE_KEY])
	if not numeric_in_range(scale, 75.0, 250.0):
		return "Fastener visual scale must be between 75% and 250%."
	validated[VISUAL_SCALE_KEY] = roundi(snappedf(float(scale), 5.0))
	var controls: Variant = candidate.get("controls", {})
	if not controls is Dictionary:
		return "Controls must be a settings object."
	for key: String in CONTROL_LIMITS:
		var bounds: Vector2 = CONTROL_LIMITS[key]
		var value: Variant = controls.get(key, DEFAULTS.controls[key])
		if not numeric_in_range(value, snappedf(bounds.x, 0.00001), snappedf(bounds.y, 0.00001)):
			return "%s is out of range." % key
		validated.controls[key] = value
	values = validated
	changed.emit()
	return ""

static func numeric_in_range(value: Variant, minimum: float, maximum: float) -> bool:
	return typeof(value) in [TYPE_FLOAT, TYPE_INT] and is_finite(float(value)) and value >= minimum and value <= maximum

func save_file(path: String = FILE_PATH) -> String:
	var temporary := path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return "Cannot write settings (%s)." % error_string(FileAccess.get_open_error())
	file.store_string(JSON.stringify(values, "\t") + "\n")
	file.flush()
	var result := file.get_error()
	file.close()
	if result == OK:
		result = DirAccess.rename_absolute(temporary, path)
	if result != OK:
		DirAccess.remove_absolute(temporary)
		return "Cannot save settings (%s)." % error_string(result)
	return ""

func export_snapshot() -> String:
	var stamp := Time.get_datetime_string_from_system().replace(":", "-")
	var path := "user://mechanical_interaction_%s_%d.json" % [stamp, Time.get_ticks_msec()]
	var issue := save_file(path)
	return ProjectSettings.globalize_path(path) if issue.is_empty() else ""

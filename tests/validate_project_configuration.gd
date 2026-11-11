extends SceneTree
var checks: int = 0
var failures: int = 0
func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(message)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var version := Engine.get_version_info()
	check(version.major == 4 and version.minor == 7 and version.patch == 2, "Configuration validation requires Godot 4.7.2")
	check(ClassDB.class_exists("JoltPhysicsServer3D"), "Jolt backend is available in this build")
	var world := root.find_world_3d()
	var space_class := world.direct_space_state.get_class()
	check(space_class == "JoltPhysicsDirectSpaceState3D", "Active physics space really uses Jolt")
	var body := PhysicsServer3D.body_create()
	PhysicsServer3D.body_set_space(body, world.space)
	var body_class := PhysicsServer3D.body_get_direct_state(body).get_class()
	check(body_class == "JoltPhysicsDirectBodyState3D", "Active physics body really uses Jolt")
	PhysicsServer3D.free_rid(body)
	var method := RenderingServer.get_current_rendering_method()
	var driver := RenderingServer.get_current_rendering_driver_name()
	check(method == "gl_compatibility", "Active rendering method is Compatibility")
	check(driver == "opengl3", "Active rendering driver is OpenGL 3")
	var canonical := "user://rd-project-roundtrip.godot"
	check(ProjectSettings.save_custom(canonical) == OK, "Engine can serialize project settings")
	check(FileAccess.get_file_as_string(canonical) == FileAccess.get_file_as_string("res://project.godot"), "Tracked config matches Godot's canonical round-trip representation")
	for action in ["move_forward", "move_back", "move_left", "move_right", "interact", "debug_overlay", "drop_item", "equip_first"]:
		var events := InputMap.action_get_events(action)
		check(events.size() == 1 and events[0] is InputEventKey and events[0].physical_keycode != 0, "Physical input binding preserved: " + action)
	print("Backend verification: ", space_class, " / ", body_class, "; renderer=", method, "; driver=", driver, "; display=", DisplayServer.get_name())
	if DisplayServer.get_name() != "headless":
		print("Video adapter: ", RenderingServer.get_video_adapter_name())
	print("Project configuration: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

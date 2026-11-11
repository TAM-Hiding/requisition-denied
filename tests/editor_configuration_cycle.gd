@tool
extends EditorPlugin
## Used only by validate_editor_configuration.py in a disposable project copy.
func _enter_tree() -> void:
	if DisplayServer.get_name() != "headless":
		call_deferred("run_cycle")
func run_cycle() -> void:
	while EditorInterface.get_resource_filesystem().is_scanning():
		await get_tree().process_frame
	await get_tree().create_timer(1).timeout
	var saved := ProjectSettings.save()
	EditorInterface.play_main_scene()
	await get_tree().create_timer(3).timeout
	var played := EditorInterface.is_playing_scene()
	EditorInterface.stop_playing_scene()
	await get_tree().create_timer(1).timeout
	var stopped := not EditorInterface.is_playing_scene()
	print("EDITOR_CYCLE saved=", saved == OK, " played=", played, " stopped=", stopped)
	get_tree().quit(0 if saved == OK and played and stopped else 1)

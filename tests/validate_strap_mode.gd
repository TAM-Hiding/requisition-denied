extends SceneTree

class HeadlessLocomotion extends OtisLocomotion:
	func input_active() -> bool:
		return actor.controls_enabled

var checks := 0
var failures := 0
var actor: OtisController
var hall: Node3D
var ui: CanvasLayer
var crane: BridgeCrane


func _initialize() -> void:
	run.call_deferred()


func check(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)


func frames(count: int) -> void:
	for tick in count:
		await physics_frame


func tap(code: Key) -> void:
	var pressed := InputEventKey.new()
	pressed.physical_keycode = code
	pressed.keycode = code
	pressed.pressed = true
	Input.parse_input_event(pressed)
	var released := pressed.duplicate() as InputEventKey
	released.pressed = false
	Input.parse_input_event(released)
	Input.flush_buffered_events()


func click(button: MouseButton) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	Input.parse_input_event(event)
	var released := event.duplicate() as InputEventMouseButton
	released.pressed = false
	Input.parse_input_event(released)
	Input.flush_buffered_events()


func aim(point: Vector3) -> void:
	var ray := (point - actor.camera.global_position).normalized()
	actor.rotation.y = atan2(-ray.x, -ray.z)
	actor.camera.rotation.x = asin(ray.y)


func load_fixture() -> RigidBody3D:
	var load := RigidBody3D.new()
	load.name = "StrapTestBeam"
	load.mass = 32.0
	load.position = Vector3(-1.5, 0.15, 8.0)
	load.set_meta(LiftMassProperties.FIXTURE_PROPERTIES, {"center": Vector3(0.25, 0, 0)})
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.65, 0.27, 0.52)
	collider.shape = shape
	load.add_child(collider)
	hall.add_child(load)
	return load


func run() -> void:
	var facility := preload("res://scenes/facility.tscn").instantiate()
	root.add_child(facility)
	current_scene = facility
	actor = facility.get_node("Otis")
	hall = facility.get_node("EngineeringTestHall")
	ui = facility.get_node("InteractionUI")
	crane = facility.overhead_crane
	if DisplayServer.get_name() == "headless":
		actor.remove_child(actor.locomotion)
		actor.locomotion.free()
		actor.locomotion = HeadlessLocomotion.new()
		actor.add_child(actor.locomotion)
		actor.locomotion.feedback.connect(ui.show_feedback)
	var mode := ui.get("strap_mode") as StrapMode
	var load := load_fixture()
	await frames(6)
	tap(KEY_H)
	check(not mode.active, "H does not open Strap Mode outside the hall")
	actor.global_position = hall.to_global(Vector3(-1.75, 0.04, 6.25))
	crane.adjust_hook_steps(-47.0, false)
	await frames(410)

	aim(load.to_global(Vector3(-0.19, 0.09, -0.20)))
	tap(KEY_H)
	await frames(4)
	check(mode.active and mode.hovered != null and mode.hovered.root == load,
		"H enables Strap Mode and resolves the actual camera-ray load")
	check(mode.overlay.center_marker.visible and mode.overlay.vertical_line.visible
		and mode.overlay.center_marker.global_position.is_equal_approx(load.to_global(Vector3(0.25, 0, 0))),
		"Authored local center appears at the correct world position through the load")
	check(Color(mode.overlay.center_marker.material_override.albedo_color, 1.0).is_equal_approx(mode.overlay.KNOWN_COLOR)
		and mode.overlay.vertical_line.global_basis.y.is_equal_approx(Vector3.UP)
		and mode.overlay.vertical_line.global_position.is_equal_approx(mode.overlay.center_marker.global_position),
		"Known center uses a green world-vertical marker")
	load.remove_meta(LiftMassProperties.FIXTURE_PROPERTIES)
	await frames(2)
	check(mode.hovered != null and mode.hovered.confidence == LiftMassProperties.Confidence.ESTIMATED
		and Color(mode.overlay.center_marker.material_override.albedo_color, 1.0).is_equal_approx(mode.overlay.ESTIMATED_COLOR),
		"Un-authored collider geometry uses an amber estimate")
	load.set_meta(LiftMassProperties.FIXTURE_PROPERTIES, {"center": Vector3(0.1, 0, 0)})
	await frames(2)
	check(mode.overlay.center_marker.global_position.is_equal_approx(load.to_global(Vector3(0.1, 0, 0)))
		and StrapMassOverlay.confidence_color(LiftMassProperties.Confidence.UNKNOWN) == StrapMassOverlay.UNKNOWN_COLOR,
		"Changed mass metadata refreshes the marker and insufficient information is gray")

	var exact_hit := actor.target_hit()
	click(MOUSE_BUTTON_LEFT)
	await frames(2)
	check(mode.selected_body == load and mode.overlay.strap_marker.visible
		and mode.overlay.strap_marker.global_position.distance_to(exact_hit.get("position", Vector3.INF)) < 0.02,
		"LMB sets the actual surface hit rather than an automatic balancing point")
	tap(KEY_E)
	check(crane.rigged_body() == null and mode.selected_body == load and not ui.menu_open,
		"E aimed at the load cannot attach or open an ordinary interaction menu")
	aim(crane.hook_collision_body().global_position + Vector3.UP * 0.06)
	await frames(3)
	tap(KEY_E)
	check(crane.rigged_body() == load and mode.selected_body == null,
		"E aimed at the physical hook connects the selected load")
	tap(KEY_H)
	check(not mode.active and not mode.overlay.strap_marker.visible and not mode.overlay.center_marker.visible
		and crane.rigged_body() == load, "Leaving Strap Mode hides all markers and keeps the physical strap connected")
	tap(KEY_H)
	click(MOUSE_BUTTON_RIGHT)
	check(crane.rigged_body() == null, "RMB aimed at the hook releases its strap")

	aim(load.to_global(Vector3(-0.19, 0.09, -0.20)))
	await frames(3)
	click(MOUSE_BUTTON_LEFT)
	tap(KEY_T)
	check(not mode.active and ui.inventory.active and not mode.overlay.center_marker.visible,
		"Opening the satchel dismisses Strap Mode and its overlays")
	tap(KEY_T)
	tap(KEY_H)
	check(mode.active and mode.selected_body == load, "Returning to Strap Mode preserves the chosen surface")
	var remote := facility.crane_remote as CraneRemote
	check(actor.equipment.pick_up(remote).ok, "Can equip the existing remote to test modal handoff")
	tap(KEY_V)
	check(ui.crane_control.active() and not mode.active and not mode.overlay.strap_marker.visible,
		"Connecting the existing remote dismisses interactive rigging")
	tap(KEY_H)
	check(ui.crane_control.active() and not mode.active, "H cannot steal an active remote's bindings")
	tap(KEY_V)
	tap(KEY_H)
	tap(KEY_ESCAPE)
	check(not mode.active and not mode.overlay.center_marker.visible, "Esc dismisses Strap Mode without changing crane state")

	facility.queue_free()
	await process_frame
	print("RD-015B Strap Mode: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

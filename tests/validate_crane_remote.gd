extends SceneTree

# The headless display cannot capture a pointer. This bypasses only the native capture check.
class HeadlessLocomotion extends OtisLocomotion:
	func input_active() -> bool:
		return actor.controls_enabled

var checks := 0
var failures := 0
var actor: OtisController
var hall: Node3D
var ui: CanvasLayer
var remote: CraneRemote
var crane: BridgeCrane
var facility: Node3D

func _initialize() -> void:
	run.call_deferred()

func check(ok: bool, description: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(description)

func frames(count: int) -> void:
	for frame in count:
		await physics_frame

func key(code: Key, pressed: bool, shift := false) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = pressed
	event.shift_pressed = shift
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func tap(code: Key) -> void:
	key(code, true)
	key(code, false)

func mouse(button: MouseButton, pressed: bool, factor := 1.0, shift := false) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = pressed
	event.factor = factor
	event.shift_pressed = shift
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func face_entry() -> void:
	actor.global_transform = hall.global_transform * Transform3D(Basis.IDENTITY, Vector3(-0.3, 0.04, 4.4))
	actor.velocity = Vector3.ZERO
	actor.camera.rotation = Vector3.ZERO

func run() -> void:
	facility = preload("res://scenes/facility.tscn").instantiate()
	root.add_child(facility)
	current_scene = facility
	actor = facility.get_node("Otis")
	hall = facility.get_node("EngineeringTestHall")
	ui = facility.get_node("InteractionUI")
	crane = facility.overhead_crane
	remote = facility.crane_remote
	if DisplayServer.get_name() == "headless":
		actor.remove_child(actor.locomotion)
		actor.locomotion.free()
		actor.locomotion = HeadlessLocomotion.new()
		actor.add_child(actor.locomotion)
		actor.locomotion.feedback.connect(ui.show_feedback)
	face_entry()
	await frames(16)
	check(is_instance_valid(remote) and remote.crane == crane and remote.state == InteractableObject.State.WORLD,
		"The physical pendant starts paired to the installed crane")
	check(actor.equipment.pick_up(remote).ok and actor.equipment.held_item() == remote,
		"The physical pendant equips through the common handheld slot")
	actor.global_position = hall.to_global(Vector3(0, 0.04, -1.0))
	tap(KEY_V)
	check(not ui.crane_control.active(), "The pendant cannot connect from the Systems Test Chamber")
	face_entry()
	await frames(8)
	tap(KEY_V)
	await frames(2)
	check(ui.crane_control.active() and "CONNECTED" in ui.tool_readout.text,
		"V connects the equipped pendant and shows the crane status")

	var forward := hall.to_local(actor.global_position).z
	var old_x := crane.trolley.position
	var old_z := crane.bridge.position
	var old_pitch := actor.camera.rotation.x
	mouse(MOUSE_BUTTON_LEFT, true)
	mouse(MOUSE_BUTTON_XBUTTON2, true)
	key(KEY_W, true)
	var look := InputEventMouseMotion.new()
	look.relative = Vector2(2, 6)
	Input.parse_input_event(look)
	Input.flush_buffered_events()
	await frames(30)
	key(KEY_W, false)
	mouse(MOUSE_BUTTON_LEFT, false)
	mouse(MOUSE_BUTTON_XBUTTON2, false)
	check(crane.trolley.position > old_x + 0.07 and crane.bridge.position > old_z + 0.07,
		"LMB and the forward Linux side button drive trolley and bridge simultaneously")
	check(hall.to_local(actor.global_position).z < forward - 0.4 and actor.camera.rotation.x < old_pitch,
		"Walking and native camera look continue while the crane is moving")
	tap(KEY_C)
	check(actor.view_camera.third_person and ui.crane_control.active(),
		"Shoulder view works with the remote still connected")
	tap(KEY_C)

	var requested := crane.suspension.target
	var hook_position := crane.suspension.height
	mouse(MOUSE_BUTTON_WHEEL_UP, true)
	check(is_equal_approx(crane.suspension.target, requested + 0.10) and is_equal_approx(crane.suspension.height, hook_position),
		"Wheel up sets a new target without teleporting the hook")
	key(KEY_SHIFT, true)
	mouse(MOUSE_BUTTON_WHEEL_UP, true, 1.0, true)
	key(KEY_SHIFT, false)
	check(is_equal_approx(crane.suspension.target, requested + 0.11), "Shift plus wheel steps the target by 1 cm")
	tap(KEY_PAGEDOWN)
	check(is_equal_approx(crane.suspension.target, requested + 0.01), "Page Down uses the keyboard hoist fallback")
	tap(KEY_PAGEUP)
	await frames(35)
	check(crane.suspension.height > hook_position and is_equal_approx(crane.suspension.target, requested + 0.11),
		"The hoist approaches the target and Page Up raises it")

	old_x = crane.trolley.position
	old_z = crane.bridge.position
	mouse(MOUSE_BUTTON_RIGHT, true)
	mouse(MOUSE_BUTTON_XBUTTON1, true)
	await frames(30)
	mouse(MOUSE_BUTTON_RIGHT, false)
	mouse(MOUSE_BUTTON_XBUTTON1, false)
	check(crane.trolley.position < old_x - 0.07 and crane.bridge.position < old_z - 0.07 and not actor.tool_aiming,
		"RMB and the back Linux side button drive negative travel without aiming")

	old_x = crane.trolley.position
	old_z = crane.bridge.position
	key(KEY_RIGHT, true)
	key(KEY_UP, true)
	await frames(55)
	key(KEY_RIGHT, false)
	key(KEY_UP, false)
	check(crane.trolley.position > old_x + 0.07 and crane.bridge.position > old_z + 0.07,
		"Movement fallback leaves WASD available")

	var replacement := InputEventKey.new()
	replacement.physical_keycode = KEY_H
	InputMap.action_add_event(&"crane_trolley_positive", replacement)
	mouse(MOUSE_BUTTON_LEFT, true)
	key(KEY_H, true)
	mouse(MOUSE_BUTTON_LEFT, false)
	await frames(3)
	check(crane._trolley_demand > 0.0, "Rebound input remains engaged after releasing an alternate binding")
	key(KEY_H, false)
	InputMap.action_erase_event(&"crane_trolley_positive", replacement)
	await frames(3)
	check(is_zero_approx(crane._trolley_demand), "Releasing the final bound button clears its command")

	tap(KEY_E)
	tap(KEY_G)
	check(not ui.e_pending and not ui.menu_open and not actor.placement.is_active() and actor.equipment.held_item() == remote,
		"Connected input leaves context interactions and manipulation idle")
	tap(KEY_V)
	await frames(45)
	check(not ui.crane_control.active() and absf(crane.bridge.velocity) < 0.001 and absf(crane.trolley.velocity) < 0.001,
		"V disconnects and both horizontal axes brake to a stop")
	old_x = crane.trolley.position
	old_z = crane.bridge.position
	await frames(10)
	check(is_equal_approx(crane.trolley.position, old_x) and is_equal_approx(crane.bridge.position, old_z),
		"Disconnected travel holds position")

	tap(KEY_V)
	key(KEY_RIGHT, true)
	tap(KEY_1)
	key(KEY_RIGHT, false)
	check(not ui.crane_control.active() and actor.equipment.container.contains(remote),
		"Stowing the active pendant immediately disconnects it")
	tap(KEY_1)
	check(actor.equipment.held_item() == remote and not ui.crane_control.active(), "Retrieving the pendant leaves it inactive")
	tap(KEY_V)
	tap(KEY_X)
	check(not ui.crane_control.active() and remote.state == InteractableObject.State.WORLD,
		"Dropping the active pendant immediately disconnects it")
	check(actor.equipment.pick_up(remote).ok, "Dropped pendant can be equipped again")
	tap(KEY_V)
	tap(KEY_T)
	check(not ui.crane_control.active() and ui.inventory.active, "Opening the satchel disconnects the pendant")
	tap(KEY_T)

	tap(KEY_V)
	actor.global_position = hall.to_global(Vector3(0, 0.04, -1.0))
	await frames(2)
	check(not ui.crane_control.active() and is_zero_approx(crane._bridge_demand) and is_zero_approx(crane._trolley_demand),
		"Leaving the hall cancels the active link and releases its commands")
	face_entry()
	await frames(4)
	tap(KEY_V)
	ui.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(not ui.crane_control.active(), "Application focus loss disconnects the remote immediately")
	ui.notification(NOTIFICATION_APPLICATION_FOCUS_IN)

	tap(KEY_V)
	var tool := facility.bolt_tool as FasteningTool
	check(actor.equipment.store_world(tool).ok and actor.equipment.equip_item(tool).ok
		and not ui.crane_control.active() and actor.equipped_tool() == tool,
		"Switching directly to the Uni-Bolt returns input ownership to ordinary gameplay")
	var grade := tool.grade_index
	tap(KEY_V)
	mouse(MOUSE_BUTTON_RIGHT, true)
	check(tool.grade_index != grade and actor.tool_aiming and not ui.crane_control.active(),
		"Inactive crane routing preserves the Uni-Bolt grade and aim bindings")
	mouse(MOUSE_BUTTON_RIGHT, false)
	check(not actor.tool_aiming, "RMB release restores the ordinary unaimed state")

	facility.queue_free()
	await process_frame
	print("RD-015A crane remote: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)

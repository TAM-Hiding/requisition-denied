class_name CraneRemoteControls
extends RefCounted
## Owns crane-specific inputs while the pendant has a live connection.

const HORIZONTAL_ACTIONS: Array[StringName] = [
	&"crane_trolley_positive", &"crane_trolley_negative", &"crane_bridge_positive", &"crane_bridge_negative",
]

var remote: CraneRemote
var _crane: BridgeCrane
var _pressed: Dictionary = {}

func held_remote(actor: OtisController) -> CraneRemote:
	if actor.equipment.placing:
		return null
	var item := actor.equipment.held_item() as CraneRemote
	if is_instance_valid(item) and item.equipment_owner == actor.equipment and item.state == InteractableObject.State.HELD:
		return item
	return null

func active() -> bool:
	return is_instance_valid(_crane)

func connect_remote(item: CraneRemote, actor: OtisController) -> bool:
	if not is_instance_valid(item) or item != held_remote(actor) or not item.in_range(actor):
		return false
	remote = item
	_crane = item.crane
	_pressed.clear()
	remote.set_link_status(true)
	return true

func disconnect_remote() -> void:
	if is_instance_valid(_crane):
		_crane.clear_controls()
	if is_instance_valid(remote):
		remote.set_link_status(false)
	remote = null
	_crane = null
	_pressed.clear()

func check_ownership(actor: OtisController) -> void:
	if active() and (not is_instance_valid(remote) or held_remote(actor) != remote or remote.crane != _crane):
		disconnect_remote()

func update(actor: OtisController, context_ready: bool) -> void:
	check_ownership(actor)
	if not active():
		return
	if not context_ready or not remote.in_range(actor):
		disconnect_remote()
		return
	_crane.set_controls(
		axis(&"crane_trolley_negative", &"crane_trolley_positive"),
		axis(&"crane_bridge_negative", &"crane_bridge_positive"),
		precision())

func status_text() -> String:
	return _crane.status_text() if active() else ""

func axis(negative: StringName, positive: StringName) -> float:
	return float(not _pressed.get(positive, {}).is_empty()) - float(not _pressed.get(negative, {}).is_empty())

func precision() -> bool:
	return Input.is_action_pressed(&"crane_precision")

func route(event: InputEvent) -> bool:
	if not active():
		return false
	var prior := false
	var button := input_identity(event)
	if event.is_released() and not button.is_empty():
		# A modifier can be released before the button that used it.
		for action: StringName in _pressed:
			prior = _pressed[action].erase(button) or prior
	for action in HORIZONTAL_ACTIONS:
		if event.is_action(action):
			if event.is_action_pressed(action) and not event.is_echo() and not button.is_empty():
				if not _pressed.has(action):
					_pressed[action] = {}
				_pressed[action][button] = true
			return true
	if event.is_action(&"crane_hook_up") or event.is_action(&"crane_hook_down"):
		if event.is_pressed() and not event.is_echo():
			var direction := float(event.is_action_pressed(&"crane_hook_up")) - float(event.is_action_pressed(&"crane_hook_down"))
			var steps := maxf(1.0, event.factor) if event is InputEventMouseButton else 1.0
			if direction != 0.0:
				_crane.adjust_hook_steps(direction * steps, precision())
		return true
	return prior

func input_identity(event: InputEvent) -> String:
	if event is InputEventMouseButton:
		return "mouse:%d:%d" % [event.device, event.button_index]
	if event is InputEventKey:
		var code: Key = event.physical_keycode if event.physical_keycode != KEY_NONE else event.keycode
		return "key:%d:%d" % [event.device, code]
	if event is InputEventJoypadButton:
		return "pad:%d:%d" % [event.device, event.button_index]
	return ""

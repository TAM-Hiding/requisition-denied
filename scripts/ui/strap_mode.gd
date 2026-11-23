class_name StrapMode
extends RefCounted
## Player rigging inputs. The crane owns the physical attachment and its validation.

const TOGGLE := &"strap_mode_toggle"

var active := false
var overlay: StrapMassOverlay
var hovered: LiftMassProperties.Result
var selected_body: RigidBody3D
var selected_point := Vector3.ZERO
var _actor: OtisController
var _hall: Node3D
var _crane: BridgeCrane
var _mass := LiftMassProperties.new()
var _hit := {}


func configure(actor: OtisController, hall: Node3D) -> void:
	_actor = actor
	_hall = hall
	overlay = StrapMassOverlay.new()
	overlay.name = "StrapMassOverlay"
	hall.add_child(overlay)


func can_enter() -> bool:
	if not is_instance_valid(_hall) or not is_instance_valid(_actor):
		return false
	var at := _hall.to_local(_actor.global_position)
	return absf(at.x) < float(_hall.get("width")) * 0.5 and at.z >= 0.0 and at.z < float(_hall.get("depth"))


func enter() -> bool:
	if not can_enter():
		return false
	_crane = _hall.get_node_or_null("OverheadCrane") as BridgeCrane
	active = is_instance_valid(_crane)
	return active


func leave() -> void:
	active = false
	hovered = null
	_hit.clear()
	if is_instance_valid(overlay):
		overlay.clear_center()
		overlay.clear_strap()


func update(gameplay_ready: bool) -> void:
	if not active:
		return
	if not gameplay_ready or not can_enter() or not is_instance_valid(_crane):
		leave()
		return
	_refresh_hit()
	if hovered == null or not is_instance_valid(hovered.root):
		overlay.clear_center()
	else:
		var center := hovered.world_center()
		if center.is_finite():
			overlay.show_center(center, hovered.confidence)
		else:
			overlay.clear_center()
	if not is_instance_valid(selected_body):
		_clear_selection()
	else:
		overlay.show_strap(selected_body.to_global(selected_point))


func route(event: InputEvent, feedback: Callable) -> bool:
	if not active:
		return false
	if event.is_action_pressed(&"ui_cancel") and not event.is_echo():
		leave()
		return true
	if event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
		if event.pressed:
			_refresh_hit()
			var message := _select_surface() if event.button_index == MOUSE_BUTTON_LEFT else _cancel_or_release()
			feedback.call(message)
		return true
	if event.is_action(&"interact"):
		if event.is_action_pressed(&"interact") and not event.is_echo():
			_refresh_hit()
			feedback.call(_connect())
		return true
	return false


func status_text() -> String:
	var text := "OC-01 / STRAP MODE"
	if is_instance_valid(_crane.rigged_body()):
		text += "\nLOAD CONNECTED  •  Aim at load or hook, RMB to release"
	elif _aiming_at_hook():
		text += "\n[E] Connect selected strap" if is_instance_valid(selected_body) else "\nSelect a load surface with LMB"
	elif is_instance_valid(selected_body):
		text += "\nSTRAP POINT SET  •  Aim at hook, then E"
	else:
		text += "\nLMB Select load surface"
	if hovered != null and is_instance_valid(hovered.root):
		var confidence: String = LiftMassProperties.Confidence.keys()[hovered.confidence]
		var measure := "%.1f kg" % hovered.mass_kg if hovered.mass_kg > 0.0 else "MASS UNKNOWN"
		var membership := " · %d components" % hovered.members.size() if hovered.members.size() > 1 else ""
		text += "\n%s  •  %s%s  •  %s" % [hovered.display_name, measure, membership, confidence]
		if not hovered.is_liftable():
			text += "\nFixed or unavailable for lifting"
	return text


func _refresh_hit() -> void:
	_hit = _actor.target_hit()
	var body := _hit.get("collider") as PhysicsBody3D
	hovered = _mass.resolve(body) if is_instance_valid(body) and not _aiming_at_hook() else null


func _aiming_at_hook() -> bool:
	var hook := _crane.hook_collision_body()
	return is_instance_valid(hook) and _hit.get("collider") == hook


func _select_surface() -> String:
	if is_instance_valid(_crane.rigged_body()):
		return "Release the current load before selecting a strap point."
	if hovered == null or not hovered.is_liftable():
		return "Aim at a movable load surface."
	var member := _hit.get("collider") as RigidBody3D
	var point: Vector3 = _hit.get("position", Vector3.INF)
	if not is_instance_valid(member) or not point.is_finite():
		return "The load surface is unavailable."
	var issue := _crane.rig_candidate(member, point)
	if not issue.is_empty():
		return issue
	selected_body = member
	selected_point = member.to_local(point)
	return "Strap point selected. Aim at the hook and press E to connect."


func _connect() -> String:
	if is_instance_valid(_crane.rigged_body()):
		return "OC-01 already has a load attached."
	if not is_instance_valid(selected_body):
		return "Select a load surface with LMB first."
	if not _aiming_at_hook():
		return "Aim at the hook within reach to connect."
	var issue := _crane.attach_load(selected_body, selected_body.to_global(selected_point))
	if not issue.is_empty():
		return issue
	_clear_selection()
	return "Load connected to OC-01."


func _cancel_or_release() -> String:
	var load_body := _crane.rigged_body()
	if is_instance_valid(load_body):
		if not _aiming_at_hook() and (hovered == null or hovered.root != load_body):
			return "Aim at the attached load or hook within reach."
		var issue := _crane.detach_load()
		return "Rigging released." if issue.is_empty() else issue
	if is_instance_valid(selected_body):
		_clear_selection()
		return "Strap point cleared."
	return "No strap point selected."


func _clear_selection() -> void:
	selected_body = null
	overlay.clear_strap()

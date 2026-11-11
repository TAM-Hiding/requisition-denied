class_name TerminalInteraction
extends Node
## Transfers camera and input ownership without pausing the Facility.
signal active_changed(active: bool)
var active := false
var screen_ui: TerminalDisplay
var camera: Camera3D
var _otis: OtisController
var _target: InteractableObject
var _surface: MeshInstance3D
var _view_anchor: Marker3D
var _display: SubViewport
var _screen_size: Vector2
var _transition: Tween
var _service := InteractionService.new()
var _pointer_inside := false
var _last_pointer := Vector2.ZERO
var _pressed_buttons: Dictionary = {}

func configure(otis: OtisController, target: InteractableObject, session: AdministrativeSession,
		surface: MeshInstance3D, view_anchor: Marker3D, display: SubViewport) -> void:
	_otis = otis
	_target = target
	_surface = surface
	_view_anchor = view_anchor
	_display = display
	_screen_size = (surface.mesh as QuadMesh).size
	camera = Camera3D.new()
	camera.name = "TerminalCamera"
	camera.fov = 44.0
	camera.near = 0.05
	add_child(camera)
	screen_ui = TerminalDisplay.new()
	_display.add_child(screen_ui)
	screen_ui.configure(session, _otis, target.definition.object_id)

func is_target(object: InteractableObject) -> bool:
	return is_instance_valid(object) and object == _target

func enter() -> bool:
	if (active or not _otis.controls_enabled or _otis.placement.is_active()
			or _otis.controls_world_object()):
		return false
	if (not _service.permitted(_otis, _otis.camera, _target, _otis.interaction_distance)
			or not _target.query_actions().has(&"use_terminal")):
		return false
	active = true
	_otis.placement.clear_gesture()
	_otis.controls_enabled = false
	camera.global_transform = _otis.camera.global_transform
	camera.fov = _otis.camera.fov
	camera.make_current()
	screen_ui.set_active(true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_transition = create_tween().set_parallel().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_transition.tween_property(camera, "global_transform", _view_anchor.global_transform, 0.28)
	_transition.tween_property(camera, "fov", 44.0, 0.28)
	active_changed.emit(true)
	return true

func leave() -> void:
	if not active:
		return
	active = false
	if _transition != null:
		_transition.kill()
	if _pointer_inside:
		_display.notify_mouse_exited()
	_pointer_inside = false
	_pressed_buttons.clear()
	screen_ui.set_active(false)
	_otis.camera.make_current()
	_otis.controls_enabled = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	active_changed.emit(false)

func route(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		leave()
	elif event is InputEventKey:
		_display.push_input(event, true)
	elif event is InputEventMouse:
		_route_pointer(event)

func _route_pointer(event: InputEventMouse) -> void:
	var position := _display_position(event.position)
	var inside := Rect2(Vector2.ZERO, Vector2(_display.size)).has_point(position)
	if inside != _pointer_inside:
		if inside:
			_display.notify_mouse_entered()
		else:
			_display.notify_mouse_exited()
		_last_pointer = position
	_pointer_inside = inside
	var forwarded := event.duplicate() as InputEventMouse
	if event is InputEventMouseButton:
		if event.pressed and inside:
			if event.button_index <= MOUSE_BUTTON_MIDDLE:
				_pressed_buttons[event.button_index] = true
		elif not event.pressed and _pressed_buttons.has(event.button_index):
			_pressed_buttons.erase(event.button_index)
		elif not inside:
			return
	elif not inside and _pressed_buttons.is_empty():
		return
	forwarded.position = position
	forwarded.global_position = position
	if forwarded is InputEventMouseMotion:
		forwarded.relative = position - _last_pointer
	_last_pointer = position
	_display.push_input(forwarded, true)

func _display_position(pointer: Vector2) -> Vector2:
	var from := _surface.to_local(camera.project_ray_origin(pointer))
	var direction := _surface.global_basis.inverse() * camera.project_ray_normal(pointer)
	if absf(direction.z) < 0.0001:
		return Vector2(-1, -1)
	var hit := from - direction * from.z / direction.z
	return (Vector2(hit.x, -hit.y) / _screen_size + Vector2(0.5, 0.5)) * Vector2(_display.size)

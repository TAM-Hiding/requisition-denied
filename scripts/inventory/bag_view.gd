class_name BagView
extends SubViewportContainer
signal item_selected(item: InteractableObject)
signal context_requested(item: InteractableObject)
signal dump_requested
@export var tuning: SatchelTuning = preload("res://data/inventory/satchel_tuning.tres")
var container: InventoryContainer
var interior: ContainerInterior
var simulation: SubViewport
var camera: Camera3D
var active := false
var selected: InteractableObject
var cursor := Vector2(-100, -100)
var orbiting := false
var view_yaw := 0.0
var view_tilt := 0.25
var bag_angle := 0.0
var dumping := false
var inversion_time := 0.0
var _rmb_pending := false
var _rmb_consumed := false
var _rmb_elapsed := 0.0
var _press_point := Vector2.ZERO
var _press_hit := {}
var _dragging := false
var _drag_plane_y := 0.0
var _drag_offset := Vector3.ZERO
var _height_offset := 0.0
var _wheel_release_delay := 0.0
var _tilt_poses := {}

func open() -> String:
	if active:
		return ""
	if not is_instance_valid(container) or not container.accessible or container.definition == null:
		return "Container inaccessible."
	if not container.initialize_packing():
		return "Existing contents have no safe arrangement. Grid access remains available."
	simulation = SubViewport.new()
	simulation.size = Vector2i(900, 650)
	simulation.own_world_3d = true
	simulation.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	stretch = true
	add_child(simulation)
	var world := Node3D.new()
	simulation.add_child(world)
	var scene: Node3D = container.definition.physical_interior.instantiate() as Node3D 		if container.definition.physical_interior != null else ContainerInterior.new()
	if not scene is ContainerInterior:
		if scene != null:
			scene.free()
		close()
		return "Container interior scene must provide ContainerInterior."
	interior = scene
	interior.container = container
	world.add_child(interior)
	camera = Camera3D.new()
	world.add_child(camera)
	update_camera()
	camera.fov = 44
	camera.make_current()
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-70, -15, 0)
	light.light_energy = 0.9
	world.add_child(light)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("#162023")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("#a9b8b8")
	environment.environment.ambient_light_energy = 0.6
	world.add_child(environment)
	active = true
	dumping = false
	interior.selected = selected if container.contains(selected) else null
	interior.highlight()
	return ""

func close() -> void:
	cancel_gestures()
	if is_instance_valid(interior) and not dumping:
		restore_bag()
		interior.capture()
	if is_instance_valid(simulation):
		remove_child(simulation)
		simulation.queue_free()
	interior = null
	simulation = null
	camera = null
	_tilt_poses.clear()
	active = false
	dumping = false
	bag_angle = 0
	view_tilt = clampf(view_tilt, 0.08, 0.65)
	inversion_time = 0
	cursor = Vector2(-100, -100)

func update_camera() -> void:
	var envelope := container.definition.packing_dimensions()
	var focus := Vector3(0, envelope.y * 0.35, 0)
	var tilt := clampf(view_tilt, 0.08, 0.65)
	var distance := maxf(envelope.x, envelope.z) * 1.5
	camera.position = focus + Vector3(sin(view_yaw) * sin(tilt), cos(tilt), cos(view_yaw) * sin(tilt)) * distance
	camera.look_at(focus)

func _draw() -> void:
	if active and cursor.x >= 0:
		var color := Color("#dcb66a") if interior.plowing else Color("#75cab9")
		draw_arc(cursor, 7.0, 0, TAU, 24, color, 1.5, true)

func cancel_gestures() -> void:
	release_right(false)
	orbiting = false
	end_drag()

func end_plow() -> void:
	if is_instance_valid(interior):
		interior.end_plow()

func end_drag() -> void:
	_dragging = false
	_wheel_release_delay = 0
	if is_instance_valid(interior):
		interior.end_drag()

func release_right(open_context := true) -> void:
	if _rmb_pending and not _rmb_consumed and open_context and not _press_hit.is_empty():
		var item := _press_hit.get("item") as InteractableObject
		if container.contains(item):
			select(item)
			context_requested.emit(item)
	_rmb_pending = false
	_rmb_consumed = false
	end_plow()

func select(item: InteractableObject) -> void:
	selected = item
	interior.selected = item
	item_selected.emit(item)
	interior.highlight()

func advance_gestures(delta: float) -> void:
	if not active or dumping:
		return
	if _wheel_release_delay > 0 and not _dragging:
		_wheel_release_delay -= delta
		if _wheel_release_delay <= 0:
			interior.end_drag()
	if _rmb_pending and not _rmb_consumed:
		_rmb_elapsed += delta
		if _rmb_elapsed >= tuning.plow_hold_seconds and cursor.distance_to(_press_point) >= tuning.plow_motion_pixels 				and not _press_hit.is_empty():
			_rmb_consumed = true
			end_drag()
			interior.begin_plow(_press_hit.position + _press_hit.normal * 0.028)
			update_pointer_target()
	if orbiting:
		bag_angle = clampf(view_tilt - 0.65, 0.0, PI)
	elif bag_angle > 0:
		bag_angle = move_toward(bag_angle, 0.0, delta * 3.0)
		view_tilt = 0.65 + bag_angle
	update_bag_orientation()
	if opening_direction().dot(Vector3.UP) <= cos(deg_to_rad(tuning.inversion_degrees)):
		inversion_time += delta
		if inversion_time >= tuning.inversion_dwell and not container.items().is_empty():
			dumping = true
			cancel_gestures()
			dump_requested.emit()
	else:
		inversion_time = 0

func _process(delta: float) -> void:
	advance_gestures(delta)

func opening_direction() -> Vector3:
	return Basis(Vector3.RIGHT, -bag_angle) * Vector3.UP

func update_bag_orientation() -> void:
	if bag_angle <= 0.0001:
		restore_bag()
		return
	if _tilt_poses.is_empty():
		cancel_gestures_for_tilt()
		interior.capture()
		for source in interior.proxies:
			var body: RigidBody3D = interior.proxies[source]
			_tilt_poses[source] = body.transform
			body.freeze = true
		interior.set_physics_process(false)
	var focus := Vector3(0, interior.extent.y / 2, 0)
	var rotation := Basis(Vector3.RIGHT, -bag_angle)
	interior.transform = Transform3D(rotation, focus - rotation * focus)

func cancel_gestures_for_tilt() -> void:
	# MMB retains ownership of the turn gesture.
	release_right(false)
	end_drag()

func restore_bag() -> void:
	if not is_instance_valid(interior):
		return
	if not interior.transform.is_equal_approx(Transform3D.IDENTITY):
		interior.transform = Transform3D.IDENTITY
	for source in _tilt_poses:
		if interior.proxies.has(source):
			var body: RigidBody3D = interior.proxies[source]
			body.transform = _tilt_poses[source]
			body.freeze = false
			body.linear_velocity = Vector3.ZERO
			body.angular_velocity = Vector3.ZERO
	_tilt_poses.clear()
	interior.set_physics_process(true)

func update_pointer_target() -> void:
	var origin := camera.project_ray_origin(cursor)
	var direction := camera.project_ray_normal(cursor)
	if _dragging:
		var point: Variant = Plane(Vector3.UP, _drag_plane_y).intersects_ray(origin, direction)
		if point != null:
			interior.drag_goal = point + _drag_offset + Vector3.UP * _height_offset
	elif interior.plowing:
		var point: Variant = Plane(Vector3.UP, interior.plow_plane_y).intersects_ray(origin, direction)
		if point != null:
			interior.plow_goal = point

func _gui_input(event: InputEvent) -> void:
	if not active or dumping:
		return
	if event is InputEventMouseButton:
		cursor = event.position
		queue_redraw()
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			orbiting = event.pressed
			accept_event()
		elif event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and event.pressed:
			var step := tuning.height_step * (1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1)
			if _dragging:
				_height_offset += step
				update_pointer_target()
			elif container.contains(selected):
				if interior.drag_item != selected:
					interior.begin_drag(selected)
				interior.drag_goal.y += step
				_wheel_release_delay = 0.4
			accept_event()
		elif bag_angle > 0.001:
			return
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				end_drag()
				_rmb_pending = true
				_rmb_consumed = false
				_rmb_elapsed = 0
				_press_point = cursor
				_press_hit = interior.pick(camera, cursor)
			else:
				release_right()
			accept_event()
		elif event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				var hit := interior.pick(camera, cursor)
				if not hit.is_empty():
					select(hit.item)
					interior.begin_drag(selected)
					_dragging = true
					_wheel_release_delay = 0
					_height_offset = 0
					_drag_plane_y = hit.position.y
					_drag_offset = interior.proxies[selected].position - hit.position
			else:
				end_drag()
			accept_event()
	elif event is InputEventMouseMotion:
		cursor = event.position
		queue_redraw()
		if orbiting:
			view_yaw += event.relative.x * 0.006
			view_tilt = clampf(view_tilt + event.relative.y * 0.006, 0.08, PI + 0.65)
			update_camera()
		elif bag_angle <= 0.001:
			var hit := interior.pick(camera, cursor)
			interior.hover = hit.get("item")
			update_pointer_target()
			interior.highlight()
		accept_event()

class_name BagView
extends SubViewportContainer
signal item_selected(item: InteractableObject)
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

func open() -> String:
	if active:
		return ""
	if not is_instance_valid(container) or not container.accessible or container.definition == null:
		return "Container inaccessible."
	if not container.initialize_packing():
		return "Existing contents have no safe arrangement. Grid access remains available."
	simulation = SubViewport.new()
	simulation.size = Vector2i(700, 650)
	simulation.own_world_3d = true
	simulation.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	stretch = true
	add_child(simulation)
	var scene: Node3D
	if container.definition.physical_interior != null:
		scene = container.definition.physical_interior.instantiate() as Node3D
	else:
		scene = ContainerInterior.new()
	if not scene is ContainerInterior:
		if scene != null:
			scene.free()
		close()
		return "Container interior scene must provide ContainerInterior."
	interior = scene
	interior.container = container
	simulation.add_child(interior)
	camera = Camera3D.new()
	camera.position = Vector3(0, 1.1, 0.24)
	interior.add_child(camera)
	update_camera()
	camera.fov = 44
	camera.make_current()
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-70, -15, 0)
	light.light_energy = 0.9
	interior.add_child(light)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("#162023")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("#a9b8b8")
	environment.environment.ambient_light_energy = 0.6
	interior.add_child(environment)
	active = true
	interior.selected = selected
	interior.highlight()
	return ""

func close() -> void:
	if is_instance_valid(interior):
		interior.capture()
	if is_instance_valid(simulation):
		remove_child(simulation)
		simulation.queue_free()
	interior = null
	simulation = null
	camera = null
	active = false
	orbiting = false
	cursor = Vector2(-100, -100)

func update_camera() -> void:
	var size := container.definition.insertion_dimensions
	var focus := Vector3(0, size.y * 0.35, 0)
	var distance := maxf(size.x, size.z) * 1.8
	camera.position = focus + Vector3(sin(view_yaw) * sin(view_tilt), cos(view_tilt), cos(view_yaw) * sin(view_tilt)) * distance
	camera.look_at(focus)

func _draw() -> void:
	if active and cursor.x >= 0:
		var color := Color("#dcb66a") if interior.plowing else Color("#75cab9")
		draw_arc(cursor, 7.0, 0, TAU, 24, color, 1.5, true)

func end_plow() -> void:
	if is_instance_valid(interior):
		interior.end_plow()

func _gui_input(event: InputEvent) -> void:
	if not active:
		return
	if event is InputEventMouseButton:
		cursor = event.position
		queue_redraw()
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			orbiting = event.pressed
			accept_event()
		elif event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] and event.pressed:
			camera.fov = clampf(camera.fov + (-3 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 3), 35, 65)
			accept_event()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				var hit := interior.pick(camera, event.position)
				if not hit.is_empty():
					interior.begin_plow(hit.position + hit.normal * 0.028)
			else:
				end_plow()
			accept_event()
		elif event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			var hit := interior.pick(camera, event.position)
			if not hit.is_empty():
				selected = hit.item
				interior.selected = selected
				item_selected.emit(selected)
				interior.highlight()
			accept_event()
	elif event is InputEventMouseMotion:
		cursor = event.position
		queue_redraw()
		if orbiting:
			view_yaw -= event.relative.x * 0.006
			view_tilt = clampf(view_tilt + event.relative.y * 0.004, 0.08, 0.65)
			update_camera()
			accept_event()
			return
		var hit := interior.pick(camera, event.position)
		interior.hover = hit.get("item")
		if interior.plowing:
			var origin := camera.project_ray_origin(event.position)
			var direction := camera.project_ray_normal(event.position)
			var plane := Plane(Vector3.UP, interior.plow_plane_y)
			var point: Variant = plane.intersects_ray(origin, direction)
			if point != null:
				interior.plow_goal = point
		interior.highlight()
		accept_event()

class_name PhysicalLoadSensor
extends InteractableObject
## Samples near-contact supports beneath load-bearing collision shapes.
@export var sensor_id: StringName
@export_range(0.1, 5000.0) var activation_kg := 40.0
@export_range(0.0, 5000.0) var release_kg := 37.0
@export_range(0.0, 10.0) var activation_delay := 0.4
@export var output: EnvironmentalSignal
@export var detection_area: Area3D
@export var support_surface: CollisionObject3D
@export var surface_size := Vector2(2.1, 2.1)
var measured_kg := 0.0
var qualifying_time := 0.0

func _physics_process(delta: float) -> void:
	if not is_instance_valid(detection_area):
		measured_kg = 0.0
		qualifying_time = 0.0
		if is_instance_valid(output):
			output.set_output(false)
		return
	var supports := {}
	measured_kg = 0.0
	for body in detection_area.get_overlapping_bodies():
		var kilograms := load_mass(body)
		if kilograms > 0 and reaches_plate(body, supports):
			measured_kg += kilograms
	if not is_instance_valid(output):
		qualifying_time = 0.0
		return
	if output.is_active():
		if measured_kg < minf(release_kg, activation_kg):
			output.set_output(false)
		qualifying_time = 0.0
	elif measured_kg >= activation_kg:
		qualifying_time += delta
		if qualifying_time >= activation_delay:
			output.set_output(true)
	else:
		qualifying_time = 0.0

func load_mass(body: Node3D) -> float:
	if body is OtisController:
		# The supported load is transmitted through Otis. The frozen carried
		# body contributes nothing independently even if it overlaps the plate.
		return body.supporting_load_kg() if body.is_on_floor() else 0.0
	if body is RigidBody3D and not body.freeze and absf(body.linear_velocity.y) < 0.2:
		return body.mass
	return 0.0

func reaches_plate(body: Node3D, supports: Dictionary) -> bool:
	var visited := {}
	while is_instance_valid(body) and not visited.has(body):
		visited[body] = true
		if body is InteractableObject and body.state == InteractableObject.State.CARRIED:
			body = body.support_carrier
			continue
		if load_mass(body) <= 0.0:
			return false
		if not supports.has(body):
			supports[body] = support_under(body)
		body = supports[body]
		if body == self:
			return true
	return false

func support_under(body: CollisionObject3D) -> Node3D:
	var bounds := AABB()
	var found := false
	for child in body.get_children():
		var collider := child as CollisionShape3D
		if collider == null or collider.disabled or collider.shape == null:
			continue
		var part := collider.global_transform * collider.shape.get_debug_mesh().get_aabb()
		bounds = bounds.merge(part) if found else part
		found = true
	if not found:
		return null
	var center := bounds.get_center()
	center.y = bounds.position.y + 0.04
	var inset := bounds.size * 0.22
	var support: Node3D
	for offset in [Vector3.ZERO, Vector3(inset.x, 0, inset.z), Vector3(-inset.x, 0, inset.z),
			Vector3(inset.x, 0, -inset.z), Vector3(-inset.x, 0, -inset.z)]:
		var start: Vector3 = center + offset
		var query := PhysicsRayQueryParameters3D.create(start, start - Vector3.UP * 0.075, 3)
		query.exclude = [body.get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(query)
		if hit.is_empty() or hit.normal.y < 0.7:
			return null
		var collider: Node3D = hit.collider
		if collider == support_surface:
			var local := to_local(hit.position)
			if absf(local.x) > surface_size.x * 0.5 or absf(local.z) > surface_size.y * 0.5 or absf(local.y) > 0.04:
				return null
			collider = self
		if support != null and support != collider:
			return null
		support = collider
	return support

func is_active() -> bool:
	return is_instance_valid(output) and output.is_active()

func inspection_information() -> Dictionary:
	var info := super.inspection_information()
	info.description += "\nDEVICE: %s\nSTATUS: %s\nCURRENT LOAD: %.1f KG\nACTIVATION THRESHOLD: %.1f KG" % [
		sensor_id, "ACTIVE" if is_active() else "INACTIVE", measured_kg, activation_kg]
	return info

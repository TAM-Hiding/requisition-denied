class_name ContainerInterior
extends Node3D
## Temporary physics representations. The records retain gameplay ownership.
const PLOW_ACCELERATION := 6.0
const PLOW_SPEED := 0.45
var container: InventoryContainer
var proxies: Dictionary = {}
var safe_poses: Dictionary = {}
var walls: Array[Node3D] = []
var pusher: AnimatableBody3D
var plowing := false
var drag_item: InteractableObject
var drag_goal := Vector3.ZERO
var plow_goal := Vector3.ZERO
var plow_plane_y := 0.0
var extent: Vector3
var hover: InteractableObject
var selected: InteractableObject
var _highlight: StandardMaterial3D
var _contact_shape: SphereShape3D

func _ready() -> void:
	extent = container.definition.packing_dimensions()
	_contact_shape = SphereShape3D.new()
	_contact_shape.radius = 0.028
	_highlight = StandardMaterial3D.new()
	_highlight.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_highlight.albedo_color = Color(0.45, 0.85, 0.76, 0.25)
	_highlight.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	make_boundary(Vector3(extent.x + 0.06, 0.03, extent.z + 0.06), Vector3(0, -0.015, 0), true)
	for sign_value in [-1.0, 1.0]:
		make_boundary(Vector3(0.03, extent.y, extent.z + 0.06),
			Vector3(sign_value * (extent.x / 2 + 0.015), extent.y / 2, 0), true)
		make_boundary(Vector3(extent.x, extent.y, 0.03),
			Vector3(0, extent.y / 2, sign_value * (extent.z / 2 + 0.015)), true)
	# A transparent lid keeps the temporary simulation contained.
	make_boundary(Vector3(extent.x + 0.06, 0.03, extent.z + 0.06), Vector3(0, extent.y + 0.015, 0), false)
	for record in container.records():
		make_proxy(record)
	pusher = AnimatableBody3D.new()
	pusher.name = "CursorPlow"
	pusher.sync_to_physics = false
	pusher.collision_layer = 0
	pusher.collision_mask = 1 | 4
	var shape := CollisionShape3D.new()
	shape.shape = SphereShape3D.new()
	shape.shape.radius = 0.022
	pusher.add_child(shape)
	add_child(pusher)
	pusher.position = Vector3(0, extent.y + 1, 0)

func make_boundary(size: Vector3, at: Vector3, visible_shell: bool) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 4 if visible_shell else 8
	body.collision_mask = 1 | 2
	var shape := CollisionShape3D.new()
	shape.shape = BoxShape3D.new()
	shape.shape.size = size
	body.add_child(shape)
	body.position = at
	add_child(body)
	if visible_shell:
		var segments := 3 if size.x > size.z and size.y > 0.05 else 1
		for segment in segments:
			make_wall_panel(size, at, segment, segments)

func make_wall_panel(size: Vector3, at: Vector3, segment: int, segments: int) -> void:
		var wall := MeshInstance3D.new()
		wall.mesh = BoxMesh.new()
		var panel_size := size
		panel_size.x /= segments
		wall.mesh.size = panel_size
		wall.position = at + Vector3((segment - (segments - 1) / 2.0) * panel_size.x, 0, 0)
		wall.set_meta(&"rest_position", wall.position)
		wall.set_meta(&"long_face", segments > 1)
		var material := StandardMaterial3D.new()
		material.albedo_color = Color("#625d46")
		material.roughness = 0.95
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		wall.material_override = material
		add_child(wall)
		walls.append(wall)
		for index in 4:
			var seam := MeshInstance3D.new()
			seam.mesh = BoxMesh.new()
			seam.mesh.size = Vector3(panel_size.x * 0.88, 0.002, 0.002) if size.x > size.z else Vector3(0.002, 0.002, size.z * 0.88)
			seam.position.y = -size.y * 0.4 + index * size.y * 0.25
			seam.material_override = material
			wall.add_child(seam)

func make_proxy(record: InventoryItem) -> void:
	var source := record.body
	var body := RigidBody3D.new()
	body.name = "Packing_" + String(source.definition.object_id)
	body.mass = source.mass
	body.continuous_cd = true
	body.linear_damp = 3.0
	body.angular_damp = 5.0
	body.collision_layer = 1
	body.collision_mask = 1 | 2 | 4 | 8
	body.physics_material_override = PhysicsMaterial.new()
	body.physics_material_override.friction = 0.35
	body.physics_material_override.bounce = 0.0
	add_child(body)
	body.transform = record.internal_pose
	var scale_basis := Basis.from_scale(source.global_basis.get_scale().abs())
	for child in source.get_children():
		if child is CollisionShape3D and not child.disabled and child.shape != null:
			var shape := CollisionShape3D.new()
			shape.shape = child.shape
			shape.transform = Transform3D(scale_basis, Vector3.ZERO) * child.transform
			body.add_child(shape)
		elif child is Node3D and not child is CollisionObject3D:
			var visual := InventoryPreview.copy_visual(child, body)
			visual.transform = Transform3D(scale_basis, Vector3.ZERO) * child.transform
	proxies[source] = body
	safe_poses[source] = record.internal_pose

func pick(camera: Camera3D, point: Vector2) -> Dictionary:
	var start := camera.project_ray_origin(point)
	var direction := camera.project_ray_normal(point)
	var query := PhysicsRayQueryParameters3D.create(start, start + direction * 3.0, 1)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return {}
	for source in proxies:
		if proxies[source] == hit.collider:
			hit.item = source
			return hit
	return {}

func highlight() -> void:
	for source in proxies:
		for mesh in proxies[source].find_children("*", "MeshInstance3D", true, false):
			mesh.material_overlay = _highlight if source == selected or source == hover else null

func begin_plow(at: Vector3) -> void:
	var position_query := PhysicsShapeQueryParameters3D.new()
	position_query.shape = pusher.get_child(0).shape
	position_query.transform = Transform3D(Basis.IDENTITY, at)
	position_query.collision_mask = 1 | 4
	if not get_world_3d().direct_space_state.intersect_shape(position_query, 1).is_empty():
		return
	pusher.position = at
	plow_goal = at
	plow_plane_y = at.y - 0.014
	pusher.collision_layer = 0
	plowing = true

func end_plow() -> void:
	plowing = false
	if is_instance_valid(pusher):
		pusher.collision_layer = 0
		pusher.position = Vector3(0, extent.y + 1, 0)

func begin_drag(item: InteractableObject) -> void:
	end_plow()
	if proxies.has(item):
		drag_item = item
		drag_goal = proxies[item].position
		proxies[item].sleeping = false

func end_drag() -> void:
	drag_item = null

func _physics_process(delta: float) -> void:
	if is_instance_valid(drag_item) and proxies.has(drag_item):
		var body: RigidBody3D = proxies[drag_item]
		var box := ContainerPacking.bounds(InventoryItem.from_body(drag_item), body.transform)
		var relative_min := box.position - body.position
		var relative_max := box.end - body.position
		var low := Vector3(-extent.x / 2, 0, -extent.z / 2) - relative_min + Vector3.ONE * 0.003
		var high := Vector3(extent.x / 2, extent.y, extent.z / 2) - relative_max - Vector3.ONE * 0.003
		drag_goal = drag_goal.clamp(low, high)
		var desired := ((drag_goal - body.position) * 9.0).limit_length(0.45)
		var change := (desired - body.linear_velocity).limit_length(12.0 * delta)
		body.apply_central_impulse((change + Vector3.UP * 9.8 * delta) * body.mass)
	if plowing:
		var radius := 0.025
		var goal := plow_goal.clamp(Vector3(-extent.x / 2 + radius, radius, -extent.z / 2 + radius),
			Vector3(extent.x / 2 - radius, extent.y + 0.04, extent.z / 2 - radius))
		var motion := (goal - pusher.position).limit_length(0.45 * delta)
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = pusher.get_child(0).shape
		query.transform = pusher.global_transform
		query.motion = motion
		query.collision_mask = 1 | 4
		query.margin = 0.002
		var space := get_world_3d().direct_space_state
		var fractions := space.cast_motion(query)
		query.shape = _contact_shape
		query.motion = Vector3.ZERO
		var contact := space.get_rest_info(query)
		if contact.is_empty():
			var sample := query.transform
			sample.origin += motion * minf(1.0, fractions[1] + 0.01)
			query.transform = sample
			query.motion = Vector3.ZERO
			contact = space.get_rest_info(query)
		if not contact.is_empty():
			var body := instance_from_id(contact.collider_id) as RigidBody3D
			if body != null:
				var push := motion
				if contact.normal.y > 0.5:
					push.y = 0.0
				# Bound the requested velocity change and resulting push speed.
				var direction := push.normalized()
				var change := minf(PLOW_ACCELERATION * delta,
					maxf(0.0, PLOW_SPEED - body.linear_velocity.dot(direction)))
				var impulse := direction * body.mass * change
				body.apply_impulse(impulse, contact.point - body.global_position)
			motion -= contact.normal * minf(0.0, motion.dot(contact.normal))
		pusher.position += motion * fractions[0]
	for source in proxies:
		var body: RigidBody3D = proxies[source]
		# Node velocity getters retain the preceding physics-step value.
		# Unconditional writes here would erase an impulse just submitted to
		# PhysicsServer3D before it can affect this step.
		if body.linear_velocity.length_squared() > 0.49:
			body.linear_velocity = body.linear_velocity.limit_length(0.7)
		if body.angular_velocity.length_squared() > 16.0:
			body.angular_velocity = body.angular_velocity.limit_length(4.0)
		var record := InventoryItem.from_body(source)
		var box := ContainerPacking.bounds(record, body.transform)
		# The physical walls are primary. Recover only an invalid escaped pose.
		if ContainerPacking.inside(box, extent, 0.004):
			safe_poses[source] = body.transform
		else:
			body.transform = safe_poses[source]
			body.linear_velocity = Vector3.ZERO
			body.angular_velocity = Vector3.ZERO
	for wall in walls:
		var rest: Vector3 = wall.get_meta(&"rest_position")
		var offset := Vector3.ZERO
		if rest.y > 0:
			for source in proxies:
				var box := ContainerPacking.bounds(InventoryItem.from_body(source), proxies[source].transform)
				var distance := absf(box.position.z - rest.z) if rest.z < -extent.z / 2 else absf(box.end.z - rest.z)
				var local_x := absf(box.get_center().x - rest.x)
				if wall.get_meta(&"long_face", false):
					if distance < 0.04 and local_x < extent.x / 3:
						offset.z = signf(rest.z) * 0.008
				elif absf(rest.x) > extent.x / 2:
					var side_distance := absf(box.position.x - rest.x) if rest.x < 0 else absf(box.end.x - rest.x)
					if side_distance < 0.04:
						offset.x = signf(rest.x) * 0.006
		wall.position = wall.position.lerp(rest + offset, 1 - exp(-7 * delta))

func capture() -> void:
	end_drag()
	end_plow()
	for record in container.records():
		if proxies.has(record.body):
			record.internal_pose = proxies[record.body].transform
			record.packed = true

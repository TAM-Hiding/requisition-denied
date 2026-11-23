class_name CraneRigging
extends Node3D
## Single-point strap between independently simulated bodies. Only separation
## along the strap axis receives an impulse, so slack cannot push a load.

const ATTACHED_META := &"crane_rigged"
const MASS_CENTER_META := &"rig_original_mass_center"

@export var capacity_kg := 50000.0
@export var connect_distance_m := 0.95
@export var initial_slack_m := 0.03
@export var minimum_length_m := 0.18
@export var max_correction_mps := 3.0
@export var max_acceleration_mps2 := 32.0

var load_body: RigidBody3D
var load_mass_kg := 0.0
var length_m := 0.0
var tension_newtons := 0.0
var slack_m := 0.0
## World-space reaction applied to the hook by the latest solve.
var hook_impulse := Vector3.ZERO

var _hook: RigidBody3D
var _hook_local := Vector3.ZERO
var _load_local := Vector3.ZERO
var _original_lock_rotation := false
var _original_center_mode := RigidBody3D.CENTER_OF_MASS_MODE_AUTO
var _original_center := Vector3.ZERO
var _strap: Array[MeshInstance3D] = []


func _ready() -> void:
	var webbing := StandardMaterial3D.new()
	webbing.albedo_color = Color("ce7e29")
	webbing.roughness = 0.94
	var strip := BoxMesh.new()
	strip.size = Vector3(0.054, 1.0, 0.014)
	strip.material = webbing
	for index in 2:
		var segment := MeshInstance3D.new()
		segment.name = "StrapSegment%d" % (index + 1)
		segment.mesh = strip
		segment.hide()
		add_child(segment)
		_strap.append(segment)


func _exit_tree() -> void:
	detach()


func attach(hook: RigidBody3D, hook_world: Vector3, load_target: RigidBody3D, load_world: Vector3,
		load_mass: float, load_center: Variant = null) -> String:
	if is_attached():
		return "OC-01 already has a strap attached."
	if not _available(hook) or not _available(load_target) or hook == load_target:
		return "The hook and a free physical load are required."
	if hook.get_world_3d() != load_target.get_world_3d():
		return "The hook and load must be in the same physics space."
	if load_target.has_meta(ATTACHED_META):
		return "The load already has a lifting strap."
	if not _valid_mass(load_mass):
		return "A known positive load mass within the %.0f kg rated capacity is required." % capacity_kg
	if not hook_world.is_finite() or not load_world.is_finite() or not _valid_center(load_center):
		return "The attachment point or load center is invalid."
	var separation := hook_world.distance_to(load_world)
	if separation > connect_distance_m or load_world.y > hook_world.y + 0.06:
		return "Position the hook within %.2f m above the selected attachment point." % connect_distance_m

	_hook = hook
	_hook.tree_exiting.connect(detach)
	_hook_local = hook.to_local(hook_world)
	length_m = maxf(minimum_length_m, separation + initial_slack_m)
	slack_m = length_m - separation
	_bind_load(load_target, load_world, load_mass, load_center)
	_update_visual(hook_world, load_world)
	return ""


func rebind_load(load_target: RigidBody3D, load_world: Vector3, load_mass: float,
		load_center: Variant = null) -> bool:
	if not is_attached() or not _available(load_target) or load_target == _hook \
			or load_target.get_world_3d() != _hook.get_world_3d() or not _valid_mass(load_mass) \
			or not load_world.is_finite() or not _valid_center(load_center):
		return false
	if load_target != load_body and load_target.has_meta(ATTACHED_META):
		return false

	# After a fastener split, transfer to the selected member only if the
	# same physical point still lies on the original connection.
	var current := load_point()
	var hook_world := hook_point()
	if current.distance_to(load_world) > 0.08 \
			or hook_world.distance_to(load_world) > maxf(length_m, hook_world.distance_to(current)) + 0.04:
		return false
	_unbind_load()
	_bind_load(load_target, load_world, load_mass, load_center)
	return true


func _bind_load(body: RigidBody3D, world_point: Vector3, load_mass: float, load_center: Variant) -> void:
	load_body = body
	load_body.tree_exiting.connect(detach)
	_load_local = body.to_local(world_point)
	_original_lock_rotation = body.lock_rotation
	_original_center_mode = body.center_of_mass_mode
	_original_center = body.center_of_mass
	body.set_meta(MASS_CENTER_META, {"mode": _original_center_mode, "center": _original_center})
	body.set_meta(ATTACHED_META, true)
	body.lock_rotation = false
	update_load_properties(load_mass, load_center)


func update_load_properties(load_mass: float, load_center: Variant = null) -> bool:
	if not is_attached() or not _valid_mass(load_mass) or not _valid_center(load_center):
		return false
	load_mass_kg = load_mass
	if load_center is Vector3 and (load_body.center_of_mass_mode != RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
			or not load_body.center_of_mass.is_equal_approx(load_center)):
		load_body.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
		load_body.center_of_mass = load_center
	return true


func is_attached() -> bool:
	return is_instance_valid(_hook) and is_instance_valid(load_body)


func hook_point() -> Vector3:
	return _hook.to_global(_hook_local) if is_instance_valid(_hook) else Vector3.ZERO


func load_point() -> Vector3:
	return load_body.to_global(_load_local) if is_instance_valid(load_body) else Vector3.ZERO


func detach() -> void:
	if is_instance_valid(_hook) and _hook.tree_exiting.is_connected(detach):
		_hook.tree_exiting.disconnect(detach)
	_unbind_load()
	_hook = null
	length_m = 0.0
	slack_m = 0.0
	tension_newtons = 0.0
	hook_impulse = Vector3.ZERO
	for segment in _strap:
		if is_instance_valid(segment):
			segment.hide()


func _unbind_load() -> void:
	if is_instance_valid(load_body):
		if load_body.tree_exiting.is_connected(detach):
			load_body.tree_exiting.disconnect(detach)
		if _original_center_mode == RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM:
			load_body.center_of_mass = _original_center
		load_body.center_of_mass_mode = _original_center_mode
		load_body.lock_rotation = _original_lock_rotation
		load_body.remove_meta(MASS_CENTER_META)
		load_body.remove_meta(ATTACHED_META)
	load_body = null
	load_mass_kg = 0.0


func step(delta: float, hook_support_axis := Vector3.ZERO, support_speed_mps := 0.0) -> void:
	hook_impulse = Vector3.ZERO
	tension_newtons = 0.0
	if not _available(_hook) or not _available(load_body):
		if _hook != null or load_body != null or length_m > 0.0:
			detach()
		return
	if not is_finite(delta) or delta <= 0.0:
		return
	var hook_state := PhysicsServer3D.body_get_direct_state(_hook.get_rid())
	var load_state := PhysicsServer3D.body_get_direct_state(load_body.get_rid())
	if hook_state == null or load_state == null:
		return

	var start := hook_state.transform * _hook_local
	var finish := load_state.transform * _load_local
	var offset := finish - start
	var separation := offset.length()
	if not start.is_finite() or not finish.is_finite() or not is_finite(separation):
		detach()
		return
	slack_m = maxf(0.0, length_m - separation)
	_update_visual(start, finish)
	if separation < 0.0001:
		return
	var direction := offset / separation
	var hook_arm := start - hook_state.transform * hook_state.center_of_mass_local
	var load_arm := finish - load_state.transform * load_state.center_of_mass_local
	var hook_velocity := hook_state.linear_velocity + hook_state.angular_velocity.cross(hook_arm)
	var load_velocity := load_state.linear_velocity + load_state.angular_velocity.cross(load_arm)

	# A slack strap permits separation up to take-up in this tick. A taut
	# strap subtracts only excess outward velocity and a bounded error term.
	var error := separation - length_m
	var allowed := -minf(max_correction_mps, error * 0.42 / delta) if error > 0.0 else -error / delta
	var excess := (load_velocity - hook_velocity).dot(direction) - allowed
	var inverse_mass := hook_state.inverse_mass + load_state.inverse_mass \
		+ _angular_inverse_mass(_hook, hook_state, hook_arm, direction) \
		+ _angular_inverse_mass(load_body, load_state, load_arm, direction)
	if inverse_mass <= 0.00000001 or not is_finite(excess):
		return
	var magnitude := maxf(0.0, excess / inverse_mass)

	# Couple the line and strap only when the proposed strap impulse requires
	# a tensile line reaction. A slack line leaves the block free; a tensioned
	# line reduces its translational compliance along the shared direction.
	if hook_support_axis.is_finite() and hook_support_axis.length_squared() > 0.5 \
			and is_finite(support_speed_mps):
		var support := hook_support_axis.normalized()
		var cosine := support.dot(direction)
		var reaction_speed := support_speed_mps - hook_state.linear_velocity.dot(support)
		if reaction_speed > magnitude * hook_state.inverse_mass * cosine:
			var supported_mass := maxf(inverse_mass - hook_state.inverse_mass * cosine * cosine, 0.00000001)
			magnitude = maxf(0.0, (excess - reaction_speed * cosine) / supported_mass)

	var limit := (load_mass_kg + _hook.mass) * max_acceleration_mps2 * delta
	magnitude = minf(magnitude, limit)
	if not is_finite(magnitude) or magnitude <= 0.0:
		return

	hook_impulse = direction * magnitude
	tension_newtons = magnitude / delta
	hook_state.apply_impulse(hook_impulse, start - hook_state.transform.origin)
	load_state.apply_impulse(-hook_impulse, finish - load_state.transform.origin)


func _angular_inverse_mass(body: RigidBody3D, state: PhysicsDirectBodyState3D, arm: Vector3,
		axis: Vector3) -> float:
	if body.lock_rotation:
		return 0.0
	var torque_axis := arm.cross(axis)
	# The hook's pitch and roll are locked. Do not count excluded rotations as
	# compliance just because the direct state's inverse tensor is nonzero.
	if body.axis_lock_angular_x:
		torque_axis.x = 0.0
	if body.axis_lock_angular_y:
		torque_axis.y = 0.0
	if body.axis_lock_angular_z:
		torque_axis.z = 0.0
	return maxf(0.0, torque_axis.dot(state.inverse_inertia_tensor * torque_axis))


func _available(body: RigidBody3D) -> bool:
	return is_instance_valid(body) and body.is_inside_tree() and not body.is_queued_for_deletion() 		and not body.freeze and (not body is InteractableObject or body.state == InteractableObject.State.WORLD)


func _valid_mass(kilograms: float) -> bool:
	return is_finite(kilograms) and kilograms > 0.0 and kilograms <= capacity_kg


func _valid_center(center: Variant) -> bool:
	return center == null or (center is Vector3 and center.is_finite())


func _update_visual(start: Vector3, finish: Vector3) -> void:
	if _strap.size() != 2:
		return
	var direction := (finish - start).normalized()
	var sag_axis := Vector3.DOWN.slide(direction)
	if sag_axis.length_squared() < 0.04:
		sag_axis = Vector3.RIGHT.slide(direction)
	var sag := sqrt(maxf(0.0, length_m * length_m - start.distance_squared_to(finish))) * 0.5
	var midpoint := start.lerp(finish, 0.5) + sag_axis.normalized() * sag
	_line(_strap[0], start, midpoint)
	_line(_strap[1], midpoint, finish)


func _line(mesh: MeshInstance3D, start: Vector3, finish: Vector3) -> void:
	var length := start.distance_to(finish)
	mesh.visible = length > 0.001
	if not mesh.visible:
		return
	var up := (finish - start) / length
	var reference := Vector3.FORWARD if absf(up.dot(Vector3.FORWARD)) < 0.92 else Vector3.RIGHT
	var right := reference.cross(up).normalized()
	mesh.global_transform = Transform3D(Basis(right, up * length, right.cross(up)), start.lerp(finish, 0.5))

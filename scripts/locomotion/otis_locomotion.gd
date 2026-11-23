class_name OtisLocomotion
extends Node
## Posture/traversal state owns the character collider; ownership stays in equipment.
signal feedback(message: String)
enum Posture { STANDING, CROUCHING, PRONE }
enum ClimbVariant { SCRAMBLE, MAINTENANCE_HOIST, AWKWARD_RECOVERY }
@export var tuning: LocomotionTuning = preload("res://data/locomotion/wayfarer_movement.tres")
var posture := Posture.STANDING
var sprinting := false
var climbing := false
var climb_variant := -1
var climb_progress := 0.0
var climb_edge := Vector3.ZERO
var climb_rise := 0.0
var climb_random := RandomNumberGenerator.new()
var last_feedback := ""
var local_motion := Vector3.ZERO
var current_speed := 0.0
var load_modifiers := {"ratio": 0.0, "jump": 1.0, "sprint": 1.0, "walk": 1.0, "acceleration": 1.0}
var _alt_pressed_at := -1
var _alt_consumed := false
var _jump_pending := false
var _profiles: Array[Dictionary] = []
var _climb_path: Array[Vector3] = []
var _climb_speed := 0.0
var _climb_distance := 0.0
var _last_variant := -1
var _variant_streak := 0
var _support: PhysicsBody3D
var _support_pose := Transform3D.IDENTITY
@onready var actor := get_parent() as OtisController
@onready var collider := actor.get_node("CollisionShape3D") as CollisionShape3D

func _ready() -> void:
	register_action(&"locomotion_sprint", KEY_SHIFT)
	register_action(&"locomotion_jump", KEY_SPACE)
	register_action(&"locomotion_posture", KEY_ALT)
	for height in [tuning.standing_height, tuning.crouch_height]:
		var shape := CapsuleShape3D.new()
		shape.radius = tuning.upright_radius
		shape.height = height
		_profiles.append({"shape": shape, "pose": Transform3D(Basis.IDENTITY, Vector3(0, height / 2, 0))})
	var prone_shape := BoxShape3D.new()
	# Conservative horizontal footprint includes the existing shoulder/hand
	# reach and messenger satchel; no chassis geometry is resized.
	prone_shape.size = Vector3(tuning.prone_width, tuning.prone_height, tuning.prone_length)
	_profiles.append({"shape": prone_shape,
		"pose": Transform3D(Basis.IDENTITY, Vector3(0, tuning.prone_height / 2, tuning.prone_center_z))})
	apply_profile()

static func register_action(action: StringName, key: Key) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	var event := InputEventKey.new()
	event.physical_keycode = key
	InputMap.action_add_event(action, event)

func input_active() -> bool:
	return actor.controls_enabled and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED

func interaction_restricted() -> bool:
	return actor.placement.is_supported_grab() or actor.placement.is_seating()

func handle_input(event: InputEvent) -> void:
	if not input_active() or not (event is InputEventKey or event is InputEventAction) or event.is_echo():
		return
	if event.is_action_pressed("locomotion_posture"):
		press_posture()
		get_viewport().set_input_as_handled()
	elif event.is_action_released("locomotion_posture"):
		release_posture()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("locomotion_jump"):
		_jump_pending = true
		get_viewport().set_input_as_handled()

func press_posture(now := -1) -> void:
	_alt_pressed_at = Time.get_ticks_usec() if now < 0 else now
	_alt_consumed = false

func advance_posture(now := -1) -> void:
	if now < 0:
		now = Time.get_ticks_usec()
	if _alt_pressed_at >= 0 and not _alt_consumed and now - _alt_pressed_at >= int(tuning.posture_hold_seconds * 1000000):
		_alt_consumed = true
		request_posture(Posture.PRONE)

func release_posture(now := -1) -> void:
	if _alt_pressed_at < 0:
		return
	advance_posture(now)
	if not _alt_consumed:
		request_posture(Posture.CROUCHING if posture != Posture.CROUCHING else Posture.STANDING)
	_alt_pressed_at = -1
	_alt_consumed = false

func report(message: String) -> void:
	last_feedback = message
	feedback.emit(message)

func profile_clear(candidate: Posture, at: Transform3D) -> bool:
	var profile: Dictionary = _profiles[candidate]
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = profile.shape
	query.transform = at * profile.pose
	query.collision_mask = actor.collision_mask
	query.exclude = [actor.get_rid()]
	# Permit a resting floor contact, never clearance through a ceiling.
	query.margin = -0.001
	return actor.get_world_3d().direct_space_state.intersect_shape(query, 1).is_empty()

func request_posture(candidate: Posture) -> bool:
	if climbing:
		report("Finish climbing before changing posture.")
		return false
	if candidate == posture:
		return true
	if not profile_clear(candidate, actor.global_transform):
		report("Not enough clearance to stand." if candidate == Posture.STANDING else "Not enough clearance for that posture.")
		return false
	last_feedback = ""
	posture = candidate
	sprinting = false
	apply_profile()
	return true

func apply_profile() -> void:
	collider.shape = _profiles[posture].shape
	collider.transform = _profiles[posture].pose

func try_turn(angle: float) -> void:
	if posture != Posture.PRONE:
		actor.rotate_y(angle)
		return
	# Short bounded angular samples prevent the longer footprint sweeping
	# through corners. Standing capsules are rotationally symmetric.
	var remaining := clampf(angle, -2.56, 2.56)
	for iteration in 64:
		if absf(remaining) < 0.00001:
			break
		var step := clampf(remaining, -0.04, 0.04)
		var candidate := actor.global_transform
		candidate.basis = Basis(Vector3.UP, step) * candidate.basis
		if not profile_clear(posture, candidate):
			break
		actor.global_basis = candidate.basis
		remaining -= step

func cancel_input() -> void:
	_alt_pressed_at = -1
	_alt_consumed = false
	_jump_pending = false
	sprinting = false
	if climbing:
		cancel_climb("Climb interrupted.")

func request_jump() -> bool:
	if not input_active() or posture == Posture.PRONE or climbing or interaction_restricted():
		report("Cannot jump during this movement or manipulation state.")
		return false
	if posture == Posture.CROUCHING and not request_posture(Posture.STANDING):
		return false
	if try_climb():
		return true
	if not actor.is_on_floor():
		return false
	var height := maxf(0.02, tuning.jump_height * load_modifiers.jump)
	last_feedback = ""
	actor.velocity.y = sqrt(2.0 * maxf(actor.gravity, 0.001) * height)
	return true

func tick(delta: float) -> void:
	var enabled := input_active()
	load_modifiers = LocomotionLoad.modifiers(actor.carrying_loads().total, actor.placement.lift_capacity(),
		tuning.jump_load_factors, tuning.sprint_load_factors)
	if not enabled:
		cancel_input()
	else:
		advance_posture()
	if _jump_pending:
		_jump_pending = false
		request_jump()
	if climbing:
		advance_climb(delta)
		update_camera(delta)
		return
	var axis := Input.get_vector("move_left", "move_right", "move_forward", "move_back") if enabled else Vector2.ZERO
	var can_sprint := posture == Posture.STANDING and not actor.placement.is_active() and not actor.tool_aiming
	sprinting = enabled and can_sprint and Input.is_action_pressed("locomotion_sprint") and axis.y < -0.1
	var base := actor.movement_speed
	current_speed = base * (tuning.sprint_multiplier * load_modifiers.sprint if sprinting else load_modifiers.walk)
	if posture == Posture.CROUCHING:
		current_speed *= tuning.crouch_multiplier
	elif posture == Posture.PRONE:
		current_speed *= tuning.crawl_multiplier
	var direction := actor.global_basis * Vector3(axis.x, 0, axis.y)
	var change: float = actor.acceleration * load_modifiers.acceleration * delta
	if enabled:
		actor.velocity.x = move_toward(actor.velocity.x, direction.x * current_speed, change)
		actor.velocity.z = move_toward(actor.velocity.z, direction.z * current_speed, change)
	else:
		actor.velocity.x = 0
		actor.velocity.z = 0
	if not actor.is_on_floor():
		actor.velocity.y -= actor.gravity * delta
	elif actor.velocity.y <= 0:
		actor.velocity.y = 0
	# CharacterBody3D handles collision and sliding before the contacted bodies
	# receive any impulse. Idle, airborne and dedicated manipulation cannot push.
	var approach := direction * current_speed
	var platform_velocity := actor.get_platform_velocity() if actor.is_on_floor() else Vector3.ZERO
	var can_push := enabled and not axis.is_zero_approx() and not interaction_restricted()
	actor.move_and_slide()
	if actor.is_on_floor():
		ContactPush.apply_weight(actor)
		if can_push:
			ContactPush.apply(actor, approach, delta, platform_velocity)
	local_motion = actor.global_basis.inverse() * Vector3(actor.velocity.x, 0, actor.velocity.z)
	update_camera(delta)

func update_camera(delta: float) -> void:
	var target: Vector3 = [tuning.standing_eye, tuning.crouch_eye, tuning.prone_eye][posture]
	var desired := actor.camera.position.lerp(target, 1.0 - exp(-tuning.camera_response * delta))
	var start := actor.to_global(Vector3(0, minf(0.4, target.y), 0))
	var ray := PhysicsRayQueryParameters3D.create(start, actor.to_global(desired), actor.collision_mask, [actor.get_rid()])
	var hit := actor.get_world_3d().direct_space_state.intersect_ray(ray)
	actor.camera.position = actor.to_local(hit.position + hit.normal * 0.07) if not hit.is_empty() else desired

func ray(from: Vector3, to: Vector3) -> Dictionary:
	return actor.get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(from, to, actor.collision_mask, [actor.get_rid()]))

func stable_support(body: PhysicsBody3D) -> bool:
	return body != null and (not body is RigidBody3D or
		(body.linear_velocity.length() < 0.1 and body.angular_velocity.length() < 0.1))

func sweep_clear(from: Transform3D, motion: Vector3) -> bool:
	var parameters := PhysicsTestMotionParameters3D.new()
	parameters.from = from
	parameters.motion = motion
	parameters.margin = 0.001
	parameters.recovery_as_collision = false
	return not PhysicsServer3D.body_test_motion(actor.get_rid(), parameters)

func ledge_candidate() -> Dictionary:
	if posture == Posture.PRONE or actor.placement.is_active():
		return {}
	var forward := -actor.global_basis.z
	var origin := actor.global_position
	var face := ray(origin + Vector3.UP * 0.3, origin + Vector3.UP * 0.3 + forward * tuning.ledge_reach)
	if face.is_empty() or absf(face.normal.y) > 0.25 or not stable_support(face.collider):
		return {}
	var probe: Vector3 = face.position + forward * (tuning.upright_radius + 0.16)
	var top := ray(Vector3(probe.x, origin.y + tuning.maximum_ledge_rise + 0.05, probe.z),
		Vector3(probe.x, origin.y + tuning.minimum_ledge_rise, probe.z))
	if top.is_empty() or top.normal.y < 0.7 or not stable_support(top.collider):
		return {}
	var destination: Vector3 = top.position + Vector3.UP * 0.025
	var rise: float = top.position.y - origin.y
	if rise < tuning.minimum_ledge_rise or rise > tuning.maximum_ledge_rise:
		return {}
	for offset in [Vector3.ZERO, actor.global_basis.x * 0.24, -actor.global_basis.x * 0.24,
			forward * 0.24, -forward * 0.24]:
		var support := ray(destination + offset + Vector3.UP * 0.06, destination + offset - Vector3.UP * 0.09)
		if support.is_empty() or support.normal.y < 0.7 or absf(support.position.y - top.position.y) > 0.035:
			return {}
	var goal := Transform3D(actor.global_basis, destination)
	var lifted := actor.global_transform
	lifted.origin.y = destination.y + 0.015
	if not profile_clear(Posture.STANDING, goal) or not sweep_clear(actor.global_transform, lifted.origin - origin) \
			or not sweep_clear(lifted, destination - lifted.origin):
		return {}
	var edge := Vector3(face.position.x, top.position.y, face.position.z)
	return {"lifted": lifted.origin, "destination": destination, "support": top.collider,
		"edge": edge + forward * 0.08, "rise": rise}

func _next_climb_variant() -> int:
	var count := ClimbVariant.size()
	# After two repeats, roll only among the other variants.
	var variant := (_last_variant + climb_random.randi_range(1, count - 1)) % count \
		if _variant_streak >= 2 else climb_random.randi_range(0, count - 1)
	_variant_streak = _variant_streak + 1 if variant == _last_variant else 1
	_last_variant = variant
	return variant

func try_climb() -> bool:
	if climbing or posture != Posture.STANDING or not input_active() or actor.placement.is_active():
		return false
	var candidate := ledge_candidate()
	if candidate.is_empty():
		return false
	actor.set_tool_aiming(false)
	_support = candidate.support
	_support_pose = _support.global_transform
	_climb_path.assign([candidate.lifted, candidate.destination])
	_climb_distance = actor.global_position.distance_to(_climb_path[0]) + _climb_path[0].distance_to(_climb_path[1])
	climb_variant = _next_climb_variant()
	climb_progress = 0.0
	climb_edge = candidate.edge
	climb_rise = candidate.rise
	_climb_speed = _climb_distance / tuning.climb_time(climb_variant)
	last_feedback = ""
	climbing = true
	sprinting = false
	actor.velocity = Vector3.ZERO
	return true

func cancel_climb(message := "") -> void:
	climbing = false
	climb_variant = -1
	climb_progress = 0.0
	climb_edge = Vector3.ZERO
	climb_rise = 0.0
	_climb_path.clear()
	_support = null
	actor.velocity = Vector3.ZERO
	last_feedback = message
	if not message.is_empty():
		report(message)

func advance_climb(delta: float) -> void:
	if not is_instance_valid(_support) or not stable_support(_support) \
			or _support.global_transform.origin.distance_to(_support_pose.origin) > tuning.support_motion_tolerance \
			or not _support.global_basis.is_equal_approx(_support_pose.basis):
		cancel_climb("Support moved; climb released.")
		return
	var goal := _climb_path[0]
	var motion := actor.global_position.move_toward(goal, _climb_speed * delta) - actor.global_position
	var collision := actor.move_and_collide(motion, false, 0.001)
	if collision != null:
		cancel_climb("Climb path obstructed.")
		return
	# Key the visual pose to progress along the validated path.
	climb_progress = minf(1.0, climb_progress + motion.length() / _climb_distance)
	if actor.global_position.distance_to(goal) < 0.001:
		_climb_path.pop_front()
		if _climb_path.is_empty():
			cancel_climb()

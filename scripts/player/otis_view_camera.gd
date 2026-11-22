class_name OtisViewCamera
extends Camera3D
## External views are presentation only. The eye camera still owns gameplay rays.
@export var shoulder_offset := Vector3(0.62, 0.36, 2.75)
@export var orbit_distance := 3.34
@export var orbit_speed := 1.8
@export var orbit_wheel_step := PI / 12.0
var third_person := false
var orbiting := false
var orbit_angle := 0.0
var _camera_reach := INF
var _shoulder_yaw := 0.0
var _follow_focus := Vector3.ZERO
var _sphere := SphereShape3D.new()
@onready var actor := get_parent() as OtisController
@onready var rig := actor.get_node("ICF01_Wayfarer") as WayfarerRig

func _ready() -> void:
	top_level = true
	near = actor.camera.near
	cull_mask = actor.camera.cull_mask & ~WayfarerRig.FIRST_PERSON_ITEM
	_sphere.radius = 0.16
	OtisLocomotion.register_action(&"camera_gameplay", KEY_C)
	OtisLocomotion.register_action(&"camera_orbit", KEY_K)
	OtisLocomotion.register_action(&"camera_orbit_left", KEY_Q)
	OtisLocomotion.register_action(&"camera_orbit_right", KEY_E)

func route(event: InputEvent) -> bool:
	if not actor.locomotion.input_active():
		return false
	if event.is_action_pressed(&"camera_orbit"):
		set_orbiting(not orbiting)
		return true
	if event.is_action_pressed(&"camera_gameplay"):
		if not orbiting:
			third_person = not third_person
			restore_view()
		return true
	if not orbiting:
		return false
	if event.is_action(&"camera_orbit_left") or event.is_action(&"camera_orbit_right"):
		return true
	if event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
		if event.pressed:
			var step := 1.0 if event.button_index == MOUSE_BUTTON_WHEEL_LEFT else -1.0
			rotate_orbit(step * orbit_wheel_step)
		return true
	return false

func rotate_orbit(angle: float) -> void:
	orbit_angle = wrapf(orbit_angle + angle, -PI, PI)

func set_orbiting(active: bool) -> void:
	if active and not orbiting:
		orbit_angle = actor.global_rotation.y + atan2(1.35, -3.05)
	orbiting = active
	restore_view()

func restore_view() -> void:
	rig.visible = orbiting or third_person
	if rig.visible:
		_camera_reach = INF
		_shoulder_yaw = actor.global_rotation.y
		_follow_focus = posture_focus()
		global_transform = actor.camera.global_transform
		make_current()
	else:
		rig.clear_display_item()
		actor.camera.make_current()

func tick(delta: float) -> void:
	if not is_current():
		return
	if orbiting and actor.locomotion.input_active():
		rotate_orbit(Input.get_axis(&"camera_orbit_right", &"camera_orbit_left") * orbit_speed * delta)
	var focus := posture_focus()
	var follow_weight := 1.0 - exp(-18.0 * delta)
	var desired: Vector3
	var target := focus
	if orbiting:
		desired = focus + Vector3(0, 0.51, orbit_distance).rotated(Vector3.UP, orbit_angle)
		fov = 46.0
	else:
		_shoulder_yaw = lerp_angle(_shoulder_yaw, actor.global_rotation.y, follow_weight)
		_follow_focus = _follow_focus.lerp(focus, follow_weight)
		desired = _follow_focus + shoulder_offset.rotated(Vector3.UP, _shoulder_yaw)
		var eye := actor.camera.global_position
		var direction := -actor.camera.global_basis.z
		var hit := actor.target_hit()
		target = hit.get("position", eye + direction * actor.interaction_distance)
		fov = actor.camera.fov
	global_position = safe_position(focus, desired, delta)
	# The rig would fill the near plane when a wall squeezes the camera
	# directly against Otis. Restore its visibility as soon as space opens.
	rig.visible = _camera_reach >= 0.60
	if not rig.visible:
		rig.clear_display_item()
	if global_position.distance_squared_to(target) > 0.0001:
		var direction := global_position.direction_to(target)
		look_at(target, Vector3.FORWARD if absf(direction.y) > 0.999 else Vector3.UP)

func posture_focus() -> Vector3:
	var height: float = [0.96, 0.65, 0.35][actor.locomotion.posture]
	return actor.to_global(Vector3(0, height, 0))

func safe_position(focus: Vector3, desired: Vector3, delta: float) -> Vector3:
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _sphere
	query.transform.origin = focus
	query.collision_mask = actor.collision_mask
	query.exclude = [actor.get_rid()]
	var space := actor.get_world_3d().direct_space_state
	# A sweep ignores existing overlaps. Fall back to the verified eye position
	# if the shoulder/orbit pivot starts against new geometry.
	if not space.intersect_shape(query, 1).is_empty():
		_camera_reach = 0.0
		return actor.camera.global_position
	query.motion = desired - focus
	var fractions := space.cast_motion(query)
	var limit := query.motion.length() * fractions[0]
	_camera_reach = minf(limit, lerpf(_camera_reach, limit, 1.0 - exp(-12.0 * delta))) if is_finite(_camera_reach) else limit
	return focus + query.motion.normalized() * _camera_reach

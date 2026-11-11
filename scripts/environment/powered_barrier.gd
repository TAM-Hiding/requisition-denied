class_name PoweredBarrier
extends AnimatableBody3D

signal state_changed(state: State)
enum State { CLOSED, OPENING, OPEN, CLOSING, BLOCKED }
const MOTION_MARGIN := 0.002
const MAX_SUPPORTED_BODIES := 4
@export var barrier_id: StringName
@export var barrier_type: StringName = &"sliding"
@export var material_id: StringName = &"steel"
@export var closed_position: Vector3
@export var open_position: Vector3
@export_range(0.01, 20.0) var movement_duration := 1.5
@export var starts_open := false
var state := State.CLOSED
var _wants_open := false
var _received_request := false

func _ready() -> void:
	sync_to_physics = false
	position = open_position if starts_open else closed_position
	if not _received_request:
		_wants_open = starts_open
	state = State.OPEN if starts_open else State.CLOSED

func request_open(active: bool) -> void:
	_received_request = true
	_wants_open = active

func _physics_process(delta: float) -> void:
	var target := open_position if _wants_open else closed_position
	var next := position.move_toward(target, closed_position.distance_to(open_position) * delta / maxf(movement_duration, 0.01))
	var motion := next - position
	if motion.length_squared() > 0.0:
		var parent_3d := get_parent_node_3d()
		var world_motion := parent_3d.global_basis * motion if parent_3d != null else motion
		if not _can_travel(world_motion):
			_set_state(State.BLOCKED)
			return
		position = next
	if position.is_equal_approx(target):
		_set_state(State.OPEN if _wants_open else State.CLOSED)
	else:
		_set_state(State.OPENING if _wants_open else State.CLOSING)

func _can_travel(motion: Vector3) -> bool:
	var parameters := PhysicsTestMotionParameters3D.new()
	parameters.from = global_transform
	parameters.motion = motion
	parameters.margin = MOTION_MARGIN
	# Report hits in the swept direction. Resting or tangential recovery alone
	# should not stop travel away from or alongside a contact.
	var can_carry := motion.normalized().dot(Vector3.UP) >= 0.95
	var supported: Array[RigidBody3D] = []
	var excluded: Array[RID] = []
	var collision := PhysicsTestMotionResult3D.new()
	for attempt in MAX_SUPPORTED_BODIES + 1:
		parameters.exclude_bodies = excluded
		if not PhysicsServer3D.body_test_motion(get_rid(), parameters, collision):
			for load in supported:
				load.sleeping = false
			return true
		var load := collision.get_collider() as RigidBody3D
		if (attempt == MAX_SUPPORTED_BODIES or load == null or load.freeze
				or not can_carry
				or collision.get_collision_normal().dot(Vector3.DOWN) < 0.95
				or not _can_lift(load, motion)):
			return false
		# Skip this load for the gate's query only. Its real collision stays
		# enabled so the rising surface carries it through the physics solver.
		supported.append(load)
		excluded.append(load.get_rid())
	return false

func _can_lift(load: RigidBody3D, motion: Vector3) -> bool:
	var parameters := PhysicsTestMotionParameters3D.new()
	parameters.from = load.global_transform
	parameters.motion = motion
	parameters.margin = MOTION_MARGIN
	parameters.exclude_bodies = [get_rid()]
	return not PhysicsServer3D.body_test_motion(load.get_rid(), parameters)

func _set_state(value: State) -> void:
	if state != value:
		state = value
		state_changed.emit(state)

func state_name() -> String:
	return State.keys()[state]

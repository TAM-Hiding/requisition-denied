class_name PoweredBarrier
extends AnimatableBody3D

signal state_changed(state: State)
enum State { CLOSED, OPENING, OPEN, CLOSING, BLOCKED }
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
		var parameters := PhysicsTestMotionParameters3D.new()
		parameters.from = global_transform
		var parent_3d := get_parent_node_3d()
		parameters.motion = parent_3d.global_basis * motion if parent_3d != null else motion
		parameters.margin = 0.002
		parameters.recovery_as_collision = true
		if PhysicsServer3D.body_test_motion(get_rid(), parameters):
			_set_state(State.BLOCKED)
			return
		position = next
	if position.is_equal_approx(target):
		_set_state(State.OPEN if _wants_open else State.CLOSED)
	else:
		_set_state(State.OPENING if _wants_open else State.CLOSING)

func _set_state(value: State) -> void:
	if state != value:
		state = value
		state_changed.emit(state)

func state_name() -> String:
	return State.keys()[state]

class_name PrecisionPlacement
extends Node
## Equipment owns the item throughout. This controller only drives its pose.
@export_range(0.05, 2.0) var hold_seconds := 0.35
@export var minimum_distance := 0.45
@export var maximum_distance := 3.0
@export var initial_distance := 1.35
@export var wheel_step := 0.15
@export var follow_speed := 20.0
@export var rotation_speed := 0.009
const AXES := [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
const AXIS_NAMES := ["X", "Y", "Z"]

var distance := 1.35
var axis := 0
var rotating := false
var valid := false
var _pressed_at := -1
var _hold_consumed := false
var _angle := 0.0
var _clearance: PlacementClearance
@onready var actor: OtisController = get_parent() as OtisController

func is_active() -> bool:
	return actor.equipment.placing

func press_drop(now: int = -1) -> void:
	_pressed_at = Time.get_ticks_usec() if now < 0 else now
	_hold_consumed = false

func advance_drop(now: int = -1) -> void:
	if now < 0:
		now = Time.get_ticks_usec()
	if _pressed_at < 0 or _hold_consumed or now - _pressed_at < roundi(hold_seconds * 1000000.0):
		return
	_hold_consumed = true
	if not is_active():
		begin()

func release_drop(now: int = -1) -> void:
	if _pressed_at < 0:
		return
	advance_drop(now)
	var tapped := not _hold_consumed
	clear_gesture()
	if tapped:
		if is_active():
			confirm()
		else:
			actor.equipment.drop()

func clear_gesture() -> void:
	_pressed_at = -1
	_hold_consumed = false

func begin() -> bool:
	var item := actor.equipment.held_item()
	if item == null or is_active() or actor.manipulation.moving_object() != null:
		return false
	var clearance := PlacementClearance.new()
	if not clearance.configure(item) or not clearance.clear(item.global_transform, 1):
		actor.equipment.result(false, "Move to clear space before placing.")
		return false
	if not actor.equipment.begin_placement():
		return false
	_clearance = clearance
	distance = clampf(initial_distance, minimum_distance, maximum_distance)
	axis = 0
	rotating = false
	_angle = 0
	valid = false
	return true

func cancel() -> void:
	clear_gesture()
	rotating = false
	_angle = 0.0
	valid = false
	if is_active():
		actor.equipment.cancel_placement()
	_clearance = null

func cycle_axis() -> void:
	axis = (axis + 1) % AXES.size()
	_angle = 0

func adjust_distance(steps: float) -> void:
	distance = clampf(distance + steps * wheel_step, minimum_distance, maximum_distance)

func rotate_from_mouse(horizontal: float) -> void:
	_angle = clampf(_angle + horizontal * rotation_speed, -PI, PI)

func _physics_process(delta: float) -> void:
	if is_active():
		update_preview(delta)

func target_position() -> Vector3:
	return actor.camera.global_position - actor.camera.global_basis.z * distance

func update_preview(delta: float) -> void:
	var item := actor.equipment.held_item()
	var pose := item.global_transform
	var displacement := (target_position() - pose.origin) * (1.0 - exp(-follow_speed * delta))
	# Let a preview that Otis has walked into escape along a clear world route.
	# The displayed pose still has to clear Otis before it can be released.
	var mask := 3 if _clearance.clear(pose) else 1
	pose = _clearance.slide(pose, displacement, mask)
	if mask == 3 and not rotating and is_zero_approx(_angle):
		pose = _clearance.accommodate_contact(pose, displacement)
	for increment in 8:
		if is_zero_approx(_angle):
			break
		var step := clampf(_angle, -0.035, 0.035)
		_angle -= step
		var candidate := pose
		var orientation := pose.basis.orthonormalized() * Basis(AXES[axis], step)
		candidate.basis = orientation.orthonormalized() * Basis.from_scale(pose.basis.get_scale())
		if not _clearance.rotation_clear(pose, candidate, step):
			_angle = 0
			break
		pose = candidate
	item.global_transform = pose
	valid = _clearance.clear(pose)

func confirm() -> bool:
	var item := actor.equipment.held_item()
	if not is_active() or item == null:
		return false
	# Recheck current geometry at the input event, including moving barriers.
	if not _clearance.clear(item.global_transform):
		valid = false
		actor.equipment.result(false, "Placement blocked.")
		return false
	actor.equipment.finish_placement(item.global_transform)
	rotating = false
	_clearance = null
	valid = false
	return true

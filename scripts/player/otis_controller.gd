class_name OtisController
extends CharacterBody3D
@export var movement_speed: float = 4.0
@export var acceleration: float = 18.0
@export var mouse_sensitivity: float = 0.0025
@export var camera_fov: float = 75.0
@export var interaction_distance: float = 3.0
@export var gravity: float = 9.8
@export var interact_hold_threshold: float = 0.35
var equipment: EquipmentController
var manipulation: EnvironmentalManipulation
var knowledge := PlayerKnowledge.new()
var controls_enabled: bool = true
@onready var camera: Camera3D = $Camera3D

func _ready() -> void:
	camera.fov = camera_fov
	equipment = EquipmentController.new()
	equipment.name = "Equipment"
	add_child(equipment)
	manipulation = EnvironmentalManipulation.new()
	manipulation.name = "EnvironmentalManipulation"
	add_child(manipulation)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and controls_enabled and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		camera.rotation.x = clampf(camera.rotation.x - event.relative.y * mouse_sensitivity, -1.5, 1.5)

func _physics_process(delta: float) -> void:
	if manipulation.can_process():
		manipulation.prepare_movement()
	var speed := manipulation.effective_speed(movement_speed)
	var movement_acceleration := manipulation.effective_acceleration(acceleration)
	var direction := Vector3.ZERO
	if controls_enabled and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var axis := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		direction = global_basis * Vector3(axis.x, 0, axis.y)
	if not controls_enabled or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		velocity.x = 0
		velocity.z = 0
	else:
		velocity.x = move_toward(velocity.x, direction.x * speed, movement_acceleration * delta)
		velocity.z = move_toward(velocity.z, direction.z * speed, movement_acceleration * delta)
	if not is_on_floor():
		velocity.y -= gravity * delta
	else:
		velocity.y = 0
	velocity = manipulation.constrain_velocity(velocity, delta)
	move_and_slide()
	if manipulation.can_process():
		manipulation.update_goal()

func target_hit() -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(camera.global_position,
		camera.global_position - camera.global_basis.z * interaction_distance, 1)
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query)

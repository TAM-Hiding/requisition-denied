class_name OtisController
extends CharacterBody3D
var chassis := AndroidChassis.new()
var body_mass_kg: float:
	get: return chassis.effective(AndroidChassis.Attribute.MASS_KG)
var movement_speed: float:
	get: return chassis.effective(AndroidChassis.Attribute.WALK_MPS)
var acceleration: float:
	get: return chassis.effective(AndroidChassis.Attribute.ACCELERATION_MPS2)
@export var mouse_sensitivity: float = 0.0025
@export var camera_fov: float = 75.0
@export var interaction_distance: float = 3.0
@export var gravity: float = 9.8
@export var interact_hold_threshold: float = 0.35
var equipment: EquipmentController
var manipulation: EnvironmentalManipulation
var carry: LargeObjectCarry
var knowledge := PlayerKnowledge.new()
var controls_enabled: bool = true
@onready var placement: PrecisionPlacement = $PrecisionPlacement
@onready var camera: Camera3D = $Camera3D

func _ready() -> void:
	camera.fov = camera_fov
	equipment = EquipmentController.new()
	equipment.name = "Equipment"
	add_child(equipment)
	manipulation = EnvironmentalManipulation.new()
	manipulation.name = "EnvironmentalManipulation"
	add_child(manipulation)
	manipulation.equipment_pose_requested.connect(equipment.presentation.request_pose)
	carry = LargeObjectCarry.new()
	carry.name = "LargeObjectCarry"
	add_child(carry)

func supporting_load_kg() -> float:
	return body_mass_kg + carry.load_kg()

func controls_world_object() -> bool:
	return manipulation.moving_object() != null or is_instance_valid(carry.item)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and controls_enabled and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if placement.is_active() and placement.rotating:
			placement.rotate_from_mouse(event.relative.x)
			return
		rotate_y(-event.relative.x * mouse_sensitivity)
		camera.rotation.x = clampf(camera.rotation.x - event.relative.y * mouse_sensitivity, -1.5, 1.5)

func _physics_process(delta: float) -> void:
	if manipulation.can_process():
		manipulation.prepare_movement()
	var speed := manipulation.effective_speed(movement_speed) * carry.speed_factor()
	var movement_acceleration := manipulation.effective_acceleration(acceleration) * carry.acceleration_factor()
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
	velocity = carry.constrain_velocity(velocity, delta)
	move_and_slide()
	carry.update_goal(delta)
	if manipulation.can_process():
		manipulation.update_goal()

func target_hit() -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(camera.global_position,
		camera.global_position - camera.global_basis.z * interaction_distance, 5)
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query)

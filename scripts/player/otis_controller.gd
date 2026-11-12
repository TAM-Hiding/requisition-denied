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
var knowledge := PlayerKnowledge.new()
var controls_enabled: bool = true
@onready var placement: PrecisionPlacement = $PrecisionPlacement
@onready var camera: Camera3D = $Camera3D

func _ready() -> void:
	camera.fov = camera_fov
	equipment = EquipmentController.new()
	equipment.name = "Equipment"
	add_child(equipment)

func supporting_load_kg() -> float:
	return body_mass_kg + placement.suspended_mass_kg()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and controls_enabled and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if placement.is_active() and placement.rotating:
			placement.rotate_from_mouse(event.relative.x)
			return
		rotate_y(-event.relative.x * mouse_sensitivity)
		camera.rotation.x = clampf(camera.rotation.x - event.relative.y * mouse_sensitivity, -1.5, 1.5)

func _physics_process(delta: float) -> void:
	var speed := movement_speed * (1.0 - 0.25 * placement.load_fraction())
	var movement_acceleration := acceleration * (1.0 - 0.30 * placement.load_fraction())
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
	move_and_slide()

func target_hit() -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(camera.global_position,
		camera.global_position - camera.global_basis.z * interaction_distance, 5)
	query.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(query)

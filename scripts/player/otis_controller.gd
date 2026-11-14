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
@export var tool_aim_fov: float = 57.0
@export var tool_aim_sensitivity: float = 0.75
var tool_aiming := false
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
			placement.rotate_from_mouse(event.relative)
			get_viewport().set_input_as_handled()
			return
		var sensitivity := mouse_sensitivity * (tool_aim_sensitivity if tool_aiming else 1.0)
		rotate_y(-event.relative.x * sensitivity)
		camera.rotation.x = clampf(camera.rotation.x - event.relative.y * sensitivity, -1.5, 1.5)

func equipped_tool() -> FasteningTool:
	return equipment.held_item() as FasteningTool if not equipment.placing else null

func set_tool_aiming(active: bool) -> void:
	var was_aiming := tool_aiming
	tool_aiming = active and equipped_tool() != null
	equipment.presentation.aim_requested = tool_aiming
	if tool_aiming:
		placement.set_rotating(false)
		placement.pin_workpiece()
	elif was_aiming:
		placement.resume_workpiece()

func _physics_process(delta: float) -> void:
	if tool_aiming and (equipped_tool() == null or not controls_enabled or placement.input_suspended):
		set_tool_aiming(false)
	camera.fov = move_toward(camera.fov, tool_aim_fov if tool_aiming else camera_fov, delta * 100.0)
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
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty() and hit.collider is PhysicsBody3D:
		hit.collider = FasteningSystem.logical_body(hit.collider, hit.shape)
	return hit

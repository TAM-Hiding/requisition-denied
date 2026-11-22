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
var locomotion: OtisLocomotion
var view_camera: OtisViewCamera
var knowledge := PlayerKnowledge.new()
var controls_enabled: bool = true
@onready var placement: PrecisionPlacement = $PrecisionPlacement
@onready var camera: Camera3D = $Camera3D

func _ready() -> void:
	camera.fov = camera_fov
	equipment = EquipmentController.new()
	equipment.name = "Equipment"
	add_child(equipment)
	locomotion = OtisLocomotion.new()
	locomotion.name = "Locomotion"
	add_child(locomotion)
	view_camera = OtisViewCamera.new()
	view_camera.name = "ExternalCamera"
	add_child(view_camera)

func supporting_load_kg() -> float:
	return body_mass_kg + carrying_loads().total

func carrying_loads() -> Dictionary:
	var stored := equipment.inventory_mass_kg() if equipment != null else 0.0
	var equipped := equipment.equipped_mass_kg() if equipment != null else 0.0
	# Placement of owned equipment already counts in equipped load.
	var external := placement.suspended_mass_kg() if placement.is_grabbing() else 0.0
	return {"inventory": stored, "equipped": equipped, "external": external,
		"dragged": 0.0, "total": stored + equipped + external}

func _unhandled_input(event: InputEvent) -> void:
	if view_camera.route(event):
		get_viewport().set_input_as_handled()
		return
	locomotion.handle_input(event)
	if event is InputEventMouseMotion and locomotion.input_active():
		if placement.is_active() and placement.rotating:
			placement.rotate_from_mouse(event.relative)
			get_viewport().set_input_as_handled()
			return
		var sensitivity := mouse_sensitivity * (tool_aim_sensitivity if tool_aiming else 1.0)
		locomotion.try_turn(-event.relative.x * sensitivity)
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
	locomotion.tick(delta)
	view_camera.tick(delta)

func target_hit() -> Dictionary:
	var query := PhysicsRayQueryParameters3D.create(camera.global_position,
		camera.global_position - camera.global_basis.z * interaction_distance, 5)
	query.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty() and hit.collider is PhysicsBody3D:
		hit.collider = FasteningSystem.logical_body(hit.collider, hit.shape)
	return hit

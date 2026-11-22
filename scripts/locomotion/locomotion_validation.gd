extends Node3D
## Optional compact development fixture. Never loaded by the Facility main scene.
var status: Label
@onready var actor := $Otis as OtisController

func _ready() -> void:
	block("Floor", Vector3(11, 0.3, 10), Vector3(0, -0.15, 0), Color("343f46"))
	block("LowLedge", Vector3(2.0, 0.65, 1.6), Vector3(-3, 0.325, -2.6), Color("697579"))
	block("StandingLedge", Vector3(2, 1.3, 1.6), Vector3(0, 0.65, -2.6), Color("697579"))
	block("JumpLedge", Vector3(2, 1.8, 1.6), Vector3(3, 0.9, -2.6), Color("697579"))
	block("CrouchRoof", Vector3(3, 0.2, 1.7), Vector3(-2.1, 1.6, 1.5), Color("8a8052"))
	block("CrawlRoof", Vector3(3, 0.2, 2.2), Vector3(2.1, 1.04, 1.5), Color("8a8052"))
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-65, -25, 0)
	light.light_energy = 1.5
	add_child(light)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("27343c")
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("a8bec8")
	environment.environment.ambient_light_energy = 0.65
	add_child(environment)
	var canvas := CanvasLayer.new()
	add_child(canvas)
	status = Label.new()
	status.position = Vector2(24, 20)
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas.add_child(status)
	actor.locomotion.feedback.connect(func(message: String) -> void: print("TRAVERSAL ", message))
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func block(title: String, size: Vector3, at: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.name = title
	var collision := CollisionShape3D.new()
	collision.shape = BoxShape3D.new()
	collision.shape.size = size
	body.add_child(collision)
	var mesh := MeshInstance3D.new()
	mesh.mesh = BoxMesh.new()
	mesh.mesh.size = size
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh.material_override = material
	body.add_child(mesh)
	body.position = at
	add_child(body)
	if title != "Floor":
		var label := Label3D.new()
		label.text = title
		label.position = at + Vector3(0, size.y / 2 + 0.2, 0)
		label.font_size = 32
		add_child(label)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _process(_delta: float) -> void:
	status.text = "RD-013 / COMPACT LOCOMOTION VALIDATION\nWASD · Shift+W sprint · Space jump/climb · Alt tap crouch / hold crawl · C shoulder · K orbit (Q/E) · Esc cursor\n%s · sprint %s · climb %s · speed %.2f m/s · load %.0f%%\n%s" % [
		OtisLocomotion.Posture.keys()[actor.locomotion.posture], actor.locomotion.sprinting,
		actor.locomotion.climbing, actor.velocity.length(), actor.locomotion.load_modifiers.ratio * 100,
		actor.locomotion.last_feedback]

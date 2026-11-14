class_name FasteningTool
extends InteractableObject

const CAPACITY := 20
const RANGE := 3.0
const REAR_SIGHT_TIP := Vector3(0, 0.105, 0.115)
const GRADES: Array[FastenerGrade] = [
	preload("res://data/fasteners/standard.tres"),
	preload("res://data/fasteners/grade_8.tres"),
	preload("res://data/fasteners/megabolt.tres"),
]
var system: FasteningSystem
var removing := false:
	set(value):
		removing = value
		if indicator != null:
			var color := Color("e4b968") if value else Color("83d6a8")
			indicator.albedo_color = color
			indicator.emission = color
var removal_behavior := "Timed"
var removal_seconds := 5.0
var removal_remaining := 0.0

func configure_removal(behavior: String, seconds: float) -> void:
	if behavior != removal_behavior:
		removing = false
		removal_remaining = 0.0
	removal_behavior = behavior
	removal_seconds = seconds
	removal_remaining = minf(removal_remaining, seconds)

func removal_input(pressed: bool) -> void:
	if removal_behavior == "Hold":
		removing = pressed
	elif pressed and removal_behavior == "Toggle":
		removing = not removing
	elif pressed:
		removing = true
		removal_remaining = removal_seconds

func update_removal(delta: float, input_allowed: bool) -> void:
	if not input_allowed:
		if removal_behavior == "Hold":
			removing = false
		return
	if removing and removal_behavior == "Timed":
		removal_remaining = maxf(0.0, removal_remaining - delta)
		if is_zero_approx(removal_remaining):
			removing = false

var grade_index := 0
var rounds: Array[InstalledFastener] = []
var recovered: Array[InstalledFastener] = []
var indicator: StandardMaterial3D

func load_grade(index: int) -> void:
	recovered.append_array(rounds)
	rounds.clear()
	grade_index = posmod(index, GRADES.size())
	for bolt in recovered.duplicate():
		if bolt.grade == GRADES[grade_index] and rounds.size() < CAPACITY:
			recovered.erase(bolt)
			rounds.append(bolt)
	replenish()

func replenish() -> void:
	while rounds.size() < CAPACITY:
		rounds.append(system.create_round(GRADES[grade_index]))

func aim_feedback(camera: Camera3D, actor: PhysicsBody3D) -> Dictionary:
	var origin := camera.global_position
	var direction := -camera.global_basis.z
	if removing:
		var bolt := system.target_bolt(origin, direction, RANGE, actor)
		return {"issue": "NO INTACT FASTENER TARGETED"} if bolt == null else {
			"a": bolt.a, "b": bolt.b, "issue": "", "bolt": bolt,
		}
	return system.probe(origin, direction, RANGE, actor)

func use(camera: Camera3D, actor: PhysicsBody3D) -> String:
	if removing:
		system.reconcile()
		var target := system.target_bolt(camera.global_position, -camera.global_basis.z, RANGE, actor)
		if not system.remove(target):
			return "NO INTACT FASTENER TARGETED"
		if target.grade == GRADES[grade_index] and rounds.size() < CAPACITY:
			rounds.append(target)
		else:
			recovered.append(target)
		if removal_behavior == "Timed":
			removal_remaining = removal_seconds
		return "RECOVERED %s #%d" % [target.grade.title, target.id]
	if rounds.is_empty():
		return "MAGAZINE EMPTY"
	var bolt := rounds.back() as InstalledFastener
	var issue := system.install(bolt, camera.global_position, -camera.global_basis.z, RANGE, actor)
	if not issue.is_empty():
		return issue
	rounds.pop_back()
	return "INSTALLED %s #%d" % [bolt.grade.title, bolt.id]

func hud_text() -> String:
	return "UNI-BOLT™  |  %s  |  %s  |  %d/%d  ·  %d IN RESERVE" % [
		"REMOVE" if removing else "INSTALL", GRADES[grade_index].title.to_upper(), rounds.size(), CAPACITY, recovered.size()]

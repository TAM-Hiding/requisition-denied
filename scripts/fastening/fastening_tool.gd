class_name FasteningTool
extends InteractableObject

const CAPACITY := 20
const RANGE := 3.0
const GRADES: Array[FastenerGrade] = [
	preload("res://data/fasteners/standard.tres"),
	preload("res://data/fasteners/grade_8.tres"),
	preload("res://data/fasteners/megabolt.tres"),
]
var system: FasteningSystem
var removing := false
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

func use(camera: Camera3D, actor: PhysicsBody3D) -> String:
	if removing:
		var target := system.target_bolt(camera.global_position, -camera.global_basis.z, RANGE, actor)
		if not system.remove(target):
			return "NO INTACT FASTENER TARGETED"
		if target.grade == GRADES[grade_index] and rounds.size() < CAPACITY:
			rounds.append(target)
		else:
			recovered.append(target)
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

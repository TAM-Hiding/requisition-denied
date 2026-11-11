class_name BarrierController
extends Node
## All configured inputs must be available and active to open.
@export var inputs: Array[EnvironmentalSignal] = []
@export var actuator: PoweredBarrier
var input_active := false

func _ready() -> void:
	connect_inputs(inputs)

func connect_inputs(sources: Array[EnvironmentalSignal]) -> void:
	for source in inputs:
		if not is_instance_valid(source):
			continue
		if source.output_changed.is_connected(_on_output):
			source.output_changed.disconnect(_on_output)
			source.tree_exiting.disconnect(_on_source_exiting.bind(source))
	inputs = sources.duplicate()
	for source in inputs:
		if is_instance_valid(source) and not source.output_changed.is_connected(_on_output):
			source.output_changed.connect(_on_output)
			source.tree_exiting.connect(_on_source_exiting.bind(source))
	_refresh()

func _on_output(_active: bool) -> void:
	_refresh()

func _on_source_exiting(source: EnvironmentalSignal) -> void:
	source.output_changed.disconnect(_on_output)
	source.tree_exiting.disconnect(_on_source_exiting.bind(source))
	# Preserve the missing input slot so an AND receiver cannot fail open.
	for index in inputs.size():
		if inputs[index] == source:
			inputs[index] = null
	_refresh()

func _refresh() -> void:
	input_active = not inputs.is_empty()
	for source in inputs:
		if not is_instance_valid(source) or not source.is_inside_tree() or not source.is_active():
			input_active = false
			break
	if is_instance_valid(actuator):
		actuator.request_open(input_active)

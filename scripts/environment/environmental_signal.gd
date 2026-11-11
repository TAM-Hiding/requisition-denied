class_name EnvironmentalSignal
extends Node

signal output_changed(active: bool)
@export var source_id: StringName
@export var initial_output := false
var _output := false
var _initialized := false

func is_active() -> bool:
	return _output if _initialized else initial_output

func set_output(active: bool) -> void:
	var changed := active != is_active()
	_output = active
	_initialized = true
	if changed:
		output_changed.emit(active)

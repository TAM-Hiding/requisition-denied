class_name PowerSourceDefinition
extends Resource

enum Stage { NONE, BASIC, WORKSHOP, INDUSTRIAL }
@export var stage := Stage.BASIC

func can_supply(consumer: PowerConsumerDefinition, available: bool) -> bool:
	return available and consumer != null and stage > Stage.NONE and stage >= consumer.required_stage

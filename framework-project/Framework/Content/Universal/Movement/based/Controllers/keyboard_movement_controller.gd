extends "res://Framework/Content/Universal/Movement/based/Controllers/movement_controller.gd"

const Rules = preload("res://Framework/Content/Universal/Movement/based/Controllers/controller_rules.gd")
const DIRECTIONS := Rules.DIRECTIONS

@export var actions: Dictionary = {}


func sample_intent(read_input: Callable, _observe_target: Callable) -> Dictionary:
	return Rules.keyboard_intent(actions, read_input)


func to_definition() -> Dictionary:
	return {"kind": "keyboard", "actions": actions.duplicate(true)}


func validation_error() -> String:
	return Rules.keyboard_error(actions)

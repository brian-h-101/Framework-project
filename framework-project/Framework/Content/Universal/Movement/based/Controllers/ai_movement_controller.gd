extends "res://Framework/Content/Universal/Movement/based/Controllers/movement_controller.gd"

const Rules = preload("res://Framework/Content/Universal/Movement/based/Controllers/controller_rules.gd")

@export_enum("nearest", "selected") var targeting: String = "nearest"
@export var stopping_distance: float = 48.0
@export_enum("pixels", "gameplay_units") var distance_unit: String = "pixels"


func sample_intent(_read_input: Callable, observe_target: Callable) -> Dictionary:
	return Rules.ai_intent(observe_target, StringName(targeting), distance_unit, stopping_distance)


func to_definition() -> Dictionary:
	return {"kind": "ai", "targeting": targeting, "stopping_distance": stopping_distance, "distance_unit": distance_unit}


func validation_error() -> String:
	return Rules.ai_error(targeting, distance_unit, stopping_distance)

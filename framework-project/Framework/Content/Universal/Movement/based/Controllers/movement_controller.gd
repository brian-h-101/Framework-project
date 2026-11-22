extends "res://Framework/Env/Configuration/Resources/Shared/configuration_resource.gd"

const Intent = preload("res://Framework/Content/Universal/Movement/based/Contracts/movement_intent.gd")


func sample_intent(_read_input: Callable, _observe_target: Callable) -> Dictionary:
	return Intent.axes()


func validation_error() -> String:
	return "Choose a concrete movement controller."

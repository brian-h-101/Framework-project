extends "res://Framework/Env/Configuration/Resources/Shared/configuration_resource.gd"

@export var bindings: Array[Dictionary] = []


func to_definition() -> Dictionary[StringName, Dictionary]:
	return named_entries(bindings, "action")


func validation_error() -> String:
	var error := entry_error(bindings, "action")
	if not error.is_empty():
		return error
	for binding in bindings:
		if not binding.get("keys") is Array:
			return "Input bindings require nonempty action names and key arrays."
		for key in binding["keys"]:
			if not key is int or key <= 0:
				return "Input key codes must be positive integers."
		for field in ["interaction", "targeting", "command", "behavior_event"]:
			if binding.has(field) and (not is_text(binding[field]) or String(binding[field]).is_empty()):
				return "Input %s must be nonempty text." % field
	return ""

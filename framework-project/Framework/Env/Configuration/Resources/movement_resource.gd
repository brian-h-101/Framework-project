extends "res://Framework/Env/Configuration/Resources/configuration_resource.gd"

@export var actions: Dictionary = {}
@export var speed_container: StringName = &""
@export var speed_path: Array[String] = []
@export var pixels_per_unit: float = 0.0


func to_definition() -> Dictionary:
	return {
		"actions": actions.duplicate(true),
		"speed": {
			"container": speed_container,
			"path": speed_path.duplicate(),
			"pixels_per_unit": pixels_per_unit,
		},
	}


func validation_error() -> String:
	for direction in ["left", "right", "up", "down"]:
		if not is_text(actions.get(direction)) or String(actions[direction]).is_empty():
			return "Movement requires a nonempty %s action." % direction
	if not is_finite(pixels_per_unit) or pixels_per_unit <= 0.0:
		return "Pixels per speed unit must be positive and finite."
	return attribute_error(to_definition()["speed"])

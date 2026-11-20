extends "res://Framework/Env/Configuration/Resources/configuration_resource.gd"

@export var seconds_per_day: float = 0.0
@export var starting_hour: float = 0.0


func to_definition() -> Dictionary:
	return {"seconds_per_day": seconds_per_day, "starting_hour": starting_hour}


func validation_error() -> String:
	if not is_finite(seconds_per_day) or seconds_per_day <= 0.0:
		return "Seconds per day must be positive and finite."
	if not is_finite(starting_hour) or starting_hour < 0.0 or starting_hour >= 24.0:
		return "Starting hour must be finite and between 0 (inclusive) and 24 (exclusive)."
	return ""

extends RefCounted


func observe_target(_mode: StringName, _distance_unit: String) -> Dictionary:
	return {}


func apply_movement(_desired: Dictionary, _delta: float) -> String:
	return "The movement environment has no driver."


func stop() -> void:
	pass

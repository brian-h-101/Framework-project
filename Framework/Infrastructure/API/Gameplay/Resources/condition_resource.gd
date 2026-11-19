extends Resource

@export var id: StringName = &""
@export var requirement: Dictionary = {}


func to_definition() -> Dictionary:
	return requirement.duplicate(true)
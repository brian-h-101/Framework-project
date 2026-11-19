extends Resource

@export var id: StringName = &""
@export var effects: Array[Dictionary] = []


func to_definition() -> Dictionary:
	return {
		"id": id,
		"effects": effects.duplicate(true),
	}
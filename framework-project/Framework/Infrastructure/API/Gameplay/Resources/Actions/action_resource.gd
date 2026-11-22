extends Resource

@export var id: StringName = &""
@export var behavior_id: StringName = &"attribute_effects"
@export var effects: Array[Dictionary] = []


func to_definition() -> Dictionary:
	return {
		"id": id,
		"behavior_id": behavior_id,
		"effects": effects.duplicate(true),
	}

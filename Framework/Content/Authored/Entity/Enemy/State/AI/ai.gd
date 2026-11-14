extends RefCounted

# Example initial ai data for the enemy template.

static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"ai": {
			"controller": "scripted",
			"behavior_profile": "guard",
			"aggro_range": 4,
			"target_entity_id": 0,
		},
	}

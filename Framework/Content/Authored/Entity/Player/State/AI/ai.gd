extends RefCounted

# Example initial ai data for the player template.

static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"ai": {
			"controller": "player",
			"behavior_profile": "manual",
			"aggro_range": 0,
			"target_entity_id": 0,
		},
	}

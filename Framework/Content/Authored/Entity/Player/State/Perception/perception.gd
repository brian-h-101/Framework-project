extends RefCounted

# Example initial perception data for the player template.

static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"perception": {
			"sight_range": 8,
			"hearing_range": 5,
			"concealment": 10,
			"awareness": 30,
			"visible_entity_ids": [],
		},
	}

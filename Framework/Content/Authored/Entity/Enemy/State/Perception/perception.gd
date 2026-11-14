extends RefCounted

# Example initial perception data for the enemy template.

static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"perception": {
			"sight_range": 6,
			"hearing_range": 7,
			"concealment": 30,
			"awareness": 50,
			"visible_entity_ids": [],
		},
	}

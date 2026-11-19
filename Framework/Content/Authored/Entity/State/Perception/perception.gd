extends RefCounted


static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"perception": {
			"awareness": 0,
			"concealment": 0,
			"hearing_range": 0,
			"sight_range": 0,
			"visible_entity_ids": []
		}
	}

extends RefCounted


static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"ai": {
			"aggro_range": 0,
			"behavior_profile": "",
			"controller": "",
			"target_entity_id": 0
		}
	}

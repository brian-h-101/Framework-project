extends RefCounted


static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"hunting": {
			"active": false,
			"last_attempt_tick": 0,
			"preferred_region_ids": [],
			"target_species": "",
			"tracks_found": 0
		}
	}

extends RefCounted

# Example initial hunting data for the player template.

static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"hunting": {
			"active": false,
			"target_species": "game_animal",
			"tracks_found": 0,
			"preferred_region_ids": [
				"woodland",
			],
			"last_attempt_tick": -1,
		},
	}

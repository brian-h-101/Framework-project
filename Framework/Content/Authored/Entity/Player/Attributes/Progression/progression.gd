extends RefCounted

# Example initial progression data for the player template.

static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"progression": {
			"level": 1,
			"experience": 0,
			"next_level_experience": 100,
			"unspent_points": 3,
		},
	}

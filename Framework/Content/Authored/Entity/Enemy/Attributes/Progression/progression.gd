extends RefCounted

# Example initial progression data for the enemy template.

static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"progression": {
			"level": 2,
			"experience": 40,
			"next_level_experience": 200,
			"unspent_points": 0,
		},
	}

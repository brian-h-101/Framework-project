extends RefCounted


static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"progression": {
			"experience": 0,
			"level": 0,
			"next_level_experience": 0,
			"unspent_points": 0
		}
	}

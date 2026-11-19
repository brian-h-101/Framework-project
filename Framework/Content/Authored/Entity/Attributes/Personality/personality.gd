extends RefCounted


static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"personality": {
			"aggression": 0,
			"courage": 0,
			"curiosity": 0,
			"empathy": 0
		}
	}

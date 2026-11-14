extends RefCounted

# Example initial personality data for the enemy template.

static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"personality": {
			"courage": 55,
			"empathy": 20,
			"curiosity": 30,
			"aggression": 75,
		},
	}

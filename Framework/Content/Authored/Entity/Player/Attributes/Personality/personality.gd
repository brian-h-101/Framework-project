extends RefCounted

# Example initial personality data for the player template.

static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"personality": {
			"courage": 65,
			"empathy": 70,
			"curiosity": 80,
			"aggression": 20,
		},
	}

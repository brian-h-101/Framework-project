extends RefCounted

# Example initial skills data for the player template.

static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"skills": {
			"survival": {
				"rank": 2,
				"experience": 25,
			},
			"medicine": {
				"rank": 1,
				"experience": 0,
			},
			"stealth": {
				"rank": 1,
				"experience": 10,
			},
		},
	}

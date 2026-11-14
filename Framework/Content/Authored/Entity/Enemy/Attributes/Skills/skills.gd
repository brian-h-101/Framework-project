extends RefCounted

# Example initial skills data for the enemy template.

static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"skills": {
			"survival": {
				"rank": 3,
				"experience": 25,
			},
			"medicine": {
				"rank": 1,
				"experience": 0,
			},
			"stealth": {
				"rank": 3,
				"experience": 10,
			},
		},
	}

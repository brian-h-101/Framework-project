extends RefCounted


static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"skills": {
			"medicine": {
				"experience": 0,
				"rank": 0
			},
			"stealth": {
				"experience": 0,
				"rank": 0
			},
			"survival": {
				"experience": 0,
				"rank": 0
			}
		}
	}

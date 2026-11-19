extends RefCounted


static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"needs": {
			"fatigue": {
				"current": 0,
				"maximum": 100
			},
			"hunger": {
				"current": 0,
				"maximum": 100
			},
			"thirst": {
				"current": 0,
				"maximum": 100
			}
		}
	}

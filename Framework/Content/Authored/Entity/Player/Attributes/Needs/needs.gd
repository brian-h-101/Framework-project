extends RefCounted

# Example initial needs data for the player template.

static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"needs": {
			"hunger": {
				"current": 10,
				"maximum": 100,
			},
			"thirst": {
				"current": 5,
				"maximum": 100,
			},
			"fatigue": {
				"current": 15,
				"maximum": 100,
			},
		},
	}

extends RefCounted

# Example initial needs data for the enemy template.

static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"needs": {
			"hunger": {
				"current": 30,
				"maximum": 100,
			},
			"thirst": {
				"current": 20,
				"maximum": 100,
			},
			"fatigue": {
				"current": 25,
				"maximum": 100,
			},
		},
	}

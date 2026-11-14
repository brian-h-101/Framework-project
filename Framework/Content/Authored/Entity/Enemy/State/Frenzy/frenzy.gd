extends RefCounted

# Example initial frenzy data for the enemy template.

static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"frenzy": {
			"active": false,
			"intensity": 0,
			"threshold": 100,
			"recovery_per_tick": 5,
		},
	}

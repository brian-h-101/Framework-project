extends RefCounted


static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"frenzy": {
			"active": false,
			"intensity": 0,
			"recovery_per_tick": 0,
			"threshold": 0
		}
	}

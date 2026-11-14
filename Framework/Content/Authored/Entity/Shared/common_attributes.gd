extends RefCounted


static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"health": {
			"current": 100,
			"maximum": 100,
		},
		&"speed": {
			"current": 20,
			"maximum": 50,
		},
	}
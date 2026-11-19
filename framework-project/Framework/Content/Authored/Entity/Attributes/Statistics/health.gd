extends RefCounted


static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"health": {
			"current": 100,
			"maximum": 100,
		},
	}

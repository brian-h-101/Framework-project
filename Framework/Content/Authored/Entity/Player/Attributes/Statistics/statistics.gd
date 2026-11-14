extends RefCounted


static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"health": {
			"current": 150,
			"maximum": 150,
		},
	}

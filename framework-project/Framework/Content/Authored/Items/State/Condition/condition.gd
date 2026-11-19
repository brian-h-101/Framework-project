extends RefCounted


static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"condition": {
			"current": 100,
			"maximum": 100,
		},
	}

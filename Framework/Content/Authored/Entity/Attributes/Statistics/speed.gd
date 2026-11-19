extends RefCounted


static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"speed": {
			"current": 20,
			"maximum": 50,
		},
	}

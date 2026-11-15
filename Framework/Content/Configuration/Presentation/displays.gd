extends RefCounted


static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"health": {
			"container": &"health",
			"path": ["current"],
			"format": "Health: %s",
		},
	}
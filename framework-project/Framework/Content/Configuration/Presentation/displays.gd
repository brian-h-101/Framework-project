extends RefCounted


static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"name": {
			"container": &"identity",
			"path": ["name"],
			"format": "%s",
		},
		&"health": {
			"container": &"health",
			"path": ["current"],
			"format": "Health: %s",
			"optional": true,
		},
	}
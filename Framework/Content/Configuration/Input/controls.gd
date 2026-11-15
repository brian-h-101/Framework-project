extends RefCounted


static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"primary_interaction": {
			"keys": [KEY_SPACE],
			"interaction": &"strike",
		},
	}
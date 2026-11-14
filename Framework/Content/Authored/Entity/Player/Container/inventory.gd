extends RefCounted


static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"inventory": {
			"capacity": 10,
			"items": {},
		},
	}

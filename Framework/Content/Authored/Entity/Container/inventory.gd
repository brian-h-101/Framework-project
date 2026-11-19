extends RefCounted


static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"inventory": {
			"capacity": 0,
			"items": {}
		}
	}

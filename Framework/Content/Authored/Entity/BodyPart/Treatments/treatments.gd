extends RefCounted


static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"treatments": {
			"active": [],
			"known": {}
		}
	}

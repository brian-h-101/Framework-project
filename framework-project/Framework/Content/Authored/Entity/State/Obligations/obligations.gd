extends RefCounted


static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"obligations": {
			"entries": [],
			"last_completed_tick": 0
		}
	}

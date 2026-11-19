extends RefCounted


static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"illness": {
			"active": [],
			"history": [],
			"immunities": []
		}
	}

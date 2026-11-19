extends RefCounted


static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"status_effects": {
			"active": []
		}
	}

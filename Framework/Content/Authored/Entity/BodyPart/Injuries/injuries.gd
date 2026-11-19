extends RefCounted


static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"injuries": {
			"active": [],
			"healed_ids": []
		}
	}

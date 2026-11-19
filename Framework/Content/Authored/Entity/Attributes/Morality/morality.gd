extends RefCounted


static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"morality": {
			"compassion": 0,
			"degeneration": 0,
			"integrity": 0,
			"outlook": ""
		}
	}

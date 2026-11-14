extends RefCounted

# Example initial morality data for the player template.

static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"morality": {
			"outlook": "compassionate",
			"compassion": 75,
			"integrity": 70,
			"degeneration": 0,
		},
	}

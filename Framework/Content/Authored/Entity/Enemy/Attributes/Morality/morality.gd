extends RefCounted

# Example initial morality data for the enemy template.

static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"morality": {
			"outlook": "self_serving",
			"compassion": 20,
			"integrity": 30,
			"degeneration": 10,
		},
	}

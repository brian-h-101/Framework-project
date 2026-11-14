extends RefCounted

# Example initial reputation data for the enemy template.

static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"reputation": {
			"standings": {
				"village": -10,
				"outpost": 10,
			},
		},
	}

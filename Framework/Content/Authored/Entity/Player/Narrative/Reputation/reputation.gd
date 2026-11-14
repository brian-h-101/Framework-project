extends RefCounted

# Example initial reputation data for the player template.

static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"reputation": {
			"standings": {
				"village": 0,
				"outpost": -5,
			},
		},
	}

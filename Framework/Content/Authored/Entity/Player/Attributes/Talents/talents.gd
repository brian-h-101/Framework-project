extends RefCounted

# Example initial talents data for the player template.

static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"talents": {
			"known": [
				"observant",
			],
			"ranks": {
				"observant": 1,
			},
			"unspent_points": 1,
		},
	}

extends RefCounted

# Example initial talents data for the enemy template.

static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"talents": {
			"known": [
				"ambusher",
			],
			"ranks": {
				"ambusher": 1,
			},
			"unspent_points": 0,
		},
	}

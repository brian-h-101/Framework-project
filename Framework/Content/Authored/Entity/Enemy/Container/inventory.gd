extends RefCounted

# Example initial inventory data for the enemy template.

static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"inventory": {
			"capacity": 6,
			"items": {
				"ration": 1,
				"cloth": 2,
			},
		},
	}

extends RefCounted

# Example initial factions data for the enemy template.

static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"factions": {
			"memberships": {
				"raiders": {
					"rank": "scout",
					"standing": 10,
				},
			},
		},
	}

extends RefCounted

# Example initial factions data for the player template.

static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"factions": {
			"memberships": {
				"villagers": {
					"rank": "outsider",
					"standing": 5,
				},
			},
		},
	}

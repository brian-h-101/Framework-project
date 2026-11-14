extends RefCounted

# Example initial illness data for the player template.

static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"illness": {
			"active": [],
			"history": [
				{
					"id": "winter_cold",
					"recovered": true,
				},
			],
			"immunities": [],
		},
	}

extends RefCounted

# Example initial crime data for the player template.

static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"crime": {
			"offenses": [],
			"bounty": 0,
			"wanted": false,
			"jurisdiction_id": "village",
		},
	}

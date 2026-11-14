extends RefCounted

# Example initial supernatural data for the enemy template.

static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"supernatural": {
			"origin": "mortal",
			"traits": [],
			"resource": {
				"id": "none",
				"current": 0,
				"maximum": 0,
			},
		},
	}

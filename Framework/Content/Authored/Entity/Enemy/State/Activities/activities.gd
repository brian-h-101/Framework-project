extends RefCounted

# Example initial activities data for the enemy template.

static func defaults() -> Dictionary[StringName, Dictionary]:
	return {
		&"activity": {
			"current": "guarding",
			"progress": 0,
			"started_tick": 0,
			"interrupted": false,
		},
	}
